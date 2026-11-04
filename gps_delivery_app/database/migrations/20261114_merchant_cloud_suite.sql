-- Additive migration: Merchant Cloud Suite (dashboard KPIs, quick storefront/catalog controls,
-- stock audit ledger, shop promotions management, enriched order queue, aftersales inbox,
-- and delegated shop staff live delivery journey + chat access).
begin;

-- 1. Delegated shop staff read/chat authorization helper for linked cloud delivery orders
create or replace function public.delivery_can_access_cloud_order_as_shop_staff(
  p_order_id uuid,
  p_user uuid
) returns boolean
language sql stable security definer set search_path='' as $$
  select p_order_id is not null and p_user is not null and (
    exists(
      select 1
      from public.delivery_market_shop_orders so
      where so.delivery_id = p_order_id
        and public.delivery_market_can_access_shop(so.shop_id, p_user, 'staff')
    )
    or exists(
      select 1
      from public.delivery_market_shipments ms
      join public.delivery_market_shop_orders so on so.id = ms.order_id
      where ms.delivery_id = p_order_id
        and public.delivery_market_can_access_shop(so.shop_id, p_user, 'staff')
    )
    or exists(
      select 1
      from public.delivery_market_returns r
      join public.delivery_market_shop_orders so on so.id = r.order_id
      where r.return_delivery_id = p_order_id
        and public.delivery_market_can_access_shop(so.shop_id, p_user, 'staff')
    )
  );
$$;

