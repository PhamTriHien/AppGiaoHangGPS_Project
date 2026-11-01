-- Additive marketplace foundation. Requires cloud orders, payments and addresses.
-- No business/demo rows are seeded. App roles can use only the fixed RPC below.
begin;
create table if not exists public.delivery_market_shops (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.delivery_cloud_accounts(user_id),
  name text not null check(length(name) between 1 and 120),
  description text not null default '' check(length(description)<=2000),
  address text not null check(length(address) between 5 and 500),
  latitude double precision not null check(latitude between -90 and 90),
  longitude double precision not null check(longitude between -180 and 180),
  status text not null default 'pending' check(status in ('pending','active','suspended')),
  paused boolean not null default false,
  version integer not null default 1 check(version>0), updated_at timestamptz not null default now()
);
create table if not exists public.delivery_market_products (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.delivery_market_shops(id),
  name text not null check(length(name) between 1 and 160),
  description text not null default '' check(length(description)<=4000),
  category text not null check(length(category) between 1 and 80),
  sku text not null check(length(sku) between 1 and 80),
  image_url text not null default '' check(length(image_url)<=1000 and (image_url='' or image_url ~ '^https://')),
  price integer not null check(price between 1 and 10000000),
  stock integer not null check(stock between 0 and 1000000),
  weight_kg numeric not null check(weight_kg between 0.01 and 30),
  published boolean not null default false, version integer not null default 1 check(version>0),
  updated_at timestamptz not null default now(), unique(shop_id,sku)
);
create index if not exists delivery_market_products_shop on public.delivery_market_products(shop_id,id);
create table if not exists public.delivery_market_stock (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.delivery_market_products(id),
  actor_id uuid references auth.users(id), actor_source text not null default 'user' check(actor_source in ('user','carrier')),
  delta integer not null, check(actor_source='carrier' or actor_id is not null),
  reason text not null, reference_id uuid, created_at timestamptz not null default now()
);
create table if not exists public.delivery_market_carts (
  user_id uuid primary key references public.delivery_cloud_accounts(user_id), version integer not null default 1
);
create table if not exists public.delivery_market_cart_items (
  user_id uuid not null references public.delivery_market_carts(user_id),
  product_id uuid not null references public.delivery_market_products(id),
  quantity integer not null check(quantity between 1 and 99), primary key(user_id,product_id)
);
create table if not exists public.delivery_market_quotes (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
  snapshot jsonb not null, expires_at timestamptz not null default (now()+interval '5 minutes'),
  created_at timestamptz not null default now()
);
create table if not exists public.delivery_market_purchases (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
  request_key uuid not null, quote_id uuid not null unique references public.delivery_market_quotes(id),
  snapshot jsonb not null, total integer not null check(total between 1 and 100000000),
  payment_method text not null default 'cod' check(payment_method='cod'),
  payment_status text not null default 'UNPAID' check(payment_status in ('UNPAID','REVIEW','PAID')),
  created_at timestamptz not null default now(), unique(owner_id,request_key)
);
create table if not exists public.delivery_market_shop_orders (
  id uuid primary key default gen_random_uuid(), purchase_id uuid not null references public.delivery_market_purchases(id),
  shop_id uuid not null references public.delivery_market_shops(id), owner_id uuid not null references auth.users(id),
  merchant_id uuid not null references auth.users(id), snapshot jsonb not null,
  state text not null default 'pending' check(state in ('pending','accepted','ready','cancelled')),
  delivery_id uuid unique references public.delivery_cloud_orders(id),
  version integer not null default 1, reason text not null default '',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(purchase_id,shop_id)
);
create index if not exists delivery_market_shop_orders_owner on public.delivery_market_shop_orders(owner_id,id);
create index if not exists delivery_market_shop_orders_merchant on public.delivery_market_shop_orders(merchant_id,id);
create table if not exists public.delivery_market_events (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.delivery_market_shop_orders(id),
  actor_id uuid references auth.users(id), actor_source text not null default 'user' check(actor_source in ('user','carrier')),
  action text not null, check(actor_source='carrier' or actor_id is not null),
  reason text not null default '', created_at timestamptz not null default now()
);
create table if not exists public.delivery_market_messages (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.delivery_market_shop_orders(id),
  actor_id uuid not null references auth.users(id), body text not null check(length(body) between 1 and 2000),
  request_key uuid not null, created_at timestamptz not null default now(), unique(actor_id,request_key)
);
create table if not exists public.delivery_market_notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
  order_id uuid not null references public.delivery_market_shop_orders(id),
  kind text not null, read_at timestamptz, created_at timestamptz not null default now()
);
create index if not exists delivery_market_notifications_owner on public.delivery_market_notifications(user_id,id);

do $$ declare n text; begin
  foreach n in array array['shops','products','stock','carts','cart_items','quotes','purchases','shop_orders','events','messages','notifications'] loop
    execute format('alter table public.delivery_market_%I enable row level security',n);
    execute format('revoke all on public.delivery_market_%I from public, anon, authenticated',n);
  end loop;
