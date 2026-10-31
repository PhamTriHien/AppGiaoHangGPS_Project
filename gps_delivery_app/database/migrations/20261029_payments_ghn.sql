-- Requires the two previous delivery migrations. Reapplying preserves all rows.
begin;
alter table public.delivery_cloud_orders drop constraint if exists delivery_cloud_orders_payment_status_check;
alter table public.delivery_cloud_orders add constraint delivery_cloud_orders_payment_status_check
  check (payment_status in ('UNPAID','PAID','REVIEW'));
alter table public.delivery_cloud_orders add column if not exists fulfillment_provider text check(fulfillment_provider='ghn');
alter table public.delivery_cloud_orders add column if not exists carrier_code text;
alter table public.delivery_cloud_orders add column if not exists carrier_status text;

create table if not exists public.delivery_payment_transactions (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'payos' check(provider='payos'),
  provider_order_code bigint generated always as identity(start with 100000) unique check(provider_order_code<9007199254740991),
  order_id uuid not null references public.delivery_cloud_orders(id),
  owner_id uuid not null references auth.users(id),
  amount integer not null check(amount between 1 and 100000000),
  status text not null check(status in ('CREATING','PENDING','PAID','REVIEW','CANCELLED','EXPIRED')),
  payment_link_id text,
  checkout_url text,
  qr_code text,
  expires_at timestamptz not null default (now()+interval '15 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists delivery_payment_order on public.delivery_payment_transactions(order_id,created_at desc);
create unique index if not exists delivery_payment_active on public.delivery_payment_transactions(order_id)
  where status in ('CREATING','PENDING','PAID','REVIEW');
create table if not exists public.delivery_payment_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.delivery_payment_transactions(id),
  reference text unique not null check(length(reference) between 1 and 200),
  amount integer not null check(amount between 1 and 100000000),
  received_at timestamptz not null default now()
);
create table if not exists public.delivery_ghn_quotes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.delivery_cloud_orders(id),
  order_version integer not null,
  created_by uuid not null references auth.users(id),
  payload jsonb not null,
  total_fee integer not null check(total_fee>=0),
  base_url text not null,
  shop_id text not null,
  expires_at timestamptz not null default (now()+interval '10 minutes')
);
create table if not exists public.delivery_ghn_shipments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid unique not null references public.delivery_cloud_orders(id),
  created_by uuid not null references auth.users(id),
  quote_id uuid not null references public.delivery_ghn_quotes(id),
  client_order_code text unique not null,
  ghn_order_code text unique,
  status text not null default 'CREATING',
  base_url text not null,
  shop_id text not null,
  payload jsonb not null,
  total_fee integer,
  expected_delivery_time timestamptz,
  provider_updated_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.delivery_ghn_events (
  event_key text primary key,
  shipment_id uuid not null references public.delivery_ghn_shipments(id),
  received_at timestamptz not null default now()
);
alter table public.delivery_payment_transactions enable row level security;
alter table public.delivery_payment_receipts enable row level security;
alter table public.delivery_ghn_quotes enable row level security;
alter table public.delivery_ghn_shipments enable row level security;
alter table public.delivery_ghn_events enable row level security;
revoke all on public.delivery_payment_transactions, public.delivery_payment_receipts, public.delivery_ghn_quotes,
  public.delivery_ghn_shipments, public.delivery_ghn_events from public,anon,authenticated;
revoke all on sequence public.delivery_payment_transactions_provider_order_code_seq from public,anon,authenticated;

create or replace function public.delivery_commerce_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status is distinct from old.status or new.driver_id is distinct from old.driver_id or
      new.merchant_ready is distinct from old.merchant_ready or new.fulfillment_provider is distinct from old.fulfillment_provider then
    if coalesce(current_setting('ghst.carrier_sync',true),'')<>'on' and exists(select 1 from public.delivery_payment_transactions where order_id=old.id and status in ('CREATING','PENDING','REVIEW')) then
      raise sqlstate 'PT409' using message='Cần hoàn tất, hủy liên kết thanh toán hoặc đối soát trước khi điều phối/hủy đơn.';
    end if;
    if old.fulfillment_provider='ghn' and coalesce(current_setting('ghst.carrier_sync',true),'')<>'on' then
      raise sqlstate 'PT409' using message='Đơn GHN phải được cập nhật qua hãng vận chuyển.';
    end if;
  end if;
  if new.fulfillment_provider='ghn' and new.driver_id is not null then
    raise sqlstate 'PT409' using message='Không gán tài xế nội bộ cho đơn GHN.';
  end if;
  if old.payment_status='PAID' and new.status in ('cancelled','returned') then
    new.payment_status:='REVIEW';
    update public.delivery_payment_transactions set status='REVIEW',updated_at=now()
      where order_id=new.id and status='PAID';
  end if;
  return new;
end; $$;
revoke all on function public.delivery_commerce_guard() from public,anon,authenticated;
drop trigger if exists delivery_commerce_guard on public.delivery_cloud_orders;
create trigger delivery_commerce_guard before update on public.delivery_cloud_orders
  for each row execute function public.delivery_commerce_guard();
commit;
