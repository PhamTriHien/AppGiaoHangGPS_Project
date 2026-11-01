-- Marketplace operations. Additive; no accounts, sales or balances are seeded.
begin;
alter table public.delivery_market_shop_orders add column if not exists accept_by timestamptz not null default (now()+interval '15 minutes');
alter table public.delivery_market_shop_orders add column if not exists delivered_at timestamptz;

create table if not exists public.delivery_market_jobs (
  id uuid primary key default gen_random_uuid(), order_id uuid not null unique references public.delivery_market_shop_orders(id),
  run_at timestamptz not null, state text not null default 'pending' check(state in ('pending','done','failed')),
  attempts integer not null default 0, last_error text, completed_at timestamptz
);
create index if not exists delivery_market_jobs_due on public.delivery_market_jobs(run_at,id) where state='pending';
create table if not exists public.delivery_market_favorites (
  user_id uuid not null references auth.users(id), product_id uuid not null references public.delivery_market_products(id),
  created_at timestamptz not null default now(), primary key(user_id,product_id)
);
create table if not exists public.delivery_market_reviews (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.delivery_market_shop_orders(id),
  product_id uuid not null references public.delivery_market_products(id), user_id uuid not null references auth.users(id),
  rating integer not null check(rating between 1 and 5), body text not null check(length(body) between 3 and 2000),
  hidden boolean not null default false, created_at timestamptz not null default now(), unique(order_id,product_id)
);
create table if not exists public.delivery_market_returns (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.delivery_market_shop_orders(id),
  product_id uuid not null references public.delivery_market_products(id), user_id uuid not null references auth.users(id),
  quantity integer not null check(quantity between 1 and 99), reason text not null check(length(reason) between 3 and 1000),
  state text not null default 'requested' check(state in ('requested','approved','rejected','escalated','received')),
  response text not null default '', version integer not null default 1, request_key uuid not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id,request_key)
);
create index if not exists delivery_market_returns_order on public.delivery_market_returns(order_id,product_id);
create table if not exists public.delivery_market_finance (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.delivery_market_shop_orders(id),
  kind text not null check(kind in ('collection','refund','settlement')), amount integer not null check(amount between 1 and 100000000),
  return_id uuid references public.delivery_market_returns(id),
  proposer uuid not null references auth.users(id), approver uuid references auth.users(id),
  reason text not null check(length(reason) between 3 and 1000), evidence text not null check(length(evidence) between 3 and 500),
  completion_evidence text, state text not null default 'requested' check(state in ('requested','approved','rejected','completed')),
  version integer not null default 1, request_key uuid not null, created_at timestamptz not null default now(), completed_at timestamptz,
  unique(proposer,request_key), check(approver is null or approver<>proposer),
  check(state<>'completed' or (approver is not null and length(completion_evidence) between 3 and 500))
);
create index if not exists delivery_market_finance_order on public.delivery_market_finance(order_id,kind,state);
create table if not exists public.delivery_market_journals (
  id uuid primary key default gen_random_uuid(), finance_id uuid not null unique references public.delivery_market_finance(id),
  order_id uuid not null references public.delivery_market_shop_orders(id), created_at timestamptz not null default now()
);
create table if not exists public.delivery_market_ledger (
  journal_id uuid not null references public.delivery_market_journals(id), account text not null
    check(account in ('cash_clearing','merchant_payable','shipping_revenue')),
  amount bigint not null check(amount<>0), primary key(journal_id,account)
);
create table if not exists public.delivery_market_shares (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.delivery_market_shop_orders(id),
  owner_id uuid not null references auth.users(id), token_hash text not null unique,
  expires_at timestamptz not null, revoked_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.delivery_market_commands (
  user_id uuid not null references auth.users(id), request_key uuid not null, action text not null, payload jsonb not null,
  result jsonb not null, primary key(user_id,request_key)
);
do $$ declare n text; begin
  foreach n in array array['jobs','favorites','reviews','returns','finance','journals','ledger','shares','commands'] loop
    execute format('alter table public.delivery_market_%I enable row level security',n);
    execute format('revoke all on public.delivery_market_%I from public,anon,authenticated',n);
  end loop;
end $$;

create or replace function public.delivery_market_immutable() returns trigger
language plpgsql set search_path='' as $$begin raise exception 'Immutable accounting record'; end$$;
drop trigger if exists immutable on public.delivery_market_journals;
create trigger immutable before update or delete on public.delivery_market_journals for each row execute function public.delivery_market_immutable();
drop trigger if exists immutable on public.delivery_market_ledger;
create trigger immutable before update or delete on public.delivery_market_ledger for each row execute function public.delivery_market_immutable();
create or replace function public.delivery_market_balance() returns trigger
language plpgsql security definer set search_path='' as $$
declare k uuid;
begin
  if tg_table_name='delivery_market_journals' then k:=new.id; else k:=new.journal_id; end if;
  if (select count(*)<2 or coalesce(sum(amount),1)<>0 from public.delivery_market_ledger where journal_id=k) then
    raise exception 'Unbalanced accounting journal';
  end if;
  return null;
end$$;
drop trigger if exists balanced on public.delivery_market_journals;
create constraint trigger balanced after insert on public.delivery_market_journals deferrable initially deferred for each row execute function public.delivery_market_balance();
drop trigger if exists balanced on public.delivery_market_ledger;
create constraint trigger balanced after insert on public.delivery_market_ledger deferrable initially deferred for each row execute function public.delivery_market_balance();

create or replace function public.delivery_market_order_job() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    insert into public.delivery_market_jobs(order_id,run_at) values(new.id,new.accept_by) on conflict do nothing;
  elsif old.state='pending' and new.state='accepted' and old.accept_by<=now() then
    raise sqlstate 'PT409' using message='Đơn đã quá hạn xác nhận.';
  end if;
  return new;
end$$;
drop trigger if exists delivery_market_order_job on public.delivery_market_shop_orders;
create trigger delivery_market_order_job after insert or update of state on public.delivery_market_shop_orders for each row execute function public.delivery_market_order_job();
insert into public.delivery_market_jobs(order_id,run_at) select id,accept_by from public.delivery_market_shop_orders where state='pending' on conflict do nothing;

create or replace function public.delivery_market_delivered() returns trigger
language plpgsql security definer set search_path='' as $$begin
  if new.status='delivered' and old.status is distinct from new.status then
    update public.delivery_market_shop_orders set delivered_at=coalesce(delivered_at,now()),version=version+1,updated_at=now() where delivery_id=new.id;
  end if;
  return new;
end$$;
drop trigger if exists delivery_market_delivered on public.delivery_cloud_orders;
create trigger delivery_market_delivered after update of status on public.delivery_cloud_orders for each row execute function public.delivery_market_delivered();

-- Backend database principal only. Bounded, transaction-safe and restartable.
create or replace function public.delivery_market_run_jobs(p_limit integer default 25) returns jsonb
language plpgsql security definer set search_path='' as $$
declare job public.delivery_market_jobs; so public.delivery_market_shop_orders; item jsonb; processed integer:=0; failed integer:=0;
begin
  for job in select * from public.delivery_market_jobs where state='pending' and run_at<=now() order by run_at,id limit greatest(1,least(coalesce(p_limit,25),100)) for update skip locked loop
    begin
      select * into so from public.delivery_market_shop_orders where id=job.order_id for update;
      if so.state='pending' and so.accept_by<=now() then
        perform 1 from public.delivery_market_products where id in
          (select (i->>'product_id')::uuid from jsonb_array_elements(so.snapshot->'items') i) order by id for update;
        for item in select * from jsonb_array_elements(so.snapshot->'items') loop
          update public.delivery_market_products set stock=stock+(item->>'quantity')::integer,version=version+1,updated_at=now() where id=(item->>'product_id')::uuid;
          -- System source uses a dedicated value, never a fabricated user.
          insert into public.delivery_market_stock(product_id,actor_id,actor_source,delta,reason,reference_id)
            values((item->>'product_id')::uuid,null,'system',(item->>'quantity')::integer,'acceptance_expired',so.id);
        end loop;
        update public.delivery_market_shop_orders set state='cancelled',reason='Quá hạn xác nhận',version=version+1,updated_at=now() where id=so.id;
        insert into public.delivery_market_events(order_id,actor_id,actor_source,action) values(so.id,null,'system','acceptance_expired');
        insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.owner_id,so.id,'acceptance_expired'),(so.merchant_id,so.id,'acceptance_expired');
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
alter table public.delivery_market_stock drop constraint if exists delivery_market_stock_actor_source_check;
alter table public.delivery_market_stock drop constraint if exists delivery_market_stock_check;
alter table public.delivery_market_stock add constraint delivery_market_stock_actor_source_check check(actor_source in ('user','carrier','system'));
alter table public.delivery_market_stock add constraint delivery_market_stock_check check(actor_source<>'user' or actor_id is not null);
alter table public.delivery_market_events drop constraint if exists delivery_market_events_actor_source_check;
alter table public.delivery_market_events drop constraint if exists delivery_market_events_check;
alter table public.delivery_market_events add constraint delivery_market_events_actor_source_check check(actor_source in ('user','carrier','system'));
alter table public.delivery_market_events add constraint delivery_market_events_check check(actor_source<>'user' or actor_id is not null);

