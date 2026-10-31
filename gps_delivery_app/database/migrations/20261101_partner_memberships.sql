-- Additive partner approvals. Existing primary roles remain for old clients;
-- only memberships authorize partner actions after this migration.
begin;
create table if not exists public.delivery_cloud_memberships (
  user_id uuid not null references public.delivery_cloud_accounts(user_id),
  role text not null check(role in ('merchant','driver')),
  state text not null check(state in ('pending','active','rejected','revoked')),
  version integer not null default 1 check(version>0),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz, reviewed_by uuid references auth.users(id),
  reason text not null default '' check(length(reason)<=500),
  primary key(user_id,role)
);
alter table public.delivery_cloud_memberships enable row level security;
revoke all on public.delivery_cloud_memberships from public,anon,authenticated;
-- Preserve existing server-approved rights, never infer approval from a request.
insert into public.delivery_cloud_memberships(user_id,role,state)
  select user_id,role,'active' from public.delivery_cloud_accounts where role in ('merchant','driver')
  on conflict do nothing;
insert into public.delivery_cloud_memberships(user_id,role,state)
  select user_id,requested_role,'pending' from public.delivery_cloud_accounts where requested_role is not null
  on conflict do nothing;

create or replace function public.delivery_cloud_has_membership(p_user uuid,p_role text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id=m.user_id
    where m.user_id=p_user and m.role=p_role and m.state='active' and not a.blocked);
$$;
create or replace function public.delivery_cloud_account_snapshot(p_user uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(a)||jsonb_build_object(
    'approved_roles',coalesce((select jsonb_agg(m.role order by m.role) from public.delivery_cloud_memberships m
      where m.user_id=a.user_id and m.state='active'),'[]'::jsonb),
    'memberships',coalesce((select jsonb_agg(to_jsonb(m)-'user_id'-'reviewed_by' order by m.role)
      from public.delivery_cloud_memberships m where m.user_id=a.user_id),'[]'::jsonb),
    'requested_role',(select m.role from public.delivery_cloud_memberships m where m.user_id=a.user_id and m.state='pending' order by m.role limit 1))
  from public.delivery_cloud_accounts a where a.user_id=p_user;
$$;

create or replace function public.delivery_cloud_membership(p_role text,p_decision text,p_user uuid default null,
  p_version integer default null,p_reason text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_user,auth.uid()); a public.delivery_cloud_accounts; previous public.delivery_cloud_memberships;
  changed public.delivery_cloud_memberships; next_state text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if p_role is null or p_role not in ('merchant','driver') or p_decision is null or
    p_decision not in ('request','approve','reject','revoke') or p_reason is null or length(p_reason)>500 then
    raise sqlstate 'PT400' using message='Yêu cầu tư cách đối tác không hợp lệ.';
  end if;
  if p_decision='request' then
    if target<>auth.uid() then raise sqlstate 'PT403' using message='Chỉ được đăng ký cho chính mình.'; end if;
  elsif not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền quản trị.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('driver:'||target::text,0));
  select * into a from public.delivery_cloud_accounts where user_id=target for update;
  if not found then raise sqlstate 'PT404' using message='Cần hoàn thiện hồ sơ trước.'; end if;
  if a.blocked then raise sqlstate 'PT403' using message='Tài khoản đang khóa.'; end if;
  select * into previous from public.delivery_cloud_memberships where user_id=target and role=p_role for update;
  if p_decision='request' then
    if previous.state in ('active','pending') then return jsonb_build_object('membership',to_jsonb(previous)-'user_id'-'reviewed_by'); end if;
    insert into public.delivery_cloud_memberships(user_id,role,state) values(target,p_role,'pending')
      on conflict(user_id,role) do update set state='pending',version=delivery_cloud_memberships.version+1,
        requested_at=now(),reviewed_at=null,reviewed_by=null,reason=''
      returning * into changed;
  else
    if previous.user_id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu đối tác.'; end if;
    if p_version is distinct from previous.version then raise sqlstate 'PT409' using message='Quyền đã thay đổi. Vui lòng tải lại.'; end if;
    if (p_decision in ('approve','reject') and previous.state<>'pending') or
      (p_decision='revoke' and previous.state<>'active') then
      raise sqlstate 'PT409' using message='Quyết định không phù hợp trạng thái hiện tại.';
    end if;
    if p_decision in ('reject','revoke') and length(btrim(p_reason))<3 then
      raise sqlstate 'PT400' using message='Cần lý do ít nhất 3 ký tự.';
    end if;
    if p_decision='revoke' and p_role='driver' and exists(select 1 from public.delivery_cloud_orders
      where driver_id=target and status not in ('delivered','returned','cancelled')) then
      raise sqlstate 'PT409' using message='Tài xế còn chuyến chưa hoàn tất.';
    end if;
    if p_decision='revoke' and p_role='merchant' and exists(select 1 from public.delivery_market_shop_orders o
      left join public.delivery_cloud_orders d on d.id=o.delivery_id where o.merchant_id=target and o.state<>'cancelled'
        and (d.id is null or d.status not in ('delivered','returned','cancelled'))) then
      raise sqlstate 'PT409' using message='Cửa hàng còn đơn chưa hoàn tất.';
    end if;
    next_state:=case p_decision when 'approve' then 'active' when 'reject' then 'rejected' else 'revoked' end;
    update public.delivery_cloud_memberships set state=next_state,version=version+1,reviewed_at=now(),reviewed_by=auth.uid(),reason=btrim(p_reason)
      where user_id=target and role=p_role returning * into changed;
    if p_decision='approve' and a.role='customer' then
      update public.delivery_cloud_accounts set role=p_role where user_id=target;
    elsif p_decision='revoke' and a.role=p_role then
      update public.delivery_cloud_accounts set role=coalesce((select role from public.delivery_cloud_memberships
        where user_id=target and state='active' order by role limit 1),'customer') where user_id=target;
    end if;
  end if;
  update public.delivery_cloud_accounts set requested_role=(select role from public.delivery_cloud_memberships
    where user_id=target and state='pending' order by role limit 1),updated_at=now() where user_id=target;
  insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
    values(auth.uid(),'membership_'||p_decision,target,to_jsonb(previous),to_jsonb(changed));
  return jsonb_build_object('membership',to_jsonb(changed)-'user_id'-'reviewed_by');
end; $$;

