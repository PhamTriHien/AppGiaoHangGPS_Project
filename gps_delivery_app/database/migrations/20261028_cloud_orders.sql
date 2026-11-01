-- Requires 20261027_delivery_integrations.sql. Safe to reapply.
begin;

create table if not exists public.delivery_cloud_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (length(full_name) between 1 and 120),
  phone text not null check (phone ~ '^0[35789][0-9]{8}$'),
  role text not null default 'customer' check (role in ('customer','merchant','driver')),
  requested_role text check (requested_role in ('merchant','driver')),
  blocked boolean not null default false,
  updated_at timestamptz not null default now()
);
create table if not exists public.delivery_cloud_pricing (
  id boolean primary key default true check (id),
  base_fee integer not null default 25000 check (base_fee between 0 and 1000000),
  per_km integer not null default 5000 check (per_km between 0 and 100000),
  express_fee integer not null default 10000 check (express_fee between 0 and 1000000),
  extra_kg integer not null default 3000 check (extra_kg between 0 and 100000),
  version integer not null default 1
);
insert into public.delivery_cloud_pricing(id) values(true) on conflict do nothing;
create table if not exists public.delivery_cloud_orders (
  id uuid primary key default gen_random_uuid(),
  tracking_code text not null unique default ('CL-' || upper(replace(gen_random_uuid()::text,'-',''))),
  owner_id uuid not null references public.delivery_cloud_accounts(user_id),
  merchant_id uuid references public.delivery_cloud_accounts(user_id),
  driver_id uuid references public.delivery_cloud_accounts(user_id),
  request_key uuid not null,
  request_payload jsonb not null,
  details jsonb not null,
  distance_meters integer not null check (distance_meters between 1 and 200000),
  shipping_fee integer not null check (shipping_fee >= 0),
  cod_amount integer not null check (cod_amount between 0 and 20000000),
  pricing_version integer not null,
  payment_status text not null default 'UNPAID' check (payment_status = 'UNPAID'),
  status text not null default 'searching' check (status in ('searching','accepted','arrivingPickup','inTransit','delivered','failed','returning','returned','cancelled')),
  merchant_ready boolean not null,
  version integer not null default 1,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,request_key)
);
alter table public.delivery_cloud_orders drop constraint if exists delivery_cloud_orders_status_check;
alter table public.delivery_cloud_orders add constraint delivery_cloud_orders_status_check
  check (status in ('searching','accepted','arrivingPickup','inTransit','delivered','failed','returning','returned','cancelled'));
create index if not exists cloud_orders_owner on public.delivery_cloud_orders(owner_id,created_at desc);
create index if not exists cloud_orders_merchant on public.delivery_cloud_orders(merchant_id,created_at desc);
create index if not exists cloud_orders_driver on public.delivery_cloud_orders(driver_id,status);
create index if not exists cloud_orders_queue on public.delivery_cloud_orders(created_at desc) where status='searching' and merchant_ready;
create table if not exists public.delivery_cloud_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.delivery_cloud_orders(id),
  actor_id uuid not null references auth.users(id),
  action text not null,
  status text not null,
  version integer not null,
  created_at timestamptz not null default now(),
  unique(order_id,version)
);
alter table public.delivery_cloud_history add column if not exists reason text not null default ''
  check (length(reason)<=500);
create table if not exists public.delivery_cloud_commands (
  actor_id uuid not null references auth.users(id),
  request_key uuid not null,
  request_payload jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id,request_key)
);
create table if not exists public.delivery_cloud_admin_audit (
  id uuid primary key default gen_random_uuid(), actor_id uuid not null references auth.users(id),
  action text not null, target_id uuid, before_value jsonb, after_value jsonb, created_at timestamptz not null default now()
);
alter table public.delivery_cloud_accounts enable row level security;
alter table public.delivery_cloud_orders enable row level security;
alter table public.delivery_cloud_pricing enable row level security;
alter table public.delivery_cloud_history enable row level security;
alter table public.delivery_cloud_commands enable row level security;
alter table public.delivery_cloud_admin_audit enable row level security;
revoke all on public.delivery_cloud_accounts, public.delivery_cloud_orders, public.delivery_cloud_pricing,
  public.delivery_cloud_history, public.delivery_cloud_commands, public.delivery_cloud_admin_audit from anon, authenticated;
grant select on public.delivery_cloud_accounts, public.delivery_cloud_orders, public.delivery_cloud_pricing,
  public.delivery_cloud_history to authenticated;

