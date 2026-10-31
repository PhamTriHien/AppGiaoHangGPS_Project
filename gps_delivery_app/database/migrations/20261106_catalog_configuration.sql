-- Configured cart lines keep immutable option prices and per-line return bounds.
begin;
alter table public.delivery_market_products
  add column if not exists option_groups jsonb not null default '[]',
  add column if not exists sale_schedule jsonb not null default '[]',
  add column if not exists preparation_minutes integer not null default 0 check(preparation_minutes between 0 and 1440),
  add column if not exists images jsonb not null default '[]';
alter table public.delivery_market_shops add column if not exists opening_schedule jsonb not null default '[]';
alter table public.delivery_market_cart_items
  add column if not exists line_id uuid,
  add column if not exists selected_options jsonb not null default '[]';
update public.delivery_market_cart_items set line_id=product_id where line_id is null;
alter table public.delivery_market_cart_items alter column line_id set not null;
alter table public.delivery_market_cart_items drop constraint if exists delivery_market_cart_items_pkey;
alter table public.delivery_market_cart_items add primary key(user_id,line_id);
create index if not exists delivery_market_cart_items_product on public.delivery_market_cart_items(user_id,product_id);
alter table public.delivery_market_returns add column if not exists line_id uuid;
update public.delivery_market_returns set line_id=product_id where line_id is null;
create or replace function public.delivery_market_return_line() returns trigger
language plpgsql set search_path='' as $$begin
  new.line_id:=coalesce(new.line_id,new.product_id);return new;
end$$;
revoke all on function public.delivery_market_return_line() from public,anon,authenticated;
drop trigger if exists delivery_market_return_line on public.delivery_market_returns;
create trigger delivery_market_return_line before insert on public.delivery_market_returns
  for each row execute function public.delivery_market_return_line();
alter table public.delivery_market_returns alter column line_id set not null;

