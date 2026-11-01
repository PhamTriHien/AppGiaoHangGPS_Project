begin;

create table if not exists public.delivery_cloud_addresses (
  id uuid primary key,
  user_id uuid not null references public.delivery_cloud_accounts(user_id) on delete cascade,
  label text not null check(length(label) between 1 and 60),
  recipient_name text not null check(length(recipient_name) between 1 and 120),
  recipient_phone text not null check(recipient_phone ~ '^0[35789][0-9]{8}$'),
  full_address text not null check(length(full_address) between 5 and 500),
  latitude double precision not null check(latitude between -90 and 90),
  longitude double precision not null check(longitude between -180 and 180),
  is_default boolean not null default false,
  version integer not null default 1 check(version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_cloud_addresses_owner on public.delivery_cloud_addresses(user_id);
create unique index if not exists delivery_cloud_addresses_one_default
  on public.delivery_cloud_addresses(user_id) where is_default;
alter table public.delivery_cloud_addresses enable row level security;
revoke all on public.delivery_cloud_addresses from public, anon, authenticated;
grant select on public.delivery_cloud_addresses to authenticated;
drop policy if exists cloud_address_read on public.delivery_cloud_addresses;
create policy cloud_address_read on public.delivery_cloud_addresses for select to authenticated
  using(user_id=auth.uid() and public.delivery_cloud_active());

create or replace function public.delivery_cloud_addresses_manage(
  p_id uuid default null, p_details jsonb default null,
  p_delete boolean default false, p_version integer default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  account public.delivery_cloud_accounts;
  previous public.delivery_cloud_addresses;
  normalized jsonb;
  wanted_default boolean;
  item_count integer;
  result jsonb;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  -- Serialize edits for one account, including first/default address selection.
  select * into account from public.delivery_cloud_accounts where user_id=auth.uid() for update;
  if account.user_id is null or account.blocked then
    raise sqlstate 'PT403' using message='Cần hồ sơ tài khoản đang hoạt động.';
  end if;
  if p_delete is null or (p_id is null and (p_details is not null or p_delete or p_version is not null)) then
    raise sqlstate 'PT400' using message='Thao tác địa chỉ không hợp lệ.';
  end if;
  if p_id is not null then
    select * into previous from public.delivery_cloud_addresses where id=p_id and user_id=auth.uid();
    if p_delete then
      if p_details is not null or p_version is null or p_version < 1 then
        raise sqlstate 'PT400' using message='Cần phiên bản địa chỉ để xóa.';
      end if;
      if previous.id is not null then
        if previous.version<>p_version then raise sqlstate 'PT409' using message='Địa chỉ đã thay đổi. Hãy tải lại.'; end if;
        delete from public.delivery_cloud_addresses where id=p_id and user_id=auth.uid();
        if previous.is_default then
          update public.delivery_cloud_addresses set is_default=true,version=version+1,updated_at=now()
          where id=(select id from public.delivery_cloud_addresses where user_id=auth.uid() order by created_at,id limit 1);
        end if;
      end if;
    else
      if p_details is null or jsonb_typeof(p_details)<>'object' then
        raise sqlstate 'PT400' using message='Thông tin địa chỉ không hợp lệ.';
      end if;
      if exists(select 1 from jsonb_object_keys(p_details) k where k not in
        ('label','recipient_name','recipient_phone','full_address','latitude','longitude','is_default')) or
        jsonb_typeof(p_details->'label') is distinct from 'string' or
        jsonb_typeof(p_details->'recipient_name') is distinct from 'string' or
        jsonb_typeof(p_details->'recipient_phone') is distinct from 'string' or
        jsonb_typeof(p_details->'full_address') is distinct from 'string' or
        jsonb_typeof(p_details->'latitude') is distinct from 'number' or
        jsonb_typeof(p_details->'longitude') is distinct from 'number' or
        jsonb_typeof(p_details->'is_default') is distinct from 'boolean' then
        raise sqlstate 'PT400' using message='Thông tin địa chỉ không hợp lệ.';
      end if;
      normalized:=jsonb_build_object(
        'label',btrim(p_details->>'label'), 'recipient_name',btrim(p_details->>'recipient_name'),
        'recipient_phone',btrim(p_details->>'recipient_phone'), 'full_address',btrim(p_details->>'full_address'),
        'latitude',p_details->'latitude', 'longitude',p_details->'longitude', 'is_default',p_details->'is_default');
      if length(normalized->>'label') not between 1 and 60 or
        length(normalized->>'recipient_name') not between 1 and 120 or
        normalized->>'recipient_phone' !~ '^0[35789][0-9]{8}$' or
        length(normalized->>'full_address') not between 5 and 500 or
        (normalized->>'latitude')::numeric not between -90 and 90 or
        (normalized->>'longitude')::numeric not between -180 and 180 then
        raise sqlstate 'PT400' using message='Tên, số điện thoại, địa chỉ hoặc tọa độ không hợp lệ.';
      end if;
      select count(*) into item_count from public.delivery_cloud_addresses where user_id=auth.uid();
      wanted_default:=(normalized->>'is_default')::boolean or item_count=0 or coalesce(previous.is_default,false);
      if previous.id is not null then
        if p_version is null then
          -- Retrying creation with the same UUID must never duplicate or overwrite.
          if (to_jsonb(previous)-array['id','user_id','version','created_at','updated_at'])<>
            (normalized || jsonb_build_object('is_default',wanted_default)) then
            raise sqlstate 'PT409' using message='Mã địa chỉ đã được dùng. Hãy tải lại.';
          end if;
        else
          if p_version<1 or p_version<>previous.version then raise sqlstate 'PT409' using message='Địa chỉ đã thay đổi. Hãy tải lại.'; end if;
          wanted_default:=wanted_default or previous.is_default;
          if wanted_default then
            update public.delivery_cloud_addresses set is_default=false,version=version+1,updated_at=now()
            where user_id=auth.uid() and is_default and id<>p_id;
          end if;
          update public.delivery_cloud_addresses set label=normalized->>'label',recipient_name=normalized->>'recipient_name',
            recipient_phone=normalized->>'recipient_phone',full_address=normalized->>'full_address',
            latitude=(normalized->>'latitude')::double precision,longitude=(normalized->>'longitude')::double precision,
            is_default=wanted_default,version=version+1,updated_at=now()
            where id=p_id and user_id=auth.uid();
        end if;
      else
        if p_version is not null then raise sqlstate 'PT404' using message='Không tìm thấy địa chỉ.'; end if;
        if exists(select 1 from public.delivery_cloud_addresses where id=p_id) then
          raise sqlstate 'PT409' using message='Mã địa chỉ không khả dụng.';
        end if;
        if item_count>=25 then raise sqlstate 'PT409' using message='Mỗi tài khoản lưu tối đa 25 địa chỉ.'; end if;
        if wanted_default then
          update public.delivery_cloud_addresses set is_default=false,version=version+1,updated_at=now()
            where user_id=auth.uid() and is_default;
        end if;
        insert into public.delivery_cloud_addresses(id,user_id,label,recipient_name,recipient_phone,full_address,latitude,longitude,is_default)
          values(p_id,auth.uid(),normalized->>'label',normalized->>'recipient_name',normalized->>'recipient_phone',
            normalized->>'full_address',(normalized->>'latitude')::double precision,
            (normalized->>'longitude')::double precision,wanted_default);
      end if;
    end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(a)-'user_id' order by a.is_default desc,a.created_at,a.id),'[]'::jsonb)
    into result from public.delivery_cloud_addresses a where a.user_id=auth.uid();
  return jsonb_build_object('addresses',result);
end; $$;
revoke all on function public.delivery_cloud_addresses_manage(uuid,jsonb,boolean,integer) from public,anon;
grant execute on function public.delivery_cloud_addresses_manage(uuid,jsonb,boolean,integer) to authenticated;

commit;
