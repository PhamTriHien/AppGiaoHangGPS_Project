-- Additive cloud logistics: scheduled bulk pickups, recipient trust, delivery
-- instructions and delivery statistics derived from real cloud orders.
-- Safe to reapply; seeds no rows.
begin;

alter table public.delivery_cloud_orders
  add column if not exists delivery_instruction text not null default ''
    check(length(delivery_instruction)<=200);
create index if not exists cloud_orders_recipient_phone
  on public.delivery_cloud_orders((details->>'recipient_phone'));

create table if not exists public.delivery_cloud_pickups (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.delivery_cloud_accounts(user_id),
  request_key uuid not null,
  request_payload jsonb not null,
  -- Address book rows can change later; the pickup keeps the confirmed snapshot.
  address_id uuid not null,
  pickup_address text not null check(length(pickup_address) between 5 and 500),
  pickup_lat double precision not null check(pickup_lat between -90 and 90),
  pickup_lng double precision not null check(pickup_lng between -180 and 180),
  contact_name text not null check(length(contact_name) between 1 and 120),
  contact_phone text not null check(contact_phone ~ '^0[35789][0-9]{8}$'),
  vehicle_type text not null check(vehicle_type in ('tricycle_300kg','van_500kg','box_truck_1500kg')),
  pickup_date date not null,
  time_slot text not null check(time_slot in ('morning','afternoon','evening')),
  package_count integer not null check(package_count between 1 and 1000),
  total_weight_kg numeric(7,1) not null check(total_weight_kg>0 and total_weight_kg<=case vehicle_type
    when 'tricycle_300kg' then 300 when 'van_500kg' then 500 else 1500 end),
  note text not null default '' check(length(note)<=500),
  status text not null default 'requested' check(status in ('requested','assigned')),
  driver_id uuid references public.delivery_cloud_accounts(user_id),
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz,
  version integer not null default 1 check(version>0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(merchant_id,request_key),
  check((status='assigned')=(driver_id is not null))
);
create index if not exists cloud_pickups_merchant on public.delivery_cloud_pickups(merchant_id,created_at desc);
create index if not exists cloud_pickups_driver on public.delivery_cloud_pickups(driver_id,created_at desc) where driver_id is not null;

create table if not exists public.delivery_cloud_recipient_flags (
  owner_id uuid not null references public.delivery_cloud_accounts(user_id) on delete cascade,
  recipient_phone text not null check(recipient_phone ~ '^0[35789][0-9]{8}$'),
  created_at timestamptz not null default now(),
  primary key(owner_id,recipient_phone)
);

alter table public.delivery_cloud_pickups enable row level security;
alter table public.delivery_cloud_recipient_flags enable row level security;
revoke all on public.delivery_cloud_pickups, public.delivery_cloud_recipient_flags from public,anon,authenticated;

create or replace function public.delivery_cloud_logistics(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb:=coalesce(p_payload,'{}'::jsonb);
  uid uuid:=auth.uid();
  op boolean:=public.delivery_is_operator();
  addr public.delivery_cloud_addresses;
  pk public.delivery_cloud_pickups;
  o public.delivery_cloud_orders;
  local_now timestamp:=now() at time zone 'Asia/Ho_Chi_Minh';
  v_slot time; v_day date; v_packages numeric; v_weight numeric; v_driver uuid;
  v_phone text; v_delivered integer; v_failed integer; v_flagged boolean; v_score integer;
  v_instruction text; v_since timestamptz:=now()-interval '30 days'; v_result jsonb;
begin
  if uid is null then raise sqlstate 'PT401' using message='Cần đăng nhập cloud.'; end if;
  if not op and not public.delivery_cloud_active() then raise sqlstate 'PT403' using message='Cần hồ sơ cloud đang hoạt động.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>4000 then
    raise sqlstate 'PT400' using message='Yêu cầu vận hành không hợp lệ.';
  end if;

  if p_action='pickup_list' then
    return jsonb_build_object(
      'pickups',coalesce((select jsonb_agg(jsonb_build_object(
          'id',p.id,'merchant_id',p.merchant_id,'merchant_name',m.full_name,'address_id',p.address_id,
          'pickup_address',p.pickup_address,'pickup_lat',p.pickup_lat,'pickup_lng',p.pickup_lng,
          'contact_name',p.contact_name,'contact_phone',p.contact_phone,'vehicle_type',p.vehicle_type,
          'pickup_date',p.pickup_date,'time_slot',p.time_slot,'package_count',p.package_count,
          'total_weight_kg',p.total_weight_kg,'note',p.note,'status',p.status,'driver_id',p.driver_id,
          'driver_name',dr.full_name,'assigned_at',p.assigned_at,'version',p.version,'created_at',p.created_at)
          order by p.created_at desc,p.id desc)
        from (select * from public.delivery_cloud_pickups where op or uid in (merchant_id,driver_id)
          order by created_at desc,id desc limit 50) p
        join public.delivery_cloud_accounts m on m.user_id=p.merchant_id
        left join public.delivery_cloud_accounts dr on dr.user_id=p.driver_id),'[]'::jsonb),
      'drivers',case when op then coalesce((select jsonb_agg(jsonb_build_object('user_id',a.user_id,'full_name',a.full_name)
          order by a.full_name,a.user_id)
        from public.delivery_cloud_accounts a where public.delivery_cloud_has_membership(a.user_id,'driver')),'[]'::jsonb)
        else '[]'::jsonb end);

  elsif p_action='pickup_create' then
    if not public.delivery_cloud_has_membership(uid,'merchant') then
      raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
    end if;
    if d-array['request_key','address_id','vehicle_type','pickup_date','time_slot','package_count','total_weight_kg','note']<>'{}'::jsonb or
      jsonb_typeof(d->'request_key') is distinct from 'string' or jsonb_typeof(d->'address_id') is distinct from 'string' or
      jsonb_typeof(d->'package_count') is distinct from 'number' or jsonb_typeof(d->'total_weight_kg') is distinct from 'number' or
      (d ? 'note' and jsonb_typeof(d->'note') is distinct from 'string') or
      coalesce(d->>'pickup_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise sqlstate 'PT400' using message='Phiếu thu gom có trường không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('pickup:'||uid::text||(d->>'request_key'),0));
    select * into pk from public.delivery_cloud_pickups where merchant_id=uid and request_key=(d->>'request_key')::uuid;
    if found then
      if pk.request_payload<>d then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho nội dung khác.'; end if;
      return to_jsonb(pk)-'request_payload'-'request_key';
    end if;
    v_day:=(d->>'pickup_date')::date;
    v_slot:=case d->>'time_slot' when 'morning' then time '09:00' when 'afternoon' then time '14:00' when 'evening' then time '18:00' end;
    if v_slot is null or v_day+v_slot<=local_now or v_day>local_now::date+14 then
      raise sqlstate 'PT400' using message='Ngày và khung giờ thu gom phải chưa bắt đầu và trong 14 ngày tới.';
    end if;
    v_packages:=(d->>'package_count')::numeric;
    v_weight:=(d->>'total_weight_kg')::numeric;
    if v_packages<>trunc(v_packages) or v_packages not between 1 and 1000 or v_weight<=0 or v_weight<>round(v_weight,1) or
      v_weight>(case d->>'vehicle_type' when 'tricycle_300kg' then 300 when 'van_500kg' then 500 when 'box_truck_1500kg' then 1500 else 0 end) or
      length(btrim(coalesce(d->>'note','')))>500 then
      raise sqlstate 'PT400' using message='Số kiện, khối lượng hoặc loại xe không hợp lệ.';
    end if;
    select * into addr from public.delivery_cloud_addresses where id=(d->>'address_id')::uuid and user_id=uid;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy địa chỉ kho trong sổ địa chỉ.'; end if;
    insert into public.delivery_cloud_pickups(merchant_id,request_key,request_payload,address_id,pickup_address,pickup_lat,pickup_lng,
      contact_name,contact_phone,vehicle_type,pickup_date,time_slot,package_count,total_weight_kg,note)
    values(uid,(d->>'request_key')::uuid,d,addr.id,addr.full_address,addr.latitude,addr.longitude,addr.recipient_name,addr.recipient_phone,
      d->>'vehicle_type',v_day,d->>'time_slot',v_packages::integer,v_weight,btrim(coalesce(d->>'note','')))
    returning * into pk;
    return to_jsonb(pk)-'request_payload'-'request_key';

  elsif p_action='pickup_assign' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if d-array['id','version','driver_id']<>'{}'::jsonb or jsonb_typeof(d->'version') is distinct from 'number' or
      jsonb_typeof(d->'driver_id') is distinct from 'string' then
      raise sqlstate 'PT400' using message='Yêu cầu điều xe không hợp lệ.';
    end if;
    v_driver:=(d->>'driver_id')::uuid;
    select * into pk from public.delivery_cloud_pickups where id=(d->>'id')::uuid for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy phiếu thu gom.'; end if;
    if pk.version is distinct from (d->>'version')::numeric then raise sqlstate 'PT409' using message='Phiếu thu gom đã thay đổi. Vui lòng tải lại.'; end if;
    if pk.status<>'requested' then raise sqlstate 'PT409' using message='Phiếu thu gom đã được điều xe.'; end if;
    if not public.delivery_cloud_has_membership(v_driver,'driver') then
      raise sqlstate 'PT409' using message='Tài xế chưa được duyệt hoặc đang khóa.';
    end if;
    update public.delivery_cloud_pickups set status='assigned',driver_id=v_driver,assigned_by=uid,assigned_at=now(),
      version=version+1,updated_at=now() where id=pk.id returning * into pk;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value)
      values(uid,'pickup_assign',pk.id,jsonb_build_object('driver_id',pk.driver_id,'version',pk.version));
    return to_jsonb(pk)-'request_payload'-'request_key';

  elsif p_action in ('recipient_trust','recipient_flag') then
    v_phone:=d->>'phone';
    if coalesce(v_phone,'') !~ '^0[35789][0-9]{8}$' or d-array['phone','flagged']<>'{}'::jsonb or
      (p_action='recipient_flag' and jsonb_typeof(d->'flagged') is distinct from 'boolean') then
      raise sqlstate 'PT400' using message='Số điện thoại người nhận không hợp lệ.';
    end if;
    if p_action='recipient_flag' then
      if (d->>'flagged')::boolean then
        insert into public.delivery_cloud_recipient_flags(owner_id,recipient_phone) values(uid,v_phone) on conflict do nothing;
      else
        delete from public.delivery_cloud_recipient_flags where owner_id=uid and recipient_phone=v_phone;
      end if;
    end if;
    -- Only the caller's own shipments are counted, never another sender's history.
    -- Cancellation happens before pickup, so it is not attributed to the recipient.
    select count(*) filter(where status='delivered'),count(*) filter(where status in ('failed','returning','returned'))
      into v_delivered,v_failed from public.delivery_cloud_orders
      where details->>'recipient_phone'=v_phone and (owner_id=uid or merchant_id=uid);
    v_flagged:=exists(select 1 from public.delivery_cloud_recipient_flags where owner_id=uid and recipient_phone=v_phone);
    v_score:=greatest(15,least(99,88+v_delivered*4-v_failed*22-case when v_flagged then 45 else 0 end));
    return jsonb_build_object('phone',v_phone,'delivered',v_delivered,'failed_or_returned',v_failed,'flagged',v_flagged,'score',v_score,
      'tier',case when v_flagged or v_score<60 then 'high_risk' when v_score<80 then 'confirm' else 'trusted' end);

  elsif p_action='instruction_set' then
    if d-array['order_id','version','instruction']<>'{}'::jsonb or jsonb_typeof(d->'order_id') is distinct from 'string' or
      jsonb_typeof(d->'version') is distinct from 'number' or jsonb_typeof(d->'instruction') is distinct from 'string' or
      length(btrim(d->>'instruction'))>200 then
      raise sqlstate 'PT400' using message='Chỉ dẫn giao hàng không hợp lệ.';
    end if;
    v_instruction:=btrim(d->>'instruction');
    select * into o from public.delivery_cloud_orders where id=(d->>'order_id')::uuid for update;
    if not found or o.owner_id<>uid then raise sqlstate 'PT404' using message='Không tìm thấy đơn hàng được phép truy cập.'; end if;
    if o.version is distinct from (d->>'version')::numeric then raise sqlstate 'PT409' using message='Đơn đã thay đổi. Vui lòng tải lại.'; end if;
    if o.status not in ('searching','accepted','arrivingPickup','inTransit','failed') then
      raise sqlstate 'PT409' using message='Đơn đã kết thúc, không thể đổi chỉ dẫn giao hàng.';
    end if;
    if o.delivery_instruction<>v_instruction then
      update public.delivery_cloud_orders set delivery_instruction=v_instruction,version=version+1,updated_at=now()
        where id=o.id returning * into o;
      insert into public.delivery_cloud_history(order_id,actor_id,action,status,version,reason)
        values(o.id,uid,'instruction',o.status,o.version,v_instruction);
      insert into public.delivery_live_events(room_id,kind,payload)
        values(o.tracking_code,'status',jsonb_build_object('status',o.status,'version',o.version));
    end if;
    return to_jsonb(o)-'request_payload'-'request_key';

  elsif p_action='stats' then
    with scoped as (
      select o2.status,o2.created_at,coalesce(o2.details->>'service_type','standard') as service_type,
        (select min(h.created_at) from public.delivery_cloud_history h where h.order_id=o2.id and h.action='pickup') as picked_at,
        (select max(h.created_at) from public.delivery_cloud_history h where h.order_id=o2.id and h.action='deliver') as delivered_at
      from public.delivery_cloud_orders o2
      where o2.created_at>=v_since and (op or uid in (o2.owner_id,o2.merchant_id,o2.driver_id))
    ), services as (
      select service_type,count(*) as total,count(*) filter(where status='delivered') as delivered,
        round(avg(extract(epoch from delivered_at-created_at)/60) filter(where status='delivered' and delivered_at is not null)) as avg_minutes
      from scoped group by service_type
    )
    select jsonb_build_object(
      'total',(select count(*) from scoped),
      'delivered',(select count(*) from scoped where status='delivered'),
      'failed_or_returned',(select count(*) from scoped where status in ('failed','returning','returned')),
      'cancelled',(select count(*) from scoped where status='cancelled'),
      'active',(select count(*) from scoped where status in ('searching','accepted','arrivingPickup','inTransit')),
      'avg_delivery_minutes',(select round(avg(extract(epoch from delivered_at-created_at)/60)) from scoped
        where status='delivered' and delivered_at is not null),
      'avg_transit_minutes',(select round(avg(extract(epoch from delivered_at-picked_at)/60)) from scoped
        where status='delivered' and delivered_at is not null and picked_at is not null),
      'by_service',coalesce((select jsonb_agg(jsonb_build_object('service_type',service_type,'total',total,
        'delivered',delivered,'avg_delivery_minutes',avg_minutes) order by total desc,service_type) from services),'[]'::jsonb)
    ) into v_result;
    return jsonb_build_object('scope',case when op then 'network' else 'account' end,'window_days',30,'summary',v_result,
      'pickups',jsonb_build_object(
        'requested',(select count(*) from public.delivery_cloud_pickups where status='requested' and (op or merchant_id=uid)),
        'assigned',(select count(*) from public.delivery_cloud_pickups where status='assigned' and (op or uid in (merchant_id,driver_id)))),
      'drivers',case when op then jsonb_build_object(
        'approved',(select count(*) from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id=m.user_id
          where m.role='driver' and m.state='active' and not a.blocked),
        'on_trip',(select count(distinct driver_id) from public.delivery_cloud_orders
          where driver_id is not null and status in ('accepted','arrivingPickup','inTransit','returning'))) end);

  elsif p_action='service_eta' then
    -- Network-wide averages expose no order, account or address data.
    return jsonb_build_object('window_days',30,'services',coalesce((select jsonb_agg(jsonb_build_object(
        'service_type',q.service_type,'samples',q.samples,'avg_delivery_minutes',q.avg_minutes) order by q.service_type)
      from (select coalesce(o2.details->>'service_type','standard') as service_type,count(*) as samples,
          round(avg(extract(epoch from h.delivered_at-o2.created_at)/60)) as avg_minutes
        from public.delivery_cloud_orders o2
        cross join lateral (select max(h2.created_at) as delivered_at from public.delivery_cloud_history h2
          where h2.order_id=o2.id and h2.action='deliver') h
        where o2.status='delivered' and o2.created_at>=v_since and h.delivered_at is not null
        group by 1) q),'[]'::jsonb));
  end if;
  raise sqlstate 'PT400' using message='Thao tác vận hành không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_logistics(text,jsonb) from public,anon;
grant execute on function public.delivery_cloud_logistics(text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
