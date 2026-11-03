-- Additive Cloud UI/Draft Sync, AI Chat History Persistence, Enriched Shipping Queue/Order Projections,
-- Live Shipping Telemetry/Chat/Checkpoints RPC, and Driver Reviews Read + Notifications.
-- Safe to reapply; seeds zero demo users, orders, messages, or reviews.
begin;

-- 1. Account-Scoped UI Preferences & Shipping Draft on delivery_cloud_accounts
alter table public.delivery_cloud_accounts
  add column if not exists ui_preferences jsonb not null default '{}'::jsonb;
alter table public.delivery_cloud_accounts
  add column if not exists shipping_draft jsonb;

alter table public.delivery_cloud_accounts
  drop constraint if exists delivery_cloud_accounts_ui_preferences_check;
alter table public.delivery_cloud_accounts
  add constraint delivery_cloud_accounts_ui_preferences_check
  check (
    jsonb_typeof(ui_preferences) = 'object'
    and octet_length(ui_preferences::text) <= 4096
  );

alter table public.delivery_cloud_accounts
  drop constraint if exists delivery_cloud_accounts_shipping_draft_check;
alter table public.delivery_cloud_accounts
  add constraint delivery_cloud_accounts_shipping_draft_check
  check (
    shipping_draft is null
    or (
      jsonb_typeof(shipping_draft) = 'object'
      and octet_length(shipping_draft::text) <= 16384
    )
  );