create or replace function public.delivery_market_schedule_valid(p_schedule jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare slot jsonb; seen jsonb:='[]';
begin
  if jsonb_typeof(p_schedule) is distinct from 'array' or jsonb_array_length(p_schedule)>28 then return false; end if;
  for slot in select * from jsonb_array_elements(p_schedule) loop
    if jsonb_typeof(slot) is distinct from 'object' or slot-array['day','open','close']<>'{}' or
      not(slot?&array['day','open','close']) or jsonb_typeof(slot->'day') is distinct from 'number' or
      jsonb_typeof(slot->'open') is distinct from 'number' or jsonb_typeof(slot->'close') is distinct from 'number' then return false; end if;
    if (slot->>'day')::numeric not between 1 and 7 or (slot->>'day')::numeric<>trunc((slot->>'day')::numeric) or
      (slot->>'open')::numeric not between 0 and 1439 or (slot->>'open')::numeric<>trunc((slot->>'open')::numeric) or
      (slot->>'close')::numeric not between 1 and 1440 or (slot->>'close')::numeric<>trunc((slot->>'close')::numeric) or
      (slot->>'open')::numeric>=(slot->>'close')::numeric then return false; end if;
    if exists(select 1 from jsonb_array_elements(seen) s where s->>'day'=slot->>'day' and
      (s->>'open')::integer<(slot->>'close')::integer and (slot->>'open')::integer<(s->>'close')::integer) then return false; end if;
    seen:=seen||jsonb_build_array(slot);
  end loop;
  return true;
end$$;
create or replace function public.delivery_market_is_open(p_schedule jsonb,p_at timestamptz default now()) returns boolean
language sql stable set search_path='' as $$
  select case when p_schedule='[]'::jsonb then true else exists(
    select 1 from jsonb_array_elements(p_schedule) s
    where (s->>'day')::integer=extract(isodow from p_at at time zone 'Asia/Ho_Chi_Minh') and
      extract(hour from p_at at time zone 'Asia/Ho_Chi_Minh')*60+extract(minute from p_at at time zone 'Asia/Ho_Chi_Minh')
        >=(s->>'open')::integer and
      extract(hour from p_at at time zone 'Asia/Ho_Chi_Minh')*60+extract(minute from p_at at time zone 'Asia/Ho_Chi_Minh')
        <(s->>'close')::integer) end;
$$;
revoke all on function public.delivery_market_schedule_valid(jsonb),public.delivery_market_is_open(jsonb,timestamptz) from public,anon,authenticated;

create or replace function public.delivery_market_catalog_guard() returns trigger
language plpgsql set search_path='' as $$
declare g jsonb; choice jsonb; groups text[]:='{}'; choices text[]; total_options integer:=0;
begin
  if tg_table_name='delivery_market_shops' then
    if not public.delivery_market_schedule_valid(new.opening_schedule) then raise sqlstate 'PT400' using message='Giờ hoạt động không hợp lệ.'; end if;
    return new;
  end if;
  if not public.delivery_market_schedule_valid(new.sale_schedule) or jsonb_typeof(new.images) is distinct from 'array'
    or jsonb_array_length(new.images)>8 or exists(select 1 from jsonb_array_elements(new.images) i
      where jsonb_typeof(i)<>'string' or length(i#>>'{}')>1000 or (i#>>'{}')!~'^https://[^/]+/') then
    raise sqlstate 'PT400' using message='Lịch bán hoặc bộ ảnh không hợp lệ.';
  end if;
  if jsonb_typeof(new.option_groups) is distinct from 'array' or jsonb_array_length(new.option_groups)>6 or
    octet_length(new.option_groups::text)>12000 then raise sqlstate 'PT400' using message='Tối đa 6 nhóm lựa chọn.'; end if;
  for g in select * from jsonb_array_elements(new.option_groups) loop
    if jsonb_typeof(g) is distinct from 'object' or g-array['id','name','min','max','options']<>'{}' or
      not(g?&array['id','name','min','max','options']) or jsonb_typeof(g->'id') is distinct from 'string' or
      jsonb_typeof(g->'name') is distinct from 'string' or jsonb_typeof(g->'min') is distinct from 'number' or
      jsonb_typeof(g->'max') is distinct from 'number' or jsonb_typeof(g->'options') is distinct from 'array' then
      raise sqlstate 'PT400' using message='Nhóm lựa chọn không hợp lệ.'; end if;
    if g->>'id'!~'^[a-zA-Z0-9_-]{1,40}$' or g->>'id'=any(groups) or length(btrim(g->>'name')) not between 1 and 80 or
      (g->>'min')::numeric<>trunc((g->>'min')::numeric) or (g->>'max')::numeric<>trunc((g->>'max')::numeric) or
      (g->>'min')::numeric<0 or (g->>'max')::numeric<(g->>'min')::numeric or
      (g->>'max')::numeric not between 1 and 12 or jsonb_array_length(g->'options') not between 1 and 12 or
      (g->>'max')::integer>jsonb_array_length(g->'options') then raise sqlstate 'PT400' using message='Giới hạn hoặc mã nhóm lựa chọn không hợp lệ.'; end if;
    groups:=array_append(groups,g->>'id'); choices:='{}';
    for choice in select * from jsonb_array_elements(g->'options') loop
      if jsonb_typeof(choice) is distinct from 'object' or choice-array['id','name','price']<>'{}' or
        not(choice?&array['id','name','price']) or jsonb_typeof(choice->'id') is distinct from 'string' or
        jsonb_typeof(choice->'name') is distinct from 'string' or jsonb_typeof(choice->'price') is distinct from 'number' then
        raise sqlstate 'PT400' using message='Lựa chọn không hợp lệ.'; end if;
      if choice->>'id'!~'^[a-zA-Z0-9_-]{1,40}$' or choice->>'id'=any(choices) or length(btrim(choice->>'name')) not between 1 and 80 or
        (choice->>'price')::numeric not between 0 and 1000000 or (choice->>'price')::numeric<>trunc((choice->>'price')::numeric) then
        raise sqlstate 'PT400' using message='Mã hoặc phụ thu lựa chọn không hợp lệ.'; end if;
      choices:=array_append(choices,choice->>'id'); total_options:=total_options+1;
    end loop;
  end loop;
  return new;
end$$;
revoke all on function public.delivery_market_catalog_guard() from public,anon,authenticated;
drop trigger if exists delivery_market_catalog_guard on public.delivery_market_products;
create trigger delivery_market_catalog_guard before insert or update on public.delivery_market_products
  for each row execute function public.delivery_market_catalog_guard();
drop trigger if exists delivery_market_catalog_guard on public.delivery_market_shops;
create trigger delivery_market_catalog_guard before insert or update on public.delivery_market_shops
  for each row execute function public.delivery_market_catalog_guard();

create or replace function public.delivery_market_selection(p_product uuid,p_selected jsonb default '[]') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.delivery_market_products; g jsonb; opt jsonb; chosen jsonb; normalized jsonb; snapshots jsonb:='[]';
  matched integer:=0; qty integer; amount bigint; lid uuid;
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
  amount:=p.price;
  for g in select * from jsonb_array_elements(p.option_groups) loop
    select count(*) into qty from jsonb_array_elements(normalized) s where s->>'group_id'=g->>'id';
    if qty<(g->>'min')::integer or qty>(g->>'max')::integer then raise sqlstate 'PT409' using message='Cần chọn đúng số lượng cho '||(g->>'name')||'.'; end if;
    for opt in select * from jsonb_array_elements(g->'options') o where exists(
      select 1 from jsonb_array_elements(normalized) s where s->>'group_id'=g->>'id' and s->>'option_id'=o->>'id') order by o->>'id' loop
      matched:=matched+1;amount:=amount+(opt->>'price')::integer;
      snapshots:=snapshots||jsonb_build_array(jsonb_build_object('group_id',g->>'id','group_name',g->>'name',
        'option_id',opt->>'id','name',opt->>'name','price',opt->'price'));
    end loop;
  end loop;
  if matched<>jsonb_array_length(normalized) or amount>10000000 then raise sqlstate 'PT409' using message='Lựa chọn đã thay đổi hoặc vượt giới hạn giá.'; end if;
  lid:=case when normalized='[]'::jsonb then p.id else md5(p.id::text||':'||normalized::text)::uuid end;
  return jsonb_build_object('line_id',lid,'selected_options',normalized,'options',snapshots,'unit_price',amount);
end$$;
revoke all on function public.delivery_market_selection(uuid,jsonb) from public,anon,authenticated;

create or replace function public.delivery_market_configured_cart() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]'; row record; selection jsonb; available boolean; cv integer;
begin
  select version into cv from public.delivery_market_carts where user_id=auth.uid();
  for row in select p.*,c.line_id,c.selected_options,c.quantity,s.name as shop_name,s.status as shop_status,s.paused,
    s.opening_schedule,m.blocked as merchant_blocked,public.delivery_cloud_has_membership(m.user_id,'merchant') as merchant_active
    from public.delivery_market_cart_items c join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
    where c.user_id=auth.uid() order by p.shop_id,c.line_id loop
    begin
      selection:=public.delivery_market_selection(row.id,row.selected_options);
      available:=row.published and row.shop_status='active' and not row.paused and not row.merchant_blocked and row.merchant_active and
        public.delivery_market_is_open(row.opening_schedule) and public.delivery_market_is_open(row.sale_schedule) and
        row.stock>=(select sum(quantity) from public.delivery_market_cart_items where user_id=auth.uid() and product_id=row.id);
    exception when sqlstate 'PT409' or sqlstate 'PT404' then
      selection:=jsonb_build_object('unit_price',null,'options','[]'::jsonb);available:=false;
    end;
    result:=result||jsonb_build_array((to_jsonb(row)-array['merchant_blocked','merchant_active','opening_schedule'])||selection||jsonb_build_object('available',available));
  end loop;
  return jsonb_build_object('version',coalesce(cv,1),'items',result);
end$$;
revoke all on function public.delivery_market_configured_cart() from public,anon,authenticated;

create or replace function public.delivery_market_snapshot(p_address uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.delivery_cloud_addresses; s record; i record; items jsonb; shops jsonb:='[]';
  subtotal bigint; total bigint:=0; weight numeric; details jsonb; q jsonb; cart_version integer; selection jsonb;
begin
  select * into a from public.delivery_cloud_addresses where id=p_address and user_id=auth.uid();
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy địa chỉ nhận hàng.'; end if;
  select version into cart_version from public.delivery_market_carts where user_id=auth.uid();
  if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid()) then
    raise sqlstate 'PT400' using message='Giỏ hàng đang trống.'; end if;
  for s in select distinct sh.* from public.delivery_market_cart_items c
    join public.delivery_market_products p on p.id=c.product_id
    join public.delivery_market_shops sh on sh.id=p.shop_id where c.user_id=auth.uid() order by sh.id loop
    if s.status<>'active' or s.paused or not public.delivery_market_is_open(s.opening_schedule) or
      not exists(select 1 from public.delivery_cloud_accounts where user_id=s.owner_id and
        public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
      raise sqlstate 'PT409' using message='Cửa hàng tạm ngừng nhận đơn.'; end if;
    if s.owner_id=auth.uid() then raise sqlstate 'PT400' using message='Không thể mua hàng từ cửa hàng của chính mình.'; end if;
    items:='[]'; subtotal:=0; weight:=0;
    for i in select p.*,c.quantity,c.line_id,c.selected_options from public.delivery_market_cart_items c
      join public.delivery_market_products p on p.id=c.product_id
      where c.user_id=auth.uid() and p.shop_id=s.id order by p.id,c.line_id loop
      if not i.published or not public.delivery_market_is_open(i.sale_schedule) or
        i.stock<(select sum(quantity) from public.delivery_market_cart_items where user_id=auth.uid() and product_id=i.id) then
        raise sqlstate 'PT409' using message='Sản phẩm ngừng bán hoặc không đủ tồn kho.'; end if;
      selection:=public.delivery_market_selection(i.id,i.selected_options);
      subtotal:=subtotal+(selection->>'unit_price')::bigint*i.quantity;weight:=weight+i.weight_kg*i.quantity;
      items:=items||jsonb_build_array(jsonb_build_object('product_id',i.id,'line_id',i.line_id,'name',i.name,'sku',i.sku,
        'quantity',i.quantity,'unit_price',selection->'unit_price','selected_options',selection->'selected_options',
        'options',selection->'options','preparation_minutes',i.preparation_minutes,
        'version',i.terms_version,'image_url',i.image_url));
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
end$$;
revoke all on function public.delivery_market_snapshot(uuid) from public,anon,authenticated;

create or replace function public.delivery_marketplace(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor public.delivery_cloud_accounts; sh public.delivery_market_shops; prod public.delivery_market_products;
  previous public.delivery_market_products; purchase public.delivery_market_purchases; so public.delivery_market_shop_orders;
  quote public.delivery_market_quotes; shipment public.delivery_cloud_orders; msg public.delivery_market_messages;
  d jsonb:=p_payload; result jsonb; snapshot jsonb; group_row jsonb; item jsonb;
  cart_version integer; qty integer; product_key uuid; requested text; line_key uuid; selected jsonb; selection jsonb; aggregate_qty bigint;
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
      where p.published and s.status='active' and not s.paused and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant')
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d ? 'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid)
      order by p.id limit 50
    ) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action='workspace' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') and not public.delivery_is_operator() then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    result:=jsonb_build_object('shops',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
      (select * from public.delivery_market_shops where (owner_id=auth.uid() or d->>'moderation'='true' and public.delivery_is_operator())
        and (d->>'moderation' is distinct from 'true' or not(d ? 'after') or id>(d->>'after')::uuid) order by id limit 50) x),'[]'),
      'products',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from
      (select p.* from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
        where s.owner_id=auth.uid() and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x),'[]'));
    snapshot:=result->case when d->>'moderation'='true' then 'shops' else 'products' end;
    return result||jsonb_build_object('next',case when jsonb_array_length(snapshot)=50 then jsonb_build_object('after',snapshot->49->>'id') end);
  elsif p_action='shop_save' then
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    if d-array['name','description','address','latitude','longitude','paused','version','opening_schedule']<>'{}' or
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
    update public.delivery_market_shops set opening_schedule=coalesce(d->'opening_schedule',opening_schedule)
      where id=sh.id returning * into sh;
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
    if not public.delivery_cloud_has_membership(actor.user_id,'merchant') then raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.'; end if;
    if d-array['id','shop_id','name','description','category','sku','image_url','price','stock','weight_kg','published','version','option_groups','sale_schedule','preparation_minutes','images']<>'{}' or
      jsonb_typeof(d->'price') is distinct from 'number' or jsonb_typeof(d->'stock') is distinct from 'number' or
      jsonb_typeof(d->'weight_kg') is distinct from 'number' or jsonb_typeof(d->'published') is distinct from 'boolean' or
      (d->>'stock')::numeric<>trunc((d->>'stock')::numeric) or (d->>'price')::numeric<>trunc((d->>'price')::numeric) then
      raise sqlstate 'PT400' using message='Giá và tồn kho cần là số nguyên hợp lệ.';
    end if;
    if d?'preparation_minutes' and (jsonb_typeof(d->'preparation_minutes') is distinct from 'number' or
      (d->>'preparation_minutes')::numeric<>trunc((d->>'preparation_minutes')::numeric) or
      (d->>'preparation_minutes')::numeric not between 0 and 1440) then
      raise sqlstate 'PT400' using message='Thời gian chuẩn bị không hợp lệ.'; end if;
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
    update public.delivery_market_products set option_groups=coalesce(d->'option_groups',option_groups),
      sale_schedule=coalesce(d->'sale_schedule',sale_schedule),images=coalesce(d->'images',images),
      preparation_minutes=case when d?'preparation_minutes' then (d->>'preparation_minutes')::integer else preparation_minutes end
      where id=prod.id returning * into prod;
    return jsonb_build_object('product',to_jsonb(prod));
  elsif p_action in ('cart','cart_set') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    insert into public.delivery_market_carts(user_id) values(auth.uid()) on conflict do nothing;
    select version into cart_version from public.delivery_market_carts where user_id=auth.uid() for update;
    if p_action='cart_set' then
      if d-array['product_id','line_id','selected_options','quantity','version']<>'{}' or
        jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) or
        (d->>'quantity')::numeric not between 0 and 99 then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
      if cart_version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Giỏ hàng đã thay đổi trên thiết bị khác. Hãy tải lại.'; end if;
      qty:=(d->>'quantity')::integer;product_key:=(d->>'product_id')::uuid;
      line_key:=(d->>'line_id')::uuid;selected:=coalesce(d->'selected_options','[]');
      if product_key is null then raise sqlstate 'PT400' using message='Thiếu sản phẩm.'; end if;
      if line_key is not null then
        select selected_options into selected from public.delivery_market_cart_items
          where user_id=auth.uid() and line_id=line_key and product_id=product_key;
        if not found then raise sqlstate 'PT409' using message='Dòng giỏ hàng đã thay đổi. Hãy tải lại.'; end if;
        if d?'selected_options' and d->'selected_options' is distinct from selected then
          raise sqlstate 'PT409' using message='Không thể đổi lựa chọn của dòng giỏ hàng.'; end if;
      end if;
      if qty=0 then
        -- Removal remains possible when the original option was retired.
        if line_key is null then
          selection:=public.delivery_market_selection(product_key,selected);line_key:=(selection->>'line_id')::uuid;
        end if;
        delete from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key and product_id=product_key;
      else
        select * into prod from public.delivery_market_products where id=product_key for share;
        select * into sh from public.delivery_market_shops where id=prod.shop_id;
        if prod.id is null or not prod.published or sh.status<>'active' or sh.paused or sh.owner_id=auth.uid() or
          not public.delivery_market_is_open(prod.sale_schedule) or not public.delivery_market_is_open(sh.opening_schedule) or
          not exists(select 1 from public.delivery_cloud_accounts where user_id=sh.owner_id and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
          raise sqlstate 'PT409' using message='Sản phẩm không thể mua hoặc không đủ tồn kho.'; end if;
        selection:=public.delivery_market_selection(product_key,selected);
        line_key:=(selection->>'line_id')::uuid;
        select qty+coalesce(sum(quantity),0) into aggregate_qty from public.delivery_market_cart_items
          where user_id=auth.uid() and product_id=product_key and line_id<>line_key;
        if aggregate_qty>prod.stock or aggregate_qty>99 then raise sqlstate 'PT409' using message='Tổng số lượng các lựa chọn vượt tồn kho hoặc giới hạn 99.'; end if;
        if not exists(select 1 from public.delivery_market_cart_items where user_id=auth.uid() and line_id=line_key) and
          (select count(*) from public.delivery_market_cart_items where user_id=auth.uid())>=50 then raise sqlstate 'PT400' using message='Giỏ hàng hỗ trợ tối đa 50 dòng.'; end if;
        insert into public.delivery_market_cart_items(user_id,product_id,quantity,line_id,selected_options)
          values(auth.uid(),product_key,qty,line_key,selection->'selected_options')
          on conflict(user_id,line_id) do update set quantity=excluded.quantity;
      end if;
      update public.delivery_market_carts set version=version+1 where user_id=auth.uid();
    end if;
    return public.delivery_market_configured_cart();
  elsif p_action in ('quote','checkout') then
    perform pg_advisory_xact_lock(hashtextextended('cart:'||auth.uid()::text,0));
    if p_action='quote' then
      if d-array['address_id','cart_version','address_version']<>'{}' or
        (d?'cart_version' and (jsonb_typeof(d->'cart_version') is distinct from 'number' or
          (d->>'cart_version')::numeric<>trunc((d->>'cart_version')::numeric))) or
        (d?'address_version' and (jsonb_typeof(d->'address_version') is distinct from 'number' or
          (d->>'address_version')::numeric<>trunc((d->>'address_version')::numeric))) then
        raise sqlstate 'PT400' using message='Yêu cầu báo giá không hợp lệ.'; end if;
      snapshot:=public.delivery_market_snapshot((d->>'address_id')::uuid);
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
      where (case when d->>'workspace'='merchant' then o.merchant_id=auth.uid() and public.delivery_cloud_has_membership(actor.user_id,'merchant') else o.owner_id=auth.uid() end)
        and (not(d ? 'after') or o.id>(d->>'after')::uuid) order by o.id limit 50) x;
    return jsonb_build_object('orders',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action in ('order_action','messages','message_send') then
    select * into so from public.delivery_market_shop_orders where delivery_market_shop_orders.id=(d->>'order_id')::uuid
      and (owner_id=auth.uid() or merchant_id=auth.uid() and public.delivery_cloud_has_membership(actor.user_id,'merchant')) for update;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
    if p_action='order_action' then
      requested:=d->>'action';
      if so.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Đơn hàng đã thay đổi. Hãy tải lại.'; end if;
      if requested not in ('accept','ready','cancel') or requested is null then raise sqlstate 'PT400' using message='Thao tác không hợp lệ.'; end if;
      if requested in ('accept','ready') and (so.merchant_id<>auth.uid() or not public.delivery_cloud_has_membership(actor.user_id,'merchant')) then raise sqlstate 'PT403' using message='Chỉ cửa hàng xử lý đơn mua hàng.'; end if;
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

create or replace function public.delivery_market_operations(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; a public.delivery_cloud_accounts; so public.delivery_market_shop_orders;
  prod public.delivery_market_products; ret public.delivery_market_returns; f public.delivery_market_finance; existing public.delivery_market_commands;
  result jsonb; item jsonb; token text; jid uuid; qty integer; cv integer; collected bigint; refunded bigint; settled bigint;
  due bigint; goods bigint; freight bigint; used bigint; op boolean; k uuid; requested text; line_key uuid; selection jsonb;
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
      return jsonb_build_object('product',to_jsonb(prod)||jsonb_build_object('available',prod.stock>0 and public.delivery_market_is_open(prod.sale_schedule) and
        exists(select 1 from public.delivery_market_shops where id=prod.shop_id and public.delivery_market_is_open(opening_schedule))),
        'favorite',exists(select 1 from public.delivery_market_favorites where user_id=auth.uid() and product_id=prod.id),
        'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from
          (select id,rating,body,created_at from public.delivery_market_reviews where product_id=prod.id and not hidden order by created_at desc,id desc limit 50) r),'[]'));
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from
      (select p.*,s.name as shop_name from public.delivery_market_favorites fav join public.delivery_market_products p on p.id=fav.product_id
        join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
        where fav.user_id=auth.uid() and p.published and s.status='active' and not s.paused and public.delivery_cloud_has_membership(m.user_id,'merchant') and not m.blocked
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (not(d ? 'after') or p.id>(d->>'after')::uuid) order by p.id limit 50) x;
    return jsonb_build_object('products',result,'next',case when jsonb_array_length(result)=50 then jsonb_build_object('after',result->49->>'id') end);
  elsif p_action='operations' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    result:=jsonb_build_object('finance',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
      (select * from public.delivery_market_finance where (not(d ? 'before') or (created_at,id)<((d->>'before')::timestamptz,(d->>'before_id')::uuid)) order by created_at desc,id desc limit 50) x),'[]'),
      'returns',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
        (select * from public.delivery_market_returns where state in ('requested','escalated')
          and (not(d ? 'before_returns') or (created_at,id)<((d->>'before_returns')::timestamptz,(d->>'before_return_id')::uuid)) order by created_at desc,id desc limit 50) x),'[]'),
      'jobs',jsonb_build_object('pending',(select count(*) from public.delivery_market_jobs where state='pending'),
        'failed',(select count(*) from public.delivery_market_jobs where state='failed'),
        'overdue',(select count(*) from public.delivery_market_jobs where state='pending' and run_at<=now())),
      'failed_jobs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.delivery_market_jobs where state='failed' order by run_at,id limit 50) x),'[]'));
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
    if jsonb_typeof(d->'hidden') is distinct from 'boolean' or length(btrim(coalesce(d->>'reason',''))) not between 3 and 500 then
      raise sqlstate 'PT400' using message='Cần lý do kiểm duyệt.'; end if;
    update public.delivery_market_reviews set hidden=(d->>'hidden')::boolean where id=(d->>'id')::uuid;
    if not found then raise sqlstate 'PT404' using message='Không tìm thấy đánh giá.'; end if;
    insert into public.delivery_cloud_admin_audit(actor_id,action,target_id,after_value) values(auth.uid(),'review_moderate',(d->>'id')::uuid,d);
    return jsonb_build_object('ok',true);
  elsif p_action='finance_action' then
    if not op then raise sqlstate 'PT403' using message='Cần quyền quản trị.'; end if;
    select order_id into k from public.delivery_market_finance where id=(d->>'id')::uuid;
    -- Every financial mutation locks its order first, then the request.
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
      goods:=(so.snapshot->>'subtotal')::bigint; freight:=(so.snapshot->>'shipping_fee')::bigint; due:=goods+freight;
      select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
        into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
      if f.kind='collection' and (so.delivered_at is null or so.state='cancelled' or f.amount<>due or collected<>0) then
        raise sqlstate 'PT409' using message='Chỉ xác nhận đủ tiền COD một lần sau giao thành công.';
      elsif f.kind='refund' then
        select * into ret from public.delivery_market_returns where id=f.return_id and order_id=so.id;
        select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state='completed';
        select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
        if ret.id is null or ret.state<>'received' or f.amount>ret.quantity*(item->>'unit_price')::bigint-used
          or f.amount>least(goods-refunded-settled,collected-refunded-settled) then raise sqlstate 'PT409' using message='Khoản hoàn vượt mức hoặc chưa nhận hàng trả.'; end if;
      elsif f.kind='settlement' and (f.amount>least(goods-refunded-settled,collected-refunded-settled-freight) or exists
        (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=r.line_id) v on true
          where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
          r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))
        or so.delivered_at is null or so.delivered_at>now()-interval '7 days') then
        raise sqlstate 'PT409' using message='Chưa đủ điều kiện đối soát shop: tiền khả dụng, hạn hậu mãi hoặc tranh chấp.';
      end if;
      update public.delivery_market_finance set state='completed',completion_evidence=btrim(d->>'evidence'),completed_at=now(),version=version+1 where id=f.id returning * into f;
      insert into public.delivery_market_journals(finance_id,order_id) values(f.id,so.id) returning id into jid;
      if f.kind='collection' then
        insert into public.delivery_market_ledger values(jid,'cash_clearing',due),(jid,'merchant_payable',-goods);
        if freight>0 then insert into public.delivery_market_ledger values(jid,'shipping_revenue',-freight); end if;
      else insert into public.delivery_market_ledger values(jid,'cash_clearing',-f.amount),(jid,'merchant_payable',f.amount);
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
    and (owner_id=auth.uid() or merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant') or op or exists
      (select 1 from public.delivery_cloud_orders o where o.id=delivery_id and o.driver_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'driver'))) for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
  if p_action='order_services' then
    if not op and so.owner_id<>auth.uid() and not (so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant')) then raise sqlstate 'PT403' using message='Không có quyền xem hậu mãi của đơn này.'; end if;
    select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    return jsonb_build_object('order',to_jsonb(so),'collected',collected,'refunded',refunded,'settled',settled,
      'returns',coalesce((select jsonb_agg(to_jsonb(r) order by created_at,id) from public.delivery_market_returns r where order_id=so.id),'[]'),
      'reviews',coalesce((select jsonb_agg(to_jsonb(r)-'user_id' order by created_at,id) from public.delivery_market_reviews r where order_id=so.id),'[]'),
      'finance',coalesce((select jsonb_agg(to_jsonb(r)-'evidence'-'completion_evidence'-'request_key' order by created_at,id) from public.delivery_market_finance r where order_id=so.id),'[]'),
      'shares',case when so.owner_id=auth.uid() then coalesce((select jsonb_agg(to_jsonb(s)-'token_hash'-'owner_id' order by created_at,id) from public.delivery_market_shares s where order_id=so.id and revoked_at is null and expires_at>now()),'[]') else '[]'::jsonb end);
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
      selection:=public.delivery_market_selection(prod.id,coalesce(item->'selected_options','[]'));
      select coalesce((select quantity from public.delivery_market_cart_items where user_id=auth.uid() and line_id=(selection->>'line_id')::uuid),0)+(item->>'quantity')::integer into qty;
      perform public.delivery_marketplace('cart_set',jsonb_build_object('product_id',prod.id,'selected_options',selection->'selected_options','quantity',qty,'version',cv));
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
    insert into public.delivery_market_returns(order_id,product_id,line_id,user_id,quantity,reason,request_key) values(so.id,(d->>'product_id')::uuid,line_key,auth.uid(),(d->>'quantity')::integer,btrim(d->>'reason'),(d->>'request_key')::uuid) returning * into ret;
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
    elsif requested in ('approve','reject') and (so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant') and ret.state='requested' or op and ret.state in ('requested','escalated')) then
      requested:=case requested when 'approve' then 'approved' else 'rejected' end;
    elsif requested='receive' and ret.state='approved' and (so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant') or op) then requested:='received';
    else raise sqlstate 'PT403' using message='Không có quyền chuyển trạng thái trả hàng.';
    end if;
    update public.delivery_market_returns set state=requested,response=btrim(d->>'response'),version=version+1,updated_at=now() where id=ret.id returning * into ret;
    insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'return_'||requested,btrim(d->>'response'));
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'return_'||requested);
    return jsonb_build_object('return',to_jsonb(ret));
  elsif p_action='finance_request' then
    requested:=d->>'kind';
    if requested not in ('collection','refund','settlement') or requested is null then raise sqlstate 'PT400' using message='Loại yêu cầu không hợp lệ.'; end if;
    if not op and not (requested='settlement' and so.merchant_id=auth.uid() and public.delivery_cloud_has_membership(a.user_id,'merchant')) and not
      (requested='collection' and public.delivery_cloud_has_membership(a.user_id,'driver') and exists(select 1 from public.delivery_cloud_orders where id=so.delivery_id and driver_id=auth.uid())) and not
      (requested='refund' and so.owner_id=auth.uid()) then raise sqlstate 'PT403' using message='Không có quyền đề nghị khoản thu/chi này.'; end if;
    if jsonb_typeof(d->'amount') is distinct from 'number' or (d->>'amount')::numeric<>trunc((d->>'amount')::numeric) then raise sqlstate 'PT400' using message='Số tiền cần là số nguyên.'; end if;
    select * into f from public.delivery_market_finance where proposer=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if f.order_id<>so.id or f.kind<>requested or f.amount is distinct from (d->>'amount')::integer or f.reason is distinct from btrim(d->>'reason') or f.evidence is distinct from btrim(d->>'evidence') or f.return_id is distinct from (d->>'return_id')::uuid then raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.'; end if;
      return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
    end if;
    if (select count(*) from public.delivery_market_finance where order_id=so.id)>=100 then raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu thu/chi. Cần quản trị viên kiểm tra.'; end if;
    goods:=(so.snapshot->>'subtotal')::bigint; freight:=(so.snapshot->>'shipping_fee')::bigint; due:=goods+freight;
    select coalesce(sum(amount) filter(where kind='collection'),0),coalesce(sum(amount) filter(where kind='refund'),0),coalesce(sum(amount) filter(where kind='settlement'),0)
      into collected,refunded,settled from public.delivery_market_finance where order_id=so.id and state='completed';
    if requested='collection' and (so.delivered_at is null or (d->>'amount')::bigint<>due or exists(select 1 from public.delivery_market_finance where order_id=so.id and kind='collection' and state<>'rejected')) then raise sqlstate 'PT409' using message='COD chỉ được đề nghị đủ tiền một lần sau giao hàng.'; end if;
    if requested='refund' then
      select * into ret from public.delivery_market_returns where id=(d->>'return_id')::uuid and order_id=so.id and state='received';
      select i into item from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=ret.line_id;
      select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state<>'rejected';
      if ret.id is null or (d->>'amount')::bigint>ret.quantity*(item->>'unit_price')::bigint-used or (d->>'amount')::bigint>least(goods-refunded-settled,collected-refunded-settled) then raise sqlstate 'PT409' using message='Chưa nhận hàng trả hoặc khoản hoàn vượt mức.'; end if;
    elsif requested='settlement' and ((d->>'amount')::bigint>least(goods-refunded-settled,collected-refunded-settled-freight) or so.delivered_at is null or so.delivered_at>now()-interval '7 days' or exists
      (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where coalesce(i->>'line_id',i->>'product_id')::uuid=r.line_id) v on true
        where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
        r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))) then raise sqlstate 'PT409' using message='Chưa có tiền hàng khả dụng để đối soát.';
    end if;
    insert into public.delivery_market_finance(order_id,kind,amount,return_id,proposer,reason,evidence,request_key)
      values(so.id,requested,(d->>'amount')::integer,(d->>'return_id')::uuid,auth.uid(),btrim(d->>'reason'),btrim(d->>'evidence'),(d->>'request_key')::uuid) returning * into f;
    return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
  else raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end$$;