create or replace function public.delivery_cloud_active() returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and not blocked);
$$;
create or replace function public.delivery_is_member(room text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_live_members where room_id=room and user_id=auth.uid()) and
    (not exists(select 1 from public.delivery_cloud_orders where tracking_code=room) or public.delivery_cloud_active());
$$;
create or replace function public.delivery_is_driver(room text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_live_members where room_id=room and user_id=auth.uid() and role='driver') and
    (not exists(select 1 from public.delivery_cloud_orders where tracking_code=room) or exists(
      select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and role='driver' and not blocked));
$$;
drop policy if exists cloud_account_read on public.delivery_cloud_accounts;
create policy cloud_account_read on public.delivery_cloud_accounts for select to authenticated
  using(user_id=auth.uid() or public.delivery_is_operator());
drop policy if exists cloud_order_read on public.delivery_cloud_orders;
create policy cloud_order_read on public.delivery_cloud_orders for select to authenticated
  using(public.delivery_is_operator() or (public.delivery_cloud_active() and auth.uid() in (owner_id,merchant_id,driver_id)));
drop policy if exists cloud_pricing_read on public.delivery_cloud_pricing;
create policy cloud_pricing_read on public.delivery_cloud_pricing for select to authenticated using(true);
drop policy if exists cloud_history_read on public.delivery_cloud_history;
create policy cloud_history_read on public.delivery_cloud_history for select to authenticated using(
  exists(select 1 from public.delivery_cloud_orders o where o.id=order_id));

create or replace function public.delivery_cloud_profile(p_details jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_accounts; requested text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập cloud.'; end if;
  if p_details is not null then
    if jsonb_typeof(p_details) <> 'object' or length(btrim(coalesce(p_details->>'full_name',''))) not between 1 and 120 or
      coalesce(p_details->>'phone','') !~ '^0[35789][0-9]{8}$' or
      coalesce(p_details->>'requested_role','customer') not in ('customer','merchant','driver') then
      raise sqlstate 'PT400' using message='Họ tên, số điện thoại hoặc vai trò không hợp lệ.';
    end if;
    requested := case when p_details->>'requested_role' in ('merchant','driver') then p_details->>'requested_role' end;
    insert into public.delivery_cloud_accounts(user_id,full_name,phone,requested_role)
    values(auth.uid(),btrim(p_details->>'full_name'),p_details->>'phone',requested)
    on conflict(user_id) do update set full_name=excluded.full_name,phone=excluded.phone,
      requested_role=case when delivery_cloud_accounts.role=excluded.requested_role then null else excluded.requested_role end,
      updated_at=now();
  end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid();
  return jsonb_build_object('account',case when a.user_id is null then null else to_jsonb(a) end,
    'operator',public.delivery_is_operator(),'user_id',auth.uid(),'schema_version',2);
end; $$;

create or replace function public.delivery_cloud_accounts_manage(p_user uuid default null,p_role text default null,p_blocked boolean default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous public.delivery_cloud_accounts; changed public.delivery_cloud_accounts;
begin
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền operator cloud.'; end if;
  if p_user is not null then
    if p_role is null or p_role not in ('customer','merchant','driver') or p_blocked is null then
      raise sqlstate 'PT400' using message='Vai trò không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||p_user::text,0));
    select * into previous from public.delivery_cloud_accounts where user_id=p_user for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy tài khoản cloud.'; end if;
    if previous.role='driver' and p_role<>'driver' and exists(select 1 from public.delivery_cloud_orders
      where driver_id=p_user and status not in ('delivered','returned','cancelled')) then
      raise sqlstate 'PT409' using message='Tài xế còn chuyến chưa hoàn tất. Hoàn tất hoặc xử lý chuyến trước khi đổi vai trò.';
    end if;
    update public.delivery_cloud_accounts set role=p_role,blocked=p_blocked,
      requested_role=case when p_role=previous.role and p_blocked<>previous.blocked then previous.requested_role else null end,
      updated_at=now() where user_id=p_user returning * into changed;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(auth.uid(),'account_role',p_user,to_jsonb(previous),to_jsonb(changed));
  end if;
  return jsonb_build_object('accounts',coalesce((select jsonb_agg(to_jsonb(a) order by a.updated_at desc)
    from (select * from public.delivery_cloud_accounts order by updated_at desc limit 200) a),'[]'::jsonb));
end; $$;

create or replace function public.delivery_cloud_pricing_manage(p_values jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous public.delivery_cloud_pricing; changed public.delivery_cloud_pricing; k text; maximum integer;
begin
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền operator cloud.'; end if;
  select * into previous from public.delivery_cloud_pricing where id for update;
  if p_values is not null then
    if jsonb_typeof(p_values) is distinct from 'object' or
      not(p_values ?& array['base_fee','per_km','express_fee','extra_kg','version']) or
      p_values-array['base_fee','per_km','express_fee','extra_kg','version']<>'{}'::jsonb then
      raise sqlstate 'PT400' using message='Thông tin bảng giá không hợp lệ.';
    end if;
    foreach k in array array['base_fee','per_km','express_fee','extra_kg','version'] loop
      maximum:=case when k='version' then 2147483646 when k in ('per_km','extra_kg') then 100000 else 1000000 end;
      if jsonb_typeof(p_values->k) is distinct from 'number' then
        raise sqlstate 'PT400' using message='Bảng giá cần số nguyên trong giới hạn cho phép.';
      end if;
      if (p_values->>k)::numeric<>trunc((p_values->>k)::numeric) or
        (p_values->>k)::numeric not between (case when k='version' then 1 else 0 end) and maximum then
        raise sqlstate 'PT400' using message='Bảng giá cần số nguyên trong giới hạn cho phép.';
      end if;
    end loop;
    if (p_values->>'version')::integer is distinct from previous.version then
      raise sqlstate 'PT409' using message='Bảng giá đã thay đổi. Vui lòng tải lại.';
    end if;
    update public.delivery_cloud_pricing set base_fee=(p_values->>'base_fee')::integer,per_km=(p_values->>'per_km')::integer,
      express_fee=(p_values->>'express_fee')::integer,extra_kg=(p_values->>'extra_kg')::integer,version=version+1 where id returning * into changed;
    insert into public.delivery_cloud_admin_audit(actor_id,action,before_value,after_value)
      values(auth.uid(),'pricing',to_jsonb(previous),to_jsonb(changed));
  else changed:=previous; end if;
  return jsonb_build_object('pricing',to_jsonb(changed));
end; $$;

create or replace function public.delivery_cloud_audit_read() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền operator cloud.'; end if;
  return jsonb_build_object('entries',coalesce((select jsonb_agg(to_jsonb(a) order by created_at desc)
    from (select * from public.delivery_cloud_admin_audit order by created_at desc limit 50) a),'[]'::jsonb));
end; $$;

create or replace function public.delivery_cloud_merchants() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('merchants',coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'full_name',full_name) order by full_name),'[]'::jsonb))
  from public.delivery_cloud_accounts where role='merchant' and not blocked and auth.uid() is not null;