create or replace function public.delivery_cloud_preferences(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  a public.delivery_cloud_accounts;
  v_theme text;
  v_role text;
  v_patch jsonb := '{}'::jsonb;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 16000 then
    raise sqlstate 'PT400' using message = 'Dữ liệu tùy chọn không hợp lệ.';
  end if;

  if p_action = 'get' then
    select * into a from public.delivery_cloud_accounts where user_id = uid;
    return jsonb_build_object(
      'ui_preferences', coalesce(a.ui_preferences, '{}'::jsonb),
      'shipping_draft', a.shipping_draft
    );

  elsif p_action = 'save_ui' then
    if d - array['theme_mode', 'preferred_role'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Trường giao diện không hợp lệ.';
    end if;
    if d ? 'theme_mode' then
      v_theme := coalesce(d->>'theme_mode', '');
      if v_theme not in ('light', 'dark', 'system') then
        raise sqlstate 'PT400' using message = 'Chế độ giao diện không hợp lệ.';
      end if;
      v_patch := v_patch || jsonb_build_object('theme_mode', v_theme);
    end if;
    if d ? 'preferred_role' then
      v_role := coalesce(d->>'preferred_role', '');
      if v_role not in ('customer', 'driver', 'merchant', 'admin') then
        raise sqlstate 'PT400' using message = 'Chế độ vai trò không hợp lệ.';
      end if;
      v_patch := v_patch || jsonb_build_object('preferred_role', v_role);
    end if;

    select * into a from public.delivery_cloud_accounts where user_id = uid for update;
    if not found then
      return jsonb_build_object('ui_preferences', v_patch, 'persisted', false);
    end if;
    if a.blocked then
      raise sqlstate 'PT403' using message = 'Tài khoản đang khóa.';
    end if;
    update public.delivery_cloud_accounts
      set ui_preferences = coalesce(ui_preferences, '{}'::jsonb) || v_patch,
          updated_at = now()
      where user_id = uid
      returning * into a;
    return jsonb_build_object('ui_preferences', a.ui_preferences, 'persisted', true);

  elsif p_action = 'save_draft' then
    if not public.delivery_cloud_active() then
      raise sqlstate 'PT403' using message = 'Cần hồ sơ đang hoạt động.';
    end if;
    if d - array['draft'] <> '{}'::jsonb
       or (d->'draft' is not null and jsonb_typeof(d->'draft') not in ('object', 'null'))
       or octet_length(coalesce(d->'draft', '{}'::jsonb)::text) > 14000 then
      raise sqlstate 'PT400' using message = 'Bản nháp đơn hàng không hợp lệ.';
    end if;
    update public.delivery_cloud_accounts
      set shipping_draft = case
            when d->'draft' is null or jsonb_typeof(d->'draft') = 'null' or d->'draft' = '{}'::jsonb then null
            else (d->'draft') || jsonb_build_object('saved_at', now())
          end,
          updated_at = now()
      where user_id = uid;
    return jsonb_build_object('ok', true, 'updated_at', now());

  elsif p_action = 'clear_draft' then
    update public.delivery_cloud_accounts
      set shipping_draft = null,
          updated_at = now()
      where user_id = uid and shipping_draft is not null;
    return jsonb_build_object('ok', true);
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác tùy chọn không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_preferences(text, jsonb) from public, anon;
grant execute on function public.delivery_cloud_preferences(text, jsonb) to authenticated;

create or replace function public.delivery_cloud_orders_clear_draft() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  update public.delivery_cloud_accounts
    set shipping_draft = null
    where user_id = new.owner_id and shipping_draft is not null;
  return new;
end; $$;
revoke all on function public.delivery_cloud_orders_clear_draft() from public, anon, authenticated;

drop trigger if exists delivery_cloud_orders_clear_draft on public.delivery_cloud_orders;
create trigger delivery_cloud_orders_clear_draft
  after insert on public.delivery_cloud_orders
  for each row execute function public.delivery_cloud_orders_clear_draft();

create or replace function public.delivery_cloud_account_snapshot(p_user uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select (case when p_user = auth.uid() then to_jsonb(a) else to_jsonb(a) - 'shipping_draft' end) || jsonb_build_object(
    'identity_verified', (a.birth_date is not null and a.citizen_id is not null),
    'approved_roles', coalesce((select jsonb_agg(m.role order by m.role) from public.delivery_cloud_memberships m
      where m.user_id = a.user_id and m.state = 'active'), '[]'::jsonb),
    'memberships', coalesce((select jsonb_agg(to_jsonb(m) - 'user_id' - 'reviewed_by' order by m.role)
      from public.delivery_cloud_memberships m where m.user_id = a.user_id), '[]'::jsonb),
    'requested_role', (select m.role from public.delivery_cloud_memberships m where m.user_id = a.user_id and m.state = 'pending' order by m.role limit 1),
    'staff_shops', coalesce((select jsonb_agg(jsonb_build_object('shop_id', st.shop_id, 'shop_name', s.name, 'role', st.role) order by st.shop_id)
      from public.delivery_market_shop_staff st join public.delivery_market_shops s on s.id = st.shop_id
      join public.delivery_cloud_accounts oa on oa.user_id = s.owner_id
      where st.user_id = a.user_id and st.active and s.status <> 'suspended' and not oa.blocked
        and public.delivery_cloud_has_membership(s.owner_id, 'merchant')), '[]'::jsonb),
    'coin_balance', coalesce((select balance from public.delivery_market_coin_wallets w where w.user_id = a.user_id), 0),
    'unread_notifications', (select count(*)::integer from public.delivery_user_notifications n where n.user_id = a.user_id and n.read_at is null))
  from public.delivery_cloud_accounts a where a.user_id = p_user;
$$;
revoke all on function public.delivery_cloud_account_snapshot(uuid) from public, anon, authenticated;

-- 2. Cloud AI Assistant Conversation History
create table if not exists public.delivery_ai_chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (length(btrim(content)) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists delivery_ai_chat_messages_user_idx
  on public.delivery_ai_chat_messages(user_id, created_at desc, id desc);

alter table public.delivery_ai_chat_messages enable row level security;
revoke all on public.delivery_ai_chat_messages from public, anon, authenticated;

create or replace function public.delivery_cloud_ai_history(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  v_user_text text;
  v_assistant_text text;
  v_now timestamptz := now();
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 12000 then
    raise sqlstate 'PT400' using message = 'Dữ liệu hội thoại AI không hợp lệ.';
  end if;

  if p_action = 'list' then
    return jsonb_build_object(
      'messages', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', q.id,
            'role', q.role,
            'content', q.content,
            'created_at', q.created_at
          ) order by q.created_at asc, q.id asc
        )
        from (
          select id, role, content, created_at
          from public.delivery_ai_chat_messages
          where user_id = uid
          order by created_at desc, id desc
          limit 30
        ) q
      ), '[]'::jsonb)
    );

  elsif p_action = 'append_exchange' then
    if d - array['user_text', 'assistant_text'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Trường hội thoại AI không hợp lệ.';
    end if;
    v_user_text := btrim(coalesce(d->>'user_text', ''));
    v_assistant_text := btrim(coalesce(d->>'assistant_text', ''));
    if length(v_user_text) not between 1 and 2000 or length(v_assistant_text) not between 1 and 4000 then
      raise sqlstate 'PT400' using message = 'Độ dài tin nhắn AI không hợp lệ.';
    end if;
    insert into public.delivery_ai_chat_messages(user_id, role, content, created_at)
      values
        (uid, 'user', v_user_text, v_now),
        (uid, 'assistant', v_assistant_text, v_now + interval '1 millisecond');
    delete from public.delivery_ai_chat_messages
      where user_id = uid
        and id not in (
          select id from public.delivery_ai_chat_messages
          where user_id = uid
          order by created_at desc, id desc
          limit 40
        );
    return jsonb_build_object('ok', true);

  elsif p_action = 'clear' then
    delete from public.delivery_ai_chat_messages where user_id = uid;
    return jsonb_build_object('ok', true);
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác lịch sử AI không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_ai_history(text, jsonb) from public, anon;
grant execute on function public.delivery_cloud_ai_history(text, jsonb) to authenticated;

-- 3. Privacy-Preserving Coarse Area Helper & Enriched Order Projection
create or replace function public.delivery_coarse_area(p_address text) returns text
language plpgsql immutable set search_path='' as $$
declare
  parts text[];
  cleaned text[] := array[]::text[];
  seg text;
  n int;
begin
  if p_address is null or strpos(p_address, ',') = 0 then
    return null;
  end if;
  parts := string_to_array(p_address, ',');
  if coalesce(array_length(parts, 1), 0) < 2 then
    return null;
  end if;
  for i in 2..array_length(parts, 1) loop
    seg := btrim(parts[i]);
    if length(seg) > 0 and seg !~ '[0-9]{7,}' then
      cleaned := array_append(cleaned, left(seg, 60));
    end if;
  end loop;
  n := coalesce(array_length(cleaned, 1), 0);
  if n = 0 then
    return null;
  elsif n = 1 then
    return cleaned[1];
  else
    return cleaned[n - 1] || ', ' || cleaned[n];
  end if;
end; $$;
revoke all on function public.delivery_coarse_area(text) from public, anon, authenticated;

create or replace function public.delivery_cloud_order_enriched(o public.delivery_cloud_orders) returns jsonb
language sql stable security definer set search_path='' as $$
  select (to_jsonb(o) - 'request_payload' - 'request_key') || jsonb_build_object(
    'sender_profile', (
      select jsonb_build_object('full_name', sa.full_name, 'phone', sa.phone)
      from public.delivery_cloud_accounts sa
      where sa.user_id = o.owner_id
    ),
    'driver_profile', case
      when o.driver_id is null then null
      else (
        select jsonb_build_object(
          'user_id', da.user_id,
          'full_name', da.full_name,
          'phone', da.phone,
          'rating_avg', coalesce((
            select round(avg(pr.rating)::numeric, 2)
            from public.delivery_partner_reviews pr
            where pr.target_kind = 'driver' and pr.driver_id = da.user_id and not pr.hidden
          ), 0),
          'rating_count', (
            select count(*)::integer
            from public.delivery_partner_reviews pr
            where pr.target_kind = 'driver' and pr.driver_id = da.user_id and not pr.hidden
          )
        )
        from public.delivery_cloud_accounts da
        where da.user_id = o.driver_id
      )
    end,
    'has_pod', exists (
      select 1 from public.delivery_live_events ev
      where ev.room_id = o.tracking_code and ev.kind = 'pod'
    ),
    'pod_photo_path', (
      select ev.payload->>'path'
      from public.delivery_live_events ev
      where ev.room_id = o.tracking_code and ev.kind = 'pod'
      order by ev.created_at desc, ev.id desc
      limit 1
    ),
    'latest_gps', (
      select ev.payload || jsonb_build_object('updated_at', ev.created_at)
      from public.delivery_live_events ev
      where ev.room_id = o.tracking_code and ev.kind = 'gps'
      order by ev.created_at desc, ev.id desc
      limit 1
    ),
    'driver_review', (
      select jsonb_build_object(
        'id', pr.id,
        'rating', pr.rating,
        'body', pr.body,
        'reply', pr.reply,
        'replied_at', pr.replied_at,
        'created_at', pr.created_at
      )
      from public.delivery_partner_reviews pr
      where pr.target_kind = 'driver' and pr.cloud_order_id = o.id and not pr.hidden
      order by pr.created_at desc
      limit 1
    ),
    'completed_checkpoints', coalesce(o.details->'completed_checkpoints', '[]'::jsonb)
  );
$$;
revoke all on function public.delivery_cloud_order_enriched(public.delivery_cloud_orders) from public, anon, authenticated;

create or replace function public.delivery_cloud_list(
  p_queue boolean default false,
  p_before timestamptz default null,
  p_before_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  a public.delivery_cloud_accounts;
  result jsonb;
begin
  select * into a from public.delivery_cloud_accounts where user_id = auth.uid();
  if not public.delivery_is_operator() and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Cần hồ sơ cloud đang hoạt động.';
  end if;

  if p_queue then
    if not public.delivery_cloud_has_membership(a.user_id, 'driver') or a.blocked then
      raise sqlstate 'PT403' using message = 'Cần tài khoản tài xế được duyệt.';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id,
      'tracking_code', o.tracking_code,
      'shipping_fee', o.shipping_fee,
      'payable_fee', o.payable_fee,
      'coin_discount', o.coin_discount,
      'payment_status', o.payment_status,
      'cod_amount', o.cod_amount,
      'version', o.version,
      'status', o.status,
      'created_at', o.created_at,
      'distance_meters', o.distance_meters,
      'details', jsonb_build_object(
        'weight_kg', o.details->'weight_kg',
        'service_type', coalesce(o.details->'service_type', '"standard"'::jsonb),
        'payment_method', coalesce(o.details->'payment_method', '"sender_cash"'::jsonb),
        'stops_count', case
          when jsonb_typeof(o.details->'extra_stops') = 'array' then jsonb_array_length(o.details->'extra_stops')
          else 0
        end,
        'is_round_trip', coalesce((o.details->>'is_round_trip')::boolean, false),
        'scheduled_at', o.details->'scheduled_at',
        'prefer_ev', coalesce((o.details->>'prefer_ev')::boolean, false),
        'require_pod', coalesce((o.details->>'require_pod')::boolean, false),
        'require_otp', coalesce((o.details->>'require_otp')::boolean, false),
        'pickup_area', public.delivery_coarse_area(o.details->>'pickup_address'),
        'dropoff_area', public.delivery_coarse_area(o.details->>'dropoff_address'),
        'approx_pickup_lat', case
          when jsonb_typeof(o.details->'pickup_lat') = 'number' then round((o.details->>'pickup_lat')::numeric, 2)
          else null
        end,
        'approx_pickup_lng', case
          when jsonb_typeof(o.details->'pickup_lng') = 'number' then round((o.details->>'pickup_lng')::numeric, 2)
          else null
        end,
        'approx_dropoff_lat', case
          when jsonb_typeof(o.details->'dropoff_lat') = 'number' then round((o.details->>'dropoff_lat')::numeric, 2)
          else null
        end,
        'approx_dropoff_lng', case
          when jsonb_typeof(o.details->'dropoff_lng') = 'number' then round((o.details->>'dropoff_lng')::numeric, 2)
          else null
        end
      )
    ) order by o.created_at desc, o.id desc), '[]'::jsonb)
    into result
    from (
      select * from public.delivery_cloud_orders
      where status = 'searching'
        and merchant_ready
        and driver_id is null
        and (
          p_before is null
          or (p_before_id is null and created_at < p_before)
          or (created_at, id) < (p_before, p_before_id)
        )
      order by created_at desc, id desc
      limit 50
    ) o;
  else
    select coalesce(
      jsonb_agg(public.delivery_cloud_order_enriched(o) order by o.created_at desc, o.id desc),
      '[]'::jsonb
    )
    into result
    from (
      select * from public.delivery_cloud_orders
      where (public.delivery_is_operator() or auth.uid() in (owner_id, merchant_id, driver_id))
        and (
          p_before is null
          or (p_before_id is null and created_at < p_before)
          or (created_at, id) < (p_before, p_before_id)
        )
      order by created_at desc, id desc
      limit 50
    ) o;
  end if;

  return jsonb_build_object('orders', result, 'page_size', 50);