create or replace function public.delivery_market_public_tracking(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise sqlstate 'PT404' using message='Liên kết không tồn tại hoặc hết hạn.'; end if;
  select jsonb_build_object('shop_name',o.snapshot->>'shop_name','state',o.state,'delivery_status',d.status,'updated_at',o.updated_at,'expires_at',s.expires_at)
    into result from public.delivery_market_shares s join public.delivery_market_shop_orders o on o.id=s.order_id
    join public.delivery_cloud_accounts a on a.user_id=s.owner_id left join public.delivery_cloud_orders d on d.id=o.delivery_id
    where s.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') and s.expires_at>now() and s.revoked_at is null and not a.blocked;
  if result is null then raise sqlstate 'PT404' using message='Liên kết không tồn tại hoặc hết hạn.'; end if;
  return result;
end$$;

create or replace function public.delivery_market_operations(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_payload; a public.delivery_cloud_accounts; so public.delivery_market_shop_orders;
  prod public.delivery_market_products; ret public.delivery_market_returns; f public.delivery_market_finance; existing public.delivery_market_commands;
  result jsonb; item jsonb; token text; jid uuid; qty integer; cv integer; collected bigint; refunded bigint; settled bigint;
  due bigint; goods bigint; freight bigint; used bigint; op boolean; k uuid; requested text;
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
          and p.published and s.status='active' and not s.paused and not m.blocked and m.role='merchant') then
          raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;
        insert into public.delivery_market_favorites(user_id,product_id) values(auth.uid(),(d->>'product_id')::uuid) on conflict do nothing;
      else delete from public.delivery_market_favorites where user_id=auth.uid() and product_id=(d->>'product_id')::uuid;
      end if;
    end if;
    if p_action='product_details' then
      select p.* into prod from public.delivery_market_products p join public.delivery_market_shops s on s.id=p.shop_id
        join public.delivery_cloud_accounts m on m.user_id=s.owner_id where p.id=(d->>'product_id')::uuid
        and p.published and s.status='active' and not s.paused and m.role='merchant' and not m.blocked;
      if not found then raise sqlstate 'PT404' using message='Không tìm thấy sản phẩm.'; end if;
      return jsonb_build_object('product',to_jsonb(prod),'favorite',exists(select 1 from public.delivery_market_favorites where user_id=auth.uid() and product_id=prod.id),
        'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from
          (select id,rating,body,created_at from public.delivery_market_reviews where product_id=prod.id and not hidden order by created_at desc,id desc limit 50) r),'[]'));
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into result from
      (select p.*,s.name as shop_name from public.delivery_market_favorites fav join public.delivery_market_products p on p.id=fav.product_id
        join public.delivery_market_shops s on s.id=p.shop_id join public.delivery_cloud_accounts m on m.user_id=s.owner_id
        where fav.user_id=auth.uid() and p.published and s.status='active' and not s.paused and m.role='merchant' and not m.blocked
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
        select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=ret.product_id;
        if ret.id is null or ret.state<>'received' or f.amount>ret.quantity*(item->>'unit_price')::bigint-used
          or f.amount>least(goods-refunded-settled,collected-refunded-settled) then raise sqlstate 'PT409' using message='Khoản hoàn vượt mức hoặc chưa nhận hàng trả.'; end if;
      elsif f.kind='settlement' and (f.amount>least(goods-refunded-settled,collected-refunded-settled-freight) or exists
        (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=r.product_id) v on true
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
    and (owner_id=auth.uid() or merchant_id=auth.uid() and a.role='merchant' or op or exists
      (select 1 from public.delivery_cloud_orders o where o.id=delivery_id and o.driver_id=auth.uid() and a.role='driver')) for update;
  if not found then raise sqlstate 'PT404' using message='Không tìm thấy đơn mua hàng.'; end if;
  if p_action='order_services' then
    if not op and so.owner_id<>auth.uid() and not (so.merchant_id=auth.uid() and a.role='merchant') then raise sqlstate 'PT403' using message='Không có quyền xem hậu mãi của đơn này.'; end if;
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
      select coalesce((select quantity from public.delivery_market_cart_items where user_id=auth.uid() and product_id=prod.id),0)+(item->>'quantity')::integer into qty;
      perform public.delivery_marketplace('cart_set',jsonb_build_object('product_id',prod.id,'quantity',qty,'version',cv));
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
    if so.owner_id<>auth.uid() or so.delivered_at is null or so.state='cancelled' or so.delivered_at<now()-interval '7 days' then raise sqlstate 'PT403' using message='Chỉ người mua yêu cầu trả trong 7 ngày sau nhận hàng.'; end if;
    select * into ret from public.delivery_market_returns where user_id=auth.uid() and request_key=(d->>'request_key')::uuid;
    if found then
      if ret.order_id<>so.id or ret.product_id<>(d->>'product_id')::uuid or ret.quantity is distinct from (d->>'quantity')::integer or ret.reason is distinct from btrim(d->>'reason') then raise sqlstate 'PT409' using message='Mã yêu cầu đã được dùng.'; end if;
      return jsonb_build_object('return',to_jsonb(ret));
    end if;
    if jsonb_typeof(d->'quantity') is distinct from 'number' or (d->>'quantity')::numeric<>trunc((d->>'quantity')::numeric) then raise sqlstate 'PT400' using message='Số lượng không hợp lệ.'; end if;
    select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=(d->>'product_id')::uuid;
    select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and product_id=(d->>'product_id')::uuid and state<>'rejected';
    if item is null or (d->>'quantity')::integer+used>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Số lượng trả vượt số lượng đã mua còn lại.'; end if;
    if (select count(*) from public.delivery_market_returns where order_id=so.id)>=100 then raise sqlstate 'PT409' using message='Đơn đã đạt giới hạn yêu cầu trả hàng. Cần quản trị viên kiểm tra.'; end if;
    insert into public.delivery_market_returns(order_id,product_id,user_id,quantity,reason,request_key) values(so.id,(d->>'product_id')::uuid,auth.uid(),(d->>'quantity')::integer,btrim(d->>'reason'),(d->>'request_key')::uuid) returning * into ret;
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(so.merchant_id,so.id,'return_requested');
    return jsonb_build_object('return',to_jsonb(ret));
  elsif p_action='return_action' then
    select * into ret from public.delivery_market_returns where id=(d->>'id')::uuid and order_id=so.id for update;
    if ret.id is null then raise sqlstate 'PT404' using message='Không tìm thấy yêu cầu trả hàng.'; end if;
    if ret.version is distinct from (d->>'version')::integer then raise sqlstate 'PT409' using message='Yêu cầu đã thay đổi.'; end if;
    requested:=d->>'action';
    if length(btrim(coalesce(d->>'response',''))) not between 3 and 1000 then raise sqlstate 'PT400' using message='Cần phản hồi/lý do xử lý.'; end if;
    if requested='escalate' and ret.state='rejected' and so.owner_id=auth.uid() then
      select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=ret.product_id;
      select coalesce(sum(quantity),0) into used from public.delivery_market_returns where order_id=so.id and product_id=ret.product_id and state<>'rejected';
      if used+ret.quantity>(item->>'quantity')::integer then raise sqlstate 'PT409' using message='Đã có yêu cầu khác cho số lượng này.'; end if;
      requested:='escalated';
    elsif requested in ('approve','reject') and (so.merchant_id=auth.uid() and a.role='merchant' and ret.state='requested' or op and ret.state in ('requested','escalated')) then
      requested:=case requested when 'approve' then 'approved' else 'rejected' end;
    elsif requested='receive' and ret.state='approved' and (so.merchant_id=auth.uid() and a.role='merchant' or op) then requested:='received';
    else raise sqlstate 'PT403' using message='Không có quyền chuyển trạng thái trả hàng.';
    end if;
    update public.delivery_market_returns set state=requested,response=btrim(d->>'response'),version=version+1,updated_at=now() where id=ret.id returning * into ret;
    insert into public.delivery_market_events(order_id,actor_id,action,reason) values(so.id,auth.uid(),'return_'||requested,btrim(d->>'response'));
    insert into public.delivery_market_notifications(user_id,order_id,kind) values(case when auth.uid()=so.owner_id then so.merchant_id else so.owner_id end,so.id,'return_'||requested);
    return jsonb_build_object('return',to_jsonb(ret));
  elsif p_action='finance_request' then
    requested:=d->>'kind';
    if requested not in ('collection','refund','settlement') or requested is null then raise sqlstate 'PT400' using message='Loại yêu cầu không hợp lệ.'; end if;
    if not op and not (requested='settlement' and so.merchant_id=auth.uid() and a.role='merchant') and not
      (requested='collection' and a.role='driver' and exists(select 1 from public.delivery_cloud_orders where id=so.delivery_id and driver_id=auth.uid())) and not
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
      select i into item from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=ret.product_id;
      select coalesce(sum(amount),0) into used from public.delivery_market_finance where return_id=ret.id and kind='refund' and state<>'rejected';
      if ret.id is null or (d->>'amount')::bigint>ret.quantity*(item->>'unit_price')::bigint-used or (d->>'amount')::bigint>least(goods-refunded-settled,collected-refunded-settled) then raise sqlstate 'PT409' using message='Chưa nhận hàng trả hoặc khoản hoàn vượt mức.'; end if;
    elsif requested='settlement' and ((d->>'amount')::bigint>least(goods-refunded-settled,collected-refunded-settled-freight) or so.delivered_at is null or so.delivered_at>now()-interval '7 days' or exists
      (select 1 from public.delivery_market_returns r join lateral (select i from jsonb_array_elements(so.snapshot->'items') i where (i->>'product_id')::uuid=r.product_id) v on true
        where r.order_id=so.id and (r.state in ('requested','approved','escalated') or r.state='received' and
        r.quantity*(v.i->>'unit_price')::bigint>(select coalesce(sum(amount),0) from public.delivery_market_finance where return_id=r.id and kind='refund' and state='completed')))) then raise sqlstate 'PT409' using message='Chưa có tiền hàng khả dụng để đối soát.';
    end if;
    insert into public.delivery_market_finance(order_id,kind,amount,return_id,proposer,reason,evidence,request_key)
      values(so.id,requested,(d->>'amount')::integer,(d->>'return_id')::uuid,auth.uid(),btrim(d->>'reason'),btrim(d->>'evidence'),(d->>'request_key')::uuid) returning * into f;
    return jsonb_build_object('finance',to_jsonb(f)-'evidence'-'completion_evidence');
  else raise sqlstate 'PT400' using message='Chức năng không được hỗ trợ.';
  end if;
end$$;

revoke all on function public.delivery_market_immutable(),public.delivery_market_balance(),public.delivery_market_order_job(),public.delivery_market_delivered(),public.delivery_market_run_jobs(integer) from public,anon,authenticated;
revoke all on function public.delivery_market_operations(text,jsonb) from public,anon;
grant execute on function public.delivery_market_operations(text,jsonb) to authenticated;
revoke all on function public.delivery_market_public_tracking(text) from public;
grant execute on function public.delivery_market_public_tracking(text) to anon,authenticated;
notify pgrst,'reload schema';
commit;
