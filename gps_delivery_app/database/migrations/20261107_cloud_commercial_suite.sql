-- Additive Cloud Commercial Suite (P1-P6). Safe to reapply; zero demo/fake rows seeded.
begin;

-- P1: Shop cover, service radius, staff delegation, multi-SKU variants, parcel dimensions
alter table public.delivery_market_shops
  add column if not exists banner_url text not null default '' check(length(banner_url)<=1000 and (banner_url='' or banner_url ~ '^https://')),
  add column if not exists service_radius_km numeric not null default 0 check(service_radius_km between 0 and 200);

alter table public.delivery_market_products
  add column if not exists length_cm numeric not null default 0 check(length_cm between 0 and 300),
  add column if not exists width_cm numeric not null default 0 check(width_cm between 0 and 300),
  add column if not exists height_cm numeric not null default 0 check(height_cm between 0 and 300);

create table if not exists public.delivery_market_shop_staff (
  shop_id uuid not null references public.delivery_market_shops(id) on delete cascade,
  user_id uuid not null references public.delivery_cloud_accounts(user_id) on delete cascade,
  role text not null check(role in ('manager','staff')),
  active boolean not null default true,
  version integer not null default 1 check(version>0),
  added_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(shop_id,user_id)
);
create index if not exists delivery_market_shop_staff_user on public.delivery_market_shop_staff(user_id) where active;

create table if not exists public.delivery_market_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.delivery_market_products(id) on delete cascade,
  sku text not null check(length(sku) between 1 and 80),
  title text not null check(length(title) between 1 and 120),
  price integer not null check(price between 1 and 10000000),
  stock integer not null check(stock between 0 and 1000000),
  weight_kg numeric not null check(weight_kg between 0.01 and 30),
  length_cm numeric not null default 0 check(length_cm between 0 and 300),
  width_cm numeric not null default 0 check(width_cm between 0 and 300),
  height_cm numeric not null default 0 check(height_cm between 0 and 300),
  published boolean not null default true,
  version integer not null default 1 check(version>0),
  terms_version integer not null default 1 check(terms_version>0),
  updated_at timestamptz not null default now(),
  unique(product_id,sku)
);
create index if not exists delivery_market_variants_product on public.delivery_market_variants(product_id,id);

create or replace function public.delivery_market_variant_terms() returns trigger
language plpgsql set search_path='' as $$
begin
  if (to_jsonb(new)-array['stock','version','updated_at','terms_version']) is distinct from
    (to_jsonb(old)-array['stock','version','updated_at','terms_version']) then new.terms_version:=old.terms_version+1;
  else new.terms_version:=old.terms_version;
  end if;
  return new;
end $$;
revoke all on function public.delivery_market_variant_terms() from public,anon,authenticated;
drop trigger if exists delivery_market_variant_terms on public.delivery_market_variants;
create trigger delivery_market_variant_terms before update on public.delivery_market_variants
  for each row execute function public.delivery_market_variant_terms();

alter table public.delivery_market_cart_items add column if not exists variant_id uuid references public.delivery_market_variants(id);
alter table public.delivery_market_stock add column if not exists variant_id uuid references public.delivery_market_variants(id);

-- P3: Prepaid multi-shop checkout & provider finance reconciliation
alter table public.delivery_market_purchases drop constraint if exists delivery_market_purchases_payment_method_check;
alter table public.delivery_market_purchases add constraint delivery_market_purchases_payment_method_check
  check(payment_method in ('cod','prepaid'));

alter table public.delivery_payment_transactions alter column order_id drop not null;
alter table public.delivery_payment_transactions add column if not exists purchase_id uuid references public.delivery_market_purchases(id);
alter table public.delivery_payment_transactions drop constraint if exists delivery_payment_target_check;
alter table public.delivery_payment_transactions add constraint delivery_payment_target_check
  check((order_id is not null and purchase_id is null) or (order_id is null and purchase_id is not null));
create index if not exists delivery_payment_purchase on public.delivery_payment_transactions(purchase_id,created_at desc) where purchase_id is not null;
create unique index if not exists delivery_payment_purchase_active on public.delivery_payment_transactions(purchase_id)
  where purchase_id is not null and status in ('CREATING','PENDING','PAID','REVIEW');

alter table public.delivery_market_finance add column if not exists source text not null default 'manual' check(source in ('manual','provider'));
alter table public.delivery_market_finance drop constraint if exists delivery_market_finance_check;
alter table public.delivery_market_finance drop constraint if exists delivery_market_finance_check1;
alter table public.delivery_market_finance add constraint delivery_market_finance_check check(approver is null or approver<>proposer);
alter table public.delivery_market_finance add constraint delivery_market_finance_check1
  check(state<>'completed' or ((source='provider' or approver is not null) and length(completion_evidence) between 3 and 500));

alter table public.delivery_market_ledger drop constraint if exists delivery_market_ledger_account_check;
alter table public.delivery_market_ledger add constraint delivery_market_ledger_account_check
  check(account in ('cash_clearing','merchant_payable','shipping_revenue','promo_expense'));

-- P4: Multi-parcel split shipments, recipient OTP gate, cloud standalone shares
create table if not exists public.delivery_market_shipments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.delivery_market_shop_orders(id) on delete cascade,
  delivery_id uuid not null unique references public.delivery_cloud_orders(id),
  parcel_index integer not null check(parcel_index between 1 and 20),
  items jsonb not null default '[]',
  weight_kg numeric not null check(weight_kg between 0.01 and 500),
  cod_amount integer not null default 0 check(cod_amount between 0 and 20000000),
  created_at timestamptz not null default now(),
  unique(order_id,parcel_index)
);
create index if not exists delivery_market_shipments_order on public.delivery_market_shipments(order_id,parcel_index);