$$;

create or replace function public.delivery_cloud_quote(p_details jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.delivery_cloud_pricing; a float8; meters integer; fee integer; weight numeric;
  lat1 float8; lat2 float8; lng1 float8; lng2 float8; service text;
begin
  if not public.delivery_cloud_active() then raise sqlstate 'PT403' using message='Cần hoàn thiện hồ sơ cloud và tài khoản đang hoạt động.'; end if;
  if jsonb_typeof(p_details) is distinct from 'object' or
    not(p_details ?& array['pickup_lat','pickup_lng','dropoff_lat','dropoff_lng','weight_kg','service_type']) or
    jsonb_typeof(p_details->'pickup_lat') <> 'number' or jsonb_typeof(p_details->'pickup_lng') <> 'number' or
    jsonb_typeof(p_details->'dropoff_lat') <> 'number' or jsonb_typeof(p_details->'dropoff_lng') <> 'number' or
    jsonb_typeof(p_details->'weight_kg') <> 'number' then
    raise sqlstate 'PT400' using message='Cần tọa độ và khối lượng hợp lệ.';
  end if;
  lat1:=(p_details->>'pickup_lat')::float8; lng1:=(p_details->>'pickup_lng')::float8;
  lat2:=(p_details->>'dropoff_lat')::float8; lng2:=(p_details->>'dropoff_lng')::float8;
  weight:=(p_details->>'weight_kg')::numeric; service:=p_details->>'service_type';
  if abs(lat1)>90 or abs(lat2)>90 or abs(lng1)>180 or abs(lng2)>180 or
    weight<=0 or weight>30 or service is null or service not in ('standard','express') then
    raise sqlstate 'PT400' using message='Tọa độ, dịch vụ hoặc khối lượng không hợp lệ (tối đa 30 kg).';
  end if;
  a:=power(sin(radians(lat2-lat1)/2),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lng2-lng1)/2),2);
  meters:=greatest(1,ceil(6371000*2*asin(sqrt(least(1,a)))*1.3)::integer);
  if meters>200000 then raise sqlstate 'PT400' using message='Ngoài phạm vi giao hàng 200 km.'; end if;
  select * into p from public.delivery_cloud_pricing where id;
  fee:=p.base_fee+greatest(0,ceil(meters/1000.0)-2)::integer*p.per_km+
    greatest(0,ceil(weight-5))::integer*p.extra_kg+case when service='express' then p.express_fee else 0 end;
  return jsonb_build_object('shipping_fee',fee,'distance_meters',meters,'pricing_version',p.version,
    'distance_source','geodesic_estimate','currency','VND','breakdown',jsonb_build_object(
      'base_fee',p.base_fee,'distance_fee',greatest(0,ceil(meters/1000.0)-2)::integer*p.per_km,
      'weight_fee',greatest(0,ceil(weight-5))::integer*p.extra_kg,
      'express_fee',case when service='express' then p.express_fee else 0 end));
