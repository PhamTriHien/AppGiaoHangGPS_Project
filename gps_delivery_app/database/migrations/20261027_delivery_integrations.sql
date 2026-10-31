-- Run after database/schema.sql. Cloud identities are Supabase Auth users.
begin;
create table if not exists public.delivery_api_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'user' check (role in ('user', 'operator'))
);
alter table public.delivery_api_profiles enable row level security;
create policy profile_read_self on public.delivery_api_profiles for select to authenticated using (user_id = auth.uid());

create or replace function public.delivery_is_operator() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.delivery_api_profiles where user_id = auth.uid() and role = 'operator');
$$;
revoke all on function public.delivery_is_operator() from public;
grant execute on function public.delivery_is_operator() to authenticated;

create table if not exists public.delivery_live_rooms (
  id text primary key check (length(id) between 1 and 100),
  created_at timestamptz not null default now()
);
create table if not exists public.delivery_live_members (
  room_id text not null references public.delivery_live_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('customer','merchant','driver')),
  primary key (room_id, user_id)
);
create or replace function public.delivery_is_member(room text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.delivery_live_members where room_id = room and user_id = auth.uid());
$$;
revoke all on function public.delivery_is_member(text) from public;
grant execute on function public.delivery_is_member(text) to authenticated;
create or replace function public.delivery_is_driver(room text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.delivery_live_members where room_id = room and user_id = auth.uid() and role = 'driver');
$$;
revoke all on function public.delivery_is_driver(text) from public;
grant execute on function public.delivery_is_driver(text) to authenticated;

alter table public.delivery_live_rooms enable row level security;
alter table public.delivery_live_members enable row level security;
create policy rooms_read on public.delivery_live_rooms for select to authenticated using (public.delivery_is_operator() or public.delivery_is_member(id));
create policy rooms_manage on public.delivery_live_rooms for all to authenticated using (public.delivery_is_operator()) with check (public.delivery_is_operator());
create policy members_read on public.delivery_live_members for select to authenticated using (user_id = auth.uid() or public.delivery_is_operator());
create policy members_manage on public.delivery_live_members for all to authenticated using (public.delivery_is_operator()) with check (public.delivery_is_operator());

create table if not exists public.delivery_live_events (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references public.delivery_live_rooms(id) on delete cascade,
  sender_id uuid not null default auth.uid() references auth.users(id),
  kind text not null check (kind in ('status','chat','gps','pod')),
  payload jsonb not null check (octet_length(payload::text) <= 12000),
  created_at timestamptz not null default now()
);
create index if not exists delivery_events_room_created on public.delivery_live_events(room_id,created_at desc);
alter table public.delivery_live_events enable row level security;
create policy events_read on public.delivery_live_events for select to authenticated using (public.delivery_is_member(room_id) or public.delivery_is_operator());
create policy events_insert on public.delivery_live_events for insert to authenticated with check (
  sender_id = auth.uid() and
  ((kind = 'chat' and (public.delivery_is_member(room_id) or public.delivery_is_operator())) or
   (kind in ('status','gps','pod') and (public.delivery_is_driver(room_id) or public.delivery_is_operator())))
);
-- Events are immutable. Clients cannot grant themselves access or an operator role.
create or replace function public.delivery_validate_event() returns trigger
language plpgsql set search_path = '' as $$
declare previous_status text;
declare next_status text;
begin
  new.created_at := now();
  if new.kind = 'status' and coalesce(new.payload->>'status','') not in ('searching','accepted','arrivingPickup','inTransit','delivered','failed','returning','cancelled') then
    raise exception 'Invalid delivery status';
  end if;
  if new.kind = 'status' then
    perform pg_advisory_xact_lock(hashtextextended(new.room_id,0));
    select payload->>'status' into previous_status from public.delivery_live_events
      where room_id=new.room_id and kind='status' order by created_at desc limit 1;
    next_status := new.payload->>'status';
    if previous_status is not null and previous_status <> next_status and not (
      (previous_status='searching' and next_status in ('accepted','cancelled')) or
      (previous_status='accepted' and next_status in ('arrivingPickup','cancelled')) or
      (previous_status='arrivingPickup' and next_status in ('inTransit','cancelled')) or
      (previous_status='inTransit' and next_status in ('delivered','failed')) or
      (previous_status='failed' and next_status in ('inTransit','returning')) or
      (previous_status='returning' and next_status='delivered')
    ) then raise exception 'Invalid delivery transition'; end if;
  end if;
  if new.kind = 'chat' and (length(coalesce(new.payload->>'text','')) not between 1 and 2000) then
    raise exception 'Invalid chat message';
  end if;
  if new.kind = 'chat' then
    new.payload := jsonb_set(new.payload,'{isCustomer}',to_jsonb(not public.delivery_is_driver(new.room_id)));
  end if;
  if new.kind = 'gps' and (jsonb_typeof(new.payload->'latitude') is distinct from 'number' or jsonb_typeof(new.payload->'longitude') is distinct from 'number' or (new.payload->>'latitude')::numeric not between -90 and 90 or (new.payload->>'longitude')::numeric not between -180 and 180 or not (new.payload ?& array['latitude','longitude'])) then
    raise exception 'Invalid location';
  end if;
  if new.kind = 'pod' and (split_part(coalesce(new.payload->>'path',''), '/', 1) <> new.room_id or
      strpos(coalesce(new.payload->>'path',''), '..') > 0 or not exists (
        select 1 from storage.objects where bucket_id='delivery-evidence' and name=new.payload->>'path')) then
    raise exception 'Invalid delivery evidence';
  end if;
  return new;
end;
$$;
create trigger delivery_event_validate before insert on public.delivery_live_events for each row execute function public.delivery_validate_event();

create table if not exists public.delivery_device_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null check (length(token) between 20 and 4096),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);
alter table public.delivery_device_tokens enable row level security;
create policy tokens_self on public.delivery_device_tokens for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select on public.delivery_api_profiles to authenticated;
grant select, insert, update, delete on public.delivery_live_rooms, public.delivery_live_members, public.delivery_device_tokens to authenticated;
grant select, insert on public.delivery_live_events to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('delivery-evidence','delivery-evidence',false,5000000,array['image/jpeg','image/png'])
on conflict(id) do nothing;
create policy evidence_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'delivery-evidence' and (public.delivery_is_driver((storage.foldername(name))[1]) or public.delivery_is_operator())
);
create policy evidence_read on storage.objects for select to authenticated using (
  bucket_id = 'delivery-evidence' and (public.delivery_is_member((storage.foldername(name))[1]) or public.delivery_is_operator())
);
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='delivery_live_events') then
    alter publication supabase_realtime add table public.delivery_live_events;
  end if;
end $$;
commit;