create table if not exists public.delivery_cloud_order_secrets (
  order_id uuid primary key references public.delivery_cloud_orders(id) on delete cascade,
  otp_code text not null check(otp_code ~ '^[0-9]{6}$'),
  otp_hash text not null,
  verified_at timestamptz,
  attempts integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.delivery_cloud_shares (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.delivery_cloud_orders(id) on delete cascade,
  owner_id uuid not null references auth.users(id),
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists delivery_cloud_shares_order on public.delivery_cloud_shares(order_id,created_at desc);

-- P5: Private evidence attachments, return logistics & disposition, partner reviews, shop follows
create table if not exists public.delivery_market_attachments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  scope text not null check(scope in ('chat','return','finance')),
  order_id uuid not null references public.delivery_market_shop_orders(id) on delete cascade,
  owner_id uuid not null references auth.users(id),
  content_hash text not null check(content_hash ~ '^[a-f0-9]{64}$'),
  byte_size integer not null check(byte_size between 1 and 5000000),
  created_at timestamptz not null default now(),
  upload_until timestamptz not null default (now()+interval '15 minutes'),
  unique(order_id,scope,content_hash)
);
create index if not exists delivery_market_attachments_order on public.delivery_market_attachments(order_id,created_at);

alter table public.delivery_market_messages add column if not exists attachments jsonb not null default '[]';
alter table public.delivery_market_returns
  add column if not exists attachments jsonb not null default '[]',
  add column if not exists return_delivery_id uuid references public.delivery_cloud_orders(id),
  add column if not exists disposition text check(disposition in ('restock','writeoff')),
  add column if not exists variant_id uuid references public.delivery_market_variants(id);
alter table public.delivery_market_finance add column if not exists attachments jsonb not null default '[]';

alter table public.delivery_market_reviews
  add column if not exists reply text not null default '' check(length(reply)<=1000),
  add column if not exists replied_at timestamptz,
  add column if not exists report_count integer not null default 0 check(report_count>=0);

create table if not exists public.delivery_partner_reviews (
  id uuid primary key default gen_random_uuid(),
  target_kind text not null check(target_kind in ('shop','driver')),
  shop_order_id uuid references public.delivery_market_shop_orders(id),
  cloud_order_id uuid references public.delivery_cloud_orders(id),
  shop_id uuid references public.delivery_market_shops(id),
  driver_id uuid references public.delivery_cloud_accounts(user_id),
  reviewer_id uuid not null references auth.users(id),
  rating integer not null check(rating between 1 and 5),
  body text not null check(length(body) between 3 and 2000),
  reply text not null default '' check(length(reply)<=1000),
  replied_at timestamptz,
  report_count integer not null default 0 check(report_count>=0),
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  check((target_kind='shop' and shop_order_id is not null and shop_id is not null and driver_id is null) or
        (target_kind='driver' and cloud_order_id is not null and driver_id is not null))
);
create unique index if not exists delivery_partner_reviews_shop_order on public.delivery_partner_reviews(shop_order_id) where target_kind='shop';
create unique index if not exists delivery_partner_reviews_driver_order on public.delivery_partner_reviews(cloud_order_id,reviewer_id) where target_kind='driver';
create index if not exists delivery_partner_reviews_shop on public.delivery_partner_reviews(shop_id,created_at desc) where target_kind='shop' and not hidden;
create index if not exists delivery_partner_reviews_driver on public.delivery_partner_reviews(driver_id,created_at desc) where target_kind='driver' and not hidden;

create table if not exists public.delivery_market_review_reports (
  review_kind text not null check(review_kind in ('product','partner')),
  review_id uuid not null,
  reporter_id uuid not null references auth.users(id),
  reason text not null check(length(reason) between 3 and 500),
  created_at timestamptz not null default now(),
  primary key(review_kind,review_id,reporter_id)
);

create table if not exists public.delivery_market_shop_follows (
  user_id uuid not null references auth.users(id) on delete cascade,
  shop_id uuid not null references public.delivery_market_shops(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id,shop_id)
);
create index if not exists delivery_market_shop_follows_shop on public.delivery_market_shop_follows(shop_id);

-- P6: Funded server vouchers, flash sales & coin ledger
create table if not exists public.delivery_market_vouchers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check(code ~ '^[A-Z0-9_-]{3,32}$'),
  shop_id uuid references public.delivery_market_shops(id) on delete cascade,
  title text not null check(length(title) between 1 and 120),
  discount_kind text not null check(discount_kind in ('fixed','percent')),
  discount_value integer not null check(discount_value between 1 and 5000000 and (discount_kind='fixed' or discount_value<=90)),
  max_discount integer not null check(max_discount between 1 and 5000000),
  min_subtotal integer not null default 0 check(min_subtotal between 0 and 20000000),
  budget_total bigint not null check(budget_total between 1 and 1000000000),
  budget_used bigint not null default 0 check(budget_used>=0 and budget_used<=budget_total),
  per_user_limit integer not null default 1 check(per_user_limit between 1 and 20),
  starts_at timestamptz not null,
  ends_at timestamptz not null check(ends_at>starts_at),
  active boolean not null default true,
  version integer not null default 1 check(version>0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_market_vouchers_active on public.delivery_market_vouchers(shop_id,ends_at) where active;

create table if not exists public.delivery_market_voucher_usages (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.delivery_market_vouchers(id),
  purchase_id uuid not null references public.delivery_market_purchases(id),
  order_id uuid references public.delivery_market_shop_orders(id),
  user_id uuid not null references auth.users(id),
  discount_amount integer not null check(discount_amount between 1 and 5000000),
  state text not null default 'allocated' check(state in ('allocated','released')),
  created_at timestamptz not null default now(),
  released_at timestamptz
);
create index if not exists delivery_market_voucher_usages_user on public.delivery_market_voucher_usages(voucher_id,user_id) where state='allocated';
create index if not exists delivery_market_voucher_usages_order on public.delivery_market_voucher_usages(order_id) where state='allocated';

create table if not exists public.delivery_market_flash_sales (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.delivery_market_products(id) on delete cascade,
  shop_id uuid not null references public.delivery_market_shops(id) on delete cascade,
  sale_price integer not null check(sale_price between 1 and 10000000),
  allocated_stock integer not null check(allocated_stock between 1 and 100000),
  sold_stock integer not null default 0 check(sold_stock>=0 and sold_stock<=allocated_stock),
  per_user_limit integer not null default 2 check(per_user_limit between 1 and 20),
  starts_at timestamptz not null,
  ends_at timestamptz not null check(ends_at>starts_at),
  active boolean not null default true,
  version integer not null default 1 check(version>0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_market_flash_sales_product on public.delivery_market_flash_sales(product_id,ends_at) where active;

create table if not exists public.delivery_market_flash_claims (
  id uuid primary key default gen_random_uuid(),
  flash_sale_id uuid not null references public.delivery_market_flash_sales(id),
  order_id uuid not null references public.delivery_market_shop_orders(id),
  user_id uuid not null references auth.users(id),
  quantity integer not null check(quantity between 1 and 20),
  state text not null default 'allocated' check(state in ('allocated','released')),
  created_at timestamptz not null default now(),
  released_at timestamptz
);
create index if not exists delivery_market_flash_claims_user on public.delivery_market_flash_claims(flash_sale_id,user_id) where state='allocated';
create index if not exists delivery_market_flash_claims_order on public.delivery_market_flash_claims(order_id) where state='allocated';

create table if not exists public.delivery_market_coin_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance bigint not null default 0 check(balance>=0),
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_market_coin_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta bigint not null check(delta<>0),
  kind text not null check(kind in ('earn_settlement','redeem_checkout','release_cancel','reverse_refund')),
  reference_id uuid not null,
  created_at timestamptz not null default now(),
  unique(user_id,kind,reference_id)
);
drop trigger if exists immutable on public.delivery_market_coin_ledger;
create trigger immutable before update or delete on public.delivery_market_coin_ledger
  for each row execute function public.delivery_market_immutable();

do $$ declare t text; begin
  foreach t in array array[
    'delivery_market_shop_staff','delivery_market_variants','delivery_market_shipments',
    'delivery_cloud_order_secrets','delivery_cloud_shares','delivery_market_attachments',
    'delivery_partner_reviews','delivery_market_review_reports','delivery_market_shop_follows',
    'delivery_market_vouchers','delivery_market_voucher_usages','delivery_market_flash_sales',
    'delivery_market_flash_claims','delivery_market_coin_wallets','delivery_market_coin_ledger'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
  end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('delivery-evidence','delivery-evidence',false,5000000,array['image/jpeg','image/png','image/webp'])
  on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('delivery-private-evidence','delivery-private-evidence',false,5000000,array['image/webp'])
  on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Shop ownership & staff delegation check
create or replace function public.delivery_market_can_access_shop(p_shop uuid,p_user uuid,p_min_role text default 'staff') returns boolean
language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.delivery_market_shops s
    join public.delivery_cloud_accounts oa on oa.user_id=s.owner_id
    where s.id=p_shop and not oa.blocked and public.delivery_cloud_has_membership(s.owner_id,'merchant')
      and (
        (s.owner_id=p_user and p_min_role in ('owner','manager','staff'))
        or (
          p_min_role in ('manager','staff') and exists(
            select 1 from public.delivery_market_shop_staff st
            join public.delivery_cloud_accounts ua on ua.user_id=st.user_id
            where st.shop_id=s.id and st.user_id=p_user and st.active and not ua.blocked
              and (p_min_role='staff' or st.role='manager')
          )
        )
      )
  );
$$;
revoke all on function public.delivery_market_can_access_shop(uuid,uuid,text) from public,anon,authenticated;

create or replace function public.delivery_cloud_account_snapshot(p_user uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(a)||jsonb_build_object(
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
    'coin_balance',coalesce((select balance from public.delivery_market_coin_wallets w where w.user_id=a.user_id),0))
  from public.delivery_cloud_accounts a where a.user_id=p_user;
$$;
revoke all on function public.delivery_cloud_account_snapshot(uuid) from public,anon,authenticated;

-- Update product media reserve to also allow delegated shop managers
create or replace function public.delivery_market_media_reserve(p_shop uuid,p_hash text,p_bytes integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.delivery_market_shops; m public.delivery_market_media;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if not public.delivery_market_can_access_shop(p_shop,auth.uid(),'manager') then
    raise sqlstate 'PT403' using message='Cần quyền chủ cửa hàng hoặc quản lý cửa hàng.';
  end if;
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or p_bytes is null or p_bytes not between 1 and 5000000 then
    raise sqlstate 'PT400' using message='Ảnh không hợp lệ.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('market-media-budget',0));
  select * into s from public.delivery_market_shops where id=p_shop for update;
  if not found or s.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền tải ảnh cho cửa hàng này.'; end if;
  select * into m from public.delivery_market_media where shop_id=s.id and content_hash=p_hash;
  if found then
    if m.byte_size<>p_bytes then raise sqlstate 'PT409' using message='Nội dung ảnh đã thay đổi.'; end if;
    update public.delivery_market_media set owner_id=auth.uid(),upload_until=now()+interval '15 minutes' where name=m.name returning * into m;
  else
    if (select coalesce(sum(byte_size),0) from public.delivery_market_media)+p_bytes>500000000
      or (select coalesce(sum(byte_size),0) from public.delivery_market_media where shop_id=s.id)+p_bytes>100000000
      or (select count(*) from public.delivery_market_media where shop_id=s.id and created_at>now()-interval '1 hour')>=60
      or (select count(*) from public.delivery_market_media where shop_id=s.id)>=2000 then
      raise sqlstate 'PT409' using message='Cửa hàng đã đạt giới hạn ảnh. Vui lòng liên hệ hỗ trợ.';
    end if;
    insert into public.delivery_market_media(name,shop_id,owner_id,content_hash,byte_size)
      values(auth.uid()::text||'/'||s.id::text||'/'||p_hash||'.webp',s.id,auth.uid(),p_hash,p_bytes) returning * into m;
  end if;
  return jsonb_build_object('name',m.name,'bucket','delivery-market-media');
end $$;

create or replace function public.delivery_market_media_can_upload(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_market_media m
    join public.delivery_market_shops s on s.id=m.shop_id join public.delivery_cloud_accounts a on a.user_id=m.owner_id
    where m.name=p_name and m.owner_id=auth.uid() and s.status<>'suspended'
      and m.upload_until>now() and not a.blocked and public.delivery_market_can_access_shop(s.id,auth.uid(),'manager'));
$$;

-- Server-side GPS jump guard (<= 120 km/h and <= 30m at non-positive dt) + POD check
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

-- Recipient OTP read (sender/buyer or operator only; never driver)
create or replace function public.delivery_cloud_order_otp(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.delivery_cloud_orders; s public.delivery_cloud_order_secrets;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into o from public.delivery_cloud_orders where id=p_order;
  if not found or (not public.delivery_is_operator() and auth.uid() not in (o.owner_id,coalesce(o.merchant_id,o.owner_id))) then
    raise sqlstate 'PT403' using message='Chỉ người đặt đơn hoặc quản trị viên được xem mã OTP nhận hàng.';
  end if;
  select * into s from public.delivery_cloud_order_secrets where order_id=o.id;
  if not found then return jsonb_build_object('required',false,'otp_code',null,'verified_at',null); end if;
  return jsonb_build_object('required',true,'otp_code',s.otp_code,'verified_at',s.verified_at);
end $$;

-- Standalone cloud order share management & public tracking lookup
create or replace function public.delivery_cloud_share_manage(p_order uuid,p_action text default 'list',p_share uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.delivery_cloud_orders; token text; k uuid;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into o from public.delivery_cloud_orders where id=p_order for update;
  if not found or (not public.delivery_is_operator() and auth.uid() not in (o.owner_id,coalesce(o.merchant_id,o.owner_id))) then
    raise sqlstate 'PT403' using message='Chỉ chủ đơn hoặc cửa hàng quản lý liên kết chia sẻ.';
  end if;
  if p_action='revoke' then
    update public.delivery_cloud_shares set revoked_at=coalesce(revoked_at,now()) where order_id=o.id and id=p_share;
    return jsonb_build_object('ok',true);
  elsif p_action='create' then
    if (select count(*) from public.delivery_cloud_shares where order_id=o.id and revoked_at is null and expires_at>now())>=5 then
      raise sqlstate 'PT409' using message='Tối đa 5 liên kết chia sẻ còn hiệu lực.';
    end if;
    token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
    insert into public.delivery_cloud_shares(order_id,owner_id,token_hash,expires_at)
      values(o.id,auth.uid(),encode(sha256(convert_to(token,'UTF8')),'hex'),now()+interval '24 hours') returning id into k;
    return jsonb_build_object('id',k,'token',token,'expires_at',now()+interval '24 hours');
  elsif p_action='list' then
    return jsonb_build_object('shares',coalesce((select jsonb_agg(to_jsonb(s)-'token_hash'-'owner_id' order by created_at desc,id desc)
      from public.delivery_cloud_shares s where order_id=o.id and revoked_at is null and expires_at>now()),'[]'::jsonb));
  else raise sqlstate 'PT400' using message='Thao tác chia sẻ không hợp lệ.';
  end if;
end $$;

create or replace function public.delivery_market_public_tracking(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; th text;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise sqlstate 'PT404' using message='Liên kết không tồn tại hoặc hết hạn.'; end if;
  th:=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  select jsonb_build_object('shop_name',o.snapshot->>'shop_name','state',o.state,'delivery_status',d.status,'updated_at',o.updated_at,'expires_at',s.expires_at)
    into result from public.delivery_market_shares s join public.delivery_market_shop_orders o on o.id=s.order_id
    join public.delivery_cloud_accounts a on a.user_id=s.owner_id left join public.delivery_cloud_orders d on d.id=o.delivery_id
    where s.token_hash=th and s.expires_at>now() and s.revoked_at is null and not a.blocked;
  if result is null then
    select jsonb_build_object('shop_name',coalesce(m.full_name,'GHST Express'),'state',o.status,'delivery_status',o.status,'updated_at',o.updated_at,'expires_at',s.expires_at)
      into result from public.delivery_cloud_shares s join public.delivery_cloud_orders o on o.id=s.order_id
      join public.delivery_cloud_accounts a on a.user_id=s.owner_id left join public.delivery_cloud_accounts m on m.user_id=o.merchant_id
      where s.token_hash=th and s.expires_at>now() and s.revoked_at is null and not a.blocked;
  end if;
  if result is null then raise sqlstate 'PT404' using message='Liên kết không tồn tại hoặc hết hạn.'; end if;
  return result;
end$$;

create or replace function public.delivery_cloud_public_lookup(p_tracking_code text,p_phone_last4 text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare code text:=upper(btrim(coalesce(p_tracking_code,''))); o public.delivery_cloud_orders;
begin
  if code !~ '^CL-[A-F0-9]{32}$' or coalesce(p_phone_last4,'') !~ '^[0-9]{4}$' then
    raise sqlstate 'PT404' using message='Không tìm thấy vận đơn khớp mã vận đơn và 4 số cuối điện thoại.';
  end if;
  select * into o from public.delivery_cloud_orders
    where tracking_code=code and right(coalesce(details->>'recipient_phone',''),4)=p_phone_last4;
  if not found then
    raise sqlstate 'PT404' using message='Không tìm thấy vận đơn khớp mã vận đơn và 4 số cuối điện thoại.';
  end if;
  return jsonb_build_object(
    'tracking_code',o.tracking_code,
    'status',o.status,
    'service_type',coalesce(o.details->>'service_type','standard'),
    'distance_meters',o.distance_meters,
    'created_at',o.created_at,
    'updated_at',o.updated_at,
    'timeline',coalesce((select jsonb_agg(jsonb_build_object('action',h.action,'status',h.status,'created_at',h.created_at) order by h.version)
      from public.delivery_cloud_history h where h.order_id=o.id),'[]'::jsonb)
  );
end $$;

-- P2 & P4: Expanded 5-mode shipping quote, create & POD/OTP-gated transitions
create or replace function public.delivery_cloud_quote(p_details jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.delivery_cloud_pricing; a float8; leg_m integer; meters integer:=0; fee integer;
  weight numeric; vol_weight numeric:=0; eff_weight numeric; max_weight numeric;
  lat1 float8; lat2 float8; lng1 float8; lng2 float8; cur_lat float8; cur_lng float8;
  wp jsonb; wp_lat float8; wp_lng float8; stop_count integer:=0;
  l_cm numeric:=0; w_cm numeric:=0; h_cm numeric:=0;
  declared_val numeric:=0; is_round boolean:=false; prefer_ev boolean:=false; green_fund boolean:=false;
  service text; v_base integer; v_dist integer; v_weight integer; v_express integer:=0;
  v_stop integer:=0; v_round integer:=0; v_ins integer:=0; v_green integer:=0; v_per_km integer;
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
      raise sqlstate 'PT400' using message='Giá trị khai giá tối đa 30.000.000đ.';
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

  return jsonb_build_object(
    'shipping_fee',fee,
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

create or replace function public.delivery_cloud_create(p_details jsonb,p_request_key uuid,p_pricing_version integer,p_expected_fee integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.delivery_cloud_orders; a public.delivery_cloud_accounts; q jsonb; merchant uuid; saved jsonb;
  raw_bytes bytea; otp_val text;
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
  q:=public.delivery_cloud_quote(p_details);
  if octet_length(p_details::text)>12000 or p_details-array[
    'pickup_address','dropoff_address','recipient_name','recipient_phone','package_description',
    'pickup_lat','pickup_lng','dropoff_lat','dropoff_lng','weight_kg','cod_amount','service_type',
    'payment_method','merchant_id','length_cm','width_cm','height_cm','declared_value','extra_stops',
    'is_round_trip','prefer_ev','green_fund','scheduled_at','buyer_note','require_pod','require_otp'
  ] <> '{}'::jsonb then
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
  insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
    shipping_fee,cod_amount,pricing_version,merchant_ready)
  values(auth.uid(),merchant,p_request_key,saved,p_details,(q->>'distance_meters')::integer,
    (q->>'shipping_fee')::integer,(p_details->>'cod_amount')::integer,(q->>'pricing_version')::integer,merchant is null) returning * into o;
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

create or replace function public.delivery_cloud_transition(p_order uuid,p_action text,p_version integer,p_request_key uuid,p_reason text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.delivery_cloud_orders; a public.delivery_cloud_accounts; op boolean; next_status text;
  request jsonb; prior public.delivery_cloud_commands; response jsonb;
  secret public.delivery_cloud_order_secrets; candidate_otp text; history_reason text:=btrim(coalesce(p_reason,''));
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
  request:=jsonb_build_object('order',p_order,'action',p_action,'version',p_version,'reason',case when p_action='deliver' and p_reason ~ '^(OTP:)?[0-9]{6}$' then 'OTP_SUBMITTED' else p_reason end);
  select * into prior from public.delivery_cloud_commands where actor_id=auth.uid() and request_key=p_request_key;
  if found then
    if prior.request_payload<>request then raise sqlstate 'PT409' using message='Mã yêu cầu đã dùng cho nội dung khác.'; end if;
    return prior.response;
  end if;
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
    if p_action='deliver' and not op then
      if coalesce((o.details->>'require_pod')::boolean,false) and not exists(
        select 1 from public.delivery_live_events where room_id=o.tracking_code and kind='pod') then
        raise sqlstate 'PT409' using message='Cần tải ảnh bằng chứng giao hàng (POD) trước khi hoàn tất.';
      end if;
      select * into secret from public.delivery_cloud_order_secrets where order_id=o.id for update;
      if found and secret.verified_at is null then
        candidate_otp:=substring(btrim(p_reason) from '([0-9]{6})');
        if candidate_otp is null or encode(sha256(convert_to(candidate_otp,'UTF8')),'hex')<>secret.otp_hash then
          update public.delivery_cloud_order_secrets set attempts=attempts+1 where order_id=o.id;
          raise sqlstate 'PT409' using message='Cần mã OTP 6 số hợp lệ từ người nhận để hoàn tất giao hàng.';
        end if;
        update public.delivery_cloud_order_secrets set verified_at=now(),attempts=attempts+1 where order_id=o.id;
        history_reason:='Đã xác thực OTP người nhận';
      end if;
    elsif p_action='deliver' and history_reason ~ '^(OTP:)?[0-9]{6}$' then
      history_reason:='Đã xác thực giao hàng';
    end if;
  end if;
  update public.delivery_cloud_orders set status=next_status,driver_id=o.driver_id,merchant_ready=o.merchant_ready,
    cancel_reason=o.cancel_reason,version=version+1,updated_at=now() where id=o.id returning * into o;
  if p_action='claim' then insert into public.delivery_live_members values(o.tracking_code,auth.uid(),'driver')
    on conflict(room_id,user_id) do update set role='driver'; end if;
  insert into public.delivery_cloud_history(order_id,actor_id,action,status,version,reason)
    values(o.id,auth.uid(),p_action,o.status,o.version,history_reason);
  insert into public.delivery_live_events(room_id,kind,payload) values(o.tracking_code,'status',jsonb_build_object('status',o.status,'version',o.version));
  response:=to_jsonb(o)-'request_payload'-'request_key';
  insert into public.delivery_cloud_commands values(auth.uid(),p_request_key,request,response,now());
  return response;
end; $$;

-- Marketplace selection, cart, snapshot, allocation release, prepaid capture & core RPC
create or replace function public.delivery_market_selection_v2(
  p_product uuid,
  p_selected jsonb default '[]',
  p_variant uuid default null,
  p_qty integer default 1,
  p_user uuid default null
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.delivery_market_products; v public.delivery_market_variants; fs public.delivery_market_flash_sales;
  g jsonb; opt jsonb; chosen jsonb; normalized jsonb; snapshots jsonb:='[]';
  matched integer:=0; qty integer; base_price bigint; amount bigint; lid uuid;
  eff_sku text; eff_weight numeric; eff_l numeric; eff_w numeric; eff_h numeric; eff_terms integer;
  flash_id uuid:=null; claimed integer:=0;
begin
  if jsonb_typeof(p_selected) is distinct from 'array' or jsonb_array_length(p_selected)>72 or octet_length(p_selected::text)>12000 then
    raise sqlstate 'PT400' using message='Các lựa chọn không hợp lệ.'; end if;
  for chosen in select * from jsonb_array_elements(p_selected) loop
    if jsonb_typeof(chosen) is distinct from 'object' or chosen-array['group_id','option_id']<>'{}' or
      not(chosen?&array['group_id','option_id']) or jsonb_typeof(chosen->'group_id') is distinct from 'string' or
      jsonb_typeof(chosen->'option_id') is distinct from 'string' then raise sqlstate 'PT400' using message='Lựa chọn chứa dữ liệu không hợp lệ.'; end if;
  end loop;
  if (select count(*)<>count(distinct (s->>'group_id',s->>'option_id')) from jsonb_array_elements(p_selected) s) then
    raise sqlstate 'PT400' using message='Lựa chọn bị trùng.'; end if;
  select coalesce(jsonb_agg(s order by s->>'group_id',s->>'option_id'),'[]') into normalized from jsonb_array_elements(p_selected) s;
  select * into p from public.delivery_market_products where id=p_product;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;

  if p_variant is not null then
    select * into v from public.delivery_market_variants where id=p_variant and product_id=p.id and published;
    if not found then raise sqlstate 'PT409' using message='Biến thể sản phẩm không còn khả dụng.'; end if;
    base_price:=v.price; eff_sku:=v.sku; eff_weight:=v.weight_kg;
    eff_l:=case when v.length_cm>0 then v.length_cm else p.length_cm end;
    eff_w:=case when v.width_cm>0 then v.width_cm else p.width_cm end;
    eff_h:=case when v.height_cm>0 then v.height_cm else p.height_cm end;
    eff_terms:=p.terms_version+v.terms_version-1;
  else
    base_price:=p.price; eff_sku:=p.sku; eff_weight:=p.weight_kg;
    eff_l:=p.length_cm; eff_w:=p.width_cm; eff_h:=p.height_cm;
    eff_terms:=p.terms_version;
  end if;

  select * into fs from public.delivery_market_flash_sales
    where product_id=p.id and active and starts_at<=now() and ends_at>now()
      and sold_stock+greatest(1,coalesce(p_qty,1))<=allocated_stock
    order by sale_price asc,id asc limit 1;
  if found then
    if p_user is not null then
      select coalesce(sum(quantity),0) into claimed from public.delivery_market_flash_claims
        where flash_sale_id=fs.id and user_id=p_user and state='allocated';
    end if;
    if claimed+greatest(1,coalesce(p_qty,1))<=fs.per_user_limit and fs.sale_price<base_price then
      base_price:=fs.sale_price; flash_id:=fs.id;
    end if;
  end if;

  amount:=base_price;
  for g in select * from jsonb_array_elements(p.option_groups) loop
    select count(*) into qty from jsonb_array_elements(normalized) s where s->>'group_id'=g->>'id';
    if qty<(g->>'min')::integer or qty>(g->>'max')::integer then raise sqlstate 'PT409' using message='Cần chọn đúng số lượng cho '||(g->>'name')||'.'; end if;
    for opt in select * from jsonb_array_elements(g->'options') o where exists(
      select 1 from jsonb_array_elements(normalized) s where s->>'group_id'=g->>'id' and s->>'option_id'=o->>'id') order by o->>'id' loop
      matched:=matched+1; amount:=amount+(opt->>'price')::integer;
      snapshots:=snapshots||jsonb_build_array(jsonb_build_object('group_id',g->>'id','group_name',g->>'name',
        'option_id',opt->>'id','name',opt->>'name','price',opt->'price'));
    end loop;
  end loop;
  if matched<>jsonb_array_length(normalized) or amount>10000000 then raise sqlstate 'PT409' using message='Lựa chọn đã thay đổi hoặc vượt giới hạn giá.'; end if;
  lid:=case
    when p_variant is not null then md5(p.id::text||':v:'||p_variant::text||':'||normalized::text)::uuid
    when normalized='[]'::jsonb then p.id
    else md5(p.id::text||':'||normalized::text)::uuid end;
  return jsonb_build_object(
    'line_id',lid,'selected_options',normalized,'options',snapshots,'unit_price',amount,
    'variant_id',p_variant,'variant_title',v.title,'effective_sku',eff_sku,
    'effective_weight_kg',eff_weight,'length_cm',eff_l,'width_cm',eff_w,'height_cm',eff_h,
    'effective_terms_version',eff_terms,'flash_sale_id',flash_id
  );
end$$;
revoke all on function public.delivery_market_selection_v2(uuid,jsonb,uuid,integer,uuid) from public,anon,authenticated;

create or replace function public.delivery_market_selection(p_product uuid,p_selected jsonb default '[]') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare sel jsonb;
begin
  sel:=public.delivery_market_selection_v2(p_product,p_selected,null,1,auth.uid());
  return jsonb_build_object('line_id',sel->'line_id','selected_options',sel->'selected_options',
    'options',sel->'options','unit_price',sel->'unit_price');
end$$;
revoke all on function public.delivery_market_selection(uuid,jsonb) from public,anon,authenticated;

create or replace function public.delivery_market_configured_cart() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]'; row record; sel jsonb; available boolean; cv integer; stock_ok boolean;
begin
  select version into cv from public.delivery_market_carts where user_id=auth.uid();
  for row in select p.*,c.line_id,c.selected_options,c.variant_id,c.quantity,s.name as shop_name,s.status as shop_status,s.paused,
    s.opening_schedule,m.blocked as merchant_blocked,public.delivery_cloud_has_membership(m.user_id,'merchant') as merchant_active
    from public.delivery_market_cart_items c join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
    where c.user_id=auth.uid() order by p.shop_id,c.line_id loop
    begin
      sel:=public.delivery_market_selection_v2(row.id,row.selected_options,row.variant_id,row.quantity,auth.uid());
      if row.variant_id is not null then
        stock_ok:=exists(select 1 from public.delivery_market_variants v where v.id=row.variant_id and v.product_id=row.id and v.published and
          v.stock>=(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and variant_id=row.variant_id));
      else
        stock_ok:=row.stock>=(select coalesce(sum(quantity),0) from public.delivery_market_cart_items where user_id=auth.uid() and product_id=row.id and variant_id is null);
      end if;
      available:=row.published and row.shop_status='active' and not row.paused and not row.merchant_blocked and row.merchant_active and
        public.delivery_market_is_open(row.opening_schedule) and public.delivery_market_is_open(row.sale_schedule) and stock_ok;
    exception when sqlstate 'PT409' or sqlstate 'PT404' then
      sel:=jsonb_build_object('unit_price',null,'options','[]'::jsonb,'variant_title',null,'flash_sale_id',null);
      available:=false;
    end;
    result:=result||jsonb_build_array(
      (to_jsonb(row)-array['merchant_blocked','merchant_active','opening_schedule'])||
      jsonb_build_object('unit_price',sel->'unit_price','options',sel->'options','available',available)||
      case when row.variant_id is not null then jsonb_build_object('variant_id',row.variant_id,'variant_title',sel->'variant_title','sku',coalesce(sel->>'effective_sku',row.sku)) else '{}'::jsonb end||
      case when sel->'flash_sale_id' is not null and jsonb_typeof(sel->'flash_sale_id')<>'null' then jsonb_build_object('flash_sale_id',sel->'flash_sale_id') else '{}'::jsonb end
    );
  end loop;
  return jsonb_build_object('version',coalesce(cv,1),'items',result);
end$$;
revoke all on function public.delivery_market_configured_cart() from public,anon,authenticated;

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
      where code=v_code and active and starts_at<=now() and ends_at>now();
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

create or replace function public.delivery_market_snapshot(p_address uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  return public.delivery_market_snapshot_v2(p_address,'{}'::jsonb);
end$$;
revoke all on function public.delivery_market_snapshot(uuid) from public,anon,authenticated;

-- Atomic release of product/variant stock, voucher budget, flash-sale claims & redeemed coins
create or replace function public.delivery_market_release_order_allocations(
  p_order public.delivery_market_shop_orders,
  p_actor uuid,
  p_source text,
  p_reason text
) returns void
language plpgsql security definer set search_path='' as $$
declare item jsonb; vu record; fc record; coin_refund bigint:=0;
begin
  perform 1 from public.delivery_market_products where id in
    (select (i->>'product_id')::uuid from jsonb_array_elements(p_order.snapshot->'items') i) order by id for update;
  perform 1 from public.delivery_market_variants where id in
    (select (i->>'variant_id')::uuid from jsonb_array_elements(p_order.snapshot->'items') i where i ? 'variant_id' and jsonb_typeof(i->'variant_id')='string') order by id for update;

  for item in select * from jsonb_array_elements(p_order.snapshot->'items') loop
    if item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then
      update public.delivery_market_variants set stock=stock+(item->>'quantity')::integer,version=version+1,updated_at=now()
        where id=(item->>'variant_id')::uuid;
      insert into public.delivery_market_stock(product_id,variant_id,actor_id,actor_source,delta,reason,reference_id)
        values((item->>'product_id')::uuid,(item->>'variant_id')::uuid,p_actor,p_source,(item->>'quantity')::integer,p_reason,p_order.id);
    else
      update public.delivery_market_products set stock=stock+(item->>'quantity')::integer,version=version+1,updated_at=now()
        where id=(item->>'product_id')::uuid;
      insert into public.delivery_market_stock(product_id,actor_id,actor_source,delta,reason,reference_id)
        values((item->>'product_id')::uuid,p_actor,p_source,(item->>'quantity')::integer,p_reason,p_order.id);
    end if;
  end loop;

  for vu in select * from public.delivery_market_voucher_usages where order_id=p_order.id and state='allocated' for update loop
    update public.delivery_market_voucher_usages set state='released',released_at=now() where id=vu.id;
    update public.delivery_market_vouchers set budget_used=greatest(0,budget_used-vu.discount_amount),version=version+1,updated_at=now() where id=vu.voucher_id;
  end loop;

  for fc in select * from public.delivery_market_flash_claims where order_id=p_order.id and state='allocated' for update loop
    update public.delivery_market_flash_claims set state='released',released_at=now() where id=fc.id;
    update public.delivery_market_flash_sales set sold_stock=greatest(0,sold_stock-fc.quantity),version=version+1,updated_at=now() where id=fc.flash_sale_id;
  end loop;

  coin_refund:=coalesce((p_order.snapshot->>'coin_share')::bigint,0);
  if coin_refund>0 and not exists(select 1 from public.delivery_market_coin_ledger where user_id=p_order.owner_id and kind='release_cancel' and reference_id=p_order.id) then
    insert into public.delivery_market_coin_wallets(user_id,balance) values(p_order.owner_id,coin_refund)
      on conflict(user_id) do update set balance=public.delivery_market_coin_wallets.balance+excluded.balance,updated_at=now();
    insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
      values(p_order.owner_id,coin_refund,'release_cancel',p_order.id);
  end if;
end$$;
revoke all on function public.delivery_market_release_order_allocations(public.delivery_market_shop_orders,uuid,text,text) from public,anon,authenticated;

-- Update delivery triggers for split shipments and full allocation release
create or replace function public.delivery_market_delivered() returns trigger
language plpgsql security definer set search_path='' as $$
declare target_order uuid;
begin
  if new.status='delivered' and old.status is distinct from new.status then
    select order_id into target_order from public.delivery_market_shipments where delivery_id=new.id;
    if target_order is not null then
      if not exists(select 1 from public.delivery_market_shipments ms join public.delivery_cloud_orders co on co.id=ms.delivery_id
        where ms.order_id=target_order and co.id<>new.id and co.status<>'delivered') then
        update public.delivery_market_shop_orders set delivered_at=coalesce(delivered_at,now()),version=version+1,updated_at=now() where id=target_order;
      end if;
    else
      update public.delivery_market_shop_orders set delivered_at=coalesce(delivered_at,now()),version=version+1,updated_at=now() where delivery_id=new.id;
    end if;
  end if;
  return new;
end$$;

create or replace function public.delivery_market_shipping_cancel() returns trigger
language plpgsql security definer set search_path='' as $$
declare so public.delivery_market_shop_orders; target_id uuid; source text:='user';
begin
  if new.status='cancelled' and old.status is distinct from new.status then
    select id into target_id from public.delivery_market_shop_orders where delivery_id=new.id;
    if target_id is null then
      select order_id into target_id from public.delivery_market_shipments where delivery_id=new.id;
    end if;
    if target_id is not null then
      select * into so from public.delivery_market_shop_orders where id=target_id for update;
      if so.id is not null and so.state<>'cancelled' and not exists(
        select 1 from public.delivery_market_shipments ms join public.delivery_cloud_orders co on co.id=ms.delivery_id
        where ms.order_id=so.id and co.id<>new.id and co.status<>'cancelled') then
        if auth.uid() is null then
          if current_setting('ghst.carrier_sync',true) is distinct from 'on' then raise sqlstate 'PT403' using message='Thiếu nguồn hủy vận đơn.'; end if;
          source:='carrier';
        end if;
        perform public.delivery_market_release_order_allocations(so,auth.uid(),source,'shipping_cancel_release');
        update public.delivery_market_shop_orders set state='cancelled',reason=coalesce(new.cancel_reason,''),version=version+1,updated_at=now() where id=so.id;
        insert into public.delivery_market_events(order_id,actor_id,actor_source,action,reason) values(so.id,auth.uid(),source,'shipping_cancel',coalesce(new.cancel_reason,''));
        insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'cancel'),(so.merchant_id,so.id,'cancel');
        if exists(select 1 from public.delivery_market_purchases where id=so.purchase_id and payment_status='PAID') then
          update public.delivery_market_purchases set payment_status='REVIEW' where id=so.purchase_id;
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Prepaid multi-shop capture recorded by backend payment gateway inside a DB transaction
create or replace function public.delivery_market_record_prepaid_capture(p_purchase uuid,p_reference text) returns text
language plpgsql security definer set search_path='' as $$
declare p public.delivery_market_purchases; so public.delivery_market_shop_orders; f public.delivery_market_finance;
  jid uuid; goods bigint; shop_disc bigint; plat_disc bigint; freight bigint; cash_due bigint; merch_net bigint;
begin
  select * into p from public.delivery_market_purchases where id=p_purchase for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy giao dịch mua hàng.'; end if;
  if exists(select 1 from public.delivery_market_shop_orders where purchase_id=p.id and state='cancelled') then
    update public.delivery_market_purchases set payment_status='REVIEW' where id=p.id;
    return 'REVIEW';
  end if;
  for so in select * from public.delivery_market_shop_orders where purchase_id=p.id order by id for update loop
    if not exists(select 1 from public.delivery_market_finance where order_id=so.id and kind='collection' and state='completed') then
      goods:=(so.snapshot->>'subtotal')::bigint;
      shop_disc:=coalesce((so.snapshot->>'shop_discount')::bigint,0);
      plat_disc:=coalesce((so.snapshot->>'platform_discount')::bigint,0);
      freight:=(so.snapshot->>'shipping_fee')::bigint;
      merch_net:=greatest(0,goods-shop_disc);
      cash_due:=greatest(1,goods-shop_disc-plat_disc+freight);
      insert into public.delivery_market_finance(order_id,kind,amount,proposer,reason,evidence,completion_evidence,state,source,request_key,completed_at)
        values(so.id,'collection',cash_due::integer,p.owner_id,'Thanh toán trực tuyến payOS','payOS:'||left(p_reference,180),'payOS:'||left(p_reference,180),'completed','provider',gen_random_uuid(),now())
        returning * into f;
      insert into public.delivery_market_journals(finance_id,order_id) values(f.id,so.id) returning id into jid;
      insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'cash_clearing',cash_due);
      if plat_disc>0 then insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'promo_expense',plat_disc); end if;
      if merch_net>0 then insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'merchant_payable',-merch_net); end if;
      if freight>0 then insert into public.delivery_market_ledger(journal_id,account,amount) values(jid,'shipping_revenue',-freight); end if;
      update public.delivery_market_shop_orders set accept_by=greatest(accept_by,now()+interval '15 minutes') where id=so.id;
      update public.delivery_market_jobs set run_at=greatest(run_at,now()+interval '15 minutes') where order_id=so.id and state='pending';
    end if;
  end loop;
  update public.delivery_market_purchases set payment_status='PAID' where id=p.id;
  return 'PAID';
end$$;
revoke all on function public.delivery_market_record_prepaid_capture(uuid,text) from public,anon,authenticated;

-- Background worker: expire pending shop orders, stale payment links & ended promotions
create or replace function public.delivery_market_run_jobs(p_limit integer default 25) returns jsonb
language plpgsql security definer set search_path='' as $$
declare job public.delivery_market_jobs; so public.delivery_market_shop_orders; processed integer:=0; failed integer:=0;
begin
  update public.delivery_payment_transactions set status='EXPIRED',updated_at=now()
    where status in ('CREATING','PENDING') and expires_at<=now();
  update public.delivery_market_flash_sales set active=false,updated_at=now()
    where active and ends_at<=now();
  update public.delivery_market_vouchers set active=false,updated_at=now()
    where active and ends_at<=now();

  for job in select * from public.delivery_market_jobs where state='pending' and run_at<=now()
    order by run_at,id limit greatest(1,least(coalesce(p_limit,25),100)) for update skip locked loop
    begin
      select * into so from public.delivery_market_shop_orders where id=job.order_id for update;
      if so.state='pending' and so.accept_by<=now() then
        perform public.delivery_market_release_order_allocations(so,null,'system','acceptance_expired');
        update public.delivery_market_shop_orders set state='cancelled',reason='Quá hạn xác nhận',version=version+1,updated_at=now() where id=so.id;
        insert into public.delivery_market_events(order_id,actor_id,actor_source,action) values(so.id,null,'system','acceptance_expired');
        insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'acceptance_expired'),(so.merchant_id,so.id,'acceptance_expired');
        if exists(select 1 from public.delivery_market_purchases where id=so.purchase_id and payment_status='PAID') then
          update public.delivery_market_purchases set payment_status='REVIEW' where id=so.purchase_id;
        end if;
      end if;
      update public.delivery_market_jobs set state='done',attempts=attempts+1,last_error=null,completed_at=now() where id=job.id;
      processed:=processed+1;
    exception when others then
      update public.delivery_market_jobs set attempts=attempts+1,state=case when attempts>=4 then 'failed' else 'pending' end,
        run_at=now()+interval '1 minute',last_error=sqlstate where id=job.id;
      failed:=failed+1;
    end;
  end loop;
  return jsonb_build_object('processed',processed,'failed',failed);
end$$;
revoke all on function public.delivery_market_run_jobs(integer) from public,anon,authenticated;

-- Main marketplace RPC (P1-P6)
create or replace function public.delivery_marketplace(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor public.delivery_cloud_accounts; sh public.delivery_market_shops; prod public.delivery_market_products;
  previous public.delivery_market_products; var_row public.delivery_market_variants; prev_var public.delivery_market_variants;
  voucher_row public.delivery_market_vouchers; flash_row public.delivery_market_flash_sales;
  purchase public.delivery_market_purchases; so public.delivery_market_shop_orders;
  quote public.delivery_market_quotes; shipment public.delivery_cloud_orders; msg public.delivery_market_messages;
  d jsonb:=p_payload; result jsonb; snapshot jsonb; group_row jsonb; item jsonb; parcel jsonb;
  cart_version integer; qty integer; product_key uuid; variant_key uuid; requested text; line_key uuid;
  selected jsonb; selection jsonb; aggregate_qty bigint; op boolean;
  staff_user uuid; att_list jsonb:='[]'; att_name text; idx integer:=0;
  coin_total bigint:=0; coin_rem bigint:=0; sh_cnt integer:=0; sh_idx integer:=0; sh_coin bigint:=0;
  v_id uuid; fs_id uuid; split_cod bigint:=0; expected_cod bigint:=0; parcel_weight numeric;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  select * into actor from public.delivery_cloud_accounts where user_id=auth.uid() for share;
  op:=public.delivery_is_operator();
  if (actor.user_id is null or actor.blocked) and not (p_action in ('workspace','shop_moderate','voucher_save') and op) then
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
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not op and
       not exists(select 1 from public.delivery_market_shop_staff st where st.user_id=auth.uid() and st.active and public.delivery_market_can_access_shop(st.shop_id,auth.uid(),'staff')) then
      raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
    end if;
    result:=jsonb_build_object(
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
      'staff',coalesce((select jsonb_agg(jsonb_build_object('shop_id',st.shop_id,'user_id',st.user_id,'full_name',ua.full_name,'phone',ua.phone,'role',st.role,'active',st.active,'version',st.version) order by st.created_at,st.user_id)
        from public.delivery_market_shop_staff st join public.delivery_market_shops s on s.id=st.shop_id
        join public.delivery_cloud_accounts ua on ua.user_id=st.user_id
        where s.owner_id=auth.uid() and st.active),'[]'),
      'vouchers',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc,v.id desc) from
        (select v.* from public.delivery_market_vouchers v
         where (op and d->>'moderation'='true') or (v.shop_id is not null and public.delivery_market_can_access_shop(v.shop_id,auth.uid(),'staff'))
         order by v.created_at desc,v.id desc limit 50) v),'[]'),
      'flash_sales',coalesce((select jsonb_agg(to_jsonb(fs) order by fs.starts_at desc,fs.id desc) from
        (select fs.* from public.delivery_market_flash_sales fs
         where (op and d->>'moderation'='true') or public.delivery_market_can_access_shop(fs.shop_id,auth.uid(),'staff')
         order by fs.starts_at desc,fs.id desc limit 50) fs),'[]')
    );
    snapshot:=result->case when d->>'moderation'='true' then 'shops' else 'products' end;
    return result||jsonb_build_object('next',case when jsonb_array_length(snapshot)=50 then jsonb_build_object('after',snapshot->49->>'id') end);

  elsif p_action='shop_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    if d-array['name','description','address','latitude','longitude','paused','version','opening_schedule','banner_url','service_radius_km']<>'{}' or
      jsonb_typeof(d->'name') is distinct from 'string' or jsonb_typeof(d->'address') is distinct from 'string' or
      jsonb_typeof(d->'latitude') is distinct from 'number' or jsonb_typeof(d->'longitude') is distinct from 'number' or
      jsonb_typeof(d->'paused') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Thông tin cửa hàng không hợp lệ.'; end if;
    if (d ? 'service_radius_km' and (jsonb_typeof(d->'service_radius_km')<>'number' or (d->>'service_radius_km')::numeric not between 0 and 200)) or
       (d ? 'banner_url' and (jsonb_typeof(d->'banner_url')<>'string' or length(d->>'banner_url')>1000 or (d->>'banner_url'<>'' and (d->>'banner_url') !~ '^https://'))) then
      raise sqlstate 'PT400' using message='Ảnh bìa hoặc bán kính phục vụ không hợp lệ.';
    end if;
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
    update public.delivery_market_shops set
      opening_schedule=coalesce(d->'opening_schedule',opening_schedule),
      banner_url=case when d ? 'banner_url' then d->>'banner_url' else banner_url end,
      service_radius_km=case when d ? 'service_radius_km' then (d->>'service_radius_km')::numeric else service_radius_km end
      where id=sh.id returning * into sh;
    return jsonb_build_object('shop',to_jsonb(sh));

  elsif p_action='staff_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Chỉ chủ cửa hàng quản lý nhân sự.'; end if;
    select * into sh from public.delivery_market_shops where id=(d->>'shop_id')::uuid and owner_id=auth.uid() for update;
    if not found or sh.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền quản lý nhân sự cửa hàng này.'; end if;
    if d ? 'user_id' and jsonb_typeof(d->'user_id')='string' then
      staff_user:=(d->>'user_id')::uuid;
    elsif d ? 'phone' and jsonb_typeof(d->'phone')='string' then
      select user_id into staff_user from public.delivery_cloud_accounts where phone=btrim(d->>'phone') and not blocked order by updated_at desc limit 1;
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
    return jsonb_build_object('staff',coalesce((select jsonb_agg(jsonb_build_object('shop_id',st.shop_id,'user_id',st.user_id,'full_name',ua.full_name,'phone',ua.phone,'role',st.role,'active',st.active,'version',st.version) order by st.created_at,st.user_id)
      from public.delivery_market_shop_staff st join public.delivery_cloud_accounts ua on ua.user_id=st.user_id where st.shop_id=sh.id and st.active),'[]'::jsonb));

  elsif p_action='shop_moderate' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    if d->>'status' not in ('active','suspended') or not(d ?& array['id','version','status']) then raise sqlstate 'PT400' using message='Trạng thái không hợp lệ.'; end if;
    update public.delivery_market_shops set status=d->>'status',version=version+1,updated_at=now()
      where id=(d->>'id')::uuid and version=(d->>'version')::integer returning * into sh;
    if not found then raise sqlstate 'PT409' using message='Cửa hàng đã thay đổi hoặc không tồn tại.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'shop_moderate',sh.id,to_jsonb(sh));
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
      raise sqlstate 'PT400' using message='Thời gian chuẩn bị không hợp lệ.'; end if;
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
    variant_key:=coalesce((d->>'id')::uuid,gen_random_uuid());
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
    v_id:=coalesce((d->>'id')::uuid,gen_random_uuid());
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
    fs_id:=coalesce((d->>'id')::uuid,gen_random_uuid());
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
      qty:=(d->>'quantity')::integer; product_key:=(d->>'product_id')::uuid;
      variant_key:=nullif(d->>'variant_id','')::uuid;
      line_key:=(d->>'line_id')::uuid; selected:=coalesce(d->'selected_options','[]');
      if product_key is null then raise sqlstate 'PT400' using message='Thiếu sản phẩm.'; end if;
      if line_key is not null then
        select c.selected_options,c.variant_id into selected,variant_key from public.delivery_market_cart_items c
          where c.user_id=auth.uid() and c.line_id=line_key and c.product_id=product_key;
        if not found then raise sqlstate 'PT409' using message='Dòng giỏ hàng đã thay đổi. Hãy tải lại.'; end if;
        if (d?'selected_options' and d->'selected_options' is distinct from selected) or
           (d?'variant_id' and nullif(d->>'variant_id','')::uuid is distinct from variant_key) then
          raise sqlstate 'PT409' using message='Không thể đổi lựa chọn của dòng giỏ hàng.'; end if;
      end if;
      if qty=0 then
        if line_key is null then
          selection:=public.delivery_market_selection_v2(product_key,selected,variant_key,1,auth.uid());
          line_key:=(selection->>'line_id')::uuid;
        end if;
        delete from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key and product_id=product_key;
      else
        select * into prod from public.delivery_market_products where id=product_key for share;
        select * into sh from public.delivery_market_shops where id=prod.shop_id;
        if prod.id is null or not prod.published or sh.status<>'active' or sh.paused or sh.owner_id=auth.uid() or
          not public.delivery_market_is_open(prod.sale_schedule) or not public.delivery_market_is_open(sh.opening_schedule) or
          not exists(select 1 from public.delivery_cloud_accounts where user_id=sh.owner_id and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
          raise sqlstate 'PT409' using message='Sản phẩm không thể mua hoặc không đủ tồn kho.'; end if;
        selection:=public.delivery_market_selection_v2(product_key,selected,variant_key,qty,auth.uid());
        line_key:=(selection->>'line_id')::uuid;
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
          if aggregate_qty>prod.stock or aggregate_qty>99 then raise sqlstate 'PT409' using message='Tổng số lượng các lựa chọn vượt tồn kho hoặc giới hạn 99.'; end if;
        end if;
        if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key) and
          (select count(*) from public.delivery_market_cart_items where user_id=auth.uid())>=50 then raise sqlstate 'PT400' using message='Giỏ hàng hỗ trợ tối đa 50 dòng.'; end if;
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
        raise sqlstate 'PT400' using message='Yêu cầu báo giá không hợp lệ.'; end if;
      snapshot:=public.delivery_market_snapshot_v2((d->>'address_id')::uuid,d-array['address_id','cart_version','address_version']);
      if d?'cart_version' and d->'cart_version' is distinct from snapshot->'cart_version' then
        raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy kiểm tra lại.'; end if;
      if d?'address_version' and d->'address_version' is distinct from snapshot->'address_version' then
        raise sqlstate 'PT409' using message='Địa chỉ đã thay đổi. Hãy kiểm tra lại địa chỉ nhận hàng.'; end if;
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

    snapshot:=public.delivery_market_snapshot_v2((quote.snapshot->>'address_id')::uuid,coalesce(quote.snapshot->'checkout_options','{}'::jsonb));
    if snapshot<>quote.snapshot then raise sqlstate 'PT409' using message='Giá, khuyến mãi, giỏ hàng hoặc địa chỉ đã thay đổi. Hãy xác nhận báo giá mới.'; end if;

    insert into public.delivery_market_purchases(owner_id,request_key,quote_id,snapshot,total,payment_method)
      values(auth.uid(),(d->>'request_key')::uuid,quote.id,snapshot,(snapshot->>'total')::integer,coalesce(snapshot->>'payment_method','cod'))
      returning * into purchase;

    coin_total:=coalesce((snapshot->>'coin_discount')::bigint,0);
    coin_rem:=coin_total;
    if coin_total>0 then
      update public.delivery_market_coin_wallets set balance=balance-coin_total,updated_at=now()
        where user_id=auth.uid() and balance>=coin_total;
      if not found then raise sqlstate 'PT409' using message='Số dư xu không đủ.'; end if;
      insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
        values(auth.uid(),-coin_total,'redeem_checkout',purchase.id);
    end if;

    sh_cnt:=jsonb_array_length(snapshot->'shops');
    for group_row in select * from jsonb_array_elements(snapshot->'shops') loop
      sh_idx:=sh_idx+1;
      if coin_rem>0 then
        if sh_idx=sh_cnt then sh_coin:=coin_rem;
        else sh_coin:=least(coin_rem,floor(coin_total*(group_row->>'subtotal')::numeric/greatest(1,(snapshot->>'goods_subtotal')::numeric))::bigint);
        end if;
        coin_rem:=greatest(0,coin_rem-sh_coin);
        group_row:=group_row||jsonb_build_object('coin_share',sh_coin);
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
    end loop;

    delete from public.delivery_market_cart_items where user_id=auth.uid();
    update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    return jsonb_build_object('purchase',to_jsonb(purchase)-'request_key');

  elsif p_action='orders' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from (
      select o.*,p.payment_status,p.payment_method,del.status as delivery_status,del.tracking_code,
        coalesce((select jsonb_agg(jsonb_build_object('parcel_index',ms.parcel_index,'delivery_id',ms.delivery_id,'tracking_code',co.tracking_code,'status',co.status,'weight_kg',ms.weight_kg,'cod_amount',ms.cod_amount) order by ms.parcel_index)
          from public.delivery_market_shipments ms join public.delivery_cloud_orders co on co.id=ms.delivery_id where ms.order_id=o.id),'[]'::jsonb) as shipments
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
      if purchase.payment_method='prepaid' and purchase.payment_status<>'PAID' then
        raise sqlstate 'PT409' using message='Đơn trả trước chưa thanh toán thành công.';
      end if;
      if jsonb_typeof(d->'parcels')<>'array' or jsonb_array_length(d->'parcels') not between 2 and 10 then
        raise sqlstate 'PT400' using message='Tách kiện cần từ 2 đến 10 kiện hàng.';
      end if;
      expected_cod:=case when purchase.payment_method='prepaid' then 0 else coalesce((so.snapshot->>'payable_subtotal')::bigint,(so.snapshot->>'subtotal')::bigint) end;
      for parcel in select * from jsonb_array_elements(d->'parcels') loop
        idx:=idx+1;
        parcel_weight:=coalesce((parcel->>'weight_kg')::numeric,0);
        if parcel_weight<=0 or parcel_weight>500 or jsonb_typeof(coalesce(parcel->'cod_amount','0'::jsonb))<>'number' or
           (parcel->>'cod_amount')::numeric<0 or (parcel->>'cod_amount')::numeric<>trunc((parcel->>'cod_amount')::numeric) then
          raise sqlstate 'PT400' using message='Khối lượng hoặc COD từng kiện không hợp lệ.';
        end if;
        split_cod:=split_cod+coalesce((parcel->>'cod_amount')::bigint,0);
      end loop;
      if split_cod<>expected_cod then
        raise sqlstate 'PT409' using message='Tổng COD các kiện phải khớp số tiền cần thu của đơn.';
      end if;
      idx:=0;
      for parcel in select * from jsonb_array_elements(d->'parcels') loop
        idx:=idx+1;
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id,'parcel_index',idx),
            jsonb_set(jsonb_set(so.snapshot->'details','{weight_kg}',parcel->'weight_kg'),'{cod_amount}',coalesce(parcel->'cod_amount','0'::jsonb)),
            (so.snapshot->>'distance_meters')::integer,
            case when idx=1 then (so.snapshot->>'shipping_fee')::integer else 0 end,
            coalesce((parcel->>'cod_amount')::integer,0),(so.snapshot->>'pricing_version')::integer,true)
          returning * into shipment;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code);
        insert into public.delivery_live_members values(shipment.tracking_code,so.owner_id,'customer'),(shipment.tracking_code,so.merchant_id,'merchant');
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        insert into public.delivery_market_shipments(order_id,delivery_id,parcel_index,items,weight_kg,cod_amount)
          values(so.id,shipment.id,idx,coalesce(parcel->'items','[]'::jsonb),(parcel->>'weight_kg')::numeric,coalesce((parcel->>'cod_amount')::integer,0));
        if idx=1 then so.delivery_id:=shipment.id; end if;
      end loop;
      update public.delivery_market_shop_orders set state='ready',delivery_id=so.delivery_id,version=version+1,updated_at=now()
        where id=so.id returning * into so;
      insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'ready_split','Tách '||idx||' kiện vận chuyển');
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'ready');
      return jsonb_build_object('order',to_jsonb(so));
    end if;

    if p_action='order_action' then
      requested:=d->>'action';
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if requested not in ('accept','ready','cancel') or requested is null then raise sqlstate 'PT400' using message='Thao tác không hợp lệ.'; end if;
      if requested in ('accept','ready') and not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff') then
        raise sqlstate 'PT403' using message='Chỉ cửa hàng xử lý đơn mua hàng.';
      end if;
      select * into purchase from public.delivery_market_purchases where id=so.purchase_id;
      if requested in ('accept','ready') and purchase.payment_method='prepaid' and purchase.payment_status<>'PAID' then
        raise sqlstate 'PT409' using message='Đơn trả trước cần khách thanh toán thành công trước khi xác nhận.';
      end if;
      if requested='accept' and so.state='pending' then so.state:='accepted';
      elsif requested='ready' and so.state='accepted' then
        expected_cod:=case when purchase.payment_method='prepaid' then 0 else coalesce((so.snapshot->>'payable_subtotal')::bigint,(so.snapshot->>'subtotal')::bigint) end;
        insert into public.delivery_cloud_orders(owner_id,merchant_id,request_key,request_payload,details,distance_meters,
          shipping_fee,cod_amount,pricing_version,merchant_ready)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('shop_order',so.id),so.snapshot->'details',
            (so.snapshot->>'distance_meters')::integer,(so.snapshot->>'shipping_fee')::integer,
            expected_cod::integer,(so.snapshot->>'pricing_version')::integer,true) returning * into shipment;
        if coalesce((so.snapshot->'details'->>'require_otp')::boolean,false) then
          insert into public.delivery_cloud_order_secrets(order_id,otp_code,otp_hash)
            select shipment.id,otp_code,encode(sha256(convert_to(otp_code,'UTF8')),'hex')
            from (select ((get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),0)*65536 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),1)*256 + get_byte(sha256(convert_to(gen_random_uuid()::text,'UTF8')),2)) % 900000 + 100000)::text as otp_code) g;
        end if;
        insert into public.delivery_live_rooms(id) values(shipment.tracking_code);
        insert into public.delivery_live_members values(shipment.tracking_code,so.owner_id,'customer'),(shipment.tracking_code,so.merchant_id,'merchant');
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(shipment.id,auth.uid(),'create',shipment.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(shipment.tracking_code,'status',jsonb_build_object('status',shipment.status,'version',1));
        so.state:='ready'; so.delivery_id:=shipment.id;
      elsif requested='cancel' and so.state in ('pending','accepted') and length(btrim(coalesce(d->>'reason',''))) between 3 and 500 and
        (public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') or (so.owner_id=auth.uid() and so.state='pending')) then
        perform public.delivery_market_release_order_allocations(so,auth.uid(),'user','cancel_release');
        so.state:='cancelled'; so.reason:=btrim(d->>'reason');
        if purchase.payment_status='PAID' then
          update public.delivery_market_purchases set payment_status='REVIEW' where id=purchase.id;
        end if;
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
      if d ? 'attachments' then
        if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>4 then
          raise sqlstate 'PT400' using message='Tối đa 4 tệp đính kèm mỗi tin nhắn.';
        end if;
        for att_name in select jsonb_array_elements_text(d->'attachments') loop
          if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='chat') then
            raise sqlstate 'PT403' using message='Tệp đính kèm không thuộc cuộc hội thoại này.';
          end if;
        end loop;
        att_list:=d->'attachments';
      end if;
      perform pg_advisory_xact_lock(hashtextextended('message:'||auth.uid()::text,0));
      select * into msg from public.delivery_market_messages where actor_id=auth.uid() and request_key=(d->>'request_key')::uuid;
      if msg.id is not null then
        if msg.order_id<>so.id or msg.body<>btrim(d->>'body') then raise sqlstate 'PT409' using message='Mã tin nhắn đã được dùng.'; end if;
      else
        if (select count(*) from public.delivery_market_messages where actor_id=auth.uid() and created_at>now()-interval '1 minute')>=20 then
          raise sqlstate 'PT409' using message='Bạn gửi quá nhiều tin nhắn. Vui lòng chờ.'; end if;
        insert into public.delivery_market_messages(order_id,actor_id,body,attachments,request_key)
          values(so.id,auth.uid(),btrim(d->>'body'),att_list,(d->>'request_key')::uuid);
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


-- P5: Private evidence attachment reservation & Storage RLS
create or replace function public.delivery_market_attachment_reserve(
  p_order uuid,
  p_scope text,
  p_hash text,
  p_bytes integer
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare so public.delivery_market_shop_orders; a public.delivery_cloud_accounts;
  att public.delivery_market_attachments; op boolean; is_driver boolean:=false; obj_name text;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  op:=public.delivery_is_operator();
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
  if p_scope='finance' and so.delivery_id is not null then
    is_driver:=public.delivery_cloud_has_membership(auth.uid(),'driver') and exists(
      select 1 from public.delivery_cloud_orders co where co.id=so.delivery_id and co.driver_id=auth.uid()
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
    obj_name:=p_scope||'/'||so.id::text||'/'||p_hash||'.webp';
    insert into public.delivery_market_attachments(name,scope,order_id,owner_id,content_hash,byte_size)
      values(obj_name,p_scope,so.id,auth.uid(),p_hash,p_bytes) returning * into att;
  end if;
  return jsonb_build_object('id',att.id,'name',att.name,'bucket','delivery-private-evidence');
end $$;

create or replace function public.delivery_market_attachment_can_upload(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.delivery_market_attachments att
    left join public.delivery_cloud_accounts a on a.user_id=att.owner_id
    where att.name=p_name and att.owner_id=auth.uid() and att.upload_until>now()
      and (public.delivery_is_operator() or coalesce(not a.blocked,false))
  );
$$;

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
          or (att.scope='finance' and so.delivery_id is not null and public.delivery_cloud_has_membership(auth.uid(),'driver')
              and exists(select 1 from public.delivery_cloud_orders co where co.id=so.delivery_id and co.driver_id=auth.uid()))
        )
      )
    )
  );