revoke all on function public.delivery_can_access_cloud_order_as_shop_staff(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.delivery_is_order_shop_staff(p_order_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null
    and public.delivery_can_access_cloud_order_as_shop_staff(p_order_id, auth.uid());
$$;

revoke all on function public.delivery_is_order_shop_staff(uuid) from public, anon;
grant execute on function public.delivery_is_order_shop_staff(uuid) to authenticated;

drop policy if exists cloud_order_read on public.delivery_cloud_orders;
create policy cloud_order_read on public.delivery_cloud_orders for select to authenticated
  using (
    public.delivery_is_operator()
    or (
      public.delivery_cloud_active()
      and (
        auth.uid() in (owner_id, merchant_id, driver_id)
        or public.delivery_is_order_shop_staff(id)
      )
    )
  );

-- 2. Extend live room membership & order history read to delegated shop staff (driver write checks remain unchanged)
create or replace function public.delivery_is_member(room text) returns boolean
language sql stable security definer set search_path='' as $$
  select (
    exists(select 1 from public.delivery_live_members where room_id = room and user_id = auth.uid())
    or exists(
      select 1
      from public.delivery_cloud_orders o
      where o.tracking_code = room
        and public.delivery_can_access_cloud_order_as_shop_staff(o.id, auth.uid())
    )
  ) and (
    not exists(select 1 from public.delivery_cloud_orders where tracking_code = room)
    or public.delivery_cloud_active()
  );
$$;

revoke all on function public.delivery_is_member(text) from public;
grant execute on function public.delivery_is_member(text) to authenticated;

create or replace function public.delivery_cloud_history_read(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not exists(
    select 1
    from public.delivery_cloud_orders o
    where o.id = p_order
      and (
        public.delivery_is_operator()
        or (
          public.delivery_cloud_active()
          and (
            auth.uid() in (o.owner_id, o.merchant_id, o.driver_id)
            or public.delivery_can_access_cloud_order_as_shop_staff(o.id, auth.uid())
          )
        )
      )
  ) then
    raise sqlstate 'PT404' using message = 'Không tìm thấy đơn hàng.';
  end if;
  return jsonb_build_object(
    'history',
    coalesce(
      (select jsonb_agg(to_jsonb(h) order by h.version) from public.delivery_cloud_history h where h.order_id = p_order),
      '[]'::jsonb
    )
  );
end; $$;

revoke all on function public.delivery_cloud_history_read(uuid) from public, anon;
grant execute on function public.delivery_cloud_history_read(uuid) to authenticated;

-- 3. Extend delivery_cloud_order_live so delegated shop staff can inspect live telemetry and chat as 'merchant'
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
  v_is_shop_staff boolean := false;
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

  if o.id is not null then
    v_is_shop_staff := public.delivery_can_access_cloud_order_as_shop_staff(o.id, uid);
  end if;

  if o.id is null or (
    not op
    and uid not in (o.owner_id, coalesce(o.merchant_id, o.owner_id), coalesce(o.driver_id, o.owner_id))
    and not v_is_shop_staff
  ) then
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
                when m.sender_id = o.merchant_id or public.delivery_can_access_cloud_order_as_shop_staff(o.id, m.sender_id) then 'merchant'
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
      when uid = o.merchant_id or v_is_shop_staff then 'merchant'
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

-- 4. Authoritative Merchant Suite RPC (dashboard, storefront quick pause, catalog quick update,
--    stock ledger, promotions, enriched shop orders queue, and aftersales/finance inbox)
create or replace function public.delivery_merchant_suite(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  a public.delivery_cloud_accounts;
  sh public.delivery_market_shops;
  prod public.delivery_market_products;
  var_row public.delivery_market_variants;
  v_shop uuid;
  v_prod uuid;
  v_var uuid;
  v_ver integer;
  v_old_stock integer;
  v_new_stock integer;
  v_new_pub boolean;
  v_can_manage boolean := false;
  v_role text := 'staff';
  v_filter text;
  v_search text;
  v_tab text;
  v_before_ts timestamptz;
  v_before_id uuid;
  v_shops jsonb;
  v_eligible jsonb;
  v_finance jsonb;
  v_rows jsonb;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  select * into a from public.delivery_cloud_accounts where user_id = uid for share;
  if a.blocked or (a.user_id is null and not op) then
    raise sqlstate 'PT403' using message = 'Cần tài khoản đang hoạt động.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 16000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu cửa hàng không hợp lệ.';
  end if;

  if p_action = 'dashboard' then
    v_shop := case
      when d ? 'shop_id' and jsonb_typeof(d->'shop_id') = 'string' and btrim(d->>'shop_id') <> ''
      then (d->>'shop_id')::uuid
      else null
    end;

    select coalesce(jsonb_agg(x order by x.is_owner desc, x.updated_at desc, x.id asc), '[]'::jsonb)
    into v_shops
    from (
      select
        s.id,
        s.owner_id,
        s.name,
        s.description,
        s.address,
        s.latitude,
        s.longitude,
        s.status,
        s.paused,
        s.version,
        s.updated_at,
        s.opening_schedule,
        s.banner_url,
        s.service_radius_km,
        (s.owner_id = uid) as is_owner,
        case
          when s.owner_id = uid then 'owner'
          when exists(
            select 1 from public.delivery_market_shop_staff st
            where st.shop_id = s.id and st.user_id = uid and st.active and st.role = 'manager'
          ) then 'manager'
          when exists(
            select 1 from public.delivery_market_shop_staff st
            where st.shop_id = s.id and st.user_id = uid and st.active
          ) then 'staff'
          when op then 'operator'
          else 'staff'
        end as my_role,
        (not s.paused and s.status = 'active' and public.delivery_market_is_open(s.opening_schedule)) as open_now,
        (select count(*)::int from public.delivery_market_shop_follows sf where sf.shop_id = s.id) as followers,
        coalesce((
          select round(avg(pr.rating)::numeric, 2)
          from public.delivery_partner_reviews pr
          where pr.target_kind = 'shop' and pr.shop_id = s.id and not pr.hidden
        ), 0) as rating_avg,
        (
          select count(*)::int
          from public.delivery_partner_reviews pr
          where pr.target_kind = 'shop' and pr.shop_id = s.id and not pr.hidden
        ) as rating_count
      from public.delivery_market_shops s
      where s.owner_id = uid
        or public.delivery_market_can_access_shop(s.id, uid, 'staff')
        or (op and v_shop is not null and s.id = v_shop)
      limit 50
    ) x;

    if jsonb_array_length(v_shops) = 0
       and not op
       and not public.delivery_cloud_has_membership(uid, 'merchant') then
      raise sqlstate 'PT403' using message = 'Cần tư cách cửa hàng đã được duyệt hoặc phân quyền nhân sự.';
    end if;

    if v_shop is not null then
      if not op and not public.delivery_market_can_access_shop(v_shop, uid, 'staff') then
        raise sqlstate 'PT403' using message = 'Không có quyền truy cập cửa hàng này.';
      end if;
      select * into sh from public.delivery_market_shops where id = v_shop;
      if sh.id is null then
        raise sqlstate 'PT404' using message = 'Không tìm thấy cửa hàng.';
      end if;
    elsif jsonb_array_length(v_shops) > 0 then
      v_shop := (v_shops->0->>'id')::uuid;
      select * into sh from public.delivery_market_shops where id = v_shop;
    else
      return jsonb_build_object(
        'shops', '[]'::jsonb,
        'selected_shop_id', null,
        'my_role', case when op then 'operator' else 'owner' end,
        'kpis', null
      );
    end if;

    v_can_manage := op or public.delivery_market_can_access_shop(v_shop, uid, 'manager');
    v_role := case
      when sh.owner_id = uid then 'owner'
      when exists(
        select 1 from public.delivery_market_shop_staff st
        where st.shop_id = v_shop and st.user_id = uid and st.active and st.role = 'manager'
      ) then 'manager'
      when exists(
        select 1 from public.delivery_market_shop_staff st
        where st.shop_id = v_shop and st.user_id = uid and st.active
      ) then 'staff'
      when op then 'operator'
      else 'staff'
    end;

    if v_can_manage then
      select coalesce(jsonb_agg(el order by el.delivered_at asc, el.order_id asc), '[]'::jsonb)
      into v_eligible
      from (
        select
          so.id as order_id,
          so.delivered_at,
          co.tracking_code,
          greatest(0, (so.snapshot->>'subtotal')::bigint - coalesce((so.snapshot->>'shop_discount')::bigint, 0)) as merch_net,
          f_agg.collected,
          f_agg.refunded,
          f_agg.settled,
          f_agg.pending_settlement,
          greatest(
            0,
            least(
              greatest(0, (so.snapshot->>'subtotal')::bigint - coalesce((so.snapshot->>'shop_discount')::bigint, 0)) - f_agg.refunded - f_agg.settled,
              f_agg.collected + coalesce((so.snapshot->>'platform_discount')::bigint, 0) - f_agg.refunded - f_agg.settled - (so.snapshot->>'shipping_fee')::bigint
            ) - f_agg.pending_settlement
          ) as eligible_amount
        from public.delivery_market_shop_orders so
        left join public.delivery_cloud_orders co on co.id = so.delivery_id
        cross join lateral (
          select
            coalesce(sum(f.amount) filter (where f.kind = 'collection' and f.state = 'completed'), 0)::bigint as collected,
            coalesce(sum(f.amount) filter (where f.kind = 'refund' and f.state = 'completed'), 0)::bigint as refunded,
            coalesce(sum(f.amount) filter (where f.kind = 'settlement' and f.state = 'completed'), 0)::bigint as settled,
            coalesce(sum(f.amount) filter (where f.kind = 'settlement' and f.state in ('requested', 'approved')), 0)::bigint as pending_settlement
          from public.delivery_market_finance f
          where f.order_id = so.id
        ) f_agg
        where so.shop_id = v_shop
          and so.state <> 'cancelled'
          and so.delivered_at is not null
          and so.delivered_at <= now() - interval '7 days'
          and not exists (
            select 1
            from public.delivery_market_returns r
            join lateral (
              select i
              from jsonb_array_elements(so.snapshot->'items') i
              where coalesce(i->>'line_id', i->>'product_id')::uuid = r.line_id
            ) v on true
            where r.order_id = so.id
              and (
                r.state in ('requested', 'approved', 'escalated')
                or (
                  r.state = 'received'
                  and r.quantity * (v.i->>'unit_price')::bigint > (
                    select coalesce(sum(rf.amount), 0)
                    from public.delivery_market_finance rf
                    where rf.return_id = r.id and rf.kind = 'refund' and rf.state = 'completed'
                  )
                )
              )
          )
      ) el
      where el.eligible_amount > 0
      limit 30;

      v_finance := jsonb_build_object(
        'gross_subtotal', coalesce((
          select sum(greatest(0, (so.snapshot->>'subtotal')::bigint - coalesce((so.snapshot->>'shop_discount')::bigint, 0)))::bigint
          from public.delivery_market_shop_orders so
          where so.shop_id = v_shop and so.state <> 'cancelled'
        ), 0),
        'collected_total', coalesce((
          select sum(f.amount)::bigint
          from public.delivery_market_finance f
          join public.delivery_market_shop_orders so on so.id = f.order_id
          where so.shop_id = v_shop and f.kind = 'collection' and f.state = 'completed'
        ), 0),
        'refunded_total', coalesce((
          select sum(f.amount)::bigint
          from public.delivery_market_finance f
          join public.delivery_market_shop_orders so on so.id = f.order_id
          where so.shop_id = v_shop and f.kind = 'refund' and f.state = 'completed'
        ), 0),
        'settled_total', coalesce((
          select sum(f.amount)::bigint
          from public.delivery_market_finance f
          join public.delivery_market_shop_orders so on so.id = f.order_id
          where so.shop_id = v_shop and f.kind = 'settlement' and f.state = 'completed'
        ), 0),
        'pending_settlement_total', coalesce((
          select sum(f.amount)::bigint
          from public.delivery_market_finance f
          join public.delivery_market_shop_orders so on so.id = f.order_id
          where so.shop_id = v_shop and f.kind = 'settlement' and f.state in ('requested', 'approved')
        ), 0),
        'eligible_settlement_total', coalesce((
          select sum((e->>'eligible_amount')::bigint)::bigint
          from jsonb_array_elements(v_eligible) e
        ), 0),
        'eligible_orders', v_eligible
      );
    else
      v_finance := null;
    end if;

    return jsonb_build_object(
      'shops', v_shops,
      'selected_shop_id', v_shop,
      'my_role', v_role,
      'kpis', jsonb_build_object(
        'orders', jsonb_build_object(
          'pending', (select count(*)::int from public.delivery_market_shop_orders so where so.shop_id = v_shop and so.state = 'pending'),
          'overdue_pending', (select count(*)::int from public.delivery_market_shop_orders so where so.shop_id = v_shop and so.state = 'pending' and so.accept_by <= now()),
          'accepted', (select count(*)::int from public.delivery_market_shop_orders so where so.shop_id = v_shop and so.state = 'accepted'),
          'ready', (select count(*)::int from public.delivery_market_shop_orders so where so.shop_id = v_shop and so.state = 'ready' and so.delivered_at is null),
          'in_transit', (
            select count(*)::int
            from public.delivery_market_shop_orders so
            where so.shop_id = v_shop
              and so.state = 'ready'
              and so.delivered_at is null
              and exists(
                select 1
                from public.delivery_cloud_orders co
                where (
                  co.id = so.delivery_id
                  or exists(
                    select 1 from public.delivery_market_shipments ms
                    where ms.order_id = so.id and ms.delivery_id = co.id
                  )
                )
                and co.status in ('accepted', 'arrivingPickup', 'inTransit', 'returning', 'failed')
              )
          ),
          'delivered', (select count(*)::int from public.delivery_market_shop_orders so where so.shop_id = v_shop and so.state <> 'cancelled' and so.delivered_at is not null),
          'cancelled', (select count(*)::int from public.delivery_market_shop_orders so where so.shop_id = v_shop and so.state = 'cancelled')
        ),
        'catalog', jsonb_build_object(
          'products_total', (select count(*)::int from public.delivery_market_products p where p.shop_id = v_shop),
          'published_count', (select count(*)::int from public.delivery_market_products p where p.shop_id = v_shop and p.published),
          'low_stock_count', (select count(*)::int from public.delivery_market_products p where p.shop_id = v_shop and p.published and p.stock between 1 and 5),
          'out_of_stock_count', (select count(*)::int from public.delivery_market_products p where p.shop_id = v_shop and p.stock <= 0)
        ),
        'aftersales', jsonb_build_object(
          'open_returns', (
            select count(*)::int
            from public.delivery_market_returns r
            join public.delivery_market_shop_orders so on so.id = r.order_id
            where so.shop_id = v_shop and r.state in ('requested', 'approved', 'escalated')
          ),
          'unreplied_reviews', (
            (
              select count(*)::int
              from public.delivery_market_reviews r
              join public.delivery_market_products p on p.id = r.product_id
              where p.shop_id = v_shop and not r.hidden and btrim(r.reply) = ''
            ) + (
              select count(*)::int
              from public.delivery_partner_reviews pr
              where pr.target_kind = 'shop' and pr.shop_id = v_shop and not pr.hidden and btrim(pr.reply) = ''
            )
          ),
          'active_vouchers', (
            select count(*)::int
            from public.delivery_market_vouchers v
            where v.shop_id = v_shop
              and v.owner_user_id is null
              and v.active
              and v.ends_at > now()
              and v.budget_used < v.budget_total
          ),
          'active_flash_sales', (
            select count(*)::int
            from public.delivery_market_flash_sales fs
            where fs.shop_id = v_shop
              and fs.active
              and fs.ends_at > now()
              and fs.sold_stock < fs.allocated_stock
          )
        ),
        'finance', v_finance
      )
    );

  elsif p_action = 'shop_quick_pause' then
    if d - array['shop_id', 'paused', 'version'] <> '{}'::jsonb
       or jsonb_typeof(d->'shop_id') is distinct from 'string'
       or jsonb_typeof(d->'paused') is distinct from 'boolean'
       or jsonb_typeof(d->'version') is distinct from 'number' then
      raise sqlstate 'PT400' using message = 'Thông tin tạm nghỉ cửa hàng không hợp lệ.';
    end if;
    v_shop := (d->>'shop_id')::uuid;
    v_ver := (d->>'version')::integer;
    select * into sh from public.delivery_market_shops where id = v_shop for update;
    if sh.id is null then
      raise sqlstate 'PT404' using message = 'Không tìm thấy cửa hàng.';
    end if;
    if not op and not public.delivery_market_can_access_shop(sh.id, uid, 'manager') then
      raise sqlstate 'PT403' using message = 'Chỉ chủ cửa hàng hoặc quản lý được bật/tắt nhận đơn.';
    end if;
    if sh.status = 'suspended' then
      raise sqlstate 'PT403' using message = 'Cửa hàng đang tạm khóa.';
    end if;
    if sh.version is distinct from v_ver then
      raise sqlstate 'PT409' using message = 'Cửa hàng đã thay đổi. Hãy tải lại.';
    end if;
    update public.delivery_market_shops
      set paused = (d->>'paused')::boolean,
          version = version + 1,
          updated_at = now()
      where id = sh.id
      returning * into sh;
    return jsonb_build_object('shop', to_jsonb(sh));

  elsif p_action = 'product_quick_update' then
    if d - array['product_id', 'variant_id', 'version', 'stock', 'published'] <> '{}'::jsonb
       or jsonb_typeof(d->'product_id') is distinct from 'string'
       or jsonb_typeof(d->'version') is distinct from 'number'
       or (not (d ? 'stock') and not (d ? 'published')) then
      raise sqlstate 'PT400' using message = 'Thông tin cập nhật nhanh sản phẩm không hợp lệ.';
    end if;
    if d ? 'stock' and (
      jsonb_typeof(d->'stock') is distinct from 'number'
      or (d->>'stock')::numeric <> trunc((d->>'stock')::numeric)
      or (d->>'stock')::numeric not between 0 and 1000000
    ) then
      raise sqlstate 'PT400' using message = 'Tồn kho cần là số nguyên từ 0 đến 1.000.000.';
    end if;
    if d ? 'published' and jsonb_typeof(d->'published') is distinct from 'boolean' then
      raise sqlstate 'PT400' using message = 'Trạng thái hiển thị không hợp lệ.';
    end if;

    v_prod := (d->>'product_id')::uuid;
    v_var := case
      when d ? 'variant_id' and jsonb_typeof(d->'variant_id') = 'string' and btrim(d->>'variant_id') <> ''
      then (d->>'variant_id')::uuid
      else null
    end;
    v_ver := (d->>'version')::integer;

    select * into prod from public.delivery_market_products where id = v_prod for update;
    if prod.id is null then
      raise sqlstate 'PT404' using message = 'Không tìm thấy sản phẩm.';
    end if;
    select * into sh from public.delivery_market_shops where id = prod.shop_id;
    if sh.id is null or sh.status = 'suspended' then
      raise sqlstate 'PT403' using message = 'Cửa hàng không hợp lệ hoặc đang tạm khóa.';
    end if;
    if not op and not public.delivery_market_can_access_shop(prod.shop_id, uid, 'manager') then
      raise sqlstate 'PT403' using message = 'Chỉ chủ cửa hàng hoặc quản lý được cập nhật tồn kho và trạng thái bán.';
    end if;

    if v_var is not null then
      select * into var_row
      from public.delivery_market_variants
      where id = v_var and product_id = prod.id
      for update;
      if var_row.id is null then
        raise sqlstate 'PT404' using message = 'Không tìm thấy phân loại sản phẩm.';
      end if;
      if var_row.version is distinct from v_ver then
        raise sqlstate 'PT409' using message = 'Phân loại sản phẩm đã thay đổi. Hãy tải lại.';
      end if;
      v_old_stock := var_row.stock;
      v_new_stock := case when d ? 'stock' then (d->>'stock')::integer else var_row.stock end;
      v_new_pub := case when d ? 'published' then (d->>'published')::boolean else var_row.published end;

      update public.delivery_market_variants
        set stock = v_new_stock,
            published = v_new_pub,
            version = version + 1,
            updated_at = now()
        where id = var_row.id
        returning * into var_row;

      if v_new_stock <> v_old_stock then
        insert into public.delivery_market_stock(product_id, variant_id, actor_id, delta, reason)
          values (prod.id, var_row.id, uid, v_new_stock - v_old_stock, 'merchant_variant_quick_adjust');
      end if;

      return jsonb_build_object('variant', to_jsonb(var_row), 'product_id', prod.id);
    else
      if prod.version is distinct from v_ver then
        raise sqlstate 'PT409' using message = 'Sản phẩm đã thay đổi. Hãy tải lại.';
      end if;
      v_old_stock := prod.stock;
      v_new_stock := case when d ? 'stock' then (d->>'stock')::integer else prod.stock end;
      v_new_pub := case when d ? 'published' then (d->>'published')::boolean else prod.published end;

      update public.delivery_market_products
        set stock = v_new_stock,
            published = v_new_pub,
            version = version + 1,
            updated_at = now()
        where id = prod.id
        returning * into prod;

      if v_new_stock <> v_old_stock then
        insert into public.delivery_market_stock(product_id, actor_id, delta, reason)
          values (prod.id, uid, v_new_stock - v_old_stock, 'merchant_quick_adjust');
      end if;

      return jsonb_build_object(
        'product',
        to_jsonb(prod) || jsonb_build_object(
          'variants',
          coalesce((
            select jsonb_agg(to_jsonb(v) order by v.sku, v.id)
            from public.delivery_market_variants v
            where v.product_id = prod.id
          ), '[]'::jsonb)
        )
      );
    end if;

  elsif p_action = 'stock_ledger' then
    if jsonb_typeof(d->'shop_id') is distinct from 'string' or btrim(d->>'shop_id') = '' then
      raise sqlstate 'PT400' using message = 'Thiếu mã cửa hàng.';
    end if;
    v_shop := (d->>'shop_id')::uuid;
    v_prod := case
      when d ? 'product_id' and jsonb_typeof(d->'product_id') = 'string' and btrim(d->>'product_id') <> ''
      then (d->>'product_id')::uuid
      else null
    end;
    if not op and not public.delivery_market_can_access_shop(v_shop, uid, 'manager') then
      raise sqlstate 'PT403' using message = 'Chỉ chủ cửa hàng hoặc quản lý được xem sổ biến động tồn kho.';
    end if;
    v_before_ts := case when d ? 'before' and jsonb_typeof(d->'before') = 'string' then (d->>'before')::timestamptz else null end;
    v_before_id := case when d ? 'before_id' and jsonb_typeof(d->'before_id') = 'string' then (d->>'before_id')::uuid else null end;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb)
    into v_rows
    from (
      select
        st.id,
        st.product_id,
        p.name as product_name,
        p.sku as product_sku,
        st.variant_id,
        mv.title as variant_title,
        mv.sku as variant_sku,
        st.actor_source,
        coalesce(ua.full_name, case when st.actor_source = 'system' then 'Hệ thống' else 'Thành viên' end) as actor_name,
        st.delta,
        st.reason,
        st.reference_id,
        st.created_at
      from public.delivery_market_stock st
      join public.delivery_market_products p on p.id = st.product_id
      left join public.delivery_market_variants mv on mv.id = st.variant_id
      left join public.delivery_cloud_accounts ua on ua.user_id = st.actor_id
      where p.shop_id = v_shop
        and (v_prod is null or st.product_id = v_prod)
        and (
          v_before_ts is null
          or (st.created_at, st.id) < (v_before_ts, coalesce(v_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
        )
      order by st.created_at desc, st.id desc
      limit 50
    ) x;

    return jsonb_build_object(
      'entries', v_rows,
      'next', case
        when jsonb_array_length(v_rows) = 50 then jsonb_build_object(
          'before', v_rows->49->>'created_at',
          'before_id', v_rows->49->>'id'
        )
        else null
      end
    );

  elsif p_action = 'promotions' then
    if jsonb_typeof(d->'shop_id') is distinct from 'string' or btrim(d->>'shop_id') = '' then
      raise sqlstate 'PT400' using message = 'Thiếu mã cửa hàng.';
    end if;
    v_shop := (d->>'shop_id')::uuid;
    if not op and not public.delivery_market_can_access_shop(v_shop, uid, 'manager') then
      raise sqlstate 'PT403' using message = 'Chỉ chủ cửa hàng hoặc quản lý được quản trị khuyến mãi.';
    end if;

    return jsonb_build_object(
      'vouchers', coalesce((
        select jsonb_agg(to_jsonb(v) order by v.created_at desc, v.id desc)
        from (
          select
            mv.*,
            (
              select count(*)::int
              from public.delivery_market_voucher_usages vu
              where vu.voucher_id = mv.id and vu.state = 'allocated'
            ) as usage_count
          from public.delivery_market_vouchers mv
          where mv.shop_id = v_shop
            and mv.owner_user_id is null
          order by mv.created_at desc, mv.id desc
          limit 100
        ) v
      ), '[]'::jsonb),
      'flash_sales', coalesce((
        select jsonb_agg(to_jsonb(fs) order by fs.starts_at desc, fs.id desc)
        from (
          select
            mfs.*,
            p.name as product_name,
            p.sku as product_sku,
            p.price as original_price,
            p.stock as product_stock,
            p.image_url
          from public.delivery_market_flash_sales mfs
          join public.delivery_market_products p on p.id = mfs.product_id
          where mfs.shop_id = v_shop
          order by mfs.starts_at desc, mfs.id desc
          limit 100
        ) fs
      ), '[]'::jsonb)
    );

  elsif p_action = 'orders_list' then
    v_shop := case
      when d ? 'shop_id' and jsonb_typeof(d->'shop_id') = 'string' and btrim(d->>'shop_id') <> ''
      then (d->>'shop_id')::uuid
      else null
    end;
    if v_shop is not null then
      if not op and not public.delivery_market_can_access_shop(v_shop, uid, 'staff') then
        raise sqlstate 'PT403' using message = 'Không có quyền xem đơn của cửa hàng này.';
      end if;
    elsif not op
      and not public.delivery_cloud_has_membership(uid, 'merchant')
      and not exists(
        select 1 from public.delivery_market_shop_staff st
        where st.user_id = uid and st.active and public.delivery_market_can_access_shop(st.shop_id, uid, 'staff')
      ) then
      raise sqlstate 'PT403' using message = 'Cần tư cách cửa hàng hoặc phân quyền nhân sự.';
    end if;

    v_filter := coalesce(nullif(btrim(d->>'filter'), ''), 'all');
    v_search := lower(btrim(coalesce(d->>'search', '')));
    v_before_ts := case when d ? 'before' and jsonb_typeof(d->'before') = 'string' then (d->>'before')::timestamptz else null end;
    v_before_id := case when d ? 'before_id' and jsonb_typeof(d->'before_id') = 'string' then (d->>'before_id')::uuid else null end;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb)
    into v_rows
    from (
      select
        o.id,
        o.purchase_id,
        o.shop_id,
        s.name as shop_name,
        o.owner_id,
        o.merchant_id,
        o.snapshot,
        o.state,
        o.delivery_id,
        o.version,
        o.reason,
        o.created_at,
        o.updated_at,
        o.accept_by,
        o.delivered_at,
        p.payment_status,
        p.payment_method,
        del.status as delivery_status,
        del.tracking_code,
        case when del.id is not null then public.delivery_cloud_order_enriched(del) else null end as delivery_order,
        coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'parcel_index', ms.parcel_index,
              'delivery_id', ms.delivery_id,
              'tracking_code', co.tracking_code,
              'status', co.status,
              'weight_kg', ms.weight_kg,
              'cod_amount', ms.cod_amount,
              'delivery_order', public.delivery_cloud_order_enriched(co)
            )
            order by ms.parcel_index
          )
          from public.delivery_market_shipments ms
          join public.delivery_cloud_orders co on co.id = ms.delivery_id
          where ms.order_id = o.id
        ), '[]'::jsonb) as shipments,
        jsonb_build_object(
          'full_name', coalesce(nullif(o.snapshot->'details'->>'recipient_name', ''), ba.full_name, 'Khách hàng'),
          'phone', coalesce(nullif(o.snapshot->'details'->>'recipient_phone', ''), ba.phone, '')
        ) as buyer_profile,
        (
          select count(*)::int
          from public.delivery_market_returns r
          where r.order_id = o.id and r.state in ('requested', 'approved', 'escalated')
        ) as open_returns_count,
        (
          select count(*)::int
          from public.delivery_market_returns r
          where r.order_id = o.id
        ) as returns_total_count,
        (
          select count(*)::int
          from public.delivery_market_messages m
          where m.order_id = o.id
        ) as message_count
      from public.delivery_market_shop_orders o
      join public.delivery_market_shops s on s.id = o.shop_id
      join public.delivery_market_purchases p on p.id = o.purchase_id
      left join public.delivery_cloud_orders del on del.id = o.delivery_id
      left join public.delivery_cloud_accounts ba on ba.user_id = o.owner_id
      where (
        case
          when v_shop is not null then o.shop_id = v_shop
          when op and d->>'moderation' = 'true' then true
          else public.delivery_market_can_access_shop(o.shop_id, uid, 'staff')
        end
      )
      and (
        case v_filter
          when 'pending' then o.state = 'pending'
          when 'accepted' then o.state = 'accepted'
          when 'ready' then o.state = 'ready' and o.delivered_at is null
          when 'in_transit' then o.state = 'ready' and o.delivered_at is null and exists(
            select 1 from public.delivery_cloud_orders co
            where (co.id = o.delivery_id or exists(select 1 from public.delivery_market_shipments ms where ms.order_id = o.id and ms.delivery_id = co.id))
              and co.status in ('accepted', 'arrivingPickup', 'inTransit', 'returning', 'failed')
          )
          when 'delivered' then o.state <> 'cancelled' and o.delivered_at is not null
          when 'cancelled' then o.state = 'cancelled'
          when 'returns' then exists(
            select 1 from public.delivery_market_returns r
            where r.order_id = o.id and r.state in ('requested', 'approved', 'escalated')
          )
          else true
        end
      )
      and (
        v_search = ''
        or strpos(
          lower(
            o.id::text || ' ' ||
            coalesce(del.tracking_code, '') || ' ' ||
            coalesce(ba.full_name, '') || ' ' ||
            coalesce(o.snapshot->'details'->>'recipient_name', '') || ' ' ||
            coalesce(o.snapshot->'details'->>'recipient_phone', '') || ' ' ||
            coalesce(o.snapshot::text, '')
          ),
          v_search
        ) > 0
      )
      and (
        v_before_ts is null
        or (o.created_at, o.id) < (v_before_ts, coalesce(v_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
      )
      order by o.created_at desc, o.id desc
      limit 50
    ) x;

    return jsonb_build_object(
      'orders', v_rows,
      'next', case
        when jsonb_array_length(v_rows) = 50 then jsonb_build_object(
          'before', v_rows->49->>'created_at',
          'before_id', v_rows->49->>'id'
        )
        else null
      end
    );

  elsif p_action = 'aftersales_inbox' then
    if jsonb_typeof(d->'shop_id') is distinct from 'string' or btrim(d->>'shop_id') = '' then
      raise sqlstate 'PT400' using message = 'Thiếu mã cửa hàng.';
    end if;
    v_shop := (d->>'shop_id')::uuid;
    v_tab := coalesce(nullif(btrim(d->>'tab'), ''), 'returns');
    v_filter := coalesce(nullif(btrim(d->>'filter'), ''), 'all');
    if v_tab not in ('returns', 'reviews', 'finance') then
      raise sqlstate 'PT400' using message = 'Danh mục hậu mãi không hợp lệ.';
    end if;

    if v_tab = 'finance' then
      if not op and not public.delivery_market_can_access_shop(v_shop, uid, 'manager') then
        raise sqlstate 'PT403' using message = 'Chỉ chủ cửa hàng hoặc quản lý được xem sổ đối soát tài chính.';
      end if;
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb)
      into v_rows
      from (
        select
          f.id,
          f.order_id,
          f.kind,
          f.amount,
          f.return_id,
          f.proposer,
          f.approver,
          f.reason,
          f.state,
          f.version,
          f.created_at,
          f.completed_at,
          f.source,
          f.attachments,
          co.tracking_code,
          (so.snapshot->>'subtotal')::bigint as order_subtotal,
          so.delivered_at
        from public.delivery_market_finance f
        join public.delivery_market_shop_orders so on so.id = f.order_id
        left join public.delivery_cloud_orders co on co.id = so.delivery_id
        where so.shop_id = v_shop
          and (
            case v_filter
              when 'settlement' then f.kind = 'settlement'
              when 'collection' then f.kind = 'collection'
              when 'refund' then f.kind = 'refund'
              when 'pending' then f.state in ('requested', 'approved')
              else true
            end
          )
        order by f.created_at desc, f.id desc
        limit 50
      ) x;
      return jsonb_build_object('finance', v_rows);
    end if;

    if not op and not public.delivery_market_can_access_shop(v_shop, uid, 'staff') then
      raise sqlstate 'PT403' using message = 'Không có quyền truy cập hậu mãi cửa hàng này.';
    end if;

    if v_tab = 'returns' then
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb)
      into v_rows
      from (
        select
          r.id,
          r.order_id,
          r.product_id,
          r.variant_id,
          r.line_id,
          r.quantity,
          r.reason,
          r.state,
          r.response,
          r.version,
          r.created_at,
          r.updated_at,
          r.attachments,
          r.return_delivery_id,
          r.disposition,
          so.state as order_state,
          so.delivered_at,
          coalesce(nullif(so.snapshot->'details'->>'recipient_name', ''), ba.full_name, 'Khách hàng') as buyer_name,
          coalesce(nullif(so.snapshot->'details'->>'recipient_phone', ''), ba.phone, '') as buyer_phone,
          coalesce(line_item.item->>'name', p.name, 'Sản phẩm') as item_name,
          coalesce(line_item.item->>'sku', p.sku, '') as item_sku,
          coalesce((line_item.item->>'unit_price')::bigint, p.price, 0) as unit_price,
          co.tracking_code as order_tracking_code,
          rco.tracking_code as return_tracking_code,
          case when rco.id is not null then public.delivery_cloud_order_enriched(rco) else null end as return_delivery_order
        from public.delivery_market_returns r
        join public.delivery_market_shop_orders so on so.id = r.order_id
        left join public.delivery_market_products p on p.id = r.product_id
        left join public.delivery_cloud_accounts ba on ba.user_id = r.user_id
        left join public.delivery_cloud_orders co on co.id = so.delivery_id
        left join public.delivery_cloud_orders rco on rco.id = r.return_delivery_id
        left join lateral (
          select i as item
          from jsonb_array_elements(so.snapshot->'items') i
          where coalesce(i->>'line_id', i->>'product_id')::uuid = r.line_id
          limit 1
        ) line_item on true
        where so.shop_id = v_shop
          and (
            case v_filter
              when 'open' then r.state in ('requested', 'approved', 'escalated')
              when 'requested' then r.state = 'requested'
              when 'approved' then r.state = 'approved'
              when 'received' then r.state = 'received'
              when 'rejected' then r.state = 'rejected'
              when 'escalated' then r.state = 'escalated'
              else true
            end
          )
        order by r.created_at desc, r.id desc
        limit 50
      ) x;
      return jsonb_build_object('returns', v_rows);
    end if;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb)
    into v_rows
    from (
      select *
      from (
        select
          'partner'::text as review_kind,
          pr.id,
          pr.shop_order_id as order_id,
          null::uuid as product_id,
          coalesce(sh_t.name, 'Đánh giá cửa hàng') as target_title,
          coalesce(ua.full_name, 'Khách mua hàng') as reviewer_name,
          pr.rating,
          pr.body,
          pr.reply,
          pr.replied_at,
          pr.report_count,
          pr.created_at
        from public.delivery_partner_reviews pr
        left join public.delivery_market_shops sh_t on sh_t.id = pr.shop_id
        left join public.delivery_cloud_accounts ua on ua.user_id = pr.reviewer_id
        where pr.target_kind = 'shop'
          and pr.shop_id = v_shop
          and not pr.hidden

        union all

        select
          'product'::text as review_kind,
          r.id,
          r.order_id,
          r.product_id,
          p.name as target_title,
          coalesce(ua.full_name, 'Khách mua hàng') as reviewer_name,
          r.rating,
          r.body,
          r.reply,
          r.replied_at,
          r.report_count,
          r.created_at
        from public.delivery_market_reviews r
        join public.delivery_market_products p on p.id = r.product_id
        left join public.delivery_cloud_accounts ua on ua.user_id = r.user_id
        where p.shop_id = v_shop
          and not r.hidden
      ) u
      where (
        case v_filter
          when 'unreplied' then btrim(u.reply) = ''
          when 'replied' then btrim(u.reply) <> ''
          when 'shop' then u.review_kind = 'partner'
          when 'product' then u.review_kind = 'product'
          else true
        end
      )
      order by u.created_at desc, u.id desc
      limit 60
    ) x;

    return jsonb_build_object(
      'reviews', v_rows,
      'summary', jsonb_build_object(
        'shop_rating_avg', coalesce((
          select round(avg(pr.rating)::numeric, 2)
          from public.delivery_partner_reviews pr
          where pr.target_kind = 'shop' and pr.shop_id = v_shop and not pr.hidden
        ), 0),
        'shop_rating_count', (
          select count(*)::int
          from public.delivery_partner_reviews pr
          where pr.target_kind = 'shop' and pr.shop_id = v_shop and not pr.hidden
        ),
        'product_rating_avg', coalesce((
          select round(avg(r.rating)::numeric, 2)
          from public.delivery_market_reviews r
          join public.delivery_market_products p on p.id = r.product_id
          where p.shop_id = v_shop and not r.hidden
        ), 0),
        'product_rating_count', (
          select count(*)::int
          from public.delivery_market_reviews r
          join public.delivery_market_products p on p.id = r.product_id
          where p.shop_id = v_shop and not r.hidden
        ),
        'unreplied_count', (
          (
            select count(*)::int
            from public.delivery_partner_reviews pr
            where pr.target_kind = 'shop' and pr.shop_id = v_shop and not pr.hidden and btrim(pr.reply) = ''
          ) + (
            select count(*)::int
            from public.delivery_market_reviews r
            join public.delivery_market_products p on p.id = r.product_id
            where p.shop_id = v_shop and not r.hidden and btrim(r.reply) = ''
          )
        )
      )
    );
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác cửa hàng không hỗ trợ.';
end; $$;

revoke all on function public.delivery_merchant_suite(text, jsonb) from public, anon;
grant execute on function public.delivery_merchant_suite(text, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
