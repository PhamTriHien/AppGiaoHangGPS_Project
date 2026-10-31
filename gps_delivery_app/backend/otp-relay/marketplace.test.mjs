import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

test('Marketplace catalog, ownership, cart, atomic multi-shop checkout, fulfillment and chat', async t => {
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
  for (const name of ['20261027_delivery_integrations','20261028_cloud_orders','20261029_payments_ghn','20261029_cloud_addresses','20261030_marketplace']) {
    await db.exec(await readFile(new URL(`../../database/migrations/${name}.sql`, import.meta.url),'utf8'));
  }
  const ids = Object.fromEntries(['buyer','other','merchant','second','operator','driver'].map(k=>[k,randomUUID()]));
  for (const id of Object.values(ids)) await db.query('insert into auth.users values($1)',[id]);
  await db.query("insert into delivery_api_profiles values($1,'operator')",[ids.operator]);
  const as = async name => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]]);
    await db.exec('set role authenticated');
  };
  const rpc = async (name,args=[]) => (await db.query(`select public.${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) as data`,args)).rows[0].data;
  const call = (name,body={}) => rpc('delivery_marketplace',[name,body]);
  for (const name of Object.keys(ids)) {
    await as(name);
    await rpc('delivery_cloud_profile',[{full_name:name,phone:'0901234567',requested_role:'customer'}]);
  }
  await as('operator');
  for (const name of ['merchant','second','driver']) await rpc('delivery_cloud_accounts_manage',[ids[name],name==='driver'?'driver':'merchant',false]);
  const shops={},products={};
  for (const [index,name] of ['merchant','second'].entries()) {
    await as(name);
    shops[name]=(await call('shop_save',{name:`Shop ${name}`,description:'',address:'12 Nguyen Hue TP HCM',latitude:10.77,longitude:106.7,paused:false})).shop;
    products[name]=(await call('product_save',{id:randomUUID(),shop_id:shops[name].id,name:`Product ${name}`,description:'Real item',category:'Food',sku:`SKU-${index}`,price:50000+index*10000,stock:5,weight_kg:1,published:true})).product;
  }
  await t.test('Pending shops are invisible; only operator approves, and raw tables/helpers are private', async()=>{
    await as('buyer');
    assert.equal((await call('catalog')).products.length,0);
    await assert.rejects(call('shop_moderate',{id:shops.merchant.id,version:1,status:'active'}),/quản trị/);
    await assert.rejects(call('workspace'),/đã được duyệt/);
    for (const table of ['shops','products','stock','carts','cart_items','quotes','purchases','shop_orders','events','messages','notifications']) {
      await assert.rejects(db.exec(`select * from delivery_market_${table}`),/permission denied/);
    }
    await assert.rejects(rpc('delivery_market_snapshot',[randomUUID()]),/permission denied/);
    await db.exec('reset role');
    await db.query('delete from delivery_cloud_accounts where user_id=$1',[ids.operator]);
    await as('operator');
    assert.equal((await call('workspace',{moderation:true})).shops.length,2);
    for (const name of ['merchant','second']) shops[name]=(await call('shop_moderate',{id:shops[name].id,version:1,status:'active'})).shop;
    await rpc('delivery_cloud_profile',[{full_name:'operator',phone:'0901234567',requested_role:'customer'}]);
    await as('buyer');
    assert.equal((await call('catalog')).products.length,2);
    assert.equal((await call('catalog',{search:'second'})).products.length,1);
    assert.equal((await call('catalog',{search:'%'})).products.length,0);
  });
  await t.test('Merchant cannot edit another shop or forge ownership; stale and fractional writes fail',async()=>{
    await as('merchant');
    const foreign={...products.second,stock:99};delete foreign.updated_at;
    await assert.rejects(call('product_save',foreign),/quyền sửa/);
    await assert.rejects(call('shop_save',{name:'Attack',address:'123 Other',latitude:0,longitude:0,paused:false,owner_id:ids.second}),/không hợp lệ/);
    const payload={...products.merchant};delete payload.updated_at;
    await assert.rejects(call('product_save',{...payload,price:1.5}),/số nguyên/);
    await assert.rejects(call('product_save',{...payload,version:99}),/đã thay đổi/);
    await assert.rejects(call('cart_set',{product_id:payload.id,quantity:1,version:1}),/không thể mua/);
  });
  let address;
  await as('buyer');
  address=(await rpc('delivery_cloud_addresses_manage',[randomUUID(),{label:'Home',recipient_name:'Buyer',recipient_phone:'0912345678',full_address:'20 Le Loi TP HCM',latitude:10.78,longitude:106.71,is_default:true},false,null])).addresses[0];
  let cart=(await call('cart'));
  for (const name of ['merchant','second']) cart=await call('cart_set',{product_id:products[name].id,quantity:2,version:cart.version});
  let quote=(await call('quote',{address_id:address.id})).quote;
  await t.test('Cross-account cart and quote ownership; no forged price/payment in checkout',async()=>{
    await as('other');
    assert.equal((await call('cart')).items.length,0);
    await assert.rejects(call('quote',{address_id:address.id}),/địa chỉ/);
    await assert.rejects(call('checkout',{quote_id:quote.id,request_key:randomUUID()}),/báo giá/);
    await as('buyer');
    await assert.rejects(call('checkout',{quote_id:quote.id,request_key:randomUUID(),total:1,payment_status:'PAID'}),/không hợp lệ/);
    await assert.rejects(call('cart_set',{product_id:products.merchant.id,quantity:1,version:1}),/thiết bị khác/);
  });
  await t.test('Price changes reject the entire checkout without stock allocation; expired quote also fails',async()=>{
    await as('merchant');
    const payload={...products.merchant,price:51000};delete payload.updated_at;
    products.merchant=(await call('product_save',payload)).product;
    await as('buyer');
    await assert.rejects(call('checkout',{quote_id:quote.id,request_key:randomUUID()}),/đã thay đổi/);
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int as n from delivery_market_purchases')).rows[0].n,0);
    assert.ok((await db.query('select stock from delivery_market_products')).rows.every(p=>p.stock===5));
    await db.query("update delivery_market_quotes set expires_at=now()-interval '1 second' where id=$1",[quote.id]);
    await as('buyer');
    await assert.rejects(call('checkout',{quote_id:quote.id,request_key:randomUUID()}),/hết hạn/);
    quote=(await call('quote',{address_id:address.id})).quote;
  });
  let purchase,orders;
  await t.test('Two shops commit atomically with immutable prices, allocated stock and restart-safe replay',async()=>{
    const key=randomUUID();
    purchase=(await call('checkout',{quote_id:quote.id,request_key:key})).purchase;
    assert.equal(purchase.total,quote.snapshot.total);
    assert.equal(purchase.payment_status,'UNPAID');
    assert.equal((await call('checkout',{quote_id:quote.id,request_key:key})).purchase.id,purchase.id);
    assert.equal((await call('checkout',{quote_id:quote.id,request_key:randomUUID()})).purchase.id,purchase.id);
    orders=(await call('orders')).orders;
    assert.equal(orders.length,2);
    assert.equal((await call('cart')).items.length,0);
    await db.exec('reset role');
    assert.ok((await db.query('select stock from delivery_market_products')).rows.every(p=>p.stock===3));
    assert.equal((await db.query("select count(*)::int as n from delivery_market_stock where reason='purchase_allocate'")).rows[0].n,2);
    await as('other');
    assert.equal((await call('orders')).orders.length,0);
    await assert.rejects(call('order_action',{order_id:orders[0].id,version:1,action:'cancel',reason:'Attack'}),/Không tìm thấy/);
  });
  await t.test('Chat is order-bound, replay safe and notifications have no message body or customer address',async()=>{
    const order=orders.find(o=>o.merchant_id===ids.merchant), key=randomUUID();
    await as('buyer');
    await call('message_send',{order_id:order.id,body:'Please prepare carefully',request_key:key});
    assert.equal((await call('message_send',{order_id:order.id,body:'Please prepare carefully',request_key:key})).messages.length,1);
    await assert.rejects(call('message_send',{order_id:order.id,body:'Changed',request_key:key}),/đã được dùng/);
    await as('merchant');
    assert.equal((await call('orders',{workspace:'merchant'})).orders.length,1);
    assert.equal((await call('messages',{order_id:order.id})).messages.length,1);
    const notices=(await call('notifications')).notifications;
    assert.equal(notices.length,2);
    assert.ok(notices.every(n=>!Object.hasOwn(n,'body')&&!Object.hasOwn(n,'snapshot')));
    await call('notification_read',{id:notices[0].id});
    assert.ok((await call('notifications')).notifications.find(n=>n.id===notices[0].id).read_at);
    await as('other');
    await assert.rejects(call('messages',{order_id:order.id}),/Không tìm thấy/);
  });
  await t.test('Merchant ready creates exactly one linked internal shipment, not a paid purchase',async()=>{
    const order=orders.find(o=>o.merchant_id===ids.merchant);
    await as('buyer');
    await assert.rejects(call('order_action',{order_id:order.id,version:1,action:'accept'}),/Chỉ cửa hàng/);
    await as('merchant');
    let updated=(await call('order_action',{order_id:order.id,version:1,action:'accept'})).order;
    updated=(await call('order_action',{order_id:order.id,version:updated.version,action:'ready'})).order;
    assert.ok(updated.delivery_id);
    await assert.rejects(call('order_action',{order_id:order.id,version:updated.version,action:'ready'}),/trạng thái/);
    const shipping=(await rpc('delivery_cloud_list')).orders.find(o=>o.id===updated.delivery_id);
    assert.equal(shipping.cod_amount,102000);
    assert.equal(shipping.payment_status,'UNPAID');
    await as('driver');
    assert.ok((await rpc('delivery_cloud_list',[true])).orders.some(o=>o.id===updated.delivery_id));
    assert.equal((await call('cart')).items.length,0); // Approved partners retain basic buyer rights.
  });
  await t.test('Cancel restores only its allocated stock, exactly once; blocked accounts cannot read or write',async()=>{
    const order=orders.find(o=>o.merchant_id===ids.second);
    await as('buyer');
    await call('order_action',{order_id:order.id,version:1,action:'cancel',reason:'No longer needed'});
    await assert.rejects(call('order_action',{order_id:order.id,version:2,action:'cancel',reason:'Again'}),/trạng thái/);
    await db.exec('reset role');
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[products.second.id])).rows[0].stock,5);
    await as('operator');
    await rpc('delivery_cloud_accounts_manage',[ids.buyer,'customer',true]);
    await as('buyer');
    for (const action of ['catalog','cart','orders','notifications']) await assert.rejects(call(action),/đang hoạt động/);
  });
  await t.test('Shipping cancellation releases purchase stock atomically without marking money received',async()=>{
    await as('operator');
    await rpc('delivery_cloud_accounts_manage',[ids.buyer,'customer',false]);
    await as('buyer');
    const shipping=(await rpc('delivery_cloud_list')).orders[0];
    await rpc('delivery_cloud_transition',[shipping.id,'cancel',shipping.version,randomUUID(),'Recipient requested cancellation']);
    const updated=(await call('orders')).orders.find(o=>o.delivery_id===shipping.id);
    assert.equal(updated.state,'cancelled');assert.equal(updated.payment_status,'UNPAID');
    await db.exec('reset role');
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[products.merchant.id])).rows[0].stock,5);
    assert.equal((await db.query("select count(*)::int as n from delivery_market_stock where reason='shipping_cancel_release'")).rows[0].n,1);
  });
  await t.test('Unavailable second shop rolls back the complete checkout, preserving the cart and quote',async()=>{
    await as('buyer');
    let c=await call('cart');
    for(const name of ['merchant','second']) c=await call('cart_set',{product_id:products[name].id,quantity:1,version:c.version});
    const q=(await call('quote',{address_id:address.id})).quote;
    await db.exec(`reset role; create function test_stock_failure() returns trigger language plpgsql as $$begin
      if new.id='${products.second.id}' and new.stock<old.stock then raise exception 'injected inventory failure'; end if; return new; end$$;
      create trigger test_stock_failure before update on delivery_market_products for each row execute function test_stock_failure();`);
    await as('buyer');
    await assert.rejects(call('checkout',{quote_id:q.id,request_key:randomUUID()}),/inventory failure/);
    assert.equal((await call('cart')).items.length,2);
    await db.exec('reset role; drop trigger test_stock_failure on delivery_market_products; drop function test_stock_failure()');
    assert.equal((await db.query('select count(*)::int as n from delivery_market_purchases')).rows[0].n,1);
    assert.ok((await db.query('select stock from delivery_market_products')).rows.every(p=>p.stock===5));
    await as('buyer');
    const first=(await call('checkout',{quote_id:q.id,request_key:randomUUID()})).purchase;
    assert.ok(first.id);
  });
  await t.test('Carrier-origin cancellation has a system source rather than impersonating a user',async()=>{
    await as('merchant');
    let o=(await call('orders',{workspace:'merchant'})).orders.find(o=>o.state==='pending');
    o=(await call('order_action',{order_id:o.id,version:o.version,action:'accept'})).order;
    o=(await call('order_action',{order_id:o.id,version:o.version,action:'ready'})).order;
    await db.exec("reset role; select set_config('request.jwt.claim.sub','',false); set ghst.carrier_sync='on'");
    await db.query("update delivery_cloud_orders set status='cancelled',version=version+1 where id=$1",[o.delivery_id]);
    const entry=(await db.query("select actor_id,actor_source from delivery_market_stock where reference_id=$1 and reason='shipping_cancel_release'",[o.id])).rows[0];
    assert.equal(entry.actor_id,null);assert.equal(entry.actor_source,'carrier');
    assert.equal((await db.query('select state from delivery_market_shop_orders where id=$1',[o.id])).rows[0].state,'cancelled');
  });
  await t.test('Notification keyset pagination does not omit rows with tied timestamps',async()=>{
    await db.exec('reset role');
    const order=orders[0];
    for(let i=0;i<55;i++) await db.query("insert into delivery_market_notifications(user_id,order_id,kind,created_at) values($1,$2,'message','2026-10-29T00:00:00Z')",[ids.buyer,order.id]);
    await as('buyer');
    const first=await call('notifications');
    assert.ok(first.next);
    const second=await call('notifications',first.next);
    const noticeIds=[...first.notifications,...second.notifications].map(n=>n.id);
    assert.equal(new Set(noticeIds).size,noticeIds.length);
    await db.exec('reset role');
    assert.equal(noticeIds.length,(await db.query('select count(*)::int as n from delivery_market_notifications where user_id=$1',[order.owner_id])).rows[0].n);
  });
  await t.test('Reapplying preserves existing purchases and denies anonymous execution',async()=>{
    await db.exec('reset role');
    await db.exec(await readFile(new URL('../../database/migrations/20261030_marketplace.sql',import.meta.url),'utf8'));
    assert.equal((await db.query('select count(*)::int as n from delivery_market_purchases')).rows[0].n,2);
    await db.exec('set role anon');
    await assert.rejects(call('catalog'),/permission denied/);
  });
});
