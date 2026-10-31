import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';

test('Cloud orders enforce identities, authoritative fees, approvals, transitions, privacy and idempotent commands in PostgreSQL', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`create role authenticated; create role anon;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text); alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated; create publication supabase_realtime;`);
  await db.exec(await readFile(new URL('../../database/migrations/20261027_delivery_integrations.sql', import.meta.url), 'utf8'));
  const sql = await readFile(new URL('../../database/migrations/20261028_cloud_orders.sql', import.meta.url), 'utf8');
  await db.exec(sql);
  await db.exec(sql);
  const ids = Object.fromEntries(['customer','merchant','driver','otherDriver','outsider','operator'].map((role,i) => [role,`00000000-0000-0000-0000-00000000000${i+1}`]));
  for (const id of Object.values(ids)) await db.query('insert into auth.users values($1)',[id]);
  await db.query("insert into delivery_api_profiles values($1,'operator')",[ids.operator]);
  const as = async role => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[role]]);
    await db.exec('set role authenticated');
  };
  const rpc = async (name,args=[],placeholders=args.map((_,i)=>`$${i+1}`).join(',')) =>
    (await db.query(`select public.${name}(${placeholders}) as result`,args)).rows[0].result;
  for (const role of Object.keys(ids)) {
    await as(role);
    const profile = await rpc('delivery_cloud_profile',[{full_name:role,phone:'0901234567',requested_role:['driver','otherDriver'].includes(role)?'driver':role==='merchant'?'merchant':'customer'}]);
    assert.equal(profile.account.role,'customer');
  }
  await as('driver');
  await assert.rejects(rpc('delivery_cloud_list',[true]),/tài xế được duyệt/);
  await assert.rejects(rpc('delivery_cloud_accounts_manage',[ids.driver,'driver',false]),/operator/);
  await assert.rejects(db.exec("update delivery_cloud_accounts set role='driver'"),/permission denied/);
  await as('operator');
  for(const role of ['merchant','driver','otherDriver']) await rpc('delivery_cloud_accounts_manage',[ids[role],role==='merchant'?'merchant':'driver',false]);
  const details={pickup_address:'12 Nguyen Hue, TP HCM',dropoff_address:'20 Le Loi, TP HCM',pickup_lat:10.77,pickup_lng:106.7,
    dropoff_lat:10.78,dropoff_lng:106.71,weight_kg:1,service_type:'standard',recipient_name:'Real Customer',recipient_phone:'0912345678',
    package_description:'Documents',cod_amount:120000,payment_method:'recipient_cash',merchant_id:ids.merchant};
  const createKey='10000000-0000-0000-0000-000000000001';
  await as('customer');
  const quote=await rpc('delivery_cloud_quote',[details]);
  assert.ok(quote.shipping_fee>=25000);
  await assert.rejects(rpc('delivery_cloud_quote',[{...details,service_type:null}]),/không hợp lệ/);
  await assert.rejects(rpc('delivery_cloud_quote',[{...details,weight_kg:31}]),/không hợp lệ/);
  await assert.rejects(rpc('delivery_cloud_pricing_manage',[{base_fee:0,per_km:0,express_fee:0,extra_kg:0,version:1}]),/operator/);
  await as('operator');
  const newPrice=await rpc('delivery_cloud_pricing_manage',[{base_fee:30000,per_km:5000,express_fee:10000,extra_kg:3000,version:1}]);
  assert.equal(newPrice.pricing.version,2);
  await assert.rejects(rpc('delivery_cloud_pricing_manage',[{base_fee:30000,per_km:5000,express_fee:10000,extra_kg:3000,version:1}]),/Bảng giá đã thay đổi/);
  assert.ok((await rpc('delivery_cloud_audit_read')).entries.some(e=>e.action==='pricing'));
  await as('customer');
  await assert.rejects(rpc('delivery_cloud_create',[details,createKey,quote.pricing_version,quote.shipping_fee]),/Giá cước/);
  Object.assign(quote,await rpc('delivery_cloud_quote',[details]));
  await assert.rejects(rpc('delivery_cloud_create',[details,createKey,quote.pricing_version,1]),/Giá cước/);
  const order=await rpc('delivery_cloud_create',[details,createKey,quote.pricing_version,quote.shipping_fee]);
  assert.equal(order.merchant_ready,false); assert.equal(order.owner_id,ids.customer); assert.equal(order.payment_status,'UNPAID');
  assert.equal((await rpc('delivery_cloud_create',[details,createKey,quote.pricing_version,quote.shipping_fee])).id,order.id);
  await assert.rejects(rpc('delivery_cloud_create',[{...details,cod_amount:0},createKey,quote.pricing_version,quote.shipping_fee]),/nội dung khác/);
  await assert.rejects(rpc('delivery_cloud_create',[{...details,payment_status:'PAID'},'10000000-0000-0000-0000-000000000007',quote.pricing_version,quote.shipping_fee]),/trường không hỗ trợ/);
  await assert.rejects(db.exec("update delivery_cloud_orders set shipping_fee=0"),/permission denied/);
  await assert.rejects(db.query('insert into delivery_cloud_orders(owner_id) values($1)',[ids.customer]),/permission denied/);
  await assert.rejects(rpc('delivery_cloud_transition',[order.id,'deliver',1,'20000000-0000-0000-0000-000000000001','']),/Chỉ tài xế/);
  await assert.rejects(db.query("insert into delivery_live_events(room_id,kind,payload) values($1,'status',$2)",[order.tracking_code,{status:'delivered',version:1}]),/API cloud/);
  await as('outsider');
  assert.equal((await rpc('delivery_cloud_list')).orders.length,0);
  assert.equal((await db.query('select * from delivery_cloud_orders')).rows.length,0);
  await assert.rejects(rpc('delivery_cloud_history_read',[order.id]),/Không tìm thấy/);
  await as('merchant');
  const ready=await rpc('delivery_cloud_transition',[order.id,'ready',1,'20000000-0000-0000-0000-000000000002','']);
  assert.equal(ready.version,2);
  await as('driver');
  const queue=(await rpc('delivery_cloud_list',[true])).orders;
  assert.equal(queue.length,1);
  assert.equal(JSON.stringify(queue).includes('0912345678'),false);
  assert.equal(JSON.stringify(queue).includes('Nguyen Hue'),false);
  const claimKey='20000000-0000-0000-0000-000000000003';
  const claimed=await rpc('delivery_cloud_transition',[order.id,'claim',2,claimKey,'']);
  assert.equal(claimed.driver_id,ids.driver); assert.equal(claimed.status,'accepted');
  assert.equal((await rpc('delivery_cloud_transition',[order.id,'claim',2,claimKey,''])).version,3);
  await as('customer');
  const secondDetails={...details};delete secondDetails.merchant_id;
  const second=await rpc('delivery_cloud_create',[secondDetails,'10000000-0000-0000-0000-000000000002',quote.pricing_version,quote.shipping_fee]);
  await as('driver');
  await assert.rejects(rpc('delivery_cloud_transition',[second.id,'claim',1,'20000000-0000-0000-0000-000000000008','']),/chuyến chưa hoàn tất/);
  await assert.rejects(rpc('delivery_cloud_transition',[order.id,'cancel',3,'20000000-0000-0000-0000-000000000004','Driver cancels']),/Không thể hủy/);
  await as('otherDriver');
  await assert.rejects(rpc('delivery_cloud_transition',[order.id,'claim',2,'20000000-0000-0000-0000-000000000005','']),/Không tìm thấy/);
  await as('driver');
  let version=3;
  for (const [i,action] of ['arrive','pickup','deliver'].entries()) {
    const changed=await rpc('delivery_cloud_transition',[order.id,action,version,`30000000-0000-0000-0000-00000000000${i+1}`,'']);
    version=changed.version;
  }
  assert.equal((await rpc('delivery_cloud_list')).orders.find(o=>o.id===order.id).status,'delivered');
  assert.equal((await rpc('delivery_cloud_history_read',[order.id])).history.length,6);
  await assert.rejects(rpc('delivery_cloud_transition',[order.id,'pickup',version,'30000000-0000-0000-0000-000000000005','']),/không phù hợp/);
  await as('operator');
  await rpc('delivery_cloud_accounts_manage',[ids.driver,'driver',true]);
  await as('driver');
  await assert.rejects(rpc('delivery_cloud_list'),/đang hoạt động/);
  await assert.rejects(db.query("insert into delivery_live_events(room_id,kind,payload) values($1,'chat',$2)",[order.tracking_code,{text:'Blocked sender'}]),/row-level security/);
  await db.exec("reset role; update delivery_cloud_orders set created_at='2026-10-27T00:00:00Z'");
  await as('customer');
  const tied=(await rpc('delivery_cloud_list')).orders;
  assert.equal(tied.length,2);
  const older=(await rpc('delivery_cloud_list',[false,tied[0].created_at,tied[0].id])).orders;
  assert.equal(older.length,1);
  assert.equal(older[0].id,tied[1].id);

  await t.test('Reapplying the migration upgrades legacy tables without deleting orders or history', async () => {
    await db.exec(`reset role;
      alter table delivery_cloud_history drop column reason;
      alter table delivery_cloud_orders drop constraint delivery_cloud_orders_status_check;
      alter table delivery_cloud_orders add constraint delivery_cloud_orders_status_check
        check(status in ('searching','accepted','arrivingPickup','inTransit','delivered','failed','returning','cancelled'));`);
    await db.exec(sql);
    await as('customer');
    assert.equal((await rpc('delivery_cloud_list')).orders.length,2);
    const history=(await rpc('delivery_cloud_history_read',[order.id])).history;
    assert.equal(history.length,6);
    assert.ok(history.every(h=>h.reason===''));
  });

  await t.test('Blocking preserves pending approval, rejection clears it and profiles cannot unblock themselves', async () => {
    await as('outsider');
    await rpc('delivery_cloud_profile',[{full_name:'Pending driver',phone:'0901234567',requested_role:'driver'}]);
    await as('operator');
    let accounts=(await rpc('delivery_cloud_accounts_manage',[ids.outsider,'customer',true])).accounts;
    assert.equal(accounts.find(a=>a.user_id===ids.outsider).requested_role,'driver');
    await as('outsider');
    const profile=await rpc('delivery_cloud_profile',[{full_name:'Pending driver',phone:'0901234567',requested_role:'driver',blocked:false,role:'driver'}]);
    assert.equal(profile.account.blocked,true);
    assert.equal(profile.account.role,'customer');
    await assert.rejects(rpc('delivery_cloud_quote',[details]),/đang hoạt động/);
    await as('operator');
    accounts=(await rpc('delivery_cloud_accounts_manage',[ids.outsider,'customer',false])).accounts;
    assert.equal(accounts.find(a=>a.user_id===ids.outsider).requested_role,'driver');
    accounts=(await rpc('delivery_cloud_accounts_manage',[ids.outsider,'customer',false])).accounts;
    assert.equal(accounts.find(a=>a.user_id===ids.outsider).requested_role,null);
  });

  await t.test('Direct pricing writes reject nulls, strings, fractional amounts, over-limit values and unsupported fields', async () => {
    await as('operator');
    const price={base_fee:30000,per_km:5000,express_fee:10000,extra_kg:3000,version:2};
    for (const patch of [{base_fee:null},{per_km:'5000'},{extra_kg:1.5},{base_fee:-1},{per_km:100001},{version:0},{unknown:0}]) {
      await assert.rejects(rpc('delivery_cloud_pricing_manage',[{...price,...patch}]),/không hợp lệ|số nguyên/);
    }
    await as('customer');
    const short={...secondDetails,dropoff_lat:details.pickup_lat,dropoff_lng:details.pickup_lng,weight_kg:5};
    const base=await rpc('delivery_cloud_quote',[short]);
    assert.equal(base.shipping_fee,30000);
    const heavy=await rpc('delivery_cloud_quote',[{...short,weight_kg:5.1,service_type:'express'}]);
    assert.equal(heavy.shipping_fee,43000);
    assert.equal(heavy.shipping_fee,Object.values(heavy.breakdown).reduce((sum,v)=>sum+v,0));
  });

  await t.test('Failure requires a reason, retry remains active and a completed return is distinct from delivery', async () => {
    await as('operator');
    await rpc('delivery_cloud_accounts_manage',[ids.driver,'driver',false]);
    await as('customer');
    const fee=await rpc('delivery_cloud_quote',[secondDetails]);
    const returnedOrder=await rpc('delivery_cloud_create',[secondDetails,randomUUID(),fee.pricing_version,fee.shipping_fee]);
    const transition=(o,action,reason='')=>rpc('delivery_cloud_transition',[o.id,action,o.version,randomUUID(),reason]);
    await as('driver');
    let changed=await transition(returnedOrder,'claim');
    await as('operator');
    await assert.rejects(rpc('delivery_cloud_accounts_manage',[ids.driver,'customer',false]),/chuyến chưa hoàn tất/);
    await as('driver');
    changed=await transition(changed,'arrive');
    changed=await transition(changed,'pickup');
    await assert.rejects(transition(changed,'cancel','Cannot cancel after pickup'),/Không thể hủy/);
    await assert.rejects(transition(changed,'fail'),/lý do/);
    changed=await transition(changed,'fail','Recipient unavailable');
    assert.equal(changed.status,'failed');
    changed=await transition(changed,'retry');
    assert.equal(changed.status,'inTransit');
    changed=await transition(changed,'fail','Recipient refused package');
    await assert.rejects(transition(changed,'return',' '),/lý do/);
    changed=await transition(changed,'return','Return requested by sender');
    await assert.rejects(transition(changed,'deliver'),/không phù hợp/);
    changed=await transition(changed,'complete_return');
    assert.equal(changed.status,'returned');
    assert.equal(changed.payment_status,'UNPAID');
    const history=(await rpc('delivery_cloud_history_read',[changed.id])).history;
    assert.equal(history.find(h=>h.action==='return').reason,'Return requested by sender');
    assert.equal(history.filter(h=>h.action==='fail').length,2);
    assert.equal(history.at(-1).status,'returned');
    const next=await transition(second,'claim');
    assert.equal(next.status,'accepted');
    await as('operator');
    await transition(next,'cancel','Sender cancelled before pickup');
    await as('customer');
    const cancelled=await rpc('delivery_cloud_create',[secondDetails,randomUUID(),fee.pricing_version,fee.shipping_fee]);
    const final=await transition(cancelled,'cancel','Wrong pickup address');
    assert.equal(final.status,'cancelled');
    assert.equal((await rpc('delivery_cloud_history_read',[final.id])).history.at(-1).reason,'Wrong pickup address');
    await assert.rejects(transition(final,'cancel','Already cancelled'),/Không thể hủy/);
    await db.exec('reset role');
    await db.exec(sql);
    await as('customer');
    assert.equal((await rpc('delivery_cloud_profile')).schema_version,2);
    assert.equal((await rpc('delivery_cloud_history_read',[final.id])).history.at(-1).reason,'Wrong pickup address');
  });
  await db.exec('reset role; set role anon');
  await assert.rejects(rpc('delivery_cloud_list'),/permission denied/);
});

