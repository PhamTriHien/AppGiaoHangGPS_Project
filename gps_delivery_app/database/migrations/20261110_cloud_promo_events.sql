-- Additive Cloud Promo Events: Daily Check-in, Order Missions, Coin Exchange,
-- Server-Authoritative Lucky Spin Wheel, Mystery Blind Box & Personal Vouchers.
-- Safe to reapply; seeds only the singleton settings row (zero demo users/shops/orders/vouchers).
begin;

alter table public.delivery_market_coin_ledger
  drop constraint if exists delivery_market_coin_ledger_kind_check;
alter table public.delivery_market_coin_ledger
  add constraint delivery_market_coin_ledger_kind_check
  check(kind in (
    'earn_settlement','redeem_checkout','release_cancel','reverse_refund',
    'promo_checkin','promo_spin','promo_blind_box','promo_mission','promo_exchange'
  ));

alter table public.delivery_market_vouchers
  add column if not exists owner_user_id uuid references auth.users(id) on delete cascade;

create index if not exists delivery_market_vouchers_owner
  on public.delivery_market_vouchers(owner_user_id, ends_at desc)
  where owner_user_id is not null and active;

create table if not exists public.delivery_promo_settings (
  id boolean primary key default true check(id),
  enabled boolean not null default true,
  spin_ticket_coin_cost integer not null default 100 check(spin_ticket_coin_cost between 10 and 100000),
  box_ticket_coin_cost integer not null default 150 check(box_ticket_coin_cost between 10 and 100000),
  voucher_20k_coin_cost integer not null default 200 check(voucher_20k_coin_cost between 10 and 100000),
  voucher_40k_coin_cost integer not null default 350 check(voucher_40k_coin_cost between 10 and 100000),
  version integer not null default 1 check(version>0),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

insert into public.delivery_promo_settings(id)
  values(true)
  on conflict(id) do nothing;

create table if not exists public.delivery_promo_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  spin_tickets integer not null default 0 check(spin_tickets between 0 and 10000),
  blind_box_tickets integer not null default 0 check(blind_box_tickets between 0 and 10000),
  checkin_streak integer not null default 0 check(checkin_streak between 0 and 7),
  last_checkin_date date,
  opened_boxes jsonb not null default '{}'::jsonb check(jsonb_typeof(opened_boxes)='object'),
  claimed_missions jsonb not null default '[]'::jsonb check(jsonb_typeof(claimed_missions)='array'),
  total_spins integer not null default 0 check(total_spins>=0),
  total_boxes_opened integer not null default 0 check(total_boxes_opened>=0),
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_promo_reward_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_kind text not null check(event_kind in ('checkin','mission','exchange','spin','blind_box')),
  rarity text not null default 'Common' check(rarity in ('Common','Rare','Epic','Legendary','R','SR','SSR')),
  title text not null check(length(title) between 1 and 140),
  summary text not null check(length(summary) between 1 and 300),
  coins_delta integer not null default 0,
  spin_tickets_delta integer not null default 0,
  box_tickets_delta integer not null default 0,
  voucher_id uuid references public.delivery_market_vouchers(id),
  voucher_code text,
  wheel_segment integer check(wheel_segment is null or wheel_segment between 0 and 7),
  box_index integer check(box_index is null or box_index between 0 and 5),
  created_at timestamptz not null default now()
);

create index if not exists delivery_promo_reward_claims_user
  on public.delivery_promo_reward_claims(user_id, created_at desc, id desc);

drop trigger if exists immutable on public.delivery_promo_reward_claims;
create trigger immutable before update or delete on public.delivery_promo_reward_claims
  for each row execute function public.delivery_market_immutable();

