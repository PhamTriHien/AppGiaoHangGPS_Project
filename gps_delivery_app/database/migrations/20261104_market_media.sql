-- Public product photography only. Never reuse this bucket for private evidence.
begin;
create table if not exists public.delivery_market_media (
  name text primary key,
  shop_id uuid not null references public.delivery_market_shops(id),
  owner_id uuid not null references auth.users(id),
  content_hash text not null check(content_hash ~ '^[a-f0-9]{64}$'),
  byte_size integer not null check(byte_size between 1 and 5000000),
  created_at timestamptz not null default now(),
  upload_until timestamptz not null default now()+interval '15 minutes',
  unique(shop_id,content_hash)
);
alter table public.delivery_market_media enable row level security;
revoke all on public.delivery_market_media from public,anon,authenticated;
create index if not exists delivery_market_media_shop_created on public.delivery_market_media(shop_id,created_at);

create or replace function public.delivery_market_media_reserve(p_shop uuid,p_hash text,p_bytes integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.delivery_market_shops; m public.delivery_market_media;
begin
  if auth.uid() is null then raise sqlstate 'PT401' using message='Cần đăng nhập.'; end if;
  if not exists(select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and not blocked
    and public.delivery_cloud_has_membership(user_id,'merchant')) then
    raise sqlstate 'PT403' using message='Cần tư cách cửa hàng đã được duyệt.';
  end if;
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or p_bytes is null or p_bytes not between 1 and 5000000 then
    raise sqlstate 'PT400' using message='Ảnh không hợp lệ.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('market-media-budget',0));
  select * into s from public.delivery_market_shops where id=p_shop and owner_id=auth.uid() for update;
  if not found or s.status='suspended' then raise sqlstate 'PT403' using message='Không có quyền tải ảnh cho cửa hàng này.'; end if;
  select * into m from public.delivery_market_media where shop_id=s.id and content_hash=p_hash;
  if found then
    if m.byte_size<>p_bytes then raise sqlstate 'PT409' using message='Nội dung ảnh đã thay đổi.'; end if;
    update public.delivery_market_media set upload_until=now()+interval '15 minutes' where name=m.name returning * into m;
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
revoke all on function public.delivery_market_media_reserve(uuid,text,integer) from public,anon;
grant execute on function public.delivery_market_media_reserve(uuid,text,integer) to authenticated;

create or replace function public.delivery_market_media_can_upload(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.delivery_market_media m
    join public.delivery_market_shops s on s.id=m.shop_id join public.delivery_cloud_accounts a on a.user_id=m.owner_id
    where m.name=p_name and m.owner_id=auth.uid() and s.owner_id=auth.uid() and s.status<>'suspended'
      and m.upload_until>now() and not a.blocked and public.delivery_cloud_has_membership(a.user_id,'merchant'));
$$;
revoke all on function public.delivery_market_media_can_upload(text) from public,anon;
grant execute on function public.delivery_market_media_can_upload(text) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('delivery-market-media','delivery-market-media',true,5000000,array['image/webp'])
  on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists delivery_market_media_insert on storage.objects;
create policy delivery_market_media_insert on storage.objects for insert to authenticated
  with check(bucket_id='delivery-market-media' and public.delivery_market_media_can_upload(name));
notify pgrst,'reload schema';
commit;
