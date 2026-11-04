-- Additive Cross-Role Linkage Completion (Customer <-> Merchant/Shop Staff <-> Driver <-> Operator/Admin):
-- 1. Multi-branch shops & delegated manager shop updates
-- 2. Single-operator finance dual-control fallback & pre-delivery cancelled prepaid full refund reversal
-- 3. Prepaid Marketplace shipping fee settlement & COD collection auto-reconciliation
-- 4. Terminal returned/mixed split-parcel Marketplace order finalization & split-parcel OTP secrets
-- 5. Anti-self-dealing driver claim/review guards, trip release/reassign & delegated staff shipping access
-- 6. Driver Wallet (85%/15% trip earnings), COD remittance & payout settlements
-- 7. Full Bulk Pickup lifecycle (requested -> assigned -> arrived -> picked_up -> completed / cancelled)
-- 8. Reverse return shipment lifecycle guards, Partner KYC enforcement & full cross-role notifications
-- Safe to reapply; seeds zero demo users, shops, orders, vouchers, or balances.
begin;

-- ============================================================================
-- 1. SCHEMA & CONSTRAINT UPGRADES
-- ============================================================================

-- Multi-branch storefronts per merchant owner
alter table public.delivery_market_shops
  drop constraint if exists delivery_market_shops_owner_id_key;
create index if not exists delivery_market_shops_owner_id_idx
  on public.delivery_market_shops(owner_id, id);

-- Allow single-operator deployments to approve finance while multi-operator deployments enforce dual-control in RPC
alter table public.delivery_market_finance
  drop constraint if exists delivery_market_finance_check;

-- Expand unified notification reference_type check for cross-role events
alter table public.delivery_user_notifications
  drop constraint if exists delivery_user_notifications_reference_type_check;
alter table public.delivery_user_notifications
  add constraint delivery_user_notifications_reference_type_check
  check (reference_type is null or reference_type in (
    'cloud_order','market_order','pickup','membership','promo','account',
    'shop','finance','driver_settlement','review'
  ));

-- Bulk Pickup full lifecycle columns & relaxed status/driver invariants
alter table public.delivery_cloud_pickups
  add column if not exists shop_id uuid references public.delivery_market_shops(id) on delete set null,
  add column if not exists order_ids uuid[] not null default '{}'::uuid[],
  add column if not exists arrived_at timestamptz,
  add column if not exists picked_up_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text not null default '' check (length(cancel_reason) <= 500);

do $$
declare
  c_name text;
begin
  for c_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'delivery_cloud_pickups'
      and con.contype = 'c'
      and (
        pg_get_constraintdef(con.oid) ilike '%status%'
        or pg_get_constraintdef(con.oid) ilike '%driver_id%'
      )
  loop
    execute format('alter table public.delivery_cloud_pickups drop constraint if exists %I', c_name);
  end loop;
end $$;

alter table public.delivery_cloud_pickups
  add constraint delivery_cloud_pickups_status_v2_check
  check (status in ('requested','assigned','arrived','picked_up','completed','cancelled'));

alter table public.delivery_cloud_pickups
  add constraint delivery_cloud_pickups_driver_v2_check
  check (
    (status in ('assigned','arrived','picked_up','completed') and driver_id is not null)
    or (status = 'requested' and driver_id is null)
    or status = 'cancelled'
  );

create index if not exists cloud_pickups_shop_idx
  on public.delivery_cloud_pickups(shop_id, created_at desc)
  where shop_id is not null;

-- Driver Settlements (COD Remittance & Earnings Payouts) + Immutable Driver Wallet Ledger
create table if not exists public.delivery_driver_settlements (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.delivery_cloud_accounts(user_id) on delete cascade,
  kind text not null check (kind in ('cod_remit','payout')),
  amount bigint not null check (amount between 1000 and 500000000),
  order_ids uuid[] not null default '{}'::uuid[],
  reference_code text not null default '' check (length(reference_code) <= 200),
  note text not null default '' check (length(note) <= 500),
  state text not null default 'requested' check (state in ('requested','approved','rejected','completed')),
  reviewed_by uuid references auth.users(id),
  review_note text not null default '' check (length(review_note) <= 500),
  completion_evidence text not null default '' check (length(completion_evidence) <= 500),
  request_key uuid not null,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (driver_id, request_key)
);

create index if not exists delivery_driver_settlements_driver_idx
  on public.delivery_driver_settlements(driver_id, created_at desc, id desc);
create index if not exists delivery_driver_settlements_state_idx
  on public.delivery_driver_settlements(state, created_at desc, id desc);

create table if not exists public.delivery_driver_wallet_entries (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.delivery_cloud_accounts(user_id) on delete cascade,
  order_id uuid references public.delivery_cloud_orders(id) on delete set null,
  settlement_id uuid references public.delivery_driver_settlements(id) on delete restrict,
  kind text not null check (kind in ('trip_earning','payout_debit')),
  gross_fee integer not null default 0 check (gross_fee >= 0),
  platform_commission integer not null default 0 check (platform_commission >= 0),
  amount bigint not null check (
    (kind = 'trip_earning' and amount > 0 and amount = gross_fee - platform_commission)
    or (kind = 'payout_debit' and amount < 0 and gross_fee = 0 and platform_commission = 0)
  ),
  note text not null default '' check (length(note) <= 500),
  created_at timestamptz not null default now()
);

create unique index if not exists delivery_driver_wallet_order_earning_key
  on public.delivery_driver_wallet_entries(order_id)
  where order_id is not null and kind = 'trip_earning';

create unique index if not exists delivery_driver_wallet_settlement_debit_key
  on public.delivery_driver_wallet_entries(settlement_id)
  where settlement_id is not null and kind = 'payout_debit';

create index if not exists delivery_driver_wallet_driver_idx
  on public.delivery_driver_wallet_entries(driver_id, created_at desc, id desc);

drop trigger if exists immutable on public.delivery_driver_wallet_entries;
create trigger immutable before update or delete on public.delivery_driver_wallet_entries
  for each row execute function public.delivery_market_immutable();

alter table public.delivery_driver_settlements enable row level security;
alter table public.delivery_driver_wallet_entries enable row level security;
revoke all on public.delivery_driver_settlements, public.delivery_driver_wallet_entries
  from public, anon, authenticated;

-- ============================================================================
-- 2. PRIVATE CROSS-ROLE NOTIFICATION & FINALIZATION HELPERS
-- ============================================================================

create or replace function public.delivery_notify_operators(
  p_exclude uuid,
  p_category text,
  p_kind text,
  p_title text,
  p_body text,
  p_ref_type text default null,
  p_ref_id uuid default null,
  p_meta jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path='' as $$
declare
  op_uid uuid;
begin
  for op_uid in
    select ap.user_id
    from public.delivery_api_profiles ap
    left join public.delivery_cloud_accounts ca on ca.user_id = ap.user_id
    where ap.role = 'operator'
      and not coalesce(ca.blocked, false)
      and ap.user_id is distinct from p_exclude
  loop
    perform public.delivery_emit_notification(
      op_uid, p_category, p_kind, p_title, p_body, p_ref_type, p_ref_id, p_meta
    );
  end loop;
end; $$;
revoke all on function public.delivery_notify_operators(uuid,text,text,text,text,text,uuid,jsonb)
  from public, anon, authenticated;

create or replace function public.delivery_notify_shop_team(
  p_shop uuid,
  p_exclude uuid,
  p_min_role text,
  p_category text,
  p_kind text,
  p_title text,
  p_body text,
  p_ref_type text default null,
  p_ref_id uuid default null,
  p_meta jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path='' as $$
declare
  rcp uuid;
begin
  if p_shop is null then return; end if;
  for rcp in
    select distinct u_id
    from (
      select s.owner_id as u_id
      from public.delivery_market_shops s
      join public.delivery_cloud_accounts oa on oa.user_id = s.owner_id
      where s.id = p_shop and not oa.blocked
      union
      select st.user_id as u_id
      from public.delivery_market_shop_staff st
      join public.delivery_cloud_accounts sa on sa.user_id = st.user_id
      where st.shop_id = p_shop
        and st.active
        and not sa.blocked
        and (p_min_role = 'staff' or st.role = 'manager')
    ) team
    where u_id is not null and u_id is distinct from p_exclude
  loop
    perform public.delivery_emit_notification(
      rcp, p_category, p_kind, p_title, p_body, p_ref_type, p_ref_id, p_meta
    );
  end loop;
end; $$;
revoke all on function public.delivery_notify_shop_team(uuid,uuid,text,text,text,text,text,text,uuid,jsonb)
  from public, anon, authenticated;

-- Finalize Marketplace shop orders across single/split forward parcels + auto-sync COD collection
create or replace function public.delivery_market_finalize_order_shipments(
  p_shop_order_id uuid,
  p_actor uuid,
  p_cancel_reason text default ''
) returns void
language plpgsql security definer set search_path='' as $$
declare
  so public.delivery_market_shop_orders;
  purchase public.delivery_market_purchases;
  v_has_split boolean := false;
  v_active integer := 0;
  v_delivered integer := 0;
  v_failed integer := 0;
  v_all_cash_collected boolean := false;
  v_source text := 'user';
  goods bigint;
  shop_disc bigint;
  plat_disc bigint;
  freight bigint;
  due bigint;
  v_proposer uuid;
  f_id uuid;
begin
  if p_shop_order_id is null then return; end if;
  select * into so from public.delivery_market_shop_orders where id = p_shop_order_id for update;
  if not found or so.state = 'cancelled' then return; end if;

  select exists(select 1 from public.delivery_market_shipments where order_id = so.id) into v_has_split;
  if v_has_split then
    select
      count(*) filter (where co.status not in ('delivered','cancelled','returned')),
      count(*) filter (where co.status = 'delivered'),
      count(*) filter (where co.status in ('cancelled','returned')),
      bool_and(
        co.status = 'delivered'
        and (co.payable_fee = 0 or co.payment_status = 'PAID' or co.cash_collected_fee >= co.payable_fee)
        and co.cash_collected_cod >= co.cod_amount
      ),
      coalesce(max(co.cash_collected_by::text)::uuid, max(co.driver_id::text)::uuid, p_actor, so.merchant_id)
    into v_active, v_delivered, v_failed, v_all_cash_collected, v_proposer
    from public.delivery_market_shipments ms
    join public.delivery_cloud_orders co on co.id = ms.delivery_id
    where ms.order_id = so.id;
  elsif so.delivery_id is not null then
    select
      count(*) filter (where co.status not in ('delivered','cancelled','returned')),
      count(*) filter (where co.status = 'delivered'),
      count(*) filter (where co.status in ('cancelled','returned')),
      bool_and(
        co.status = 'delivered'
        and (co.payable_fee = 0 or co.payment_status = 'PAID' or co.cash_collected_fee >= co.payable_fee)
        and co.cash_collected_cod >= co.cod_amount
      ),
      coalesce(max(co.cash_collected_by::text)::uuid, max(co.driver_id::text)::uuid, p_actor, so.merchant_id)
    into v_active, v_delivered, v_failed, v_all_cash_collected, v_proposer
    from public.delivery_cloud_orders co
    where co.id = so.delivery_id;
  else
    return;
  end if;

  if v_active > 0 then
    return;
  end if;

  select * into purchase from public.delivery_market_purchases where id = so.purchase_id;

  if v_delivered = 0 and v_failed > 0 then
    if p_actor is null then
      if current_setting('ghst.carrier_sync', true) is distinct from 'on' then
        raise sqlstate 'PT403' using message = 'Thiếu nguồn hủy/hoàn vận đơn.';
      end if;
      v_source := 'carrier';
    end if;
    perform public.delivery_market_release_order_allocations(so, p_actor, v_source, 'shipping_cancel_release');
    update public.delivery_market_shop_orders
      set state = 'cancelled',
          reason = coalesce(nullif(btrim(p_cancel_reason), ''), 'Vận đơn hủy hoặc hoàn trả toàn bộ'),
          version = version + 1,
          updated_at = now()
      where id = so.id;
    insert into public.delivery_market_events(order_id, actor_id, actor_source, action, reason)
      values (so.id, p_actor, v_source, 'shipping_cancel', coalesce(p_cancel_reason, ''));
    insert into public.delivery_market_notifications(user_id, order_id, kind)
      values (so.owner_id, so.id, 'cancel'), (so.merchant_id, so.id, 'cancel');
    perform public.delivery_notify_shop_team(
      so.shop_id, so.merchant_id, 'staff', 'market', 'cancel',
      'Đơn hàng tại cửa hàng đã hủy/hoàn trả',
      'Vận đơn của đơn mua ' || left(so.id::text, 8) || ' đã hủy hoặc hoàn trả, tồn kho đã được hoàn lại.',
      'market_order', so.id, jsonb_build_object('order_id', so.id)
    );
    if purchase.payment_status = 'PAID' then
      update public.delivery_market_purchases set payment_status = 'REVIEW' where id = purchase.id;
    end if;
    return;
  end if;

  if v_delivered > 0 then
    if so.delivered_at is null then
      update public.delivery_market_shop_orders
        set delivered_at = now(),
            version = version + 1,
            updated_at = now()
        where id = so.id
        returning * into so;
    end if;

    if purchase.payment_method = 'cod' and v_failed = 0 and coalesce(v_all_cash_collected, false) then
      goods := (so.snapshot->>'subtotal')::bigint;
      shop_disc := coalesce((so.snapshot->>'shop_discount')::bigint, 0);
      plat_disc := coalesce((so.snapshot->>'platform_discount')::bigint, 0);
      freight := (so.snapshot->>'shipping_fee')::bigint;
      due := greatest(0, goods - shop_disc - plat_disc) + freight;
      if due > 0 and v_proposer is not null and not exists (
        select 1 from public.delivery_market_finance
        where order_id = so.id and kind = 'collection' and state <> 'rejected'
      ) then
        insert into public.delivery_market_finance(
          order_id, kind, amount, proposer, reason, evidence, request_key
        ) values (
          so.id,
          'collection',
          due::integer,
          v_proposer,
          'Tự động ghi nhận thu đủ tiền mặt COD khi giao hoàn tất',
          'AUTO-COD-' || left(so.id::text, 8),
          so.id
        )
        on conflict (proposer, request_key) do nothing
        returning id into f_id;

        if f_id is not null then
          perform public.delivery_notify_operators(
            v_proposer,
            'market',
            'finance_collection_requested',
            'Cần đối soát khoản thu COD ' || due || ' đ',
            'Tài xế đã giao hàng và thu đủ tiền mặt COD cho đơn mua ' || left(so.id::text, 8) || '.',
            'finance',
            f_id,
            jsonb_build_object('order_id', so.id, 'amount', due, 'kind', 'collection')
          );
        end if;
      end if;
    end if;
  end if;
end; $$;
revoke all on function public.delivery_market_finalize_order_shipments(uuid,uuid,text)
  from public, anon, authenticated;

-- Update forward shipment triggers to handle delivered, cancelled, returned & mixed split parcels
create or replace function public.delivery_market_delivered() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  target_order uuid;
begin
  if new.status = 'delivered' and old.status is distinct from new.status then
    select order_id into target_order from public.delivery_market_shipments where delivery_id = new.id;
    if target_order is null then
      select id into target_order from public.delivery_market_shop_orders where delivery_id = new.id;
    end if;
    if target_order is not null then
      perform public.delivery_market_finalize_order_shipments(target_order, auth.uid(), '');
    end if;
  end if;
  return new;
end $$;

create or replace function public.delivery_market_shipping_cancel() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  target_id uuid;
begin
  if new.status in ('cancelled', 'returned') and old.status is distinct from new.status then
    if exists (select 1 from public.delivery_market_returns where return_delivery_id = new.id) then
      return new;
    end if;
    select order_id into target_id from public.delivery_market_shipments where delivery_id = new.id;
    if target_id is null then
      select id into target_id from public.delivery_market_shop_orders where delivery_id = new.id;
    end if;
    if target_id is not null then
      perform public.delivery_market_finalize_order_shipments(
        target_id,
        auth.uid(),
        case
          when new.status = 'returned' then coalesce(nullif(btrim(new.cancel_reason), ''), 'Kiện hàng đã hoàn trả về cửa hàng')
          else coalesce(new.cancel_reason, '')
        end
      );
    end if;
  end if;
  return new;
end $$;

drop trigger if exists delivery_market_shipping_cancel on public.delivery_cloud_orders;
create trigger delivery_market_shipping_cancel
  after update of status on public.delivery_cloud_orders
  for each row execute function public.delivery_market_shipping_cancel();

-- ============================================================================
-- 3. DRIVER WALLET ACCRUAL, RETURN SHIPMENT NOTIFICATIONS & ORDER TRIGGER
-- ============================================================================

create or replace function public.delivery_cloud_orders_after_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  v_forward_shop_order uuid;
  v_forward_shop_id uuid;
  v_return_row record;
  is_market_forward boolean := false;
  is_return_shipment boolean := false;
  is_market_linked boolean := false;
  v_earn bigint := 0;
  v_commission integer := 0;
  v_driver_net integer := 0;
  v_wallet_entry uuid;
  v_title text;
  v_body text;
  v_pay_body text;
  v_meta jsonb;
  v_fee_delta integer := 0;
  v_cod_delta integer := 0;
  rcp uuid;
begin
  select so.id, so.shop_id
    into v_forward_shop_order, v_forward_shop_id
    from public.delivery_market_shop_orders so
    where so.delivery_id = new.id
    limit 1;

  if v_forward_shop_order is null then
    select so.id, so.shop_id
      into v_forward_shop_order, v_forward_shop_id
      from public.delivery_market_shipments ms
      join public.delivery_market_shop_orders so on so.id = ms.order_id
      where ms.delivery_id = new.id
      limit 1;
  end if;

  is_market_forward := v_forward_shop_order is not null;

  select r.id, r.order_id, so.shop_id, so.owner_id, so.merchant_id
    into v_return_row
    from public.delivery_market_returns r
    join public.delivery_market_shop_orders so on so.id = r.order_id
    where r.return_delivery_id = new.id
    limit 1;

  is_return_shipment := v_return_row.id is not null;
  is_market_linked := is_market_forward or is_return_shipment;

  v_meta := jsonb_build_object(
    'tracking_code', new.tracking_code,
    'status', new.status,
    'payment_status', new.payment_status,
    'shipping_fee', new.shipping_fee,
    'coin_discount', new.coin_discount,
    'payable_fee', new.payable_fee,
    'cash_collected_fee', new.cash_collected_fee,
    'cash_collected_cod', new.cash_collected_cod
  );

  if tg_op = 'INSERT' then
    if new.merchant_id is not null and new.merchant_id is distinct from new.owner_id
       and new.merchant_id is distinct from actor and not new.merchant_ready then
      perform public.delivery_emit_notification(
        new.merchant_id, 'shipping', 'merchant_prepare',
        'Đơn gửi hàng mới chờ chuẩn bị',
        'Vận đơn ' || new.tracking_code || ' đang chờ cửa hàng xác nhận sẵn sàng bàn giao.',
        'cloud_order', new.id, v_meta
      );
    end if;
    return new;
  end if;

  -- Driver Wallet trip earnings accrual (85% net to Driver, 15% platform fee)
  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and new.driver_id is not null
     and new.fulfillment_provider is null
     and new.shipping_fee > 0 then
    v_commission := floor(new.shipping_fee * 0.15)::integer;
    v_driver_net := greatest(1, new.shipping_fee - v_commission);
    v_commission := new.shipping_fee - v_driver_net;
    insert into public.delivery_driver_wallet_entries(
      driver_id, order_id, kind, gross_fee, platform_commission, amount, note
    ) values (
      new.driver_id,
      new.id,
      'trip_earning',
      new.shipping_fee,
      v_commission,
      v_driver_net,
      'Thu nhập chuyến giao ' || new.tracking_code
    )
    on conflict (order_id) where order_id is not null and kind = 'trip_earning' do nothing
    returning id into v_wallet_entry;

    if v_wallet_entry is not null then
      perform public.delivery_emit_notification(
        new.driver_id,
        'shipping',
        'driver_trip_earning',
        'Cộng +' || v_driver_net || ' đ vào Ví Tài xế',
        'Hoàn tất vận đơn ' || new.tracking_code || ' · Cước ' || new.shipping_fee || ' đ (khấu trừ phí nền tảng 15%: ' || v_commission || ' đ).',
        'cloud_order',
        new.id,
        v_meta || jsonb_build_object('driver_earning', v_driver_net, 'platform_commission', v_commission)
      );
    end if;
  end if;

  -- Sync Marketplace COD collection even when cash_collected happens on an already-delivered order
  if is_market_forward and new.status = 'delivered' and (
    new.cash_collected_fee > coalesce(old.cash_collected_fee, 0)
    or new.cash_collected_cod > coalesce(old.cash_collected_cod, 0)
  ) then
    perform public.delivery_market_finalize_order_shipments(v_forward_shop_order, actor, '');
  end if;

  -- Standalone shipping coin refund / accrual (strictly excludes Marketplace & return shipments)
  if not is_market_linked and new.coin_discount > 0
     and new.status in ('cancelled', 'returned')
     and old.status not in ('cancelled', 'returned') then
    if not exists (
      select 1 from public.delivery_market_coin_ledger
      where user_id = new.owner_id and kind = 'release_shipping_cancel' and reference_id = new.id
    ) then
      insert into public.delivery_market_coin_wallets(user_id, balance)
        values (new.owner_id, new.coin_discount)
        on conflict (user_id) do update
          set balance = public.delivery_market_coin_wallets.balance + excluded.balance,
              updated_at = now();
      insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
        values (new.owner_id, new.coin_discount, 'release_shipping_cancel', new.id);
      perform public.delivery_emit_notification(
        new.owner_id, 'promo', 'release_shipping_cancel',
        'Hoàn lại Xu cước vận chuyển',
        'Đã hoàn +' || new.coin_discount || ' Xu vào Ví Xu từ vận đơn ' || new.tracking_code || '.',
        'cloud_order', new.id, v_meta || jsonb_build_object('coins_delta', new.coin_discount)
      );
    end if;
  end if;

  if not is_market_linked and new.status = 'delivered' and old.status is distinct from 'delivered' then
    v_earn := floor(greatest(0, new.payable_fee) * 0.01)::bigint;
    if v_earn > 0 and not exists (
      select 1 from public.delivery_market_coin_ledger
      where user_id = new.owner_id and kind = 'earn_shipping' and reference_id = new.id
    ) then
      insert into public.delivery_market_coin_wallets(user_id, balance)
        values (new.owner_id, v_earn)
        on conflict (user_id) do update
          set balance = public.delivery_market_coin_wallets.balance + excluded.balance,
              updated_at = now();
      insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
        values (new.owner_id, v_earn, 'earn_shipping', new.id);
      perform public.delivery_emit_notification(
        new.owner_id, 'promo', 'earn_shipping',
        'Tích lũy Xu giao hàng thành công',
        'Bạn nhận được +' || v_earn || ' Xu thưởng từ vận đơn ' || new.tracking_code || '.',
        'cloud_order', new.id, v_meta || jsonb_build_object('coins_delta', v_earn)
      );
    end if;
  end if;

  v_fee_delta := greatest(0, new.cash_collected_fee - coalesce(old.cash_collected_fee, 0));
  v_cod_delta := greatest(0, new.cash_collected_cod - coalesce(old.cash_collected_cod, 0));
  if v_fee_delta > 0 or v_cod_delta > 0 then
    v_pay_body := case
      when v_fee_delta > 0 and v_cod_delta > 0 then
        'Tài xế đã xác nhận thu tiền mặt cước ' || v_fee_delta || ' đ và COD ' || v_cod_delta || ' đ cho vận đơn ' || new.tracking_code || '.'
      when v_fee_delta > 0 then
        'Tài xế đã xác nhận thu tiền mặt cước ' || v_fee_delta || ' đ cho vận đơn ' || new.tracking_code || '.'
      else
        'Tài xế đã xác nhận thu hộ COD ' || v_cod_delta || ' đ cho vận đơn ' || new.tracking_code || '.'
    end;
    for rcp in
      select distinct u_id
      from unnest(array[new.owner_id, new.merchant_id]) as u_id
      where u_id is not null and u_id is distinct from actor
    loop
      perform public.delivery_emit_notification(
        rcp, 'shipping', 'cash_collected',
        'Đã xác nhận thu tiền mặt',
        v_pay_body, 'cloud_order', new.id, v_meta
      );
    end loop;
  elsif new.payment_status = 'PAID'
        and old.payment_status is distinct from 'PAID'
        and new.cash_collected_fee = coalesce(old.cash_collected_fee, 0) then
    for rcp in
      select distinct u_id
      from unnest(array[new.owner_id, new.merchant_id]) as u_id
      where u_id is not null and u_id is distinct from actor
    loop
      perform public.delivery_emit_notification(
        rcp, 'shipping', 'payment_paid',
        'Thanh toán cước trực tuyến thành công',
        'Vận đơn ' || new.tracking_code || ' đã ghi nhận thanh toán cước ' || new.payable_fee || ' đ.',
        'cloud_order', new.id, v_meta
      );
    end loop;
  end if;

  if new.merchant_ready and not old.merchant_ready and new.owner_id is distinct from actor then
    perform public.delivery_emit_notification(
      new.owner_id, 'shipping', 'merchant_ready',
      'Cửa hàng đã sẵn sàng giao kiện',
      'Vận đơn ' || new.tracking_code || ' đã sẵn sàng và đang tìm tài xế nhận chuyến.',
      'cloud_order', new.id, v_meta
    );
  end if;

  -- Reverse return shipment terminal notifications to Shop team & Buyer
  if is_return_shipment and new.status in ('delivered', 'cancelled', 'returned') and old.status is distinct from new.status then
    perform public.delivery_notify_shop_team(
      v_return_row.shop_id,
      actor,
      'staff',
      'market',
      'return_shipment_' || new.status,
      case new.status
        when 'delivered' then 'Kiện hàng hoàn trả đã giao tới cửa hàng'
        when 'returned' then 'Kiện hàng hoàn trả đã quay đầu về người mua'
        else 'Vận đơn thu hồi hàng trả đã hủy'
      end,
      'Vận đơn hoàn hàng ' || new.tracking_code || ' vừa chuyển sang trạng thái ' || new.status || '. Cửa hàng có thể kiểm tra và xác nhận nhập kho.',
      'market_order',
      v_return_row.order_id,
      v_meta || jsonb_build_object('return_id', v_return_row.id)
    );
  end if;

  if new.status is distinct from old.status then
    case new.status
      when 'searching' then
        if old.driver_id is not null and new.driver_id is null then
          v_title := 'Vận đơn đang tìm lại tài xế';
          v_body := 'Vận đơn ' || new.tracking_code || ' đã được mở lại trên sàn điều phối để gán tài xế mới.';
        else
          v_title := null;
        end if;
      when 'accepted' then
        v_title := 'Tài xế đã nhận vận đơn';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã có tài xế tiếp nhận và đang di chuyển lấy hàng.';
      when 'arrivingPickup' then
        v_title := 'Tài xế đã tới điểm lấy hàng';
        v_body := 'Tài xế đang làm thủ tục nhận kiện hàng ' || new.tracking_code || '.';
      when 'inTransit' then
        v_title := 'Đơn hàng đang trên đường giao';
        v_body := 'Tài xế đã nhận kiện và đang giao vận đơn ' || new.tracking_code || ' tới người nhận.';
      when 'delivered' then
        v_title := 'Giao hàng thành công';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã giao hoàn tất cho người nhận.';
      when 'failed' then
        v_title := 'Giao hàng tạm hoãn';
        v_body := 'Vận đơn ' || new.tracking_code || ' chưa giao được, vui lòng kiểm tra chi tiết hành trình.';
      when 'returning' then
        v_title := 'Đơn hàng đang chuyển hoàn';
        v_body := 'Vận đơn ' || new.tracking_code || ' đang được tài xế hoàn trả về điểm gửi.';
      when 'returned' then
        v_title := 'Đã hoàn trả kiện hàng';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã bàn giao hoàn trả thành công.';
      when 'cancelled' then
        v_title := 'Vận đơn đã hủy';
        v_body := 'Vận đơn ' || new.tracking_code || ' đã hủy'
          || case when length(btrim(coalesce(new.cancel_reason, ''))) > 0
                  then ': ' || left(btrim(new.cancel_reason), 180)
                  else '.' end;
      else
        v_title := null;
    end case;

    if v_title is not null then
      for rcp in
        select distinct u_id
        from (
          select unnest(array[
            new.owner_id,
            new.merchant_id,
            case when new.status in ('cancelled', 'searching') then old.driver_id else null end
          ]) as u_id
          union
          select st.user_id as u_id
          from public.delivery_market_shop_staff st
          join public.delivery_cloud_accounts sa on sa.user_id = st.user_id
          where v_forward_shop_id is not null
            and st.shop_id = v_forward_shop_id
            and st.active
            and not sa.blocked
        ) notify_targets
        where u_id is not null and u_id is distinct from actor
      loop
        perform public.delivery_emit_notification(
          rcp, 'shipping', 'order_' || new.status,
          v_title, v_body, 'cloud_order', new.id, v_meta
        );
      end loop;
    end if;
  end if;

  return new;
end; $$;
revoke all on function public.delivery_cloud_orders_after_change() from public, anon, authenticated;

-- ============================================================================
-- 4. OTP READ, DIRECT ORDER GET, LIST, TRANSITION, LIVE CHAT & DRIVER FINANCE
-- ============================================================================

create or replace function public.delivery_cloud_order_otp(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  s public.delivery_cloud_order_secrets;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  select * into o from public.delivery_cloud_orders where id = p_order;
  if not found or (
    not public.delivery_is_operator()
    and (
      uid = o.driver_id
      or (
        uid not in (o.owner_id, coalesce(o.merchant_id, o.owner_id))
        and not public.delivery_can_access_cloud_order_as_shop_staff(o.id, uid)
      )
    )
  ) then
    raise sqlstate 'PT403' using message = 'Chỉ người đặt đơn, cửa hàng hoặc quản trị viên được xem mã OTP nhận hàng.';
  end if;
  select * into s from public.delivery_cloud_order_secrets where order_id = o.id;
  if not found then
    return jsonb_build_object('required', false, 'otp_code', null, 'verified_at', null);
  end if;
  return jsonb_build_object('required', true, 'otp_code', s.otp_code, 'verified_at', s.verified_at);
end $$;
revoke all on function public.delivery_cloud_order_otp(uuid) from public, anon;
grant execute on function public.delivery_cloud_order_otp(uuid) to authenticated;

create or replace function public.delivery_cloud_get(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if not op and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Tài khoản chưa có hồ sơ hoặc đang khóa.';
  end if;
  select * into o from public.delivery_cloud_orders where id = p_order;
  if not found or (
    not op
    and uid not in (o.owner_id, coalesce(o.merchant_id, o.owner_id), coalesce(o.driver_id, o.owner_id))
    and not public.delivery_can_access_cloud_order_as_shop_staff(o.id, uid)
  ) then
    raise sqlstate 'PT404' using message = 'Không tìm thấy vận đơn được phép truy cập.';
  end if;
  return public.delivery_cloud_order_enriched(o);
end $$;
revoke all on function public.delivery_cloud_get(uuid) from public, anon;
grant execute on function public.delivery_cloud_get(uuid) to authenticated;

create or replace function public.delivery_cloud_list(
  p_queue boolean default false,
  p_before timestamptz default null,
  p_before_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  a public.delivery_cloud_accounts;
  uid uuid := auth.uid();
  result jsonb;
begin
  select * into a from public.delivery_cloud_accounts where user_id = uid;
  if not public.delivery_is_operator() and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Cần hồ sơ đang hoạt động.';
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
      select * from public.delivery_cloud_orders co
      where co.status = 'searching'
        and co.merchant_ready
        and co.driver_id is null
        and uid is distinct from co.owner_id
        and uid is distinct from co.merchant_id
        and not public.delivery_can_access_cloud_order_as_shop_staff(co.id, uid)
        and (
          p_before is null
          or (p_before_id is null and co.created_at < p_before)
          or (co.created_at, co.id) < (p_before, p_before_id)
        )
      order by co.created_at desc, co.id desc
      limit 50
    ) o;
  else
    select coalesce(
      jsonb_agg(public.delivery_cloud_order_enriched(o) order by o.created_at desc, o.id desc),
      '[]'::jsonb
    )
    into result
    from (
      select * from public.delivery_cloud_orders co
      where (
        public.delivery_is_operator()
        or uid in (co.owner_id, co.merchant_id, co.driver_id)
        or public.delivery_can_access_cloud_order_as_shop_staff(co.id, uid)
      )
        and (
          p_before is null
          or (p_before_id is null and co.created_at < p_before)
          or (co.created_at, co.id) < (p_before, p_before_id)
        )
      order by co.created_at desc, co.id desc
      limit 50
    ) o;
  end if;

  return jsonb_build_object('orders', result, 'page_size', 50);
end; $$;
revoke all on function public.delivery_cloud_list(boolean, timestamptz, uuid) from public, anon;
grant execute on function public.delivery_cloud_list(boolean, timestamptz, uuid) to authenticated;

create or replace function public.delivery_validate_event() returns trigger
language plpgsql set search_path='' as $$
declare previous_status text; next_status text; prev_gps record;
  lat1 float8; lng1 float8; lat2 float8; lng2 float8; a float8; dist_m float8; dt_sec float8;
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
      (previous_status in ('accepted','arrivingPickup') and next_status='searching' and exists(
        select 1 from public.delivery_cloud_orders where tracking_code=new.room_id and status='searching' and driver_id is null
      )) or
      (previous_status='inTransit' and next_status in ('delivered','failed')) or
      (previous_status='failed' and next_status in ('inTransit','returning')) or
      (previous_status='returning' and next_status in ('delivered','returned'))
    ) then raise exception 'Invalid delivery transition'; end if;
  end if;
  if new.kind='chat' then
    if length(coalesce(new.payload->>'text','')) not between 1 and 2000 then raise exception 'Invalid chat message'; end if;
    new.payload:=jsonb_set(new.payload,'{isCustomer}',to_jsonb(not public.delivery_is_driver(new.room_id)));
  end if;
  if new.kind='gps' then
    if jsonb_typeof(new.payload->'latitude') is distinct from 'number' or
      jsonb_typeof(new.payload->'longitude') is distinct from 'number' or
      (new.payload->>'latitude')::numeric not between -90 and 90 or
      (new.payload->>'longitude')::numeric not between -180 and 180 or
      not(new.payload ?& array['latitude','longitude']) then
      raise exception 'Invalid location';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('gps:'||new.room_id,0));
    select payload,created_at into prev_gps from public.delivery_live_events
      where room_id=new.room_id and kind='gps' order by created_at desc,id desc limit 1;
    if prev_gps.payload is not null then
      lat1:=(prev_gps.payload->>'latitude')::float8; lng1:=(prev_gps.payload->>'longitude')::float8;
      lat2:=(new.payload->>'latitude')::float8; lng2:=(new.payload->>'longitude')::float8;
      a:=power(sin(radians(lat2-lat1)/2),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lng2-lng1)/2),2);
      dist_m:=6371000.0*2.0*asin(sqrt(least(1.0,a)));
      if jsonb_typeof(new.payload->'timestamp_ms')='number' and jsonb_typeof(prev_gps.payload->'timestamp_ms')='number' then
        dt_sec:=((new.payload->>'timestamp_ms')::float8-(prev_gps.payload->>'timestamp_ms')::float8)/1000.0;
      else
        dt_sec:=extract(epoch from (new.created_at-prev_gps.created_at));
      end if;
      if dt_sec<=0 and dist_m>30.0 then
        raise exception 'GPS jump rejected';
      end if;
      if dt_sec>0 and (dist_m>10.0 or dt_sec>=0.5) and (dist_m/greatest(dt_sec,0.1))*3.6>120.0 then
        raise exception 'GPS speed exceeded 120 km/h';
      end if;
    end if;
  end if;
  if new.kind='pod' and (split_part(coalesce(new.payload->>'path',''),'/',1)<>new.room_id or
    strpos(coalesce(new.payload->>'path',''),'..')>0 or not exists(
      select 1 from storage.objects where bucket_id='delivery-evidence' and name=new.payload->>'path')) then
    raise exception 'Invalid delivery evidence';
  end if;
  return new;