do $$ declare t text; begin
  foreach t in array array[
    'delivery_promo_settings','delivery_promo_wallets','delivery_promo_reward_claims'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- Enforce personal voucher ownership on Marketplace checkout quote & order placement
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
    coin_disc:=least(wallet_bal,floor(greatest(0,goods_total-voucher_disc)*0.20)::bigint,greatest(0,goods_total-voucher_disc));
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

-- Filter personal vouchers per owner_user_id across Marketplace voucher/product/shop reads
do $$
begin
  if to_regprocedure('public.delivery_market_operations_core(text,jsonb)') is null then
    alter function public.delivery_market_operations(text,jsonb)
      rename to delivery_market_operations_core;
    revoke all on function public.delivery_market_operations_core(text,jsonb)
      from public, anon, authenticated;
  end if;
end $$;

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

create or replace function public.delivery_promo_mint_voucher(
  p_user uuid,
  p_prefix text,
  p_title text,
  p_kind text,
  p_value integer,
  p_max integer,
  p_min integer,
  p_days integer default 7
) returns public.delivery_market_vouchers
language plpgsql security definer set search_path='' as $$
declare
  v_code text;
  v_row public.delivery_market_vouchers;
begin
  loop
    v_code := upper(regexp_replace(coalesce(p_prefix, 'PR'), '[^A-Za-z0-9]', '', 'g'))
      || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists(select 1 from public.delivery_market_vouchers where code = v_code);
  end loop;

  insert into public.delivery_market_vouchers(
    code, shop_id, owner_user_id, title, discount_kind, discount_value,
    max_discount, min_subtotal, budget_total, budget_used, per_user_limit,
    starts_at, ends_at, active, created_by
  ) values (
    v_code, null, p_user, left(btrim(p_title), 120), p_kind, p_value,
    p_max, p_min, p_max, 0, 1,
    now() - interval '1 minute',
    now() + make_interval(days => greatest(1, p_days)),
    true, p_user
  ) returning * into v_row;

  return v_row;
end $$;
revoke all on function public.delivery_promo_mint_voucher(uuid,text,text,text,integer,integer,integer,integer)
  from public, anon, authenticated;

create or replace function public.delivery_promo_status_payload(
  p_user uuid,
  p_is_operator boolean
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  s public.delivery_promo_settings;
  w public.delivery_promo_wallets;
  today_vn date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  coin_bal bigint := 0;
  eff_streak integer := 0;
  checked_today boolean := false;
  ship_done integer := 0;
  market_done integer := 0;
  ev_done integer := 0;
  total_done integer := 0;
  claimed jsonb := '[]'::jsonb;
  missions jsonb;
begin
  select * into s from public.delivery_promo_settings where id = true;
  if not found then
    s.enabled := true;
    s.spin_ticket_coin_cost := 100;
    s.box_ticket_coin_cost := 150;
    s.voucher_20k_coin_cost := 200;
    s.voucher_40k_coin_cost := 350;
    s.version := 1;
  end if;

  select * into w from public.delivery_promo_wallets where user_id = p_user;
  if not found then
    w.user_id := p_user;
    w.spin_tickets := 0;
    w.blind_box_tickets := 0;
    w.checkin_streak := 0;
    w.last_checkin_date := null;
    w.opened_boxes := '{}'::jsonb;
    w.claimed_missions := '[]'::jsonb;
    w.total_spins := 0;
    w.total_boxes_opened := 0;
  end if;

  select coalesce(balance, 0) into coin_bal
    from public.delivery_market_coin_wallets where user_id = p_user;

  checked_today := (w.last_checkin_date = today_vn);
  if w.last_checkin_date in (today_vn, today_vn - 1) then
    eff_streak := w.checkin_streak;
  else
    eff_streak := 0;
  end if;
  claimed := coalesce(w.claimed_missions, '[]'::jsonb);

  select count(*)::integer into ship_done
    from public.delivery_cloud_orders co
    where co.owner_id = p_user
      and co.status = 'delivered'
      and not exists(select 1 from public.delivery_market_shop_orders so where so.delivery_id = co.id)
      and not exists(select 1 from public.delivery_market_shipments ms where ms.delivery_id = co.id);

  select count(*)::integer into market_done
    from public.delivery_market_shop_orders so
    where so.owner_id = p_user
      and so.delivered_at is not null
      and so.state <> 'cancelled';

  select count(*)::integer into ev_done
    from public.delivery_cloud_orders co
    where co.owner_id = p_user
      and co.status = 'delivered'
      and coalesce((co.details->>'prefer_ev')::boolean, false);

  total_done := ship_done + market_done;

  missions := jsonb_build_array(
    jsonb_build_object(
      'id', 'first_shipping',
      'title', 'Chuyến giao hàng đầu tiên',
      'subtitle', 'Hoàn thành 1 đơn giao hàng thành công',
      'progress', least(1, ship_done),
      'target', 1,
      'coins', 100,
      'spin_tickets', 1,
      'box_tickets', 0,
      'claimed', claimed ? 'first_shipping',
      'claimable', ship_done >= 1 and not (claimed ? 'first_shipping')
    ),
    jsonb_build_object(
      'id', 'first_market',
      'title', 'Đơn Ăn uống / Mua sắm đầu tiên',
      'subtitle', 'Nhận thành công 1 đơn đặt món hoặc mua sắm',
      'progress', least(1, market_done),
      'target', 1,
      'coins', 120,
      'spin_tickets', 0,
      'box_tickets', 1,
      'claimed', claimed ? 'first_market',
      'claimable', market_done >= 1 and not (claimed ? 'first_market')
    ),
    jsonb_build_object(
      'id', 'green_ev',
      'title', 'Giao hàng xanh Xe điện (EV)',
      'subtitle', 'Hoàn thành 1 chuyến có bật ưu tiên xe điện xanh',
      'progress', least(1, ev_done),
      'target', 1,
      'coins', 150,
      'spin_tickets', 1,
      'box_tickets', 0,
      'claimed', claimed ? 'green_ev',
      'claimable', ev_done >= 1 and not (claimed ? 'green_ev')
    ),
    jsonb_build_object(
      'id', 'three_orders',
      'title', 'Mốc 3 đơn hàng hoàn tất',
      'subtitle', 'Hoàn tất tổng cộng 3 đơn giao hàng hoặc mua sắm',
      'progress', least(3, total_done),
      'target', 3,
      'coins', 300,
      'spin_tickets', 1,
      'box_tickets', 1,
      'claimed', claimed ? 'three_orders',
      'claimable', total_done >= 3 and not (claimed ? 'three_orders')
    )
  );

  return jsonb_build_object(
    'enabled', s.enabled,
    'server_date', today_vn::text,
    'coin_balance', coin_bal,
    'settings', jsonb_build_object(
      'enabled', s.enabled,
      'spin_ticket_coin_cost', s.spin_ticket_coin_cost,
      'box_ticket_coin_cost', s.box_ticket_coin_cost,
      'voucher_20k_coin_cost', s.voucher_20k_coin_cost,
      'voucher_40k_coin_cost', s.voucher_40k_coin_cost,
      'version', s.version,
      'updated_at', s.updated_at
    ),
    'wallet', jsonb_build_object(
      'spin_tickets', w.spin_tickets,
      'blind_box_tickets', w.blind_box_tickets,
      'checkin_streak', eff_streak,
      'checked_in_today', checked_today,
      'last_checkin_date', w.last_checkin_date,
      'opened_boxes', w.opened_boxes,
      'total_spins', w.total_spins,
      'total_boxes_opened', w.total_boxes_opened
    ),
    'checkin_schedule', jsonb_build_array(
      jsonb_build_object('day', 1, 'coins', 50, 'spin_tickets', 1, 'box_tickets', 0),
      jsonb_build_object('day', 2, 'coins', 80, 'spin_tickets', 0, 'box_tickets', 0),
      jsonb_build_object('day', 3, 'coins', 100, 'spin_tickets', 1, 'box_tickets', 0),
      jsonb_build_object('day', 4, 'coins', 120, 'spin_tickets', 0, 'box_tickets', 1),
      jsonb_build_object('day', 5, 'coins', 150, 'spin_tickets', 1, 'box_tickets', 0),
      jsonb_build_object('day', 6, 'coins', 200, 'spin_tickets', 0, 'box_tickets', 0),
      jsonb_build_object('day', 7, 'coins', 350, 'spin_tickets', 1, 'box_tickets', 1)
    ),
    'missions', missions,
    'exchange_catalog', jsonb_build_array(
      jsonb_build_object(
        'id', 'spin_ticket',
        'title', '+1 Vé Vòng Xoay May Mắn',
        'subtitle', 'Quay thưởng Voucher hoặc Xu ngay lập tức',
        'coin_cost', s.spin_ticket_coin_cost,
        'kind', 'ticket'
      ),
      jsonb_build_object(
        'id', 'blind_box_ticket',
        'title', '+1 Vé Mở Hộp Mù Bí Ẩn',
        'subtitle', 'Khui hộp mù săn Voucher SSR 60.000đ hoặc kho Xu',
        'coin_cost', s.box_ticket_coin_cost,
        'kind', 'ticket'
      ),
      jsonb_build_object(
        'id', 'voucher_20k',
        'title', 'Voucher Ăn Uống 20.000đ',
        'subtitle', 'Đơn từ 80.000đ • Hiệu lực 7 ngày cho riêng tài khoản bạn',
        'coin_cost', s.voucher_20k_coin_cost,
        'kind', 'voucher'
      ),
      jsonb_build_object(
        'id', 'voucher_40k',
        'title', 'Voucher Ăn Uống 40.000đ',
        'subtitle', 'Đơn từ 150.000đ • Hiệu lực 7 ngày cho riêng tài khoản bạn',
        'coin_cost', s.voucher_40k_coin_cost,
        'kind', 'voucher'
      )
    ),
    'wheel_segments', jsonb_build_array(
      jsonb_build_object('index', 0, 'label', '+50 Xu', 'subtitle', 'Cộng thẳng Ví Xu', 'rarity', 'Common'),
      jsonb_build_object('index', 1, 'label', 'Voucher 15K', 'subtitle', 'Đơn từ 60.000đ (7 ngày)', 'rarity', 'Common'),
      jsonb_build_object('index', 2, 'label', '+1 Vé Hộp Mù', 'subtitle', 'Mở 1 Hộp Mù Bí Ẩn', 'rarity', 'Rare'),
      jsonb_build_object('index', 3, 'label', '+150 Xu', 'subtitle', 'Cộng thẳng Ví Xu', 'rarity', 'Rare'),
      jsonb_build_object('index', 4, 'label', 'Voucher 25K', 'subtitle', 'Đơn từ 99.000đ (7 ngày)', 'rarity', 'Rare'),
      jsonb_build_object('index', 5, 'label', '+30 Xu Lộc', 'subtitle', 'Xu may mắn mỗi lượt', 'rarity', 'Common'),
      jsonb_build_object('index', 6, 'label', 'Giảm 50% (35K)', 'subtitle', 'Đơn từ 70.000đ (7 ngày)', 'rarity', 'Epic'),
      jsonb_build_object('index', 7, 'label', 'Siêu Cấp 50K', 'subtitle', 'Đơn từ 150.000đ (7 ngày)', 'rarity', 'Legendary')
    ),
    'vouchers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id,
        'code', v.code,
        'shop_id', v.shop_id,
        'shop_name', sh.name,
        'personal', v.owner_user_id is not null,
        'title', v.title,
        'discount_kind', v.discount_kind,
        'discount_value', v.discount_value,
        'max_discount', v.max_discount,
        'min_subtotal', v.min_subtotal,
        'per_user_limit', v.per_user_limit,
        'starts_at', v.starts_at,
        'ends_at', v.ends_at,
        'remaining_budget', v.budget_total - v.budget_used,
        'used_by_me', (
          select count(*)::integer from public.delivery_market_voucher_usages vu
          where vu.voucher_id = v.id and vu.user_id = p_user and vu.state = 'allocated'
        )
      ) order by (v.owner_user_id is not null) desc, v.created_at desc, v.id desc)
      from public.delivery_market_vouchers v
      left join public.delivery_market_shops sh on sh.id = v.shop_id
      where v.active
        and v.starts_at <= now()
        and v.ends_at > now()
        and v.budget_used < v.budget_total
        and (v.owner_user_id is null or v.owner_user_id = p_user)
        and (
          select count(*) from public.delivery_market_voucher_usages vu
          where vu.voucher_id = v.id and vu.user_id = p_user and vu.state = 'allocated'
        ) < v.per_user_limit
    ), '[]'::jsonb),
    'flash_sales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', fs.id,
        'product_id', p.id,
        'product_name', p.name,
        'image_url', p.image_url,
        'shop_id', sh.id,
        'shop_name', sh.name,
        'original_price', p.price,
        'sale_price', fs.sale_price,
        'allocated_stock', fs.allocated_stock,
        'sold_stock', fs.sold_stock,
        'per_user_limit', fs.per_user_limit,
        'ends_at', fs.ends_at
      ) order by fs.ends_at asc, fs.id asc)
      from (
        select fs0.*
        from public.delivery_market_flash_sales fs0
        join public.delivery_market_products p0 on p0.id = fs0.product_id
        join public.delivery_market_shops sh0 on sh0.id = fs0.shop_id
        join public.delivery_cloud_accounts m0 on m0.user_id = sh0.owner_id
        where fs0.active
          and fs0.starts_at <= now()
          and fs0.ends_at > now()
          and fs0.sold_stock < fs0.allocated_stock
          and p0.published
          and sh0.status = 'active'
          and not sh0.paused
          and not m0.blocked
          and public.delivery_cloud_has_membership(m0.user_id, 'merchant')
        order by fs0.ends_at asc, fs0.id asc
        limit 20
      ) fs
      join public.delivery_market_products p on p.id = fs.product_id
      join public.delivery_market_shops sh on sh.id = fs.shop_id
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id,
        'event_kind', h.event_kind,
        'rarity', h.rarity,
        'title', h.title,
        'summary', h.summary,
        'coins_delta', h.coins_delta,
        'spin_tickets_delta', h.spin_tickets_delta,
        'box_tickets_delta', h.box_tickets_delta,
        'voucher_code', h.voucher_code,
        'wheel_segment', h.wheel_segment,
        'box_index', h.box_index,
        'created_at', h.created_at
      ) order by h.created_at desc, h.id desc)
      from (
        select * from public.delivery_promo_reward_claims
        where user_id = p_user
        order by created_at desc, id desc
        limit 30
      ) h
    ), '[]'::jsonb)
  ) || case when p_is_operator then jsonb_build_object(
    'admin_stats', jsonb_build_object(
      'participants', (select count(*)::integer from public.delivery_promo_wallets),
      'total_spins', coalesce((select sum(total_spins)::integer from public.delivery_promo_wallets), 0),
      'total_boxes_opened', coalesce((select sum(total_boxes_opened)::integer from public.delivery_promo_wallets), 0),
      'total_claims', (select count(*)::integer from public.delivery_promo_reward_claims),
      'personal_vouchers_active', (
        select count(*)::integer from public.delivery_market_vouchers
        where owner_user_id is not null and active and ends_at > now() and budget_used < budget_total
      )
    )
  ) else '{}'::jsonb end;