end; $$;

create or replace function public.delivery_cloud_create(p_details jsonb,p_request_key uuid,p_pricing_version integer,p_expected_fee integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.delivery_cloud_orders; a public.delivery_cloud_accounts; q jsonb; merchant uuid; saved jsonb;
begin
  if not public.delivery_cloud_active() then raise sqlstate 'PT403' using message='Cần hồ sơ cloud đang hoạt động.'; end if;
  if p_request_key is null then raise sqlstate 'PT400' using message='Thiếu mã yêu cầu.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_key::text,0));
  saved:=jsonb_build_object('details',p_details,'pricing_version',p_pricing_version,'expected_fee',p_expected_fee);
  select * into o from public.delivery_cloud_orders where owner_id=auth.uid() and request_key=p_request_key;
  if found then
    if o.request_payload<>saved then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho nội dung khác.'; end if;
    return to_jsonb(o)-'request_payload'-'request_key';
  end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid();
  if a.role not in ('customer','merchant') then raise sqlstate 'PT403' using message='Chỉ khách hàng hoặc cửa hàng được tạo đơn.'; end if;
  q:=public.delivery_cloud_quote(p_details);
  if octet_length(p_details::text)>12000 or p_details-array['pickup_address','dropoff_address','recipient_name',
    'recipient_phone','package_description','pickup_lat','pickup_lng','dropoff_lat','dropoff_lng','weight_kg',
    'cod_amount','service_type','payment_method','merchant_id'] <> '{}'::jsonb then
    raise sqlstate 'PT400' using message='Đơn hàng có trường không hỗ trợ hoặc quá dài.';
  end if;
  if p_pricing_version is distinct from (q->>'pricing_version')::integer or p_expected_fee is distinct from (q->>'shipping_fee')::integer then
    raise sqlstate 'PT409' using message='Giá cước đã thay đổi. Vui lòng lấy báo giá lại.';
  end if;
  if length(btrim(coalesce(p_details->>'pickup_address',''))) not between 5 and 500 or
    length(btrim(coalesce(p_details->>'dropoff_address',''))) not between 5 and 500 or
    length(btrim(coalesce(p_details->>'recipient_name',''))) not between 1 and 120 or
    coalesce(p_details->>'recipient_phone','') !~ '^0[35789][0-9]{8}$' or
    length(btrim(coalesce(p_details->>'package_description',''))) not between 1 and 1000 or
    jsonb_typeof(p_details->'cod_amount') is distinct from 'number' or
    (p_details->>'cod_amount')::numeric not between 0 and 20000000 or
    trunc((p_details->>'cod_amount')::numeric)<>(p_details->>'cod_amount')::numeric or
    coalesce(p_details->>'payment_method','') not in ('sender_cash','recipient_cash') then
    raise sqlstate 'PT400' using message='Thông tin người nhận, hàng hóa, COD hoặc phương thức trả phí không hợp lệ.';
  end if;
  merchant:=case when a.role='merchant' then auth.uid() else nullif(p_details->>'merchant_id','')::uuid end;
  if merchant is not null and not exists(select 1 from public.delivery_cloud_accounts where user_id=merchant and role='merchant' and not blocked) then
    raise sqlstate 'PT400' using message='Cửa hàng chưa được duyệt hoặc đang khóa.';
  end if;
  insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
    shipping_fee,cod_amount,pricing_version,merchant_ready)
  values(auth.uid(),merchant,p_request_key,saved,p_details,(q->>'distance_meters')::integer,
    (q->>'shipping_fee')::integer,(p_details->>'cod_amount')::integer,(q->>'pricing_version')::integer,merchant is null) returning * into o;
  insert into public.delivery_live_rooms(id) values(o.tracking_code);
  insert into public.delivery_live_members values(o.tracking_code,auth.uid(),case when a.role='merchant' then 'merchant' else 'customer' end);
  if merchant is not null and merchant<>auth.uid() then insert into public.delivery_live_members values(o.tracking_code,merchant,'merchant'); end if;
  insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(o.id,auth.uid(),'create',o.status,o.version);
  insert into public.delivery_live_events(room_id,kind,payload) values(o.tracking_code,'status',jsonb_build_object('status',o.status,'version',o.version));
  return to_jsonb(o)-'request_payload'-'request_key';
