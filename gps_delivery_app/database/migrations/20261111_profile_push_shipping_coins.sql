-- Additive Cloud Profile Identity (birth_date & 12-digit citizen_id),
-- Unified In-App & Push Notification Inbox, and Shipping Fee Coin Redemption/Accrual.
-- Safe to reapply; seeds zero demo users, shops, orders, vouchers, or balances.
begin;

-- 1. Cloud Personal Profile Identity: birth_date & citizen_id (12-digit CCCD)
alter table public.delivery_cloud_accounts
  add column if not exists birth_date date;
alter table public.delivery_cloud_accounts
  add column if not exists citizen_id text;

alter table public.delivery_cloud_accounts
  drop constraint if exists delivery_cloud_accounts_birth_date_check;
alter table public.delivery_cloud_accounts
  add constraint delivery_cloud_accounts_birth_date_check
  check (birth_date is null or (birth_date >= date '1900-01-01' and birth_date <= date '2100-12-31'));

alter table public.delivery_cloud_accounts
  drop constraint if exists delivery_cloud_accounts_citizen_id_check;
alter table public.delivery_cloud_accounts
  add constraint delivery_cloud_accounts_citizen_id_check
  check (citizen_id is null or citizen_id ~ '^[0-9]{12}$');

create unique index if not exists delivery_cloud_accounts_citizen_id_key
  on public.delivery_cloud_accounts(citizen_id)
  where citizen_id is not null;

-- 2. Unified Notification Inbox & Per-User Notification Preferences
create table if not exists public.delivery_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  shipping_updates boolean not null default true,
  market_updates boolean not null default true,
  promo_updates boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('shipping','market','account','promo','system')),
  kind text not null check (length(kind) between 1 and 60),
  title text not null check (length(title) between 1 and 160),
  body text not null check (length(body) between 1 and 500),
  reference_type text check (reference_type is null or reference_type in (
    'cloud_order','market_order','pickup','membership','promo','account'
  )),
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists delivery_user_notifications_inbox
  on public.delivery_user_notifications(user_id, created_at desc, id desc);
create index if not exists delivery_user_notifications_unread
  on public.delivery_user_notifications(user_id, created_at desc)
  where read_at is null;
create unique index if not exists delivery_user_notifications_market_mirror
  on public.delivery_user_notifications(((metadata->>'market_notification_id')::uuid))
  where metadata ? 'market_notification_id';

