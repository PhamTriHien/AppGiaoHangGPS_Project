-- Additive Standalone Shipping Cash & COD Settlement, Commerce Guard Hardening,
-- and Payment Settlement Notifications.
-- Safe to reapply; seeds zero demo users, orders, receipts, or balances.
begin;

-- 1. Cash Collection Columns & Invariants on delivery_cloud_orders
alter table public.delivery_cloud_orders
  add column if not exists cash_collected_fee integer not null default 0;
alter table public.delivery_cloud_orders
  add column if not exists cash_collected_cod integer not null default 0;
alter table public.delivery_cloud_orders
  add column if not exists cash_collected_at timestamptz;
alter table public.delivery_cloud_orders
  add column if not exists cash_collected_by uuid references auth.users(id);

alter table public.delivery_cloud_orders
  drop constraint if exists delivery_cloud_orders_cash_collected_check;
alter table public.delivery_cloud_orders
  add constraint delivery_cloud_orders_cash_collected_check
  check (
    cash_collected_fee >= 0
    and cash_collected_fee <= payable_fee
    and cash_collected_cod >= 0
    and cash_collected_cod <= cod_amount
    and (
      (cash_collected_fee = 0 and cash_collected_cod = 0)
      or (cash_collected_at is not null and cash_collected_by is not null)
    )
  );

-- 2. Harden Commerce Guard against Dual Cash + Online Shipping Fee Collection
create or replace function public.delivery_commerce_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status is distinct from old.status
     or new.driver_id is distinct from old.driver_id
     or new.merchant_ready is distinct from old.merchant_ready
     or new.fulfillment_provider is distinct from old.fulfillment_provider then
    if coalesce(current_setting('ghst.carrier_sync', true), '') <> 'on'
       and exists (
         select 1 from public.delivery_payment_transactions
         where order_id = old.id and status in ('CREATING', 'PENDING', 'REVIEW')
       ) then
      raise sqlstate 'PT409' using message = 'Cần hoàn tất, hủy liên kết thanh toán hoặc đối soát trước khi điều phối/hủy đơn.';
    end if;
    if old.fulfillment_provider = 'ghn'
       and coalesce(current_setting('ghst.carrier_sync', true), '') <> 'on' then
      raise sqlstate 'PT409' using message = 'Đơn GHN phải được cập nhật qua hãng vận chuyển.';
    end if;
  end if;

  if new.cash_collected_fee > old.cash_collected_fee
     and exists (
       select 1 from public.delivery_payment_transactions
       where order_id = old.id and status in ('CREATING', 'PENDING', 'PAID', 'REVIEW')
     ) then
    raise sqlstate 'PT409' using message = 'Đơn đã có giao dịch thanh toán cước trực tuyến, không thu trùng tiền mặt cước.';
  end if;

  if new.fulfillment_provider = 'ghn' and new.driver_id is not null then
    raise sqlstate 'PT409' using message = 'Không gán tài xế nội bộ cho đơn GHN.';
  end if;

  if old.payment_status = 'PAID' and new.status in ('cancelled', 'returned') then
    new.payment_status := 'REVIEW';
    update public.delivery_payment_transactions
      set status = 'REVIEW', updated_at = now()
      where order_id = new.id and status = 'PAID';
  end if;

  return new;
end; $$;
revoke all on function public.delivery_commerce_guard() from public, anon, authenticated;

-- 3. Authoritative Driver / Operator Cash & COD Collection in delivery_cloud_transition
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
  op boolean;
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
  if auth.uid() is null then
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
       'fail','retry','return','complete_return','collect_cash'
     )
     or p_reason is null
     or length(p_reason) > 500 then
    raise sqlstate 'PT400' using message = 'Thao tác hoặc lý do không hợp lệ.';
  end if;
  if p_action in ('cancel','fail','return') and length(btrim(p_reason)) < 3 then
    raise sqlstate 'PT400' using message = 'Cần nhập lý do ít nhất 3 ký tự.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_key::text, 0));
  request := jsonb_build_object(
    'order', p_order,
    'action', p_action,
    'version', p_version,
    'reason', case when p_action = 'deliver' and p_reason ~ '^(OTP:)?[0-9]{6}$' then 'OTP_SUBMITTED' else p_reason end
  );
  select * into prior
    from public.delivery_cloud_commands
    where actor_id = auth.uid() and request_key = p_request_key;
  if found then
    if prior.request_payload <> request then
      raise sqlstate 'PT409' using message = 'Mã yêu cầu đã dùng cho nội dung khác.';
    end if;
    return prior.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('driver:' || auth.uid()::text, 0));
  select * into o from public.delivery_cloud_orders where id = p_order for update;
  select * into a from public.delivery_cloud_accounts where user_id = auth.uid();

  if o.id is null or (
    not op
    and auth.uid() not in (o.owner_id, coalesce(o.merchant_id, o.owner_id), coalesce(o.driver_id, o.owner_id))
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
    if (not op and auth.uid() is distinct from o.merchant_id) or o.status <> 'searching' or o.merchant_ready then
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
    if exists (
      select 1 from public.delivery_cloud_orders
      where driver_id = auth.uid() and status not in ('delivered','returned','cancelled')
    ) then
      raise sqlstate 'PT409' using message = 'Bạn đang có chuyến chưa hoàn tất.';
    end if;
    o.driver_id := auth.uid();
    next_status := 'accepted';

  elsif p_action = 'cancel' then
    if (not op and auth.uid() is distinct from o.owner_id and auth.uid() is distinct from o.merchant_id)
       or o.status not in ('searching','accepted','arrivingPickup')
       or length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then
      raise sqlstate 'PT409' using message = 'Không thể hủy đơn hoặc chưa nhập lý do hợp lệ.';
    end if;
    next_status := 'cancelled';
    o.cancel_reason := btrim(p_reason);

  elsif p_action = 'collect_cash' then
    if not op and (
      auth.uid() is distinct from o.driver_id
      or not public.delivery_cloud_has_membership(auth.uid(), 'driver')
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
    o.cash_collected_by := auth.uid();

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
    if not op and (auth.uid() is distinct from o.driver_id or not public.delivery_cloud_has_membership(auth.uid(), 'driver')) then
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
    insert into public.delivery_live_members values (o.tracking_code, auth.uid(), 'driver')
      on conflict (room_id, user_id) do update set role = 'driver';
  end if;

  insert into public.delivery_cloud_history(order_id, actor_id, action, status, version, reason)
    values (o.id, auth.uid(), p_action, o.status, o.version, history_reason);
  insert into public.delivery_live_events(room_id, kind, payload)
    values (o.tracking_code, 'status', jsonb_build_object('status', o.status, 'version', o.version));

  response := to_jsonb(o) - 'request_payload' - 'request_key';
  insert into public.delivery_cloud_commands values (auth.uid(), p_request_key, request, response, now());
  return response;
end; $$;

revoke all on function public.delivery_cloud_transition(uuid,text,integer,uuid,text) from public, anon;
grant execute on function public.delivery_cloud_transition(uuid,text,integer,uuid,text) to authenticated;

-- 4. Emit Push/In-App Notifications on Cash Collection & Online VietQR Settlement
create or replace function public.delivery_cloud_orders_after_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  is_market_linked boolean := false;
  v_earn bigint := 0;
  v_title text;
  v_body text;
  v_pay_body text;
  v_meta jsonb;
  v_fee_delta integer := 0;
  v_cod_delta integer := 0;
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

notify pgrst, 'reload schema';
commit;