create or replace function public.delivery_cloud_profile(p_details jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_accounts; requested text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if p_details is not null then
    if jsonb_typeof(p_details) is distinct from 'object' or
      p_details-array['full_name','phone','requested_role']<>'{}'::jsonb or
      jsonb_typeof(p_details->'full_name') is distinct from 'string' or
      jsonb_typeof(p_details->'phone') is distinct from 'string' or
      length(btrim(coalesce(p_details->>'full_name',''))) not between 1 and 120 or
      coalesce(p_details->>'phone','') !~ '^0[35789][0-9]{8}$' or
      coalesce(p_details->>'requested_role','customer') not in ('customer','merchant','driver') then
      raise sqlstate 'PT400' using message='Thông tin hồ sơ không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||auth.uid()::text,0));
    select * into a from public.delivery_cloud_accounts where user_id=auth.uid() for update;
    if a.blocked then raise sqlstate 'PT403' using message='Tài khoản đang khóa.'; end if;
    insert into public.delivery_cloud_accounts(user_id,full_name,phone)
      values(auth.uid(),btrim(p_details->>'full_name'),p_details->>'phone')
      on conflict(user_id) do update set full_name=excluded.full_name,phone=excluded.phone,updated_at=now();
    requested:=p_details->>'requested_role';
    if requested in ('merchant','driver') then perform public.delivery_cloud_membership(requested,'request'); end if;
  end if;
  return jsonb_build_object('account',public.delivery_cloud_account_snapshot(auth.uid()),'operator',public.delivery_is_operator(),
    'user_id',auth.uid(),'schema_version',3);
end; $$;

-- Compatibility for older operator clients: changing the primary display role
-- grants that role, and never silently revokes a separate approved membership.
create or replace function public.delivery_cloud_accounts_manage(p_user uuid default null,p_role text default null,p_blocked boolean default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous public.delivery_cloud_accounts; changed public.delivery_cloud_accounts;
begin
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
  if p_user is not null then
    if p_role is null or p_role not in ('customer','merchant','driver') or p_blocked is null then
      raise sqlstate 'PT400' using message='Quyền không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||p_user::text,0));
    select * into previous from public.delivery_cloud_accounts where user_id=p_user for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy tài khoản.'; end if;
    if p_role in ('merchant','driver') and p_role<>previous.role then
      insert into public.delivery_cloud_memberships(user_id,role,state,reviewed_at,reviewed_by)
        values(p_user,p_role,'active',now(),auth.uid())
        on conflict(user_id,role) do update set state='active',version=delivery_cloud_memberships.version+1,
          reviewed_at=now(),reviewed_by=auth.uid(),reason='' where delivery_cloud_memberships.state<>'active';
    end if;
    update public.delivery_cloud_accounts set role=p_role,blocked=p_blocked,
      requested_role=(select role from public.delivery_cloud_memberships where user_id=p_user and state='pending' order by role limit 1),
      updated_at=now() where user_id=p_user returning * into changed;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(auth.uid(),'account_role',p_user,to_jsonb(previous),to_jsonb(changed));
  end if;
  return jsonb_build_object('accounts',coalesce((select jsonb_agg(public.delivery_cloud_account_snapshot(a.user_id) order by a.updated_at desc,a.user_id desc)
    from (select user_id,updated_at from public.delivery_cloud_accounts order by updated_at desc,user_id desc limit 200) a),'[]'::jsonb));
end; $$;

create or replace function public.delivery_is_driver(room text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_live_members where room_id=room and user_id=auth.uid() and role='driver') and
    (not exists(select 1 from public.delivery_cloud_orders where tracking_code=room) or
      public.delivery_cloud_has_membership(auth.uid(),'driver'));
$$;
create or replace function public.delivery_cloud_merchants() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('merchants',coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'full_name',full_name) order by full_name),'[]'::jsonb))
    from public.delivery_cloud_accounts where public.delivery_cloud_has_membership(user_id,'merchant') and auth.uid() is not null;
$$;

revoke all on function public.delivery_cloud_has_membership(uuid,text),public.delivery_cloud_account_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.delivery_cloud_membership(text,text,uuid,integer,text) from public,anon;
grant execute on function public.delivery_cloud_membership(text,text,uuid,integer,text) to authenticated;

-- Partner-aware replacements of the existing fixed RPCs follow.
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
  -- All active accounts retain basic sender rights.
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
  merchant:=case when public.delivery_cloud_has_membership(a.user_id,'merchant') then auth.uid() else nullif(p_details->>'merchant_id','')::uuid end;
  if merchant is not null and not exists(select 1 from public.delivery_cloud_accounts where user_id=merchant and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
    raise sqlstate 'PT400' using message='Cửa hàng chưa được duyệt hoặc đang khóa.';
  end if;
  insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
    shipping_fee,cod_amount,pricing_version,merchant_ready)
  values(auth.uid(),merchant,p_request_key,saved,p_details,(q->>'distance_meters')::integer,
    (q->>'shipping_fee')::integer,(p_details->>'cod_amount')::integer,(q->>'pricing_version')::integer,merchant is null) returning * into o;
  insert into public.delivery_live_rooms(id) values(o.tracking_code);
  insert into public.delivery_live_members values(o.tracking_code,auth.uid(),case when public.delivery_cloud_has_membership(a.user_id,'merchant') then 'merchant' else 'customer' end);
  if merchant is not null and merchant<>auth.uid() then insert into public.delivery_live_members values(o.tracking_code,merchant,'merchant'); end if;
  insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(o.id,auth.uid(),'create',o.status,o.version);
  insert into public.delivery_live_events(room_id,kind,payload) values(o.tracking_code,'status',jsonb_build_object('status',o.status,'version',o.version));
  return to_jsonb(o)-'request_payload'-'request_key';
end; $$;

create or replace function public.delivery_cloud_list(p_queue boolean default false,p_before timestamptz default null,p_before_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a public.delivery_cloud_accounts; result jsonb;
begin
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid();
  if not public.delivery_is_operator() and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message='Cần hồ sơ cloud đang hoạt động.';
  end if;
  if p_queue then
    if not public.delivery_cloud_has_membership(a.user_id,'driver') or a.blocked then raise sqlstate 'PT403' using message='Cần tài khoản tài xế được duyệt.'; end if;
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
    not (p_action='claim' and public.delivery_cloud_has_membership(a.user_id,'driver') and o.status='searching' and o.merchant_ready)) then
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
    if not public.delivery_cloud_has_membership(a.user_id,'driver') or a.blocked or o.status<>'searching' or not o.merchant_ready or o.driver_id is not null then
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
    if not op and (auth.uid() is distinct from o.driver_id or not public.delivery_cloud_has_membership(auth.uid(),'driver')) then raise sqlstate 'PT403' using message='Chỉ tài xế nhận chuyến hoặc operator được cập nhật.'; end if;
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

