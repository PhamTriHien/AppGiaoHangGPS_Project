import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { createHmac, randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { PayOS } from '@payos/node';
import express from 'express';
import { createPaymentGateway, resolvePayosRedirectUrl } from './payment-gateway.mjs';
import { createGhnGateway } from './ghn-gateway.mjs';
import { integrationUsage } from './integration-monitor.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from './deployment-readiness.mjs';

test('commerce uses durable PostgreSQL state, verified receipts and authoritative carrier data', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`create role authenticated; create role anon;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text); alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated;
    create publication supabase_realtime;`);
  for (const file of ['20261027_delivery_integrations.sql','20261028_cloud_orders.sql','20261029_payments_ghn.sql','20261029_payments_ghn.sql','20261029_cloud_addresses.sql','20261030_marketplace.sql','20261031_market_operations.sql','20261101_partner_memberships.sql','20261102_local_address_import.sql','20261103_catalog_stock_versions.sql','20261104_market_media.sql','20261105_market_browse.sql','20261106_catalog_configuration.sql','20261107_cloud_commercial_suite.sql','20261108_cloud_logistics.sql','20261109_admin_account_management.sql','20261110_cloud_promo_events.sql','20261111_profile_push_shipping_coins.sql','20261112_shipping_cash_settlement.sql','20261113_cloud_sync_and_journey.sql','20261113_cloud_sync_and_journey.sql']) {
    await db.exec(await readFile(new URL(`../../database/migrations/${file}`,import.meta.url),'utf8'));
  }
  const ids = Object.fromEntries(['owner','outsider','operator','driver','blocked'].map(key=>[key,randomUUID()]));
  for (const [name,id] of Object.entries(ids)) {
    await db.query('insert into auth.users values($1)',[id]);
    await db.query('insert into delivery_cloud_accounts(user_id,full_name,phone,role,blocked) values($1,$2,$3,$4,$5)',
      [id,name,'0901234567',name==='driver'?'driver':'customer',name==='blocked']);
  }
  const database={query:(...args)=>db.query(...args),transaction:op=>db.transaction(tx=>op(tx))};
  const env={DATABASE_URL:'postgresql://test',PAYOS_ENABLED:'true',PAYOS_CLIENT_ID:'test-client',PAYOS_API_KEY:'test-api',
    PAYOS_CHECKSUM_KEY:'test-checksum',GHN_ENABLED:'true',GHN_TOKEN:'test-token',GHN_SHOP_ID:'123',
    GHN_BASE_URL:'https://dev-online-gateway.ghn.vn/shiip/public-api/',GHN_WEBHOOK_SECRET:'test-callback-secret'};
  const details={pickup_address:'12 Nguyen Hue',dropoff_address:'20 Le Loi',weight_kg:1,recipient_name:'Receiver',
    recipient_phone:'0912345678',package_description:'Documents',payment_method:'sender_cash'};
  async function order(patch={}) {
    return (await db.query(`insert into delivery_cloud_orders(owner_id,request_key,request_payload,details,distance_meters,shipping_fee,cod_amount,pricing_version,merchant_ready)
      values($1,$2,'{}',$3,1500,30000,120000,1,false) returning *`,[patch.owner_id??ids.owner,randomUUID(),{...details,...patch.details}])).rows[0];
  }
  const paymentLinks=new Map(), createCalls=[];
  let paymentTimeout=false,ghnTimeout=false,cancelAllowed=true;
  const sdk=new PayOS({clientId:env.PAYOS_CLIENT_ID,apiKey:env.PAYOS_API_KEY,checksumKey:env.PAYOS_CHECKSUM_KEY});
  const clientFactory=()=>({webhooks:sdk.webhooks,paymentRequests:{
    async create(input) {
      createCalls.push(input);
      const id=`link-${input.orderCode}`;
      paymentLinks.set(input.orderCode,{id,orderCode:input.orderCode,amount:input.amount,amountPaid:0,status:'PENDING',transactions:[]});
      if(paymentTimeout) throw new Error('connection dropped after provider created link');
      return {paymentLinkId:id,orderCode:input.orderCode,amount:input.amount,checkoutUrl:`https://pay.payos.vn/web/${id}`,qrCode:'verified-provider-qr'};
    },
    async get(code) { const value=paymentLinks.get(code); if(!value) throw new Error('not found'); return value; },
    async cancel(code) { const value=paymentLinks.get(code); if(value.amountPaid===0) value.status='CANCELLED'; return value; },
  }});
  const ghnCalls=[],carrierDetails=new Map();
  const fetcher=async(url,options)=>{
    const path=new URL(url).pathname, body=options.body?JSON.parse(options.body):null;
    ghnCalls.push({path,body});
    let data;
    if(path.endsWith('/preview')) data={total_fee:28000,expected_delivery_time:'2026-11-01T10:00:00Z'};
    else if(path.endsWith('/create')) {
      const code=`GHN${body.client_order_code.slice(-10).toUpperCase()}`;
      carrierDetails.set(code,{order_code:code,client_order_code:body.client_order_code,shop_id:123,status:'ready_to_pick',updated_date:'2026-10-28T10:00:00Z'});
      if(ghnTimeout) throw new Error('uncertain create');
      data={order_code:code,total_fee:28000};
    } else if(path.endsWith('/detail')) data=carrierDetails.get(new URL(url).searchParams.get('order_code'));
    else if(path.endsWith('/cancel')) {
      const code=body.order_codes[0];
      if(cancelAllowed) Object.assign(carrierDetails.get(code),{status:'cancel',updated_date:'2026-10-30T10:00:00Z'});
      data=[{order_code:code,result:cancelAllowed}];
    } else throw new Error(`unexpected route ${path}`);
    return new Response(JSON.stringify({code:200,data}),{status:200});
  };
  const app=express(); app.use(express.json());
  function authenticate(req,_res,next) {
    const name=req.get('x-test-actor')||'owner';
    req.deliveryIdentity={id:ids[name]||ids.owner,role:name==='operator'?'operator':'user',local:name==='local'};next();
  }
  app.use('/delivery',createPaymentGateway({env,database,authenticate,clientFactory}));
  app.use('/delivery',createGhnGateway({env,database,authenticate,fetcher}));
  app.use((error,_req,res,_next)=>res.status(error.status||(/^PT\d+$/.test(error.code)?Number(error.code.slice(2)):500)).json({error:error.message}));
  const server=app.listen(0,'127.0.0.1');t.after(()=>server.close());
  await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/delivery`;
  async function request(path,body,actor='owner',headers={}) {
    const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json','x-test-actor':actor,...headers},
      ...(body===undefined?{}:{body:JSON.stringify(body)})});
    return {status:response.status,body:await response.json()};
  }
  const payment=(o,suffix='')=>`/cloud/orders/${o.id}/payment${suffix}`;
  const shipment=(o,suffix='')=>`/cloud/orders/${o.id}/shipment${suffix}`;
  function signed(data) {
    const text=Object.keys(data).sort().map(key=>`${key}=${data[key]}`).join('&');
    return {data,signature:createHmac('sha256',env.PAYOS_CHECKSUM_KEY).update(text).digest('hex')};
  }
  const receipt=(p,patch={})=>signed({code:'00',currency:'VND',orderCode:Number(p.provider_order_code),amount:p.amount,
    paymentLinkId:`link-${p.provider_order_code}`,reference:randomUUID(),...patch});
  const fields={from_province_name:'Ho Chi Minh',from_ward_name:'Sai Gon',to_province_name:'Ho Chi Minh',to_ward_name:'Ben Thanh',
    length:20,width:15,height:10,required_note:'KHONGCHOXEMHANG',cod_amount:1,weight:1};

  await t.test('authorization and disabled services prevent external calls',async()=>{
    const o=await order();
    assert.equal((await request(payment(o),undefined,'outsider')).status,404);
    assert.equal((await request(payment(o),undefined,'local')).status,401);
    assert.equal((await request(payment(await order({owner_id:ids.blocked})))).status,404);
    const blocked=await order({owner_id:ids.blocked});
    assert.equal((await request(payment(blocked),{},'blocked')).status,403);
    env.PAYOS_ENABLED='false';
    assert.equal((await request(payment(o),{})).status,503);
    env.PAYOS_ENABLED='true';
    assert.equal((await request(shipment(o,'/preview'),fields)).status,403);
    assert.equal(createCalls.length,0);assert.equal(ghnCalls.length,0);
  });
  await t.test('authoritative amount, idempotent intent, invalid signature and dispatch guard',async()=>{
    const o=await order();
    const first=await request(payment(o),{amount:1,owner_id:ids.outsider});
    assert.equal(first.status,200);
    const p=first.body.payment;
    assert.equal(p.amount,30000);assert.equal(createCalls.at(-1).amount,30000);
    assert.equal((await request(payment(o),{})).body.payment.id,p.id);
    await assert.rejects(db.query("update delivery_cloud_orders set status='accepted',driver_id=$1 where id=$2",[ids.driver,o.id]),e=>e.code==='PT409');
    await assert.rejects(db.query("update delivery_cloud_orders set status='cancelled' where id=$1",[o.id]),e=>e.code==='PT409');
    const preview=await request(shipment(o,'/preview'),fields,'operator');
    assert.equal((await request(shipment(o),{quote_id:preview.body.quote_id},'operator')).status,409);
    const bad=receipt(p);bad.data.amount++;
    assert.equal((await request('/payments/webhook',bad)).status,400);
    assert.equal((await db.query('select count(*)::int as n from delivery_payment_receipts')).rows[0].n,0);
    const good=receipt(p);
    env.PAYOS_ENABLED='false';
    assert.equal((await request('/payments/webhook',good)).body.status,'PAID');
    assert.equal((await request('/payments/webhook',good)).body.duplicate,true);
    env.PAYOS_ENABLED='true';
    assert.equal((await request(payment(o),{})).status,409);
    assert.equal((await db.query('select count(*)::int as n from delivery_payment_receipts')).rows[0].n,1);
    await db.query("update delivery_cloud_orders set status='cancelled' where id=$1",[o.id]);
    assert.equal((await db.query('select payment_status from delivery_cloud_orders where id=$1',[o.id])).rows[0].payment_status,'REVIEW');
    assert.equal((await request(payment(o))).body.payment.status,'REVIEW');
  });
  await t.test('uncertain creation recovers same code, provider cancellation and expiry release locks',async()=>{
    const o=await order();paymentTimeout=true;
    const result=await request(payment(o),{});paymentTimeout=false;
    assert.equal(result.status,200);assert.equal(result.body.payment.status,'PENDING');
    assert.equal((await request(payment(o,'/cancel'),{})).body.payment.status,'CANCELLED');
    await db.query("update delivery_cloud_orders set status='cancelled' where id=$1",[o.id]);
    const other=await order();const p=(await request(payment(other),{})).body.payment;
    paymentLinks.get(Number(p.provider_order_code)).status='EXPIRED';
    assert.equal((await request(payment(other,'/refresh'),{})).body.payment.status,'EXPIRED');
    assert.notEqual((await request(payment(other),{})).body.payment.id,p.id);
  });
  await t.test('receipt mismatches require review and signed provider reconciliation records real transfers',async()=>{
    const o=await order();const p=(await request(payment(o),{})).body.payment;
    assert.equal((await request('/payments/webhook',receipt(p,{currency:'USD'}))).status,400);
    assert.equal((await request('/payments/webhook',receipt(p,{paymentLinkId:'different-link'}))).status,409);
    assert.equal((await request('/payments/webhook',receipt(p,{amount:p.amount+1}))).body.status,'REVIEW');
    assert.equal((await request(payment(o,'/cancel'),{})).status,409);
    const next=await order();const intent=(await request(payment(next),{})).body.payment;
    Object.assign(paymentLinks.get(Number(intent.provider_order_code)),{status:'PAID',amountPaid:intent.amount,
      transactions:[{amount:intent.amount,reference:'provider-bank-reference'}]});
    assert.equal((await request(payment(next,'/refresh'),{})).body.payment.status,'PAID');
    assert.equal((await request(payment(next,'/refresh'),{})).body.payment.status,'PAID');
    assert.equal((await db.query("select count(*)::int as n from delivery_payment_receipts where reference='provider-bank-reference'")).rows[0].n,1);
    const sample=signed({code:'00',currency:'VND',orderCode:9999999,amount:1000,paymentLinkId:'sample',reference:'sample'});
    assert.equal((await request('/payments/webhook',sample)).body.accepted,false);
  });
  await t.test('GHN quotes expire and bind provider configuration and order version',async()=>{
    const o=await order();const preview=await request(shipment(o,'/preview'),fields,'operator');
    assert.equal(preview.status,200);
    assert.equal(ghnCalls.at(-1).body.cod_amount,120000);assert.equal(ghnCalls.at(-1).body.weight,1000);
    await db.query("update delivery_ghn_quotes set expires_at=now()-interval '1 second' where id=$1",[preview.body.quote_id]);
    assert.equal((await request(shipment(o),{quote_id:preview.body.quote_id},'operator')).status,409);
    const quote=(await request(shipment(o,'/preview'),fields,'operator')).body;
    env.GHN_SHOP_ID='456';assert.equal((await request(shipment(o),{quote_id:quote.quote_id},'operator')).status,409);env.GHN_SHOP_ID='123';
    await db.query('update delivery_cloud_orders set version=version+1 where id=$1',[o.id]);
    assert.equal((await request(shipment(o),{quote_id:quote.quote_id},'operator')).status,409);
  });
  await t.test('GHN retries use durable payload, callback rereads provider, duplicate/stale events are safe',async()=>{
    const o=await order();const quote=(await request(shipment(o,'/preview'),fields,'operator')).body;
    ghnTimeout=true;
    assert.equal((await request(shipment(o),{quote_id:quote.quote_id},'operator')).status,502);
    ghnTimeout=false;
    await assert.rejects(db.query("update delivery_cloud_orders set merchant_ready=true where id=$1",[o.id]),e=>e.code==='PT409');
    const result=await request(shipment(o),{cod_amount:1},'operator');
    assert.equal(result.status,200);const s=result.body.shipment;
    const creates=ghnCalls.filter(c=>c.path.endsWith('/create')).slice(-2);
    assert.deepEqual(creates[0].body,creates[1].body);
    assert.equal(s.status,'ready_to_pick');
    const callback={ShopID:123,OrderCode:s.ghn_order_code,ClientOrderCode:s.client_order_code,Type:'Switch_status',Time:'2026-10-28T10:00:00Z',Status:'delivered'};
    assert.equal((await request('/webhooks/ghn',callback)).status,401);
    const headers={'x-ghn-webhook-secret':env.GHN_WEBHOOK_SECRET};
    env.GHN_ENABLED='false';
    assert.equal((await request('/webhooks/ghn',callback,'owner',headers)).status,200);
    env.GHN_ENABLED='true';
    assert.equal((await request('/webhooks/ghn',callback,'owner',headers)).body.duplicate,true);
    assert.equal((await request(shipment(o))).body.shipment.status,'ready_to_pick');
    Object.assign(carrierDetails.get(s.ghn_order_code),{status:'delivered',updated_date:'2026-10-29T10:00:00Z'});
    assert.equal((await request(shipment(o,'/refresh'),{})).body.shipment.status,'delivered');
    assert.equal((await db.query('select status from delivery_cloud_orders where id=$1',[o.id])).rows[0].status,'delivered');
    Object.assign(carrierDetails.get(s.ghn_order_code),{status:'picking',updated_date:'2026-10-28T11:00:00Z'});
    assert.equal((await request(shipment(o,'/refresh'),{})).body.shipment.status,'delivered');
    cancelAllowed=false;
    assert.equal((await request(shipment(o,'/cancel'),{},'operator')).status,409);
    const history=await db.query("select action from delivery_cloud_history where order_id=$1 order by version",[o.id]);
    assert.deepEqual(history.rows.map(h=>h.action),['ghn_reserve','ghn_sync','ghn_sync']);
    assert.ok(integrationUsage().providers.some(p=>p.provider==='ghn' && p.requests>0));
  });
  await t.test('commerce tables and sequence cannot be accessed through public Supabase roles',async()=>{
    const ready=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    assert.ok(Object.values(ready).every(value=>value===true));
    for(const role of ['anon','authenticated']) {
      await db.exec(`set role ${role}`);
      for(const table of ['delivery_payment_transactions','delivery_payment_receipts','delivery_ghn_quotes','delivery_ghn_shipments','delivery_ghn_events']) {
        await assert.rejects(db.query(`select * from public.${table}`),/permission denied/);
      }
      await assert.rejects(db.query("select nextval('public.delivery_payment_transactions_provider_order_code_seq')"),/permission denied/);
      await db.exec('reset role');
    }
    const sql=await readFile(new URL('../../database/migrations/20261029_payments_ghn.sql',import.meta.url),'utf8');
    await db.exec(sql);
    await db.exec(await readFile(new URL('../../database/migrations/20261112_shipping_cash_settlement.sql',import.meta.url),'utf8'));
    assert.ok((await db.query('select count(*)::int as n from delivery_payment_receipts')).rows[0].n>0);
  });
  await t.test('driver collect_cash settles shipping fee and COD atomically, blocks double collection & emits notifications',async()=>{
    assert.equal(resolvePayosRedirectUrl('PAYOS_RETURN_URL', { PUBLIC_BASE_URL: 'https://ghst-backend-admin.onrender.com' }),
      'https://ghst-backend-admin.onrender.com/#/cloud');
    assert.equal(resolvePayosRedirectUrl('PAYOS_RETURN_URL', {
      PUBLIC_BASE_URL: 'https://ghst-backend-admin.onrender.com',
      PAYOS_RETURN_URL: 'https://app.example.com/#/done',
    }), 'https://app.example.com/#/done');

    await db.query("insert into delivery_cloud_memberships(user_id,role,state) values($1,'driver','active') on conflict(user_id,role) do update set state='active'",
      [ids.driver]);

    const asRole = async (userId, sql, args = []) => {
      await db.exec('reset role');
      await db.query("select set_config('request.jwt.claim.sub',$1,false)", [userId]);
      await db.exec('set role authenticated');
      try { return await db.query(sql, args); }
      finally { await db.exec('reset role'); }
    };
    const transition = async (actorId, orderId, action, version, reason = '') =>
      (await asRole(actorId, 'select public.delivery_cloud_transition($1,$2,$3,$4,$5) as data',
        [orderId, action, version, randomUUID(), reason])).rows[0].data;

    const createRealOrder = async (extraDetails = {}) => {
      const payload = {
        ...details,
        pickup_lat: 10.77,
        pickup_lng: 106.7,
        dropoff_lat: 10.78,
        dropoff_lng: 106.71,
        service_type: 'standard',
        cod_amount: 120000,
        ...extraDetails,
      };
      const quote = (await asRole(ids.owner, 'select public.delivery_cloud_quote($1) as data', [payload])).rows[0].data;
      return (await asRole(ids.owner, 'select public.delivery_cloud_create($1,$2,$3,$4) as data',
        [payload, randomUUID(), quote.pricing_version, quote.payable_fee ?? quote.shipping_fee])).rows[0].data;
    };

    // 1. Online payOS order with COD: online payment emits payment_paid; driver collect_cash collects COD only, never double-collecting fee
    const onlineCod = await createRealOrder({ cod_amount: 120000, payment_method: 'sender_cash' });
    const p = (await request(payment(onlineCod), {})).body.payment;
    await assert.rejects(transition(ids.driver, onlineCod.id, 'collect_cash', onlineCod.version), e => e.code === 'PT404' || e.code === 'PT403');
    assert.equal((await request('/payments/webhook', receipt(p))).body.status, 'PAID');
    const paidNotif = await db.query("select count(*)::int as n from delivery_user_notifications where user_id=$1 and kind='payment_paid' and reference_id=$2",
      [ids.owner, onlineCod.id]);
    assert.equal(paidNotif.rows[0].n, 1);

    let claimed = await transition(ids.driver, onlineCod.id, 'claim', onlineCod.version);
    claimed = await transition(ids.driver, onlineCod.id, 'arrive', claimed.version);
    claimed = await transition(ids.driver, onlineCod.id, 'pickup', claimed.version);
    await assert.rejects(db.query('update delivery_cloud_orders set cash_collected_fee=1000,cash_collected_at=now(),cash_collected_by=$1 where id=$2',
      [ids.driver, onlineCod.id]), e => e.code === 'PT409');
    claimed = await transition(ids.driver, onlineCod.id, 'collect_cash', claimed.version, 'Thu hộ tiền mặt COD');
    assert.equal(claimed.cash_collected_fee, 0);
    assert.equal(claimed.cash_collected_cod, 120000);
    assert.equal(claimed.payment_status, 'PAID');
    claimed = await transition(ids.driver, onlineCod.id, 'deliver', claimed.version);
    assert.equal(claimed.status, 'delivered');

    // 2. Pure cash order with coin discount (cod_amount = 50000): collect_cash settles payable_fee at arrivingPickup and COD at delivered
    await db.query('insert into delivery_market_coin_wallets(user_id,balance) values($1,500) on conflict(user_id) do update set balance=500', [ids.owner]);
    const cashOrder = await createRealOrder({ cod_amount: 50000, payment_method: 'sender_cash', use_coins: true });
    assert.ok(cashOrder.coin_discount > 0);
    assert.equal(cashOrder.payable_fee, cashOrder.shipping_fee - cashOrder.coin_discount);
    let step = await transition(ids.driver, cashOrder.id, 'claim', cashOrder.version);
    await assert.rejects(transition(ids.owner, cashOrder.id, 'collect_cash', step.version), e => e.code === 'PT403');
    await assert.rejects(transition(ids.driver, cashOrder.id, 'collect_cash', step.version), e => e.code === 'PT409');
    step = await transition(ids.driver, cashOrder.id, 'arrive', step.version);
    step = await transition(ids.driver, cashOrder.id, 'collect_cash', step.version);
    assert.equal(step.cash_collected_fee, cashOrder.payable_fee);
    assert.equal(step.cash_collected_cod, 0);
    assert.equal(step.payment_status, 'PAID');
    step = await transition(ids.driver, cashOrder.id, 'pickup', step.version);
    step = await transition(ids.driver, cashOrder.id, 'deliver', step.version);
    step = await transition(ids.driver, cashOrder.id, 'collect_cash', step.version);
    assert.equal(step.cash_collected_fee, cashOrder.payable_fee);
    assert.equal(step.cash_collected_cod, 50000);
    await assert.rejects(transition(ids.driver, cashOrder.id, 'collect_cash', step.version), e => e.code === 'PT409');

    const cashNotifs = await db.query("select count(*)::int as n from delivery_user_notifications where user_id=$1 and kind='cash_collected' and reference_id=$2",
      [ids.owner, cashOrder.id]);
    assert.equal(cashNotifs.rows[0].n, 2);
  });
  await t.test('Readiness catalog detects disabled guards, public data access and insufficient backend privileges',async()=>{
    await db.exec('alter table delivery_cloud_orders disable trigger delivery_commerce_guard');
    assert.equal((await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0].commerce_guard,false);
    await db.exec('alter table delivery_cloud_orders enable trigger delivery_commerce_guard; grant select on delivery_payment_receipts to anon');
    assert.equal((await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0].commerce_privacy,false);
    await db.exec('revoke select on delivery_payment_receipts from anon; alter table delivery_ghn_events disable row level security');
    assert.equal((await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0].commerce_privacy,false);
    await db.exec('alter table delivery_ghn_events enable row level security; create role catalog_reader; set role catalog_reader');
    assert.equal((await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0].commerce_permissions,false);
    await db.exec('reset role');
  });
});