end; $$;

create or replace function public.delivery_cloud_transition(
  p_order uuid,
  p_action text,
  p_version integer,
  p_request_key uuid,
  p_reason text default ''
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  o public.delivery_cloud_orders;
  a public.delivery_cloud_accounts;
  uid uuid := auth.uid();
  op boolean;
  v_is_shop_staff boolean := false;
  v_is_shop_manager boolean := false;
  v_prev_driver uuid := null;
  next_status text;
  request jsonb;
  prior public.delivery_cloud_commands;
  response jsonb;
  secret public.delivery_cloud_order_secrets;
  candidate_otp text;
  history_reason text := btrim(coalesce(p_reason, ''));
  v_pay_method text;
  need_fee boolean := false;
  need_cod boolean := false;
  v_fee_now integer := 0;
  v_cod_now integer := 0;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  op := public.delivery_is_operator();
  if not op and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Tài khoản chưa có hồ sơ hoặc đang khóa.';
  end if;
  if p_request_key is null then
    raise sqlstate 'PT400' using message = 'Thiếu mã yêu cầu.';
  end if;
  if p_action is null
     or p_action not in (
       'ready','claim','cancel','arrive','pickup','deliver',
       'fail','retry','return','complete_return','collect_cash',
       'release','reassign'
     )
     or p_reason is null
     or length(p_reason) > 500 then
    raise sqlstate 'PT400' using message = 'Thao tác hoặc lý do không hợp lệ.';
  end if;
  if p_action in ('cancel','fail','return','release','reassign') and length(btrim(p_reason)) < 3 then
    raise sqlstate 'PT400' using message = 'Cần nhập lý do ít nhất 3 ký tự.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(uid::text || p_request_key::text, 0));
  request := jsonb_build_object(
    'order', p_order,
    'action', p_action,
    'version', p_version,
    'reason', case when p_action = 'deliver' and p_reason ~ '^(OTP:)?[0-9]{6}$' then 'OTP_SUBMITTED' else p_reason end
  );
  select * into prior
    from public.delivery_cloud_commands
    where actor_id = uid and request_key = p_request_key;
  if found then
    if prior.request_payload <> request then
      raise sqlstate 'PT409' using message = 'Mã yêu cầu đã dùng cho nội dung khác.';
    end if;
    return prior.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('driver:' || uid::text, 0));
  select * into o from public.delivery_cloud_orders where id = p_order for update;
  select * into a from public.delivery_cloud_accounts where user_id = uid;

  if o.id is not null then
    v_is_shop_staff := public.delivery_can_access_cloud_order_as_shop_staff(o.id, uid);
    if v_is_shop_staff then
      v_is_shop_manager := exists(
        select 1 from public.delivery_market_shop_orders so
        where (so.delivery_id = o.id or exists(select 1 from public.delivery_market_shipments ms where ms.order_id = so.id and ms.delivery_id = o.id))
          and public.delivery_market_can_access_shop(so.shop_id, uid, 'manager')
      );
    end if;
  end if;

  if o.id is null or (
    not op
    and uid not in (o.owner_id, coalesce(o.merchant_id, o.owner_id), coalesce(o.driver_id, o.owner_id))
    and not v_is_shop_staff
    and not (
      p_action = 'claim'
      and public.delivery_cloud_has_membership(a.user_id, 'driver')
      and o.status = 'searching'
      and o.merchant_ready
    )
  ) then
    raise sqlstate 'PT404' using message = 'Không tìm thấy đơn hàng được phép truy cập.';
  end if;

  if p_version is distinct from o.version then
    raise sqlstate 'PT409' using message = 'Đơn đã thay đổi. Vui lòng tải lại.';
  end if;

  next_status := o.status;

  if p_action = 'ready' then
    if (not op and uid is distinct from o.merchant_id and not v_is_shop_staff)
       or o.status <> 'searching' or o.merchant_ready then
      raise sqlstate 'PT409' using message = 'Không thể xác nhận cửa hàng sẵn sàng.';
    end if;
    o.merchant_ready := true;

  elsif p_action = 'claim' then
    if not public.delivery_cloud_has_membership(a.user_id, 'driver')
       or a.blocked
       or o.status <> 'searching'
       or not o.merchant_ready
       or o.driver_id is not null then
      raise sqlstate 'PT409' using message = 'Đơn không còn khả dụng hoặc tài khoản chưa được duyệt tài xế.';
    end if;
    if uid = o.owner_id or (o.merchant_id is not null and uid = o.merchant_id) or v_is_shop_staff then
      raise sqlstate 'PT403' using message = 'Không thể tự nhận vận chuyển đơn hàng của chính mình hoặc cửa hàng mình làm việc.';
    end if;
    if exists (
      select 1 from public.delivery_cloud_orders
      where driver_id = uid and status not in ('delivered','returned','cancelled')
    ) then
      raise sqlstate 'PT409' using message = 'Bạn đang có chuyến chưa hoàn tất.';
    end if;
    o.driver_id := uid;
    next_status := 'accepted';

  elsif p_action = 'release' then
    if uid is distinct from o.driver_id
       or not public.delivery_cloud_has_membership(uid, 'driver')
       or coalesce(a.blocked, true) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế đang nhận chuyến được nhả chuyến trước khi lấy hàng.';
    end if;
    if o.status not in ('accepted', 'arrivingPickup')
       or o.cash_collected_fee > 0
       or o.cash_collected_cod > 0 then
      raise sqlstate 'PT409' using message = 'Chỉ được nhả chuyến trước khi nhận kiện hàng và chưa thu tiền mặt.';
    end if;
    v_prev_driver := o.driver_id;
    o.driver_id := null;
    next_status := 'searching';
    history_reason := 'Tài xế nhả chuyến: ' || btrim(p_reason);

  elsif p_action = 'reassign' then
    if not op then
      raise sqlstate 'PT403' using message = 'Chỉ quản trị viên được điều phối lại tài xế.';
    end if;
    if o.status not in ('accepted', 'arrivingPickup')
       or o.driver_id is null
       or o.cash_collected_fee > 0
       or o.cash_collected_cod > 0 then
      raise sqlstate 'PT409' using message = 'Chỉ điều phối lại khi tài xế chưa lấy kiện hàng và chưa thu tiền mặt.';
    end if;
    v_prev_driver := o.driver_id;
    o.driver_id := null;
    next_status := 'searching';
    history_reason := 'Điều phối lại tài xế: ' || btrim(p_reason);

  elsif p_action = 'cancel' then
    if (not op and uid is distinct from o.owner_id and uid is distinct from o.merchant_id and not v_is_shop_manager)
       or o.status not in ('searching','accepted','arrivingPickup')
       or o.cash_collected_fee > 0
       or o.cash_collected_cod > 0
       or length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then
      raise sqlstate 'PT409' using message = 'Không thể hủy đơn hoặc chưa nhập lý do hợp lệ.';
    end if;
    next_status := 'cancelled';
    o.cancel_reason := btrim(p_reason);

  elsif p_action = 'collect_cash' then
    if not op and (
      uid is distinct from o.driver_id
      or not public.delivery_cloud_has_membership(uid, 'driver')
      or coalesce(a.blocked, true)
    ) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế nhận chuyến hoặc quản trị viên được xác nhận thu tiền mặt.';
    end if;
    if o.fulfillment_provider is not null then
      raise sqlstate 'PT409' using message = 'Đơn gửi qua hãng vận chuyển ngoài không thu tiền mặt nội bộ.';
    end if;
    if o.payment_status = 'REVIEW' or exists (
      select 1 from public.delivery_payment_transactions
      where order_id = o.id and status in ('CREATING','PENDING','REVIEW')
    ) then
      raise sqlstate 'PT409' using message = 'Đơn đang có giao dịch thanh toán trực tuyến chờ xử lý hoặc cần đối soát.';
    end if;

    v_pay_method := coalesce(o.details->>'payment_method', 'sender_cash');
    need_fee := (
      o.payment_status = 'UNPAID'
      and o.payable_fee > 0
      and o.cash_collected_fee = 0
      and (
        (v_pay_method = 'sender_cash' and o.status in ('arrivingPickup','inTransit','delivered'))
        or (v_pay_method = 'recipient_cash' and o.status in ('inTransit','delivered'))
      )
    );
    need_cod := (
      o.cod_amount > 0
      and o.cash_collected_cod < o.cod_amount
      and o.status in ('inTransit','delivered')
    );

    if not need_fee and not need_cod then
      raise sqlstate 'PT409' using message = 'Đơn hàng không còn khoản tiền mặt cần xác nhận thu.';
    end if;

    v_fee_now := case when need_fee then o.payable_fee else 0 end;
    v_cod_now := case when need_cod then (o.cod_amount - o.cash_collected_cod) else 0 end;

    if need_fee then
      o.cash_collected_fee := o.payable_fee;
      o.payment_status := 'PAID';
    end if;
    if need_cod then
      o.cash_collected_cod := o.cod_amount;
    end if;
    o.cash_collected_at := now();
    o.cash_collected_by := uid;

    history_reason := case
      when v_fee_now > 0 and v_cod_now > 0 then
        'Đã thu tiền mặt cước ' || v_fee_now || ' đ và COD ' || v_cod_now || ' đ'
      when v_fee_now > 0 then
        'Đã thu tiền mặt cước ' || v_fee_now || ' đ'
      else
        'Đã thu tiền mặt COD ' || v_cod_now || ' đ'
    end || case
      when length(history_reason) > 0 then ' · ' || left(history_reason, 200)
      else ''
    end;

  else
    if not op and (uid is distinct from o.driver_id or not public.delivery_cloud_has_membership(uid, 'driver')) then
      raise sqlstate 'PT403' using message = 'Chỉ tài xế nhận chuyến hoặc quản trị viên được cập nhật.';
    end if;
    next_status := case
      when p_action = 'arrive' and o.status = 'accepted' then 'arrivingPickup'
      when p_action = 'pickup' and o.status = 'arrivingPickup' then 'inTransit'
      when p_action = 'deliver' and o.status = 'inTransit' then 'delivered'
      when p_action = 'fail' and o.status = 'inTransit' then 'failed'
      when p_action = 'retry' and o.status = 'failed' then 'inTransit'
      when p_action = 'return' and o.status = 'failed' then 'returning'
      when p_action = 'complete_return' and o.status = 'returning' then 'returned'
    end;
    if next_status is null then
      raise sqlstate 'PT409' using message = 'Thao tác không phù hợp trạng thái đơn.';
    end if;
    if p_action = 'deliver' and not op then
      if coalesce((o.details->>'require_pod')::boolean, false) and not exists (
        select 1 from public.delivery_live_events where room_id = o.tracking_code and kind = 'pod'
      ) then
        raise sqlstate 'PT409' using message = 'Cần tải ảnh bằng chứng giao hàng trước khi hoàn tất.';
      end if;
      select * into secret from public.delivery_cloud_order_secrets where order_id = o.id for update;
      if found and secret.verified_at is null then
        candidate_otp := substring(btrim(p_reason) from '([0-9]{6})');
        if candidate_otp is null or encode(sha256(convert_to(candidate_otp, 'UTF8')), 'hex') <> secret.otp_hash then
          update public.delivery_cloud_order_secrets set attempts = attempts + 1 where order_id = o.id;
          raise sqlstate 'PT409' using message = 'Cần mã OTP 6 số hợp lệ từ người nhận để hoàn tất giao hàng.';
        end if;
        update public.delivery_cloud_order_secrets set verified_at = now(), attempts = attempts + 1 where order_id = o.id;
        history_reason := 'Đã xác thực OTP người nhận';
      end if;
    elsif p_action = 'deliver' and history_reason ~ '^(OTP:)?[0-9]{6}$' then
      history_reason := 'Đã xác thực giao hàng';
    end if;
  end if;

  update public.delivery_cloud_orders set
    status = next_status,
    driver_id = o.driver_id,
    merchant_ready = o.merchant_ready,
    cancel_reason = o.cancel_reason,
    payment_status = o.payment_status,
    cash_collected_fee = o.cash_collected_fee,
    cash_collected_cod = o.cash_collected_cod,
    cash_collected_at = o.cash_collected_at,
    cash_collected_by = o.cash_collected_by,
    version = version + 1,
    updated_at = now()
  where id = o.id returning * into o;

  if p_action = 'claim' then
    insert into public.delivery_live_members values (o.tracking_code, uid, 'driver')
      on conflict (room_id, user_id) do update set role = 'driver';
  elsif p_action in ('release', 'reassign') and v_prev_driver is not null then
    delete from public.delivery_live_members
      where room_id = o.tracking_code and user_id = v_prev_driver and role = 'driver';
    if p_action = 'release' then
      perform public.delivery_notify_operators(
        uid, 'shipping', 'driver_released_trip',
        'Tài xế vừa nhả vận đơn ' || o.tracking_code,
        'Lý do: ' || btrim(p_reason) || '. Đơn đã quay lại sàn tìm tài xế.',
        'cloud_order', o.id, jsonb_build_object('tracking_code', o.tracking_code, 'driver_id', v_prev_driver)
      );
    else
      insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
        values (uid, 'order_reassign', o.id, jsonb_build_object('previous_driver_id', v_prev_driver, 'reason', btrim(p_reason)));
    end if;
  end if;

  insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
    values (o.id, uid, p_action, o.status, o.version, history_reason);
  insert into public.delivery_live_events(room_id, kind, payload)
    values (o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));

  response := to_jsonb(o) - 'request_payload' - 'request_key';
  insert into public.delivery_cloud_commands values (uid, p_request_key, request, response, now());
  return response;
end; $$;
revoke all on function public.delivery_cloud_transition(uuid,text,integer,uuid,text) from public, anon;
grant execute on function public.delivery_cloud_transition(uuid,text,integer,uuid,text) to authenticated;

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
  v_shop_id uuid := null;
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

    select coalesce(
      (select so.shop_id from public.delivery_market_shop_orders so where so.delivery_id = o.id limit 1),
      (select so.shop_id from public.delivery_market_shipments ms join public.delivery_market_shop_orders so on so.id = ms.order_id where ms.delivery_id = o.id limit 1),
      (select so.shop_id from public.delivery_market_returns r join public.delivery_market_shop_orders so on so.id = r.order_id where r.return_delivery_id = o.id limit 1)
    ) into v_shop_id;

    for rcp in
      select distinct x
      from (
        select unnest(array[o.owner_id, o.merchant_id, o.driver_id]) as x
        union
        select st.user_id as x
        from public.delivery_market_shop_staff st
        join public.delivery_cloud_accounts sa on sa.user_id = st.user_id
        where v_shop_id is not null and st.shop_id = v_shop_id and st.active and not sa.blocked
      ) targets
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