do $$ declare t text; begin
  foreach t in array array[
    'delivery_notification_preferences','delivery_user_notifications'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- 3. Shipping Order Coin Redemption & Accrual Columns + Coin Ledger Kinds
alter table public.delivery_market_coin_ledger
  drop constraint if exists delivery_market_coin_ledger_kind_check;
alter table public.delivery_market_coin_ledger
  add constraint delivery_market_coin_ledger_kind_check
  check (kind in (
    'earn_settlement','redeem_checkout','release_cancel','reverse_refund',
    'promo_checkin','promo_spin','promo_blind_box','promo_mission','promo_exchange',
    'redeem_shipping','release_shipping_cancel','earn_shipping'
  ));

alter table public.delivery_cloud_orders
  add column if not exists coin_discount integer not null default 0;
alter table public.delivery_cloud_orders
  add column if not exists payable_fee integer;

update public.delivery_cloud_orders
  set payable_fee = greatest(0, shipping_fee - coalesce(coin_discount, 0))
  where payable_fee is null;

alter table public.delivery_cloud_orders
  alter column payable_fee set not null;

alter table public.delivery_cloud_orders
  drop constraint if exists delivery_cloud_orders_coin_fee_check;
alter table public.delivery_cloud_orders
  add constraint delivery_cloud_orders_coin_fee_check
  check (
    coin_discount >= 0
    and coin_discount <= shipping_fee
    and payable_fee = shipping_fee - coin_discount
  );

create or replace function public.delivery_cloud_orders_fee_sync() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  new.coin_discount := greatest(0, coalesce(new.coin_discount, 0));
  if new.coin_discount > new.shipping_fee then
    new.coin_discount := new.shipping_fee;
  end if;
  new.payable_fee := greatest(0, new.shipping_fee - new.coin_discount);
  return new;
end; $$;
revoke all on function public.delivery_cloud_orders_fee_sync() from public, anon, authenticated;

drop trigger if exists a_delivery_cloud_orders_fee_sync on public.delivery_cloud_orders;
create trigger a_delivery_cloud_orders_fee_sync
  before insert or update of shipping_fee, coin_discount, payable_fee
  on public.delivery_cloud_orders
  for each row execute function public.delivery_cloud_orders_fee_sync();

-- 4. Private Notification Helper & Domain Event Triggers
create or replace function public.delivery_emit_notification(
  p_user uuid,
  p_category text,
  p_kind text,
  p_title text,
  p_body text,
  p_ref_type text default null,
  p_ref_id uuid default null,
  p_meta jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  pref public.delivery_notification_preferences;
  nid uuid;
begin
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    return null;
  end if;
  select * into pref from public.delivery_notification_preferences where user_id = p_user;
  if found then
    if p_category = 'shipping' and not pref.shipping_updates then return null; end if;
    if p_category = 'market' and not pref.market_updates then return null; end if;
    if p_category = 'promo' and not pref.promo_updates then return null; end if;
  end if;
  insert into public.delivery_user_notifications(
    user_id, category, kind, title, body, reference_type, reference_id, metadata
  ) values (
    p_user,
    p_category,
    left(btrim(coalesce(p_kind, 'notice')), 60),
    left(btrim(coalesce(p_title, 'Thông báo mới')), 160),
    left(btrim(coalesce(p_body, 'Bạn có cập nhật mới trên hệ thống.')), 500),
    p_ref_type,
    p_ref_id,
    coalesce(p_meta, '{}'::jsonb)
  ) returning id into nid;
  return nid;
end; $$;
revoke all on function public.delivery_emit_notification(uuid,text,text,text,text,text,uuid,jsonb)
  from public, anon, authenticated;

-- Standalone Shipping Order Coin Settlement + Order Status Notifications
create or replace function public.delivery_cloud_orders_after_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  is_market_linked boolean := false;
  v_earn bigint := 0;
  v_title text;
  v_body text;
  v_meta jsonb;
  rcp uuid;
begin
  is_market_linked := exists (
    select 1 from public.delivery_market_shop_orders where delivery_id = new.id
  ) or exists (
    select 1 from public.delivery_market_shipments where delivery_id = new.id
  );

  v_meta := jsonb_build_object(
    'tracking_code', new.tracking_code,
    'status', new.status,
    'shipping_fee', new.shipping_fee,
    'coin_discount', new.coin_discount,
    'payable_fee', new.payable_fee
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

  -- Refund redeemed shipping coins on standalone order cancel / return
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

  -- Accrue 1% Xu on standalone delivered shipping orders
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

  -- Merchant ready notification to sender
  if new.merchant_ready and not old.merchant_ready and new.owner_id is distinct from actor then
    perform public.delivery_emit_notification(
      new.owner_id, 'shipping', 'merchant_ready',
      'Cửa hàng đã sẵn sàng giao kiện',
      'Vận đơn ' || new.tracking_code || ' đã sẵn sàng và đang tìm tài xế nhận chuyến.',
      'cloud_order', new.id, v_meta
    );
  end if;

  if new.status is distinct from old.status then
    case new.status
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
        from unnest(array[new.owner_id, new.merchant_id, case when new.status = 'cancelled' then old.driver_id else null end]) as u_id
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

drop trigger if exists z_delivery_cloud_orders_after_change on public.delivery_cloud_orders;
create trigger z_delivery_cloud_orders_after_change
  after insert or update on public.delivery_cloud_orders
  for each row execute function public.delivery_cloud_orders_after_change();

-- Mirror Marketplace Notifications into Unified Inbox & Sync Read Status
create or replace function public.delivery_market_notifications_mirror() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  so public.delivery_market_shop_orders;
  v_shop text;
  v_title text;
  v_body text;
begin
  if tg_op = 'UPDATE' then
    if new.read_at is not null and old.read_at is null then
      update public.delivery_user_notifications
        set read_at = coalesce(read_at, new.read_at)
        where user_id = new.user_id
          and metadata ? 'market_notification_id'
          and (metadata->>'market_notification_id')::uuid = new.id;
    end if;
    return new;
  end if;

  select * into so from public.delivery_market_shop_orders where id = new.order_id;
  v_shop := coalesce(nullif(btrim(so.snapshot->>'shop_name'), ''), 'cửa hàng');

  case new.kind
    when 'new_order' then
      v_title := 'Đơn mua hàng mới tại ' || v_shop;
      v_body := 'Khách hàng vừa đặt đơn mới tại ' || v_shop || '. Vui lòng xác nhận đúng hạn.';
    when 'accept' then
      v_title := v_shop || ' đã nhận đơn';
      v_body := 'Cửa hàng đang chuẩn bị món cho đơn mua hàng của bạn.';
    when 'ready' then
      v_title := 'Đơn hàng từ ' || v_shop || ' sẵn sàng giao';
      v_body := 'Cửa hàng đã đóng gói xong và chuyển sang điều phối tài xế.';
    when 'cancel' then
      v_title := 'Đơn mua tại ' || v_shop || ' đã hủy';
      v_body := 'Đơn hàng tại ' || v_shop || ' đã hủy và hoàn lại hạn mức khuyến mãi nếu có.';
    when 'acceptance_expired' then
      v_title := 'Đơn tại ' || v_shop || ' quá hạn xác nhận';
      v_body := 'Đơn hàng tự động hủy do quá thời gian xác nhận của cửa hàng.';
    when 'message' then
      v_title := 'Tin nhắn mới trong đơn ' || v_shop;
      v_body := 'Bạn có tin nhắn trao đổi mới liên quan đến đơn mua tại ' || v_shop || '.';
    when 'return_requested' then
      v_title := 'Yêu cầu trả hàng mới tại ' || v_shop;
      v_body := 'Khách hàng vừa gửi yêu cầu đổi trả cần cửa hàng phản hồi.';
    when 'shop_reviewed' then
      v_title := 'Đánh giá mới cho ' || v_shop;
      v_body := 'Khách hàng vừa gửi đánh giá chất lượng dịch vụ của ' || v_shop || '.';
    when 'review_replied' then
      v_title := v_shop || ' đã phản hồi đánh giá';
      v_body := 'Cửa hàng vừa trả lời nhận xét của bạn trên đơn mua hàng.';
    else
      v_title := 'Cập nhật đơn mua tại ' || v_shop;
      v_body := 'Đơn mua hàng của bạn tại ' || v_shop || ' vừa thay đổi trạng thái.';
  end case;

  insert into public.delivery_user_notifications(
    user_id, category, kind, title, body, reference_type, reference_id, metadata, read_at, created_at
  ) values (
    new.user_id,
    'market',
    new.kind,
    left(v_title, 160),
    left(v_body, 500),
    'market_order',
    new.order_id,
    jsonb_build_object('market_notification_id', new.id, 'shop_name', v_shop),
    new.read_at,
    new.created_at
  ) on conflict do nothing;
  return new;
end; $$;
revoke all on function public.delivery_market_notifications_mirror() from public, anon, authenticated;

drop trigger if exists z_delivery_market_notifications_mirror on public.delivery_market_notifications;
create trigger z_delivery_market_notifications_mirror
  after insert or update of read_at on public.delivery_market_notifications
  for each row execute function public.delivery_market_notifications_mirror();

-- Backfill existing delivery_market_notifications safely without duplicates
insert into public.delivery_user_notifications(
  user_id, category, kind, title, body, reference_type, reference_id, metadata, read_at, created_at
)
select
  mn.user_id,
  'market',
  mn.kind,
  left('Cập nhật đơn mua tại ' || coalesce(nullif(btrim(so.snapshot->>'shop_name'), ''), 'cửa hàng'), 160),
  left(case mn.kind
    when 'new_order' then 'Có đơn đặt hàng mới cần cửa hàng xác nhận.'
    when 'accept' then 'Cửa hàng đã xác nhận và đang chuẩn bị đơn hàng.'
    when 'ready' then 'Đơn mua hàng đã sẵn sàng bàn giao vận chuyển.'
    when 'cancel' then 'Đơn mua hàng đã hủy.'
    when 'message' then 'Bạn có tin nhắn mới trong đơn mua hàng.'
    else 'Đơn mua hàng vừa cập nhật trạng thái.'
  end, 500),
  'market_order',
  mn.order_id,
  jsonb_build_object(
    'market_notification_id', mn.id,
    'shop_name', coalesce(nullif(btrim(so.snapshot->>'shop_name'), ''), 'cửa hàng')
  ),
  mn.read_at,
  mn.created_at
from public.delivery_market_notifications mn
left join public.delivery_market_shop_orders so on so.id = mn.order_id
where exists (select 1 from auth.users u where u.id = mn.user_id)
on conflict do nothing;

-- Bulk Pickup Assignment Notifications
create or replace function public.delivery_cloud_pickups_notify() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status = 'assigned' and old.status is distinct from 'assigned' then
    perform public.delivery_emit_notification(
      new.merchant_id, 'shipping', 'pickup_assigned',
      'Đã điều xe thu gom lô hàng',
      'Phiếu thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' đã được phân công tài xế.',
      'pickup', new.id,
      jsonb_build_object('pickup_date', new.pickup_date, 'time_slot', new.time_slot, 'package_count', new.package_count)
    );
    if new.driver_id is not null then
      perform public.delivery_emit_notification(
        new.driver_id, 'shipping', 'pickup_driver_assigned',
        'Phân công ca thu gom kho mới',
        'Bạn được điều phối thu gom ' || new.package_count || ' kiện ngày ' || new.pickup_date || ' tại ' || left(new.pickup_address, 120) || '.',
        'pickup', new.id,
        jsonb_build_object('pickup_date', new.pickup_date, 'time_slot', new.time_slot, 'package_count', new.package_count)
      );
    end if;
  end if;
  return new;
end; $$;
revoke all on function public.delivery_cloud_pickups_notify() from public, anon, authenticated;

drop trigger if exists z_delivery_cloud_pickups_notify on public.delivery_cloud_pickups;
create trigger z_delivery_cloud_pickups_notify
  after update of status on public.delivery_cloud_pickups
  for each row execute function public.delivery_cloud_pickups_notify();

-- Partner Membership Request & Review Notifications
create or replace function public.delivery_cloud_memberships_notify() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  role_label text := case when new.role = 'merchant' then 'Cửa hàng' else 'Tài xế' end;
  acc public.delivery_cloud_accounts;
  op_uid uuid;
begin
  select * into acc from public.delivery_cloud_accounts where user_id = new.user_id;
  if new.state = 'pending' and (tg_op = 'INSERT' or old.state is distinct from 'pending') then
    for op_uid in
      select user_id from public.delivery_api_profiles where role = 'operator' and user_id is distinct from new.user_id
    loop
      perform public.delivery_emit_notification(
        op_uid, 'account', 'membership_pending',
        'Hồ sơ đăng ký đối tác ' || role_label,
        coalesce(nullif(btrim(acc.full_name), ''), 'Người dùng') || ' vừa gửi yêu cầu xét duyệt vai trò ' || role_label || '.',
        'membership', new.user_id,
        jsonb_build_object('role', new.role, 'state', new.state, 'applicant_id', new.user_id)
      );
    end loop;
  elsif new.state in ('active', 'rejected', 'revoked')
        and (tg_op = 'INSERT' or old.state is distinct from new.state) then
    perform public.delivery_emit_notification(
      new.user_id,
      'account',
      'membership_' || new.state,
      case new.state
        when 'active' then 'Đã kích hoạt vai trò đối tác ' || role_label
        when 'rejected' then 'Yêu cầu đối tác ' || role_label || ' chưa được duyệt'
        else 'Tạm ngưng vai trò đối tác ' || role_label
      end,
      case new.state
        when 'active' then 'Tài khoản của bạn đã mở khóa không gian làm việc ' || role_label || ' trên hệ thống.'
        when 'rejected' then 'Yêu cầu đối tác ' || role_label || ' bị từ chối: ' || coalesce(nullif(btrim(new.reason), ''), 'Cần bổ sung thông tin định danh.')
        else 'Quyền đối tác ' || role_label || ' đã thu hồi: ' || coalesce(nullif(btrim(new.reason), ''), 'Theo quyết định vận hành.')
      end,
      'membership',
      new.user_id,
      jsonb_build_object('role', new.role, 'state', new.state)
    );
  end if;
  return new;
end; $$;
revoke all on function public.delivery_cloud_memberships_notify() from public, anon, authenticated;

drop trigger if exists z_delivery_cloud_memberships_notify on public.delivery_cloud_memberships;
create trigger z_delivery_cloud_memberships_notify
  after insert or update of state on public.delivery_cloud_memberships
  for each row execute function public.delivery_cloud_memberships_notify();

-- Promo Reward Claim Notifications
create or replace function public.delivery_promo_claims_notify() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform public.delivery_emit_notification(
    new.user_id,
    'promo',
    'promo_' || new.event_kind,
    new.title,
    new.summary,
    'promo',
    new.id,
    jsonb_build_object(
      'event_kind', new.event_kind,
      'rarity', new.rarity,
      'coins_delta', new.coins_delta,
      'voucher_code', new.voucher_code
    )
  );
  return new;
end; $$;
revoke all on function public.delivery_promo_claims_notify() from public, anon, authenticated;

drop trigger if exists z_delivery_promo_claims_notify on public.delivery_promo_reward_claims;
create trigger z_delivery_promo_claims_notify
  after insert on public.delivery_promo_reward_claims
  for each row execute function public.delivery_promo_claims_notify();

-- 5. Unified Notification Center RPC
create or replace function public.delivery_cloud_notifications(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  v_cat text;
  v_unread_only boolean := false;
  v_before timestamptz := null;
  v_before_id uuid := null;
  v_limit integer := 30;
  v_id uuid;
  v_marked integer := 0;
  v_rows jsonb := '[]'::jsonb;
  v_unread integer := 0;
  v_latest jsonb := null;
  pref public.delivery_notification_preferences;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Cần đăng nhập để xem thông báo.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 4000 then
    raise sqlstate 'PT400' using message = 'Yêu cầu thông báo không hợp lệ.';
  end if;

  select * into pref from public.delivery_notification_preferences where user_id = uid;
  if not found then
    pref.user_id := uid;
    pref.push_enabled := true;
    pref.shipping_updates := true;
    pref.market_updates := true;
    pref.promo_updates := true;
    pref.updated_at := now();
  end if;

  if p_action = 'unread_count' then
    if d <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Tham số đếm thông báo không hợp lệ.';
    end if;
    select count(*)::integer into v_unread
      from public.delivery_user_notifications
      where user_id = uid and read_at is null;
    select to_jsonb(n) - 'user_id' into v_latest
      from public.delivery_user_notifications n
      where n.user_id = uid and n.read_at is null
      order by n.created_at desc, n.id desc
      limit 1;
    return jsonb_build_object(
      'unread_count', v_unread,
      'latest', v_latest,
      'preferences', jsonb_build_object(
        'push_enabled', pref.push_enabled,
        'shipping_updates', pref.shipping_updates,
        'market_updates', pref.market_updates,
        'promo_updates', pref.promo_updates
      )
    );

  elsif p_action = 'list' then
    if d - array['category','unread_only','before','before_id','limit'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Bộ lọc thông báo không hợp lệ.';
    end if;
    v_cat := coalesce(nullif(btrim(d->>'category'), ''), 'all');
    if v_cat not in ('all','shipping','market','account','promo','system') then
      raise sqlstate 'PT400' using message = 'Danh mục thông báo không hợp lệ.';
    end if;
    if d ? 'unread_only' then
      if jsonb_typeof(d->'unread_only') <> 'boolean' then
        raise sqlstate 'PT400' using message = 'Cờ lọc chưa đọc không hợp lệ.';
      end if;
      v_unread_only := (d->>'unread_only')::boolean;
    end if;
    if d ? 'limit' then
      if jsonb_typeof(d->'limit') <> 'number'
         or (d->>'limit')::numeric <> trunc((d->>'limit')::numeric)
         or (d->>'limit')::integer not between 1 and 50 then
        raise sqlstate 'PT400' using message = 'Giới hạn trang thông báo không hợp lệ.';
      end if;
      v_limit := (d->>'limit')::integer;
    end if;
    if d ? 'before' and d->'before' is not null and jsonb_typeof(d->'before') <> 'null' then
      v_before := (d->>'before')::timestamptz;
    end if;
    if d ? 'before_id' and d->'before_id' is not null and jsonb_typeof(d->'before_id') <> 'null' then
      v_before_id := (d->>'before_id')::uuid;
    end if;

    select coalesce(jsonb_agg(to_jsonb(q) - 'user_id' order by q.created_at desc, q.id desc), '[]'::jsonb)
      into v_rows
      from (
        select *
        from public.delivery_user_notifications n
        where n.user_id = uid
          and (v_cat = 'all' or n.category = v_cat)
          and (not v_unread_only or n.read_at is null)
          and (
            v_before is null
            or (v_before_id is null and n.created_at < v_before)
            or (n.created_at, n.id) < (v_before, v_before_id)
          )
        order by n.created_at desc, n.id desc
        limit v_limit
      ) q;

    select count(*)::integer into v_unread
      from public.delivery_user_notifications
      where user_id = uid and read_at is null;

    return jsonb_build_object(
      'notifications', v_rows,
      'unread_count', v_unread,
      'preferences', jsonb_build_object(
        'push_enabled', pref.push_enabled,
        'shipping_updates', pref.shipping_updates,
        'market_updates', pref.market_updates,
        'promo_updates', pref.promo_updates
      ),
      'next', case
        when jsonb_array_length(v_rows) = v_limit then jsonb_build_object(
          'before', v_rows->(v_limit - 1)->>'created_at',
          'before_id', v_rows->(v_limit - 1)->>'id'
        )
        else null
      end
    );

  elsif p_action = 'mark_read' then
    if d - array['id'] <> '{}'::jsonb or jsonb_typeof(d->'id') is distinct from 'string' then
      raise sqlstate 'PT400' using message = 'Mã thông báo không hợp lệ.';
    end if;
    v_id := (d->>'id')::uuid;
    update public.delivery_user_notifications
      set read_at = coalesce(read_at, now())
      where id = v_id and user_id = uid;
    update public.delivery_market_notifications mn
      set read_at = coalesce(mn.read_at, now())
      from public.delivery_user_notifications un
      where un.id = v_id and un.user_id = uid
        and un.metadata ? 'market_notification_id'
        and mn.id = (un.metadata->>'market_notification_id')::uuid
        and mn.user_id = uid;
    select count(*)::integer into v_unread
      from public.delivery_user_notifications
      where user_id = uid and read_at is null;
    return jsonb_build_object('ok', true, 'unread_count', v_unread);

  elsif p_action = 'mark_all_read' then
    if d - array['category'] <> '{}'::jsonb then
      raise sqlstate 'PT400' using message = 'Tham số đánh dấu đã đọc không hợp lệ.';
    end if;
    v_cat := coalesce(nullif(btrim(d->>'category'), ''), 'all');
    if v_cat not in ('all','shipping','market','account','promo','system') then
      raise sqlstate 'PT400' using message = 'Danh mục thông báo không hợp lệ.';
    end if;
    with updated as (
      update public.delivery_user_notifications
        set read_at = now()
        where user_id = uid
          and read_at is null
          and (v_cat = 'all' or category = v_cat)
        returning id, metadata
    )
    select count(*)::integer into v_marked from updated;

    if v_cat in ('all', 'market') then
      update public.delivery_market_notifications
        set read_at = now()
        where user_id = uid and read_at is null;
    end if;

    select count(*)::integer into v_unread
      from public.delivery_user_notifications
      where user_id = uid and read_at is null;
    return jsonb_build_object('ok', true, 'marked', v_marked, 'unread_count', v_unread);

  elsif p_action = 'save_preferences' then
    if d - array['push_enabled','shipping_updates','market_updates','promo_updates'] <> '{}'::jsonb
       or (d ? 'push_enabled' and jsonb_typeof(d->'push_enabled') <> 'boolean')
       or (d ? 'shipping_updates' and jsonb_typeof(d->'shipping_updates') <> 'boolean')
       or (d ? 'market_updates' and jsonb_typeof(d->'market_updates') <> 'boolean')
       or (d ? 'promo_updates' and jsonb_typeof(d->'promo_updates') <> 'boolean') then
      raise sqlstate 'PT400' using message = 'Tùy chọn nhận thông báo không hợp lệ.';
    end if;
    insert into public.delivery_notification_preferences(
      user_id, push_enabled, shipping_updates, market_updates, promo_updates, updated_at
    ) values (
      uid,
      coalesce((d->>'push_enabled')::boolean, pref.push_enabled),
      coalesce((d->>'shipping_updates')::boolean, pref.shipping_updates),
      coalesce((d->>'market_updates')::boolean, pref.market_updates),
      coalesce((d->>'promo_updates')::boolean, pref.promo_updates),
      now()
    ) on conflict (user_id) do update set
      push_enabled = excluded.push_enabled,
      shipping_updates = excluded.shipping_updates,
      market_updates = excluded.market_updates,
      promo_updates = excluded.promo_updates,
      updated_at = now()
    returning * into pref;

    select count(*)::integer into v_unread
      from public.delivery_user_notifications
      where user_id = uid and read_at is null;
    return jsonb_build_object(
      'unread_count', v_unread,
      'preferences', jsonb_build_object(
        'push_enabled', pref.push_enabled,
        'shipping_updates', pref.shipping_updates,
        'market_updates', pref.market_updates,
        'promo_updates', pref.promo_updates
      )
    );
  end if;

  raise sqlstate 'PT400' using message = 'Thao tác thông báo không hỗ trợ.';
end; $$;

revoke all on function public.delivery_cloud_notifications(text,jsonb) from public, anon;
grant execute on function public.delivery_cloud_notifications(text,jsonb) to authenticated;

-- 6. Profile Snapshot, Self-Service Profile Update & Operator Account Governance
create or replace function public.delivery_cloud_account_snapshot(p_user uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(a)||jsonb_build_object(
    'identity_verified',(a.birth_date is not null and a.citizen_id is not null),
    'approved_roles',coalesce((select jsonb_agg(m.role order by m.role) from public.delivery_cloud_memberships m
      where m.user_id=a.user_id and m.state='active'),'[]'::jsonb),
    'memberships',coalesce((select jsonb_agg(to_jsonb(m)-'user_id'-'reviewed_by' order by m.role)
      from public.delivery_cloud_memberships m where m.user_id=a.user_id),'[]'::jsonb),
    'requested_role',(select m.role from public.delivery_cloud_memberships m where m.user_id=a.user_id and m.state='pending' order by m.role limit 1),
    'staff_shops',coalesce((select jsonb_agg(jsonb_build_object('shop_id',st.shop_id,'shop_name',s.name,'role',st.role) order by st.shop_id)
      from public.delivery_market_shop_staff st join public.delivery_market_shops s on s.id=st.shop_id
      join public.delivery_cloud_accounts oa on oa.user_id=s.owner_id
      where st.user_id=a.user_id and st.active and s.status<>'suspended' and not oa.blocked
        and public.delivery_cloud_has_membership(s.owner_id,'merchant')),'[]'::jsonb),
    'coin_balance',coalesce((select balance from public.delivery_market_coin_wallets w where w.user_id=a.user_id),0),
    'unread_notifications',(select count(*)::integer from public.delivery_user_notifications n where n.user_id=a.user_id and n.read_at is null))
  from public.delivery_cloud_accounts a where a.user_id=p_user;
$$;
revoke all on function public.delivery_cloud_account_snapshot(uuid) from public, anon, authenticated;

create or replace function public.delivery_cloud_profile(p_details jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  a public.delivery_cloud_accounts;
  requested text;
  v_birth date;
  v_citizen text;
  local_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if p_details is not null then
    if jsonb_typeof(p_details) is distinct from 'object' or
      p_details - array['full_name','phone','requested_role','birth_date','citizen_id'] <> '{}'::jsonb or
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

    v_birth := a.birth_date;
    if p_details ? 'birth_date' then
      if p_details->'birth_date' is null or jsonb_typeof(p_details->'birth_date') = 'null'
         or btrim(coalesce(p_details->>'birth_date','')) = '' then
        v_birth := null;
      else
        if jsonb_typeof(p_details->'birth_date') <> 'string'
           or btrim(p_details->>'birth_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise sqlstate 'PT400' using message='Ngày tháng năm sinh không hợp lệ.';
        end if;
        begin
          v_birth := btrim(p_details->>'birth_date')::date;
        exception when others then
          raise sqlstate 'PT400' using message='Ngày tháng năm sinh không hợp lệ.';
        end;
        if v_birth < date '1900-01-01' or v_birth > local_today then
          raise sqlstate 'PT400' using message='Ngày tháng năm sinh cần nằm trong khoảng hợp lệ.';
        end if;
      end if;
    end if;

    v_citizen := a.citizen_id;
    if p_details ? 'citizen_id' then
      if p_details->'citizen_id' is null or jsonb_typeof(p_details->'citizen_id') = 'null'
         or btrim(coalesce(p_details->>'citizen_id','')) = '' then
        v_citizen := null;
      else
        if jsonb_typeof(p_details->'citizen_id') <> 'string'
           or btrim(p_details->>'citizen_id') !~ '^[0-9]{12}$' then
          raise sqlstate 'PT400' using message='Số CCCD định danh phải gồm đúng 12 chữ số.';
        end if;
        v_citizen := btrim(p_details->>'citizen_id');
        if exists (
          select 1 from public.delivery_cloud_accounts
          where citizen_id = v_citizen and user_id <> auth.uid()
        ) then
          raise sqlstate 'PT409' using message='Số CCCD định danh đã được liên kết với tài khoản khác.';
        end if;
      end if;
    end if;

    insert into public.delivery_cloud_accounts(user_id, full_name, phone, birth_date, citizen_id)
      values(auth.uid(), btrim(p_details->>'full_name'), p_details->>'phone', v_birth, v_citizen)
      on conflict(user_id) do update
        set full_name = excluded.full_name,
            phone = excluded.phone,
            birth_date = excluded.birth_date,
            citizen_id = excluded.citizen_id,
            updated_at = now();

    requested := p_details->>'requested_role';
    if requested in ('merchant','driver') then
      perform public.delivery_cloud_membership(requested, 'request');
    end if;
  end if;

  return jsonb_build_object(
    'account', public.delivery_cloud_account_snapshot(auth.uid()),
    'operator', public.delivery_is_operator(),
    'user_id', auth.uid(),
    'schema_version', 3
  );
end; $$;

revoke all on function public.delivery_cloud_profile(jsonb) from public, anon;
grant execute on function public.delivery_cloud_profile(jsonb) to authenticated;

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
    'birth_date',a.birth_date,
    'citizen_id',a.citizen_id,
    'identity_verified',(a.birth_date is not null and a.citizen_id is not null),
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
revoke all on function public.delivery_cloud_admin_account_row(uuid) from public, anon, authenticated;

create or replace function public.delivery_cloud_admin_accounts(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb:=coalesce(p_payload,'{}'::jsonb);
  uid uuid:=auth.uid();
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
  local_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if uid is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
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
        'identity_verified_accounts',(select count(*)::integer from public.delivery_cloud_accounts where birth_date is not null and citizen_id is not null),
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
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản.';
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
    if d-array['user_id','full_name','phone','birth_date','citizen_id','reason']<>'{}'::jsonb or
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
      raise sqlstate 'PT400' using message='Họ tên 1–120 ký tự hoặc số điện thoại Việt Nam 10 số không hợp lệ.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('driver:'||v_target::text,0));
    if not exists(select 1 from auth.users where id=v_target) then
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản xác thực.';
    end if;
    select * into prev_acc from public.delivery_cloud_accounts where user_id=v_target for update;

    v_birth := prev_acc.birth_date;
    if d ? 'birth_date' then
      if d->'birth_date' is null or jsonb_typeof(d->'birth_date') = 'null'
         or btrim(coalesce(d->>'birth_date','')) = '' then
        v_birth := null;
      else
        if jsonb_typeof(d->'birth_date') <> 'string'
           or btrim(d->>'birth_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise sqlstate 'PT400' using message='Ngày tháng năm sinh không hợp lệ.';
        end if;
        begin
          v_birth := btrim(d->>'birth_date')::date;
        exception when others then
          raise sqlstate 'PT400' using message='Ngày tháng năm sinh không hợp lệ.';
        end;
        if v_birth < date '1900-01-01' or v_birth > local_today then
          raise sqlstate 'PT400' using message='Ngày tháng năm sinh cần nằm trong khoảng hợp lệ.';
        end if;
      end if;
    end if;

    v_citizen := prev_acc.citizen_id;
    if d ? 'citizen_id' then
      if d->'citizen_id' is null or jsonb_typeof(d->'citizen_id') = 'null'
         or btrim(coalesce(d->>'citizen_id','')) = '' then
        v_citizen := null;
      else
        if jsonb_typeof(d->'citizen_id') <> 'string'
           or btrim(d->>'citizen_id') !~ '^[0-9]{12}$' then
          raise sqlstate 'PT400' using message='Số CCCD định danh phải gồm đúng 12 chữ số.';
        end if;
        v_citizen := btrim(d->>'citizen_id');
        if exists (
          select 1 from public.delivery_cloud_accounts
          where citizen_id = v_citizen and user_id <> v_target
        ) then
          raise sqlstate 'PT409' using message='Số CCCD định danh đã được liên kết với tài khoản khác.';
        end if;
      end if;
    end if;

    insert into public.delivery_cloud_accounts(user_id,full_name,phone,birth_date,citizen_id)
      values(v_target,v_name,v_phone,v_birth,v_citizen)
      on conflict(user_id) do update set
        full_name=excluded.full_name,
        phone=excluded.phone,
        birth_date=excluded.birth_date,
        citizen_id=excluded.citizen_id,
        updated_at=now()
      returning * into next_acc;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(uid,'account_profile',v_target,to_jsonb(prev_acc),to_jsonb(next_acc)||jsonb_build_object('reason',v_reason));
    return jsonb_build_object('account',public.delivery_cloud_admin_account_row(v_target));

  elsif p_action='set_blocked' then
    if d-array['user_id','blocked','reason']<>'{}'::jsonb or
      jsonb_typeof(d->'user_id') is distinct from 'string' or
      jsonb_typeof(d->'blocked') is distinct from 'boolean' or
      (d ? 'reason' and jsonb_typeof(d->'reason') is distinct from 'string') then
      raise sqlstate 'PT400' using message='Yêu cầu khóa hoặc mở khóa tài khoản không hợp lệ.';
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
      raise sqlstate 'PT404' using message='Tài khoản chưa hoàn tất hồ sơ. Hãy cập nhật họ tên và SĐT trước.';
    end if;
    update public.delivery_cloud_accounts set blocked=v_blocked,updated_at=now() where user_id=v_target returning * into next_acc;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,before_value,after_value)
      values(uid,case when v_blocked then 'account_block' else 'account_unblock' end,v_target,
        to_jsonb(prev_acc),to_jsonb(next_acc)||jsonb_build_object('reason',v_reason));
    perform public.delivery_emit_notification(
      v_target, 'account', case when v_blocked then 'account_blocked' else 'account_unblocked' end,
      case when v_blocked then 'Tài khoản tạm khóa' else 'Tài khoản đã mở khóa' end,
      case when v_blocked then 'Tài khoản của bạn tạm khóa: ' || coalesce(nullif(v_reason,''), 'Liên hệ quản trị viên để được hỗ trợ.')
           else 'Tài khoản của bạn đã được khôi phục trạng thái hoạt động.' end,
      'account', v_target, '{}'::jsonb
    );
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
      raise sqlstate 'PT404' using message='Không tìm thấy tài khoản xác thực.';
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

revoke all on function public.delivery_cloud_admin_accounts(text,jsonb) from public, anon;
grant execute on function public.delivery_cloud_admin_accounts(text,jsonb) to authenticated;

-- 7. Shipping Quote & Order Creation with Server-Authoritative Coin Discount
create or replace function public.delivery_cloud_quote(p_details jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.delivery_cloud_pricing; a float8; leg_m integer; meters integer:=0; fee integer;
  weight numeric; vol_weight numeric:=0; eff_weight numeric; max_weight numeric;
  lat1 float8; lat2 float8; lng1 float8; lng2 float8; cur_lat float8; cur_lng float8;
  wp jsonb; wp_lat float8; wp_lng float8; stop_count integer:=0;
  l_cm numeric:=0; w_cm numeric:=0; h_cm numeric:=0;
  declared_val numeric:=0; is_round boolean:=false; prefer_ev boolean:=false; green_fund boolean:=false;
  use_coins boolean:=false; wallet_bal bigint:=0; max_coin_disc integer:=0; coin_disc integer:=0; payable integer:=0;
  service text; v_base integer; v_dist integer; v_weight integer; v_express integer:=0;
  v_stop integer:=0; v_round integer:=0; v_ins integer:=0; v_green integer:=0; v_per_km integer;
begin
  if not public.delivery_cloud_active() then raise sqlstate 'PT403' using message='Cần hoàn thiện hồ sơ và tài khoản đang hoạt động.'; end if;
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
  max_weight:=case when service='truck' then 500 else 30 end;
  if abs(lat1)>90 or abs(lat2)>90 or abs(lng1)>180 or abs(lng2)>180 or
    weight<=0 or weight>max_weight or service is null or service not in ('standard','express','saving','same_day_2h','truck') then
    raise sqlstate 'PT400' using message='Tọa độ, dịch vụ hoặc khối lượng không hợp lệ.';
  end if;
  if p_details ? 'length_cm' or p_details ? 'width_cm' or p_details ? 'height_cm' then
    if jsonb_typeof(coalesce(p_details->'length_cm','0'::jsonb))<>'number' or
       jsonb_typeof(coalesce(p_details->'width_cm','0'::jsonb))<>'number' or
       jsonb_typeof(coalesce(p_details->'height_cm','0'::jsonb))<>'number' then
      raise sqlstate 'PT400' using message='Kích thước kiện hàng không hợp lệ.';
    end if;
    l_cm:=coalesce((p_details->>'length_cm')::numeric,0);
    w_cm:=coalesce((p_details->>'width_cm')::numeric,0);
    h_cm:=coalesce((p_details->>'height_cm')::numeric,0);
    if l_cm<0 or w_cm<0 or h_cm<0 or l_cm>300 or w_cm>300 or h_cm>300 then
      raise sqlstate 'PT400' using message='Kích thước mỗi chiều tối đa 300 cm.';
    end if;
    if l_cm>0 and w_cm>0 and h_cm>0 then vol_weight:=round((l_cm*w_cm*h_cm)/5000.0,2); end if;
  end if;
  eff_weight:=greatest(weight,vol_weight);
  if eff_weight>max_weight then raise sqlstate 'PT400' using message='Khối lượng quy đổi vượt giới hạn dịch vụ.'; end if;

  cur_lat:=lat1; cur_lng:=lng1;
  if p_details ? 'extra_stops' then
    if jsonb_typeof(p_details->'extra_stops')<>'array' or jsonb_array_length(p_details->'extra_stops')>5 then
      raise sqlstate 'PT400' using message='Hỗ trợ tối đa 5 điểm dừng phụ.';
    end if;
    for wp in select * from jsonb_array_elements(p_details->'extra_stops') loop
      if jsonb_typeof(wp)<>'object' or jsonb_typeof(wp->'lat')<>'number' or jsonb_typeof(wp->'lng')<>'number' or
         length(btrim(coalesce(wp->>'address',''))) not between 3 and 300 then
        raise sqlstate 'PT400' using message='Điểm dừng phụ không hợp lệ.';
      end if;
      wp_lat:=(wp->>'lat')::float8; wp_lng:=(wp->>'lng')::float8;
      if abs(wp_lat)>90 or abs(wp_lng)>180 then raise sqlstate 'PT400' using message='Tọa độ điểm dừng không hợp lệ.'; end if;
      a:=power(sin(radians(wp_lat-cur_lat)/2),2)+cos(radians(cur_lat))*cos(radians(wp_lat))*power(sin(radians(wp_lng-cur_lng)/2),2);
      leg_m:=ceil(6371000*2*asin(sqrt(least(1,a)))*1.3)::integer;
      meters:=meters+leg_m; cur_lat:=wp_lat; cur_lng:=wp_lng; stop_count:=stop_count+1;
    end loop;
  end if;
  a:=power(sin(radians(lat2-cur_lat)/2),2)+cos(radians(cur_lat))*cos(radians(lat2))*power(sin(radians(lng2-cur_lng)/2),2);
  meters:=greatest(1,meters+ceil(6371000*2*asin(sqrt(least(1,a)))*1.3)::integer);
  if meters>200000 then raise sqlstate 'PT400' using message='Ngoài phạm vi giao hàng 200 km.'; end if;
  if service='same_day_2h' and meters>50000 then raise sqlstate 'PT400' using message='Giao nhanh 2H chỉ áp dụng trong bán kính 50 km nội thành.'; end if;

  if p_details ? 'declared_value' then
    if jsonb_typeof(p_details->'declared_value')<>'number' or (p_details->>'declared_value')::numeric not between 0 and 30000000 or
       (p_details->>'declared_value')::numeric<>trunc((p_details->>'declared_value')::numeric) then
      raise sqlstate 'PT400' using message='Giá trị khai giá tối đa 30.000.000 đ.';
    end if;
    declared_val:=(p_details->>'declared_value')::numeric;
  end if;
  if p_details ? 'is_round_trip' then
    if jsonb_typeof(p_details->'is_round_trip')<>'boolean' then raise sqlstate 'PT400' using message='Tùy chọn khứ hồi không hợp lệ.'; end if;
    is_round:=(p_details->>'is_round_trip')::boolean;
  end if;
  if p_details ? 'prefer_ev' then
    if jsonb_typeof(p_details->'prefer_ev')<>'boolean' then raise sqlstate 'PT400' using message='Tùy chọn xe điện không hợp lệ.'; end if;
    prefer_ev:=(p_details->>'prefer_ev')::boolean;
  end if;
  if p_details ? 'green_fund' then
    if jsonb_typeof(p_details->'green_fund')<>'boolean' then raise sqlstate 'PT400' using message='Tùy chọn quỹ xanh không hợp lệ.'; end if;
    green_fund:=(p_details->>'green_fund')::boolean;
  end if;
  if p_details ? 'use_coins' then
    if jsonb_typeof(p_details->'use_coins')<>'boolean' then raise sqlstate 'PT400' using message='Tùy chọn dùng Xu không hợp lệ.'; end if;
    use_coins:=(p_details->>'use_coins')::boolean;
  end if;
  if p_details ? 'scheduled_at' and p_details->'scheduled_at' is not null and jsonb_typeof(p_details->'scheduled_at')<>'null' then
    if jsonb_typeof(p_details->'scheduled_at')<>'string' or (p_details->>'scheduled_at')::timestamptz < now()+interval '10 minutes' or
       (p_details->>'scheduled_at')::timestamptz > now()+interval '7 days' then
      raise sqlstate 'PT400' using message='Lịch hẹn lấy hàng cần từ 10 phút tới 7 ngày.';
    end if;
  end if;

  select * into p from public.delivery_cloud_pricing where id;
  if service in ('standard','express') then
    v_base:=p.base_fee; v_per_km:=p.per_km;
    v_weight:=greatest(0,ceil(eff_weight-5))::integer*p.extra_kg;
    v_express:=case when service='express' then p.express_fee else 0 end;
  elsif service='saving' then
    v_base:=greatest(12000,round(p.base_fee*0.48)::integer);
    v_per_km:=greatest(4000,round(p.per_km*0.80)::integer);
    v_weight:=greatest(0,ceil(eff_weight-5))::integer*p.extra_kg;
  elsif service='same_day_2h' then
    v_base:=greatest(12000,round(p.base_fee*0.48)::integer);
    v_per_km:=greatest(5500,round(p.per_km*1.10)::integer);
    v_weight:=greatest(0,ceil(eff_weight-5))::integer*p.extra_kg;
  else
    v_base:=greatest(80000,p.base_fee*3+5000);
    v_per_km:=p.per_km*3;
    v_weight:=greatest(0,ceil(eff_weight-20))::integer*p.extra_kg;
  end if;
  v_dist:=greatest(0,ceil(meters/1000.0)-2)::integer*v_per_km;
  v_stop:=stop_count*5000;
  v_round:=case when is_round then round((v_base+v_dist)*0.60)::integer else 0 end;
  v_ins:=case when declared_val>0 then least(150000,greatest(2000,round(declared_val*0.005)::integer)) else 0 end;
  v_green:=case when green_fund then 1000 else 0 end;
  fee:=v_base+v_dist+v_weight+v_express+v_stop+v_round+v_ins+v_green;

  select coalesce(balance, 0) into wallet_bal
    from public.delivery_market_coin_wallets
    where user_id = auth.uid();
  max_coin_disc := least(wallet_bal, floor(fee * 0.20)::bigint, greatest(0, fee - 1000))::integer;
  coin_disc := case when use_coins then max_coin_disc else 0 end;
  payable := greatest(0, fee - coin_disc);

  return jsonb_build_object(
    'shipping_fee',fee,
    'coin_discount',coin_disc,
    'payable_fee',payable,
    'available_coins',wallet_bal,
    'max_coin_discount',max_coin_disc,
    'distance_meters',meters,
    'pricing_version',p.version,
    'distance_source','geodesic_estimate',
    'currency','VND',
    'service_type',service,
    'effective_weight_kg',eff_weight,
    'volumetric_weight_kg',vol_weight,
    'stop_count',stop_count,
    'estimated_co2_saved_grams',case when prefer_ev then round((meters/1000.0)*48.0)::integer else 0 end,
    'breakdown',jsonb_build_object(
      'base_fee',v_base,
      'distance_fee',v_dist,
      'weight_fee',v_weight,
      'express_fee',v_express
    ) || case when v_stop>0 then jsonb_build_object('stop_fee',v_stop) else '{}'::jsonb end
      || case when v_round>0 then jsonb_build_object('round_trip_fee',v_round) else '{}'::jsonb end
      || case when v_ins>0 then jsonb_build_object('insurance_fee',v_ins) else '{}'::jsonb end
      || case when v_green>0 then jsonb_build_object('green_fee',v_green) else '{}'::jsonb end
  );
end; $$;

revoke all on function public.delivery_cloud_quote(jsonb) from public, anon;
grant execute on function public.delivery_cloud_quote(jsonb) to authenticated;

create or replace function public.delivery_cloud_create(
  p_details jsonb,
  p_request_key uuid,
  p_pricing_version integer,
  p_expected_fee integer
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.delivery_cloud_orders; a public.delivery_cloud_accounts; q jsonb; merchant uuid; saved jsonb;
  raw_bytes bytea; otp_val text; v_coin_disc integer := 0; v_payable integer := 0;
begin
  if not public.delivery_cloud_active() then raise sqlstate 'PT403' using message='Cần hồ sơ đang hoạt động.'; end if;
  if p_request_key is null then raise sqlstate 'PT400' using message='Thiếu mã yêu cầu.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_key::text,0));
  saved:=jsonb_build_object('details',p_details,'pricing_version',p_pricing_version,'expected_fee',p_expected_fee);
  select * into o from public.delivery_cloud_orders where owner_id=auth.uid() and request_key=p_request_key;
  if found then
    if o.request_payload<>saved then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho nội dung khác.'; end if;
    return to_jsonb(o)-'request_payload'-'request_key';
  end if;
  select * into a from public.delivery_cloud_accounts where user_id=auth.uid();
  if octet_length(p_details::text)>12000 or p_details-array[
    'pickup_address','dropoff_address','recipient_name','recipient_phone','package_description',
    'pickup_lat','pickup_lng','dropoff_lat','dropoff_lng','weight_kg','cod_amount','service_type',
    'payment_method','merchant_id','length_cm','width_cm','height_cm','declared_value','extra_stops',
    'is_round_trip','prefer_ev','green_fund','scheduled_at','buyer_note','require_pod','require_otp','use_coins'
  ] <> '{}'::jsonb then
    raise sqlstate 'PT400' using message='Đơn hàng có trường không hỗ trợ hoặc quá dài.';
  end if;

  if coalesce((p_details->>'use_coins')::boolean, false) then
    perform 1 from public.delivery_market_coin_wallets where user_id = auth.uid() for update;
  end if;

  q:=public.delivery_cloud_quote(p_details);
  v_coin_disc := coalesce((q->>'coin_discount')::integer, 0);
  v_payable := coalesce((q->>'payable_fee')::integer, (q->>'shipping_fee')::integer);

  if p_pricing_version is distinct from (q->>'pricing_version')::integer
     or p_expected_fee is distinct from v_payable then
    raise sqlstate 'PT409' using message='Giá cước hoặc số dư Xu đã thay đổi. Vui lòng lấy báo giá lại.';
  end if;

  if length(btrim(coalesce(p_details->>'pickup_address',''))) not between 5 and 500 or
    length(btrim(coalesce(p_details->>'dropoff_address',''))) not between 5 and 500 or
    length(btrim(coalesce(p_details->>'recipient_name',''))) not between 1 and 120 or
    coalesce(p_details->>'recipient_phone','') !~ '^0[35789][0-9]{8}$' or
    length(btrim(coalesce(p_details->>'package_description',''))) not between 1 and 1000 or
    length(coalesce(p_details->>'buyer_note','')) > 500 or
    (p_details ? 'require_pod' and jsonb_typeof(p_details->'require_pod')<>'boolean') or
    (p_details ? 'require_otp' and jsonb_typeof(p_details->'require_otp')<>'boolean') or
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

  insert into public.delivery_cloud_orders(
    owner_id, merchant_id, request_key, request_payload, details, distance_meters,
    shipping_fee, coin_discount, payable_fee, cod_amount, pricing_version, merchant_ready
  ) values (
    auth.uid(), merchant, p_request_key, saved, p_details, (q->>'distance_meters')::integer,
    (q->>'shipping_fee')::integer, v_coin_disc, v_payable,
    (p_details->>'cod_amount')::integer, (q->>'pricing_version')::integer, merchant is null
  ) returning * into o;

  if v_coin_disc > 0 then
    update public.delivery_market_coin_wallets
      set balance = balance - v_coin_disc, updated_at = now()
      where user_id = auth.uid() and balance >= v_coin_disc;
    if not found then
      raise sqlstate 'PT409' using message='Số dư Xu không đủ để giảm cước phí.';
    end if;
    insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
      values(auth.uid(), -v_coin_disc, 'redeem_shipping', o.id);
  end if;

  if coalesce((p_details->>'require_otp')::boolean,false) then
    raw_bytes:=sha256(convert_to(gen_random_uuid()::text||':'||o.id::text,'UTF8'));
    otp_val:=((get_byte(raw_bytes,0)*65536 + get_byte(raw_bytes,1)*256 + get_byte(raw_bytes,2)) % 900000 + 100000)::text;
    insert into public.delivery_cloud_order_secrets(order_id,otp_code,otp_hash)
      values(o.id,otp_val,encode(sha256(convert_to(otp_val,'UTF8')),'hex'));
  end if;
  insert into public.delivery_live_rooms(id) values(o.tracking_code);
  insert into public.delivery_live_members values(o.tracking_code,auth.uid(),case when public.delivery_cloud_has_membership(a.user_id,'merchant') then 'merchant' else 'customer' end);
  if merchant is not null and merchant<>auth.uid() then insert into public.delivery_live_members values(o.tracking_code,merchant,'merchant'); end if;
  insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(o.id,auth.uid(),'create',o.status,o.version);
  insert into public.delivery_live_events(room_id,kind,payload) values(o.tracking_code,'status',jsonb_build_object('status',o.status,'version',o.version));
  return to_jsonb(o)-'request_payload'-'request_key';
end; $$;

revoke all on function public.delivery_cloud_create(jsonb,uuid,integer,integer) from public, anon;
grant execute on function public.delivery_cloud_create(jsonb,uuid,integer,integer) to authenticated;

-- Allow Marketplace use_coins to offset up to 20% of (goods + shipping_total) while preserving balanced shop ledger
create or replace function public.delivery_market_snapshot_v2(p_address uuid,p_options jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_addresses; s record; i record; v public.delivery_market_variants;
  voucher public.delivery_market_vouchers; items jsonb; item_obj jsonb; shops jsonb:='[]'; final_shops jsonb:='[]';
  subtotal bigint; goods_total bigint:=0; freight_total bigint:=0; total bigint:=0;
  weight numeric; vol_weight numeric; eff_weight numeric; details jsonb; q jsonb; cart_version integer; sel jsonb;
  has_opts boolean:=p_options is not null and p_options<>'{}'::jsonb;
  v_service text:=coalesce(p_options->>'service_type','standard');
  v_pay text:=coalesce(p_options->>'payment_method','cod');
  v_note text:=btrim(coalesce(p_options->>'buyer_note',''));
  v_sched text:=nullif(btrim(coalesce(p_options->>'scheduled_at','')),'');
  v_ev boolean:=coalesce((p_options->>'prefer_ev')::boolean,false);
  v_pod boolean:=coalesce((p_options->>'require_pod')::boolean,false);
  v_otp boolean:=coalesce((p_options->>'require_otp')::boolean,false);
  v_code text:=upper(btrim(coalesce(p_options->>'voucher_code','')));
  v_use_coins boolean:=coalesce((p_options->>'use_coins')::boolean,false);
  voucher_disc bigint:=0; coin_disc bigint:=0; wallet_bal bigint:=0; used_count integer:=0;
  rem_platform bigint:=0; shop_row jsonb; idx integer:=0; shop_cnt integer:=0;
  sh_sub bigint; sh_vdisc bigint; sh_pdisc bigint; sh_pay bigint;
begin
  if jsonb_typeof(coalesce(p_options,'{}'::jsonb))<>'object' or
     (coalesce(p_options,'{}'::jsonb)-array['buyer_note','service_type','payment_method','scheduled_at','prefer_ev','require_pod','require_otp','voucher_code','use_coins'])<>'{}'::jsonb then
    raise sqlstate 'PT400' using message='Tùy chọn đặt hàng không hợp lệ.';
  end if;
  if v_service not in ('standard','express','saving','same_day_2h','truck') or v_pay not in ('cod','prepaid') or length(v_note)>500 then
    raise sqlstate 'PT400' using message='Phương thức vận chuyển, thanh toán hoặc ghi chú không hợp lệ.';
  end if;
  if v_sched is not null and (v_sched::timestamptz < now()+interval '10 minutes' or v_sched::timestamptz > now()+interval '7 days') then
    raise sqlstate 'PT400' using message='Lịch hẹn giao hàng cần từ 10 phút tới 7 ngày.';
  end if;

  select * into a from public.delivery_cloud_addresses where id=p_address and user_id=auth.uid();
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy địa chỉ nhận hàng.'; end if;
  select version into cart_version from public.delivery_market_carts where user_id=auth.uid();
  if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid()) then
    raise sqlstate 'PT400' using message='Giỏ hàng đang trống.'; end if;

  for s in select distinct sh.* from public.delivery_market_cart_items c
    join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops sh on sh.id=p.shop_id where c.user_id=auth.uid() order by sh.id loop
    if s.status<>'active' or s.paused or (v_sched is null and not public.delivery_market_is_open(s.opening_schedule)) or
      (v_sched is not null and not public.delivery_market_is_open(s.opening_schedule,v_sched::timestamptz)) or
      not exists(select 1 from public.delivery_cloud_accounts where user_id=s.owner_id and
        public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
      raise sqlstate 'PT409' using message='Cửa hàng tạm ngừng nhận đơn.'; end if;
    if s.owner_id=auth.uid() then raise sqlstate 'PT400' using message='Không thể mua hàng từ cửa hàng của chính mình.'; end if;

    items:='[]'; subtotal:=0; weight:=0; vol_weight:=0;
    for i in select p.*,c.quantity,c.line_id,c.selected_options,c.variant_id from public.delivery_market_cart_items c
      join public.delivery_market_products p on p.id=c.product_id
      where c.user_id=auth.uid() and p.shop_id=s.id order by p.id,c.line_id loop
      if not i.published or (v_sched is null and not public.delivery_market_is_open(i.sale_schedule)) or
         (v_sched is not null and not public.delivery_market_is_open(i.sale_schedule,v_sched::timestamptz)) then
        raise sqlstate 'PT409' using message='Sản phẩm ngừng bán hoặc ngoài khung giờ mở bán.';
      end if;
      if i.variant_id is not null then
        select * into v from public.delivery_market_variants where id=i.variant_id and product_id=i.id and published;
        if not found or v.stock<(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and variant_id=i.variant_id) then
          raise sqlstate 'PT409' using message='Biến thể ngừng bán hoặc không đủ tồn kho.';
        end if;
      else
        if i.stock<(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and product_id=i.id and variant_id is null) then
          raise sqlstate 'PT409' using message='Sản phẩm ngừng bán hoặc không đủ tồn kho.';
        end if;
      end if;
      sel:=public.delivery_market_selection_v2(i.id,i.selected_options,i.variant_id,i.quantity,auth.uid());
      subtotal:=subtotal+(sel->>'unit_price')::bigint*i.quantity;
      weight:=weight+(sel->>'effective_weight_kg')::numeric*i.quantity;
      if (sel->>'length_cm')::numeric>0 and (sel->>'width_cm')::numeric>0 and (sel->>'height_cm')::numeric>0 then
        vol_weight:=vol_weight+round(((sel->>'length_cm')::numeric*(sel->>'width_cm')::numeric*(sel->>'height_cm')::numeric)/5000.0,2)*i.quantity;
      end if;
      item_obj:=jsonb_build_object(
        'product_id',i.id,'line_id',i.line_id,'name',i.name,'sku',coalesce(sel->>'effective_sku',i.sku),
        'quantity',i.quantity,'unit_price',sel->'unit_price','selected_options',sel->'selected_options',
        'options',sel->'options','preparation_minutes',i.preparation_minutes,
        'version',(sel->>'effective_terms_version')::integer,'image_url',i.image_url
      ) || case when i.variant_id is not null then jsonb_build_object('variant_id',i.variant_id,'variant_title',sel->'variant_title') else '{}'::jsonb end
        || case when sel->'flash_sale_id' is not null and jsonb_typeof(sel->'flash_sale_id')<>'null' then jsonb_build_object('flash_sale_id',sel->'flash_sale_id') else '{}'::jsonb end;
      items:=items||jsonb_build_array(item_obj);
    end loop;

    eff_weight:=greatest(weight,vol_weight);
    if subtotal>20000000 or eff_weight>(case when v_service='truck' then 500 else 30 end) then
      raise sqlstate 'PT400' using message='Đơn vượt giới hạn giá trị hoặc khối lượng của dịch vụ vận chuyển.';
    end if;
    details:=jsonb_build_object(
      'pickup_address',s.address,'pickup_lat',s.latitude,'pickup_lng',s.longitude,
      'dropoff_address',a.full_address,'dropoff_lat',a.latitude,'dropoff_lng',a.longitude,
      'recipient_name',a.recipient_name,'recipient_phone',a.recipient_phone,
      'package_description','Hàng mua tại '||s.name,'weight_kg',eff_weight,'service_type',v_service,
      'payment_method',case when v_pay='prepaid' then 'sender_cash' else 'recipient_cash' end,
      'cod_amount',case when v_pay='prepaid' then 0 else subtotal end,'merchant_id',s.owner_id
    ) || case when v_note<>'' then jsonb_build_object('buyer_note',v_note) else '{}'::jsonb end
      || case when v_sched is not null then jsonb_build_object('scheduled_at',v_sched) else '{}'::jsonb end
      || case when v_ev then jsonb_build_object('prefer_ev',true) else '{}'::jsonb end
      || case when v_pod then jsonb_build_object('require_pod',true) else '{}'::jsonb end
      || case when v_otp then jsonb_build_object('require_otp',true) else '{}'::jsonb end;
    q:=public.delivery_cloud_quote(details);
    if s.service_radius_km>0 and (q->>'distance_meters')::numeric > s.service_radius_km*1000 then
      raise sqlstate 'PT409' using message='Địa chỉ nhận hàng nằm ngoài bán kính phục vụ của '||s.name||'.';
    end if;
    shops:=shops||jsonb_build_array(jsonb_build_object(
      'shop_id',s.id,'shop_name',s.name,'shop_version',s.version,
      'merchant_id',s.owner_id,'items',items,'subtotal',subtotal,'shipping_fee',q->'shipping_fee',
      'pricing_version',q->'pricing_version','distance_meters',q->'distance_meters','details',details
    ));
    goods_total:=goods_total+subtotal;
    freight_total:=freight_total+(q->>'shipping_fee')::bigint;
  end loop;

  if not has_opts then
    total:=goods_total+freight_total;
    if total not between 1 and 100000000 then raise sqlstate 'PT400' using message='Tổng giỏ hàng vượt giới hạn.'; end if;
    return jsonb_build_object('address_id',a.id,'address_version',a.version,'cart_version',cart_version,'shops',shops,'total',total);
  end if;

  if v_code<>'' then
    select * into voucher from public.delivery_market_vouchers
      where code=v_code and active and starts_at<=now() and ends_at>now()
        and (owner_user_id is null or owner_user_id=auth.uid());
    if not found then raise sqlstate 'PT409' using message='Mã giảm giá không tồn tại hoặc đã hết hạn.'; end if;
    select count(*) into used_count from public.delivery_market_voucher_usages
      where voucher_id=voucher.id and user_id=auth.uid() and state='allocated';
    if used_count>=voucher.per_user_limit then raise sqlstate 'PT409' using message='Bạn đã dùng hết lượt mã giảm giá này.'; end if;
    if voucher.shop_id is not null then
      select (g->>'subtotal')::bigint into sh_sub from jsonb_array_elements(shops) g where (g->>'shop_id')::uuid=voucher.shop_id;
      if sh_sub is null or sh_sub<voucher.min_subtotal then
        raise sqlstate 'PT409' using message='Đơn tại cửa hàng chưa đạt giá trị tối thiểu của mã giảm giá.';
      end if;
      voucher_disc:=least(sh_sub,voucher.max_discount,case when voucher.discount_kind='fixed' then voucher.discount_value::bigint else round(sh_sub*voucher.discount_value/100.0)::bigint end);
    else
      if goods_total<voucher.min_subtotal then raise sqlstate 'PT409' using message='Giỏ hàng chưa đạt giá trị tối thiểu của mã giảm giá.'; end if;
      voucher_disc:=least(goods_total,voucher.max_discount,case when voucher.discount_kind='fixed' then voucher.discount_value::bigint else round(goods_total*voucher.discount_value/100.0)::bigint end);
    end if;
    if voucher_disc<=0 or voucher.budget_used+voucher_disc>voucher.budget_total then
      raise sqlstate 'PT409' using message='Ngân sách mã giảm giá đã hết.';
    end if;
  end if;

  if v_use_coins then
    select coalesce(balance,0) into wallet_bal from public.delivery_market_coin_wallets where user_id=auth.uid();
    coin_disc:=least(
      wallet_bal,
      floor(greatest(0, goods_total - voucher_disc + freight_total) * 0.20)::bigint,
      greatest(0, goods_total - voucher_disc)
    );
  end if;

  rem_platform:=(case when voucher.id is not null and voucher.shop_id is null then voucher_disc else 0 end)+coin_disc;
  shop_cnt:=jsonb_array_length(shops);
  for shop_row in select * from jsonb_array_elements(shops) loop
    idx:=idx+1;
    sh_sub:=(shop_row->>'subtotal')::bigint;
    sh_vdisc:=case when voucher.id is not null and voucher.shop_id=(shop_row->>'shop_id')::uuid then voucher_disc else 0 end;
    if rem_platform>0 then
      if idx=shop_cnt then sh_pdisc:=least(sh_sub-sh_vdisc,rem_platform);
      else sh_pdisc:=least(sh_sub-sh_vdisc,floor(((case when voucher.id is not null and voucher.shop_id is null then voucher_disc else 0 end)+coin_disc)*sh_sub::numeric/greatest(1,goods_total))::bigint);
      end if;
      rem_platform:=greatest(0,rem_platform-sh_pdisc);
    else sh_pdisc:=0;
    end if;
    sh_pay:=greatest(0,sh_sub-sh_vdisc-sh_pdisc);
    details:=jsonb_set(shop_row->'details','{cod_amount}',to_jsonb(case when v_pay='prepaid' then 0::bigint else sh_pay end));
    final_shops:=final_shops||jsonb_build_array(
      jsonb_set(shop_row,'{details}',details)||jsonb_build_object(
        'shop_discount',sh_vdisc,'platform_discount',sh_pdisc,'payable_subtotal',sh_pay,
        'buyer_note',v_note,'scheduled_at',v_sched,'payment_method',v_pay
      )
    );
  end loop;

  total:=greatest(1,goods_total-voucher_disc-coin_disc+freight_total);
  if total not between 1 and 100000000 then raise sqlstate 'PT400' using message='Tổng giỏ hàng vượt giới hạn.'; end if;
  return jsonb_build_object(
    'address_id',a.id,'address_version',a.version,'cart_version',cart_version,
    'shops',final_shops,'goods_subtotal',goods_total,'shipping_total',freight_total,
    'voucher_id',voucher.id,'voucher_code',nullif(v_code,''),'voucher_discount',voucher_disc,
    'coin_discount',coin_disc,'discount_total',voucher_disc+coin_disc,
    'payment_method',v_pay,'checkout_options',p_options,'total',total
  );
end$$;
revoke all on function public.delivery_market_snapshot_v2(uuid,jsonb) from public,anon,authenticated;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'delivery_user_notifications'
     ) then
    alter publication supabase_realtime add table public.delivery_user_notifications;
  end if;
exception when others then
  null;
end $$;

notify pgrst, 'reload schema';
commit;