$$;

drop policy if exists delivery_private_evidence_insert on storage.objects;
create policy delivery_private_evidence_insert on storage.objects for insert to authenticated
  with check(bucket_id='delivery-private-evidence' and public.delivery_market_attachment_can_upload(name));

drop policy if exists delivery_private_evidence_select on storage.objects;
create policy delivery_private_evidence_select on storage.objects for select to authenticated
  using(bucket_id='delivery-private-evidence' and public.delivery_market_attachment_can_read(name));

-- Post-purchase operations, partner reviews, shop follows, vouchers, coins & admin analytics
create or replace function public.delivery_market_operations(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; a public.delivery_cloud_accounts; so public.delivery_market_shop_orders;
  sh public.delivery_market_shops; co public.delivery_cloud_orders;
  prod public.delivery_market_products; ret public.delivery_market_returns; f public.delivery_market_finance;
  pr public.delivery_partner_reviews; rev public.delivery_market_reviews; existing public.delivery_market_commands;
  result jsonb; item jsonb; token text; jid uuid; qty integer; cv integer; collected bigint; refunded bigint; settled bigint;
  due bigint; goods bigint; shop_disc bigint; plat_disc bigint; merch_net bigint; freight bigint; used bigint;
  op boolean; k uuid; requested text; line_key uuid; var_key uuid; selection jsonb;
  att_list jsonb:='[]'; att_name text; disp text; rev_kind text; v_target_kind text;
  rev_ship public.delivery_cloud_orders; merch_acc public.delivery_cloud_accounts; rev_details jsonb;
  coin_earn bigint:=0; coin_rev bigint:=0; wallet_bal bigint:=0;
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
    result:=jsonb_build_object(
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
    rev_kind:=coalesce(d->>'review_kind','product');
    if rev_kind not in ('product','partner') or jsonb_typeof(d->'hidden') is distinct from 'boolean' or length(btrim(coalesce(d->>'reason',''))) not between 3 and 500 then
      raise sqlstate 'PT400' using message='Cần lý do kiểm duyệt hợp lệ.'; end if;
    if rev_kind='partner' then
      update public.delivery_partner_reviews set hidden=(d->>'hidden')::boolean where id=(d->>'id')::uuid;
    else
      update public.delivery_market_reviews set hidden=(d->>'hidden')::boolean where id=(d->>'id')::uuid;
    end if;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'review_moderate',(d->>'id')::uuid,d);
    return jsonb_build_object('ok',true);

  elsif p_action='partner_review_save' then
    v_target_kind:=d->>'target_kind';
    if v_target_kind is null or v_target_kind not in ('shop','driver') or
       jsonb_typeof(d->'rating') is distinct from 'number' or (d->>'rating')::numeric<>trunc((d->>'rating')::numeric) or
       (d->>'rating')::integer not between 1 and 5 or length(btrim(coalesce(d->>'body',''))) not between 3 and 2000 then
      raise sqlstate 'PT400' using message='Nội dung hoặc số sao đánh giá đối tác không hợp lệ.';
    end if;
    if v_target_kind='shop' then
      select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid for share;
      if not found or so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '30 days' then
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
      return jsonb_build_object('partner_review',to_jsonb(pr)-'reviewer_id');
    else
      if d ? 'cloud_order_id' and jsonb_typeof(d->'cloud_order_id')='string' then
        select * into co from public.delivery_cloud_orders where id=(d->>'cloud_order_id')::uuid for share;
      elsif d ? 'order_id' and jsonb_typeof(d->'order_id')='string' then
        select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid for share;
        if found and so.delivery_id is not null then
          select * into co from public.delivery_cloud_orders where id=so.delivery_id for share;
        end if;
      end if;
      if co.id is null or co.owner_id<>auth.uid() or co.status<>'delivered' or co.driver_id is null or co.updated_at<now()-interval '30 days' then
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
    rev_kind:=coalesce(d->>'review_kind','product');
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
    rev_kind:=coalesce(d->>'review_kind','product');
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
    return jsonb_build_object('ok',true);

  elsif p_action='finance_action' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    select order_id into k from public.delivery_market_finance where id=(d->>'id')::uuid;
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
      goods:=(so.snapshot->>'subtotal')::bigint;
      shop_disc:=coalesce((so.snapshot->>'shop_discount')::bigint,0);
      plat_disc:=coalesce((so.snapshot->>'platform_discount')::bigint,0);
      freight:=(so.snapshot->>'shipping_fee')::bigint;
      merch_net:=greatest(0,goods-shop_disc);
      due:=greatest(0,goods-shop_disc-plat_disc)+freight;
      select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
        into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
      if f.kind='collection' and (so.delivered_at is null or so.state='cancelled' or f.amount<>due or collected<>0) then
        raise sqlstate 'PT409' using message='Chỉ xác nhận đủ tiền COD một lần sau giao thành công.';
      elsif f.kind='refund' then
        select * into ret from public.delivery_market_returns where id=f.return_id and order_id=so.id;
        select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state='completed';
        select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
        if ret.id is null or ret.state<>'received' or f.amount>ret.quantity*(item->>'unit_price')::bigint-used
          or f.amount>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled) then raise sqlstate 'PT409' using message='Khoản hoàn vượt mức hoặc chưa nhận hàng trả.'; end if;
      elsif f.kind='settlement' and (f.amount>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled-freight) or exists
        (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=r.line_id) v on true
          where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
          r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))
        or so.delivered_at is null or so.delivered_at>now()-interval '7 days') then
        raise sqlstate 'PT409' using message='Chưa đủ điều kiện đối soát shop: tiền khả dụng, hạn hậu mãi hoặc tranh chấp.';
      end if;
      update public.delivery_market_finance set state='completed',completion_evidence=btrim(d->>'evidence'),completed_at=now(),version=version+1 where id=f.id returning * into f;
      insert into public.delivery_market_journals(finance_id,order_id) values(f.id,so.id) returning id into jid;
      if f.kind='collection' then
        insert into public.delivery_market_ledger values(jid,'cash_clearing',due);
        if plat_disc>0 then insert into public.delivery_market_ledger values(jid,'promo_expense',plat_disc); end if;
        if merch_net>0 then insert into public.delivery_market_ledger values(jid,'merchant_payable',-merch_net); end if;
        if freight>0 then insert into public.delivery_market_ledger values(jid,'shipping_revenue',-freight); end if;
      else
        insert into public.delivery_market_ledger values(jid,'cash_clearing',-f.amount),(jid,'merchant_payable',f.amount);
        if f.kind='settlement' then
          coin_earn:=floor(f.amount*0.01)::bigint;
          if coin_earn>0 and not exists(select 1 from public.delivery_market_coin_ledger where user_id=so.owner_id and kind='earn_settlement' and reference_id=f.id) then
            insert into public.delivery_market_coin_wallets(user_id,balance) values(so.owner_id,coin_earn)
              on conflict(user_id) do update set balance=public.delivery_market_coin_wallets.balance+excluded.balance,updated_at=now();
            insert into public.delivery_market_coin_ledger(user_id,delta,kind,reference_id)
              values(so.owner_id,coin_earn,'earn_settlement',f.id);
          end if;
        elsif f.kind='refund' then
          select coalesce(balance,0) into wallet_bal from public.delivery_market_coin_wallets where user_id=so.owner_id for update;
          coin_rev:=least(wallet_bal,floor(f.amount*0.01)::bigint);
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
    else raise sqlstate 'PT409' using message='Không thể chuyển trạng thái yêu cầu tài chính.';
    end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'market_finance_'||requested,f.id,to_jsonb(f)||jsonb_build_object('decision_reason',d->>'reason'));
    return jsonb_build_object('finance',to_jsonb(f));
  end if;

  select * into so from public.delivery_market_shop_orders where id=(d->>'order_id')::uuid
    and (owner_id=auth.uid() or public.delivery_market_can_access_shop(shop_id,auth.uid(),'staff') or op or exists
      (select 1 from public.delivery_cloud_orders o where o.id=delivery_id and o.driver_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'driver'))) for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;

  if p_action='order_services' then
    if not op and so.owner_id<>auth.uid() and not public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'staff') then
      raise sqlstate 'PT403' using message='Không có quyền xem hậu mãi của đơn này.';
    end if;
    select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    return jsonb_build_object(
      'order',to_jsonb(so),
      'collected',collected,'refunded',refunded,'settled',settled,
      'returns',coalesce((select jsonb_agg(to_jsonb(r) order by created_at,id) from public.delivery_market_returns r where order_id=so.id),'[]'),
      'reviews',coalesce((select jsonb_agg(to_jsonb(r)-'user_id' order by created_at,id) from public.delivery_market_reviews r where order_id=so.id),'[]'),
      'partner_reviews',coalesce((select jsonb_agg(to_jsonb(pr)-'reviewer_id' order by created_at,id) from public.delivery_partner_reviews pr
        where pr.shop_order_id=so.id or (so.delivery_id is not null and pr.cloud_order_id=so.delivery_id)),'[]'),
      'shipments',coalesce((select jsonb_agg(jsonb_build_object('parcel_index',ms.parcel_index,'delivery_id',ms.delivery_id,'tracking_code',co.tracking_code,'status',co.status,'weight_kg',ms.weight_kg,'cod_amount',ms.cod_amount) order by ms.parcel_index)
        from public.delivery_market_shipments ms join public.delivery_cloud_orders co on co.id=ms.delivery_id where ms.order_id=so.id),'[]'),
      'attachments',coalesce((select jsonb_agg(jsonb_build_object('id',att.id,'name',att.name,'scope',att.scope,'byte_size',att.byte_size,'created_at',att.created_at) order by att.created_at,att.id)
        from public.delivery_market_attachments att where att.order_id=so.id),'[]'),
      'finance',coalesce((select jsonb_agg(to_jsonb(r)-'evidence'-'completion_evidence'-'request_key' order by created_at,id) from public.delivery_market_finance r where order_id=so.id),'[]'),
      'shares',case when so.owner_id=auth.uid() then coalesce((select jsonb_agg(to_jsonb(s)-'token_hash'-'owner_id' order by created_at,id) from public.delivery_market_shares s where order_id=so.id and revoked_at is null and expires_at>now()),'[]') else '[]'::jsonb end
    );

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
      var_key:=case when item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then (item->>'variant_id')::uuid else null end;
      selection:=public.delivery_market_selection_v2(prod.id,coalesce(item->'selected_options','[]'),var_key,1,auth.uid());
      select coalesce((select quantity from public.delivery_market_cart_items where user_id=auth.uid() and line_id=(selection->>'line_id')::uuid),0)+(item->>'quantity')::integer into qty;
      perform public.delivery_marketplace('cart_set',
        jsonb_build_object('product_id',prod.id,'selected_options',selection->'selected_options','quantity',qty,'version',cv)
        || case when var_key is not null then jsonb_build_object('variant_id',var_key) else '{}'::jsonb end);
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
    line_key:=coalesce(d->>'line_id',d->>'product_id')::uuid;
    if so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '7 days' then raise sqlstate 'PT403' using message='Chỉ người mua yêu cầu trả trong 7 ngày sau nhận hàng.'; end if;
    if d ? 'attachments' then
      if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>5 then
        raise sqlstate 'PT400' using message='Tối đa 5 ảnh bằng chứng trả hàng.';
      end if;
      for att_name in select jsonb_array_elements_text(d->'attachments') loop
        if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='return') then
          raise sqlstate 'PT403' using message='Ảnh bằng chứng không thuộc yêu cầu trả hàng này.';
        end if;
      end loop;
      att_list:=d->'attachments';
    end if;
    select * into ret from public.delivery_market_returns where user_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if ret.order_id<>so.id or ret.product_id is distinct from (d->>'product_id')::uuid or ret.line_id is distinct from line_key or ret.quantity is distinct from (d->>'quantity')::integer or ret.reason is distinct from btrim(d->>'reason') then raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.'; end if;
      return jsonb_build_object('return',to_jsonb(ret));
    end if;
    if jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
    select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=line_key and (i->>'product_id')::uuid=(d->>'product_id')::uuid;
    select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and line_id=line_key and state<>'rejected';
    if item is null or (d->>'quantity')::integer+used>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Số lượng trả vượt số lượng đã mua còn lại.'; end if;
    if (select count(*) from public.delivery_market_returns where order_id=so.id)>=100 then raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu trả hàng. Cần quản trị viên kiểm tra.'; end if;
    var_key:=case when item ? 'variant_id' and jsonb_typeof(item->'variant_id')='string' then (item->>'variant_id')::uuid else null end;
    insert into public.delivery_market_returns(order_id,product_id,variant_id,line_id,user_id,quantity,reason,attachments,request_key)
      values(so.id,(d->>'product_id')::uuid,var_key,line_key,auth.uid(),(d->>'quantity')::integer,btrim(d->>'reason'),att_list,(d->>'request_key')::uuid) returning * into ret;
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'return_requested');
    return jsonb_build_object('return',to_jsonb(ret));

  elsif p_action='return_action' then
    select * into ret from public.delivery_market_returns where id=(d->>'id')::uuid and order_id=so.id for update;
    if ret.id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu trả hàng.'; end if;
    if ret.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Yêu cầu đã thay đổi.'; end if;
    requested:=d->>'action';
    if length(btrim(coalesce(d->>'response',''))) not between 3 and 1000 then raise sqlstate 'PT400' using message='Cần phản hồi/lý do xử lý.'; end if;
    if requested='escalate' and ret.state='rejected' and so.owner_id=auth.uid() then
      select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
      select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and line_id=ret.line_id and state<>'rejected';
      if used+ret.quantity>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Đã có yêu cầu khác cho số lượng này.'; end if;
      requested:='escalated';
    elsif requested in ('approve','reject') and ((public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') and ret.state='requested') or (op and ret.state in ('requested','escalated'))) then
      requested:=case requested when 'approve' then 'approved' else 'rejected' end;
      if requested='approved' and coalesce((d->>'create_return_shipment')::boolean,false) and ret.return_delivery_id is null then
        select * into merch_acc from public.delivery_cloud_accounts where user_id=so.merchant_id;
        rev_details:=jsonb_build_object(
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
          shipping_fee,cod_amount,pricing_version,merchant_ready)
          values(so.owner_id,so.merchant_id,gen_random_uuid(),jsonb_build_object('return_id',ret.id),rev_details,
            (so.snapshot->>'distance_meters')::integer,(so.snapshot->>'shipping_fee')::integer,0,(so.snapshot->>'pricing_version')::integer,true)
          returning * into rev_ship;
        insert into public.delivery_live_rooms(id) values(rev_ship.tracking_code);
        insert into public.delivery_live_members values(rev_ship.tracking_code,so.owner_id,'customer'),(rev_ship.tracking_code,so.merchant_id,'merchant');
        insert into public.delivery_cloud_history(order_id,actor_id,action,status,version) values(rev_ship.id,auth.uid(),'create',rev_ship.status,1);
        insert into public.delivery_live_events(room_id,kind,payload) values(rev_ship.tracking_code,'status',jsonb_build_object('status',rev_ship.status,'version',1));
        ret.return_delivery_id:=rev_ship.id;
      end if;
    elsif requested='receive' and ret.state='approved' and (public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager') or op) then
      disp:=coalesce(d->>'disposition','writeoff');
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
      ret.disposition:=disp;
      requested:='received';
    else raise sqlstate 'PT403' using message='Không có quyền chuyển trạng thái trả hàng.';
    end if;
    update public.delivery_market_returns set state=requested,response=btrim(d->>'response'),
      return_delivery_id=ret.return_delivery_id,disposition=ret.disposition,version=version+1,updated_at=now()
      where id=ret.id returning * into ret;
    insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'return_'||requested,btrim(d->>'response'));
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'return_'||requested);
    return jsonb_build_object('return',to_jsonb(ret));

  elsif p_action='finance_request' then
    requested:=d->>'kind';
    if requested not in ('collection','refund','settlement') or requested is null then raise sqlstate 'PT400' using message='Loại yêu cầu không hợp lệ.'; end if;
    if not op and not (requested='settlement' and public.delivery_market_can_access_shop(so.shop_id,auth.uid(),'manager')) and not
      (requested='collection' and public.delivery_cloud_has_membership(a.user_id,'driver') and exists(select 1 from public.delivery_cloud_orders where id=so.delivery_id and driver_id=auth.uid())) and not
      (requested='refund' and so.owner_id=auth.uid()) then raise sqlstate 'PT403' using message='Không có quyền đề nghị khoản thu/chi này.'; end if;
    if jsonb_typeof(d->'amount') is distinct from 'number' or (d->>'amount')::numeric<>trunc((d->>'amount')::numeric) then raise sqlstate 'PT400' using message='Số tiền cần là số nguyên.'; end if;
    if d ? 'attachments' then
      if jsonb_typeof(d->'attachments')<>'array' or jsonb_array_length(d->'attachments')>5 then
        raise sqlstate 'PT400' using message='Tối đa 5 tệp chứng từ đính kèm.';
      end if;
      for att_name in select jsonb_array_elements_text(d->'attachments') loop
        if not exists(select 1 from public.delivery_market_attachments where name=att_name and order_id=so.id and scope='finance') then
          raise sqlstate 'PT403' using message='Chứng từ đính kèm không thuộc đơn này.';
        end if;
      end loop;
      att_list:=d->'attachments';
    end if;
    select * into f from public.delivery_market_finance where proposer=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if f.order_id<>so.id or f.kind<>requested or f.amount is distinct from (d->>'amount')::integer or f.reason is distinct from btrim(d->>'reason') or f.evidence is distinct from btrim(d->>'evidence') or f.return_id is distinct from (d->>'return_id')::uuid then raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.'; end if;
      return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
    end if;
    if (select count(*) from public.delivery_market_finance where order_id=so.id)>=100 then raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu thu/chi. Cần quản trị viên kiểm tra.'; end if;
    goods:=(so.snapshot->>'subtotal')::bigint;
    shop_disc:=coalesce((so.snapshot->>'shop_discount')::bigint,0);
    plat_disc:=coalesce((so.snapshot->>'platform_discount')::bigint,0);
    freight:=(so.snapshot->>'shipping_fee')::bigint;
    merch_net:=greatest(0,goods-shop_disc);
    due:=greatest(0,goods-shop_disc-plat_disc)+freight;
    select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    if requested='collection' and (so.delivered_at is null or (d->>'amount')::bigint<>due or exists(select 1 from public.delivery_market_finance where order_id=so.id and kind='collection' and state<>'rejected')) then raise sqlstate 'PT409' using message='COD chỉ được đề nghị đủ tiền một lần sau giao hàng.'; end if;
    if requested='refund' then
      select * into ret from public.delivery_market_returns where id=(d->>'return_id')::uuid and order_id=so.id and state='received';
      select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
      select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state<>'rejected';
      if ret.id is null or (d->>'amount')::bigint>ret.quantity*(item->>'unit_price')::bigint-used or (d->>'amount')::bigint>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled) then raise sqlstate 'PT409' using message='Chưa nhận hàng trả hoặc khoản hoàn vượt mức.'; end if;
    elsif requested='settlement' and ((d->>'amount')::bigint>least(merch_net-refunded-settled,collected+plat_disc-refunded-settled-freight) or so.delivered_at is null or so.delivered_at>now()-interval '7 days' or exists
      (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=r.line_id) v on true
        where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
        r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))) then raise sqlstate 'PT409' using message='Chưa có tiền hàng khả dụng để đối soát.';
    end if;
    insert into public.delivery_market_finance(order_id,kind,amount,return_id,proposer,reason,evidence,attachments,request_key)
      values(so.id,requested,(d->>'amount')::integer,(d->>'return_id')::uuid,auth.uid(),btrim(d->>'reason'),btrim(d->>'evidence'),att_list,(d->>'request_key')::uuid) returning * into f;
    return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
  else raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end$$;

