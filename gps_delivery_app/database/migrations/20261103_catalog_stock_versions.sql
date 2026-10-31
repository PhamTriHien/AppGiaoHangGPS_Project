-- Inventory allocations must not invalidate unchanged commercial terms.
begin;
alter table public.delivery_market_products add column if not exists terms_version integer not null default 1 check(terms_version>0);
create or replace function public.delivery_market_product_terms() returns trigger
language plpgsql set search_path='' as $$
begin
  if (to_jsonb(new)-array['stock','version','updated_at','terms_version']) is distinct from
    (to_jsonb(old)-array['stock','version','updated_at','terms_version']) then new.terms_version:=old.terms_version+1;
  else new.terms_version:=old.terms_version;
  end if;
  return new;
end $$;
revoke all on function public.delivery_market_product_terms() from public,anon,authenticated;
drop trigger if exists delivery_market_product_terms on public.delivery_market_products;
create trigger delivery_market_product_terms before update on public.delivery_market_products
  for each row execute function public.delivery_market_product_terms();

-- The fixed snapshot builder below uses terms_version; editor stock conflicts
-- still use the full product version and inventory remains locked at checkout.
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
      where user_id=s.owner_id and public.delivery_cloud_has_membership(user_id,'merchant') and not blocked) then
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
        'quantity',i.quantity,'unit_price',i.price,'version',i.terms_version,'image_url',i.image_url));
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

notify pgrst, 'reload schema';
commit;