end; $$;

drop function if exists public.delivery_cloud_list(boolean,timestamptz);
create or replace function public.delivery_cloud_list(p_queue boolean default false,p_before timestamptz default null,p_before_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a public.delivery_cloud_accounts; result jsonb;
begin
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid();
  if not public.delivery_is_operator() and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message='Cần hồ sơ cloud đang hoạt động.';
  end if;
  if p_queue then
    if a.role is distinct from 'driver' or a.blocked then raise sqlstate 'PT403' using message='Cần tài khoản tài xế được duyệt.'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'tracking_code',tracking_code,'shipping_fee',shipping_fee,
      'cod_amount',cod_amount,'version',version,'status',status,'created_at',created_at,'distance_meters',distance_meters,
      'details',jsonb_build_object('weight_kg',details->'weight_kg','service_type',details->'service_type')) order by created_at desc,id desc),'[]'::jsonb)
    into result from (select * from public.delivery_cloud_orders where status='searching' and merchant_ready and driver_id is null
      and (p_before is null or (p_before_id is null and created_at<p_before) or (created_at,id)<(p_before,p_before_id)) order by created_at desc,id desc limit 50) o;
  else
    select coalesce(jsonb_agg(to_jsonb(o)-'request_payload'-'request_key' order by created_at desc,id desc),'[]'::jsonb) into result
    from (select * from public.delivery_cloud_orders where
      (public.delivery_is_operator() or auth.uid() in (owner_id,merchant_id,driver_id)) and
      (p_before is null or (p_before_id is null and created_at<p_before) or (created_at,id)<(p_before,p_before_id)) order by created_at desc,id desc limit 50) o;
  end if;
  return jsonb_build_object('orders',result,'page_size',50);
end; $$;