-- Driver Wallet, Commission & COD Remittance RPC
create or replace function public.delivery_driver_finance(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  v_driver uuid;
  v_wallet_balance bigint := 0;
  v_gross_earnings bigint := 0;
  v_commission_total bigint := 0;
  v_payout_completed bigint := 0;
  v_payout_pending bigint := 0;
  v_cash_collected bigint := 0;
  v_cod_remitted bigint := 0;
  v_cod_pending bigint := 0;
  v_cod_unremitted bigint := 0;
  v_available_payout bigint := 0;
  v_amount bigint;
  v_ref text;
  v_note text;
  v_req_key uuid;
  v_order_ids uuid[] := '{}'::uuid[];
  s public.delivery_driver_settlements;
  v_decision text;
  v_filter text;
  v_kind_filter text;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập.';
  end if;
  if not op and not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Tài khoản chưa có hồ sơ hoặc đang khóa.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 8000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu ví tài xế không hợp lệ.';
  end if;

  if p_action in ('summary', 'remit_cod', 'request_payout') then
    v_driver := case
      when p_action = 'summary' and op and jsonb_typeof(d->'driver_id') = 'string' and btrim(d->>'driver_id') <> ''
      then (d->>'driver_id')::uuid
      else uid
    end;
    if not op and not public.delivery_cloud_has_membership(uid, 'driver') then
      raise sqlstate 'PT403' using message = 'Cần tư cách đối tác tài xế đã được duyệt.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('driver_wallet:' || v_driver::text, 0));

    select
      coalesce(sum(amount), 0),
      coalesce(sum(amount) filter (where kind = 'trip_earning'), 0),
      coalesce(sum(platform_commission) filter (where kind = 'trip_earning'), 0),
      coalesce(sum(-amount) filter (where kind = 'payout_debit'), 0)
    into v_wallet_balance, v_gross_earnings, v_commission_total, v_payout_completed
    from public.delivery_driver_wallet_entries
    where driver_id = v_driver;

    select
      coalesce(sum(amount) filter (where kind = 'payout' and state in ('requested','approved')), 0),
      coalesce(sum(amount) filter (where kind = 'cod_remit' and state = 'completed'), 0),
      coalesce(sum(amount) filter (where kind = 'cod_remit' and state in ('requested','approved')), 0)
    into v_payout_pending, v_cod_remitted, v_cod_pending
    from public.delivery_driver_settlements
    where driver_id = v_driver;

    select coalesce(sum(o.cash_collected_fee + o.cash_collected_cod), 0)
      into v_cash_collected
      from public.delivery_cloud_orders o
      where coalesce(o.cash_collected_by, o.driver_id) = v_driver
        and (o.cash_collected_fee > 0 or o.cash_collected_cod > 0);

    v_cod_unremitted := greatest(0, v_cash_collected - v_cod_remitted - v_cod_pending);
    v_available_payout := greatest(0, v_wallet_balance - v_payout_pending - v_cod_unremitted);

    if p_action = 'summary' then
      return jsonb_build_object(
        'driver_id', v_driver,
        'commission_rate_pct', 15,
        'driver_share_pct', 85,
        'wallet_balance', v_wallet_balance,
        'net_trip_earnings_total', v_gross_earnings,
        'platform_commission_total', v_commission_total,
        'payout_completed_total', v_payout_completed,
        'payout_pending_total', v_payout_pending,
        'cash_collected_total', v_cash_collected,
        'cod_remitted_total', v_cod_remitted,
        'cod_pending_total', v_cod_pending,
        'cod_unremitted_total', v_cod_unremitted,
        'available_payout', v_available_payout,
        'entries', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', e.id,
            'order_id', e.order_id,
            'tracking_code', co.tracking_code,
            'settlement_id', e.settlement_id,
            'kind', e.kind,
            'gross_fee', e.gross_fee,
            'platform_commission', e.platform_commission,
            'amount', e.amount,
            'note', e.note,
            'created_at', e.created_at
          ) order by e.created_at desc, e.id desc)
          from (
            select * from public.delivery_driver_wallet_entries
            where driver_id = v_driver
            order by created_at desc, id desc
            limit 40
          ) e
          left join public.delivery_cloud_orders co on co.id = e.order_id
        ), '[]'::jsonb),
        'settlements', coalesce((
          select jsonb_agg(to_jsonb(st) - 'request_key' order by st.created_at desc, st.id desc)
          from (
            select * from public.delivery_driver_settlements
            where driver_id = v_driver
            order by created_at desc, id desc
            limit 40
          ) st
        ), '[]'::jsonb),
        'cash_orders', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', co.id,
            'tracking_code', co.tracking_code,
            'status', co.status,
            'cash_collected_fee', co.cash_collected_fee,
            'cash_collected_cod', co.cash_collected_cod,
            'cash_total', co.cash_collected_fee + co.cash_collected_cod,
            'cash_collected_at', co.cash_collected_at
          ) order by co.cash_collected_at desc nulls last, co.id desc)
          from (
            select * from public.delivery_cloud_orders o2
            where coalesce(o2.cash_collected_by, o2.driver_id) = v_driver
              and (o2.cash_collected_fee > 0 or o2.cash_collected_cod > 0)
            order by o2.cash_collected_at desc nulls last, o2.id desc
            limit 30
          ) co
        ), '[]'::jsonb)
      );
    end if;

    if jsonb_typeof(d->'amount') is distinct from 'number'
       or (d->>'amount')::numeric <> trunc((d->>'amount')::numeric)
       or jsonb_typeof(d->'request_key') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Số tiền hoặc mã yêu cầu không hợp lệ.';
    end if;
    v_amount := (d->>'amount')::bigint;
    v_ref := btrim(coalesce(d->>'reference_code', ''));
    v_note := btrim(coalesce(d->>'note', ''));
    v_req_key := (d->>'request_key')::uuid;
    if length(v_ref) not between 3 and 200 or length(v_note) > 500 then
      raise sqlstate 'PT400' using message = 'Cần nhập mã giao dịch / tài khoản nhận từ 3 đến 200 ký tự.';
    end if;

    select * into s from public.delivery_driver_settlements where driver_id = uid and request_key = v_req_key;
    if found then
      if s.kind <> (case when p_action = 'remit_cod' then 'cod_remit' else 'payout' end)
         or s.amount <> v_amount then
        raise sqlstate 'PT409' using message = 'Mã yêu cầu đã được sử dụng cho nội dung khác.';
      end if;
      return jsonb_build_object('settlement', to_jsonb(s) - 'request_key');
    end if;

    if d ? 'order_ids' and jsonb_typeof(d->'order_ids') = 'array' then
      select coalesce(array_agg((x)::uuid), '{}'::uuid[])
        into v_order_ids
        from jsonb_array_elements_text(d->'order_ids') x;
    end if;

    if p_action = 'remit_cod' then
      if v_amount < 1000 or v_amount > v_cod_unremitted then
        raise sqlstate 'PT409' using message = 'Số tiền nộp COD vượt quá số dư tiền mặt đang giữ chưa nộp.';
      end if;
      insert into public.delivery_driver_settlements(
        driver_id, kind, amount, order_ids, reference_code, note, request_key
      ) values (
        uid, 'cod_remit', v_amount, v_order_ids, v_ref, v_note, v_req_key
      ) returning * into s;

      perform public.delivery_notify_operators(
        uid, 'shipping', 'driver_cod_remit_requested',
        'Tài xế gửi phiếu nộp COD ' || v_amount || ' đ',
        'Mã tham chiếu: ' || v_ref || '. Vui lòng kiểm tra và xác nhận đối soát.',
        'driver_settlement', s.id,
        jsonb_build_object('driver_id', uid, 'amount', v_amount, 'kind', 'cod_remit')
      );
      return jsonb_build_object('settlement', to_jsonb(s) - 'request_key');
    else
      if v_amount < 10000 or v_amount > v_available_payout then
        raise sqlstate 'PT409' using message = 'Số tiền rút tối thiểu 10.000 đ và không vượt số dư khả dụng sau đối trừ tiền mặt đang giữ.';
      end if;
      insert into public.delivery_driver_settlements(
        driver_id, kind, amount, reference_code, note, request_key
      ) values (
        uid, 'payout', v_amount, v_ref, v_note, v_req_key
      ) returning * into s;

      perform public.delivery_notify_operators(
        uid, 'shipping', 'driver_payout_requested',
        'Tài xế yêu cầu rút thu nhập ' || v_amount || ' đ',
        'Tài khoản nhận: ' || v_ref || '. Vui lòng kiểm tra và duyệt chi.',
        'driver_settlement', s.id,
        jsonb_build_object('driver_id', uid, 'amount', v_amount, 'kind', 'payout')
      );
      return jsonb_build_object('settlement', to_jsonb(s) - 'request_key');
    end if;

  elsif p_action = 'admin_list' then
    if not op then
      raise sqlstate 'PT403' using message = 'Cần quyền quản trị.';
    end if;
    v_filter := coalesce(nullif(btrim(d->>'state'), ''), 'all');
    v_kind_filter := coalesce(nullif(btrim(d->>'kind'), ''), 'all');
    return jsonb_build_object(
      'settlements', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', st.id,
          'driver_id', st.driver_id,
          'driver_name', coalesce(ca.full_name, 'Tài xế'),
          'driver_phone', coalesce(ca.phone, ''),
          'kind', st.kind,
          'amount', st.amount,
          'order_ids', st.order_ids,
          'reference_code', st.reference_code,
          'note', st.note,
          'state', st.state,
          'reviewed_by', st.reviewed_by,
          'review_note', st.review_note,
          'completion_evidence', st.completion_evidence,
          'version', st.version,
          'created_at', st.created_at,
          'completed_at', st.completed_at
        ) order by st.created_at desc, st.id desc)
        from (
          select * from public.delivery_driver_settlements
          where (v_filter = 'all' or (v_filter = 'pending' and state in ('requested','approved')) or state = v_filter)
            and (v_kind_filter = 'all' or kind = v_kind_filter)
          order by created_at desc, id desc
          limit 60
        ) st
        left join public.delivery_cloud_accounts ca on ca.user_id = st.driver_id
      ), '[]'::jsonb),
      'summary', jsonb_build_object(
        'pending_count', (select count(*)::int from public.delivery_driver_settlements where state in ('requested','approved')),
        'cod_remit_completed', coalesce((select sum(amount) from public.delivery_driver_settlements where kind = 'cod_remit' and state = 'completed'), 0),
        'payout_completed', coalesce((select sum(amount) from public.delivery_driver_settlements where kind = 'payout' and state = 'completed'), 0),
        'total_driver_earnings', coalesce((select sum(amount) from public.delivery_driver_wallet_entries where kind = 'trip_earning'), 0),
        'total_platform_commission', coalesce((select sum(platform_commission) from public.delivery_driver_wallet_entries where kind = 'trip_earning'), 0)
      )
    );

  elsif p_action = 'admin_decide' then
    if not op then
      raise sqlstate 'PT403' using message = 'Cần quyền quản trị.';
    end if;
    if jsonb_typeof(d->'id') is distinct from 'string'
       or jsonb_typeof(d->'version') is distinct from 'number'
       or jsonb_typeof(d->'decision') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Quyết định đối soát tài xế không hợp lệ.';
    end if;
    v_decision := btrim(d->>'decision');
    if v_decision not in ('approve', 'reject', 'complete') then
      raise sqlstate 'PT400' using message = 'Thao tác đối soát tài xế không hợp lệ.';
    end if;

    select * into s from public.delivery_driver_settlements where id = (d->>'id')::uuid for update;
    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy phiếu đối soát tài xế.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver_wallet:' || s.driver_id::text, 0));
    if s.version is distinct from (d->>'version')::integer then
      raise sqlstate 'PT409' using message = 'Phiếu đối soát đã thay đổi. Hãy tải lại.';
    end if;

    v_note := btrim(coalesce(d->>'reason', ''));
    v_ref := btrim(coalesce(d->>'evidence', ''));

    if v_decision = 'approve' and s.state = 'requested' then
      if length(v_note) < 3 then
        raise sqlstate 'PT400' using message = 'Cần ghi chú duyệt tối thiểu 3 ký tự.';
      end if;
      update public.delivery_driver_settlements
        set state = 'approved',
            reviewed_by = uid,
            review_note = v_note,
            version = version + 1,
            updated_at = now()
        where id = s.id returning * into s;
    elsif v_decision = 'reject' and s.state in ('requested', 'approved') then
      if length(v_note) < 3 then
        raise sqlstate 'PT400' using message = 'Cần nhập lý do từ chối tối thiểu 3 ký tự.';
      end if;
      update public.delivery_driver_settlements
        set state = 'rejected',
            reviewed_by = uid,
            review_note = v_note,
            version = version + 1,
            updated_at = now()
        where id = s.id returning * into s;
    elsif v_decision = 'complete' and s.state = 'approved' then
      if length(v_ref) < 3 then
        raise sqlstate 'PT400' using message = 'Cần mã chứng từ xác nhận thực thu / thực chi tối thiểu 3 ký tự.';
      end if;
      if s.kind = 'payout' then
        select coalesce(sum(amount), 0) into v_wallet_balance
          from public.delivery_driver_wallet_entries where driver_id = s.driver_id;
        if v_wallet_balance < s.amount then
          raise sqlstate 'PT409' using message = 'Số dư Ví Tài xế không đủ để tất toán khoản rút.';
        end if;
        insert into public.delivery_driver_wallet_entries(
          driver_id, settlement_id, kind, gross_fee, platform_commission, amount, note
        ) values (
          s.driver_id, s.id, 'payout_debit', 0, 0, -s.amount, 'Chi trả thu nhập tài xế · ' || left(v_ref, 200)
        );
      end if;
      update public.delivery_driver_settlements
        set state = 'completed',
            reviewed_by = uid,
            completion_evidence = v_ref,
            completed_at = now(),
            version = version + 1,
            updated_at = now()
        where id = s.id returning * into s;
    else
      raise sqlstate 'PT409' using message = 'Trạng thái phiếu đối soát không phù hợp thao tác.';
    end if;

    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values (uid, 'driver_settlement_' || v_decision, s.id, to_jsonb(s) - 'request_key');

    perform public.delivery_emit_notification(
      s.driver_id,
      'shipping',
      'driver_settlement_' || s.state,
      case
        when s.kind = 'cod_remit' and s.state = 'completed' then 'Đã xác nhận nộp COD ' || s.amount || ' đ'
        when s.kind = 'payout' and s.state = 'completed' then 'Đã giải ngân thu nhập ' || s.amount || ' đ'
        when s.state = 'approved' then 'Phiếu đối soát ' || s.amount || ' đ đã được duyệt'
        else 'Phiếu đối soát ' || s.amount || ' đ bị từ chối'
      end,
      case
        when s.state = 'completed' then 'Chứng từ đối soát: ' || s.completion_evidence
        else coalesce(nullif(s.review_note, ''), 'Đã cập nhật trạng thái phiếu đối soát.')
      end,
      'driver_settlement',
      s.id,
      jsonb_build_object('kind', s.kind, 'amount', s.amount, 'state', s.state)
    );
    return jsonb_build_object('settlement', to_jsonb(s) - 'request_key');
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác ví tài xế không hỗ trợ.';
end; $$;
revoke all on function public.delivery_driver_finance(text, jsonb) from public, anon;
grant execute on function public.delivery_driver_finance(text, jsonb) to authenticated;


-- ============================================================================
-- 5. MARKETPLACE RPC & SPLIT-PARCEL EVIDENCE ATTACHMENT HELPERS
-- ============================================================================