create or replace function public.delivery_market_snapshot(p_address uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_addresses; s record; i record; items jsonb; shops jsonb:='[]';
  subtotal bigint; total bigint:=0; weight numeric; details jsonb; q jsonb; cart_version integer;
begin
  select * into a from public.delivery_cloud_addresses where id=p_address and user_id=auth.uid();
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy địa chỉ nhận hàng.'; end if;
  select version into cart_version from public.delivery_market_carts where user_id=auth.uid();
  if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid()) then
    raise sqlstate 'PT400' using message='Giỏ hàng đang trống.';
  end if;
  for s in select distinct sh.* from public.delivery_market_cart_items c
    join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops sh on sh.id=p.shop_id where c.user_id=auth.uid() order by sh.id loop
    if s.status<>'active' or s.paused or not exists(select 1 from public.delivery_cloud_accounts
      where user_id=s.owner_id and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
      raise sqlstate 'PT409' using message='Cửa hàng tạm ngừng nhận đơn.';
    end if;
    if s.owner_id=auth.uid() then raise sqlstate 'PT400' using message='Không thể mua hàng từ cửa hàng của chính mình.'; end if;
    items:='[]'; subtotal:=0; weight:=0;
    for i in select p.*,c.quantity from public.delivery_market_cart_items c
      join public.delivery_market_products p on p.id=c.product_id
      where c.user_id=auth.uid() and p.shop_id=s.id order by p.id loop
      if not i.published or i.stock<i.quantity then raise sqlstate 'PT409' using message='Sản phẩm ngừng bán hoặc không đủ tồn kho.'; end if;
      subtotal:=subtotal+i.price::bigint*i.quantity; weight:=weight+i.weight_kg*i.quantity;
      items:=items||jsonb_build_array(jsonb_build_object('product_id',i.id,'name',i.name,'sku',i.sku,
        'quantity',i.quantity,'unit_price',i.price,'version',i.version,'image_url',i.image_url));
    end loop;
    if subtotal>20000000 or weight>30 then raise sqlstate 'PT400' using message='Mỗi cửa hàng hỗ trợ tối đa 20 triệu đồng và 30 kg một đơn.'; end if;
    details:=jsonb_build_object('pickup_address',s.address,'pickup_lat',s.latitude,'pickup_lng',s.longitude,
      'dropoff_address',a.full_address,'dropoff_lat',a.latitude,'dropoff_lng',a.longitude,
      'recipient_name',a.recipient_name,'recipient_phone',a.recipient_phone,
      'package_description','Hàng mua tại '||s.name,'weight_kg',weight,'service_type','standard',
      'payment_method','recipient_cash','cod_amount',subtotal,'merchant_id',s.owner_id);
    q:=public.delivery_cloud_quote(details);
    shops:=shops||jsonb_build_array(jsonb_build_object('shop_id',s.id,'shop_name',s.name,'shop_version',s.version,
      'merchant_id',s.owner_id,'items',items,'subtotal',subtotal,'shipping_fee',q->'shipping_fee',
      'pricing_version',q->'pricing_version','distance_meters',q->'distance_meters','details',details));
    total:=total+subtotal+(q->>'shipping_fee')::integer;
  end loop;
  if total not between 1 and 100000000 then raise sqlstate 'PT400' using message='Tổng giỏ hàng vượt giới hạn.'; end if;
  return jsonb_build_object('address_id',a.id,'address_version',a.version,'cart_version',cart_version,'shops',shops,'total',total);
end $$;

create or replace function public.delivery_marketplace(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor public.delivery_cloud_accounts; sh public.delivery_market_shops; prod public.delivery_market_products;
  previous public.delivery_market_products; purchase public.delivery_market_purchases; so public.delivery_market_shop_orders;
  quote public.delivery_market_quotes; shipment public.delivery_cloud_orders; msg public.delivery_market_messages;
  d jsonb:=p_payload; result jsonb; snapshot jsonb; group_row jsonb; item jsonb;
  cart_version integer; qty integer; product_key uuid; requested text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into actor from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  if (actor.user_id is null or actor.blocked) and not
    (p_action in ('workspace','shop_moderate') and public.delivery_is_operator()) then
    raise sqlstate 'PT403' using message='Cần hồ sơ tài khoản đang hoạt động.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 then raise sqlstate 'PT400' using message='Dữ liệu không hợp lệ.'; end if;

  if p_action='catalog' then
    if length(coalesce(d->>'search',''))>160 or length(coalesce(d->>'category',''))>80 then raise sqlstate 'PT400' using message='Bộ lọc quá dài.'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from (
      select p.*,s.name as shop_name from public.delivery_market_products p
      join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant')
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d ? 'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid)
      order by p.id limit 50
    ) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action='workspace' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    result:=jsonb_build_object('shops',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
      (select * from public.delivery_market_shops where (owner_id=auth.uid() or d->>'moderation'='true' and public.delivery_is_operator())
        and (d->>'moderation' is distinct from 'true' or not(d ? 'after') or id>(d->>'after')::uuid) order by id limit 50) x),'[]'),
      'products',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
      (select p.* from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
        where s.owner_id=auth.uid() and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x),'[]'));
    snapshot:=result->case when d->>'moderation'='true' then 'shops' else 'products' end;
    return result||jsonb_build_object('next',case when jsonb_array_length(snapshot)=50 then jsonb_build_object('after',snapshot->49->>'id') end);
  elsif p_action='shop_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    if d-array['name','description','address','latitude','longitude','paused','version']<>'{}' or
      jsonb_typeof(d->'name') is distinct from 'string' or jsonb_typeof(d->'address') is distinct from 'string' or
      jsonb_typeof(d->'latitude') is distinct from 'number' or jsonb_typeof(d->'longitude') is distinct from 'number' or
      jsonb_typeof(d->'paused') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Thông tin cửa hàng không hợp lệ.'; end if;
    perform pg_advisory_xact_lock(hashtextextended('shop:'||auth.uid()::text,0));
    select * into sh from public.delivery_market_shops where owner_id=auth.uid() for update;
    if sh.id is not null and sh.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi. Hãy tải lại.'; end if;
    if sh.status='suspended' then raise sqlstate 'PT403' using message='Cửa hàng đang tạm khóa.'; end if;
    insert into public.delivery_market_shops(owner_id,name,description,address,latitude,longitude,paused)
      values(auth.uid(),btrim(d->>'name'),coalesce(d->>'description',''),btrim(d->>'address'),(d->>'latitude')::float8,(d->>'longitude')::float8,(d->>'paused')::boolean)
      on conflict(owner_id) do update set name=excluded.name,description=excluded.description,address=excluded.address,
        latitude=excluded.latitude,longitude=excluded.longitude,paused=excluded.paused,version=delivery_market_shops.version+1,
        status=case when delivery_market_shops.name=excluded.name and delivery_market_shops.address=excluded.address
          and delivery_market_shops.latitude=excluded.latitude and delivery_market_shops.longitude=excluded.longitude
          then delivery_market_shops.status else 'pending' end,updated_at=now() returning * into sh;
    return jsonb_build_object('shop',to_jsonb(sh));
  elsif p_action='shop_moderate' then
    if not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if d->>'status' not in ('active','suspended') or not(d ?& array['id','version','status']) then raise sqlstate 'PT400' using message='Trạng thái không hợp lệ.'; end if;
    update public.delivery_market_shops set status=d->>'status',version=version+1,updated_at=now()
      where id=(d->>'id')::uuid and version=(d->>'version')::integer returning * into sh;
    if not found then raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi hoặc không tồn tại.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'shop_moderate',sh.id,to_jsonb(sh));
    return jsonb_build_object('shop',to_jsonb(sh));
  elsif p_action='product_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    if d-array['id','shop_id','name','description','category','sku','image_url','price','stock','weight_kg','published','version']<>'{}' or
      jsonb_typeof(d->'price') is distinct from 'number' or jsonb_typeof(d->'stock') is distinct from 'number' or
      jsonb_typeof(d->'weight_kg') is distinct from 'number' or jsonb_typeof(d->'published') is distinct from 'boolean' or
      (d->>'stock')::numeric<>trunc((d->>'stock')::numeric) or (d->>'price')::numeric<>trunc((d->>'price')::numeric) then
      raise sqlstate 'PT400' using message='Giá và tồn kho cần là số nguyên hợp lệ.';
    end if;
    select * into sh from public.delivery_market_shops where id=(d->>'shop_id')::uuid and owner_id=auth.uid() for update;
    if not found or sh.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền sửa cửa hàng này.'; end if;
    product_key:=(d->>'id')::uuid;
    if product_key is null then raise sqlstate 'PT400' using message='Thiếu mã sản phẩm.'; end if;
    select * into previous from public.delivery_market_products where delivery_market_products.id=product_key for update;
    if previous.id is not null and (previous.shop_id<>sh.id or previous.version is distinct from (d->>'version')::integer) then
      raise sqlstate 'PT409' using message='Sản phẩm đã thay đổi hoặc thuộc cửa hàng khác.';
    end if;
    if previous.id is null and d->>'version' is not null then raise sqlstate 'PT409' using message='Sản phẩm không còn tồn tại.'; end if;
    insert into public.delivery_market_products(id,shop_id,name,description,category,sku,image_url,price,stock,weight_kg,published)
      values(product_key,sh.id,btrim(d->>'name'),coalesce(d->>'description',''),btrim(d->>'category'),btrim(d->>'sku'),coalesce(d->>'image_url',''),
        (d->>'price')::integer,(d->>'stock')::integer,(d->>'weight_kg')::numeric,(d->>'published')::boolean)
      on conflict on constraint delivery_market_products_pkey do update set name=excluded.name,description=excluded.description,
        category=excluded.category,sku=excluded.sku,image_url=excluded.image_url,price=excluded.price,stock=excluded.stock,
        weight_kg=excluded.weight_kg,published=excluded.published,version=delivery_market_products.version+1,updated_at=now()
      returning * into prod;
    if prod.stock<>coalesce(previous.stock,0) then
      insert into public.delivery_market_stock(product_id,actor_id,delta,reason) values(prod.id,auth.uid(),prod.stock-coalesce(previous.stock,0),'merchant_adjust');
    end if;
    return jsonb_build_object('product',to_jsonb(prod));
  elsif p_action in ('cart','cart_set') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    insert into public.delivery_market_carts(user_id) values(auth.uid()) on conflict do nothing;
    select version into cart_version from public.delivery_market_carts where user_id=auth.uid() for update;
    if p_action='cart_set' then
      if jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) or
        (d->>'quantity')::numeric not between 0 and 99 then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
      if cart_version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy tải lại.'; end if;
      qty:=(d->>'quantity')::integer; product_key:=(d->>'product_id')::uuid;
      if qty=0 then delete from public.delivery_market_cart_items where user_id=auth.uid() and product_id=product_key;
      else
        select * into prod from public.delivery_market_products where delivery_market_products.id=product_key;
        select * into sh from public.delivery_market_shops where delivery_market_shops.id=prod.shop_id;
        if prod.id is null or not prod.published or prod.stock<qty or sh.status<>'active' or sh.paused or sh.owner_id=auth.uid() or
          not exists(select 1 from public.delivery_cloud_accounts where user_id=sh.owner_id and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
          raise sqlstate 'PT409' using message='Sản phẩm không thể mua hoặc không đủ tồn kho.';
        end if;
        if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid() and product_id=product_key) and
          (select count(*) from public.delivery_market_cart_items where user_id=auth.uid())>=50 then raise sqlstate 'PT400' using message='Giỏ hàng hỗ trợ tối đa 50 sản phẩm.'; end if;
        insert into public.delivery_market_cart_items values(auth.uid(),product_key,qty) on conflict(user_id,product_id) do update set quantity=excluded.quantity;
      end if;
      update public.delivery_market_carts set version=version+1 where user_id=auth.uid() returning version into cart_version;
    end if;
    return jsonb_build_object('version',cart_version,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.shop_id,x.id) from
      (select p.*,c.quantity,s.name as shop_name,s.status as shop_status,s.paused from public.delivery_market_cart_items c
        join public.delivery_market_products p on p.id=c.product_id join public.delivery_market_shops s on s.id=p.shop_id where c.user_id=auth.uid()) x),'[]'));
  elsif p_action in ('quote','checkout') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    if p_action='quote' then
      snapshot:=public.delivery_market_snapshot((d->>'address_id')::uuid);
      insert into public.delivery_market_quotes(owner_id,snapshot) values(auth.uid(),snapshot) returning * into quote;
      return jsonb_build_object('quote',to_jsonb(quote)-'owner_id');
    end if;
    if d-array['quote_id','request_key']<>'{}' or not(d ?& array['quote_id','request_key']) then raise sqlstate 'PT400' using message='Yêu cầu đặt hàng không hợp lệ.'; end if;
    select * into purchase from public.delivery_market_purchases where owner_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if purchase.quote_id<>(d->>'quote_id')::uuid then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho báo giá khác.'; end if;
      return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');
    end if;
    select * into quote from public.delivery_market_quotes where delivery_market_quotes.id=(d->>'quote_id')::uuid and owner_id=auth.uid() for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy báo giá.'; end if;
    -- A consumed quote always resolves to the existing purchase, even after restart.
    select * into purchase from public.delivery_market_purchases where quote_id=quote.id and owner_id=auth.uid();
    if found then return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key'); end if;
    if quote.expires_at<=now() then raise sqlstate 'PT409' using message='Báo giá đã hết hạn. Hãy lấy báo giá mới.'; end if;
    -- Lock in deterministic order before validating a fresh snapshot and reserving stock.
    perform 1 from public.delivery_market_shops where delivery_market_shops.id in
      (select (g->>'shop_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g) order by delivery_market_shops.id for share;
    perform 1 from public.delivery_cloud_accounts where user_id in
      (select (g->>'merchant_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g) order by user_id for share;
    perform 1 from public.delivery_market_products where delivery_market_products.id in
      (select (i->>'product_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i) order by delivery_market_products.id for update;
    perform 1 from public.delivery_cloud_addresses where delivery_cloud_addresses.id=(quote.snapshot->>'address_id')::uuid for share;
    perform 1 from public.delivery_cloud_pricing where delivery_cloud_pricing.id for share;
    snapshot:=public.delivery_market_snapshot((quote.snapshot->>'address_id')::uuid);
    if snapshot<>quote.snapshot then raise sqlstate 'PT409' using message='Giá, giỏ hàng hoặc địa chỉ đã thay đổi. Hãy xác nhận báo giá mới.'; end if;
    insert into public.delivery_market_purchases(owner_id,request_key,quote_id,snapshot,total)
      values(auth.uid(),(d->>'request_key')::uuid,quote.id,snapshot,(snapshot->>'total')::integer) returning * into purchase;
    for group_row in select * from jsonb_array_elements(snapshot->'shops') loop
      insert into public.delivery_market_shop_orders(purchase_id,shop_id,owner_id,merchant_id,snapshot)
        values(purchase.id,(group_row->>'shop_id')::uuid,auth.uid(),(group_row->>'merchant_id')::uuid,group_row) returning * into so;
      for item in select * from jsonb_array_elements(group_row->'items') loop
        update public.delivery_market_products set stock=stock-(item->>'quantity')::integer,version=version+1,updated_at=now()
          where delivery_market_products.id=(item->>'product_id')::uuid and stock>=(item->>'quantity')::integer;
        if not found then raise sqlstate 'PT409' using message='Sản phẩm không đủ tồn kho.'; end if;
        insert into public.delivery_market_stock(product_id,actor_id,delta,reason,reference_id)
          values((item->>'product_id')::uuid,auth.uid(),-(item->>'quantity')::integer,'purchase_allocate',so.id);
      end loop;
      insert into public.delivery_market_events(order_id,actor_id,action) values(so.id,auth.uid(),'created');
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'new_order');
    end loop;
    delete from public.delivery_market_cart_items where user_id=auth.uid();
    update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');
  elsif p_action='orders' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from (
      select o.*,p.payment_status,del.status as delivery_status,del.tracking_code
      from public.delivery_market_shop_orders o join public.delivery_market_purchases p on p.id=o.purchase_id
      left join public.delivery_cloud_orders del on del.id=o.delivery_id
      where (case when d->>'workspace'='merchant' then o.merchant_id=auth.uid() and public.delivery_cloud_has_membership(actor.user_id,'merchant') else o.owner_id=auth.uid() end)
        and (not(d ? 'after') or o.id>(d->>'after')::uuid) order by o.id limit 50) x;
    return jsonb_build_object('orders',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action in ('order_action','messages','message_send') then
    select * into so from public.delivery_market_shop_orders where delivery_market_shop_orders.id=(d->>'order_id')::uuid
      and (owner_id=auth.uid() or merchant_id=auth.uid() and public.delivery_cloud_has_membership(actor.user_id,'merchant')) for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
    if p_action='order_action' then
      requested:=d->>'action';
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if requested not in ('accept','ready','cancel') or requested is null then raise sqlstate 'PT400' using message='Thao tác không hợp lệ.'; end if;
      if requested in ('accept','ready') and (so.merchant_id<>auth.uid() or not public.delivery_cloud_has_membership(actor.user_id,'merchant')) then raise sqlstate 'PT403' using message='Chỉ cửa hàng xử lý đơn mua hàng.'; end if;
      if requested='accept' and so.state='pending' then so.state:='accepted';
      elsif requested='ready' and so.state='accepted' then
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id),so.snapshot->'details',
            (so.snapshot->>'distance_meters')::integer,(so.snapshot->>'shipping_fee')::integer,
            (so.snapshot->>'subtotal')::integer,(so.snapshot->>'pricing_version')::integer,true) returning * into shipment;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code);
        insert into public.delivery_live_members values(shipment.tracking_code,so.owner_id,'customer'),(shipment.tracking_code,so.merchant_id,'merchant');
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        so.state:='ready'; so.delivery_id:=shipment.id;
      elsif requested='cancel' and so.state in ('pending','accepted') and length(btrim(coalesce(d->>'reason',''))) between 3 and 500 and
        (so.merchant_id=auth.uid() or so.state='pending') then
        perform 1 from public.delivery_market_products where delivery_market_products.id in
          (select (i->>'product_id')::uuid from jsonb_array_elements(so.snapshot->'items') i) order by delivery_market_products.id for update;
        for item in select * from jsonb_array_elements(so.snapshot->'items') loop
          update public.delivery_market_products set stock=stock+(item->>'quantity')::integer,version=version+1,updated_at=now()
            where delivery_market_products.id=(item->>'product_id')::uuid;
          insert into public.delivery_market_stock(product_id,actor_id,delta,reason,reference_id)
            values((item->>'product_id')::uuid,auth.uid(),(item->>'quantity')::integer,'cancel_release',so.id);
        end loop;
        so.state:='cancelled'; so.reason:=btrim(d->>'reason');
      else raise sqlstate 'PT409' using message='Không thể thực hiện thao tác ở trạng thái này.';
      end if;
      update public.delivery_market_shop_orders set state=so.state,delivery_id=so.delivery_id,reason=so.reason,
        version=version+1,updated_at=now() where delivery_market_shop_orders.id=so.id returning * into so;
      insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),requested,so.reason);
      insert into public.delivery_market_notifications(user_id,order_id,kind)
        values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,requested);
      return jsonb_build_object('order',to_jsonb(so));
    end if;
    if p_action='message_send' then
      if jsonb_typeof(d->'body') is distinct from 'string' or length(btrim(d->>'body')) not between 1 and 2000 or d->>'request_key' is null then
        raise sqlstate 'PT400' using message='Nội dung tin nhắn không hợp lệ.'; end if;
      perform pg_advisory_xact_lock(hashtextextended('message:'||auth.uid()::text,0));
      select * into msg from public.delivery_market_messages where actor_id=auth.uid() and request_key=(d->>'request_key')::uuid;
      if msg.id is not null then
        if msg.order_id<>so.id or msg.body<>btrim(d->>'body') then raise sqlstate 'PT409' using message='Mã tin nhắn đã được dùng.'; end if;
      else
        if (select count(*) from public.delivery_market_messages where actor_id=auth.uid() and created_at>now()-interval '1 minute')>=20 then
          raise sqlstate 'PT409' using message='Bạn gửi quá nhiều tin nhắn. Vui lòng chờ.'; end if;
        insert into public.delivery_market_messages(order_id,actor_id,body,request_key) values(so.id,auth.uid(),btrim(d->>'body'),(d->>'request_key')::uuid);
        insert into public.delivery_market_notifications(user_id,order_id,kind)
          values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'message');
      end if;
    end if;
    select coalesce(jsonb_agg(to_jsonb(x)-'request_key' order by x.created_at,x.id),'[]') into result from
      (select * from public.delivery_market_messages where order_id=so.id and (not(d ? 'before') or
        (created_at,id)<((d->>'before')::timestamptz,coalesce((d->>'before_id')::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by created_at desc,id desc limit 50) x;
    return jsonb_build_object('messages',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('before',result->0->>'created_at','before_id',result->0->>'id') end,
      'events',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from
        (select * from public.delivery_market_events where order_id=so.id order by created_at desc,id desc limit 50) x),'[]'));
  elsif p_action in ('notifications','notification_read') then
    if p_action='notification_read' then
      update public.delivery_market_notifications set read_at=coalesce(read_at,now()) where delivery_market_notifications.id=(d->>'id')::uuid and user_id=auth.uid();
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') into result from
      (select * from public.delivery_market_notifications where user_id=auth.uid() and (not(d ? 'before') or
        (created_at,id)<((d->>'before')::timestamptz,coalesce((d->>'before_id')::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by created_at desc,id desc limit 50) x;
    return jsonb_build_object('notifications',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('before',result->49->>'created_at','before_id',result->49->>'id') end);
  else raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end $$;

create or replace function public.delivery_market_operations(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; a public.delivery_cloud_accounts; so public.delivery_market_shop_orders;
  prod public.delivery_market_products; ret public.delivery_market_returns; f public.delivery_market_finance; existing public.delivery_market_commands;
  result jsonb; item jsonb; token text; jid uuid; qty integer; cv integer; collected bigint; refunded bigint; settled bigint;
  due bigint; goods bigint; freight bigint; used bigint; op boolean; k uuid; requested text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  op:=public.delivery_is_operator();
  if a.blocked or (a.user_id is null and not op) then raise sqlstate 'PT403' using message='Cần tài khoản đang hoạt động.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 then raise sqlstate 'PT400' using message='Dữ liệu không hợp lệ.'; end if;

  if p_action in ('favorites','favorite_set','product_details') then
    if p_action='favorite_set' then
      if jsonb_typeof(d->'enabled') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Lựa chọn không hợp lệ.'; end if;
      if (d->>'enabled')::boolean then
        if not exists(select 1 from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
          join public.delivery_cloud_accounts m on m.user_id=s.owner_id where p.id=(d->>'product_id')::uuid
          and p.published and s.status='active' and not s.paused and not m.blocked and public.delivery_cloud_has_membership(m.user_id,'merchant')) then
          raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;
        insert into public.delivery_market_favorites(user_id,product_id) values(auth.uid(),(d->>'product_id')::uuid) on conflict do nothing;
      else delete from public.delivery_market_favorites where user_id=auth.uid() and product_id=(d->>'product_id')::uuid;
      end if;
    end if;
    if p_action='product_details' then
      select p.* into prod from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
        join public.delivery_cloud_accounts m on m.user_id=s.owner_id where p.id=(d->>'product_id')::uuid
        and p.published and s.status='active' and not s.paused and public.delivery_cloud_has_membership(m.user_id,'merchant') and not m.blocked;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;
      return jsonb_build_object('product',to_jsonb(prod),'favorite',exists(select 1 from public.delivery_market_favorites where user_id=auth.uid() and product_id=prod.id),
        'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from
          (select id,rating,body,created_at from public.delivery_market_reviews where product_id=prod.id and not hidden order by created_at desc,id desc limit 50) r),'[]'));
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from
      (select p.*,s.name as shop_name from public.delivery_market_favorites fav join public.delivery_market_products p on p.id=fav.product_id
        join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
        where fav.user_id=auth.uid() and p.published and s.status='active' and not s.paused and public.delivery_cloud_has_membership(m.user_id,'merchant') and not m.blocked
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action='operations' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    result:=jsonb_build_object('finance',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
      (select * from public.delivery_market_finance where (not(d ? 'before') or (created_at,id)<((d->>'before')::timestamptz,(d->>'before_id')::uuid)) order by created_at desc,id desc limit 50) x),'[]'),
      'returns',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
        (select * from public.delivery_market_returns where state in ('requested','escalated')
          and (not(d ? 'before_returns') or (created_at,id)<((d->>'before_returns')::timestamptz,(d->>'before_return_id')::uuid)) order by created_at desc,id desc limit 50) x),'[]'),
      'jobs',jsonb_build_object('pending',(select count(*) from public.delivery_market_jobs where state='pending'),
        'failed',(select count(*) from public.delivery_market_jobs where state='failed'),
        'overdue',(select count(*) from public.delivery_market_jobs where state='pending' and run_at<=now())),
      'failed_jobs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.delivery_market_jobs where state='failed' order by run_at,id limit 50) x),'[]'));
    return result||jsonb_build_object('next',case when jsonb_array_length(result->'finance')=50 then
      jsonb_build_object('before',result->'finance'->49->>'created_at','before_id',result->'finance'->49->>'id') end,
      'returns_next',case when jsonb_array_length(result->'returns')=50 then
      jsonb_build_object('before_returns',result->'returns'->49->>'created_at','before_return_id',result->'returns'->49->>'id') end);
  elsif p_action in ('job_retry','jobs_run') then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if p_action='jobs_run' then return public.delivery_market_run_jobs(25); end if;
    update public.delivery_market_jobs set state='pending',attempts=0,run_at=now(),last_error=null,completed_at=null where id=(d->>'id')::uuid and state='failed' returning id into k;
    if k is null then raise sqlstate 'PT409' using message='Tác vụ đã thay đổi hoặc không ở trạng thái lỗi.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'market_job_retry',k,jsonb_build_object('state','pending'));
    return jsonb_build_object('ok',true);
  elsif p_action='review_moderate' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if jsonb_typeof(d->'hidden') is distinct from 'boolean' or length(btrim(coalesce(d->>'reason',''))) not between 3 and 500 then
      raise sqlstate 'PT400' using message='Cần lý do kiểm duyệt.'; end if;
    update public.delivery_market_reviews set hidden=(d->>'hidden')::boolean where id=(d->>'id')::uuid;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'review_moderate',(d->>'id')::uuid,d);
    return jsonb_build_object('ok',true);
  elsif p_action='finance_action' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    select order_id into k from public.delivery_market_finance where id=(d->>'id')::uuid;
    -- Every financial mutation locks its order first, then the request.
    select * into so from public.delivery_market_shop_orders where id=k for update;
    select * into f from public.delivery_market_finance where id=(d->>'id')::uuid for update;
    if f.id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu tài chính.'; end if;
    if f.proposer=auth.uid() then raise sqlstate 'PT403' using message='Người đề nghị không được tự duyệt hoặc xác nhận chi tiền.'; end if;
    if f.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Yêu cầu đã thay đổi.'; end if;
    requested:=d->>'action';
    if requested in ('approve','reject') and length(btrim(coalesce(d->>'reason',''))) not between 3 and 1000 then raise sqlstate 'PT400' using message='Cần lý do duyệt/từ chối.'; end if;
    if requested='approve' and f.state='requested' then
      update public.delivery_market_finance set state='approved',approver=auth.uid(),version=version+1 where id=f.id returning * into f;
    elsif requested='reject' and f.state in ('requested','approved') then
      update public.delivery_market_finance set state='rejected',approver=auth.uid(),version=version+1 where id=f.id returning * into f;
    elsif requested='complete' and f.state='approved' then
      if length(btrim(coalesce(d->>'evidence',''))) not between 3 and 500 then raise sqlstate 'PT400' using message='Cần mã chứng từ thu/chi thực tế.'; end if;
      goods:=(so.snapshot->>'subtotal')::bigint; freight:=(so.snapshot->>'shipping_fee')::bigint; due:=goods+freight;
      select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
        into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
      if f.kind='collection' and (so.delivered_at is null or so.state='cancelled' or f.amount<>due or collected<>0) then
        raise sqlstate 'PT409' using message='Chỉ xác nhận đủ tiền COD một lần sau giao thành công.';
      elsif f.kind='refund' then
        select * into ret from public.delivery_market_returns where id=f.return_id and order_id=so.id;
        select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state='completed';
        select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=ret.product_id;
        if ret.id is null or ret.state<>'received' or f.amount>ret.quantity*(item->>'unit_price')::bigint-used
          or f.amount>least(goods-refunded-settled,collected-refunded-settled) then raise sqlstate 'PT409' using message='Khoản hoàn vượt mức hoặc chưa nhận hàng trả.'; end if;
      elsif f.kind='settlement' and (f.amount>least(goods-refunded-settled,collected-refunded-settled-freight) or exists
        (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=r.product_id) v on true
          where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
          r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))
        or so.delivered_at is null or so.delivered_at>now()-interval '7 days') then
        raise sqlstate 'PT409' using message='Chưa đủ điều kiện đối soát shop: tiền khả dụng, hạn hậu mãi hoặc tranh chấp.';
      end if;
      update public.delivery_market_finance set state='completed',completion_evidence=btrim(d->>'evidence'),completed_at=now(),version=version+1 where id=f.id returning * into f;
      insert into public.delivery_market_journals(finance_id,order_id) values(f.id,so.id) returning id into jid;
      if f.kind='collection' then
        insert into public.delivery_market_ledger values(jid,'cash_clearing',due),(jid,'merchant_payable',-goods);
        if freight>0 then insert into public.delivery_market_ledger values(jid,'shipping_revenue',-freight); end if;
      else insert into public.delivery_market_ledger values(jid,'cash_clearing',-f.amount),(jid,'merchant_payable',f.amount);
      end if;
      update public.delivery_market_purchases p set payment_status=case when
        exists(select 1 from public.delivery_market_shop_orders o where o.purchase_id=p.id and (o.state='cancelled' or not exists
          (select 1 from public.delivery_market_finance c where c.order_id=o.id and c.kind='collection' and c.state='completed')))
        or exists(select 1 from public.delivery_market_finance c join public.delivery_market_shop_orders o on o.id=c.order_id where o.purchase_id=p.id and c.kind='refund' and c.state='completed') then 'REVIEW' else 'PAID' end
        where p.id=so.purchase_id;
    else raise sqlstate 'PT409' using message='Không thể chuyển trạng thái yêu cầu tài chính.';
    end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'market_finance_'||requested,f.id,to_jsonb(f)||jsonb_build_object('decision_reason',d->>'reason'));
    return jsonb_build_object('finance',to_jsonb(f));
  end if;

  select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid
    and (owner_id=auth.uid() or merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant') or op or exists
      (select 1 from public.delivery_cloud_orders o where o.id=delivery_id and o.driver_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'driver'))) for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
  if p_action='order_services' then
    if not op and so.owner_id<>auth.uid() and not (so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant')) then raise sqlstate 'PT403' using message='Không có quyền xem hậu mãi của đơn này.'; end if;
    select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    return jsonb_build_object('order',to_jsonb(so),'collected',collected,'refunded',refunded,'settled',settled,
      'returns',coalesce((select jsonb_agg(to_jsonb(r) order by created_at,id) from public.delivery_market_returns r where order_id=so.id),'[]'),
      'reviews',coalesce((select jsonb_agg(to_jsonb(r)-'user_id' order by created_at,id) from public.delivery_market_reviews r where order_id=so.id),'[]'),
      'finance',coalesce((select jsonb_agg(to_jsonb(r)-'evidence'-'completion_evidence'-'request_key' order by created_at,id) from public.delivery_market_finance r where order_id=so.id),'[]'),
      'shares',case when so.owner_id=auth.uid() then coalesce((select jsonb_agg(to_jsonb(s)-'token_hash'-'owner_id' order by created_at,id) from public.delivery_market_shares s where order_id=so.id and revoked_at is null and expires_at>now()),'[]') else '[]'::jsonb end);
  elsif p_action in ('tracking_share','tracking_revoke') then
    if so.owner_id<>auth.uid() then raise sqlstate 'PT403' using message='Chỉ người mua quản lý chia sẻ.'; end if;
    if p_action='tracking_revoke' then
      update public.delivery_market_shares set revoked_at=coalesce(revoked_at,now()) where order_id=so.id and id=(d->>'id')::uuid;
      return jsonb_build_object('ok',true);
    end if;
    if (select count(*) from public.delivery_market_shares where order_id=so.id and revoked_at is null and expires_at>now())>=5 then raise sqlstate 'PT409' using message='Tối đa 5 liên kết còn hiệu lực.'; end if;
    token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
    insert into public.delivery_market_shares(order_id,owner_id,token_hash,expires_at) values(so.id,auth.uid(),encode(sha256(convert_to(token,'UTF8')),'hex'),now()+interval '24 hours') returning id into k;
    return jsonb_build_object('id',k,'token',token,'expires_at',now()+interval '24 hours');
  elsif p_action='reorder' then
    if so.owner_id<>auth.uid() then raise sqlstate 'PT403' using message='Chỉ người mua được mua lại.'; end if;
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    select * into existing from public.delivery_market_commands where user_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if existing.action<>p_action or existing.payload<>d then raise sqlstate 'PT409' using message='Mã thao tác đã được dùng.'; end if;
      return existing.result;
    end if;
    insert into public.delivery_market_carts(user_id) values(auth.uid()) on conflict do nothing;
    select version into cv from public.delivery_market_carts where user_id=auth.uid() for update;
    if cv is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi. Hãy tải lại.'; end if;
    for item in select * from jsonb_array_elements(so.snapshot->'items') loop
      select * into prod from public.delivery_market_products where id=(item->>'product_id')::uuid for share;
      select coalesce((select quantity from public.delivery_market_cart_items where user_id=auth.uid() and product_id=prod.id),0)+(item->>'quantity')::integer into qty;
      perform public.delivery_marketplace('cart_set',jsonb_build_object('product_id',prod.id,'quantity',qty,'version',cv));
      cv:=cv+1;
    end loop;
    result:=public.delivery_marketplace('cart');
    insert into public.delivery_market_commands values(auth.uid(),(d->>'request_key')::uuid,p_action,d,result);
    return result;
  elsif p_action='review_save' then
    if so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '30 days' then
      raise sqlstate 'PT403' using message='Chỉ người mua đã nhận hàng trong 30 ngày được đánh giá.'; end if;
    if not exists(select 1 from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=(d->>'product_id')::uuid) then raise sqlstate 'PT400' using message='Sản phẩm không thuộc đơn.'; end if;
    if jsonb_typeof(d->'rating') is distinct from 'number' or (d->>'rating')::numeric<>trunc((d->>'rating')::numeric) then raise sqlstate 'PT400' using message='Số sao không hợp lệ.'; end if;
    select to_jsonb(r) into result from public.delivery_market_reviews r where order_id=so.id and product_id=(d->>'product_id')::uuid;
    if result is not null then
      if result->>'body'<>btrim(d->>'body') or (result->>'rating')::integer<>(d->>'rating')::integer then raise sqlstate 'PT409' using message='Sản phẩm đã được đánh giá.'; end if;
      return jsonb_build_object('review',result);
    end if;
    insert into public.delivery_market_reviews(order_id,product_id,user_id,rating,body) values(so.id,(d->>'product_id')::uuid,auth.uid(),(d->>'rating')::integer,btrim(d->>'body')) returning to_jsonb(delivery_market_reviews) into result;
    return jsonb_build_object('review',result);
  elsif p_action='return_request' then
    if so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '7 days' then raise sqlstate 'PT403' using message='Chỉ người mua yêu cầu trả trong 7 ngày sau nhận hàng.'; end if;
    select * into ret from public.delivery_market_returns where user_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if ret.order_id<>so.id or ret.product_id<>(d->>'product_id')::uuid or ret.quantity is distinct from (d->>'quantity')::integer or ret.reason is distinct from btrim(d->>'reason') then raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.'; end if;
      return jsonb_build_object('return',to_jsonb(ret));
    end if;
    if jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
    select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=(d->>'product_id')::uuid;
    select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and product_id=(d->>'product_id')::uuid and state<>'rejected';
    if item is null or (d->>'quantity')::integer+used>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Số lượng trả vượt số lượng đã mua còn lại.'; end if;
    if (select count(*) from public.delivery_market_returns where order_id=so.id)>=100 then raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu trả hàng. Cần quản trị viên kiểm tra.'; end if;
    insert into public.delivery_market_returns(order_id,product_id,user_id,quantity,reason,request_key) values(so.id,(d->>'product_id')::uuid,auth.uid(),(d->>'quantity')::integer,btrim(d->>'reason'),(d->>'request_key')::uuid) returning * into ret;
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'return_requested');
    return jsonb_build_object('return',to_jsonb(ret));
  elsif p_action='return_action' then
    select * into ret from public.delivery_market_returns where id=(d->>'id')::uuid and order_id=so.id for update;
    if ret.id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu trả hàng.'; end if;
    if ret.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Yêu cầu đã thay đổi.'; end if;
    requested:=d->>'action';
    if length(btrim(coalesce(d->>'response',''))) not between 3 and 1000 then raise sqlstate 'PT400' using message='Cần phản hồi/lý do xử lý.'; end if;
    if requested='escalate' and ret.state='rejected' and so.owner_id=auth.uid() then
      select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=ret.product_id;
      select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and product_id=ret.product_id and state<>'rejected';
      if used+ret.quantity>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Đã có yêu cầu khác cho số lượng này.'; end if;
      requested:='escalated';
    elsif requested in ('approve','reject') and (so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant') and ret.state='requested' or op and ret.state in ('requested','escalated')) then
      requested:=case requested when 'approve' then 'approved' else 'rejected' end;
    elsif requested='receive' and ret.state='approved' and (so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant') or op) then requested:='received';
    else raise sqlstate 'PT403' using message='Không có quyền chuyển trạng thái trả hàng.';
    end if;
    update public.delivery_market_returns set state=requested,response=btrim(d->>'response'),version=version+1,updated_at=now() where id=ret.id returning * into ret;
    insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'return_'||requested,btrim(d->>'response'));
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'return_'||requested);
    return jsonb_build_object('return',to_jsonb(ret));
  elsif p_action='finance_request' then
    requested:=d->>'kind';
    if requested not in ('collection','refund','settlement') or requested is null then raise sqlstate 'PT400' using message='Loại yêu cầu không hợp lệ.'; end if;
    if not op and not (requested='settlement' and so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant')) and not
      (requested='collection' and public.delivery_cloud_has_membership(a.user_id,'driver') and exists(select 1 from public.delivery_cloud_orders where id=so.delivery_id and driver_id=auth.uid())) and not
      (requested='refund' and so.owner_id=auth.uid()) then raise sqlstate 'PT403' using message='Không có quyền đề nghị khoản thu/chi này.'; end if;
    if jsonb_typeof(d->'amount') is distinct from 'number' or (d->>'amount')::numeric<>trunc((d->>'amount')::numeric) then raise sqlstate 'PT400' using message='Số tiền cần là số nguyên.'; end if;
    select * into f from public.delivery_market_finance where proposer=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if f.order_id<>so.id or f.kind<>requested or f.amount is distinct from (d->>'amount')::integer or f.reason is distinct from btrim(d->>'reason') or f.evidence is distinct from btrim(d->>'evidence') or f.return_id is distinct from (d->>'return_id')::uuid then raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.'; end if;
      return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
    end if;
    if (select count(*) from public.delivery_market_finance where order_id=so.id)>=100 then raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu thu/chi. Cần quản trị viên kiểm tra.'; end if;
    goods:=(so.snapshot->>'subtotal')::bigint; freight:=(so.snapshot->>'shipping_fee')::bigint; due:=goods+freight;
    select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    if requested='collection' and (so.delivered_at is null or (d->>'amount')::bigint<>due or exists(select 1 from public.delivery_market_finance where order_id=so.id and kind='collection' and state<>'rejected')) then raise sqlstate 'PT409' using message='COD chỉ được đề nghị đủ tiền một lần sau giao hàng.'; end if;
    if requested='refund' then
      select * into ret from public.delivery_market_returns where id=(d->>'return_id')::uuid and order_id=so.id and state='received';
      select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=ret.product_id;
      select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state<>'rejected';
      if ret.id is null or (d->>'amount')::bigint>ret.quantity*(item->>'unit_price')::bigint-used or (d->>'amount')::bigint>least(goods-refunded-settled,collected-refunded-settled) then raise sqlstate 'PT409' using message='Chưa nhận hàng trả hoặc khoản hoàn vượt mức.'; end if;
    elsif requested='settlement' and ((d->>'amount')::bigint>least(goods-refunded-settled,collected-refunded-settled-freight) or so.delivered_at is null or so.delivered_at>now()-interval '7 days' or exists
      (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=r.product_id) v on true
        where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
        r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))) then raise sqlstate 'PT409' using message='Chưa có tiền hàng khả dụng để đối soát.';
    end if;
    insert into public.delivery_market_finance(order_id,kind,amount,return_id,proposer,reason,evidence,request_key)
      values(so.id,requested,(d->>'amount')::integer,(d->>'return_id')::uuid,auth.uid(),btrim(d->>'reason'),btrim(d->>'evidence'),(d->>'request_key')::uuid) returning * into f;
    return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
  else raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end$$;

notify pgrst, 'reload schema';
commit;