create or replace function public.delivery_cloud_transition(p_order uuid,p_action text,p_version integer,p_request_key uuid,p_reason text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.delivery_cloud_orders; a public.delivery_cloud_accounts; op boolean; next_status text;
  request jsonb; prior public.delivery_cloud_commands; response jsonb;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập cloud.'; end if;
  op:=public.delivery_is_operator();
  if not op and not public.delivery_cloud_active() then raise sqlstate 'PT403' using message='Tài khoản chưa có hồ sơ hoặc đang khóa.'; end if;
  if p_request_key is null then raise sqlstate 'PT400' using message='Thiếu mã yêu cầu.'; end if;
  if p_action is null or p_action not in ('ready','claim','cancel','arrive','pickup','deliver','fail','retry','return','complete_return') or
    p_reason is null or length(p_reason)>500 then
    raise sqlstate 'PT400' using message='Thao tác hoặc lý do không hợp lệ.';
  end if;
  if p_action in ('cancel','fail','return') and length(btrim(p_reason))<3 then
    raise sqlstate 'PT400' using message='Cần nhập lý do ít nhất 3 ký tự.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_key::text,0));
  request:=jsonb_build_object('order',p_order,'action',p_action,'version',p_version,'reason',p_reason);
  select * into prior from public.delivery_cloud_commands where actor_id=auth.uid() and request_key=p_request_key;
  if found then
    if prior.request_payload<>request then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho nội dung khác.'; end if;
    return prior.response;
  end if;
  -- Serialize competing claims by the same driver, including different orders.
  perform pg_advisory_xact_lock(hashtextextended('driver:'||auth.uid()::text,0));
  select * into o from public.delivery_cloud_orders where id=p_order for update;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid();
  if o.id is null or (not op and auth.uid() not in (o.owner_id,coalesce(o.merchant_id,o.owner_id),coalesce(o.driver_id,o.owner_id)) and
    not (p_action='claim' and a.role='driver' and o.status='searching' and o.merchant_ready)) then
    raise sqlstate 'PT404' using message='Không tìm thấy đơn hàng được phép truy cập.';
  end if;
  if p_version is distinct from o.version then raise sqlstate 'PT409' using message='Đơn đã thay đổi. Vui lòng tải lại.'; end if;
  next_status:=o.status;
  if p_action='ready' then
    if (not op and auth.uid() is distinct from o.merchant_id) or o.status<>'searching' or o.merchant_ready then
      raise sqlstate 'PT409' using message='Không thể xác nhận cửa hàng sẵn sàng.';
    end if;
    o.merchant_ready:=true;
  elsif p_action='claim' then
    if a.role is distinct from 'driver' or a.blocked or o.status<>'searching' or not o.merchant_ready or o.driver_id is not null then
      raise sqlstate 'PT409' using message='Đơn không còn khả dụng hoặc tài khoản chưa được duyệt tài xế.';
    end if;
    if exists(select 1 from public.delivery_cloud_orders where driver_id=auth.uid() and status not in ('delivered','returned','cancelled')) then
      raise sqlstate 'PT409' using message='Bạn đang có chuyến chưa hoàn tất.';
    end if;
    o.driver_id:=auth.uid(); next_status:='accepted';
  elsif p_action='cancel' then
    if (not op and auth.uid() is distinct from o.owner_id and auth.uid() is distinct from o.merchant_id) or o.status not in ('searching','accepted','arrivingPickup') or
      length(btrim(coalesce(p_reason,''))) not between 3 and 500 then
      raise sqlstate 'PT409' using message='Không thể hủy đơn hoặc chưa nhập lý do hợp lệ.';
    end if;
    next_status:='cancelled'; o.cancel_reason:=btrim(p_reason);
  else
    if not op and auth.uid() is distinct from o.driver_id then raise sqlstate 'PT403' using message='Chỉ tài xế nhận chuyến hoặc operator được cập nhật.'; end if;
    next_status:=case
      when p_action='arrive' and o.status='accepted' then 'arrivingPickup'
      when p_action='pickup' and o.status='arrivingPickup' then 'inTransit'
      when p_action='deliver' and o.status='inTransit' then 'delivered'
      when p_action='fail' and o.status='inTransit' then 'failed'
      when p_action='retry' and o.status='failed' then 'inTransit'
      when p_action='return' and o.status='failed' then 'returning'
      when p_action='complete_return' and o.status='returning' then 'returned' end;
    if next_status is null then raise sqlstate 'PT409' using message='Thao tác không phù hợp trạng thái đơn.'; end if;
  end if;
  update public.delivery_cloud_orders set status=next_status,driver_id=o.driver_id,merchant_ready=o.merchant_ready,
    cancel_reason=o.cancel_reason,version=version+1,updated_at=now() where id=o.id returning * into o;
  if p_action='claim' then insert into public.delivery_live_members values(o.tracking_code,auth.uid(),'driver')
    on conflict(room_id,user_id) do update set role='driver'; end if;
  insert into public.delivery_cloud_history(order_id,actor_id,action,status,version,reason)
    values(o.id,auth.uid(),p_action,o.status,o.version,btrim(p_reason));
  insert into public.delivery_live_events(room_id,kind,payload) values(o.tracking_code,'status',jsonb_build_object('status',o.status,'version',o.version));
  response:=to_jsonb(o)-'request_payload'-'request_key';
  insert into public.delivery_cloud_commands values(auth.uid(),p_request_key,request,response,now());
  return response;
end; $$;

create or replace function public.delivery_cloud_history_read(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not exists(select 1 from public.delivery_cloud_orders where id=p_order and
    (public.delivery_is_operator() or (public.delivery_cloud_active() and auth.uid() in (owner_id,merchant_id,driver_id)))) then
    raise sqlstate 'PT404' using message='Không tìm thấy đơn hàng.';
  end if;
  return jsonb_build_object('history',coalesce((select jsonb_agg(to_jsonb(h) order by version) from public.delivery_cloud_history h where order_id=p_order),'[]'::jsonb));
end; $$;

-- Live status is a notification of committed order state, never a write shortcut.
create or replace function public.delivery_cloud_guard_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.kind='status' and exists(select 1 from public.delivery_cloud_orders where tracking_code=new.room_id and
    (status is distinct from new.payload->>'status' or version::text is distinct from new.payload->>'version')) then
    raise sqlstate 'PT409' using message='Cập nhật đơn qua API cloud trước khi gửi sự kiện.';
  end if;
  return new;
end; $$;
drop trigger if exists cloud_event_guard on public.delivery_live_events;
create trigger cloud_event_guard before insert on public.delivery_live_events for each row execute function public.delivery_cloud_guard_event();

-- Preserve legacy room validation while allowing the cloud return terminal state.
create or replace function public.delivery_validate_event() returns trigger
language plpgsql set search_path='' as $$
declare previous_status text; next_status text;
begin
  new.created_at:=now();
  if new.kind='status' then
    if coalesce(new.payload->>'status','') not in ('searching','accepted','arrivingPickup','inTransit','delivered','failed','returning','returned','cancelled') then
      raise exception 'Invalid delivery status';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(new.room_id,0));
    select payload->>'status' into previous_status from public.delivery_live_events
      where room_id=new.room_id and kind='status' order by created_at desc limit 1;
    next_status:=new.payload->>'status';
    if previous_status is not null and previous_status<>next_status and not (
      (previous_status='searching' and next_status in ('accepted','cancelled')) or
      (previous_status='accepted' and next_status in ('arrivingPickup','cancelled')) or
      (previous_status='arrivingPickup' and next_status in ('inTransit','cancelled')) or
      (previous_status='inTransit' and next_status in ('delivered','failed')) or
      (previous_status='failed' and next_status in ('inTransit','returning')) or
      (previous_status='returning' and next_status in ('delivered','returned'))
    ) then raise exception 'Invalid delivery transition'; end if;
  end if;
  if new.kind='chat' then
    if length(coalesce(new.payload->>'text','')) not between 1 and 2000 then raise exception 'Invalid chat message'; end if;
    new.payload:=jsonb_set(new.payload,'{isCustomer}',to_jsonb(not public.delivery_is_driver(new.room_id)));
  end if;
  if new.kind='gps' and (jsonb_typeof(new.payload->'latitude') is distinct from 'number' or
    jsonb_typeof(new.payload->'longitude') is distinct from 'number' or
    (new.payload->>'latitude')::numeric not between -90 and 90 or
    (new.payload->>'longitude')::numeric not between -180 and 180 or
    not(new.payload ?& array['latitude','longitude'])) then raise exception 'Invalid location'; end if;
  if new.kind='pod' and (split_part(coalesce(new.payload->>'path',''),'/',1)<>new.room_id or
    strpos(coalesce(new.payload->>'path',''),'..')>0 or not exists(
      select 1 from storage.objects where bucket_id='delivery-evidence' and name=new.payload->>'path')) then
    raise exception 'Invalid delivery evidence';
  end if;
  return new;
end; $$;

revoke all on function public.delivery_cloud_active(),public.delivery_cloud_profile(jsonb),
  public.delivery_cloud_pricing_manage(jsonb),public.delivery_cloud_audit_read(),
  public.delivery_cloud_accounts_manage(uuid,text,boolean),public.delivery_cloud_merchants(),public.delivery_cloud_quote(jsonb),
  public.delivery_cloud_create(jsonb,uuid,integer,integer),public.delivery_cloud_list(boolean,timestamptz,uuid),
  public.delivery_cloud_transition(uuid,text,integer,uuid,text),public.delivery_cloud_history_read(uuid),
  public.delivery_cloud_guard_event() from public,anon;
grant execute on function public.delivery_cloud_active(),public.delivery_cloud_profile(jsonb),
  public.delivery_cloud_pricing_manage(jsonb),public.delivery_cloud_audit_read(),
  public.delivery_cloud_accounts_manage(uuid,text,boolean),public.delivery_cloud_merchants(),public.delivery_cloud_quote(jsonb),
  public.delivery_cloud_create(jsonb,uuid,integer,integer),public.delivery_cloud_list(boolean,timestamptz,uuid),
  public.delivery_cloud_transition(uuid,text,integer,uuid,text),public.delivery_cloud_history_read(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