end $$;
revoke all on function public.delivery_promo_status_payload(uuid,boolean)
  from public, anon, authenticated;

create or replace function public.delivery_cloud_promo_events(
  p_action text,
  p_payload jsonb default '{}'
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  d jsonb := coalesce(p_payload, '{}'::jsonb);
  uid uuid := auth.uid();
  op boolean := public.delivery_is_operator();
  s public.delivery_promo_settings;
  w public.delivery_promo_wallets;
  claim_row public.delivery_promo_reward_claims;
  v_minted public.delivery_market_vouchers;
  today_vn date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  next_streak integer;
  v_coins integer := 0;
  v_spins integer := 0;
  v_boxes integer := 0;
  v_rarity text := 'Common';
  v_title text := '';
  v_summary text := '';
  v_mission text;
  v_item text;
  v_cost integer;
  v_roll integer;
  v_segment integer := null;
  v_box_idx integer := null;
  ship_done integer := 0;
  market_done integer := 0;
  ev_done integer := 0;
  v_eligible boolean := false;
begin
  if uid is null then
    raise sqlstate 'PT401' using message = 'Vui lòng đăng nhập tài khoản.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text) > 4000 then
    raise sqlstate 'PT400' using message = 'Dữ liệu sự kiện khuyến mãi không hợp lệ.';
  end if;

  if p_action = 'status' then
    if not op and not public.delivery_cloud_active() then
      raise sqlstate 'PT403' using message = 'Cần hồ sơ tài khoản đang hoạt động.';
    end if;
    return public.delivery_promo_status_payload(uid, op);
  end if;

  if p_action = 'admin_settings_save' then
    if not op then
      raise sqlstate 'PT403' using message = 'Chỉ Quản trị viên mới được cấu hình sự kiện.';
    end if;
    insert into public.delivery_promo_settings(id) values(true) on conflict(id) do nothing;
    select * into s from public.delivery_promo_settings where id = true for update;
    if d ? 'version' and (
      jsonb_typeof(d->'version') <> 'number' or (d->>'version')::integer is distinct from s.version
    ) then
      raise sqlstate 'PT409' using message = 'Cấu hình sự kiện đã thay đổi. Hãy tải lại.';
    end if;
    if jsonb_typeof(d->'enabled') is distinct from 'boolean' then
      raise sqlstate 'PT400' using message = 'Trạng thái bật/tắt sự kiện không hợp lệ.';
    end if;
    update public.delivery_promo_settings set
      enabled = (d->>'enabled')::boolean,
      spin_ticket_coin_cost = coalesce((d->>'spin_ticket_coin_cost')::integer, s.spin_ticket_coin_cost),
      box_ticket_coin_cost = coalesce((d->>'box_ticket_coin_cost')::integer, s.box_ticket_coin_cost),
      voucher_20k_coin_cost = coalesce((d->>'voucher_20k_coin_cost')::integer, s.voucher_20k_coin_cost),
      voucher_40k_coin_cost = coalesce((d->>'voucher_40k_coin_cost')::integer, s.voucher_40k_coin_cost),
      version = s.version + 1,
      updated_by = uid,
      updated_at = now()
      where id = true
      returning * into s;
    insert into public.delivery_cloud_admin_audit(actor_id, action, target_id, after_value)
      values(uid, 'promo_settings_save', uid, jsonb_build_object(
        'enabled', s.enabled,
        'spin_ticket_coin_cost', s.spin_ticket_coin_cost,
        'box_ticket_coin_cost', s.box_ticket_coin_cost,
        'voucher_20k_coin_cost', s.voucher_20k_coin_cost,
        'voucher_40k_coin_cost', s.voucher_40k_coin_cost,
        'version', s.version
      ));
    return public.delivery_promo_status_payload(uid, op);
  end if;

  if not public.delivery_cloud_active() then
    raise sqlstate 'PT403' using message = 'Cần hoàn tất hồ sơ tài khoản đang hoạt động để tham gia sự kiện.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('promo:' || uid::text, 0));
  insert into public.delivery_promo_settings(id) values(true) on conflict(id) do nothing;
  select * into s from public.delivery_promo_settings where id = true for share;
  if not s.enabled then
    raise sqlstate 'PT409' using message = 'Trung tâm sự kiện khuyến mãi hiện đang tạm dừng.';
  end if;

  insert into public.delivery_promo_wallets(user_id) values(uid) on conflict(user_id) do nothing;
  select * into w from public.delivery_promo_wallets where user_id = uid for update;

  if p_action = 'checkin' then
    if w.last_checkin_date = today_vn then
      raise sqlstate 'PT409' using message = 'Bạn đã điểm danh hôm nay rồi. Hãy quay lại vào ngày mai.';
    end if;
    if w.last_checkin_date = today_vn - 1 and w.checkin_streak < 7 then
      next_streak := w.checkin_streak + 1;
    else
      next_streak := 1;
    end if;

    v_coins := case next_streak
      when 1 then 50 when 2 then 80 when 3 then 100 when 4 then 120
      when 5 then 150 when 6 then 200 else 350 end;
    v_spins := case when next_streak in (1, 3, 5, 7) then 1 else 0 end;
    v_boxes := case when next_streak in (4, 7) then 1 else 0 end;
    v_rarity := case when next_streak = 7 then 'Epic' when next_streak >= 4 then 'Rare' else 'Common' end;
    v_title := 'Điểm danh Ngày ' || next_streak;
    v_summary := '+' || v_coins || ' Xu'
      || case when v_spins > 0 then ' • +' || v_spins || ' Vé quay' else '' end
      || case when v_boxes > 0 then ' • +' || v_boxes || ' Vé hộp mù' else '' end;

    update public.delivery_promo_wallets set
      checkin_streak = next_streak,
      last_checkin_date = today_vn,
      spin_tickets = spin_tickets + v_spins,
      blind_box_tickets = blind_box_tickets + v_boxes,
      updated_at = now()
      where user_id = uid;

    insert into public.delivery_promo_reward_claims(
      user_id, event_kind, rarity, title, summary, coins_delta, spin_tickets_delta, box_tickets_delta
    ) values (
      uid, 'checkin', v_rarity, v_title, v_summary, v_coins, v_spins, v_boxes
    ) returning * into claim_row;

    insert into public.delivery_market_coin_wallets(user_id, balance)
      values(uid, v_coins)
      on conflict(user_id) do update set
        balance = public.delivery_market_coin_wallets.balance + excluded.balance,
        updated_at = now();
    insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
      values(uid, v_coins, 'promo_checkin', claim_row.id);

    return public.delivery_promo_status_payload(uid, op) || jsonb_build_object(
      'reward', jsonb_build_object(
        'id', claim_row.id,
        'event_kind', claim_row.event_kind,
        'rarity', claim_row.rarity,
        'title', claim_row.title,
        'summary', claim_row.summary,
        'coins_delta', claim_row.coins_delta,
        'spin_tickets_delta', claim_row.spin_tickets_delta,
        'box_tickets_delta', claim_row.box_tickets_delta,
        'voucher_code', null
      )
    );

  elsif p_action = 'claim_mission' then
    v_mission := btrim(coalesce(d->>'mission_id', ''));
    if v_mission not in ('first_shipping', 'first_market', 'green_ev', 'three_orders') then
      raise sqlstate 'PT400' using message = 'Nhiệm vụ không hợp lệ.';
    end if;
    if coalesce(w.claimed_missions, '[]'::jsonb) ? v_mission then
      raise sqlstate 'PT409' using message = 'Nhiệm vụ này đã được nhận thưởng.';
    end if;

    select count(*)::integer into ship_done
      from public.delivery_cloud_orders co
      where co.owner_id = uid
        and co.status = 'delivered'
        and not exists(select 1 from public.delivery_market_shop_orders so where so.delivery_id = co.id)
        and not exists(select 1 from public.delivery_market_shipments ms where ms.delivery_id = co.id);

    select count(*)::integer into market_done
      from public.delivery_market_shop_orders so
      where so.owner_id = uid and so.delivered_at is not null and so.state <> 'cancelled';

    select count(*)::integer into ev_done
      from public.delivery_cloud_orders co
      where co.owner_id = uid and co.status = 'delivered'
        and coalesce((co.details->>'prefer_ev')::boolean, false);

    if v_mission = 'first_shipping' then
      v_eligible := ship_done >= 1;
      v_coins := 100; v_spins := 1; v_boxes := 0; v_rarity := 'Rare';
      v_title := 'Thưởng nhiệm vụ: Chuyến giao đầu tiên';
    elsif v_mission = 'first_market' then
      v_eligible := market_done >= 1;
      v_coins := 120; v_spins := 0; v_boxes := 1; v_rarity := 'Rare';
      v_title := 'Thưởng nhiệm vụ: Đơn Ăn uống đầu tiên';
    elsif v_mission = 'green_ev' then
      v_eligible := ev_done >= 1;
      v_coins := 150; v_spins := 1; v_boxes := 0; v_rarity := 'Rare';
      v_title := 'Thưởng nhiệm vụ: Giao hàng xanh EV';
    else
      v_eligible := (ship_done + market_done) >= 3;
      v_coins := 300; v_spins := 1; v_boxes := 1; v_rarity := 'Epic';
      v_title := 'Thưởng nhiệm vụ: Mốc 3 đơn hoàn tất';
    end if;

    if not v_eligible then
      raise sqlstate 'PT409' using message = 'Bạn chưa hoàn thành đủ điều kiện đơn hàng cho nhiệm vụ này.';
    end if;

    v_summary := '+' || v_coins || ' Xu'
      || case when v_spins > 0 then ' • +' || v_spins || ' Vé quay' else '' end
      || case when v_boxes > 0 then ' • +' || v_boxes || ' Vé hộp mù' else '' end;

    update public.delivery_promo_wallets set
      claimed_missions = coalesce(claimed_missions, '[]'::jsonb) || to_jsonb(v_mission),
      spin_tickets = spin_tickets + v_spins,
      blind_box_tickets = blind_box_tickets + v_boxes,
      updated_at = now()
      where user_id = uid;

    insert into public.delivery_promo_reward_claims(
      user_id, event_kind, rarity, title, summary, coins_delta, spin_tickets_delta, box_tickets_delta
    ) values (
      uid, 'mission', v_rarity, v_title, v_summary, v_coins, v_spins, v_boxes
    ) returning * into claim_row;

    insert into public.delivery_market_coin_wallets(user_id, balance)
      values(uid, v_coins)
      on conflict(user_id) do update set
        balance = public.delivery_market_coin_wallets.balance + excluded.balance,
        updated_at = now();
    insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
      values(uid, v_coins, 'promo_mission', claim_row.id);

    return public.delivery_promo_status_payload(uid, op) || jsonb_build_object(
      'reward', jsonb_build_object(
        'id', claim_row.id,
        'event_kind', claim_row.event_kind,
        'rarity', claim_row.rarity,
        'title', claim_row.title,
        'summary', claim_row.summary,
        'coins_delta', claim_row.coins_delta,
        'spin_tickets_delta', claim_row.spin_tickets_delta,
        'box_tickets_delta', claim_row.box_tickets_delta,
        'voucher_code', null
      )
    );

  elsif p_action = 'exchange_coins' then
    v_item := btrim(coalesce(d->>'item_id', ''));
    if v_item = 'spin_ticket' then
      v_cost := s.spin_ticket_coin_cost;
      v_spins := 1; v_rarity := 'Common';
      v_title := 'Đổi Xu lấy +1 Vé Vòng Xoay';
      v_summary := '-' || v_cost || ' Xu • +1 Vé Vòng Xoay May Mắn';
    elsif v_item = 'blind_box_ticket' then
      v_cost := s.box_ticket_coin_cost;
      v_boxes := 1; v_rarity := 'Rare';
      v_title := 'Đổi Xu lấy +1 Vé Hộp Mù';
      v_summary := '-' || v_cost || ' Xu • +1 Vé Hộp Mù Bí Ẩn';
    elsif v_item = 'voucher_20k' then
      v_cost := s.voucher_20k_coin_cost;
      v_rarity := 'Rare';
      v_title := 'Đổi Xu lấy Voucher 20.000đ';
    elsif v_item = 'voucher_40k' then
      v_cost := s.voucher_40k_coin_cost;
      v_rarity := 'Epic';
      v_title := 'Đổi Xu lấy Voucher 40.000đ';
    else
      raise sqlstate 'PT400' using message = 'Vật phẩm đổi Xu không hợp lệ.';
    end if;

    perform 1 from public.delivery_market_coin_wallets where user_id = uid for update;
    update public.delivery_market_coin_wallets
      set balance = balance - v_cost, updated_at = now()
      where user_id = uid and balance >= v_cost;
    if not found then
      raise sqlstate 'PT409' using message = 'Số dư Xu không đủ để đổi phần thưởng này.';
    end if;

    if v_item = 'voucher_20k' then
      v_minted := public.delivery_promo_mint_voucher(uid, 'XU20K', 'Voucher Đổi Xu Giảm 20.000đ', 'fixed', 20000, 20000, 80000, 7);
      v_summary := '-' || v_cost || ' Xu • Mã ' || v_minted.code || ' (đơn từ 80.000đ)';
    elsif v_item = 'voucher_40k' then
      v_minted := public.delivery_promo_mint_voucher(uid, 'XU40K', 'Voucher Đổi Xu Giảm 40.000đ', 'fixed', 40000, 40000, 150000, 7);
      v_summary := '-' || v_cost || ' Xu • Mã ' || v_minted.code || ' (đơn từ 150.000đ)';
    else
      update public.delivery_promo_wallets set
        spin_tickets = spin_tickets + v_spins,
        blind_box_tickets = blind_box_tickets + v_boxes,
        updated_at = now()
        where user_id = uid;
    end if;

    insert into public.delivery_promo_reward_claims(
      user_id, event_kind, rarity, title, summary, coins_delta,
      spin_tickets_delta, box_tickets_delta, voucher_id, voucher_code
    ) values (
      uid, 'exchange', v_rarity, v_title, v_summary, -v_cost,
      v_spins, v_boxes, v_minted.id, v_minted.code
    ) returning * into claim_row;

    insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
      values(uid, -v_cost, 'promo_exchange', claim_row.id);

    return public.delivery_promo_status_payload(uid, op) || jsonb_build_object(
      'reward', jsonb_build_object(
        'id', claim_row.id,
        'event_kind', claim_row.event_kind,
        'rarity', claim_row.rarity,
        'title', claim_row.title,
        'summary', claim_row.summary,
        'coins_delta', claim_row.coins_delta,
        'spin_tickets_delta', claim_row.spin_tickets_delta,
        'box_tickets_delta', claim_row.box_tickets_delta,
        'voucher_code', claim_row.voucher_code
      )
    );

  elsif p_action = 'spin_wheel' then
    if w.spin_tickets < 1 then
      raise sqlstate 'PT409' using message = 'Bạn chưa có Vé quay. Hãy điểm danh hoặc đổi Xu để nhận thêm vé.';
    end if;

    v_roll := floor(random() * 100)::integer;
    if v_roll < 28 then
      v_segment := 0; v_coins := 50; v_rarity := 'Common';
      v_title := 'Trúng +50 Xu';
      v_summary := 'Đã cộng trực tiếp +50 Xu vào Ví Xu của bạn.';
    elsif v_roll < 48 then
      v_segment := 1; v_rarity := 'Common';
      v_minted := public.delivery_promo_mint_voucher(uid, 'SPIN15', 'Vòng Xoay Giảm 15.000đ', 'fixed', 15000, 15000, 60000, 7);
      v_title := 'Trúng Voucher 15.000đ';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Đơn từ 60.000đ (7 ngày).';
    elsif v_roll < 60 then
      v_segment := 2; v_boxes := 1; v_rarity := 'Rare';
      v_title := 'Trúng +1 Vé Hộp Mù Bí Ẩn';
      v_summary := 'Đã cộng +1 Vé mở Hộp Mù Bí Ẩn vào kho vé của bạn.';
    elsif v_roll < 75 then
      v_segment := 3; v_coins := 150; v_rarity := 'Rare';
      v_title := 'Trúng +150 Xu';
      v_summary := 'Đã cộng trực tiếp +150 Xu vào Ví Xu của bạn.';
    elsif v_roll < 85 then
      v_segment := 4; v_rarity := 'Rare';
      v_minted := public.delivery_promo_mint_voucher(uid, 'SPIN25', 'Vòng Xoay Giảm 25.000đ', 'fixed', 25000, 25000, 99000, 7);
      v_title := 'Trúng Voucher 25.000đ';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Đơn từ 99.000đ (7 ngày).';
    elsif v_roll < 93 then
      v_segment := 5; v_coins := 30; v_rarity := 'Common';
      v_title := 'Lộc May Mắn +30 Xu';
      v_summary := 'Đã cộng +30 Xu lộc may mắn vào Ví Xu.';
    elsif v_roll < 98 then
      v_segment := 6; v_rarity := 'Epic';
      v_minted := public.delivery_promo_mint_voucher(uid, 'SPIN50P', 'Vòng Xoay Giảm 50% (Tối đa 35K)', 'percent', 50, 35000, 70000, 7);
      v_title := 'Trúng Deal Epic Giảm 50%';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Giảm 50% tối đa 35.000đ, đơn từ 70.000đ.';
    else
      v_segment := 7; v_rarity := 'Legendary';
      v_minted := public.delivery_promo_mint_voucher(uid, 'VIP50K', 'Vòng Xoay Siêu Cấp 50.000đ', 'fixed', 50000, 50000, 150000, 7);
      v_title := 'NỔ HŨ! Voucher Siêu Cấp 50.000đ';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Giảm 50.000đ cho đơn từ 150.000đ.';
    end if;

    update public.delivery_promo_wallets set
      spin_tickets = spin_tickets - 1,
      blind_box_tickets = blind_box_tickets + v_boxes,
      total_spins = total_spins + 1,
      updated_at = now()
      where user_id = uid and spin_tickets >= 1;
    if not found then
      raise sqlstate 'PT409' using message = 'Số vé quay không đủ.';
    end if;

    insert into public.delivery_promo_reward_claims(
      user_id, event_kind, rarity, title, summary, coins_delta,
      spin_tickets_delta, box_tickets_delta, voucher_id, voucher_code, wheel_segment
    ) values (
      uid, 'spin', v_rarity, v_title, v_summary, v_coins,
      -1, v_boxes, v_minted.id, v_minted.code, v_segment
    ) returning * into claim_row;

    if v_coins > 0 then
      insert into public.delivery_market_coin_wallets(user_id, balance)
        values(uid, v_coins)
        on conflict(user_id) do update set
          balance = public.delivery_market_coin_wallets.balance + excluded.balance,
          updated_at = now();
      insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
        values(uid, v_coins, 'promo_spin', claim_row.id);
    end if;

    return public.delivery_promo_status_payload(uid, op) || jsonb_build_object(
      'wheel_segment', v_segment,
      'reward', jsonb_build_object(
        'id', claim_row.id,
        'event_kind', claim_row.event_kind,
        'rarity', claim_row.rarity,
        'title', claim_row.title,
        'summary', claim_row.summary,
        'coins_delta', claim_row.coins_delta,
        'spin_tickets_delta', claim_row.spin_tickets_delta,
        'box_tickets_delta', claim_row.box_tickets_delta,
        'voucher_code', claim_row.voucher_code,
        'wheel_segment', v_segment
      )
    );

  elsif p_action = 'open_blind_box' then
    if jsonb_typeof(d->'box_index') <> 'number'
       or (d->>'box_index')::numeric <> trunc((d->>'box_index')::numeric)
       or (d->>'box_index')::integer not between 0 and 5 then
      raise sqlstate 'PT400' using message = 'Vị trí Hộp mù không hợp lệ.';
    end if;
    v_box_idx := (d->>'box_index')::integer;

    if w.opened_boxes ? v_box_idx::text then
      raise sqlstate 'PT409' using message = 'Hộp mù này đã được mở. Hãy chọn hộp khác hoặc làm mới khay hộp.';
    end if;
    if w.blind_box_tickets < 1 then
      raise sqlstate 'PT409' using message = 'Bạn chưa có Vé Hộp Mù. Hãy điểm danh, quay thưởng hoặc đổi Xu để nhận vé.';
    end if;

    v_roll := floor(random() * 100)::integer;
    if v_roll < 35 then
      v_rarity := 'R'; v_coins := 80;
      v_title := 'Hộp Mù [R]: +80 Xu';
      v_summary := 'Đã cộng trực tiếp +80 Xu vào Ví Xu.';
    elsif v_roll < 60 then
      v_rarity := 'R';
      v_minted := public.delivery_promo_mint_voucher(uid, 'BOX20K', 'Hộp Mù Giảm 20.000đ', 'fixed', 20000, 20000, 80000, 7);
      v_title := 'Hộp Mù [R]: Voucher 20.000đ';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Đơn từ 80.000đ (7 ngày).';
    elsif v_roll < 78 then
      v_rarity := 'SR'; v_coins := 60; v_spins := 1;
      v_title := 'Hộp Mù [SR]: +1 Vé Quay & +60 Xu';
      v_summary := 'Nhận combo +1 Vé Vòng Xoay May Mắn và +60 Xu.';
    elsif v_roll < 92 then
      v_rarity := 'SR';
      v_minted := public.delivery_promo_mint_voucher(uid, 'BOX35K', 'Hộp Mù SR Giảm 35.000đ', 'fixed', 35000, 35000, 120000, 7);
      v_title := 'Hộp Mù [SR]: Voucher 35.000đ';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Đơn từ 120.000đ (7 ngày).';
    elsif v_roll < 98 then
      v_rarity := 'SSR'; v_coins := 300;
      v_title := 'Hộp Mù [SSR]: Kho Báu +300 Xu!';
      v_summary := 'Đại thắng! Đã cộng +300 Xu vào Ví Xu.';
    else
      v_rarity := 'SSR';
      v_minted := public.delivery_promo_mint_voucher(uid, 'SSR60K', 'Hộp Mù SSR Giảm 60.000đ', 'fixed', 60000, 60000, 180000, 7);
      v_title := 'Hộp Mù [SSR]: Siêu Voucher 60.000đ!';
      v_summary := 'Mã cá nhân ' || v_minted.code || ' • Giảm 60.000đ cho đơn từ 180.000đ.';
    end if;

    update public.delivery_promo_wallets set
      blind_box_tickets = blind_box_tickets - 1,
      spin_tickets = spin_tickets + v_spins,
      total_boxes_opened = total_boxes_opened + 1,
      opened_boxes = w.opened_boxes || jsonb_build_object(
        v_box_idx::text,
        jsonb_build_object(
          'rarity', v_rarity,
          'title', v_title,
          'summary', v_summary,
          'voucher_code', v_minted.code,
          'opened_at', now()
        )
      ),
      updated_at = now()
      where user_id = uid and blind_box_tickets >= 1;
    if not found then
      raise sqlstate 'PT409' using message = 'Số vé Hộp mù không đủ.';
    end if;

    insert into public.delivery_promo_reward_claims(
      user_id, event_kind, rarity, title, summary, coins_delta,
      spin_tickets_delta, box_tickets_delta, voucher_id, voucher_code, box_index
    ) values (
      uid, 'blind_box', v_rarity, v_title, v_summary, v_coins,
      v_spins, -1, v_minted.id, v_minted.code, v_box_idx
    ) returning * into claim_row;

    if v_coins > 0 then
      insert into public.delivery_market_coin_wallets(user_id, balance)
        values(uid, v_coins)
        on conflict(user_id) do update set
          balance = public.delivery_market_coin_wallets.balance + excluded.balance,
          updated_at = now();
      insert into public.delivery_market_coin_ledger(user_id, delta, kind, reference_id)
        values(uid, v_coins, 'promo_blind_box', claim_row.id);
    end if;

    return public.delivery_promo_status_payload(uid, op) || jsonb_build_object(
      'box_index', v_box_idx,
      'reward', jsonb_build_object(
        'id', claim_row.id,
        'event_kind', claim_row.event_kind,
        'rarity', claim_row.rarity,
        'title', claim_row.title,
        'summary', claim_row.summary,
        'coins_delta', claim_row.coins_delta,
        'spin_tickets_delta', claim_row.spin_tickets_delta,
        'box_tickets_delta', claim_row.box_tickets_delta,
        'voucher_code', claim_row.voucher_code,
        'box_index', v_box_idx
      )
    );

  elsif p_action = 'reset_blind_boxes' then
    update public.delivery_promo_wallets
      set opened_boxes = '{}'::jsonb, updated_at = now()
      where user_id = uid;
    return public.delivery_promo_status_payload(uid, op);

  else
    raise sqlstate 'PT400' using message = 'Thao tác sự kiện khuyến mãi không được hỗ trợ.';
  end if;
end $$;

revoke all on function public.delivery_cloud_promo_events(text,jsonb) from public, anon;
grant execute on function public.delivery_cloud_promo_events(text,jsonb) to authenticated;

commit;