-- Marketplace browse with flash sales, variant counts, service-radius filter & public shop_meta
create or replace function public.delivery_market_browse(p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; result jsonb; categories jsonb; shop jsonb; shop_meta jsonb;
  ordering text:=coalesce(d->>'sort','default');
  low integer:=0; high integer:=10000000; last_value jsonb;
  b_lat float8; b_lng float8; has_coords boolean:=false;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if not exists(select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and not blocked) then
    raise sqlstate 'PT403' using message='Tài khoản chưa được xác minh hoặc đã bị khóa.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 or
    d-array['search','category','shop_id','min_price','max_price','in_stock','sort','after','after_value','buyer_lat','buyer_lng']<>'{}' or
    ordering not in ('default','price_asc','price_desc','newest') then raise sqlstate 'PT400' using message='Bộ lọc không hợp lệ.'; end if;
  if (d?'search' and (jsonb_typeof(d->'search')<>'string' or length(d->>'search')>160)) or
    (d?'category' and (jsonb_typeof(d->'category')<>'string' or length(d->>'category')>80)) or
    (d?'in_stock' and jsonb_typeof(d->'in_stock')<>'boolean') or
    ((d?'buyer_lat')<>(d?'buyer_lng')) then raise sqlstate 'PT400' using message='Bộ lọc không hợp lệ.'; end if;
  if d?'buyer_lat' then
    if jsonb_typeof(d->'buyer_lat')<>'number' or jsonb_typeof(d->'buyer_lng')<>'number' or
       abs((d->>'buyer_lat')::float8)>90 or abs((d->>'buyer_lng')::float8)>180 then
      raise sqlstate 'PT400' using message='Tọa độ lọc cửa hàng không hợp lệ.';
    end if;
    b_lat:=(d->>'buyer_lat')::float8; b_lng:=(d->>'buyer_lng')::float8; has_coords:=true;
  end if;
  if d?'min_price' then
    if jsonb_typeof(d->'min_price')<>'number' or (d->>'min_price')::numeric not between 0 and 10000000 or
      (d->>'min_price')::numeric<>trunc((d->>'min_price')::numeric) then raise sqlstate 'PT400' using message='Giá tối thiểu không hợp lệ.'; end if;
    low:=(d->>'min_price')::integer;
  end if;
  if d?'max_price' then
    if jsonb_typeof(d->'max_price')<>'number' or (d->>'max_price')::numeric not between 0 and 10000000 or
      (d->>'max_price')::numeric<>trunc((d->>'max_price')::numeric) then raise sqlstate 'PT400' using message='Giá tối đa không hợp lệ.'; end if;
    high:=(d->>'max_price')::integer;
  end if;
  if low>high or (d?'after')<>(d?'after_value') or
    (d?'after_value' and (jsonb_typeof(d->'after_value')<>'number' or abs((d->>'after_value')::numeric)>3000000000000)) then
    raise sqlstate 'PT400' using message='Khoảng giá hoặc trang tiếp theo không hợp lệ.';
  end if;
  if d?'shop_id' then
    select jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'address',s.address,'paused',s.paused,'opening_schedule',s.opening_schedule,'open',not s.paused and public.delivery_market_is_open(s.opening_schedule)),
           jsonb_build_object('banner_url',s.banner_url,'service_radius_km',s.service_radius_km,
             'followers',(select count(*) from public.delivery_market_shop_follows f where f.shop_id=s.id),
             'following',exists(select 1 from public.delivery_market_shop_follows f where f.shop_id=s.id and f.user_id=auth.uid()),
             'rating_avg',coalesce((select round(avg(rating)::numeric,2) from public.delivery_partner_reviews pr where pr.target_kind='shop' and pr.shop_id=s.id and not pr.hidden),0),
             'rating_count',(select count(*) from public.delivery_partner_reviews pr where pr.target_kind='shop' and pr.shop_id=s.id and not pr.hidden))
      into shop,shop_meta from public.delivery_market_shops s join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where s.id=(d->>'shop_id')::uuid and s.status='active' and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant');
    if shop is null then raise sqlstate 'PT404' using message='Cửa hàng không còn khả dụng.'; end if;
  end if;
  select coalesce(jsonb_agg(category order by category),'[]') into categories from (
    select distinct p.category from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
      join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant')
        and (not(d?'shop_id') or s.id=(d->>'shop_id')::uuid) order by p.category limit 100
  ) c;
  with visible as (
    select p.*,s.name as shop_name,
      (p.stock>0 or exists(select 1 from public.delivery_market_variants v where v.product_id=p.id and v.published and v.stock>0))
        and public.delivery_market_is_open(p.sale_schedule) and public.delivery_market_is_open(s.opening_schedule) as available,
      (select count(*)::int from public.delivery_market_variants v where v.product_id=p.id and v.published) as variants_count,
      (select jsonb_build_object('id',fs.id,'sale_price',fs.sale_price,'allocated_stock',fs.allocated_stock,'sold_stock',fs.sold_stock,'ends_at',fs.ends_at)
        from public.delivery_market_flash_sales fs where fs.product_id=p.id and fs.active and fs.starts_at<=now() and fs.ends_at>now() and fs.sold_stock<fs.allocated_stock
        order by fs.sale_price asc,fs.id asc limit 1) as flash_sale,
      case ordering when 'price_asc' then p.price::numeric when 'price_desc' then -p.price::numeric
        when 'newest' then -extract(epoch from p.updated_at) else 0::numeric end as sort_value
      from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
      join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant')
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d?'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and (not has_coords or s.service_radius_km=0 or (
          6371000.0*2.0*asin(sqrt(least(1.0,power(sin(radians(b_lat-s.latitude)/2),2)+cos(radians(s.latitude))*cos(radians(b_lat))*power(sin(radians(b_lng-s.longitude)/2),2))))*1.3 <= s.service_radius_km*1000.0
        ))
        and p.price between low and high
        and (coalesce((d->>'in_stock')::boolean,false)=false or p.stock>0 or exists(select 1 from public.delivery_market_variants v where v.product_id=p.id and v.published and v.stock>0))
  ) select coalesce(jsonb_agg(to_jsonb(x) order by sort_value,id),'[]') into result from (
    select * from visible where not(d?'after') or (sort_value,id)>((d->>'after_value')::numeric,(d->>'after')::uuid)
      order by sort_value,id limit 50
  ) x;
  last_value:=result->49;
  return jsonb_build_object(
    'products',coalesce((select jsonb_agg(i-'sort_value' order by ord) from jsonb_array_elements(result) with ordinality as r(i,ord)),'[]'),
    'categories',categories,
    'shop',shop,
    'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',last_value->>'id','after_value',last_value->'sort_value') end
  ) || case when shop_meta is not null then jsonb_build_object('shop_meta',shop_meta) else '{}'::jsonb end;