test('Cloud gateway validates tariffs and reasons and refuses mutations on an outdated cloud schema', async t => {
  let schemaVersion=1;
  const calls=[];
  const app=express();app.use(express.json());
  app.use('/cloud',createCloudOrders({env:{SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'public-key'},
    authenticate(req,_res,next){req.deliveryIdentity={id:'verified-user',token:'user-jwt'};next();},
    fetcher:async (url,options)=>{
      calls.push({url:String(url),body:JSON.parse(options.body)});
      return new Response(JSON.stringify(String(url).endsWith('delivery_cloud_profile')?{schema_version:schemaVersion}:{}),{status:200});
    }}));
  app.use((error,_req,res,_next)=>res.status(error.status||500).json({error:error.message}));
  const server=app.listen(0,'127.0.0.1');t.after(()=>server.close());await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/cloud`;
  const post=(endpoint,body)=>fetch(base+endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const id='10000000-0000-0000-0000-000000000001';
  const price={base_fee:25000,per_km:5000,express_fee:10000,extra_kg:3000,version:1};
  assert.equal((await post('/pricing',{...price,extra_kg:100001})).status,400);
  assert.equal((await post('/pricing',{...price,base_fee:1.5})).status,400);
  assert.equal((await post('/pricing',{...price,unknown:0})).status,400);
  assert.equal((await post(`/orders/${id}/transition`,{action:'fail',version:1,request_key:id,reason:' '})).status,400);
  assert.equal(calls.length,0);
  for (const [endpoint,body] of [['/pricing',price],[`/accounts/${id}`,{role:'driver',blocked:false}],[`/orders/${id}/transition`,{action:'deliver',version:1,request_key:id}]]) {
    const response=await post(endpoint,body);
    assert.equal(response.status,503);
    assert.match((await response.json()).error,/Cloud cần cập nhật/);
  }
  assert.ok(calls.every(c=>c.url.endsWith('delivery_cloud_profile')));
  schemaVersion=2;
  assert.equal((await post(`/orders/${id}/transition`,{action:'complete_return',version:1,request_key:id})).status,200);
  assert.equal(calls.at(-1).body.p_action,'complete_return');
});

test('Cloud HTTP gateway rejects local identity, forwards only verified user JWT and preserves domain conflicts', async t => {
  let mode='local'; const calls=[];
  const app=express(); app.use(express.json());
  app.use('/cloud',createCloudOrders({env:{SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'public-key'},
    authenticate(req,_res,next){req.deliveryIdentity={id:'verified-user',token:'user-jwt',local:mode==='local'};next();},
    fetcher:async (url,options)=>{calls.push({url:String(url),options});return new Response(JSON.stringify({code:'PT409',message:'Đơn đã thay đổi.'}),{status:409});}}));
  app.use((error,_req,res,_next)=>res.status(error.status||500).json({error:error.message}));
  const server=app.listen(0,'127.0.0.1');t.after(()=>server.close()); await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/cloud`;
  assert.equal((await fetch(`${base}/orders`)).status,401);assert.equal(calls.length,0);
  mode='cloud';
  assert.equal((await fetch(`${base}/orders?before=invalid`)).status,400);assert.equal(calls.length,0);
  const response=await fetch(`${base}/orders`);assert.equal(response.status,409);
  assert.equal(calls[0].options.headers.Authorization,'Bearer user-jwt');
  assert.equal(calls[0].url,'https://example.supabase.co/rest/v1/rpc/delivery_cloud_list');
});