create or replace function public.delivery_marketplace(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  actor public.delivery_cloud_accounts;
  sh public.delivery_market_shops;
  prod public.delivery_market_products;
  previous public.delivery_market_products;
  var_row public.delivery_market_variants;
  prev_var public.delivery_market_variants;
  voucher_row public.delivery_market_vouchers;
  flash_row public.delivery_market_flash_sales;
  purchase public.delivery_market_purchases;
  so public.delivery_market_shop_orders;
  quote public.delivery_market_quotes;
  shipment public.delivery_cloud_orders;
  msg public.delivery_market_messages;
  d jsonb := p_payload;
  result jsonb;
  snapshot jsonb;
  group_row jsonb;
  item jsonb;
  parcel jsonb;
  cart_version integer;
  qty integer;
  product_key uuid;
  variant_key uuid;
  requested text;
  line_key uuid;
  selected jsonb;
  selection jsonb;
  aggregate_qty bigint;
  op boolean;
  staff_user uuid;
  att_list jsonb := '[]';
  att_name text;
  idx integer := 0;
  coin_total bigint := 0;
  coin_rem bigint := 0;
  sh_cnt integer := 0;
  sh_idx integer := 0;
  sh_coin bigint := 0;
  v_id uuid;
  fs_id uuid;
  split_cod bigint := 0;
  expected_cod bigint := 0;
  parcel_weight numeric;
  v_shop_id uuid;
  prev_shop_status text := null;
  v_ship_pay_status text;
  v_ship_details jsonb;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into actor from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  op := public.delivery_is_operator();
  if (actor.user_id is null or actor.blocked) and not (p_action in ('workspace','shop_moderate','voucher_save') and op) then
    raise sqlstate 'PT403' using message='Cần hồ sơ tài khoản đang hoạt động.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 then
    raise sqlstate 'PT400' using message='Dữ liệu không hợp lệ.';
  end if;

  if p_action='catalog' then
    if length(coalesce(d->>'search',''))>160 or length(coalesce(d->>'category',''))>80 then
      raise sqlstate 'PT400' using message='Bộ lọc quá dài.';
    end if;
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
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not op and
       not exists(select 1 from public.delivery_market_shop_staff st where st.user_id=auth.uid() and st.active and public.delivery_market_can_access_shop(st.shop_id,auth.uid(),'staff')) then
      raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
    end if;
    result := jsonb_build_object(
      'shops',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
        (select s.* from public.delivery_market_shops s
         where (s.owner_id=auth.uid() or public.delivery_market_can_access_shop(s.id,auth.uid(),'staff') or (d->>'moderation'='true' and op))
           and (d->>'moderation' is distinct from 'true' or not(d ? 'after') or s.id>(d->>'after')::uuid) order by s.id limit 50) x),'[]'),
      'products',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
        (select p.*,
           coalesce((select jsonb_agg(to_jsonb(v) order by v.sku,v.id) from public.delivery_market_variants v where v.product_id=p.id),'[]'::jsonb) as variants
         from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
         where (s.owner_id=auth.uid() or public.delivery_market_can_access_shop(s.id,auth.uid(),'staff'))
           and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x),'[]'),
      'staff',coalesce((select jsonb_agg(jsonb_build_object(
          'shop_id',st.shop_id,'user_id',st.user_id,'full_name',ua.full_name,'phone',ua.phone,
          'email',coalesce(lower(to_jsonb(au)->>'email'),''),
          'role',st.role,'active',st.active,'version',st.version
        ) order by st.created_at,st.user_id)
        from public.delivery_market_shop_staff st
        join public.delivery_market_shops s on s.id=st.shop_id
        join public.delivery_cloud_accounts ua on ua.user_id=st.user_id
        left join auth.users au on au.id=st.user_id
        where (s.owner_id=auth.uid() or public.delivery_market_can_access_shop(s.id,auth.uid(),'manager')) and st.active),'[]'),
      'vouchers',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc) from
        (select v.* from public.delivery_market_vouchers v
         where (op and d->>'moderation'='true') or (v.shop_id is not null and public.delivery_market_can_access_shop(v.shop_id,auth.uid(),'staff'))
         order by v.created_at desc,v.id desc limit 50) v),'[]'),
      'flash_sales',coalesce((select jsonb_agg(to_jsonb(fs) order by fs.starts_at desc,fs.id desc) from
        (select fs.* from public.delivery_market_flash_sales fs
         where (op and d->>'moderation'='true') or public.delivery_market_can_access_shop(fs.shop_id,auth.uid(),'staff')
         order by fs.starts_at desc,fs.id desc limit 50) fs),'[]')
    );
    snapshot := result->case when d->>'moderation'='true' then 'shops' else 'products' end;
    return result||jsonb_build_object('next',case when jsonb_array_length(snapshot)=50 then jsonb_build_object('after',snapshot->49->>'id') end);

  elsif p_action='shop_save' then
    if d-array['id','name','description','address','latitude','longitude','paused','version','opening_schedule','banner_url','service_radius_km']<>'{}' or
      jsonb_typeof(d->'name') is distinct from 'string' or jsonb_typeof(d->'address') is distinct from 'string' or
      jsonb_typeof(d->'latitude') is distinct from 'number' or jsonb_typeof(d->'longitude') is distinct from 'number' or
      jsonb_typeof(d->'paused') is distinct from 'boolean' then
      raise sqlstate 'PT400' using message='Thông tin cửa hàng không hợp lệ.';
    end if;
    if (d ? 'service_radius_km' and (jsonb_typeof(d->'service_radius_km')<>'number' or (d->>'service_radius_km')::numeric not between 0 and 200)) or
       (d ? 'banner_url' and (jsonb_typeof(d->'banner_url')<>'string' or length(d->>'banner_url')>1000 or (d->>'banner_url'<>'' and (d->>'banner_url') !~ '^https://'))) then
      raise sqlstate 'PT400' using message='Ảnh bìa hoặc bán kính phục vụ không hợp lệ.';
    end if;

    v_shop_id := case
      when d ? 'id' and jsonb_typeof(d->'id')='string' and btrim(d->>'id')<>''
      then (d->>'id')::uuid
      else null
    end;

    if v_shop_id is not null then
      perform pg_advisory_xact_lock(hashtextextended('shop:'||v_shop_id::text,0));
      select * into sh from public.delivery_market_shops where id=v_shop_id for update;
      if sh.id is not null then
        if not public.delivery_market_can_access_shop(sh.id,auth.uid(),'manager') then
          raise sqlstate 'PT403' using message='Không có quyền cập nhật cửa hàng này.';
        end if;
        if sh.version is distinct from (d->>'version')::integer then
          raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi. Hãy tải lại.';
        end if;
        if sh.status='suspended' then
          raise sqlstate 'PT403' using message='Cửa hàng đang tạm khóa.';
        end if;
        prev_shop_status := sh.status;
        update public.delivery_market_shops set
          name = btrim(d->>'name'),
          description = coalesce(d->>'description',''),
          address = btrim(d->>'address'),
          latitude = (d->>'latitude')::float8,
          longitude = (d->>'longitude')::float8,
          paused = (d->>'paused')::boolean,
          version = version + 1,
          status = case
            when name=btrim(d->>'name') and address=btrim(d->>'address')
              and latitude=(d->>'latitude')::float8 and longitude=(d->>'longitude')::float8
            then status
            else 'pending'
          end,
          updated_at = now()
          where id=sh.id returning * into sh;
      else
        if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then
          raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
        end if;
        if d ? 'version' and d->'version' is not null then
          raise sqlstate 'PT409' using message='Cửa hàng không còn tồn tại.';
        end if;
        if (select count(*) from public.delivery_market_shops where owner_id=auth.uid()) >= 10 then
          raise sqlstate 'PT409' using message='Mỗi đối tác tối đa 10 chi nhánh cửa hàng.';
        end if;
        insert into public.delivery_market_shops(id,owner_id,name,description,address,latitude,longitude,paused)
          values(v_shop_id,auth.uid(),btrim(d->>'name'),coalesce(d->>'description',''),btrim(d->>'address'),(d->>'latitude')::float8,(d->>'longitude')::float8,(d->>'paused')::boolean)
          returning * into sh;
      end if;
    else
      if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then
        raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
      end if;
      perform pg_advisory_xact_lock(hashtextextended('shop:'||auth.uid()::text,0));
      if d ? 'version' and d->'version' is not null then
        select * into sh from public.delivery_market_shops
          where owner_id=auth.uid()
          order by id asc
          limit 1 for update;
        if sh.id is null or sh.version is distinct from (d->>'version')::integer then
          raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi. Hãy tải lại.';
        end if;
        if sh.status='suspended' then
          raise sqlstate 'PT403' using message='Cửa hàng đang tạm khóa.';
        end if;
        prev_shop_status := sh.status;
        update public.delivery_market_shops set
          name = btrim(d->>'name'),
          description = coalesce(d->>'description',''),
          address = btrim(d->>'address'),
          latitude = (d->>'latitude')::float8,
          longitude = (d->>'longitude')::float8,
          paused = (d->>'paused')::boolean,
          version = version + 1,
          status = case
            when name=btrim(d->>'name') and address=btrim(d->>'address')
              and latitude=(d->>'latitude')::float8 and longitude=(d->>'longitude')::float8
            then status
            else 'pending'
          end,
          updated_at = now()
          where id=sh.id returning * into sh;
      else
        if (select count(*) from public.delivery_market_shops where owner_id=auth.uid()) >= 10 then
          raise sqlstate 'PT409' using message='Mỗi đối tác tối đa 10 chi nhánh cửa hàng.';
        end if;
        insert into public.delivery_market_shops(owner_id,name,description,address,latitude,longitude,paused)
          values(auth.uid(),btrim(d->>'name'),coalesce(d->>'description',''),btrim(d->>'address'),(d->>'latitude')::float8,(d->>'longitude')::float8,(d->>'paused')::boolean)
          returning * into sh;
      end if;
    end if;

    update public.delivery_market_shops set
      opening_schedule = coalesce(d->'opening_schedule',opening_schedule),
      banner_url = case when d ? 'banner_url' then d->>'banner_url' else banner_url end,
      service_radius_km = case when d ? 'service_radius_km' then (d->>'service_radius_km')::numeric else service_radius_km end
      where id=sh.id returning * into sh;

    if sh.status = 'pending' and prev_shop_status is distinct from 'pending' then
      perform public.delivery_notify_operators(
        auth.uid(), 'market', 'shop_pending_review',
        'Cửa hàng chờ kiểm duyệt: ' || left(sh.name, 80),
        'Đối tác vừa tạo hoặc cập nhật thông tin định vị cửa hàng ' || left(sh.name, 80) || ' cần quản trị viên phê duyệt.',
        'shop', sh.id, jsonb_build_object('shop_id', sh.id, 'owner_id', sh.owner_id)
      );
    end if;
    return jsonb_build_object('shop',to_jsonb(sh));

  elsif p_action='staff_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then
      raise sqlstate 'PT403' using message='Chỉ chủ cửa hàng quản lý nhân sự.';
    end if;
    select * into sh from public.delivery_market_shops where id=(d->>'shop_id')::uuid and owner_id=auth.uid() for update;
    if not found or sh.status='suspended' then
      raise sqlstate 'PT403' using message='Không có quyền quản lý nhân sự cửa hàng này.';
    end if;
    if d ? 'user_id' and jsonb_typeof(d->'user_id')='string' and btrim(d->>'user_id')<>'' then
      staff_user := (d->>'user_id')::uuid;
    elsif d ? 'phone' and jsonb_typeof(d->'phone')='string' and btrim(d->>'phone')<>'' then
      select user_id into staff_user from public.delivery_cloud_accounts
        where phone=btrim(d->>'phone') and not blocked order by updated_at desc limit 1;
    elsif d ? 'email' and jsonb_typeof(d->'email')='string' and btrim(d->>'email')<>'' then
      select a2.user_id into staff_user
        from auth.users u
        join public.delivery_cloud_accounts a2 on a2.user_id = u.id
        where lower(coalesce(to_jsonb(u)->>'email','')) = lower(btrim(d->>'email'))
          and not a2.blocked
        order by a2.updated_at desc limit 1;
    end if;
    if staff_user is null or staff_user=auth.uid() or not exists(select 1 from public.delivery_cloud_accounts where user_id=staff_user and not blocked) then
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản nhân viên hợp lệ.';
    end if;
    if coalesce(d->>'role','staff') not in ('manager','staff') or jsonb_typeof(coalesce(d->'active','true'::jsonb))<>'boolean' then
      raise sqlstate 'PT400' using message='Quyền nhân sự không hợp lệ.';
    end if;
    insert into public.delivery_market_shop_staff(shop_id,user_id,role,active,added_by)
      values(sh.id,staff_user,coalesce(d->>'role','staff'),coalesce((d->>'active')::boolean,true),auth.uid())
      on conflict(shop_id,user_id) do update set role=excluded.role,active=excluded.active,version=delivery_market_shop_staff.version+1,updated_at=now();

    perform public.delivery_emit_notification(
      staff_user,
      'market',
      case when coalesce((d->>'active')::boolean,true) then 'shop_staff_assigned' else 'shop_staff_revoked' end,
      case
        when coalesce((d->>'active')::boolean,true) then 'Phân quyền nhân sự tại ' || left(sh.name, 70)
        else 'Thu hồi quyền nhân sự tại ' || left(sh.name, 70)
      end,
      case
        when coalesce((d->>'active')::boolean,true) then
          'Bạn đã được cấp quyền ' || case when coalesce(d->>'role','staff')='manager' then 'Quản lý' else 'Nhân viên' end || ' tại cửa hàng ' || left(sh.name, 80) || '.'
        else
          'Quyền nhân sự của bạn tại cửa hàng ' || left(sh.name, 80) || ' đã tạm ngưng.'
      end,
      'shop',
      sh.id,
      jsonb_build_object('shop_id', sh.id, 'role', coalesce(d->>'role','staff'), 'active', coalesce((d->>'active')::boolean,true))
    );

    return jsonb_build_object('staff',coalesce((select jsonb_agg(jsonb_build_object(
        'shop_id',st.shop_id,'user_id',st.user_id,'full_name',ua.full_name,'phone',ua.phone,
        'email',coalesce(lower(to_jsonb(au)->>'email'),''),
        'role',st.role,'active',st.active,'version',st.version
      ) order by st.created_at,st.user_id)
      from public.delivery_market_shop_staff st
      join public.delivery_cloud_accounts ua on ua.user_id=st.user_id
      left join auth.users au on au.id=st.user_id
      where st.shop_id=sh.id and st.active),'[]'::jsonb));

  elsif p_action='shop_moderate' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if d->>'status' not in ('active','suspended') or not(d ?& array['id','version','status']) then
      raise sqlstate 'PT400' using message='Trạng thái không hợp lệ.';
    end if;
    update public.delivery_market_shops set status=d->>'status',version=version+1,updated_at=now()
      where id=(d->>'id')::uuid and version=(d->>'version')::integer returning * into sh;
    if not found then raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi hoặc không tồn tại.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value)
      values(auth.uid(),'shop_moderate',sh.id,to_jsonb(sh));
    perform public.delivery_notify_shop_team(
      sh.id,
      auth.uid(),
      'manager',
      'market',
      'shop_' || sh.status,
      case when sh.status='active' then 'Cửa hàng ' || left(sh.name, 70) || ' đã được duyệt'
           else 'Cửa hàng ' || left(sh.name, 70) || ' đang tạm khóa' end,
      case when sh.status='active' then 'Cửa hàng của bạn đã sẵn sàng hiển thị sản phẩm và nhận đơn đặt hàng.'
           else 'Cửa hàng của bạn đang tạm khóa bởi bộ phận vận hành. Vui lòng kiểm tra thông tin cửa hàng.' end,
      'shop',
      sh.id,
      jsonb_build_object('shop_id', sh.id, 'status', sh.status)
    );
    return jsonb_build_object('shop',to_jsonb(sh));

  elsif p_action='product_save' then
    if d-array['id','shop_id','name','description','category','sku','image_url','price','stock','weight_kg','published','version','option_groups','sale_schedule','preparation_minutes','images','length_cm','width_cm','height_cm']<>'{}' or
      jsonb_typeof(d->'price') is distinct from 'number' or jsonb_typeof(d->'stock') is distinct from 'number' or
      jsonb_typeof(d->'weight_kg') is distinct from 'number' or jsonb_typeof(d->'published') is distinct from 'boolean' or
      (d->>'stock')::numeric<>trunc((d->>'stock')::numeric) or (d->>'price')::numeric<>trunc((d->>'price')::numeric) then
      raise sqlstate 'PT400' using message='Giá và tồn kho cần là số nguyên hợp lệ.';
    end if;
    if d?'preparation_minutes' and (jsonb_typeof(d->'preparation_minutes') is distinct from 'number' or
      (d->>'preparation_minutes')::numeric<>trunc((d->>'preparation_minutes')::numeric) or
      (d->>'preparation_minutes')::numeric not between 0 and 1440) then
      raise sqlstate 'PT400' using message='Thời gian chuẩn bị không hợp lệ.';
    end if;
    if (d ? 'length_cm' and (jsonb_typeof(d->'length_cm')<>'number' or (d->>'length_cm')::numeric not between 0 and 300)) or
       (d ? 'width_cm' and (jsonb_typeof(d->'width_cm')<>'number' or (d->>'width_cm')::numeric not between 0 and 300)) or
       (d ? 'height_cm' and (jsonb_typeof(d->'height_cm')<>'number' or (d->>'height_cm')::numeric not between 0 and 300)) then
      raise sqlstate 'PT400' using message='Kích thước sản phẩm không hợp lệ.';
    end if;
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not public.delivery_market_can_access_shop((d->>'shop_id')::uuid,auth.uid(),'manager') then
      raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
    end if;
    select * into sh from public.delivery_market_shops where id=(d->>'shop_id')::uuid and public.delivery_market_can_access_shop(id,auth.uid(),'manager') for update;
    if not found or sh.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền sửa cửa hàng này.'; end if;
    product_key := (d->>'id')::uuid;
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
      insert into public.delivery_market_stock(product_id,actor_id,delta,reason)
        values(prod.id,auth.uid(),prod.stock-coalesce(previous.stock,0),'merchant_adjust');
    end if;
    update public.delivery_market_products set option_groups=coalesce(d->'option_groups',option_groups),
      sale_schedule=coalesce(d->'sale_schedule',sale_schedule),images=coalesce(d->'images',images),
      preparation_minutes=case when d?'preparation_minutes' then (d->>'preparation_minutes')::integer else preparation_minutes end,
      length_cm=case when d?'length_cm' then (d->>'length_cm')::numeric else length_cm end,
      width_cm=case when d?'width_cm' then (d->>'width_cm')::numeric else width_cm end,
      height_cm=case when d?'height_cm' then (d->>'height_cm')::numeric else height_cm end
      where id=prod.id returning * into prod;
    return jsonb_build_object('product',to_jsonb(prod));

  elsif p_action='variant_save' then
    if d-array['id','product_id','sku','title','price','stock','weight_kg','length_cm','width_cm','height_cm','published','version']<>'{}' or
       jsonb_typeof(d->'price')<>'number' or jsonb_typeof(d->'stock')<>'number' or jsonb_typeof(d->'weight_kg')<>'number' or
       jsonb_typeof(d->'published')<>'boolean' or (d->>'price')::numeric<>trunc((d->>'price')::numeric) or (d->>'stock')::numeric<>trunc((d->>'stock')::numeric) then
      raise sqlstate 'PT400' using message='Thông tin biến thể SKU không hợp lệ.';
    end if;
    select * into prod from public.delivery_market_products where id=(d->>'product_id')::uuid for share;
    if not found or not public.delivery_market_can_access_shop(prod.shop_id,auth.uid(),'manager') then
      raise sqlstate 'PT403' using message='Không có quyền quản lý biến thể sản phẩm này.';
    end if;
    variant_key := coalesce((d->>'id')::uuid,gen_random_uuid());
    select * into prev_var from public.delivery_market_variants where id=variant_key for update;
    if prev_var.id is not null and (prev_var.product_id<>prod.id or prev_var.version is distinct from (d->>'version')::integer) then
      raise sqlstate 'PT409' using message='Biến thể đã thay đổi. Hãy tải lại.';
    end if;
    insert into public.delivery_market_variants(id,product_id,sku,title,price,stock,weight_kg,length_cm,width_cm,height_cm,published)
      values(variant_key,prod.id,btrim(d->>'sku'),btrim(d->>'title'),(d->>'price')::integer,(d->>'stock')::integer,(d->>'weight_kg')::numeric,
        coalesce((d->>'length_cm')::numeric,0),coalesce((d->>'width_cm')::numeric,0),coalesce((d->>'height_cm')::numeric,0),(d->>'published')::boolean)
      on conflict(id) do update set sku=excluded.sku,title=excluded.title,price=excluded.price,stock=excluded.stock,
        weight_kg=excluded.weight_kg,length_cm=excluded.length_cm,width_cm=excluded.width_cm,height_cm=excluded.height_cm,
        published=excluded.published,version=delivery_market_variants.version+1,updated_at=now() returning * into var_row;
    if var_row.stock<>coalesce(prev_var.stock,0) then
      insert into public.delivery_market_stock(product_id,variant_id,actor_id,delta,reason)
        values(prod.id,var_row.id,auth.uid(),var_row.stock-coalesce(prev_var.stock,0),'merchant_variant_adjust');
    end if;
    return jsonb_build_object('variant',to_jsonb(var_row));

  elsif p_action='voucher_save' then
    if d-array['id','shop_id','code','title','discount_kind','discount_value','max_discount','min_subtotal','budget_total','per_user_limit','starts_at','ends_at','active','version']<>'{}' then
      raise sqlstate 'PT400' using message='Thông tin mã giảm giá không hợp lệ.';
    end if;
    if d ? 'shop_id' and d->'shop_id' is not null and jsonb_typeof(d->'shop_id')='string' then
      if not public.delivery_market_can_access_shop((d->>'shop_id')::uuid,auth.uid(),'manager') and not op then
        raise sqlstate 'PT403' using message='Không có quyền tạo mã giảm giá cho cửa hàng này.';
      end if;
    elsif not op then
      raise sqlstate 'PT403' using message='Chỉ quản trị viên được tạo mã giảm giá toàn sàn.';
    end if;
    v_id := coalesce((d->>'id')::uuid,gen_random_uuid());
    select * into voucher_row from public.delivery_market_vouchers where id=v_id for update;
    if voucher_row.id is not null then
      if voucher_row.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Mã giảm giá đã thay đổi.'; end if;
      if (d->>'budget_total')::bigint < voucher_row.budget_used then raise sqlstate 'PT409' using message='Ngân sách mới thấp hơn mức đã sử dụng.'; end if;
    end if;
    insert into public.delivery_market_vouchers(id,code,shop_id,title,discount_kind,discount_value,max_discount,min_subtotal,budget_total,per_user_limit,starts_at,ends_at,active,created_by)
      values(v_id,upper(btrim(d->>'code')),nullif(d->>'shop_id','')::uuid,btrim(d->>'title'),d->>'discount_kind',
        (d->>'discount_value')::integer,(d->>'max_discount')::integer,coalesce((d->>'min_subtotal')::integer,0),
        (d->>'budget_total')::bigint,coalesce((d->>'per_user_limit')::integer,1),(d->>'starts_at')::timestamptz,
        (d->>'ends_at')::timestamptz,coalesce((d->>'active')::boolean,true),auth.uid())
      on conflict(id) do update set title=excluded.title,discount_kind=excluded.discount_kind,discount_value=excluded.discount_value,
        max_discount=excluded.max_discount,min_subtotal=excluded.min_subtotal,budget_total=excluded.budget_total,
        per_user_limit=excluded.per_user_limit,starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=excluded.active,
        version=delivery_market_vouchers.version+1,updated_at=now() returning * into voucher_row;
    if op then insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'voucher_save',voucher_row.id,to_jsonb(voucher_row)); end if;
    return jsonb_build_object('voucher',to_jsonb(voucher_row));

  elsif p_action='flash_sale_save' then
    if d-array['id','product_id','sale_price','allocated_stock','per_user_limit','starts_at','ends_at','active','version']<>'{}' then
      raise sqlstate 'PT400' using message='Thông tin Flash Sale không hợp lệ.';
    end if;
    select * into prod from public.delivery_market_products where id=(d->>'product_id')::uuid for share;
    if not found or (not public.delivery_market_can_access_shop(prod.shop_id,auth.uid(),'manager') and not op) then
      raise sqlstate 'PT403' using message='Không có quyền cấu hình Flash Sale cho sản phẩm này.';
    end if;
    if (d->>'sale_price')::integer >= prod.price then raise sqlstate 'PT400' using message='Giá Flash Sale phải nhỏ hơn giá niêm yết.'; end if;
    fs_id := coalesce((d->>'id')::uuid,gen_random_uuid());
    select * into flash_row from public.delivery_market_flash_sales where id=fs_id for update;
    if flash_row.id is not null then
      if flash_row.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Flash Sale đã thay đổi.'; end if;
      if (d->>'allocated_stock')::integer < flash_row.sold_stock then raise sqlstate 'PT409' using message='Số lượng phân bổ thấp hơn mức đã bán.'; end if;
    end if;
    insert into public.delivery_market_flash_sales(id,product_id,shop_id,sale_price,allocated_stock,per_user_limit,starts_at,ends_at,active)
      values(fs_id,prod.id,prod.shop_id,(d->>'sale_price')::integer,(d->>'allocated_stock')::integer,
        coalesce((d->>'per_user_limit')::integer,2),(d->>'starts_at')::timestamptz,(d->>'ends_at')::timestamptz,coalesce((d->>'active')::boolean,true))
      on conflict(id) do update set sale_price=excluded.sale_price,allocated_stock=excluded.allocated_stock,
        per_user_limit=excluded.per_user_limit,starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=excluded.active,
        version=delivery_market_flash_sales.version+1,updated_at=now() returning * into flash_row;
    return jsonb_build_object('flash_sale',to_jsonb(flash_row));

  elsif p_action in ('cart','cart_set') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    insert into public.delivery_market_carts(user_id) values(auth.uid()) on conflict do nothing;
    select version into cart_version from public.delivery_market_carts where user_id=auth.uid() for update;
    if p_action='cart_set' then
      if d-array['product_id','variant_id','line_id','selected_options','quantity','version']<>'{}' or
        jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) or
        (d->>'quantity')::numeric not between 0 and 99 then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
      if cart_version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy tải lại.'; end if;
      qty := (d->>'quantity')::integer;
      product_key := (d->>'product_id')::uuid;
      variant_key := nullif(d->>'variant_id','')::uuid;
      line_key := (d->>'line_id')::uuid;
      selected := coalesce(d->'selected_options','[]');
      if product_key is null then raise sqlstate 'PT400' using message='Thiếu sản phẩm.'; end if;
      if line_key is not null then
        select c.selected_options,c.variant_id into selected,variant_key from public.delivery_market_cart_items c
          where c.user_id=auth.uid() and c.line_id=line_key and c.product_id=product_key;
        if not found then raise sqlstate 'PT409' using message='Dòng giỏ hàng đã thay đổi. Hãy tải lại.'; end if;
        if (d?'selected_options' and d->'selected_options' is distinct from selected) or
           (d?'variant_id' and nullif(d->>'variant_id','')::uuid is distinct from variant_key) then
          raise sqlstate 'PT409' using message='Không thể đổi lựa chọn của dòng giỏ hàng.';
        end if;
      end if;
      if qty=0 then
        if line_key is null then
          selection := public.delivery_market_selection_v2(product_key,selected,variant_key,1,auth.uid());
          line_key := (selection->>'line_id')::uuid;
        end if;
        delete from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key and product_id=product_key;
      else
        select * into prod from public.delivery_market_products where id=product_key for share;
        select * into sh from public.delivery_market_shops where id=prod.shop_id;
        if prod.id is null or not prod.published or sh.status<>'active' or sh.paused or sh.owner_id=auth.uid() or
          public.delivery_market_can_access_shop(sh.id,auth.uid(),'staff') or
          not public.delivery_market_is_open(prod.sale_schedule) or not public.delivery_market_is_open(sh.opening_schedule) or
          not exists(select 1 from public.delivery_cloud_accounts where user_id=sh.owner_id and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
          raise sqlstate 'PT409' using message='Sản phẩm không thể mua hoặc không đủ tồn kho.';
        end if;
        selection := public.delivery_market_selection_v2(product_key,selected,variant_key,qty,auth.uid());
        line_key := (selection->>'line_id')::uuid;
        if variant_key is not null then
          select * into var_row from public.delivery_market_variants where id=variant_key and product_id=product_key and published for share;
          select qty+coalesce(sum(quantity),0) into aggregate_qty from public.delivery_market_cart_items
            where user_id=auth.uid() and variant_id=variant_key and line_id<>line_key;
          if var_row.id is null or aggregate_qty>var_row.stock or aggregate_qty>99 then
            raise sqlstate 'PT409' using message='Tổng số lượng biến thể vượt tồn kho hoặc giới hạn 99.';
          end if;
        else
          select qty+coalesce(sum(quantity),0) into aggregate_qty from public.delivery_market_cart_items
            where user_id=auth.uid() and product_id=product_key and variant_id is null and line_id<>line_key;
          if aggregate_qty>prod.stock or aggregate_qty>99 then
            raise sqlstate 'PT409' using message='Tổng số lượng các lựa chọn vượt tồn kho hoặc giới hạn 99.';
          end if;
        end if;
        if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key) and
          (select count(*) from public.delivery_market_cart_items where user_id=auth.uid())>=50 then
          raise sqlstate 'PT400' using message='Giỏ hàng hỗ trợ tối đa 50 dòng.';
        end if;
        insert into public.delivery_market_cart_items(user_id,product_id,variant_id,quantity,line_id,selected_options)
          values(auth.uid(),product_key,variant_key,qty,line_key,selection->'selected_options')
          on conflict(user_id,line_id) do update set quantity=excluded.quantity;
      end if;
      update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    end if;
    return public.delivery_market_configured_cart();

  elsif p_action in ('quote','checkout') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    if p_action='quote' then
      if d-array['address_id','cart_version','address_version','buyer_note','service_type','payment_method','scheduled_at','prefer_ev','require_pod','require_otp','voucher_code','use_coins']<>'{}' or
        (d?'cart_version' and (jsonb_typeof(d->'cart_version') is distinct from 'number' or
          (d->>'cart_version')::numeric<>trunc((d->>'cart_version')::numeric))) or
        (d?'address_version' and (jsonb_typeof(d->'address_version') is distinct from 'number' or
          (d->>'address_version')::numeric<>trunc((d->>'address_version')::numeric))) then
        raise sqlstate 'PT400' using message='Yêu cầu báo giá không hợp lệ.';
      end if;
      snapshot := public.delivery_market_snapshot_v2((d->>'address_id')::uuid,d-array['address_id','cart_version','address_version']);
      if d?'cart_version' and d->'cart_version' is distinct from snapshot->'cart_version' then
        raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy kiểm tra lại.';
      end if;
      if d?'address_version' and d->'address_version' is distinct from snapshot->'address_version' then
        raise sqlstate 'PT409' using message='Địa chỉ đã thay đổi. Hãy kiểm tra lại địa chỉ nhận hàng.';
      end if;
      insert into public.delivery_market_quotes(owner_id,snapshot) values(auth.uid(),snapshot) returning * into quote;
      return jsonb_build_object('quote',to_jsonb(quote)-'owner_id');
    end if;

    if d-array['quote_id','request_key']<>'{}' or not(d ?& array['quote_id','request_key']) then
      raise sqlstate 'PT400' using message='Yêu cầu đặt hàng không hợp lệ.';
    end if;
    select * into purchase from public.delivery_market_purchases where owner_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if purchase.quote_id<>(d->>'quote_id')::uuid then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho báo giá khác.'; end if;
      return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');
    end if;
    select * into quote from public.delivery_market_quotes where delivery_market_quotes.id=(d->>'quote_id')::uuid and owner_id=auth.uid() for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy báo giá.'; end if;
    select * into purchase from public.delivery_market_purchases where quote_id=quote.id and owner_id=auth.uid();
    if found then return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key'); end if;
    if quote.expires_at<=now() then raise sqlstate 'PT409' using message='Báo giá đã hết hạn. Hãy lấy báo giá mới.'; end if;

    perform 1 from public.delivery_market_shops where delivery_market_shops.id in
      (select (g->>'shop_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g) order by delivery_market_shops.id for share;
    perform 1 from public.delivery_cloud_accounts where user_id in
      (select (g->>'merchant_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g) order by user_id for share;
    perform 1 from public.delivery_market_products where delivery_market_products.id in
      (select (i->>'product_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i) order by delivery_market_products.id for update;
    perform 1 from public.delivery_market_variants where delivery_market_variants.id in
      (select (i->>'variant_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i where i ? 'variant_id' and jsonb_typeof(i->'variant_id')='string') order by delivery_market_variants.id for update;
    if quote.snapshot ? 'voucher_id' and jsonb_typeof(quote.snapshot->'voucher_id')='string' then
      perform 1 from public.delivery_market_vouchers where id=(quote.snapshot->>'voucher_id')::uuid for update;
    end if;
    perform 1 from public.delivery_market_flash_sales where id in
      (select (i->>'flash_sale_id')::uuid from jsonb_array_elements(quote.snapshot->'shops') g,
        jsonb_array_elements(g->'items') i where i ? 'flash_sale_id' and jsonb_typeof(i->'flash_sale_id')='string') order by id for update;
    if coalesce((quote.snapshot->>'coin_discount')::bigint,0)>0 then
      perform 1 from public.delivery_market_coin_wallets where user_id=auth.uid() for update;
    end if;
    perform 1 from public.delivery_cloud_addresses where delivery_cloud_addresses.id=(quote.snapshot->>'address_id')::uuid for share;
    perform 1 from public.delivery_cloud_pricing where delivery_cloud_pricing.id for share;

    snapshot := public.delivery_market_snapshot_v2((quote.snapshot->>'address_id')::uuid,coalesce(quote.snapshot->'checkout_options','{}'::jsonb));
    if snapshot<>quote.snapshot then
      raise sqlstate 'PT409' using message='Giá, khuyến mãi, giỏ hàng hoặc địa chỉ đã thay đổi. Hãy xác nhận báo giá mới.';
    end if;

    insert into public.delivery_market_purchases(owner_id,request_key,quote_id,snapshot,total,payment_method)
      values(auth.uid(),(d->>'request_key')::uuid,quote.id,snapshot,(snapshot->>'total')::integer,coalesce(snapshot->>'payment_method','cod'))
      returning * into purchase;

    coin_total := coalesce((snapshot->>'coin_discount')::bigint,0);
    coin_rem := coin_total;
    if coin_total>0 then
      update public.delivery_market_coin_wallets set balance=balance-coin_total,updated_at=now()
        where user_id=auth.uid() and balance>=coin_total;
      if not found then raise sqlstate 'PT409' using message='Số dư xu không đủ.'; end if;
      insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
        values(auth.uid(),-coin_total,'redeem_checkout',purchase.id);
    end if;

    sh_cnt := jsonb_array_length(snapshot->'shops');
    for group_row in select * from jsonb_array_elements(snapshot->'shops') loop
      sh_idx := sh_idx+1;
      if coin_rem>0 then
        if sh_idx=sh_cnt then sh_coin := coin_rem;
        else sh_coin := least(coin_rem,floor(coin_total*(group_row->>'subtotal')::numeric/greatest(1,(snapshot->>'goods_subtotal')::numeric))::bigint);
        end if;
        coin_rem := greatest(0,coin_rem-sh_coin);
        group_row := group_row||jsonb_build_object('coin_share',sh_coin);
      end if;
      insert into public.delivery_market_shop_orders(purchase_id,shop_id,owner_id,merchant_id,snapshot)
        values(purchase.id,(group_row->>'shop_id')::uuid,auth.uid(),(group_row->>'merchant_id')::uuid,group_row) returning * into so;
      for item in select * from jsonb_array_elements(group_row->'items') loop
        if item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then
          update public.delivery_market_variants set stock=stock-(item->>'quantity')::integer,version=version+1,updated_at=now()
            where id=(item->>'variant_id')::uuid and stock>=(item->>'quantity')::integer;
          if not found then raise sqlstate 'PT409' using message='Biến thể không đủ tồn kho.'; end if;
          insert into public.delivery_market_stock(product_id,variant_id,actor_id,delta,reason,reference_id)
            values((item->>'product_id')::uuid,(item->>'variant_id')::uuid,auth.uid(),-(item->>'quantity')::integer,'purchase_allocate',so.id);
        else
          update public.delivery_market_products set stock=stock-(item->>'quantity')::integer,version=version+1,updated_at=now()
            where delivery_market_products.id=(item->>'product_id')::uuid and stock>=(item->>'quantity')::integer;
          if not found then raise sqlstate 'PT409' using message='Sản phẩm không đủ tồn kho.'; end if;
          insert into public.delivery_market_stock(product_id,actor_id,delta,reason,reference_id)
            values((item->>'product_id')::uuid,auth.uid(),-(item->>'quantity')::integer,'purchase_allocate',so.id);
        end if;
        if item ? 'flash_sale_id' and jsonb_typeof(item->'flash_sale_id')='string' then
          update public.delivery_market_flash_sales set sold_stock=sold_stock+(item->>'quantity')::integer,version=version+1,updated_at=now()
            where id=(item->>'flash_sale_id')::uuid and active and starts_at<=now() and ends_at>now()
              and sold_stock+(item->>'quantity')::integer<=allocated_stock;
          if not found then raise sqlstate 'PT409' using message='Suất Flash Sale đã hết.'; end if;
          insert into public.delivery_market_flash_claims(flash_sale_id,order_id,user_id,quantity)
            values((item->>'flash_sale_id')::uuid,so.id,auth.uid(),(item->>'quantity')::integer);
        end if;
      end loop;

      if snapshot ? 'voucher_id' and jsonb_typeof(snapshot->'voucher_id')='string' then
        select * into voucher_row from public.delivery_market_vouchers where id=(snapshot->>'voucher_id')::uuid;
        if (voucher_row.shop_id is not null and voucher_row.shop_id=so.shop_id) or (voucher_row.shop_id is null and sh_idx=1) then
          update public.delivery_market_vouchers set budget_used=budget_used+(snapshot->>'voucher_discount')::bigint,version=version+1,updated_at=now()
            where id=voucher_row.id and active and budget_used+(snapshot->>'voucher_discount')::bigint<=budget_total;
          if not found then raise sqlstate 'PT409' using message='Ngân sách mã giảm giá vừa hết.'; end if;
          insert into public.delivery_market_voucher_usages(voucher_id,purchase_id,order_id,user_id,discount_amount)
            values(voucher_row.id,purchase.id,so.id,auth.uid(),(snapshot->>'voucher_discount')::integer);
        end if;
      end if;

      insert into public.delivery_market_events(order_id,actor_id,action) values(so.id,auth.uid(),'created');
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'new_order');
      perform public.delivery_notify_shop_team(
        so.shop_id,
        so.merchant_id,
        'staff',
        'market',
        'new_order',
        'Đơn mua hàng mới tại ' || coalesce(nullif(btrim(group_row->>'shop_name'),''), 'cửa hàng'),
        'Khách hàng vừa đặt đơn mới cần cửa hàng xác nhận đúng hạn.',
        'market_order',
        so.id,
        jsonb_build_object('order_id', so.id, 'shop_id', so.shop_id)
      );
    end loop;

    delete from public.delivery_market_cart_items where user_id=auth.uid();
    update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');

  elsif p_action='orders' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from (
      select o.*,
        case
          when p.payment_status = 'REVIEW' and o.state <> 'cancelled'
               and exists(select 1 from public.delivery_market_finance mf where mf.order_id = o.id and mf.kind = 'collection' and mf.state = 'completed')
          then 'PAID'
          else p.payment_status
        end as payment_status,
        p.payment_method,p.total as purchase_total,del.status as delivery_status,del.tracking_code,
        coalesce((select jsonb_agg(jsonb_build_object('parcel_index',ms.parcel_index,'delivery_id',ms.delivery_id,'tracking_code',c_ord.tracking_code,'status',c_ord.status,'weight_kg',ms.weight_kg,'cod_amount',ms.cod_amount) order by ms.parcel_index)
          from public.delivery_market_shipments ms join public.delivery_cloud_orders c_ord on c_ord.id=ms.delivery_id where ms.order_id=o.id),'[]'::jsonb) as shipments
      from public.delivery_market_shop_orders o join public.delivery_market_purchases p on p.id=o.purchase_id
      left join public.delivery_cloud_orders del on del.id=o.delivery_id
      where (case when d->>'workspace'='merchant' then public.delivery_market_can_access_shop(o.shop_id,auth.uid(),'staff') else o.owner_id=auth.uid() end)
        and (not(d ? 'after') or o.id>(d->>'after')::uuid) order by o.id limit 50) x;
    return jsonb_build_object('orders',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);

  elsif p_action in ('order_action','order_shipment_split','messages','message_send') then
    select * into so from public.delivery_market_shop_orders where delivery_market_shop_orders.id=(d->>'order_id')::uuid
      and (owner_id=auth.uid() or public.delivery_market_can_access_shop(shop_id,auth.uid(),'staff')) for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;

    if p_action='order_shipment_split' then
      if not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') then
        raise sqlstate 'PT403' using message='Chỉ chủ cửa hàng hoặc quản lý được tách kiện giao hàng.';
      end if;
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if so.state<>'accepted' or so.delivery_id is not null or exists(select 1 from public.delivery_market_shipments where order_id=so.id) then
        raise sqlstate 'PT409' using message='Chỉ đơn đã nhận và chưa tạo vận đơn mới được tách kiện.';
      end if;
      select * into purchase from public.delivery_market_purchases where id=so.purchase_id;
      if purchase.payment_method='prepaid'
         and purchase.payment_status<>'PAID'
         and not exists(select 1 from public.delivery_market_finance mf where mf.order_id=so.id and mf.kind='collection' and mf.state='completed') then
        raise sqlstate 'PT409' using message='Đơn trả trước chưa thanh toán thành công.';
      end if;
      if jsonb_typeof(d->'parcels')<>'array' or jsonb_array_length(d->'parcels') not between 2 and 10 then
        raise sqlstate 'PT400' using message='Tách kiện cần từ 2 đến 10 kiện hàng.';
      end if;
      expected_cod := case when purchase.payment_method='prepaid' then 0 else coalesce((so.snapshot->>'payable_subtotal')::bigint,(so.snapshot->>'subtotal')::bigint) end;
      for parcel in select * from jsonb_array_elements(d->'parcels') loop
        idx := idx+1;
        parcel_weight := coalesce((parcel->>'weight_kg')::numeric,0);
        if parcel_weight<=0 or parcel_weight>500 or jsonb_typeof(coalesce(parcel->'cod_amount','0'::jsonb))<>'number' or
           (parcel->>'cod_amount')::numeric<0 or (parcel->>'cod_amount')::numeric<>trunc((parcel->>'cod_amount')::numeric) then
          raise sqlstate 'PT400' using message='Khối lượng hoặc COD từng kiện không hợp lệ.';
        end if;
        split_cod := split_cod+coalesce((parcel->>'cod_amount')::bigint,0);
      end loop;
      if split_cod<>expected_cod then
        raise sqlstate 'PT409' using message='Tổng COD các kiện phải khớp số tiền cần thu của đơn.';
      end if;
      v_ship_pay_status := case
        when purchase.payment_method='prepaid' and (
          purchase.payment_status='PAID'
          or exists(select 1 from public.delivery_market_finance mf where mf.order_id=so.id and mf.kind='collection' and mf.state='completed')
        ) then 'PAID'
        else 'UNPAID'
      end;
      idx := 0;
      for parcel in select * from jsonb_array_elements(d->'parcels') loop
        idx := idx+1;
        v_ship_details := jsonb_set(
          jsonb_set(so.snapshot->'details','{weight_kg}',parcel->'weight_kg'),
          '{cod_amount}',coalesce(parcel->'cod_amount','0'::jsonb)
        );
        if v_ship_pay_status = 'PAID' then
          v_ship_details := jsonb_set(v_ship_details, '{payment_method}', '"sender_cash"'::jsonb, true);
        end if;
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready,payment_status)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id,'parcel_index',idx),
            v_ship_details,
            (so.snapshot->>'distance_meters')::integer,
            case when idx=1 then (so.snapshot->>'shipping_fee')::integer else 0 end,
            coalesce((parcel->>'cod_amount')::integer,0),(so.snapshot->>'pricing_version')::integer,true,v_ship_pay_status)
          returning * into shipment;
        if coalesce((so.snapshot->'details'->>'require_otp')::boolean,false) then
          insert into public.delivery_cloud_order_secrets(order_id,otp_code,otp_hash)
            select shipment.id,otp_code,encode(sha256(convert_to(otp_code,'UTF8')),'hex')
            from (select ((get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),0)*65536 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),1)*256 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),2)) % 900000 + 100000)::text as otp_code) g;
        end if;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code);
        insert into public.delivery_live_members values(shipment.tracking_code,so.owner_id,'customer'),(shipment.tracking_code,so.merchant_id,'merchant')
          on conflict do nothing;
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        insert into public.delivery_market_shipments(order_id,delivery_id,parcel_index,items,weight_kg,cod_amount)
          values(so.id,shipment.id,idx,coalesce(parcel->'items','[]'::jsonb),(parcel->>'weight_kg')::numeric,coalesce((parcel->>'cod_amount')::integer,0));
        if idx=1 then so.delivery_id := shipment.id; end if;
      end loop;
      update public.delivery_market_shop_orders set state='ready',delivery_id=so.delivery_id,version=version+1,updated_at=now()
        where id=so.id returning * into so;
      insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'ready_split','Tách '||idx||' kiện vận chuyển');
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'ready');
      return jsonb_build_object('order',to_jsonb(so));
    end if;

    if p_action='order_action' then
      requested := d->>'action';
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if requested not in ('accept','ready','cancel') or requested is null then raise sqlstate 'PT400' using message='Thao tác không hợp lệ.'; end if;
      if requested in ('accept','ready') and not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff') then
        raise sqlstate 'PT403' using message='Chỉ cửa hàng xử lý đơn mua hàng.';
      end if;
      select * into purchase from public.delivery_market_purchases where id=so.purchase_id;
      if requested in ('accept','ready') and purchase.payment_method='prepaid'
         and purchase.payment_status<>'PAID'
         and not exists(select 1 from public.delivery_market_finance mf where mf.order_id=so.id and mf.kind='collection' and mf.state='completed') then
        raise sqlstate 'PT409' using message='Đơn trả trước cần khách thanh toán thành công trước khi xác nhận.';
      end if;
      if requested='accept' and so.state='pending' then
        so.state := 'accepted';
      elsif requested='ready' and so.state='accepted' then
        expected_cod := case when purchase.payment_method='prepaid' then 0 else coalesce((so.snapshot->>'payable_subtotal')::bigint,(so.snapshot->>'subtotal')::bigint) end;
        v_ship_pay_status := case
          when purchase.payment_method='prepaid' and (
            purchase.payment_status='PAID'
            or exists(select 1 from public.delivery_market_finance mf where mf.order_id=so.id and mf.kind='collection' and mf.state='completed')
          ) then 'PAID'
          else 'UNPAID'
        end;
        v_ship_details := so.snapshot->'details';
        if v_ship_pay_status = 'PAID' then
          v_ship_details := jsonb_set(v_ship_details, '{payment_method}', '"sender_cash"'::jsonb, true);
        end if;
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready,payment_status)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id),v_ship_details,
            (so.snapshot->>'distance_meters')::integer,(so.snapshot->>'shipping_fee')::integer,
            expected_cod::integer,(so.snapshot->>'pricing_version')::integer,true,v_ship_pay_status) returning * into shipment;
        if coalesce((so.snapshot->'details'->>'require_otp')::boolean,false) then
          insert into public.delivery_cloud_order_secrets(order_id,otp_code,otp_hash)
            select shipment.id,otp_code,encode(sha256(convert_to(otp_code,'UTF8')),'hex')
            from (select ((get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),0)*65536 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),1)*256 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),2)) % 900000 + 100000)::text as otp_code) g;
        end if;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code);
        insert into public.delivery_live_members values(shipment.tracking_code,so.owner_id,'customer'),(shipment.tracking_code,so.merchant_id,'merchant')
          on conflict do nothing;
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        so.state := 'ready';
        so.delivery_id := shipment.id;
      elsif requested='cancel' and so.state in ('pending','accepted') and length(btrim(coalesce(d->>'reason',''))) between 3 and 500 and
        (public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') or (so.owner_id=auth.uid() and so.state='pending')) then
        perform public.delivery_market_release_order_allocations(so,auth.uid(),'user','cancel_release');
        so.state := 'cancelled';
        so.reason := btrim(d->>'reason');
        if purchase.payment_status='PAID' then
          update public.delivery_market_purchases set payment_status='REVIEW' where id=purchase.id;
        end if;
      else
        raise sqlstate 'PT409' using message='Không thể thực hiện thao tác ở trạng thái này.';
      end if;
      update public.delivery_market_shop_orders set state=so.state,delivery_id=so.delivery_id,reason=so.reason,
        version=version+1,updated_at=now() where delivery_market_shop_orders.id=so.id returning * into so;
      insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),requested,so.reason);
      insert into public.delivery_market_notifications(user_id,order_id,kind)
        values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,requested);
      if auth.uid()=so.owner_id then
        perform public.delivery_notify_shop_team(
          so.shop_id, so.merchant_id, 'staff', 'market', requested,
          'Khách hàng vừa cập nhật đơn mua',
          'Đơn mua hàng ' || left(so.id::text, 8) || ' vừa chuyển sang trạng thái ' || so.state || '.',
          'market_order', so.id, jsonb_build_object('order_id', so.id)
        );
      end if;
      return jsonb_build_object('order',to_jsonb(so));
    end if;

    if p_action='message_send' then
      if jsonb_typeof(d->'body') is distinct from 'string' or length(btrim(d->>'body')) not between 1 and 2000 or d->>'request_key' is null then
        raise sqlstate 'PT400' using message='Nội dung tin nhắn không hợp lệ.';
      end if;
      if d ? 'attachments' then
        if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>4 then
          raise sqlstate 'PT400' using message='Tối đa 4 tệp đính kèm mỗi tin nhắn.';
        end if;
        for att_name in select jsonb_array_elements_text(d->'attachments') loop
          if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='chat') then
            raise sqlstate 'PT403' using message='Tệp đính kèm không thuộc cuộc hội thoại này.';
          end if;
        end loop;
        att_list := d->'attachments';
      end if;
      perform pg_advisory_xact_lock(hashtextextended('message:'||auth.uid()::text,0));
      select * into msg from public.delivery_market_messages where actor_id=auth.uid() and request_key=(d->>'request_key')::uuid;
      if msg.id is not null then
        if msg.order_id<>so.id or msg.body<>btrim(d->>'body') then raise sqlstate 'PT409' using message='Mã tin nhắn đã được dùng.'; end if;
      else
        if (select count(*) from public.delivery_market_messages where actor_id=auth.uid() and created_at>now()-interval '1 minute')>=20 then
          raise sqlstate 'PT409' using message='Bạn gửi quá nhiều tin nhắn. Vui lòng chờ.';
        end if;
        insert into public.delivery_market_messages(order_id,actor_id,body,attachments,request_key)
          values(so.id,auth.uid(),btrim(d->>'body'),att_list,(d->>'request_key')::uuid);
        insert into public.delivery_market_notifications(user_id,order_id,kind)
          values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'message');
        if auth.uid()=so.owner_id then
          perform public.delivery_notify_shop_team(
            so.shop_id, so.merchant_id, 'staff', 'market', 'message',
            'Tin nhắn mới từ khách mua hàng',
            left(btrim(d->>'body'), 200),
            'market_order', so.id, jsonb_build_object('order_id', so.id)
          );
        end if;
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
  else
    raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end $$;