end $$;

-- Internal snapshot builder. No caller can execute this helper directly.
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
      where user_id=s.owner_id and role='merchant' and not blocked) then
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
revoke all on function public.delivery_market_snapshot(uuid) from public,anon,authenticated;

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
      where p.published and s.status='active' and not s.paused and not a.blocked and a.role='merchant'
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d ? 'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid)
      order by p.id limit 50
    ) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action='workspace' then
    if actor.role<>'merchant' and not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    result:=jsonb_build_object('shops',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
      (select * from public.delivery_market_shops where (owner_id=auth.uid() or d->>'moderation'='true' and public.delivery_is_operator())
        and (d->>'moderation' is distinct from 'true' or not(d ? 'after') or id>(d->>'after')::uuid) order by id limit 50) x),'[]'),
      'products',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
      (select p.* from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
        where s.owner_id=auth.uid() and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x),'[]'));
    snapshot:=result->case when d->>'moderation'='true' then 'shops' else 'products' end;
    return result||jsonb_build_object('next',case when jsonb_array_length(snapshot)=50 then jsonb_build_object('after',snapshot->49->>'id') end);
  elsif p_action='shop_save' then
    if actor.role<>'merchant' then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
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
    if actor.role<>'merchant' then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
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
          not exists(select 1 from public.delivery_cloud_accounts where user_id=sh.owner_id and role='merchant' and not blocked) then
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
      where (case when d->>'workspace'='merchant' then o.merchant_id=auth.uid() and actor.role='merchant' else o.owner_id=auth.uid() end)
        and (not(d ? 'after') or o.id>(d->>'after')::uuid) order by o.id limit 50) x;
    return jsonb_build_object('orders',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action in ('order_action','messages','message_send') then
    select * into so from public.delivery_market_shop_orders where delivery_market_shop_orders.id=(d->>'order_id')::uuid
      and (owner_id=auth.uid() or merchant_id=auth.uid() and actor.role='merchant') for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
    if p_action='order_action' then
      requested:=d->>'action';
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if requested not in ('accept','ready','cancel') or requested is null then raise sqlstate 'PT400' using message='Thao tác không hợp lệ.'; end if;
      if requested in ('accept','ready') and (so.merchant_id<>auth.uid() or actor.role<>'merchant') then raise sqlstate 'PT403' using message='Chỉ cửa hàng xử lý đơn mua hàng.'; end if;
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
revoke all on function public.delivery_marketplace(text,jsonb) from public,anon;
grant execute on function public.delivery_marketplace(text,jsonb) to authenticated;

-- Shipping cancellation must release the purchase allocation in the same
-- transaction, even when initiated through the existing shipping API.
create or replace function public.delivery_market_shipping_cancel() returns trigger
language plpgsql security definer set search_path='' as $$
declare so public.delivery_market_shop_orders; item jsonb; source text:='user';
begin
  if new.status='cancelled' and old.status is distinct from new.status then
    select * into so from public.delivery_market_shop_orders where delivery_id=new.id for update;
    if so.id is not null and so.state<>'cancelled' then
      if auth.uid() is null then
        if current_setting('ghst.carrier_sync',true) is distinct from 'on' then raise sqlstate 'PT403' using message='Thiếu nguồn hủy vận đơn.'; end if;
        source:='carrier';
      end if;
      perform 1 from public.delivery_market_products where id in
        (select (i->>'product_id')::uuid from jsonb_array_elements(so.snapshot->'items') i) order by id for update;
      for item in select * from jsonb_array_elements(so.snapshot->'items') loop
        update public.delivery_market_products set stock=stock+(item->>'quantity')::integer,version=version+1,updated_at=now()
          where id=(item->>'product_id')::uuid;
        insert into public.delivery_market_stock(product_id,actor_id,actor_source,delta,reason,reference_id)
          values((item->>'product_id')::uuid,auth.uid(),source,(item->>'quantity')::integer,'shipping_cancel_release',so.id);
      end loop;
      update public.delivery_market_shop_orders set state='cancelled',reason=coalesce(new.cancel_reason,''),version=version+1,updated_at=now() where id=so.id;
      insert into public.delivery_market_events(order_id,actor_id,actor_source,action,reason) values(so.id,auth.uid(),source,'shipping_cancel',coalesce(new.cancel_reason,''));
      insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'cancel'),(so.merchant_id,so.id,'cancel');
    end if;
  end if;
  return new;
end $$;
revoke all on function public.delivery_market_shipping_cancel() from public,anon,authenticated;
drop trigger if exists delivery_market_shipping_cancel on public.delivery_cloud_orders;
create trigger delivery_market_shipping_cancel after update of status on public.delivery_cloud_orders
  for each row execute function public.delivery_market_shipping_cancel();
notify pgrst,'reload schema';
commit;