end $$;

revoke all on function
  public.delivery_market_media_reserve(uuid,text,integer),
  public.delivery_market_media_can_upload(text),
  public.delivery_market_attachment_reserve(uuid,text,text,integer),
  public.delivery_market_attachment_can_upload(text),
  public.delivery_market_attachment_can_read(text),
  public.delivery_cloud_order_otp(uuid),
  public.delivery_cloud_share_manage(uuid,text,uuid),
  public.delivery_cloud_quote(jsonb),
  public.delivery_cloud_create(jsonb,uuid,integer,integer),
  public.delivery_cloud_transition(uuid,text,integer,uuid,text),
  public.delivery_marketplace(text,jsonb),
  public.delivery_market_operations(text,jsonb),
  public.delivery_market_browse(jsonb)
from public,anon;

grant execute on function
  public.delivery_market_media_reserve(uuid,text,integer),
  public.delivery_market_media_can_upload(text),
  public.delivery_market_attachment_reserve(uuid,text,text,integer),
  public.delivery_market_attachment_can_upload(text),
  public.delivery_market_attachment_can_read(text),
  public.delivery_cloud_order_otp(uuid),
  public.delivery_cloud_share_manage(uuid,text,uuid),
  public.delivery_cloud_quote(jsonb),
  public.delivery_cloud_create(jsonb,uuid,integer,integer),
  public.delivery_cloud_transition(uuid,text,integer,uuid,text),
  public.delivery_marketplace(text,jsonb),
  public.delivery_market_operations(text,jsonb),
  public.delivery_market_browse(jsonb)
to authenticated;

revoke all on function public.delivery_market_public_tracking(text), public.delivery_cloud_public_lookup(text,text) from public;
grant execute on function public.delivery_market_public_tracking(text), public.delivery_cloud_public_lookup(text,text) to anon,authenticated;

notify pgrst,'reload schema';
commit;