end; $$;

revoke all on function public.delivery_cloud_list(boolean, timestamptz, uuid) from public, anon;
grant execute on function public.delivery_cloud_list(boolean, timestamptz, uuid) to authenticated;

-- 4. Authoritative Live Order Telemetry, Order Chat & Multi-Stop Checkpoints RPC
create or replace function public.delivery_cloud_order_live(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  o public.delivery_cloud_orders;
  a public.delivery_cloud_accounts;
  v_lat double precision;
  v_lng double precision;
  v_heading double precision;
  v_speed double precision;
  v_ts bigint;
  v_gps_payload jsonb;
  v_text text;
  v_role text;
  v_name text;
  v_msg_id uuid;
  v_msg_at timestamptz;
  v_cp_key text;
  v_cp_note text;
  v_cps jsonb;
  rcp uuid;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if not op and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Tài khoản chưa có hồ sơ hoặc đang khóa.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 8000
     or jsonb_typeof(d->'order_id') is distinct from 'string' then
    raise sqlstate 'PT400' using message = 'Yêu cầu hành trình không hợp lệ.';
  end if;

  if p_action in ('mark_checkpoint') then
    select * into o from public.delivery_cloud_orders where id = (d->>'order_id')::uuid for update;
  else
    select * into o from public.delivery_cloud_orders where id = (d->>'order_id')::uuid;
  end if;

  if o.id is null or (not op and uid not in (o.owner_id, coalesce(o.merchant_id, o.owner_id), coalesce(o.driver_id, o.owner_id))) then
    raise sqlstate 'PT404' using message = 'Không tìm thấy đơn hàng được phép truy cập.';
  end if;

  if p_action = 'snapshot' then
    return jsonb_build_object(
      'order', public.delivery_cloud_order_enriched(o),
      'gps_trail', coalesce((
        select jsonb_agg(
          ev.payload || jsonb_build_object('updated_at', ev.created_at)
          order by ev.created_at asc, ev.id asc
        )
        from (
          select id, payload, created_at
          from public.delivery_live_events
          where room_id = o.tracking_code and kind = 'gps'
          order by created_at desc, id desc
          limit 12
        ) ev
      ), '[]'::jsonb),
      'messages', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', m.id,
            'sender_id', m.sender_id,
            'sender_name', coalesce(m.payload->>'sender_name', sa.full_name, 'Thành viên'),
            'sender_role', coalesce(
              m.payload->>'sender_role',
              case
                when m.sender_id = o.driver_id then 'driver'
                when m.sender_id = o.merchant_id then 'merchant'
                else 'customer'
              end
            ),
            'is_customer', coalesce((m.payload->>'isCustomer')::boolean, m.sender_id is distinct from o.driver_id),
            'text', coalesce(m.payload->>'text', ''),
            'created_at', m.created_at
          ) order by m.created_at asc, m.id asc
        )
        from (
          select id, sender_id, payload, created_at
          from public.delivery_live_events
          where room_id = o.tracking_code and kind = 'chat'
          order by created_at desc, id desc
          limit 60
        ) m
        left join public.delivery_cloud_accounts sa on sa.user_id = m.sender_id
      ), '[]'::jsonb)
    );

  elsif p_action = 'push_gps' then
    if not op and (uid is distinct from o.driver_id or not public.delivery_cloud_has_membership(uid, 'driver')) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế nhận chuyến được cập nhật định vị trực tiếp.';
    end if;
    if o.status not in ('accepted', 'arrivingPickup', 'inTransit', 'returning') then
      raise sqlstate 'PT409' using message = 'Chuyến giao không ở trạng thái di chuyển.';
    end if;
    if d - array['order_id', 'latitude', 'longitude', 'heading', 'speed_kmh', 'timestamp_ms'] <> '{}'::jsonb
       or jsonb_typeof(d->'latitude') is distinct from 'number'
       or jsonb_typeof(d->'longitude') is distinct from 'number' then
      raise sqlstate 'PT400' using message = 'Tọa độ GPS không hợp lệ.';
    end if;
    v_lat := (d->>'latitude')::double precision;
    v_lng := (d->>'longitude')::double precision;
    if v_lat not between -90 and 90 or v_lng not between -180 and 180 then
      raise sqlstate 'PT400' using message = 'Tọa độ GPS ngoài phạm vi hợp lệ.';
    end if;

    v_gps_payload := jsonb_build_object(
      'latitude', round(v_lat::numeric, 6),
      'longitude', round(v_lng::numeric, 6)
    );
    if jsonb_typeof(d->'heading') = 'number' then
      v_heading := (d->>'heading')::double precision;
      if v_heading between -360 and 360 then
        v_gps_payload := v_gps_payload || jsonb_build_object('heading', round(v_heading::numeric, 1));
      end if;
    end if;
    if jsonb_typeof(d->'speed_kmh') = 'number' then
      v_speed := (d->>'speed_kmh')::double precision;
      if v_speed between 0 and 120 then
        v_gps_payload := v_gps_payload || jsonb_build_object('speed_kmh', round(v_speed::numeric, 1));
      end if;
    end if;
    if jsonb_typeof(d->'timestamp_ms') = 'number' then
      v_ts := trunc((d->>'timestamp_ms')::numeric)::bigint;
      if v_ts > 0 then
        v_gps_payload := v_gps_payload || jsonb_build_object('timestamp_ms', v_ts);
      end if;
    end if;

    insert into public.delivery_live_rooms(id) values (o.tracking_code) on conflict do nothing;
    if uid = o.driver_id then
      insert into public.delivery_live_members(room_id, user_id, role)
        values (o.tracking_code, uid, 'driver')
        on conflict (room_id, user_id) do update set role = 'driver';
    end if;

    begin
      insert into public.delivery_live_events(room_id, sender_id, kind, payload)
        values (o.tracking_code, uid, 'gps', v_gps_payload)
        returning created_at into v_msg_at;
    exception when others then
      raise sqlstate 'PT409' using message = 'Tọa độ GPS thay đổi bất thường hoặc vượt giới hạn tốc độ 120 km/h.';
    end;

    return jsonb_build_object(
      'ok', true,
      'latest_gps', v_gps_payload || jsonb_build_object('updated_at', v_msg_at)
    );

  elsif p_action = 'send_chat' then
    if o.status = 'cancelled' then
      raise sqlstate 'PT409' using message = 'Đơn đã hủy, không thể gửi thêm tin nhắn.';
    end if;
    if d - array['order_id', 'text'] <> '{}'::jsonb or jsonb_typeof(d->'text') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Nội dung tin nhắn không hợp lệ.';
    end if;
    v_text := btrim(d->>'text');
    if length(v_text) not between 1 and 1000 then
      raise sqlstate 'PT400' using message = 'Tin nhắn cần từ 1 đến 1000 ký tự.';
    end if;

    select * into a from public.delivery_cloud_accounts where user_id = uid;
    v_role := case
      when uid = o.driver_id then 'driver'
      when uid = o.merchant_id then 'merchant'
      when op and uid <> o.owner_id then 'operator'
      else 'customer'
    end;
    v_name := coalesce(nullif(btrim(a.full_name), ''), case when v_role = 'operator' then 'Điều hành viên' else 'Người dùng' end);

    insert into public.delivery_live_rooms(id) values (o.tracking_code) on conflict do nothing;
    if v_role in ('customer', 'merchant', 'driver') then
      insert into public.delivery_live_members(room_id, user_id, role)
        values (o.tracking_code, uid, v_role)
        on conflict (room_id, user_id) do nothing;
    end if;

    insert into public.delivery_live_events(room_id, sender_id, kind, payload)
      values (
        o.tracking_code,
        uid,
        'chat',
        jsonb_build_object('text', v_text, 'sender_name', v_name, 'sender_role', v_role)
      )
      returning id, created_at into v_msg_id, v_msg_at;

    for rcp in
      select distinct x
      from unnest(array[o.owner_id, o.merchant_id, o.driver_id]) as x
      where x is not null and x <> uid
    loop
      perform public.delivery_emit_notification(
        rcp,
        'shipping',
        'shipping_chat',
        'Tin nhắn mới đơn ' || o.tracking_code,
        v_name || ': ' || left(v_text, 220),
        'cloud_order',
        o.id,
        jsonb_build_object('tracking_code', o.tracking_code, 'sender_role', v_role)
      );
    end loop;

    return jsonb_build_object(
      'message', jsonb_build_object(
        'id', v_msg_id,
        'sender_id', uid,
        'sender_name', v_name,
        'sender_role', v_role,
        'is_customer', (v_role <> 'driver'),
        'text', v_text,
        'created_at', v_msg_at
      )
    );

  elsif p_action = 'mark_checkpoint' then
    if not op and (uid is distinct from o.driver_id or not public.delivery_cloud_has_membership(uid, 'driver')) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế nhận chuyến được xác nhận điểm dừng.';
    end if;
    if o.status not in ('inTransit', 'returning') then
      raise sqlstate 'PT409' using message = 'Chỉ xác nhận điểm dừng khi đang giao hoặc đang hoàn hàng.';
    end if;
    if d - array['order_id', 'checkpoint_key', 'note'] <> '{}'::jsonb
       or jsonb_typeof(d->'checkpoint_key') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Thông tin điểm dừng không hợp lệ.';
    end if;
    v_cp_key := btrim(d->>'checkpoint_key');
    v_cp_note := left(btrim(coalesce(d->>'note', '')), 200);
    if v_cp_key !~ '^(stop:[0-4]|return_leg)$' then
      raise sqlstate 'PT400' using message = 'Mã điểm dừng không hợp lệ.';
    end if;

    v_cps := coalesce(o.details->'completed_checkpoints', '[]'::jsonb);
    if jsonb_typeof(v_cps) <> 'array' then
      v_cps := '[]'::jsonb;
    end if;
    if not exists (
      select 1 from jsonb_array_elements(v_cps) elem where elem->>'key' = v_cp_key
    ) then
      v_cps := v_cps || jsonb_build_array(jsonb_build_object(
        'key', v_cp_key,
        'completed_at', now(),
        'note', v_cp_note
      ));
      update public.delivery_cloud_orders
        set details = jsonb_set(o.details, '{completed_checkpoints}', v_cps, true),
            version = o.version + 1,
            updated_at = now()
        where id = o.id
        returning * into o;
      insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
        values (
          o.id,
          uid,
          'checkpoint',
          o.status,
          o.version,
          case
            when v_cp_key = 'return_leg' then 'Hoàn tất chặng khứ hồi'
            else 'Hoàn tất điểm dừng #' || ((substring(v_cp_key from '([0-4])')::int) + 1)
          end || case when length(v_cp_note) > 0 then ' · ' || v_cp_note else '' end
        );
    end if;
    return jsonb_build_object('order', public.delivery_cloud_order_enriched(o));
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác hành trình không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_order_live(text, jsonb) from public, anon;
grant execute on function public.delivery_cloud_order_live(text, jsonb) to authenticated;

