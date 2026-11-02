-- Additive operator account governance: full Auth + profile visibility,
-- profile correction, direct partner grant, operator role management and audit.
-- Safe to reapply; seeds no rows.
begin;

create or replace function public.delivery_cloud_auth_providers(p_user uuid,p_user_json jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_providers jsonb:='[]'::jsonb;
begin
  if to_regclass('auth.identities') is not null then
    execute 'select coalesce(jsonb_agg(distinct provider::text order by provider::text),''[]''::jsonb) from auth.identities where user_id=$1'
      into v_providers using p_user;
  end if;
  if jsonb_array_length(v_providers)=0 then
    if jsonb_typeof(p_user_json#>'{raw_app_meta_data,providers}')='array' then
      v_providers:=p_user_json#>'{raw_app_meta_data,providers}';
    elsif (p_user_json#>>'{raw_app_meta_data,provider}') is not null then
      v_providers:=jsonb_build_array(p_user_json#>>'{raw_app_meta_data,provider}');
    end if;
  end if;
  return v_providers;
end; $$;
revoke all on function public.delivery_cloud_auth_providers(uuid,jsonb) from public,anon,authenticated;

create or replace function public.delivery_cloud_admin_account_row(p_user uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'user_id',u.id,
    'email',coalesce(uj.j->>'email',''),
    'email_confirmed',(uj.j->>'email_confirmed_at') is not null,
    'auth_providers',public.delivery_cloud_auth_providers(u.id,uj.j),
    'created_at',uj.j->>'created_at',
    'last_sign_in_at',uj.j->>'last_sign_in_at',
    'has_profile',a.user_id is not null,
    'full_name',coalesce(a.full_name,nullif(btrim(coalesce(uj.j#>>'{raw_user_meta_data,full_name}',uj.j#>>'{raw_user_meta_data,name}','')),''),''),
    'phone',coalesce(a.phone,''),
    'role',coalesce(a.role,'customer'),
    'blocked',coalesce(a.blocked,false),
    'updated_at',a.updated_at,
    'is_operator',coalesce(ap.role='operator',false),
    'approved_roles',coalesce((select jsonb_agg(m.role order by m.role) from public.delivery_cloud_memberships m
      where m.user_id=u.id and m.state='active'),'[]'::jsonb),
    'requested_role',(select m.role from public.delivery_cloud_memberships m
      where m.user_id=u.id and m.state='pending' order by m.role limit 1),
    'memberships',coalesce((select jsonb_agg(to_jsonb(m)-'user_id'-'reviewed_by' order by m.role)
      from public.delivery_cloud_memberships m where m.user_id=u.id),'[]'::jsonb),
    'coin_balance',coalesce((select w.balance from public.delivery_market_coin_wallets w where w.user_id=u.id),0),
    'shops_count',(select count(*)::integer from public.delivery_market_shops s where s.owner_id=u.id),
    'orders_count',(select count(*)::integer from public.delivery_cloud_orders o where o.owner_id=u.id),
    'driver_orders_count',(select count(*)::integer from public.delivery_cloud_orders o where o.driver_id=u.id),
    'active_driver_trips',(select count(*)::integer from public.delivery_cloud_orders o
      where o.driver_id=u.id and o.status not in ('delivered','returned','cancelled'))
  )
  from auth.users u
  cross join lateral (select to_jsonb(u) as j) uj
  left join public.delivery_cloud_accounts a on a.user_id=u.id
  left join public.delivery_api_profiles ap on ap.user_id=u.id
  where u.id=p_user;
$$;
revoke all on function public.delivery_cloud_admin_account_row(uuid) from public,anon,authenticated;

create or replace function public.delivery_cloud_membership(p_role text,p_decision text,p_user uuid default null,
  p_version integer default null,p_reason text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_user,auth.uid()); a public.delivery_cloud_accounts; previous public.delivery_cloud_memberships;
  changed public.delivery_cloud_memberships; next_state text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if p_role is null or p_role not in ('merchant','driver') or p_decision is null or
    p_decision not in ('request','grant','approve','reject','revoke') or p_reason is null or length(p_reason)>500 then
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
  elsif p_decision='grant' then
    if previous.user_id is null then
      if coalesce(p_version,0)<>0 then raise sqlstate 'PT409' using message='Quyền đã thay đổi. Vui lòng tải lại.'; end if;
      insert into public.delivery_cloud_memberships(user_id,role,state,version,reviewed_at,reviewed_by,reason)
        values(target,p_role,'active',1,now(),auth.uid(),btrim(p_reason))
        returning * into changed;
    else
      if p_version is distinct from previous.version then raise sqlstate 'PT409' using message='Quyền đã thay đổi. Vui lòng tải lại.'; end if;
      if previous.state='active' then raise sqlstate 'PT409' using message='Tài khoản đã được cấp quyền đối tác này.'; end if;
      update public.delivery_cloud_memberships
        set state='active',version=version+1,reviewed_at=now(),reviewed_by=auth.uid(),reason=btrim(p_reason)
        where user_id=target and role=p_role returning * into changed;
    end if;
    if a.role='customer' then
      update public.delivery_cloud_accounts set role=p_role where user_id=target;
    end if;
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
revoke all on function public.delivery_cloud_membership(text,text,uuid,integer,text) from public,anon;
grant execute on function public.delivery_cloud_membership(text,text,uuid,integer,text) to authenticated;

create or replace function public.delivery_cloud_admin_accounts(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb:=coalesce(p_payload,'{}'::jsonb);
  uid uuid:=auth.uid();
  v_target uuid;
  v_name text;
  v_phone text;
  v_reason text;
  v_blocked boolean;
  v_operator boolean;
  prev_acc public.delivery_cloud_accounts;
  next_acc public.delivery_cloud_accounts;
  prev_op text;
begin
  if uid is null then raise sqlstate 'PT401' using message='Cần đăng nhập cloud.'; end if;
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>4000 then
    raise sqlstate 'PT400' using message='Yêu cầu quản trị tài khoản không hợp lệ.';
  end if;

  if p_action='list' then
    if d<>'{}'::jsonb then raise sqlstate 'PT400' using message='Tham số danh sách tài khoản không hợp lệ.'; end if;
    return jsonb_build_object(
      'accounts',coalesce((
        select jsonb_agg(public.delivery_cloud_admin_account_row(q.id) order by q.sort_ts desc nulls last,q.id desc)
        from (
          select u.id,coalesce(a.updated_at,(nullif(to_jsonb(u)->>'created_at',''))::timestamptz) as sort_ts
          from auth.users u
          left join public.delivery_cloud_accounts a on a.user_id=u.id
          order by sort_ts desc nulls last,u.id desc
          limit 200
        ) q
      ),'[]'::jsonb),
      'summary',jsonb_build_object(
        'total_accounts',(select count(*)::integer from auth.users),
        'completed_profiles',(select count(*)::integer from public.delivery_cloud_accounts),
        'incomplete_profiles',(select count(*)::integer from auth.users u where not exists(select 1 from public.delivery_cloud_accounts a where a.user_id=u.id)),
        'operators',(select count(*)::integer from public.delivery_api_profiles where role='operator'),
        'active_drivers',(select count(*)::integer from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id=m.user_id where m.role='driver' and m.state='active' and not a.blocked),
        'active_merchants',(select count(*)::integer from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id=m.user_id where m.role='merchant' and m.state='active' and not a.blocked),
        'pending_memberships',(select count(*)::integer from public.delivery_cloud_memberships where state='pending'),
        'blocked_accounts',(select count(*)::integer from public.delivery_cloud_accounts where blocked)
      )
    );

  elsif p_action='detail' then
    if d-array['user_id']<>'{}'::jsonb or jsonb_typeof(d->'user_id') is distinct from 'string' then
      raise sqlstate 'PT400' using message='Mã tài khoản không hợp lệ.';
    end if;
    v_target:=(d->>'user_id')::uuid;
    if not exists(select 1 from auth.users where id=v_target) then
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản Cloud.';
    end if;
    return jsonb_build_object(
      'account',public.delivery_cloud_admin_account_row(v_target),
      'shops',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',s.id,'name',s.name,'status',s.status,'paused',s.paused,'address',s.address,'updated_at',s.updated_at
        ) order by s.updated_at desc,s.id desc)
        from public.delivery_market_shops s where s.owner_id=v_target
      ),'[]'::jsonb),
      'audit',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',au.id,'action',au.action,'actor_id',au.actor_id,
          'actor_email',coalesce(to_jsonb(actor_u)->>'email',''),
          'before_value',au.before_value,'after_value',au.after_value,'created_at',au.created_at
        ) order by au.created_at desc,au.id desc)
        from (select * from public.delivery_cloud_admin_audit where target_id=v_target order by created_at desc,id desc limit 25) au
        left join auth.users actor_u on actor_u.id=au.actor_id
      ),'[]'::jsonb)
    );

  elsif p_action='update_profile' then
    if d-array['user_id','full_name','phone','reason']<>'{}'::jsonb or
      jsonb_typeof(d->'user_id') is distinct from 'string' or
      jsonb_typeof(d->'full_name') is distinct from 'string' or
      jsonb_typeof(d->'phone') is distinct from 'string' or
      (d ? 'reason' and jsonb_typeof(d->'reason') is distinct from 'string') then
      raise sqlstate 'PT400' using message='Thông tin cập nhật hồ sơ không hợp lệ.';
    end if;
    v_target:=(d->>'user_id')::uuid;
    v_name:=btrim(d->>'full_name');
    v_phone:=btrim(d->>'phone');
    v_reason:=btrim(coalesce(d->>'reason',''));
    if length(v_name) not between 1 and 120 or v_phone !~ '^0[35789][0-9]{8}$' or length(v_reason)>500 then
      raise sqlstate 'PT400' using message='Họ tên (1-120 ký tự) hoặc số điện thoại Việt Nam (10 số) không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||v_target::text,0));
    if not exists(select 1 from auth.users where id=v_target) then
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản xác thực Cloud.';
    end if;
    select * into prev_acc from public.delivery_cloud_accounts where user_id=v_target for update;
    insert into public.delivery_cloud_accounts(user_id,full_name,phone)
      values(v_target,v_name,v_phone)
      on conflict(user_id) do update set full_name=excluded.full_name,phone=excluded.phone,updated_at=now()
      returning * into next_acc;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(uid,'account_profile',v_target,to_jsonb(prev_acc),to_jsonb(next_acc)||jsonb_build_object('reason',v_reason));
    return jsonb_build_object('account',public.delivery_cloud_admin_account_row(v_target));

  elsif p_action='set_blocked' then
    if d-array['user_id','blocked','reason']<>'{}'::jsonb or
      jsonb_typeof(d->'user_id') is distinct from 'string' or
      jsonb_typeof(d->'blocked') is distinct from 'boolean' or
      (d ? 'reason' and jsonb_typeof(d->'reason') is distinct from 'string') then
      raise sqlstate 'PT400' using message='Yêu cầu khóa/mở khóa tài khoản không hợp lệ.';
    end if;
    v_target:=(d->>'user_id')::uuid;
    v_blocked:=(d->>'blocked')::boolean;
    v_reason:=btrim(coalesce(d->>'reason',''));
    if length(v_reason)>500 then raise sqlstate 'PT400' using message='Ghi chú lý do tối đa 500 ký tự.'; end if;
    if v_target=uid and v_blocked then
      raise sqlstate 'PT409' using message='Không thể tự khóa tài khoản quản trị đang đăng nhập.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||v_target::text,0));
    select * into prev_acc from public.delivery_cloud_accounts where user_id=v_target for update;
    if not found then
      raise sqlstate 'PT404' using message='Tài khoản chưa hoàn tất hồ sơ Cloud. Hãy cập nhật họ tên và SĐT trước.';
    end if;
    update public.delivery_cloud_accounts set blocked=v_blocked,updated_at=now() where user_id=v_target returning * into next_acc;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(uid,case when v_blocked then 'account_block' else 'account_unblock' end,v_target,
        to_jsonb(prev_acc),to_jsonb(next_acc)||jsonb_build_object('reason',v_reason));
    return jsonb_build_object('account',public.delivery_cloud_admin_account_row(v_target));

  elsif p_action='set_operator' then
    if d-array['user_id','operator','reason']<>'{}'::jsonb or
      jsonb_typeof(d->'user_id') is distinct from 'string' or
      jsonb_typeof(d->'operator') is distinct from 'boolean' or
      jsonb_typeof(d->'reason') is distinct from 'string' then
      raise sqlstate 'PT400' using message='Yêu cầu phân quyền Operator không hợp lệ.';
    end if;
    v_target:=(d->>'user_id')::uuid;
    v_operator:=(d->>'operator')::boolean;
    v_reason:=btrim(d->>'reason');
    if length(v_reason) not between 3 and 500 then
      raise sqlstate 'PT400' using message='Cần nhập lý do phân quyền Operator ít nhất 3 ký tự.';
    end if;
    if v_target=uid and not v_operator then
      raise sqlstate 'PT409' using message='Không thể tự thu hồi quyền Operator của tài khoản đang đăng nhập.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||v_target::text,0));
    if not exists(select 1 from auth.users where id=v_target) then
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản xác thực Cloud.';
    end if;
    if v_operator and exists(select 1 from public.delivery_cloud_accounts where user_id=v_target and blocked) then
      raise sqlstate 'PT409' using message='Không thể cấp quyền Operator cho tài khoản đang bị khóa.';
    end if;
    select role into prev_op from public.delivery_api_profiles where user_id=v_target for update;
    insert into public.delivery_api_profiles(user_id,role)
      values(v_target,case when v_operator then 'operator' else 'user' end)
      on conflict(user_id) do update set role=excluded.role;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(uid,case when v_operator then 'operator_grant' else 'operator_revoke' end,v_target,
        jsonb_build_object('role',coalesce(prev_op,'user')),
        jsonb_build_object('role',case when v_operator then 'operator' else 'user' end,'reason',v_reason));
    return jsonb_build_object('account',public.delivery_cloud_admin_account_row(v_target));
  end if;

  raise sqlstate 'PT400' using message='Thao tác quản trị tài khoản không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_admin_accounts(text,jsonb) from public,anon;
grant execute on function public.delivery_cloud_admin_accounts(text,jsonb) to authenticated;

commit;
