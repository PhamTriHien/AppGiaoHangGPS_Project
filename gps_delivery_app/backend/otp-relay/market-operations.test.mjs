import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { startMarketJobs } from './market-operations.mjs';

test('Market jobs do not run without explicit enablement, overlap or leak database failures', async () => {
  let resolve, calls = 0, errors = 0;
  const env = { DATABASE_URL: 'isolated-test-only' };
  const worker = startMarketJobs({ env, schedule: () => 1, unschedule: () => {},
    database: { query: async () => { calls++; await new Promise(r => { resolve = r; }); }, close: async () => {} },
    onError: () => errors++ });
  await worker.tick(); assert.equal(calls, 0);
  env.MARKET_JOBS_ENABLED = 'true';
  const first = worker.tick(); const second = worker.tick();
  assert.equal(calls, 1); resolve(); await Promise.all([first,second]); await worker.close();
  await worker.tick(); assert.equal(calls,1); assert.equal(errors,0);
});

test('Marketplace operational lifecycle, accounting, privacy and aftersales', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`create role authenticated; create role anon;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text); alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated; create publication supabase_realtime;`);
  const migrations = ['20261027_delivery_integrations','20261028_cloud_orders','20261029_payments_ghn','20261029_cloud_addresses','20261030_marketplace','20261031_market_operations'];
  for (const name of migrations) await db.exec(await readFile(new URL(`../../database/migrations/${name}.sql`, import.meta.url), 'utf8'));
  const ids = Object.fromEntries(['buyer','other','merchant','operator','approver','driver'].map(k => [k,randomUUID()]));
  for (const id of Object.values(ids)) await db.query('insert into auth.users values($1)',[id]);
  for (const n of ['operator','approver']) await db.query("insert into delivery_api_profiles values($1,'operator')",[ids[n]]);
  const as = async n => { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[n]]); await db.exec('set role authenticated'); };
  const rpc = async (name,args=[]) => (await db.query(`select public.${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) as data`,args)).rows[0].data;
  const call = (action,d={}) => rpc('delivery_marketplace',[action,d]);
  const ops = (action,d={}) => rpc('delivery_market_operations',[action,d]);
  for (const n of Object.keys(ids)) { await as(n); await rpc('delivery_cloud_profile',[{full_name:n,phone:'0901234567',requested_role:'customer'}]); }
  await as('operator'); await rpc('delivery_cloud_accounts_manage',[ids.merchant,'merchant',false]);
  await rpc('delivery_cloud_accounts_manage',[ids.driver,'driver',false]);
  await as('merchant');
  let shop=(await call('shop_save',{name:'Test shop',address:'12 Nguyen Hue HCM',latitude:10.77,longitude:106.7,paused:false})).shop;
  const product=(await call('product_save',{id:randomUUID(),shop_id:shop.id,name:'Test item',category:'Food',sku:'A',price:50000,stock:20,weight_kg:1,published:true})).product;
  await as('operator'); shop=(await call('shop_moderate',{id:shop.id,version:shop.version,status:'active'})).shop;
  await as('buyer');
  const address=(await rpc('delivery_cloud_addresses_manage',[randomUUID(),{label:'Home',recipient_name:'Buyer',recipient_phone:'0912345678',full_address:'20 Le Loi HCM',latitude:10.78,longitude:106.71,is_default:true},false,null])).addresses[0];
  const checkout = async qty => {
    await as('buyer'); const c=await call('cart'); await call('cart_set',{product_id:product.id,quantity:qty,version:c.version});
    const q=(await call('quote',{address_id:address.id})).quote; const p=(await call('checkout',{quote_id:q.id,request_key:randomUUID()})).purchase;
    return (await call('orders')).orders.find(o=>o.purchase_id===p.id);
  };
  let order=await checkout(2);
  await t.test('Raw operational tables, worker and accounting helpers are inaccessible to app roles',async()=>{
    for (const n of ['jobs','favorites','reviews','returns','finance','journals','ledger','shares','commands']) await assert.rejects(db.exec(`select * from delivery_market_${n}`),/permission denied/);
    await assert.rejects(rpc('delivery_market_run_jobs',[1]),/permission denied/);
    await as('other'); await assert.rejects(ops('order_services',{order_id:order.id}),/Không tìm thấy/);
    await assert.rejects(ops('operations'),/quản trị/);
  });
  await t.test('Favorites are scoped, real product details only expose verified review projection',async()=>{
    await as('buyer'); await ops('favorite_set',{product_id:product.id,enabled:true});
    assert.equal((await ops('favorites')).products.length,1);
    assert.equal((await ops('product_details',{product_id:product.id})).favorite,true);
    await as('other'); assert.equal((await ops('favorites')).products.length,0);
    await as('buyer'); await ops('favorite_set',{product_id:product.id,enabled:false}); assert.equal((await ops('favorites')).products.length,0);
  });
  await t.test('Pending purchases expire, release stock once, reject late acceptance and resume after restart',async()=>{
    await db.exec('reset role');
    await db.query("update delivery_market_shop_orders set accept_by=now()-interval '1 minute' where id=$1",[order.id]);
    await db.query("update delivery_market_jobs set run_at=now()-interval '1 minute' where order_id=$1",[order.id]);
    await as('merchant'); await assert.rejects(call('order_action',{order_id:order.id,version:1,action:'accept'}),/quá hạn/);
    await db.exec('reset role');
    await db.exec(`create function injected_job_failure() returns trigger language plpgsql as $$begin raise exception 'private failure details'; end$$;
      create trigger injected_job_failure before update on delivery_market_products for each row execute function injected_job_failure();`);
    assert.equal((await rpc('delivery_market_run_jobs',[25])).failed,1);
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[product.id])).rows[0].stock,18);
    assert.equal((await db.query('select state from delivery_market_shop_orders where id=$1',[order.id])).rows[0].state,'pending');
    const job=(await db.query('select * from delivery_market_jobs where order_id=$1',[order.id])).rows[0];
    assert.equal(job.attempts,1); assert.equal(job.last_error,'P0001');
    await db.exec('drop trigger injected_job_failure on delivery_market_products; drop function injected_job_failure()');
    await db.query("update delivery_market_jobs set state='failed',attempts=5 where id=$1",[job.id]);
    await as('buyer'); await assert.rejects(ops('job_retry',{id:job.id}),/quản trị/);
    await as('operator'); assert.equal((await ops('operations')).failed_jobs.length,1);
    await ops('job_retry',{id:job.id});
    await db.exec('reset role');
    assert.equal((await rpc('delivery_market_run_jobs',[25])).processed,1);
    assert.equal((await rpc('delivery_market_run_jobs',[25])).processed,0);
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[product.id])).rows[0].stock,20);
    const audit=(await db.query("select actor_id,actor_source from delivery_market_stock where reason='acceptance_expired'")).rows[0];
    assert.equal(audit.actor_id,null); assert.equal(audit.actor_source,'system');
  });
  order=await checkout(2);
  await t.test('Early financial claims/reviews/returns fail; reorder validates prices/stock and replays once',async()=>{
    await assert.rejects(ops('review_save',{order_id:order.id,product_id:product.id,rating:5,body:'Excellent'}),/nhận hàng/);
    await assert.rejects(ops('return_request',{order_id:order.id,product_id:product.id,quantity:1,reason:'Broken item',request_key:randomUUID()}),/7 ngày/);
    const c=await call('cart'), payload={order_id:order.id,version:c.version,request_key:randomUUID()};
    assert.equal((await ops('reorder',payload)).items[0].quantity,2);
    assert.equal((await ops('reorder',payload)).items[0].quantity,2);
    assert.equal((await call('cart')).items[0].quantity,2);
    await assert.rejects(ops('reorder',{...payload,version:c.version+1}),/đã được dùng/);
    await as('operator'); await assert.rejects(ops('finance_request',{order_id:order.id,kind:'collection',amount:100000,reason:'COD collection',evidence:'Receipt 1',request_key:randomUUID()}),/sau giao hàng/);
  });
  await as('merchant');
  order=(await call('order_action',{order_id:order.id,version:order.version,action:'accept'})).order;
  order=(await call('order_action',{order_id:order.id,version:order.version,action:'ready'})).order;
  await db.exec('reset role');
  await db.query("update delivery_cloud_orders set status='delivered',version=version+1 where id=$1",[order.delivery_id]);
  const due=order.snapshot.subtotal+order.snapshot.shipping_fee;
  let collection;
  await t.test('Delivery alone never marks paid; COD uses independent approval and balanced immutable journal',async()=>{
    await as('buyer'); assert.equal((await call('orders')).orders.find(o=>o.id===order.id).payment_status,'UNPAID');
    await assert.rejects(ops('finance_request',{order_id:order.id,kind:'collection',amount:due,reason:'COD',evidence:'Receipt A',request_key:randomUUID()}),/quyền/);
    await as('operator'); const payload={order_id:order.id,kind:'collection',amount:due,reason:'Collected COD',evidence:'Receipt A',request_key:randomUUID()};
    collection=(await ops('finance_request',payload)).finance;
    assert.equal((await ops('finance_request',payload)).finance.id,collection.id);
    await assert.rejects(ops('finance_action',{id:collection.id,version:1,action:'approve'}),/tự duyệt/);
    await as('approver'); collection=(await ops('finance_action',{id:collection.id,version:1,action:'approve',reason:'Verified receipt'})).finance;
    await assert.rejects(ops('finance_action',{id:collection.id,version:collection.version,action:'complete'}),/chứng từ/);
    collection=(await ops('finance_action',{id:collection.id,version:collection.version,action:'complete',evidence:'Verified bank statement 10'})).finance;
    await assert.rejects(ops('finance_action',{id:collection.id,version:collection.version,action:'complete',evidence:'Same receipt'}),/trạng thái/);
    await db.exec('reset role');
    assert.equal((await db.query('select sum(amount)::int as amount from delivery_market_ledger')).rows[0].amount,0);
    await assert.rejects(db.exec('update delivery_market_ledger set amount=1'),/Immutable/);
    await assert.rejects(db.exec('delete from delivery_market_journals'),/Immutable/);
    await as('buyer'); assert.equal((await ops('order_services',{order_id:order.id})).collected,due);
    assert.ok((await ops('order_services',{order_id:order.id})).finance.every(f=>!Object.hasOwn(f,'evidence')));
  });
  let ret;
  await t.test('Verified reviews reject foreign orders, duplicate edits and private author leakage',async()=>{
    await as('other'); await assert.rejects(ops('review_save',{order_id:order.id,product_id:product.id,rating:5,body:'Forged'}),/Không tìm thấy/);
    await as('buyer'); const payload={order_id:order.id,product_id:product.id,rating:4,body:'Received as described'};
    const review=(await ops('review_save',payload)).review; assert.equal((await ops('review_save',payload)).review.id,review.id);
    await assert.rejects(ops('review_save',{...payload,rating:5}),/đã được đánh giá/);
    await as('other'); const reviews=(await ops('product_details',{product_id:product.id})).reviews;
    assert.equal(reviews.length,1); assert.equal(reviews[0].user_id,undefined); assert.equal(reviews[0].order_id,undefined);
    await as('operator'); await ops('review_moderate',{id:review.id,hidden:true,reason:'Privacy report'});
    await as('buyer'); assert.equal((await ops('product_details',{product_id:product.id})).reviews.length,0);
  });
  await t.test('Returns are item/quantity bounded; disputes cannot exceed purchased quantity or self-confirm receipt',async()=>{
    const payload={order_id:order.id,product_id:product.id,quantity:1,reason:'Damaged item',request_key:randomUUID()};
    ret=(await ops('return_request',payload)).return;
    assert.equal((await ops('return_request',payload)).return.id,ret.id);
    await assert.rejects(ops('return_request',{...payload,quantity:2,request_key:randomUUID()}),/vượt/);
    await assert.rejects(ops('return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'approve',response:'I approve'}),/quyền/);
    await as('merchant'); ret=(await ops('return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'reject',response:'Need inspection'})).return;
    await as('buyer'); ret=(await ops('return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'escalate',response:'Please investigate'})).return;
    await as('operator'); ret=(await ops('return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'approve',response:'Return approved'})).return;
    await as('buyer'); await assert.rejects(ops('return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'receive',response:'Self confirmed'}),/quyền/);
    await as('merchant'); ret=(await ops('return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'receive',response:'Parcel inspected'})).return;
  });
  await t.test('Partial refund needs received return, independent approval and evidence; cannot refund twice',async()=>{
    await as('buyer'); const payload={order_id:order.id,return_id:ret.id,kind:'refund',amount:50000,reason:'Returned item',evidence:'Returned parcel R1',request_key:randomUUID()};
    let f=(await ops('finance_request',payload)).finance;
    await assert.rejects(ops('finance_request',{...payload,request_key:randomUUID()}),/vượt/);
    await as('approver'); f=(await ops('finance_action',{id:f.id,version:f.version,action:'approve',reason:'Verified return'})).finance;
    f=(await ops('finance_action',{id:f.id,version:f.version,action:'complete',evidence:'Refund bank transfer R2'})).finance;
    await as('buyer'); assert.equal((await ops('order_services',{order_id:order.id})).refunded,50000);
    await assert.rejects(ops('finance_request',{...payload,request_key:randomUUID()}),/vượt/);
    await db.exec('reset role'); assert.equal((await db.query('select sum(amount)::int as amount from delivery_market_ledger')).rows[0].amount,0);
  });
  await t.test('Settlement waits for aftersales window and pays only remaining collected goods',async()=>{
    await as('merchant'); const payload={order_id:order.id,kind:'settlement',amount:50000,reason:'Shop payout',evidence:'Statement S1',request_key:randomUUID()};
    await assert.rejects(ops('finance_request',payload),/khả dụng/);
    await db.exec('reset role'); await db.query("update delivery_market_shop_orders set delivered_at=now()-interval '8 days' where id=$1",[order.id]);
    await as('merchant'); let f=(await ops('finance_request',payload)).finance;
    await as('approver'); f=(await ops('finance_action',{id:f.id,version:f.version,action:'approve',reason:'Verified settlement'})).finance;
    await ops('finance_action',{id:f.id,version:f.version,action:'complete',evidence:'Shop bank transfer S2'});
    await as('merchant'); await assert.rejects(ops('finance_request',{...payload,request_key:randomUUID()}),/khả dụng/);
    assert.equal((await ops('order_services',{order_id:order.id})).settled,50000);
  });
  await t.test('Tracking is token-only, expires/revokes, and exposes no private order data',async()=>{
    await as('buyer'); const share=await ops('tracking_share',{order_id:order.id});
    assert.match(share.token,/^[a-f0-9]{64}$/);
    await db.exec('reset role; set role anon');
    const projection=await rpc('delivery_market_public_tracking',[share.token]);
    assert.deepEqual(Object.keys(projection).sort(),['delivery_status','expires_at','shop_name','state','updated_at']);
    await assert.rejects(rpc('delivery_market_public_tracking',[order.id]),/hết hạn/);
    await as('buyer'); await ops('tracking_revoke',{order_id:order.id,id:share.id});
    await db.exec('reset role; set role anon'); await assert.rejects(rpc('delivery_market_public_tracking',[share.token]),/hết hạn/);
  });
  await t.test('Reapplying is additive and accounting constraints reject an empty journal',async()=>{
    await db.exec('reset role'); await db.exec(await readFile(new URL('../../database/migrations/20261031_market_operations.sql',import.meta.url),'utf8'));
    assert.equal((await db.query('select count(*)::int as n from delivery_market_journals')).rows[0].n,3);
    await assert.rejects(db.query('insert into delivery_market_journals(finance_id,order_id) values($1,$2)',[randomUUID(),order.id]),/foreign key/);
    const f=(await db.query("insert into delivery_market_finance(order_id,kind,amount,proposer,reason,evidence,request_key) values($1,'refund',1,$2,'Balance test','Test only',$3) returning id",[order.id,ids.operator,randomUUID()])).rows[0];
    await assert.rejects(db.query('insert into delivery_market_journals(finance_id,order_id) values($1,$2)',[f.id,order.id]),/Unbalanced/);
    assert.equal((await db.query('select count(*)::int as n from delivery_market_journals')).rows[0].n,3);
    await db.query('delete from delivery_market_finance where id=$1',[f.id]);
    await as('operator'); assert.equal((await ops('operations')).finance.length,3);
  });
  await t.test('Finance timestamp-plus-ID pagination preserves tied timestamps; blocking closes operations',async()=>{
    await db.exec('reset role');
    const inserted=[];
    for(let i=0;i<55;i++) inserted.push((await db.query("insert into delivery_market_finance(order_id,kind,amount,proposer,reason,evidence,request_key,created_at) values($1,'refund',1,$2,'Pagination test','Test only',$3,'2030-01-01') returning id",[order.id,ids.operator,randomUUID()])).rows[0].id);
    await as('operator'); const first=await ops('operations'),second=await ops('operations',first.next);
    const all=[...first.finance,...second.finance].map(f=>f.id);
    assert.equal(all.length,58); assert.equal(new Set(all).size,58);
    await db.exec('reset role'); await db.query('delete from delivery_market_finance where id=any($1::uuid[])',[inserted]);
    await as('operator'); await rpc('delivery_cloud_accounts_manage',[ids.buyer,'customer',true]);
    await as('buyer'); await assert.rejects(ops('favorites'),/hoạt động/);
    await assert.rejects(ops('order_services',{order_id:order.id}),/hoạt động/);
  });
});
