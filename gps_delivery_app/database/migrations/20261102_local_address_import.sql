-- Explicit, previewed address import only. No identities, orders or money import.
begin;
create table if not exists public.delivery_cloud_imports (
  user_id uuid not null references public.delivery_cloud_accounts(user_id),
  source_key text not null check(source_key ~ '^[a-f0-9]{64}$'),
  address_id uuid references public.delivery_cloud_addresses(id) on delete set null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key(user_id,source_key)
);
alter table public.delivery_cloud_imports enable row level security;
revoke all on public.delivery_cloud_imports from public,anon,authenticated;

create or replace function public.delivery_cloud_import(p_action text,p_items jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_accounts; item jsonb; d jsonb; rows jsonb:='[]'; report jsonb; status text; problem text;
  existing public.delivery_cloud_imports; matched uuid; saved uuid; count_ready integer:=0; current_count integer;
  key text; keys text[]:='{}';
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid() for update;
  if a.user_id is null or a.blocked then raise sqlstate 'PT403' using message='Cần tài khoản đang hoạt động.'; end if;
  if p_action is null or p_action not in ('preview','commit') or jsonb_typeof(p_items) is distinct from 'array' or
    octet_length(p_items::text)>50000 then raise sqlstate 'PT400' using message='Yêu cầu nhập dữ liệu không hợp lệ.'; end if;
  if jsonb_array_length(p_items) not between 1 and 25 then raise sqlstate 'PT400' using message='Chọn từ 1 đến 25 địa chỉ.'; end if;
  select count(*) into current_count from public.delivery_cloud_addresses where user_id=auth.uid();
  for item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(item) is distinct from 'object' or item-array['source_key','details']<>'{}'::jsonb or
      coalesce(item->>'source_key','') !~ '^[a-f0-9]{64}$' or (item->>'source_key')=any(keys) then
      raise sqlstate 'PT400' using message='Mã bản ghi nguồn không hợp lệ hoặc bị trùng.';
    end if;
    key:=item->>'source_key'; keys:=array_append(keys,key); d:=item->'details'; status:='ready'; problem:=''; matched:=null;
    if jsonb_typeof(d) is distinct from 'object' or d-array['label','recipient_name','recipient_phone','full_address','latitude','longitude']<>'{}'::jsonb or
      jsonb_typeof(d->'label') is distinct from 'string' or jsonb_typeof(d->'recipient_name') is distinct from 'string' or
      jsonb_typeof(d->'recipient_phone') is distinct from 'string' or jsonb_typeof(d->'full_address') is distinct from 'string' or
      jsonb_typeof(d->'latitude') is distinct from 'number' or jsonb_typeof(d->'longitude') is distinct from 'number' then
      status:='invalid'; problem:='Thiếu thông tin địa chỉ hoặc tọa độ.';
    else
      d:=jsonb_build_object('label',btrim(d->>'label'),'recipient_name',btrim(d->>'recipient_name'),
        'recipient_phone',btrim(d->>'recipient_phone'),'full_address',btrim(d->>'full_address'),
        'latitude',d->'latitude','longitude',d->'longitude');
      if length(d->>'label') not between 1 and 60 or length(d->>'recipient_name') not between 1 and 120 or
        d->>'recipient_phone' !~ '^0[35789][0-9]{8}$' or length(d->>'full_address') not between 5 and 500 or
        (d->>'latitude')::numeric not between -90 and 90 or (d->>'longitude')::numeric not between -180 and 180 then
        status:='invalid'; problem:='Tên, số điện thoại, địa chỉ hoặc tọa độ cần sửa.';
      end if;
    end if;
    if status='ready' then
      select * into existing from public.delivery_cloud_imports where user_id=auth.uid() and source_key=key;
      if found then
        if existing.payload=d then status:='imported'; matched:=existing.address_id;
          if matched is null then problem:='Đã nhập trước đây; địa chỉ sau đó đã bị xóa.'; end if;
        else status:='conflict'; problem:='Bản ghi nguồn đã nhập với nội dung khác.'; end if;
      else
        select id into matched from public.delivery_cloud_addresses where user_id=auth.uid()
          and lower(btrim(full_address))=lower(d->>'full_address') and recipient_phone=d->>'recipient_phone'
          and abs(latitude-(d->>'latitude')::double precision)<0.00001 and abs(longitude-(d->>'longitude')::double precision)<0.00001
          order by id limit 1;
        if matched is not null then status:='duplicate'; problem:='Địa chỉ đã có trong tài khoản.'; end if;
      end if;
    end if;
    if status='ready' then
      -- Also find duplicates in the submitted batch before writing anything.
      if exists(select 1 from jsonb_array_elements(rows) r where r->>'status' in ('ready','duplicate','imported')
        and lower(r->'details'->>'full_address')=lower(d->>'full_address') and r->'details'->>'recipient_phone'=d->>'recipient_phone'
        and abs((r->'details'->>'latitude')::numeric-(d->>'latitude')::numeric)<0.00001
        and abs((r->'details'->>'longitude')::numeric-(d->>'longitude')::numeric)<0.00001) then
        status:='duplicate'; problem:='Địa chỉ trùng trong danh sách đã chọn.';
      else count_ready:=count_ready+1; end if;
    end if;
    rows:=rows||jsonb_build_array(jsonb_build_object('source_key',key,'details',d,'status',status,'problem',problem,'address_id',matched));
  end loop;
  if count_ready+current_count>25 then
    raise sqlstate 'PT409' using message='Vượt giới hạn 25 địa chỉ. Bỏ chọn bớt rồi xem lại.';
  end if;
  if p_action='commit' then
    if exists(select 1 from jsonb_array_elements(rows) r where r->>'status' in ('invalid','conflict')) then
      raise sqlstate 'PT409' using message='Cần xử lý bản ghi lỗi trước khi nhập. Chưa có địa chỉ nào được ghi.';
    end if;
    for report in select value from jsonb_array_elements(rows) where value->>'status'='ready' loop
      saved:=gen_random_uuid();
      perform public.delivery_cloud_addresses_manage(saved,(report->'details')||jsonb_build_object('is_default',false));
      insert into public.delivery_cloud_imports(user_id,source_key,address_id,payload)
        values(auth.uid(),report->>'source_key',saved,report->'details');
    end loop;
    if count_ready>0 then insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value)
      values(auth.uid(),'local_address_import',auth.uid(),jsonb_build_object('imported',count_ready,'selected',jsonb_array_length(p_items)));
    end if;
  end if;
  return jsonb_build_object('rows',rows,'ready',count_ready,'committed',p_action='commit');
end; $$;
revoke all on function public.delivery_cloud_import(text,jsonb) from public,anon;
grant execute on function public.delivery_cloud_import(text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