-- 5. Driver Reviews Read in delivery_cloud_logistics + Review Notification Trigger
create or replace function public.delivery_partner_reviews_notify() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
begin
  if new.target_kind <> 'driver' or new.driver_id is null then
    return new;
  end if;
  select * into o from public.delivery_cloud_orders where id = new.cloud_order_id;
  if tg_op = 'INSERT' then
    perform public.delivery_emit_notification(
      new.driver_id,
      'shipping',
      'driver_reviewed',
      'Đánh giá chuyến giao ' || coalesce(o.tracking_code, '') || ': ' || new.rating || ' sao',
      left(btrim(new.body), 240),
      'cloud_order',
      new.cloud_order_id,
      jsonb_build_object('rating', new.rating, 'review_id', new.id)
    );
  elsif tg_op = 'UPDATE'
        and coalesce(btrim(old.reply), '') = ''
        and length(btrim(coalesce(new.reply, ''))) > 0 then
    perform public.delivery_emit_notification(
      new.reviewer_id,
      'shipping',
      'driver_review_replied',
      'Tài xế đã phản hồi đánh giá đơn ' || coalesce(o.tracking_code, ''),
      left(btrim(new.reply), 240),
      'cloud_order',
      new.cloud_order_id,
      jsonb_build_object('review_id', new.id)
    );
  end if;
  return new;