revoke all on function public.delivery_marketplace(text,jsonb) from public, anon;
grant execute on function public.delivery_marketplace(text,jsonb) to authenticated;

create or replace function public.delivery_market_attachment_reserve(
  p_order uuid,
  p_scope text,
  p_hash text,
  p_bytes integer
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  so public.delivery_market_shop_orders;
  a public.delivery_cloud_accounts;
  att public.delivery_market_attachments;
  op boolean;
  is_driver boolean := false;
  obj_name text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  op := public.delivery_is_operator();
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  if (a.user_id is null or a.blocked) and not op then
    raise sqlstate 'PT403' using message='Cần tài khoản đang hoạt động.';
  end if;
  if p_scope is null or p_scope not in ('chat','return','finance') or
     p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or
     p_bytes is null or p_bytes not between 1 and 5000000 then
    raise sqlstate 'PT400' using message='Tệp bằng chứng không hợp lệ.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('market-attachment-budget',0));
  select * into so from public.delivery_market_shop_orders where id=p_order for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
  if p_scope='finance' then
    is_driver := public.delivery_cloud_has_membership(auth.uid(),'driver') and exists(
      select 1 from public.delivery_cloud_orders co
      where co.driver_id=auth.uid()
        and (co.id=so.delivery_id or exists(select 1 from public.delivery_market_shipments ms where ms.order_id=so.id and ms.delivery_id=co.id))
    );
  end if;
  if not op and so.owner_id<>auth.uid() and not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff') and not is_driver then
    raise sqlstate 'PT403' using message='Không có quyền đính kèm bằng chứng cho đơn này.';
  end if;
  select * into att from public.delivery_market_attachments
    where order_id=so.id and scope=p_scope and content_hash=p_hash;
  if found then
    if att.byte_size<>p_bytes then raise sqlstate 'PT409' using message='Nội dung tệp bằng chứng đã thay đổi.'; end if;
    update public.delivery_market_attachments set owner_id=auth.uid(),upload_until=now()+interval '15 minutes'
      where id=att.id returning * into att;
  else
    if (select coalesce(sum(byte_size),0) from public.delivery_market_attachments)+p_bytes>500000000
      or (select coalesce(sum(byte_size),0) from public.delivery_market_attachments where order_id=so.id)+p_bytes>25000000
      or (select count(*) from public.delivery_market_attachments where order_id=so.id)>=40 then
      raise sqlstate 'PT409' using message='Đơn hàng đã đạt giới hạn dung lượng bằng chứng.';
    end if;
    obj_name := p_scope||'/'||so.id::text||'/'||p_hash||'.webp';
    insert into public.delivery_market_attachments(name,scope,order_id,owner_id,content_hash,byte_size)
      values(obj_name,p_scope,so.id,auth.uid(),p_hash,p_bytes) returning * into att;
  end if;
  return jsonb_build_object('id',att.id,'name',att.name,'bucket','delivery-private-evidence');
end $$;
revoke all on function public.delivery_market_attachment_reserve(uuid,text,text,integer) from public, anon;
grant execute on function public.delivery_market_attachment_reserve(uuid,text,text,integer) to authenticated;

create or replace function public.delivery_market_attachment_can_read(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.delivery_market_attachments att
    join public.delivery_market_shop_orders so on so.id=att.order_id
    left join public.delivery_cloud_accounts a on a.user_id=auth.uid()
    where att.name=p_name and (
      public.delivery_is_operator() or (
        coalesce(not a.blocked,false) and (
          so.owner_id=auth.uid()
          or public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff')
          or (att.scope='finance' and public.delivery_cloud_has_membership(auth.uid(),'driver')
              and exists(
                select 1 from public.delivery_cloud_orders co
                where co.driver_id=auth.uid()
                  and (co.id=so.delivery_id or exists(select 1 from public.delivery_market_shipments ms where ms.order_id=so.id and ms.delivery_id=co.id))
              ))
        )
      )
    )
  );
$$;
revoke all on function public.delivery_market_attachment_can_read(text) from public, anon;
grant execute on function public.delivery_market_attachment_can_read(text) to authenticated;

-- ============================================================================
-- 6. MARKET OPERATIONS CORE & PERSONAL VOUCHER WRAPPER
-- ============================================================================

create or replace function public.delivery_market_operations_core(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb := p_payload;
  a public.delivery_cloud_accounts;
  so public.delivery_market_shop_orders;
  sh public.delivery_market_shops;
  co public.delivery_cloud_orders;
  prod public.delivery_market_products;
  ret public.delivery_market_returns;
  f public.delivery_market_finance;
  pr public.delivery_partner_reviews;
  rev public.delivery_market_reviews;
  existing public.delivery_market_commands;
  result jsonb;
  item jsonb;
  token text;
  jid uuid;
  qty integer;
  cv integer;
  collected bigint;
  refunded bigint;
  settled bigint;
  due bigint;
  goods bigint;
  shop_disc bigint;
  plat_disc bigint;
  merch_net bigint;
  freight bigint;
  used bigint;
  op boolean;
  v_op_count integer := 0;
  k uuid;
  requested text;
  line_key uuid;
  var_key uuid;
  selection jsonb;
  att_list jsonb := '[]';
  att_name text;
  disp text;
  rev_kind text;
  v_target_kind text;
  v_review_author uuid;
  v_return_id uuid;
  rev_ship public.delivery_cloud_orders;
  merch_acc public.delivery_cloud_accounts;
  rev_details jsonb;
  coin_earn bigint := 0;
  coin_rev bigint := 0;
  wallet_bal bigint := 0;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  op := public.delivery_is_operator();
  if a.blocked or (a.user_id is null and not op) then raise sqlstate 'PT403' using message='Cần tài khoản đang hoạt động.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 then raise sqlstate 'PT400' using message='Dữ liệu không hợp lệ.'; end if;

  if p_action in ('favorites','favorite_set','product_details') then
    if p_action='favorite_set' then
      if jsonb_typeof(d->'enabled') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Lựa chọn không hợp lệ.'; end if;
      if (d->>'enabled')::boolean then
        if not exists(select 1 from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
          join public.delivery_cloud_accounts m on m.user_id=s.owner_id where p.id=(d->>'product_id')::uuid
          and p.published and s.status='active' and not s.paused and not m.blocked and public.delivery_cloud_has_membership(m.user_id,'merchant')) then
          raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.';
        end if;
        insert into public.delivery_market_favorites(user_id,product_id) values(auth.uid(),(d->>'product_id')::uuid) on conflict do nothing;
      else
        delete from public.delivery_market_favorites where user_id=auth.uid() and product_id=(d->>'product_id')::uuid;
      end if;
    end if;
    if p_action='product_details' then
      select p.* into prod from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
        join public.delivery_cloud_accounts m on m.user_id=s.owner_id where p.id=(d->>'product_id')::uuid
        and p.published and s.status='active' and not s.paused and public.delivery_cloud_has_membership(m.user_id,'merchant') and not m.blocked;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;
      return jsonb_build_object(
        'product',to_jsonb(prod)||jsonb_build_object(
          'available',(prod.stock>0 or exists(select 1 from public.delivery_market_variants v where v.product_id=prod.id and v.published and v.stock>0))
            and public.delivery_market_is_open(prod.sale_schedule)
            and exists(select 1 from public.delivery_market_shops where id=prod.shop_id and public.delivery_market_is_open(opening_schedule))
        ),
        'variants',coalesce((select jsonb_agg(to_jsonb(v) order by v.sku,v.id) from public.delivery_market_variants v where v.product_id=prod.id and v.published),'[]'::jsonb),
        'flash_sale',(select to_jsonb(fs)-'version' from public.delivery_market_flash_sales fs
          where fs.product_id=prod.id and fs.active and fs.starts_at<=now() and fs.ends_at>now() and fs.sold_stock<fs.allocated_stock
          order by fs.sale_price asc,fs.id asc limit 1),
        'favorite',exists(select 1 from public.delivery_market_favorites where user_id=auth.uid() and product_id=prod.id),
        'shop_following',exists(select 1 from public.delivery_market_shop_follows where user_id=auth.uid() and shop_id=prod.shop_id),
        'shop_followers',(select count(*) from public.delivery_market_shop_follows where shop_id=prod.shop_id),
        'vouchers',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'code',v.code,'shop_id',v.shop_id,'title',v.title,'discount_kind',v.discount_kind,'discount_value',v.discount_value,'max_discount',v.max_discount,'min_subtotal',v.min_subtotal,'ends_at',v.ends_at) order by v.created_at desc)
          from public.delivery_market_vouchers v where v.active and v.starts_at<=now() and v.ends_at>now() and v.budget_used<v.budget_total and (v.shop_id is null or v.shop_id=prod.shop_id)),'[]'::jsonb),
        'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from
          (select id,rating,body,reply,replied_at,created_at from public.delivery_market_reviews where product_id=prod.id and not hidden order by created_at desc,id desc limit 50) r),'[]')
      );
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from
      (select p.*,s.name as shop_name from public.delivery_market_favorites fav join public.delivery_market_products p on p.id=fav.product_id
        join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
        where fav.user_id=auth.uid() and p.published and s.status='active' and not s.paused and public.delivery_cloud_has_membership(m.user_id,'merchant') and not m.blocked
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);

  elsif p_action='shop_details' then
    select s.* into sh from public.delivery_market_shops s join public.delivery_cloud_accounts m on m.user_id=s.owner_id
      where s.id=(d->>'shop_id')::uuid and s.status='active' and not m.blocked and public.delivery_cloud_has_membership(m.user_id,'merchant');
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy cửa hàng.'; end if;
    return jsonb_build_object(
      'shop',jsonb_build_object('id',sh.id,'name',sh.name,'description',sh.description,'address',sh.address,'paused',sh.paused,
        'opening_schedule',sh.opening_schedule,'open',not sh.paused and public.delivery_market_is_open(sh.opening_schedule),
        'banner_url',sh.banner_url,'service_radius_km',sh.service_radius_km),
      'followers',(select count(*) from public.delivery_market_shop_follows where shop_id=sh.id),
      'following',exists(select 1 from public.delivery_market_shop_follows where user_id=auth.uid() and shop_id=sh.id),
      'rating_avg',coalesce((select round(avg(rating)::numeric,2) from public.delivery_partner_reviews where target_kind='shop' and shop_id=sh.id and not hidden),0),
      'rating_count',(select count(*) from public.delivery_partner_reviews where target_kind='shop' and shop_id=sh.id and not hidden),
      'partner_reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from
        (select id,rating,body,reply,replied_at,created_at from public.delivery_partner_reviews where target_kind='shop' and shop_id=sh.id and not hidden order by created_at desc,id desc limit 30) r),'[]'::jsonb),
      'vouchers',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'code',v.code,'shop_id',v.shop_id,'title',v.title,'discount_kind',v.discount_kind,'discount_value',v.discount_value,'max_discount',v.max_discount,'min_subtotal',v.min_subtotal,'ends_at',v.ends_at) order by v.created_at desc)
        from public.delivery_market_vouchers v where v.active and v.starts_at<=now() and v.ends_at>now() and v.budget_used<v.budget_total and (v.shop_id is null or v.shop_id=sh.id)),'[]'::jsonb)
    );

  elsif p_action='shop_follow_set' then
    if jsonb_typeof(d->'enabled') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Lựa chọn theo dõi không hợp lệ.'; end if;
    select s.* into sh from public.delivery_market_shops s join public.delivery_cloud_accounts m on m.user_id=s.owner_id
      where s.id=(d->>'shop_id')::uuid and s.status='active' and not m.blocked and public.delivery_cloud_has_membership(m.user_id,'merchant');
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy cửa hàng.'; end if;
    if sh.owner_id=auth.uid() then raise sqlstate 'PT400' using message='Không thể tự theo dõi cửa hàng của mình.'; end if;
    if (d->>'enabled')::boolean then
      insert into public.delivery_market_shop_follows(user_id,shop_id) values(auth.uid(),sh.id) on conflict do nothing;
    else
      delete from public.delivery_market_shop_follows where user_id=auth.uid() and shop_id=sh.id;
    end if;
    return jsonb_build_object('following',(d->>'enabled')::boolean,'followers',(select count(*) from public.delivery_market_shop_follows where shop_id=sh.id));

  elsif p_action='vouchers' then
    return jsonb_build_object('vouchers',coalesce((select jsonb_agg(jsonb_build_object(
      'id',v.id,'code',v.code,'shop_id',v.shop_id,'title',v.title,'discount_kind',v.discount_kind,
      'discount_value',v.discount_value,'max_discount',v.max_discount,'min_subtotal',v.min_subtotal,
      'per_user_limit',v.per_user_limit,'starts_at',v.starts_at,'ends_at',v.ends_at,
      'remaining_budget',v.budget_total-v.budget_used,
      'used_by_me',(select count(*) from public.delivery_market_voucher_usages vu where vu.voucher_id=v.id and vu.user_id=auth.uid() and vu.state='allocated')
    ) order by v.shop_id nulls first,v.created_at desc)
    from public.delivery_market_vouchers v
    where v.active and v.starts_at<=now() and v.ends_at>now() and v.budget_used<v.budget_total
      and (not(d ? 'shop_id') or v.shop_id is null or v.shop_id=(d->>'shop_id')::uuid)),'[]'::jsonb));

  elsif p_action='coins' then
    return jsonb_build_object(
      'balance',coalesce((select balance from public.delivery_market_coin_wallets where user_id=auth.uid()),0),
      'ledger',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc,l.id desc) from
        (select id,delta,kind,reference_id,created_at from public.delivery_market_coin_ledger where user_id=auth.uid() order by created_at desc,id desc limit 50) l),'[]'::jsonb)
    );

  elsif p_action='admin_analytics' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    return jsonb_build_object(
      'cloud_orders',jsonb_build_object(
        'total',(select count(*) from public.delivery_cloud_orders),
        'searching',(select count(*) from public.delivery_cloud_orders where status='searching'),
        'in_transit',(select count(*) from public.delivery_cloud_orders where status in ('accepted','arrivingPickup','inTransit','returning')),
        'delivered',(select count(*) from public.delivery_cloud_orders where status='delivered'),
        'cancelled',(select count(*) from public.delivery_cloud_orders where status='cancelled'),
        'shipping_fee_delivered',coalesce((select sum(shipping_fee) from public.delivery_cloud_orders where status='delivered'),0)
      ),
      'market_orders',jsonb_build_object(
        'total',(select count(*) from public.delivery_market_shop_orders),
        'pending',(select count(*) from public.delivery_market_shop_orders where state='pending'),
        'accepted_ready',(select count(*) from public.delivery_market_shop_orders where state in ('accepted','ready')),
        'delivered',(select count(*) from public.delivery_market_shop_orders where delivered_at is not null and state<>'cancelled'),
        'cancelled',(select count(*) from public.delivery_market_shop_orders where state='cancelled')
      ),
      'finance_totals',jsonb_build_object(
        'collections_completed',coalesce((select sum(amount) from public.delivery_market_finance where kind='collection' and state='completed'),0),
        'refunds_completed',coalesce((select sum(amount) from public.delivery_market_finance where kind='refund' and state='completed'),0),
        'settlements_completed',coalesce((select sum(amount) from public.delivery_market_finance where kind='settlement' and state='completed'),0),
        'pending_requests',(select count(*) from public.delivery_market_finance where state in ('requested','approved'))
      ),
      'ledger_balances',coalesce((select jsonb_object_agg(account,bal) from (select account,coalesce(sum(amount),0) as bal from public.delivery_market_ledger group by account) lb),'{}'::jsonb),
      'shops',jsonb_build_object(
        'active',(select count(*) from public.delivery_market_shops where status='active' and not paused),
        'pending',(select count(*) from public.delivery_market_shops where status='pending'),
        'suspended',(select count(*) from public.delivery_market_shops where status='suspended')
      ),
      'memberships_pending',(select count(*) from public.delivery_cloud_memberships where state='pending'),
      'returns_escalated',(select count(*) from public.delivery_market_returns where state='escalated'),
      'returns_requested',(select count(*) from public.delivery_market_returns where state='requested'),
      'pickups_requested',(select count(*) from public.delivery_cloud_pickups where status='requested'),
      'driver_settlements_pending',(select count(*) from public.delivery_driver_settlements where state in ('requested','approved')),
      'promotions',jsonb_build_object(
        'active_vouchers',(select count(*) from public.delivery_market_vouchers where active and ends_at>now()),
        'voucher_budget_used',coalesce((select sum(budget_used) from public.delivery_market_vouchers),0),
        'active_flash_sales',(select count(*) from public.delivery_market_flash_sales where active and ends_at>now()),
        'coins_circulating',coalesce((select sum(balance) from public.delivery_market_coin_wallets),0)
      ),
      'reported_reviews',(
        (select count(*) from public.delivery_market_reviews where report_count>0 and not hidden) +
        (select count(*) from public.delivery_partner_reviews where report_count>0 and not hidden)
      )
    );

  elsif p_action='operations' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    result := jsonb_build_object(
      'single_operator_mode',((select count(*) from public.delivery_api_profiles ap left join public.delivery_cloud_accounts ca on ca.user_id=ap.user_id where ap.role='operator' and coalesce(ca.blocked,false)=false)<=1),
      'finance',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
        (select * from public.delivery_market_finance where (not(d ? 'before') or (created_at,id)<((d->>'before')::timestamptz,(d->>'before_id')::uuid)) order by created_at desc,id desc limit 50) x),'[]'),
      'returns',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
        (select * from public.delivery_market_returns where state in ('requested','escalated')
          and (not(d ? 'before_returns') or (created_at,id)<((d->>'before_returns')::timestamptz,(d->>'before_return_id')::uuid)) order by created_at desc,id desc limit 50) x),'[]'),
      'jobs',jsonb_build_object('pending',(select count(*) from public.delivery_market_jobs where state='pending'),
        'failed',(select count(*) from public.delivery_market_jobs where state='failed'),
        'overdue',(select count(*) from public.delivery_market_jobs where state='pending' and run_at<=now())),
      'failed_jobs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.delivery_market_jobs where state='failed' order by run_at,id limit 50) x),'[]'),
      'vouchers',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc) from (select * from public.delivery_market_vouchers order by created_at desc,id desc limit 50) v),'[]'),
      'flash_sales',coalesce((select jsonb_agg(to_jsonb(fs) order by fs.created_at desc,fs.id desc) from (select * from public.delivery_market_flash_sales order by created_at desc,id desc limit 50) fs),'[]'),
      'reported_reviews',coalesce((select jsonb_agg(r order by (r->>'report_count')::int desc,r->>'created_at' desc) from (
        select jsonb_build_object('review_kind','product','id',id,'target_id',product_id,'rating',rating,'body',body,'reply',reply,'report_count',report_count,'hidden',hidden,'created_at',created_at) as r
          from public.delivery_market_reviews where report_count>0 or hidden
        union all
        select jsonb_build_object('review_kind','partner','id',id,'target_kind',target_kind,'target_id',coalesce(shop_id,driver_id),'rating',rating,'body',body,'reply',reply,'report_count',report_count,'hidden',hidden,'created_at',created_at) as r
          from public.delivery_partner_reviews where report_count>0 or hidden
        limit 50
      ) q),'[]')
    );
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
    rev_kind := coalesce(d->>'review_kind','product');
    if rev_kind not in ('product','partner') or jsonb_typeof(d->'hidden') is distinct from 'boolean' or length(btrim(coalesce(d->>'reason',''))) not between 3 and 500 then
      raise sqlstate 'PT400' using message='Cần lý do kiểm duyệt hợp lệ.';
    end if;
    if rev_kind='partner' then
      update public.delivery_partner_reviews set hidden=(d->>'hidden')::boolean
        where id=(d->>'id')::uuid returning reviewer_id into v_review_author;
    else
      update public.delivery_market_reviews set hidden=(d->>'hidden')::boolean
        where id=(d->>'id')::uuid returning user_id into v_review_author;
    end if;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'review_moderate',(d->>'id')::uuid,d);
    if v_review_author is not null and v_review_author <> auth.uid() then
      perform public.delivery_emit_notification(
        v_review_author,
        'market',
        'review_moderated',
        case when (d->>'hidden')::boolean then 'Đánh giá của bạn đã tạm ẩn do kiểm duyệt'
             else 'Đánh giá của bạn đã được hiển thị lại' end,
        'Lý do kiểm duyệt: ' || left(btrim(d->>'reason'), 240),
        'review',
        (d->>'id')::uuid,
        jsonb_build_object('review_kind', rev_kind, 'hidden', (d->>'hidden')::boolean)
      );
    end if;
    return jsonb_build_object('ok',true);

  elsif p_action='partner_review_save' then
    v_target_kind := d->>'target_kind';
    if v_target_kind is null or v_target_kind not in ('shop','driver') or
       jsonb_typeof(d->'rating') is distinct from 'number' or (d->>'rating')::numeric<>trunc((d->>'rating')::numeric) or
       (d->>'rating')::integer not between 1 and 5 or length(btrim(coalesce(d->>'body',''))) not between 3 and 2000 then
      raise sqlstate 'PT400' using message='Nội dung hoặc số sao đánh giá đối tác không hợp lệ.';
    end if;
    if v_target_kind='shop' then
      select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid for share;
      if not found or so.owner_id<>auth.uid() or so.merchant_id=auth.uid()
         or public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff')
         or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '30 days' then
        raise sqlstate 'PT403' using message='Chỉ người mua đã nhận hàng trong 30 ngày được đánh giá cửa hàng.';
      end if;
      select * into pr from public.delivery_partner_reviews where target_kind='shop' and shop_order_id=so.id;
      if found then
        if pr.rating<>(d->>'rating')::integer or pr.body<>btrim(d->>'body') then raise sqlstate 'PT409' using message='Cửa hàng đã được đánh giá cho đơn này.'; end if;
        return jsonb_build_object('partner_review',to_jsonb(pr)-'reviewer_id');
      end if;
      insert into public.delivery_partner_reviews(target_kind,shop_order_id,cloud_order_id,shop_id,reviewer_id,rating,body)
        values('shop',so.id,so.delivery_id,so.shop_id,auth.uid(),(d->>'rating')::integer,btrim(d->>'body')) returning * into pr;
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'shop_reviewed');
      perform public.delivery_notify_shop_team(
        so.shop_id, so.merchant_id, 'staff', 'market', 'shop_reviewed',
        'Đánh giá mới từ khách mua hàng',
        'Khách hàng vừa đánh giá ' || pr.rating || ' sao cho cửa hàng.',
        'market_order', so.id, jsonb_build_object('order_id', so.id, 'rating', pr.rating)
      );
      return jsonb_build_object('partner_review',to_jsonb(pr)-'reviewer_id');
    else
      if d ? 'cloud_order_id' and jsonb_typeof(d->'cloud_order_id')='string' then
        select * into co from public.delivery_cloud_orders where id=(d->>'cloud_order_id')::uuid for share;
      elsif d ? 'order_id' and jsonb_typeof(d->'order_id')='string' then
        select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid for share;
        if found then
          if so.delivery_id is not null then
            select * into co from public.delivery_cloud_orders where id=so.delivery_id and status='delivered' for share;
          end if;
          if co.id is null then
            select co2.* into co
              from public.delivery_market_shipments ms
              join public.delivery_cloud_orders co2 on co2.id = ms.delivery_id
              where ms.order_id = so.id and co2.status = 'delivered' and co2.driver_id is not null
              order by ms.parcel_index asc limit 1 for share;
          end if;
        end if;
      end if;
      if co.id is null or co.owner_id<>auth.uid() or co.status<>'delivered' or co.driver_id is null
         or co.driver_id=auth.uid() or co.updated_at<now()-interval '30 days' then
        raise sqlstate 'PT403' using message='Chỉ người đặt đơn đã giao thành công trong 30 ngày được đánh giá tài xế.';
      end if;
      select * into pr from public.delivery_partner_reviews where target_kind='driver' and cloud_order_id=co.id and reviewer_id=auth.uid();
      if found then
        if pr.rating<>(d->>'rating')::integer or pr.body<>btrim(d->>'body') then raise sqlstate 'PT409' using message='Tài xế đã được đánh giá cho chuyến này.'; end if;
        return jsonb_build_object('partner_review',to_jsonb(pr)-'reviewer_id');
      end if;
      insert into public.delivery_partner_reviews(target_kind,shop_order_id,cloud_order_id,driver_id,reviewer_id,rating,body)
        values('driver',so.id,co.id,co.driver_id,auth.uid(),(d->>'rating')::integer,btrim(d->>'body')) returning * into pr;
      return jsonb_build_object('partner_review',to_jsonb(pr)-'reviewer_id');
    end if;

  elsif p_action='review_reply' then
    rev_kind := coalesce(d->>'review_kind','product');
    if rev_kind not in ('product','partner') or length(btrim(coalesce(d->>'reply',''))) not between 3 and 1000 then
      raise sqlstate 'PT400' using message='Nội dung phản hồi đánh giá không hợp lệ.';
    end if;
    if rev_kind='product' then
      select r.* into rev from public.delivery_market_reviews r where r.id=(d->>'id')::uuid for update;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá sản phẩm.'; end if;
      select * into prod from public.delivery_market_products where id=rev.product_id;
      if not public.delivery_market_can_access_shop(prod.shop_id,auth.uid(),'staff') then
        raise sqlstate 'PT403' using message='Chỉ cửa hàng được phản hồi đánh giá sản phẩm.';
      end if;
      update public.delivery_market_reviews set reply=btrim(d->>'reply'),replied_at=now() where id=rev.id returning * into rev;
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(rev.user_id,rev.order_id,'review_replied');
      return jsonb_build_object('review',to_jsonb(rev)-'user_id');
    else
      select * into pr from public.delivery_partner_reviews where id=(d->>'id')::uuid for update;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá đối tác.'; end if;
      if (pr.target_kind='shop' and not public.delivery_market_can_access_shop(pr.shop_id,auth.uid(),'staff')) or
         (pr.target_kind='driver' and (pr.driver_id<>auth.uid() or not public.delivery_cloud_has_membership(auth.uid(),'driver'))) then
        raise sqlstate 'PT403' using message='Chỉ đối tác nhận đánh giá được phản hồi.';
      end if;
      update public.delivery_partner_reviews set reply=btrim(d->>'reply'),replied_at=now() where id=pr.id returning * into pr;
      return jsonb_build_object('partner_review',to_jsonb(pr)-'reviewer_id');
    end if;

  elsif p_action='review_report' then
    rev_kind := coalesce(d->>'review_kind','product');
    if rev_kind not in ('product','partner') or length(btrim(coalesce(d->>'reason',''))) not between 3 and 500 then
      raise sqlstate 'PT400' using message='Cần lý do báo cáo đánh giá hợp lệ.';
    end if;
    if rev_kind='product' then
      select * into rev from public.delivery_market_reviews where id=(d->>'id')::uuid and not hidden for update;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá.'; end if;
      if rev.user_id=auth.uid() then raise sqlstate 'PT400' using message='Không thể tự báo cáo đánh giá của mình.'; end if;
      insert into public.delivery_market_review_reports(review_kind,review_id,reporter_id,reason)
        values('product',rev.id,auth.uid(),btrim(d->>'reason')) on conflict do nothing returning review_id into k;
      if k is not null then update public.delivery_market_reviews set report_count=report_count+1 where id=rev.id; end if;
    else
      select * into pr from public.delivery_partner_reviews where id=(d->>'id')::uuid and not hidden for update;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá.'; end if;
      if pr.reviewer_id=auth.uid() then raise sqlstate 'PT400' using message='Không thể tự báo cáo đánh giá của mình.'; end if;
      insert into public.delivery_market_review_reports(review_kind,review_id,reporter_id,reason)
        values('partner',pr.id,auth.uid(),btrim(d->>'reason')) on conflict do nothing returning review_id into k;
      if k is not null then update public.delivery_partner_reviews set report_count=report_count+1 where id=pr.id; end if;
    end if;
    if k is not null then
      perform public.delivery_notify_operators(
        auth.uid(), 'market', 'review_reported',
        'Có báo cáo đánh giá cần kiểm duyệt',
        'Lý do báo cáo: ' || left(btrim(d->>'reason'), 220),
        'review', (d->>'id')::uuid, jsonb_build_object('review_kind', rev_kind)
      );
    end if;
    return jsonb_build_object('ok',true);

  elsif p_action='finance_action' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    select order_id into k from public.delivery_market_finance where id=(d->>'id')::uuid;
    select * into so from public.delivery_market_shop_orders where id=k for update;
    select * into f from public.delivery_market_finance where id=(d->>'id')::uuid for update;
    if f.id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu tài chính.'; end if;
    select count(*)::integer into v_op_count
      from public.delivery_api_profiles ap
      left join public.delivery_cloud_accounts ca on ca.user_id = ap.user_id
      where ap.role='operator' and not coalesce(ca.blocked,false);
    if f.proposer=auth.uid() and v_op_count > 1 then
      raise sqlstate 'PT403' using message='Người đề nghị không được tự duyệt hoặc xác nhận chi tiền khi hệ thống có nhiều quản trị viên.';
    end if;
    if f.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Yêu cầu đã thay đổi.'; end if;
    requested := d->>'action';
    if requested in ('approve','reject') and length(btrim(coalesce(d->>'reason',''))) not between 3 and 1000 then
      raise sqlstate 'PT400' using message='Cần lý do duyệt/từ chối.';
    end if;
    if requested='approve' and f.state='requested' then
      update public.delivery_market_finance set state='approved',approver=auth.uid(),version=version+1 where id=f.id returning * into f;
    elsif requested='reject' and f.state in ('requested','approved') then
      update public.delivery_market_finance set state='rejected',approver=auth.uid(),version=version+1 where id=f.id returning * into f;
    elsif requested='complete' and f.state='approved' then
      if length(btrim(coalesce(d->>'evidence',''))) not between 3 and 500 then
        raise sqlstate 'PT400' using message='Cần mã chứng từ thu/chi thực tế.';
      end if;
      goods := (so.snapshot->>'subtotal')::bigint;
      shop_disc := coalesce((so.snapshot->>'shop_discount')::bigint,0);
      plat_disc := coalesce((so.snapshot->>'platform_discount')::bigint,0);
      freight := (so.snapshot->>'shipping_fee')::bigint;
      merch_net := greatest(0,goods-shop_disc);
      due := greatest(0,goods-shop_disc-plat_disc)+freight;
      select coalesce(sum(amount) filter(where kind='collection'),0),
             coalesce(sum(amount) filter(where kind='refund'),0),
             coalesce(sum(amount) filter(where kind='settlement'),0)
        into collected,refunded,settled
        from public.delivery_market_finance where order_id=so.id and state='completed';

      if f.kind='collection' and (so.delivered_at is null or so.state='cancelled' or f.amount<>due or collected<>0) then
        raise sqlstate 'PT409' using message='Chỉ xác nhận đủ tiền COD một lần sau giao thành công.';
      elsif f.kind='refund' then
        if f.return_id is null then
          if so.state<>'cancelled' or so.delivered_at is not null or collected<=0 or refunded<>0 or settled<>0 or f.amount<>collected then
            raise sqlstate 'PT409' using message='Chỉ hoàn toàn bộ tiền đơn trả trước đã hủy trước khi giao hàng.';
          end if;
        else
          select * into ret from public.delivery_market_returns where id=f.return_id and order_id=so.id;
          select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state='completed';
          select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
          if ret.id is null or ret.state<>'received' or f.amount>ret.quantity*(item->>'unit_price')::bigint-used
            or f.amount>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled) then
            raise sqlstate 'PT409' using message='Khoản hoàn vượt mức hoặc chưa nhận hàng trả.';
          end if;
        end if;
      elsif f.kind='settlement' and (f.amount>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled-freight) or exists
        (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=r.line_id) v on true
          where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
          r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))
        or so.delivered_at is null or so.delivered_at>now()-interval '7 days') then
        raise sqlstate 'PT409' using message='Chưa đủ điều kiện đối soát shop: tiền khả dụng, hạn hậu mãi hoặc tranh chấp.';
      end if;

      update public.delivery_market_finance
        set state='completed',completion_evidence=btrim(d->>'evidence'),completed_at=now(),version=version+1
        where id=f.id returning * into f;
      insert into public.delivery_market_journals(finance_id,order_id) values(f.id,so.id) returning id into jid;

      if f.kind='collection' then
        insert into public.delivery_market_ledger values(jid,'cash_clearing',due);
        if plat_disc>0 then insert into public.delivery_market_ledger values(jid,'promo_expense',plat_disc); end if;
        if merch_net>0 then insert into public.delivery_market_ledger values(jid,'merchant_payable',-merch_net); end if;
        if freight>0 then insert into public.delivery_market_ledger values(jid,'shipping_revenue',-freight); end if;
      elsif f.kind='refund' and f.return_id is null then
        insert into public.delivery_market_ledger(journal_id, account, amount)
        select jid, l.account, (-sum(l.amount))::bigint
        from public.delivery_market_journals j
        join public.delivery_market_finance cf on cf.id = j.finance_id
        join public.delivery_market_ledger l on l.journal_id = j.id
        where j.order_id = so.id and cf.kind = 'collection' and cf.state = 'completed'
        group by l.account
        having sum(l.amount) <> 0;
      else
        insert into public.delivery_market_ledger values(jid,'cash_clearing',-f.amount),(jid,'merchant_payable',f.amount);
        if f.kind='settlement' then
          coin_earn := floor(f.amount*0.01)::bigint;
          if coin_earn>0 and not exists(select 1 from public.delivery_market_coin_ledger where user_id=so.owner_id and kind='earn_settlement' and reference_id=f.id) then
            insert into public.delivery_market_coin_wallets(user_id,balance) values(so.owner_id,coin_earn)
              on conflict(user_id) do update set balance=public.delivery_market_coin_wallets.balance+excluded.balance,updated_at=now();
            insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
              values(so.owner_id,coin_earn,'earn_settlement',f.id);
          end if;
        elsif f.kind='refund' then
          select coalesce(balance,0) into wallet_bal from public.delivery_market_coin_wallets where user_id=so.owner_id for update;
          coin_rev := least(wallet_bal,floor(f.amount*0.01)::bigint);
          if coin_rev>0 and not exists(select 1 from public.delivery_market_coin_ledger where user_id=so.owner_id and kind='reverse_refund' and reference_id=f.id) then
            update public.delivery_market_coin_wallets set balance=balance-coin_rev,updated_at=now() where user_id=so.owner_id;
            insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
              values(so.owner_id,-coin_rev,'reverse_refund',f.id);
          end if;
        end if;
      end if;

      update public.delivery_market_purchases p set payment_status=case when
        exists(select 1 from public.delivery_market_shop_orders o where o.purchase_id=p.id and (o.state='cancelled' or not exists
          (select 1 from public.delivery_market_finance c where c.order_id=o.id and c.kind='collection' and c.state='completed')))
        or exists(select 1 from public.delivery_market_finance c join public.delivery_market_shop_orders o on o.id=c.order_id where o.purchase_id=p.id and c.kind='refund' and c.state='completed') then 'REVIEW' else 'PAID' end
        where p.id=so.purchase_id;
    else
      raise sqlstate 'PT409' using message='Không thể chuyển trạng thái yêu cầu tài chính.';
    end if;

    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value)
      values(auth.uid(),'market_finance_'||requested,f.id,to_jsonb(f)||jsonb_build_object('decision_reason',d->>'reason'));

    if f.kind = 'refund' and so.owner_id <> auth.uid() then
      perform public.delivery_emit_notification(
        so.owner_id,
        'market',
        'finance_refund_' || f.state,
        case f.state
          when 'completed' then 'Đã hoàn tiền ' || f.amount || ' đ cho đơn mua'
          when 'approved' then 'Yêu cầu hoàn tiền ' || f.amount || ' đ đã được duyệt'
          else 'Yêu cầu hoàn tiền ' || f.amount || ' đ bị từ chối'
        end,
        case f.state
          when 'completed' then 'Chứng từ hoàn tiền: ' || f.completion_evidence
          else coalesce(nullif(btrim(d->>'reason'),''), 'Vui lòng xem chi tiết trong mục Hậu mãi.')
        end,
        'market_order',
        so.id,
        jsonb_build_object('finance_id', f.id, 'amount', f.amount, 'state', f.state)
      );
    elsif f.kind = 'settlement' then
      perform public.delivery_notify_shop_team(
        so.shop_id,
        auth.uid(),
        'manager',
        'market',
        'finance_settlement_' || f.state,
        case f.state
          when 'completed' then 'Đã giải ngân đối soát ' || f.amount || ' đ'
          when 'approved' then 'Đề nghị đối soát ' || f.amount || ' đ đã được duyệt'
          else 'Đề nghị đối soát ' || f.amount || ' đ bị từ chối'
        end,
        case f.state
          when 'completed' then 'Chứng từ thanh toán: ' || f.completion_evidence
          else coalesce(nullif(btrim(d->>'reason'),''), 'Đã cập nhật trạng thái đối soát cửa hàng.')
        end,
        'market_order',
        so.id,
        jsonb_build_object('finance_id', f.id, 'amount', f.amount, 'state', f.state)
      );
    elsif f.kind = 'collection' and f.proposer <> auth.uid() then
      perform public.delivery_emit_notification(
        f.proposer,
        'shipping',
        'finance_collection_' || f.state,
        case f.state
          when 'completed' then 'Đã xác nhận đối soát khoản thu COD ' || f.amount || ' đ'
          when 'approved' then 'Khoản thu COD ' || f.amount || ' đ đã được duyệt'
          else 'Khoản thu COD ' || f.amount || ' đ bị từ chối'
        end,
        coalesce(nullif(f.completion_evidence,''), nullif(btrim(d->>'reason'),''), 'Đã cập nhật phiếu thu COD.'),
        'market_order',
        so.id,
        jsonb_build_object('finance_id', f.id, 'amount', f.amount, 'state', f.state)
      );
    end if;

    return jsonb_build_object('finance',to_jsonb(f));
  end if;

  select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid
    and (
      owner_id=auth.uid()
      or public.delivery_market_can_access_shop(shop_id,auth.uid(),'staff')
      or op
      or (
        public.delivery_cloud_has_membership(a.user_id,'driver')
        and exists (
          select 1 from public.delivery_cloud_orders o
          where o.driver_id=auth.uid()
            and (o.id=delivery_id or exists(select 1 from public.delivery_market_shipments ms where ms.order_id=delivery_market_shop_orders.id and ms.delivery_id=o.id))
        )
      )
    ) for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;

  if p_action='order_services' then
    if not op and so.owner_id<>auth.uid() and not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff') then
      raise sqlstate 'PT403' using message='Không có quyền xem hậu mãi của đơn này.';
    end if;
    select coalesce(sum(amount) filter(where kind='collection'),0),
           coalesce(sum(amount) filter(where kind='refund'),0),
           coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    return jsonb_build_object(
      'order',to_jsonb(so),
      'collected',collected,'refunded',refunded,'settled',settled,
      'returns',coalesce((select jsonb_agg(
        to_jsonb(r_row) || case when rc.id is not null then jsonb_build_object('return_tracking_code', rc.tracking_code, 'return_delivery_status', rc.status) else '{}'::jsonb end
        order by r_row.created_at,r_row.id)
        from public.delivery_market_returns r_row
        left join public.delivery_cloud_orders rc on rc.id = r_row.return_delivery_id
        where r_row.order_id=so.id),'[]'),
      'reviews',coalesce((select jsonb_agg(to_jsonb(rv_row)-'user_id' order by rv_row.created_at,rv_row.id) from public.delivery_market_reviews rv_row where rv_row.order_id=so.id),'[]'),
      'partner_reviews',coalesce((select jsonb_agg(to_jsonb(prv)-'reviewer_id' order by prv.created_at,prv.id) from public.delivery_partner_reviews prv
        where prv.shop_order_id=so.id
           or (so.delivery_id is not null and prv.cloud_order_id=so.delivery_id)
           or exists(select 1 from public.delivery_market_shipments ms where ms.order_id=so.id and ms.delivery_id=prv.cloud_order_id)),'[]'),
      'shipments',coalesce((select jsonb_agg(jsonb_build_object('parcel_index',ms.parcel_index,'delivery_id',ms.delivery_id,'tracking_code',c_ord.tracking_code,'status',c_ord.status,'weight_kg',ms.weight_kg,'cod_amount',ms.cod_amount) order by ms.parcel_index)
        from public.delivery_market_shipments ms join public.delivery_cloud_orders c_ord on c_ord.id=ms.delivery_id where ms.order_id=so.id),'[]'),
      'attachments',coalesce((select jsonb_agg(jsonb_build_object('id',att.id,'name',att.name,'scope',att.scope,'byte_size',att.byte_size,'created_at',att.created_at) order by att.created_at,att.id)
        from public.delivery_market_attachments att where att.order_id=so.id),'[]'),
      'finance',coalesce((select jsonb_agg(to_jsonb(fin_row)-'evidence'-'completion_evidence'-'request_key' order by fin_row.created_at,fin_row.id) from public.delivery_market_finance fin_row where fin_row.order_id=so.id),'[]'),
      'single_operator_mode',case when op then ((select count(*) from public.delivery_api_profiles ap left join public.delivery_cloud_accounts ca on ca.user_id=ap.user_id where ap.role='operator' and coalesce(ca.blocked,false)=false)<=1) else false end,
      'shares',case when so.owner_id=auth.uid() then coalesce((select jsonb_agg(to_jsonb(sh_row)-'token_hash'-'owner_id' order by sh_row.created_at,sh_row.id) from public.delivery_market_shares sh_row where sh_row.order_id=so.id and sh_row.revoked_at is null and sh_row.expires_at>now()),'[]') else '[]'::jsonb end
    );

  elsif p_action in ('tracking_share','tracking_revoke') then
    if so.owner_id<>auth.uid() then raise sqlstate 'PT403' using message='Chỉ người mua quản lý chia sẻ.'; end if;
    if p_action='tracking_revoke' then
      update public.delivery_market_shares set revoked_at=coalesce(revoked_at,now()) where order_id=so.id and id=(d->>'id')::uuid;
      return jsonb_build_object('ok',true);
    end if;
    if (select count(*) from public.delivery_market_shares where order_id=so.id and revoked_at is null and expires_at>now())>=5 then
      raise sqlstate 'PT409' using message='Tối đa 5 liên kết còn hiệu lực.';
    end if;
    token := replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
    insert into public.delivery_market_shares(order_id,owner_id,token_hash,expires_at)
      values(so.id,auth.uid(),encode(sha256(convert_to(token,'UTF8')),'hex'),now()+interval '24 hours') returning id into k;
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
      var_key := case when item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then (item->>'variant_id')::uuid else null end;
      selection := public.delivery_market_selection_v2(prod.id,coalesce(item->'selected_options','[]'),var_key,1,auth.uid());
      select coalesce((select quantity from public.delivery_market_cart_items where user_id=auth.uid() and line_id=(selection->>'line_id')::uuid),0)+(item->>'quantity')::integer into qty;
      perform public.delivery_marketplace('cart_set',
        jsonb_build_object('product_id',prod.id,'selected_options',selection->'selected_options','quantity',qty,'version',cv)
        || case when var_key is not null then jsonb_build_object('variant_id',var_key) else '{}'::jsonb end);
      cv := cv+1;
    end loop;
    result := public.delivery_marketplace('cart');
    insert into public.delivery_market_commands values(auth.uid(),(d->>'request_key')::uuid,p_action,d,result);
    return result;

  elsif p_action='review_save' then
    if so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '30 days' then
      raise sqlstate 'PT403' using message='Chỉ người mua đã nhận hàng trong 30 ngày được đánh giá.';
    end if;
    if not exists(select 1 from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=(d->>'product_id')::uuid) then
      raise sqlstate 'PT400' using message='Sản phẩm không thuộc đơn.';
    end if;
    if jsonb_typeof(d->'rating') is distinct from 'number' or (d->>'rating')::numeric<>trunc((d->>'rating')::numeric) then
      raise sqlstate 'PT400' using message='Số sao không hợp lệ.';
    end if;
    select to_jsonb(r) into result from public.delivery_market_reviews r where order_id=so.id and product_id=(d->>'product_id')::uuid;
    if result is not null then
      if result->>'body'<>btrim(d->>'body') or (result->>'rating')::integer<>(d->>'rating')::integer then
        raise sqlstate 'PT409' using message='Sản phẩm đã được đánh giá.';
      end if;
      return jsonb_build_object('review',result);
    end if;
    insert into public.delivery_market_reviews(order_id,product_id,user_id,rating,body)
      values(so.id,(d->>'product_id')::uuid,auth.uid(),(d->>'rating')::integer,btrim(d->>'body')) returning to_jsonb(delivery_market_reviews) into result;
    return jsonb_build_object('review',result);

  elsif p_action='return_request' then
    line_key := coalesce(d->>'line_id',d->>'product_id')::uuid;
    if so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '7 days' then
      raise sqlstate 'PT403' using message='Chỉ người mua yêu cầu trả trong 7 ngày sau nhận hàng.';
    end if;
    if d ? 'attachments' then
      if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>5 then
        raise sqlstate 'PT400' using message='Tối đa 5 ảnh bằng chứng trả hàng.';
      end if;
      for att_name in select jsonb_array_elements_text(d->'attachments') loop
        if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='return') then
          raise sqlstate 'PT403' using message='Ảnh bằng chứng không thuộc yêu cầu trả hàng này.';
        end if;
      end loop;
      att_list := d->'attachments';
    end if;
    select * into ret from public.delivery_market_returns where user_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if ret.order_id<>so.id or ret.product_id is distinct from (d->>'product_id')::uuid or ret.line_id is distinct from line_key or ret.quantity is distinct from (d->>'quantity')::integer or ret.reason is distinct from btrim(d->>'reason') then
        raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.';
      end if;
      return jsonb_build_object('return',to_jsonb(ret));
    end if;
    if jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) then
      raise sqlstate 'PT400' using message='Số lượng không hợp lệ.';
    end if;
    select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=line_key and (i->>'product_id')::uuid=(d->>'product_id')::uuid;
    select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and line_id=line_key and state<>'rejected';
    if item is null or (d->>'quantity')::integer+used>(item->>'quantity')::integer then
      raise sqlstate 'PT409' using message='Số lượng trả vượt số lượng đã mua còn lại.';
    end if;
    if (select count(*) from public.delivery_market_returns where order_id=so.id)>=100 then
      raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu trả hàng. Cần quản trị viên kiểm tra.';
    end if;
    var_key := case when item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then (item->>'variant_id')::uuid else null end;
    insert into public.delivery_market_returns(order_id,product_id,variant_id,line_id,user_id,quantity,reason,attachments,request_key)
      values(so.id,(d->>'product_id')::uuid,var_key,line_key,auth.uid(),(d->>'quantity')::integer,btrim(d->>'reason'),att_list,(d->>'request_key')::uuid) returning * into ret;
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'return_requested');
    perform public.delivery_notify_shop_team(
      so.shop_id, so.merchant_id, 'staff', 'market', 'return_requested',
      'Yêu cầu đổi trả mới tại cửa hàng',
      'Khách hàng vừa gửi yêu cầu trả hàng cho đơn ' || left(so.id::text, 8) || '.',
      'market_order', so.id, jsonb_build_object('order_id', so.id, 'return_id', ret.id)
    );
    return jsonb_build_object('return',to_jsonb(ret));

  elsif p_action='return_action' then
    select * into ret from public.delivery_market_returns where id=(d->>'id')::uuid and order_id=so.id for update;
    if ret.id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu trả hàng.'; end if;
    if ret.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Yêu cầu đã thay đổi.'; end if;
    requested := d->>'action';
    if length(btrim(coalesce(d->>'response',''))) not between 3 and 1000 then
      raise sqlstate 'PT400' using message='Cần phản hồi/lý do xử lý.';
    end if;

    if requested='escalate' and ret.state='rejected' and so.owner_id=auth.uid() then
      select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
      select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and line_id=ret.line_id and state<>'rejected';
      if used+ret.quantity>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Đã có yêu cầu khác cho số lượng này.'; end if;
      requested := 'escalated';
    elsif requested in ('approve','reject') and ((public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') and ret.state='requested') or (op and ret.state in ('requested','escalated'))) then
      requested := case requested when 'approve' then 'approved' else 'rejected' end;
      if requested='approved' and coalesce((d->>'create_return_shipment')::boolean,false) and ret.return_delivery_id is null then
        select * into merch_acc from public.delivery_cloud_accounts where user_id=so.merchant_id;
        rev_details := jsonb_build_object(
          'pickup_address',so.snapshot->'details'->>'dropoff_address',
          'pickup_lat',(so.snapshot->'details'->>'dropoff_lat')::float8,
          'pickup_lng',(so.snapshot->'details'->>'dropoff_lng')::float8,
          'dropoff_address',so.snapshot->'details'->>'pickup_address',
          'dropoff_lat',(so.snapshot->'details'->>'pickup_lat')::float8,
          'dropoff_lng',(so.snapshot->'details'->>'pickup_lng')::float8,
          'recipient_name',coalesce(so.snapshot->>'shop_name',merch_acc.full_name,'Cửa hàng'),
          'recipient_phone',coalesce(nullif(merch_acc.phone,''),'0900000000'),
          'package_description','Hoàn trả hàng đơn '||left(so.id::text,8),
          'weight_kg',greatest(0.1,coalesce((so.snapshot->'details'->>'weight_kg')::numeric,1.0)),
          'service_type','standard',
          'payment_method','sender_cash',
          'cod_amount',0,
          'merchant_id',so.merchant_id
        );
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready,payment_status)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('return_id',ret.id),rev_details,
            (so.snapshot->>'distance_meters')::integer,(so.snapshot->>'shipping_fee')::integer,0,(so.snapshot->>'pricing_version')::integer,true,'PAID')
          returning * into rev_ship;
        insert into public.delivery_live_rooms(id) values(rev_ship.tracking_code);
        insert into public.delivery_live_members values(rev_ship.tracking_code,so.owner_id,'customer'),(rev_ship.tracking_code,so.merchant_id,'merchant')
          on conflict do nothing;
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(rev_ship.id,auth.uid(),'create',rev_ship.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(rev_ship.tracking_code,'status',jsonb_build_object('status',rev_ship.status,'version',1));
        ret.return_delivery_id := rev_ship.id;
      end if;
    elsif requested='receive' and ret.state='approved' and (public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') or op) then
      if ret.return_delivery_id is not null then
        select * into rev_ship from public.delivery_cloud_orders where id = ret.return_delivery_id for update;
        if found then
          if rev_ship.status = 'searching' and rev_ship.driver_id is null then
            update public.delivery_cloud_orders
              set status = 'cancelled',
                  cancel_reason = 'Cửa hàng đã tiếp nhận hàng hoàn trực tiếp',
                  version = version + 1,
                  updated_at = now()
              where id = rev_ship.id;
            insert into public.delivery_cloud_history(order_id,actor_id,action,status,version,reason)
              values(rev_ship.id,auth.uid(),'cancel','cancelled',rev_ship.version+1,'Cửa hàng đã tiếp nhận hàng hoàn trực tiếp');
          elsif not op and rev_ship.status not in ('delivered','cancelled','returned') then
            raise sqlstate 'PT409' using message='Vận đơn hoàn hàng đang được tài xế vận chuyển, chờ tài xế giao tới cửa hàng trước khi nhập kho.';
          end if;
        end if;
      end if;

      disp := coalesce(d->>'disposition','writeoff');
      if disp not in ('restock','writeoff') then raise sqlstate 'PT400' using message='Phương án xử lý kho trả hàng không hợp lệ.'; end if;
      if disp='restock' then
        if ret.variant_id is not null then
          update public.delivery_market_variants set stock=stock+ret.quantity,version=version+1,updated_at=now() where id=ret.variant_id;
          insert into public.delivery_market_stock(product_id,variant_id,actor_id,delta,reason,reference_id)
            values(ret.product_id,ret.variant_id,auth.uid(),ret.quantity,'return_restock',ret.id);
        else
          update public.delivery_market_products set stock=stock+ret.quantity,version=version+1,updated_at=now() where id=ret.product_id;
          insert into public.delivery_market_stock(product_id,actor_id,delta,reason,reference_id)
            values(ret.product_id,auth.uid(),ret.quantity,'return_restock',ret.id);
        end if;
      end if;
      ret.disposition := disp;
      requested := 'received';
    else
      raise sqlstate 'PT403' using message='Không có quyền chuyển trạng thái trả hàng.';
    end if;

    update public.delivery_market_returns set state=requested,response=btrim(d->>'response'),
      return_delivery_id=ret.return_delivery_id,disposition=ret.disposition,version=version+1,updated_at=now()
      where id=ret.id returning * into ret;
    insert into public.delivery_market_events(order_id,actor_id,action,reason)
      values(so.id,auth.uid(),'return_'||requested,btrim(d->>'response'));

    if requested = 'escalated' then
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'return_escalated');
      perform public.delivery_notify_operators(
        auth.uid(), 'market', 'return_escalated',
        'Khiếu nại trả hàng cần phân xử',
        'Khách hàng vừa khiếu nại yêu cầu đổi trả của đơn ' || left(so.id::text, 8) || ': ' || left(btrim(d->>'response'), 180),
        'market_order', so.id, jsonb_build_object('order_id', so.id, 'return_id', ret.id)
      );
    elsif op and auth.uid() <> so.owner_id and auth.uid() <> so.merchant_id then
      insert into public.delivery_market_notifications(user_id,order_id,kind)
        values (so.owner_id,so.id,'return_'||requested), (so.merchant_id,so.id,'return_'||requested);
      perform public.delivery_notify_shop_team(
        so.shop_id, so.merchant_id, 'staff', 'market', 'return_'||requested,
        'Phán quyết khiếu nại trả hàng từ Quản trị',
        left(btrim(d->>'response'), 220),
        'market_order', so.id, jsonb_build_object('order_id', so.id, 'return_id', ret.id)
      );
    else
      insert into public.delivery_market_notifications(user_id,order_id,kind)
        values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'return_'||requested);
    end if;
    return jsonb_build_object('return',to_jsonb(ret));

  elsif p_action='finance_request' then
    requested := d->>'kind';
    if requested not in ('collection','refund','settlement') or requested is null then
      raise sqlstate 'PT400' using message='Loại yêu cầu không hợp lệ.';
    end if;
    if not op
       and not (requested='settlement' and public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager'))
       and not (
         requested='collection'
         and public.delivery_cloud_has_membership(a.user_id,'driver')
         and exists(
           select 1 from public.delivery_cloud_orders co2
           where co2.driver_id=auth.uid()
             and (co2.id=so.delivery_id or exists(select 1 from public.delivery_market_shipments ms where ms.order_id=so.id and ms.delivery_id=co2.id))
         )
       )
       and not (requested='refund' and so.owner_id=auth.uid()) then
      raise sqlstate 'PT403' using message='Không có quyền đề nghị khoản thu/chi này.';
    end if;
    if jsonb_typeof(d->'amount') is distinct from 'number' or (d->>'amount')::numeric<>trunc((d->>'amount')::numeric) then
      raise sqlstate 'PT400' using message='Số tiền cần là số nguyên.';
    end if;
    if d ? 'attachments' then
      if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>5 then
        raise sqlstate 'PT400' using message='Tối đa 5 tệp chứng từ đính kèm.';
      end if;
      for att_name in select jsonb_array_elements_text(d->'attachments') loop
        if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='finance') then
          raise sqlstate 'PT403' using message='Chứng từ đính kèm không thuộc đơn này.';
        end if;
      end loop;
      att_list := d->'attachments';
    end if;

    v_return_id := case
      when d ? 'return_id' and jsonb_typeof(d->'return_id')='string' and btrim(d->>'return_id')<>''
      then (d->>'return_id')::uuid
      else null
    end;

    select * into f from public.delivery_market_finance where proposer=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if f.order_id<>so.id or f.kind<>requested or f.amount is distinct from (d->>'amount')::integer
         or f.reason is distinct from btrim(d->>'reason') or f.evidence is distinct from btrim(d->>'evidence')
         or f.return_id is distinct from v_return_id then
        raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.';
      end if;
      return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
    end if;

    if (select count(*) from public.delivery_market_finance where order_id=so.id)>=100 then
      raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu thu/chi. Cần quản trị viên kiểm tra.';
    end if;

    goods := (so.snapshot->>'subtotal')::bigint;
    shop_disc := coalesce((so.snapshot->>'shop_discount')::bigint,0);
    plat_disc := coalesce((so.snapshot->>'platform_discount')::bigint,0);
    freight := (so.snapshot->>'shipping_fee')::bigint;
    merch_net := greatest(0,goods-shop_disc);
    due := greatest(0,goods-shop_disc-plat_disc)+freight;
    select coalesce(sum(amount) filter(where kind='collection'),0),
           coalesce(sum(amount) filter(where kind='refund'),0),
           coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';

    if requested='collection' then
      if so.delivered_at is null or so.state='cancelled' or (d->>'amount')::bigint<>due then
        raise sqlstate 'PT409' using message='COD chỉ được đề nghị đủ tiền một lần sau giao hàng.';
      end if;
      select * into f from public.delivery_market_finance
        where order_id=so.id and kind='collection' and state<>'rejected'
        order by created_at desc limit 1 for update;
      if found then
        if f.state = 'requested' and f.amount = due and f.evidence like 'AUTO-COD-%' then
          update public.delivery_market_finance
            set proposer = auth.uid(),
                reason = btrim(d->>'reason'),
                evidence = btrim(d->>'evidence'),
                attachments = att_list,
                request_key = (d->>'request_key')::uuid
            where id = f.id
            returning * into f;
          return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
        end if;
        raise sqlstate 'PT409' using message='COD chỉ được đề nghị đủ tiền một lần sau giao hàng.';
      end if;
    elsif requested='refund' then
      if v_return_id is null then
        if so.state<>'cancelled' or so.delivered_at is not null or collected<=0 or refunded<>0 or settled<>0
           or (d->>'amount')::bigint<>collected
           or exists(select 1 from public.delivery_market_finance where order_id=so.id and kind='refund' and state<>'rejected') then
          raise sqlstate 'PT409' using message='Chưa nhận hàng trả hoặc khoản hoàn vượt mức.';
        end if;
      else
        select * into ret from public.delivery_market_returns where id=v_return_id and order_id=so.id and state='received';
        select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
        select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state<>'rejected';
        if ret.id is null or (d->>'amount')::bigint>ret.quantity*(item->>'unit_price')::bigint-used
           or (d->>'amount')::bigint>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled) then
          raise sqlstate 'PT409' using message='Chưa nhận hàng trả hoặc khoản hoàn vượt mức.';
        end if;
      end if;
    elsif requested='settlement' and ((d->>'amount')::bigint>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled-freight) or so.delivered_at is null or so.delivered_at>now()-interval '7 days' or exists
      (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=r.line_id) v on true
        where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
        r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))) then
      raise sqlstate 'PT409' using message='Chưa có tiền hàng khả dụng để đối soát.';
    end if;

    insert into public.delivery_market_finance(order_id,kind,amount,return_id,proposer,reason,evidence,attachments,request_key)
      values(so.id,requested,(d->>'amount')::integer,v_return_id,auth.uid(),btrim(d->>'reason'),btrim(d->>'evidence'),att_list,(d->>'request_key')::uuid)
      returning * into f;

    perform public.delivery_notify_operators(
      auth.uid(),
      'market',
      'finance_' || requested || '_requested',
      case requested
        when 'refund' then 'Yêu cầu hoàn tiền ' || f.amount || ' đ chờ duyệt'
        when 'settlement' then 'Đề nghị đối soát cửa hàng ' || f.amount || ' đ chờ duyệt'
        else 'Phiếu thu COD ' || f.amount || ' đ chờ đối soát'
      end,
      'Đơn hàng ' || left(so.id::text, 8) || ' · Lý do: ' || left(btrim(d->>'reason'), 180),
      'finance',
      f.id,
      jsonb_build_object('order_id', so.id, 'kind', requested, 'amount', f.amount)
    );
    return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
  else
    raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end$$;