create or replace function public.delivery_market_browse(p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; result jsonb; categories jsonb; shop jsonb; ordering text:=coalesce(d->>'sort','default');
  low integer:=0; high integer:=10000000; last_value jsonb;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if not exists(select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and not blocked) then
    raise sqlstate 'PT403' using message='Tài khoản chưa được xác minh hoặc đã bị khóa.';
  end if;
  if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>16000 or
    d-array['search','category','shop_id','min_price','max_price','in_stock','sort','after','after_value']<>'{}' or
    ordering not in ('default','price_asc','price_desc','newest') then raise sqlstate 'PT400' using message='Bộ lọc không hợp lệ.'; end if;
  if (d?'search' and (jsonb_typeof(d->'search')<>'string' or length(d->>'search')>160)) or
    (d?'category' and (jsonb_typeof(d->'category')<>'string' or length(d->>'category')>80)) or
    (d?'in_stock' and jsonb_typeof(d->'in_stock')<>'boolean') then raise sqlstate 'PT400' using message='Bộ lọc không hợp lệ.'; end if;
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
    select jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'address',s.address,'paused',s.paused,'opening_schedule',s.opening_schedule,'open',not s.paused and public.delivery_market_is_open(s.opening_schedule))
      into shop from public.delivery_market_shops s join public.delivery_cloud_accounts a on a.user_id=s.owner_id
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
    select p.*,s.name as shop_name,p.stock>0 and public.delivery_market_is_open(p.sale_schedule) and public.delivery_market_is_open(s.opening_schedule) as available,case ordering when 'price_asc' then p.price::numeric when 'price_desc' then -p.price::numeric
      when 'newest' then -extract(epoch from p.updated_at) else 0::numeric end as sort_value
      from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
      join public.delivery_cloud_accounts a on a.user_id=s.owner_id
      where p.published and s.status='active' and not s.paused and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant')
        and (coalesce(d->>'search','')='' or strpos(lower(p.name||' '||s.name||' '||p.sku),lower(d->>'search'))>0)
        and (coalesce(d->>'category','')='' or p.category=d->>'category')
        and (not(d?'shop_id') or p.shop_id=(d->>'shop_id')::uuid)
        and p.price between low and high and (coalesce((d->>'in_stock')::boolean,false)=false or p.stock>0)
  ) select coalesce(jsonb_agg(to_jsonb(x) order by sort_value,id),'[]') into result from (
    select * from visible where not(d?'after') or (sort_value,id)>((d->>'after_value')::numeric,(d->>'after')::uuid)
      order by sort_value,id limit 50
  ) x;
  last_value:=result->49;
  return jsonb_build_object('products',coalesce((select jsonb_agg(i-'sort_value' order by ord) from jsonb_array_elements(result) with ordinality as r(i,ord)),'[]'),
    'categories',categories,'shop',shop,'next',case when jsonb_array_length(result)=50 then
      jsonb_build_object('after',last_value->>'id','after_value',last_value->'sort_value') end);
end $$;
revoke all on function public.delivery_market_browse(jsonb) from public,anon;
grant execute on function public.delivery_market_browse(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