end; $$;
revoke all on function public.delivery_partner_reviews_notify() from public, anon, authenticated;

drop trigger if exists delivery_partner_reviews_notify on public.delivery_partner_reviews;
create trigger delivery_partner_reviews_notify
  after insert or update of reply on public.delivery_partner_reviews
  for each row execute function public.delivery_partner_reviews_notify();

create or replace function public.delivery_cloud_logistics(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  addr public.delivery_cloud_addresses;
  pk public.delivery_cloud_pickups;
  o public.delivery_cloud_orders;
  local_now timestamp := now() at time zone 'Asia/Ho_Chi_Minh';
  v_slot time; v_day date; v_packages numeric; v_weight numeric; v_driver uuid;
  v_phone text; v_delivered integer; v_failed integer; v_flagged boolean; v_score integer;
  v_instruction text; v_since timestamptz := now() - interval '30 days'; v_result jsonb;
begin
  if uid is null then raise sqlstate 'PT401' using message = 'Cần đăng nhập cloud.'; end if;
  if not op and not public.delivery_cloud_active() then raise sqlstate 'PT403' using message = 'Cần hồ sơ cloud đang hoạt động.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 4000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu vận hành không hợp lệ.';
  end if;

  if p_action = 'pickup_list' then
    return jsonb_build_object(
      'pickups', coalesce((select jsonb_agg(jsonb_build_object(
          'id', p.id, 'merchant_id', p.merchant_id, 'merchant_name', m.full_name, 'address_id', p.address_id,
          'pickup_address', p.pickup_address, 'pickup_lat', p.pickup_lat, 'pickup_lng', p.pickup_lng,
          'contact_name', p.contact_name, 'contact_phone', p.contact_phone, 'vehicle_type', p.vehicle_type,
          'pickup_date', p.pickup_date, 'time_slot', p.time_slot, 'package_count', p.package_count,
          'total_weight_kg', p.total_weight_kg, 'note', p.note, 'status', p.status, 'driver_id', p.driver_id,
          'driver_name', dr.full_name, 'assigned_at', p.assigned_at, 'version', p.version, 'created_at', p.created_at)
          order by p.created_at desc, p.id desc)
        from (select * from public.delivery_cloud_pickups where op or uid in (merchant_id, driver_id)
          order by created_at desc, id desc limit 50) p
        join public.delivery_cloud_accounts m on m.user_id = p.merchant_id
        left join public.delivery_cloud_accounts dr on dr.user_id = p.driver_id), '[]'::jsonb),
      'drivers', case when op then coalesce((select jsonb_agg(jsonb_build_object('user_id', a.user_id, 'full_name', a.full_name)
          order by a.full_name, a.user_id)
        from public.delivery_cloud_accounts a where public.delivery_cloud_has_membership(a.user_id, 'driver')), '[]'::jsonb)
        else '[]'::jsonb end);

  elsif p_action = 'pickup_create' then
    if not public.delivery_cloud_has_membership(uid, 'merchant') then
      raise sqlstate 'PT403' using message = 'Cần tư cách cửa hàng đã được duyệt.';
    end if;
    if d - array['request_key', 'address_id', 'vehicle_type', 'pickup_date', 'time_slot', 'package_count', 'total_weight_kg', 'note'] <> '{}'::jsonb or
      jsonb_typeof(d->'request_key') is distinct from 'string' or jsonb_typeof(d->'address_id') is distinct from 'string' or
      jsonb_typeof(d->'package_count') is distinct from 'number' or jsonb_typeof(d->'total_weight_kg') is distinct from 'number' or
      (d ? 'note' and jsonb_typeof(d->'note') is distinct from 'string') or
      coalesce(d->>'pickup_date', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise sqlstate 'PT400' using message = 'Phiếu thu gom có trường không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('pickup:' || uid::text || (d->>'request_key'), 0));
    select * into pk from public.delivery_cloud_pickups where merchant_id = uid and request_key = (d->>'request_key')::uuid;
    if found then
      if pk.request_payload <> d then raise sqlstate 'PT409' using message = 'Mã yêu cầu đã dùng cho nội dung khác.'; end if;
      return to_jsonb(pk) - 'request_payload' - 'request_key';
    end if;
    v_day := (d->>'pickup_date')::date;
    v_slot := case d->>'time_slot' when 'morning' then time '09:00' when 'afternoon' then time '14:00' when 'evening' then time '18:00' end;
    if v_slot is null or v_day + v_slot <= local_now or v_day > local_now::date + 14 then
      raise sqlstate 'PT400' using message = 'Ngày và khung giờ thu gom phải chưa bắt đầu và trong 14 ngày tới.';
    end if;
    v_packages := (d->>'package_count')::numeric;
    v_weight := (d->>'total_weight_kg')::numeric;
    if v_packages <> trunc(v_packages) or v_packages not between 1 and 1000 or v_weight <= 0 or v_weight <> round(v_weight, 1) or
      v_weight > (case d->>'vehicle_type' when 'tricycle_300kg' then 300 when 'van_500kg' then 500 when 'box_truck_1500kg' then 1500 else 0 end) or
      length(btrim(coalesce(d->>'note', ''))) > 500 then
      raise sqlstate 'PT400' using message = 'Số kiện, khối lượng hoặc loại xe không hợp lệ.';
    end if;
    select * into addr from public.delivery_cloud_addresses where id = (d->>'address_id')::uuid and user_id = uid;
    if not found then raise sqlstate 'PT404' using message = 'Không tìm thấy địa chỉ kho trong sổ địa chỉ.'; end if;
    insert into public.delivery_cloud_pickups(merchant_id, request_key, request_payload, address_id, pickup_address, pickup_lat, pickup_lng,
      contact_name, contact_phone, vehicle_type, pickup_date, time_slot, package_count, total_weight_kg, note)
    values(uid, (d->>'request_key')::uuid, d, addr.id, addr.full_address, addr.latitude, addr.longitude, addr.recipient_name, addr.recipient_phone,
      d->>'vehicle_type', v_day, d->>'time_slot', v_packages::integer, v_weight, btrim(coalesce(d->>'note', '')))
    returning * into pk;
    return to_jsonb(pk) - 'request_payload' - 'request_key';

  elsif p_action = 'pickup_assign' then
    if not op then raise sqlstate 'PT403' using message = 'Cần quyền quản trị.'; end if;
    if d - array['id', 'version', 'driver_id'] <> '{}'::jsonb or jsonb_typeof(d->'version') is distinct from 'number' or
      jsonb_typeof(d->'driver_id') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Yêu cầu điều xe không hợp lệ.';
    end if;
    v_driver := (d->>'driver_id')::uuid;
    select * into pk from public.delivery_cloud_pickups where id = (d->>'id')::uuid for update;
    if not found then raise sqlstate 'PT404' using message = 'Không tìm thấy phiếu thu gom.'; end if;
    if pk.version is distinct from (d->>'version')::numeric then raise sqlstate 'PT409' using message = 'Phiếu thu gom đã thay đổi. Vui lòng tải lại.'; end if;
    if pk.status <> 'requested' then raise sqlstate 'PT409' using message = 'Phiếu thu gom đã được điều xe.'; end if;
    if not public.delivery_cloud_has_membership(v_driver, 'driver') then
      raise sqlstate 'PT409' using message = 'Tài xế chưa được duyệt hoặc đang khóa.';
    end if;
    update public.delivery_cloud_pickups set status = 'assigned', driver_id = v_driver, assigned_by = uid, assigned_at = now(),
      version = version + 1, updated_at = now() where id = pk.id returning * into pk;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values(uid, 'pickup_assign', pk.id, jsonb_build_object('driver_id', pk.driver_id, 'version', pk.version));
    return to_jsonb(pk) - 'request_payload' - 'request_key';

  elsif p_action in ('recipient_trust', 'recipient_flag') then
    v_phone := d->>'phone';
    if coalesce(v_phone, '') !~ '^0[35789][0-9]{8}$' or d - array['phone', 'flagged'] <> '{}'::jsonb or
      (p_action = 'recipient_flag' and jsonb_typeof(d->'flagged') is distinct from 'boolean') then
      raise sqlstate 'PT400' using message = 'Số điện thoại người nhận không hợp lệ.';
    end if;
    if p_action = 'recipient_flag' then
      if (d->>'flagged')::boolean then
        insert into public.delivery_cloud_recipient_flags(owner_id, recipient_phone) values(uid, v_phone) on conflict do nothing;
      else
        delete from public.delivery_cloud_recipient_flags where owner_id = uid and recipient_phone = v_phone;
      end if;
    end if;
    select count(*) filter(where status = 'delivered'), count(*) filter(where status in ('failed', 'returning', 'returned'))
      into v_delivered, v_failed from public.delivery_cloud_orders
      where details->>'recipient_phone' = v_phone and (owner_id = uid or merchant_id = uid);
    v_flagged := exists(select 1 from public.delivery_cloud_recipient_flags where owner_id = uid and recipient_phone = v_phone);
    v_score := greatest(15, least(99, 88 + v_delivered * 4 - v_failed * 22 - case when v_flagged then 45 else 0 end));
    return jsonb_build_object('phone', v_phone, 'delivered', v_delivered, 'failed_or_returned', v_failed, 'flagged', v_flagged, 'score', v_score,
      'tier', case when v_flagged or v_score < 60 then 'high_risk' when v_score < 80 then 'confirm' else 'trusted' end);

  elsif p_action = 'instruction_set' then
    if d - array['order_id', 'version', 'instruction'] <> '{}'::jsonb or jsonb_typeof(d->'order_id') is distinct from 'string' or
      jsonb_typeof(d->'version') is distinct from 'number' or jsonb_typeof(d->'instruction') is distinct from 'string' or
      length(btrim(d->>'instruction')) > 200 then
      raise sqlstate 'PT400' using message = 'Chỉ dẫn giao hàng không hợp lệ.';
    end if;
    v_instruction := btrim(d->>'instruction');
    select * into o from public.delivery_cloud_orders where id = (d->>'order_id')::uuid for update;
    if not found or o.owner_id <> uid then raise sqlstate 'PT404' using message = 'Không tìm thấy đơn hàng được phép truy cập.'; end if;
    if o.version is distinct from (d->>'version')::numeric then raise sqlstate 'PT409' using message = 'Đơn đã thay đổi. Vui lòng tải lại.'; end if;
    if o.status not in ('searching', 'accepted', 'arrivingPickup', 'inTransit', 'failed') then
      raise sqlstate 'PT409' using message = 'Đơn đã kết thúc, không thể đổi chỉ dẫn giao hàng.';
    end if;
    if o.delivery_instruction <> v_instruction then
      update public.delivery_cloud_orders set delivery_instruction = v_instruction, version = version + 1, updated_at = now()
        where id = o.id returning * into o;
      insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
        values(o.id, uid, 'instruction', o.status, o.version, v_instruction);
      insert into public.delivery_live_events(room_id, kind, payload)
        values(o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));
    end if;
    return public.delivery_cloud_order_enriched(o);

  elsif p_action = 'stats' then
    with scoped as (
      select o2.status, o2.created_at, coalesce(o2.details->>'service_type', 'standard') as service_type,
        (select min(h.created_at) from public.delivery_cloud_history h where h.order_id = o2.id and h.action = 'pickup') as picked_at,
        (select max(h.created_at) from public.delivery_cloud_history h where h.order_id = o2.id and h.action = 'deliver') as delivered_at
      from public.delivery_cloud_orders o2
      where o2.created_at >= v_since and (op or uid in (o2.owner_id, o2.merchant_id, o2.driver_id))
    ), services as (
      select service_type, count(*) as total, count(*) filter(where status = 'delivered') as delivered,
        round(avg(extract(epoch from delivered_at - created_at) / 60) filter(where status = 'delivered' and delivered_at is not null)) as avg_minutes
      from scoped group by service_type
    )
    select jsonb_build_object(
      'total', (select count(*) from scoped),
      'delivered', (select count(*) from scoped where status = 'delivered'),
      'failed_or_returned', (select count(*) from scoped where status in ('failed', 'returning', 'returned')),
      'cancelled', (select count(*) from scoped where status = 'cancelled'),
      'active', (select count(*) from scoped where status in ('searching', 'accepted', 'arrivingPickup', 'inTransit')),
      'avg_delivery_minutes', (select round(avg(extract(epoch from delivered_at - created_at) / 60)) from scoped
        where status = 'delivered' and delivered_at is not null),
      'avg_transit_minutes', (select round(avg(extract(epoch from delivered_at - picked_at) / 60)) from scoped
        where status = 'delivered' and delivered_at is not null and picked_at is not null),
      'by_service', coalesce((select jsonb_agg(jsonb_build_object('service_type', service_type, 'total', total,
        'delivered', delivered, 'avg_delivery_minutes', avg_minutes) order by total desc, service_type) from services), '[]'::jsonb)
    ) into v_result;
    return jsonb_build_object('scope', case when op then 'network' else 'account' end, 'window_days', 30, 'summary', v_result,
      'pickups', jsonb_build_object(
        'requested', (select count(*) from public.delivery_cloud_pickups where status = 'requested' and (op or merchant_id = uid)),
        'assigned', (select count(*) from public.delivery_cloud_pickups where status = 'assigned' and (op or uid in (merchant_id, driver_id)))),
      'drivers', case when op then jsonb_build_object(
        'approved', (select count(*) from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id = m.user_id
          where m.role = 'driver' and m.state = 'active' and not a.blocked),
        'on_trip', (select count(distinct driver_id) from public.delivery_cloud_orders
          where driver_id is not null and status in ('accepted', 'arrivingPickup', 'inTransit', 'returning'))) end);

  elsif p_action = 'service_eta' then
    return jsonb_build_object('window_days', 30, 'services', coalesce((select jsonb_agg(jsonb_build_object(
        'service_type', q.service_type, 'samples', q.samples, 'avg_delivery_minutes', q.avg_minutes) order by q.service_type)
      from (select coalesce(o2.details->>'service_type', 'standard') as service_type, count(*) as samples,
          round(avg(extract(epoch from h.delivered_at - o2.created_at) / 60)) as avg_minutes
        from public.delivery_cloud_orders o2
        cross join lateral (select max(h2.created_at) as delivered_at from public.delivery_cloud_history h2
          where h2.order_id = o2.id and h2.action = 'deliver') h
        where o2.status = 'delivered' and o2.created_at >= v_since and h.delivered_at is not null
        group by 1) q), '[]'::jsonb));

  elsif p_action = 'driver_reviews' then
    v_driver := case
      when op and jsonb_typeof(d->'driver_id') = 'string' then (d->>'driver_id')::uuid
      else uid
    end;
    if not op and not public.delivery_cloud_has_membership(uid, 'driver') then
      raise sqlstate 'PT403' using message = 'Cần tư cách tài xế để xem đánh giá chuyến giao.';
    end if;
    return jsonb_build_object(
      'rating_avg', coalesce((
        select round(avg(pr.rating)::numeric, 2)
        from public.delivery_partner_reviews pr
        where pr.target_kind = 'driver' and pr.driver_id = v_driver and not pr.hidden
      ), 0),
      'rating_count', (
        select count(*)::integer
        from public.delivery_partner_reviews pr
        where pr.target_kind = 'driver' and pr.driver_id = v_driver and not pr.hidden
      ),
      'reviews', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'cloud_order_id', r.cloud_order_id,
            'tracking_code', co.tracking_code,
            'rating', r.rating,
            'body', r.body,
            'reply', r.reply,
            'replied_at', r.replied_at,
            'reviewer_name', coalesce(ra.full_name, 'Khách hàng'),
            'created_at', r.created_at
          ) order by r.created_at desc, r.id desc
        )
        from (
          select * from public.delivery_partner_reviews
          where target_kind = 'driver' and driver_id = v_driver and not hidden
          order by created_at desc, id desc
          limit 40
        ) r
        left join public.delivery_cloud_orders co on co.id = r.cloud_order_id
        left join public.delivery_cloud_accounts ra on ra.user_id = r.reviewer_id
      ), '[]'::jsonb)
    );
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác vận hành không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_logistics(text, jsonb) from public, anon;
grant execute on function public.delivery_cloud_logistics(text, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