revoke all on function public.delivery_market_operations_core(text,jsonb) from public, anon, authenticated;

create or replace function public.delivery_market_operations(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  res jsonb;
begin
  res := public.delivery_market_operations_core(p_action, p_payload);
  if p_action in ('vouchers', 'product_details', 'shop_details')
     and jsonb_typeof(res->'vouchers') = 'array' then
    res := jsonb_set(
      res,
      '{vouchers}',
      coalesce((
        select jsonb_agg(
          elem || case when v.owner_user_id is not null then jsonb_build_object('personal', true) else '{}'::jsonb end
          order by ord
        )
        from jsonb_array_elements(res->'vouchers') with ordinality as arr(elem, ord)
        join public.delivery_market_vouchers v on v.id = (elem->>'id')::uuid
        where v.owner_user_id is null or v.owner_user_id = auth.uid()
      ), '[]'::jsonb)
    );
  end if;
  return res;
end $$;
revoke all on function public.delivery_market_operations(text,jsonb) from public, anon;
grant execute on function public.delivery_market_operations(text,jsonb) to authenticated;


-- ============================================================================
-- 7. BULK PICKUP FULL LIFECYCLE & NOTIFICATIONS
-- ============================================================================

create or replace function public.delivery_cloud_pickups_notify() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  v_meta jsonb;
  v_title text;
  v_body text;
  v_kind text;
  v_driver uuid;
begin
  v_meta := jsonb_build_object(
    'pickup_date', new.pickup_date,
    'time_slot', new.time_slot,
    'package_count', new.package_count,
    'status', new.status,
    'shop_id', new.shop_id
  );

  if tg_op = 'INSERT' then
    perform public.delivery_notify_operators(
      actor,
      'shipping',
      'pickup_requested',
      'Phiếu thu gom lô mới chờ điều phối',
      'Phiếu thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' tại ' || left(new.pickup_address, 120) || '.',
      'pickup',
      new.id,
      v_meta
    );
    if new.shop_id is not null then
      perform public.delivery_notify_shop_team(
        new.shop_id,
        actor,
        'staff',
        'shipping',
        'pickup_requested',
        'Đã tạo phiếu thu gom lô mới',
        'Phiếu thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' đang chờ tài xế nhận ca.',
        'pickup',
        new.id,
        v_meta
      );
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    case new.status
      when 'assigned' then
        v_kind := 'pickup_assigned';
        v_title := 'Đã có tài xế nhận ca thu gom lô';
        v_body := 'Phiếu thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' đã có tài xế phụ trách.';
      when 'arrived' then
        v_kind := 'pickup_arrived';
        v_title := 'Tài xế đã tới điểm thu gom kho';
        v_body := 'Tài xế đang có mặt tại kho để nhận lô ' || new.package_count || ' kiện.';
      when 'picked_up' then
        v_kind := 'pickup_picked_up';
        v_title := 'Đã bàn giao lô thu gom cho tài xế';
        v_body := 'Tài xế đã tiếp nhận ' || new.package_count || ' kiện và đang vận chuyển về trạm điều phối.';
      when 'completed' then
        v_kind := 'pickup_completed';
        v_title := 'Hoàn tất ca thu gom kho';
        v_body := 'Ca thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' đã hoàn tất bàn giao.';
      when 'cancelled' then
        v_kind := 'pickup_cancelled';
        v_title := 'Phiếu thu gom lô đã hủy';
        v_body := 'Phiếu thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' đã hủy'
          || case when length(btrim(coalesce(new.cancel_reason, ''))) > 0
                  then ': ' || left(btrim(new.cancel_reason), 160)
                  else '.' end;
      else
        v_title := null;
    end case;

    if v_title is not null then
      if new.shop_id is not null then
        perform public.delivery_notify_shop_team(
          new.shop_id, actor, 'staff', 'shipping', v_kind, v_title, v_body, 'pickup', new.id, v_meta
        );
      end if;
      if new.merchant_id is distinct from actor
         and (new.shop_id is null or not public.delivery_market_can_access_shop(new.shop_id, new.merchant_id, 'staff')) then
        perform public.delivery_emit_notification(
          new.merchant_id, 'shipping', v_kind, v_title, v_body, 'pickup', new.id, v_meta
        );
      end if;
    end if;

    if new.status = 'assigned' then
      if new.driver_id is not null and new.driver_id is distinct from actor then
        perform public.delivery_emit_notification(
          new.driver_id,
          'shipping',
          'pickup_driver_assigned',
          'Phân công ca thu gom kho mới',
          'Bạn được điều phối thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' tại ' || left(new.pickup_address, 120) || '.',
          'pickup',
          new.id,
          v_meta
        );
      elsif new.driver_id is not null and actor = new.driver_id then
        perform public.delivery_notify_operators(
          actor,
          'shipping',
          'pickup_claimed',
          'Tài xế đã tự nhận ca thu gom lô',
          'Ca thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' đã có tài xế nhận ca.',
          'pickup',
          new.id,
          v_meta
        );
      end if;
    elsif new.status = 'cancelled' then
      v_driver := coalesce(new.driver_id, old.driver_id);
      if v_driver is not null and v_driver is distinct from actor then
        perform public.delivery_emit_notification(
          v_driver, 'shipping', 'pickup_cancelled', v_title, v_body, 'pickup', new.id, v_meta
        );
      end if;
    end if;
  end if;

  return new;
end; $$;
revoke all on function public.delivery_cloud_pickups_notify() from public, anon, authenticated;

drop trigger if exists z_delivery_cloud_pickups_notify on public.delivery_cloud_pickups;
create trigger z_delivery_cloud_pickups_notify
  after insert or update of status on public.delivery_cloud_pickups
  for each row execute function public.delivery_cloud_pickups_notify();

create or replace function public.delivery_cloud_logistics(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  addr public.delivery_cloud_addresses;
  pk public.delivery_cloud_pickups;
  o public.delivery_cloud_orders;
  v_shop public.delivery_market_shops;
  v_shop_owner public.delivery_cloud_accounts;
  v_shop_id uuid;
  v_order_ids uuid[] := '{}'::uuid[];
  v_oid uuid;
  v_act text;
  v_reason text;
  v_addr_id uuid;
  v_pickup_addr text;
  v_pickup_lat double precision;
  v_pickup_lng double precision;
  v_contact_name text;
  v_contact_phone text;
  local_now timestamp := now() at time zone 'Asia/Ho_Chi_Minh';
  v_slot time;
  v_day date;
  v_packages numeric;
  v_weight numeric;
  v_driver uuid;
  v_phone text;
  v_delivered integer;
  v_failed integer;
  v_flagged boolean;
  v_score integer;
  v_instruction text;
  v_since timestamptz := now() - interval '30 days';
  v_result jsonb;
begin
  if uid is null then raise sqlstate 'PT401' using message = 'Cần đăng nhập.'; end if;
  if not op and not public.delivery_cloud_active() then raise sqlstate 'PT403' using message = 'Cần hồ sơ đang hoạt động.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 8000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu vận hành không hợp lệ.';
  end if;

  if p_action = 'pickup_list' then
    return jsonb_build_object(
      'pickups', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id,
          'merchant_id', p.merchant_id,
          'merchant_name', m.full_name,
          'shop_id', p.shop_id,
          'shop_name', sh.name,
          'order_ids', to_jsonb(p.order_ids),
          'address_id', p.address_id,
          'pickup_address', p.pickup_address,
          'pickup_lat', p.pickup_lat,
          'pickup_lng', p.pickup_lng,
          'contact_name', p.contact_name,
          'contact_phone', p.contact_phone,
          'vehicle_type', p.vehicle_type,
          'pickup_date', p.pickup_date,
          'time_slot', p.time_slot,
          'package_count', p.package_count,
          'total_weight_kg', p.total_weight_kg,
          'note', p.note,
          'status', p.status,
          'driver_id', p.driver_id,
          'driver_name', dr.full_name,
          'assigned_at', p.assigned_at,
          'arrived_at', p.arrived_at,
          'picked_up_at', p.picked_up_at,
          'completed_at', p.completed_at,
          'cancelled_at', p.cancelled_at,
          'cancel_reason', p.cancel_reason,
          'version', p.version,
          'created_at', p.created_at,
          'updated_at', p.updated_at
        ) order by p.created_at desc, p.id desc)
        from (
          select *
          from public.delivery_cloud_pickups p0
          where op
            or uid in (p0.merchant_id, p0.driver_id)
            or (p0.shop_id is not null and public.delivery_market_can_access_shop(p0.shop_id, uid, 'staff'))
            or (
              p0.status = 'requested'
              and p0.driver_id is null
              and public.delivery_cloud_has_membership(uid, 'driver')
              and uid <> p0.merchant_id
              and (p0.shop_id is null or not public.delivery_market_can_access_shop(p0.shop_id, uid, 'staff'))
            )
          order by p0.created_at desc, p0.id desc
          limit 50
        ) p
        join public.delivery_cloud_accounts m on m.user_id = p.merchant_id
        left join public.delivery_market_shops sh on sh.id = p.shop_id
        left join public.delivery_cloud_accounts dr on dr.user_id = p.driver_id
      ), '[]'::jsonb),
      'drivers', case when op then coalesce((
        select jsonb_agg(jsonb_build_object('user_id', a.user_id, 'full_name', a.full_name) order by a.full_name, a.user_id)
        from public.delivery_cloud_accounts a
        where public.delivery_cloud_has_membership(a.user_id, 'driver')
      ), '[]'::jsonb) else '[]'::jsonb end
    );

  elsif p_action = 'pickup_create' then
    if d - array['request_key','address_id','shop_id','order_ids','vehicle_type','pickup_date','time_slot','package_count','total_weight_kg','note'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Phiếu thu gom có trường không hợp lệ.';
    end if;

    if d ? 'shop_id' and d->'shop_id' is not null and jsonb_typeof(d->'shop_id') <> 'null' and btrim(coalesce(d->>'shop_id', '')) <> '' then
      if jsonb_typeof(d->'shop_id') <> 'string' then
        raise sqlstate 'PT400' using message = 'Mã cửa hàng thu gom không hợp lệ.';
      end if;
      v_shop_id := (d->>'shop_id')::uuid;
      select * into v_shop from public.delivery_market_shops where id = v_shop_id;
      if v_shop.id is null then
        raise sqlstate 'PT404' using message = 'Không tìm thấy cửa hàng thu gom.';
      end if;
      if v_shop.status = 'suspended' or not public.delivery_market_can_access_shop(v_shop.id, uid, 'staff') then
        raise sqlstate 'PT403' using message = 'Không có quyền tạo phiếu thu gom cho cửa hàng này.';
      end if;
    else
      if not public.delivery_cloud_has_membership(uid, 'merchant') then
        raise sqlstate 'PT403' using message = 'Cần tư cách cửa hàng đã được duyệt hoặc phân quyền nhân sự cửa hàng.';
      end if;
    end if;

    if jsonb_typeof(d->'request_key') is distinct from 'string'
       or (v_shop_id is null and jsonb_typeof(d->'address_id') is distinct from 'string')
       or (d ? 'address_id' and d->'address_id' is not null and jsonb_typeof(d->'address_id') not in ('string','null'))
       or jsonb_typeof(d->'package_count') is distinct from 'number'
       or jsonb_typeof(d->'total_weight_kg') is distinct from 'number'
       or (d ? 'note' and jsonb_typeof(d->'note') is distinct from 'string')
       or coalesce(d->>'pickup_date', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise sqlstate 'PT400' using message = 'Phiếu thu gom có trường không hợp lệ.';
    end if;

    if d ? 'order_ids' and d->'order_ids' is not null and jsonb_typeof(d->'order_ids') <> 'null' then
      if jsonb_typeof(d->'order_ids') <> 'array' or jsonb_array_length(d->'order_ids') > 100 then
        raise sqlstate 'PT400' using message = 'Danh sách vận đơn thu gom không hợp lệ.';
      end if;
      for v_oid in select (jsonb_array_elements_text(d->'order_ids'))::uuid loop
        if not exists (
          select 1 from public.delivery_cloud_orders co
          where co.id = v_oid
            and (
              co.owner_id = uid
              or co.merchant_id = uid
              or public.delivery_can_access_cloud_order_as_shop_staff(co.id, uid)
            )
        ) then
          raise sqlstate 'PT403' using message = 'Vận đơn đính kèm không thuộc quyền quản lý của cửa hàng.';
        end if;
        v_order_ids := array_append(v_order_ids, v_oid);
      end loop;
    end if;

    perform pg_advisory_xact_lock(hashtextextended('pickup:' || uid::text || (d->>'request_key'), 0));
    select * into pk from public.delivery_cloud_pickups where merchant_id = uid and request_key = (d->>'request_key')::uuid;
    if found then
      if pk.request_payload <> d then
        raise sqlstate 'PT409' using message = 'Mã yêu cầu đã dùng cho nội dung khác.';
      end if;
      return to_jsonb(pk) - 'request_payload' - 'request_key';
    end if;

    v_day := (d->>'pickup_date')::date;
    v_slot := case d->>'time_slot' when 'morning' then time '09:00' when 'afternoon' then time '14:00' when 'evening' then time '18:00' end;
    if v_slot is null or v_day + v_slot <= local_now or v_day > local_now::date + 14 then
      raise sqlstate 'PT400' using message = 'Ngày và khung giờ thu gom phải chưa bắt đầu và trong 14 ngày tới.';
    end if;
    v_packages := (d->>'package_count')::numeric;
    v_weight := (d->>'total_weight_kg')::numeric;
    if v_packages <> trunc(v_packages) or v_packages not between 1 and 1000 or v_weight <= 0 or v_weight <> round(v_weight, 1)
       or v_weight > (case d->>'vehicle_type' when 'tricycle_300kg' then 300 when 'van_500kg' then 500 when 'box_truck_1500kg' then 1500 else 0 end)
       or length(btrim(coalesce(d->>'note', ''))) > 500 then
      raise sqlstate 'PT400' using message = 'Số kiện, khối lượng hoặc loại xe không hợp lệ.';
    end if;

    if d ? 'address_id' and jsonb_typeof(d->'address_id') = 'string' and btrim(d->>'address_id') <> '' then
      select * into addr
      from public.delivery_cloud_addresses
      where id = (d->>'address_id')::uuid
        and (user_id = uid or (v_shop.id is not null and user_id = v_shop.owner_id));
      if not found then
        raise sqlstate 'PT404' using message = 'Không tìm thấy địa chỉ kho trong sổ địa chỉ.';
      end if;
      v_addr_id := addr.id;
      v_pickup_addr := addr.full_address;
      v_pickup_lat := addr.latitude;
      v_pickup_lng := addr.longitude;
      v_contact_name := addr.recipient_name;
      v_contact_phone := addr.recipient_phone;
    else
      select * into v_shop_owner from public.delivery_cloud_accounts where user_id = v_shop.owner_id;
      if v_shop_owner.user_id is null then
        raise sqlstate 'PT404' using message = 'Không tìm thấy thông tin liên hệ cửa hàng.';
      end if;
      v_addr_id := v_shop.id;
      v_pickup_addr := v_shop.address;
      v_pickup_lat := v_shop.latitude;
      v_pickup_lng := v_shop.longitude;
      v_contact_name := left(coalesce(nullif(btrim(v_shop.name), ''), v_shop_owner.full_name), 120);
      v_contact_phone := v_shop_owner.phone;
    end if;

    insert into public.delivery_cloud_pickups(
      merchant_id, shop_id, order_ids, request_key, request_payload, address_id,
      pickup_address, pickup_lat, pickup_lng, contact_name, contact_phone,
      vehicle_type, pickup_date, time_slot, package_count, total_weight_kg, note
    ) values (
      uid, v_shop_id, v_order_ids, (d->>'request_key')::uuid, d, v_addr_id,
      v_pickup_addr, v_pickup_lat, v_pickup_lng, v_contact_name, v_contact_phone,
      d->>'vehicle_type', v_day, d->>'time_slot', v_packages::integer, v_weight, btrim(coalesce(d->>'note', ''))
    ) returning * into pk;
    return to_jsonb(pk) - 'request_payload' - 'request_key';

  elsif p_action = 'pickup_assign' then
    if not op then raise sqlstate 'PT403' using message = 'Cần quyền quản trị.'; end if;
    if d - array['id', 'version', 'driver_id'] <> '{}'::jsonb
       or jsonb_typeof(d->'version') is distinct from 'number'
       or jsonb_typeof(d->'driver_id') is distinct from 'string' then
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
    if v_driver = pk.merchant_id or (pk.shop_id is not null and public.delivery_market_can_access_shop(pk.shop_id, v_driver, 'staff')) then
      raise sqlstate 'PT409' using message = 'Không thể phân công tài xế thu gom cho chính cửa hàng của tài xế đó.';
    end if;
    update public.delivery_cloud_pickups
      set status = 'assigned',
          driver_id = v_driver,
          assigned_by = uid,
          assigned_at = now(),
          version = version + 1,
          updated_at = now()
      where id = pk.id
      returning * into pk;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values(uid, 'pickup_assign', pk.id, jsonb_build_object('driver_id', pk.driver_id, 'version', pk.version));
    return to_jsonb(pk) - 'request_payload' - 'request_key';

  elsif p_action = 'pickup_transition' then
    if d - array['id', 'action', 'version', 'request_key', 'reason'] <> '{}'::jsonb
       or jsonb_typeof(d->'id') is distinct from 'string'
       or jsonb_typeof(d->'action') is distinct from 'string'
       or jsonb_typeof(d->'version') is distinct from 'number'
       or (d ? 'reason' and jsonb_typeof(d->'reason') is distinct from 'string') then
      raise sqlstate 'PT400' using message = 'Thao tác ca thu gom không hợp lệ.';
    end if;
    v_act := btrim(d->>'action');
    v_reason := btrim(coalesce(d->>'reason', ''));
    if v_act not in ('claim', 'arrive', 'pickup', 'complete', 'cancel') or length(v_reason) > 500 then
      raise sqlstate 'PT400' using message = 'Thao tác hoặc ghi chú ca thu gom không hợp lệ.';
    end if;
    if v_act = 'cancel' and length(v_reason) < 3 then
      raise sqlstate 'PT400' using message = 'Cần nhập lý do hủy ca thu gom ít nhất 3 ký tự.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('driver:' || uid::text, 0));
    select * into pk from public.delivery_cloud_pickups where id = (d->>'id')::uuid for update;
    if not found then
      raise sqlstate 'PT404' using message = 'Không tìm thấy phiếu thu gom.';
    end if;
    if pk.version is distinct from (d->>'version')::numeric then
      raise sqlstate 'PT409' using message = 'Phiếu thu gom đã thay đổi. Vui lòng tải lại.';
    end if;

    if v_act = 'claim' then
      if not public.delivery_cloud_has_membership(uid, 'driver') then
        raise sqlstate 'PT403' using message = 'Cần tư cách tài xế đã được duyệt để nhận ca thu gom.';
      end if;
      if pk.status <> 'requested' or pk.driver_id is not null then
        raise sqlstate 'PT409' using message = 'Ca thu gom đã có tài xế nhận hoặc không còn khả dụng.';
      end if;
      if uid = pk.merchant_id or (pk.shop_id is not null and public.delivery_market_can_access_shop(pk.shop_id, uid, 'staff')) then
        raise sqlstate 'PT409' using message = 'Tài xế không được tự nhận ca thu gom của chính mình hoặc cửa hàng mình làm việc.';
      end if;
      if exists (
        select 1 from public.delivery_cloud_pickups
        where driver_id = uid and status in ('assigned', 'arrived', 'picked_up')
      ) then
        raise sqlstate 'PT409' using message = 'Bạn đang có ca thu gom kho chưa hoàn tất.';
      end if;
      update public.delivery_cloud_pickups
        set status = 'assigned',
            driver_id = uid,
            assigned_by = uid,
            assigned_at = now(),
            version = version + 1,
            updated_at = now()
        where id = pk.id
        returning * into pk;

    elsif v_act = 'arrive' then
      if not op and (uid is distinct from pk.driver_id or not public.delivery_cloud_has_membership(uid, 'driver')) then
        raise sqlstate 'PT403' using message = 'Chỉ tài xế phụ trách ca thu gom hoặc quản trị viên được cập nhật.';
      end if;
      if pk.status <> 'assigned' then
        raise sqlstate 'PT409' using message = 'Chỉ xác nhận đến kho khi ca thu gom đang ở trạng thái đã điều xe.';
      end if;
      update public.delivery_cloud_pickups
        set status = 'arrived',
            arrived_at = coalesce(arrived_at, now()),
            version = version + 1,
            updated_at = now()
        where id = pk.id
        returning * into pk;

    elsif v_act = 'pickup' then
      if not op and (uid is distinct from pk.driver_id or not public.delivery_cloud_has_membership(uid, 'driver')) then
        raise sqlstate 'PT403' using message = 'Chỉ tài xế phụ trách ca thu gom hoặc quản trị viên được cập nhật.';
      end if;
      if pk.status <> 'arrived' then
        raise sqlstate 'PT409' using message = 'Cần xác nhận đã tới kho trước khi nhận lô hàng.';
      end if;
      update public.delivery_cloud_pickups
        set status = 'picked_up',
            picked_up_at = coalesce(picked_up_at, now()),
            version = version + 1,
            updated_at = now()
        where id = pk.id
        returning * into pk;

    elsif v_act = 'complete' then
      if not op and (uid is distinct from pk.driver_id or not public.delivery_cloud_has_membership(uid, 'driver')) then
        raise sqlstate 'PT403' using message = 'Chỉ tài xế phụ trách ca thu gom hoặc quản trị viên được cập nhật.';
      end if;
      if pk.status <> 'picked_up' then
        raise sqlstate 'PT409' using message = 'Chỉ hoàn tất ca thu gom sau khi đã nhận lô hàng từ kho.';
      end if;
      update public.delivery_cloud_pickups
        set status = 'completed',
            completed_at = coalesce(completed_at, now()),
            version = version + 1,
            updated_at = now()
        where id = pk.id
        returning * into pk;

    elsif v_act = 'cancel' then
      if not op
         and uid <> pk.merchant_id
         and not (pk.shop_id is not null and public.delivery_market_can_access_shop(pk.shop_id, uid, 'manager')) then
        raise sqlstate 'PT403' using message = 'Chỉ người tạo phiếu, quản lý cửa hàng hoặc quản trị viên được hủy ca thu gom.';
      end if;
      if pk.status not in ('requested', 'assigned', 'arrived') then
        raise sqlstate 'PT409' using message = 'Ca thu gom đã nhận hàng hoặc đã kết thúc, không thể hủy.';
      end if;
      update public.delivery_cloud_pickups
        set status = 'cancelled',
            cancelled_at = now(),
            cancel_reason = v_reason,
            version = version + 1,
            updated_at = now()
        where id = pk.id
        returning * into pk;
    end if;

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
      where details->>'recipient_phone' = v_phone
        and (owner_id = uid or merchant_id = uid or public.delivery_can_access_cloud_order_as_shop_staff(id, uid));
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
      where o2.created_at >= v_since
        and (op or uid in (o2.owner_id, o2.merchant_id, o2.driver_id) or public.delivery_can_access_cloud_order_as_shop_staff(o2.id, uid))
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
    return jsonb_build_object(
      'scope', case when op then 'network' else 'account' end,
      'window_days', 30,
      'summary', v_result,
      'pickups', jsonb_build_object(
        'requested', (select count(*) from public.delivery_cloud_pickups p where p.status = 'requested' and (op or p.merchant_id = uid or (p.shop_id is not null and public.delivery_market_can_access_shop(p.shop_id, uid, 'staff')))),
        'assigned', (select count(*) from public.delivery_cloud_pickups p where p.status in ('assigned','arrived','picked_up') and (op or uid in (p.merchant_id, p.driver_id) or (p.shop_id is not null and public.delivery_market_can_access_shop(p.shop_id, uid, 'staff')))),
        'completed', (select count(*) from public.delivery_cloud_pickups p where p.status = 'completed' and (op or uid in (p.merchant_id, p.driver_id) or (p.shop_id is not null and public.delivery_market_can_access_shop(p.shop_id, uid, 'staff'))))
      ),
      'drivers', case when op then jsonb_build_object(
        'approved', (select count(*) from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id = m.user_id
          where m.role = 'driver' and m.state = 'active' and not a.blocked),
        'on_trip', (select count(distinct driver_id) from public.delivery_cloud_orders
          where driver_id is not null and status in ('accepted', 'arrivingPickup', 'inTransit', 'returning'))
      ) end
    );

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

-- ============================================================================
-- 8. PARTNER KYC ENFORCEMENT, ACTIVE-TRIP REVOKE/BLOCK GUARDS & OPERATOR NOTIFICATIONS
-- ============================================================================

create or replace function public.delivery_cloud_membership(
  p_role text,
  p_decision text,
  p_user uuid default null,
  p_version integer default null,
  p_reason text default ''
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  target uuid := coalesce(p_user, auth.uid());
  a public.delivery_cloud_accounts;
  previous public.delivery_cloud_memberships;
  changed public.delivery_cloud_memberships;
  next_state text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message = 'Cần đăng nhập.'; end if;
  if p_role is null or p_role not in ('merchant', 'driver') or p_decision is null or
     p_decision not in ('request', 'grant', 'approve', 'reject', 'revoke') or p_reason is null or length(p_reason) > 500 then
    raise sqlstate 'PT400' using message = 'Yêu cầu tư cách đối tác không hợp lệ.';
  end if;
  if p_decision = 'request' then
    if target <> auth.uid() then raise sqlstate 'PT403' using message = 'Chỉ được đăng ký cho chính mình.'; end if;
  elsif not public.delivery_is_operator() then
    raise sqlstate 'PT403' using message = 'Cần quyền quản trị.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('driver:' || target::text, 0));
  select * into a from public.delivery_cloud_accounts where user_id = target for update;
  if not found then raise sqlstate 'PT404' using message = 'Cần hoàn thiện hồ sơ trước.'; end if;
  if a.blocked then raise sqlstate 'PT403' using message = 'Tài khoản đang khóa.'; end if;

  select * into previous from public.delivery_cloud_memberships where user_id = target and role = p_role for update;

  if p_decision = 'request' then
    if previous.state in ('active', 'pending') then
      return jsonb_build_object('membership', to_jsonb(previous) - 'user_id' - 'reviewed_by');
    end if;
    if a.birth_date is null or a.citizen_id is null then
      raise sqlstate 'PT409' using message = 'Cần cập nhật ngày sinh và số CCCD 12 số trong Hồ sơ cá nhân trước khi đăng ký đối tác.';
    end if;
    insert into public.delivery_cloud_memberships(user_id, role, state)
      values(target, p_role, 'pending')
      on conflict(user_id, role) do update set
        state = 'pending',
        version = delivery_cloud_memberships.version + 1,
        requested_at = now(),
        reviewed_at = null,
        reviewed_by = null,
        reason = ''
      returning * into changed;

  elsif p_decision = 'grant' then
    if a.birth_date is null or a.citizen_id is null then
      raise sqlstate 'PT409' using message = 'Tài khoản chưa hoàn tất ngày sinh và CCCD định danh 12 số để cấp quyền đối tác.';
    end if;
    if previous.user_id is null then
      if coalesce(p_version, 0) <> 0 then
        raise sqlstate 'PT409' using message = 'Quyền đã thay đổi. Vui lòng tải lại.';
      end if;
      insert into public.delivery_cloud_memberships(user_id, role, state, version, reviewed_at, reviewed_by, reason)
        values(target, p_role, 'active', 1, now(), auth.uid(), btrim(p_reason))
        returning * into changed;
    else
      if p_version is distinct from previous.version then
        raise sqlstate 'PT409' using message = 'Quyền đã thay đổi. Vui lòng tải lại.';
      end if;
      if previous.state = 'active' then
        raise sqlstate 'PT409' using message = 'Tài khoản đã được cấp quyền đối tác này.';
      end if;
      update public.delivery_cloud_memberships
        set state = 'active', version = version + 1, reviewed_at = now(), reviewed_by = auth.uid(), reason = btrim(p_reason)
        where user_id = target and role = p_role
        returning * into changed;
    end if;
    if a.role = 'customer' then
      update public.delivery_cloud_accounts set role = p_role where user_id = target;
    end if;

  else
    if previous.user_id is null then raise sqlstate 'PT404' using message = 'Không tìm thấy yêu cầu đối tác.'; end if;
    if p_version is distinct from previous.version then raise sqlstate 'PT409' using message = 'Quyền đã thay đổi. Vui lòng tải lại.'; end if;
    if (p_decision in ('approve', 'reject') and previous.state <> 'pending')
       or (p_decision = 'revoke' and previous.state <> 'active') then
      raise sqlstate 'PT409' using message = 'Quyết định không phù hợp trạng thái hiện tại.';
    end if;
    if p_decision = 'approve' and (a.birth_date is null or a.citizen_id is null) then
      raise sqlstate 'PT409' using message = 'Tài khoản chưa hoàn tất ngày sinh và CCCD định danh 12 số để duyệt đối tác.';
    end if;
    if p_decision in ('reject', 'revoke') and length(btrim(p_reason)) < 3 then
      raise sqlstate 'PT400' using message = 'Cần lý do ít nhất 3 ký tự.';
    end if;

    if p_decision = 'revoke' and p_role = 'driver' and (
      exists(
        select 1 from public.delivery_cloud_orders
        where driver_id = target and status not in ('delivered', 'returned', 'cancelled')
      )
      or exists(
        select 1 from public.delivery_cloud_pickups
        where driver_id = target and status in ('assigned', 'arrived', 'picked_up')
      )
    ) then
      raise sqlstate 'PT409' using message = 'Tài xế còn chuyến giao hoặc ca thu gom chưa hoàn tất.';
    end if;

    if p_decision = 'revoke' and p_role = 'merchant' and (
      exists(
        select 1
        from public.delivery_market_shop_orders o
        where o.merchant_id = target
          and o.state <> 'cancelled'
          and (
            (o.delivery_id is null and not exists(select 1 from public.delivery_market_shipments ms where ms.order_id = o.id))
            or exists(
              select 1 from public.delivery_cloud_orders d
              where d.id = o.delivery_id and d.status not in ('delivered', 'returned', 'cancelled')
            )
            or exists(
              select 1 from public.delivery_market_shipments ms
              join public.delivery_cloud_orders d2 on d2.id = ms.delivery_id
              where ms.order_id = o.id and d2.status not in ('delivered', 'returned', 'cancelled')
            )
          )
      )
      or exists(
        select 1
        from public.delivery_market_returns r
        join public.delivery_market_shop_orders o on o.id = r.order_id
        join public.delivery_cloud_orders rd on rd.id = r.return_delivery_id
        where o.merchant_id = target
          and rd.status not in ('delivered', 'returned', 'cancelled')
      )
    ) then
      raise sqlstate 'PT409' using message = 'Cửa hàng còn đơn hoặc kiện hoàn trả chưa hoàn tất.';
    end if;

    next_state := case p_decision when 'approve' then 'active' when 'reject' then 'rejected' else 'revoked' end;
    update public.delivery_cloud_memberships
      set state = next_state, version = version + 1, reviewed_at = now(), reviewed_by = auth.uid(), reason = btrim(p_reason)
      where user_id = target and role = p_role
      returning * into changed;
    if p_decision = 'approve' and a.role = 'customer' then
      update public.delivery_cloud_accounts set role = p_role where user_id = target;
    elsif p_decision = 'revoke' and a.role = p_role then
      update public.delivery_cloud_accounts
        set role = coalesce((
          select role from public.delivery_cloud_memberships
          where user_id = target and state = 'active' order by role limit 1
        ), 'customer')
        where user_id = target;
    end if;
  end if;

  update public.delivery_cloud_accounts
    set requested_role = (
      select role from public.delivery_cloud_memberships
      where user_id = target and state = 'pending' order by role limit 1
    ), updated_at = now()
    where user_id = target;
  insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, before_value, after_value)
    values(auth.uid(), 'membership_' || p_decision, target, to_jsonb(previous), to_jsonb(changed));
  return jsonb_build_object('membership', to_jsonb(changed) - 'user_id' - 'reviewed_by');
end; $$;

revoke all on function public.delivery_cloud_membership(text, text, uuid, integer, text) from public, anon;
grant execute on function public.delivery_cloud_membership(text, text, uuid, integer, text) to authenticated;

create or replace function public.delivery_cloud_accounts_manage(
  p_user uuid default null,
  p_role text default null,
  p_blocked boolean default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  previous public.delivery_cloud_accounts;
  changed public.delivery_cloud_accounts;
begin
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message = 'Cần quyền quản trị.'; end if;
  if p_user is not null then
    if p_role is null or p_role not in ('customer', 'merchant', 'driver') or p_blocked is null then
      raise sqlstate 'PT400' using message = 'Quyền không hợp lệ.';
    end if;
    if p_user = auth.uid() and p_blocked then
      raise sqlstate 'PT409' using message = 'Không thể tự khóa tài khoản quản trị đang đăng nhập.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:' || p_user::text, 0));
    select * into previous from public.delivery_cloud_accounts where user_id = p_user for update;
    if not found then raise sqlstate 'PT404' using message = 'Không tìm thấy tài khoản.'; end if;

    if p_blocked and exists (
      select 1 from public.delivery_cloud_orders
      where driver_id = p_user and status in ('accepted', 'arrivingPickup', 'inTransit', 'returning')
    ) then
      raise sqlstate 'PT409' using message = 'Tài xế đang có chuyến giao chưa hoàn tất. Hãy điều phối lại hoặc hoàn tất chuyến trước khi khóa tài khoản.';
    end if;

    if p_role in ('merchant', 'driver') and p_role <> previous.role then
      if not exists (
        select 1 from public.delivery_cloud_memberships
        where user_id = p_user and role = p_role and state = 'active'
      ) and (previous.birth_date is null or previous.citizen_id is null) then
        raise sqlstate 'PT409' using message = 'Tài khoản chưa hoàn tất ngày sinh và CCCD định danh 12 số để cấp quyền đối tác.';
      end if;
      insert into public.delivery_cloud_memberships(user_id, role, state, reviewed_at, reviewed_by)
        values(p_user, p_role, 'active', now(), auth.uid())
        on conflict(user_id, role) do update set
          state = 'active',
          version = delivery_cloud_memberships.version + 1,
          reviewed_at = now(),
          reviewed_by = auth.uid(),
          reason = ''
        where delivery_cloud_memberships.state <> 'active';
    end if;

    update public.delivery_cloud_accounts
      set role = p_role,
          blocked = p_blocked,
          requested_role = (
            select role from public.delivery_cloud_memberships
            where user_id = p_user and state = 'pending' order by role limit 1
          ),
          updated_at = now()
      where user_id = p_user
      returning * into changed;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, before_value, after_value)
      values(auth.uid(), 'account_role', p_user, to_jsonb(previous), to_jsonb(changed));

    if p_blocked is distinct from previous.blocked and p_user <> auth.uid() then
      perform public.delivery_emit_notification(
        p_user,
        'account',
        case when p_blocked then 'account_blocked' else 'account_unblocked' end,
        case when p_blocked then 'Tài khoản tạm khóa' else 'Tài khoản đã mở khóa' end,
        case when p_blocked then 'Tài khoản của bạn tạm khóa theo quyết định vận hành.'
             else 'Tài khoản của bạn đã được khôi phục trạng thái hoạt động.' end,
        'account',
        p_user,
        '{}'::jsonb
      );
    end if;
  end if;

  return jsonb_build_object(
    'accounts',
    coalesce((
      select jsonb_agg(public.delivery_cloud_account_snapshot(a.user_id) order by a.updated_at desc, a.user_id desc)
      from (select user_id, updated_at from public.delivery_cloud_accounts order by updated_at desc, user_id desc limit 200) a
    ), '[]'::jsonb)
  );
