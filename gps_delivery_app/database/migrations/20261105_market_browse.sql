begin;
create index if not exists delivery_market_products_price_page on public.delivery_market_products(price,id) where published;
create index if not exists delivery_market_products_category_page on public.delivery_market_products(category,id) where published;
create index if not exists delivery_market_products_updated_page on public.delivery_market_products(updated_at desc,id) where published;

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
    select jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'address',s.address,'paused',s.paused)
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
    select p.*,s.name as shop_name,case ordering when 'price_asc' then p.price::numeric when 'price_desc' then -p.price::numeric
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