end; $$;

revoke all on function public.delivery_cloud_accounts_manage(uuid, text, boolean) from public, anon;
grant execute on function public.delivery_cloud_accounts_manage(uuid, text, boolean) to authenticated;

create or replace function public.delivery_cloud_admin_accounts(p_action text, p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  uid uuid := auth.uid();
  v_target uuid;
  v_name text;
  v_phone text;
  v_reason text;
  v_birth date;
  v_citizen text;
  v_blocked boolean;
  v_operator boolean;
  prev_acc public.delivery_cloud_accounts;
  next_acc public.delivery_cloud_accounts;
  prev_op text;
  next_op text;
  local_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if uid is null then raise sqlstate 'PT401' using message = 'Cần đăng nhập.'; end if;
  if not public.delivery_is_operator() then raise sqlstate 'PT403' using message = 'Cần quyền quản trị.'; end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 4000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu quản trị tài khoản không hợp lệ.';
  end if;

  if p_action = 'list' then
    if d <> '{}'::jsonb then raise sqlstate 'PT400' using message = 'Tham số danh sách tài khoản không hợp lệ.'; end if;
    return jsonb_build_object(
      'accounts', coalesce((
        select jsonb_agg(public.delivery_cloud_admin_account_row(q.id) order by q.sort_ts desc nulls last, q.id desc)
        from (
          select u.id, coalesce(a.updated_at, (nullif(to_jsonb(u)->>'created_at', ''))::timestamptz) as sort_ts
          from auth.users u
          left join public.delivery_cloud_accounts a on a.user_id = u.id
          order by sort_ts desc nulls last, u.id desc
          limit 200
        ) q
      ), '[]'::jsonb),
      'summary', jsonb_build_object(
        'total_accounts', (select count(*)::integer from auth.users),
        'completed_profiles', (select count(*)::integer from public.delivery_cloud_accounts),
        'identity_verified_accounts', (select count(*)::integer from public.delivery_cloud_accounts where birth_date is not null and citizen_id is not null),
        'incomplete_profiles', (select count(*)::integer from auth.users u where not exists(select 1 from public.delivery_cloud_accounts a where a.user_id = u.id)),
        'operators', (select count(*)::integer from public.delivery_api_profiles where role = 'operator'),
        'active_drivers', (select count(*)::integer from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id = m.user_id where m.role = 'driver' and m.state = 'active' and not a.blocked),
        'active_merchants', (select count(*)::integer from public.delivery_cloud_memberships m join public.delivery_cloud_accounts a on a.user_id = m.user_id where m.role = 'merchant' and m.state = 'active' and not a.blocked),
        'pending_memberships', (select count(*)::integer from public.delivery_cloud_memberships where state = 'pending'),
        'blocked_accounts', (select count(*)::integer from public.delivery_cloud_accounts where blocked)
      )
    );

  elsif p_action = 'detail' then
    if d - array['user_id'] <> '{}'::jsonb or jsonb_typeof(d->'user_id') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Mã tài khoản không hợp lệ.';
    end if;
    v_target := (d->>'user_id')::uuid;
    if not exists(select 1 from auth.users where id = v_target) then
      raise sqlstate 'PT404' using message = 'Không tìm thấy tài khoản.';
    end if;
    return jsonb_build_object(
      'account', public.delivery_cloud_admin_account_row(v_target),
      'shops', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', s.id, 'name', s.name, 'status', s.status, 'paused', s.paused, 'address', s.address, 'updated_at', s.updated_at
        ) order by s.updated_at desc, s.id desc)
        from public.delivery_market_shops s where s.owner_id = v_target
      ), '[]'::jsonb),
      'audit', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', au.id, 'action', au.action, 'actor_id', au.actor_id,
          'actor_email', coalesce(to_jsonb(actor_u)->>'email', ''),
          'before_value', au.before_value, 'after_value', au.after_value, 'created_at', au.created_at
        ) order by au.created_at desc, au.id desc)
        from (select * from public.delivery_cloud_admin_audit where target_id = v_target order by created_at desc, id desc limit 25) au
        left join auth.users actor_u on actor_u.id = au.actor_id
      ), '[]'::jsonb)
    );

  elsif p_action = 'update_profile' then
    if d - array['user_id', 'full_name', 'phone', 'birth_date', 'citizen_id', 'reason'] <> '{}'::jsonb or
       jsonb_typeof(d->'user_id') is distinct from 'string' or
       jsonb_typeof(d->'full_name') is distinct from 'string' or
       jsonb_typeof(d->'phone') is distinct from 'string' or
       (d ? 'reason' and jsonb_typeof(d->'reason') is distinct from 'string') then
      raise sqlstate 'PT400' using message = 'Thông tin cập nhật hồ sơ không hợp lệ.';
    end if;
    v_target := (d->>'user_id')::uuid;
    v_name := btrim(d->>'full_name');
    v_phone := btrim(d->>'phone');
    v_reason := btrim(coalesce(d->>'reason', ''));
    if length(v_name) not between 1 and 120 or v_phone !~ '^0[35789][0-9]{8}$' or length(v_reason) > 500 then
      raise sqlstate 'PT400' using message = 'Họ tên 1–120 ký tự hoặc số điện thoại Việt Nam 10 số không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:' || v_target::text, 0));
    if not exists(select 1 from auth.users where id = v_target) then
      raise sqlstate 'PT404' using message = 'Không tìm thấy tài khoản xác thực.';
    end if;
    select * into prev_acc from public.delivery_cloud_accounts where user_id = v_target for update;

    v_birth := prev_acc.birth_date;
    if d ? 'birth_date' then
      if d->'birth_date' is null or jsonb_typeof(d->'birth_date') = 'null'
         or btrim(coalesce(d->>'birth_date', '')) = '' then
        v_birth := null;
      else
        if jsonb_typeof(d->'birth_date') <> 'string'
           or btrim(d->>'birth_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise sqlstate 'PT400' using message = 'Ngày tháng năm sinh không hợp lệ.';
        end if;
        begin
          v_birth := btrim(d->>'birth_date')::date;
        exception when others then
          raise sqlstate 'PT400' using message = 'Ngày tháng năm sinh không hợp lệ.';
        end;
        if v_birth < date '1900-01-01' or v_birth > local_today then
          raise sqlstate 'PT400' using message = 'Ngày tháng năm sinh cần nằm trong khoảng hợp lệ.';
        end if;
      end if;
    end if;

    v_citizen := prev_acc.citizen_id;
    if d ? 'citizen_id' then
      if d->'citizen_id' is null or jsonb_typeof(d->'citizen_id') = 'null'
         or btrim(coalesce(d->>'citizen_id', '')) = '' then
        v_citizen := null;
      else
        if jsonb_typeof(d->'citizen_id') <> 'string'
           or btrim(d->>'citizen_id') !~ '^[0-9]{12}$' then
          raise sqlstate 'PT400' using message = 'Số CCCD định danh phải gồm đúng 12 chữ số.';
        end if;
        v_citizen := btrim(d->>'citizen_id');
        if exists (
          select 1 from public.delivery_cloud_accounts
          where citizen_id = v_citizen and user_id <> v_target
        ) then
          raise sqlstate 'PT409' using message = 'Số CCCD định danh đã được liên kết với tài khoản khác.';
        end if;
      end if;
    end if;

    insert into public.delivery_cloud_accounts(user_id, full_name, phone, birth_date, citizen_id)
      values(v_target, v_name, v_phone, v_birth, v_citizen)
      on conflict(user_id) do update set
        full_name = excluded.full_name,
        phone = excluded.phone,
        birth_date = excluded.birth_date,
        citizen_id = excluded.citizen_id,
        updated_at = now()
      returning * into next_acc;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, before_value, after_value)
      values(uid, 'account_profile', v_target, to_jsonb(prev_acc), to_jsonb(next_acc) || jsonb_build_object('reason', v_reason));
    return jsonb_build_object('account', public.delivery_cloud_admin_account_row(v_target));

  elsif p_action = 'set_blocked' then
    if d - array['user_id', 'blocked', 'reason'] <> '{}'::jsonb or
       jsonb_typeof(d->'user_id') is distinct from 'string' or
       jsonb_typeof(d->'blocked') is distinct from 'boolean' or
       (d ? 'reason' and jsonb_typeof(d->'reason') is distinct from 'string') then
      raise sqlstate 'PT400' using message = 'Yêu cầu khóa hoặc mở khóa tài khoản không hợp lệ.';
    end if;
    v_target := (d->>'user_id')::uuid;
    v_blocked := (d->>'blocked')::boolean;
    v_reason := btrim(coalesce(d->>'reason', ''));
    if length(v_reason) > 500 then raise sqlstate 'PT400' using message = 'Ghi chú lý do tối đa 500 ký tự.'; end if;
    if v_target = uid and v_blocked then
      raise sqlstate 'PT409' using message = 'Không thể tự khóa tài khoản quản trị đang đăng nhập.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:' || v_target::text, 0));
    select * into prev_acc from public.delivery_cloud_accounts where user_id = v_target for update;
    if not found then
      raise sqlstate 'PT404' using message = 'Tài khoản chưa hoàn tất hồ sơ. Hãy cập nhật họ tên và SĐT trước.';
    end if;
    if v_blocked and exists (
      select 1 from public.delivery_cloud_orders
      where driver_id = v_target and status in ('accepted', 'arrivingPickup', 'inTransit', 'returning')
    ) then
      raise sqlstate 'PT409' using message = 'Tài xế đang có chuyến giao chưa hoàn tất. Hãy điều phối lại hoặc hoàn tất chuyến trước khi khóa tài khoản.';
    end if;
    update public.delivery_cloud_accounts set blocked = v_blocked, updated_at = now() where user_id = v_target returning * into next_acc;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, before_value, after_value)
      values(uid, case when v_blocked then 'account_block' else 'account_unblock' end, v_target,
        to_jsonb(prev_acc), to_jsonb(next_acc) || jsonb_build_object('reason', v_reason));
    perform public.delivery_emit_notification(
      v_target, 'account', case when v_blocked then 'account_blocked' else 'account_unblocked' end,
      case when v_blocked then 'Tài khoản tạm khóa' else 'Tài khoản đã mở khóa' end,
      case when v_blocked then 'Tài khoản của bạn tạm khóa: ' || coalesce(nullif(v_reason, ''), 'Liên hệ quản trị viên để được hỗ trợ.')
           else 'Tài khoản của bạn đã được khôi phục trạng thái hoạt động.' end,
      'account', v_target, '{}'::jsonb
    );
    return jsonb_build_object('account', public.delivery_cloud_admin_account_row(v_target));

  elsif p_action = 'set_operator' then
    if d - array['user_id', 'operator', 'reason'] <> '{}'::jsonb or
       jsonb_typeof(d->'user_id') is distinct from 'string' or
       jsonb_typeof(d->'operator') is distinct from 'boolean' or
       jsonb_typeof(d->'reason') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Yêu cầu phân quyền Operator không hợp lệ.';
    end if;
    v_target := (d->>'user_id')::uuid;
    v_operator := (d->>'operator')::boolean;
    v_reason := btrim(d->>'reason');
    if length(v_reason) not between 3 and 500 then
      raise sqlstate 'PT400' using message = 'Cần nhập lý do phân quyền Operator ít nhất 3 ký tự.';
    end if;
    if v_target = uid and not v_operator then
      raise sqlstate 'PT409' using message = 'Không thể tự thu hồi quyền Operator của tài khoản đang đăng nhập.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:' || v_target::text, 0));
    if not exists(select 1 from auth.users where id = v_target) then
      raise sqlstate 'PT404' using message = 'Không tìm thấy tài khoản xác thực.';
    end if;
    if v_operator and exists(select 1 from public.delivery_cloud_accounts where user_id = v_target and blocked) then
      raise sqlstate 'PT409' using message = 'Không thể cấp quyền Operator cho tài khoản đang bị khóa.';
    end if;
    select role into prev_op from public.delivery_api_profiles where user_id = v_target for update;
    next_op := case when v_operator then 'operator' else 'user' end;
    insert into public.delivery_api_profiles(user_id, role)
      values(v_target, next_op)
      on conflict(user_id) do update set role = excluded.role;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, before_value, after_value)
      values(uid, case when v_operator then 'operator_grant' else 'operator_revoke' end, v_target,
        jsonb_build_object('role', coalesce(prev_op, 'user')),
        jsonb_build_object('role', next_op, 'reason', v_reason));
    if coalesce(prev_op, 'user') is distinct from next_op and v_target <> uid then
      perform public.delivery_emit_notification(
        v_target,
        'account',
        case when v_operator then 'operator_granted' else 'operator_revoked' end,
        case when v_operator then 'Đã cấp quyền Điều hành viên' else 'Đã thu hồi quyền Điều hành viên' end,
        'Lý do cập nhật phân quyền: ' || left(v_reason, 220),
        'account',
        v_target,
        jsonb_build_object('operator', v_operator)
      );
    end if;
    return jsonb_build_object('account', public.delivery_cloud_admin_account_row(v_target));
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác quản trị tài khoản không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_admin_accounts(text, jsonb) from public, anon;
grant execute on function public.delivery_cloud_admin_accounts(text, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
