import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';

test('Independent partner memberships preserve buyer rights and enforce each approval at fixed RPCs', async t => {
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
  const migrations = ['20261027_delivery_integrations','20261028_cloud_orders','20261029_payments_ghn',
    '20261029_cloud_addresses','20261030_marketplace','20261031_market_operations','20261101_partner_memberships'];
  for (const name of migrations) await db.exec(await readFile(new URL(`../../database/migrations/${name}.sql`, import.meta.url),'utf8'));
  const ids = Object.fromEntries(['buyer','partner','other','operator'].map(n => [n,randomUUID()]));
  for (const id of Object.values(ids)) await db.query('insert into auth.users values($1)',[id]);
  await db.query("insert into delivery_api_profiles values($1,'operator')",[ids.operator]);
  const as = async name => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]]);
    await db.exec('set role authenticated');
  };
  const rpc = async (name,args=[]) => (await db.query(`select public.${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) data`,args)).rows[0].data;
  const member = (role,decision,user=null,version=null,reason='') => rpc('delivery_cloud_membership',[role,decision,user,version,reason]);
  const market = (action,payload={}) => rpc('delivery_marketplace',[action,payload]);
  const details={pickup_address:'12 Nguyen Hue TP HCM',dropoff_address:'20 Le Loi TP HCM',recipient_name:'Recipient',
    recipient_phone:'0912345678',package_description:'Goods',pickup_lat:10.77,pickup_lng:106.7,dropoff_lat:10.78,dropoff_lng:106.71,
    weight_kg:1,cod_amount:50000,service_type:'standard',payment_method:'recipient_cash'};
  for (const name of Object.keys(ids)) {
    await as(name);
    await rpc('delivery_cloud_profile',[{full_name:name,phone:'0901234567',requested_role:'customer'}]);
  }
  let shop,product,delivery;
  await t.test('Requests are independent, idempotent and never self-approve; direct tables and internal helpers are private',async()=>{
    await as('partner');
    assert.equal((await member('merchant','request')).membership.state,'pending');
    assert.equal((await member('merchant','request')).membership.version,1);
    await member('driver','request');
    const profile=await rpc('delivery_cloud_profile');
    assert.equal(profile.schema_version,3);
    assert.deepEqual(profile.account.approved_roles,[]);
    assert.deepEqual(profile.account.memberships.map(m=>m.role),['driver','merchant']);
    await assert.rejects(member('merchant','approve',ids.partner,1),/quản trị/);
    await assert.rejects(member('merchant','request',ids.other),/chính mình/);
    await assert.rejects(db.exec('select * from delivery_cloud_memberships'),/permission denied/);
    await assert.rejects(rpc('delivery_cloud_has_membership',[ids.other,'merchant']),/permission denied/);
    await assert.rejects(rpc('delivery_cloud_account_snapshot',[ids.other]),/permission denied/);
    await assert.rejects(rpc('delivery_cloud_profile',[{full_name:'Forged',phone:'0901234567',role:'merchant'}]),/không hợp lệ/);
    await assert.rejects(market('workspace'),/đã được duyệt/);
    await assert.rejects(rpc('delivery_cloud_list',[true]),/tài xế/);
  });
  await t.test('Operator grants both roles with optimistic versions; basic buying remains independent',async()=>{
    await as('operator');
    await member('merchant','approve',ids.partner,1);
    await assert.rejects(member('merchant','approve',ids.partner,1),/thay đổi/);
    await member('driver','approve',ids.partner,1);
    await as('partner');
    const profile=await rpc('delivery_cloud_profile');
    assert.deepEqual(profile.account.approved_roles,['driver','merchant']);
    assert.equal(profile.operator,false);
    assert.equal((await market('cart')).items.length,0);
    shop=(await market('shop_save',{name:'Partner shop',description:'',address:'12 Nguyen Hue TP HCM',latitude:10.77,longitude:106.7,paused:false})).shop;
    product=(await market('product_save',{id:randomUUID(),shop_id:shop.id,name:'Product',description:'',category:'Food',sku:'P1',price:50000,stock:5,weight_kg:1,published:true})).product;
    assert.equal((await rpc('delivery_cloud_list',[true])).orders.length,0);
    await as('operator');
    await market('shop_moderate',{id:shop.id,version:1,status:'active'});
    // Primary display role switches without deleting the other server approval.
    await rpc('delivery_cloud_accounts_manage',[ids.partner,'driver',false]);
    await as('partner');
    assert.equal((await market('workspace')).shops.length,1);
    await as('buyer');
    assert.equal((await market('catalog')).products.length,1);
    assert.equal((await rpc('delivery_market_operations',['product_details',{product_id:product.id}])).product.id,product.id);
    const q=await rpc('delivery_cloud_quote',[details]);
    delivery=await rpc('delivery_cloud_create',[details,randomUUID(),q.pricing_version,q.shipping_fee]);
  });
  await t.test('Driver claims/updates are membership-gated; revoke cannot strand an active trip',async()=>{
    await as('partner');
    const queue=(await rpc('delivery_cloud_list',[true])).orders;
    assert.ok(queue.some(o=>o.id===delivery.id));
    delivery=await rpc('delivery_cloud_transition',[delivery.id,'claim',delivery.version,randomUUID(),'']);
    await as('operator');
    await assert.rejects(member('driver','revoke',ids.partner,2,'Operational review'),/chuyến chưa hoàn tất/);
    await as('partner');
    for(const action of ['arrive','pickup','deliver']) delivery=await rpc('delivery_cloud_transition',[delivery.id,action,delivery.version,randomUUID(),'']);
    await as('operator');
    await member('driver','revoke',ids.partner,2,'Operational review');
    await as('partner');
    assert.deepEqual((await rpc('delivery_cloud_profile')).account.approved_roles,['merchant']);
    assert.equal((await market('workspace')).shops.length,1);
    await assert.rejects(rpc('delivery_cloud_list',[true]),/tài xế/);
    // Reapplying never resurrects a revoked grant.
    await db.exec('reset role');
    await db.exec(await readFile(new URL('../../database/migrations/20261101_partner_memberships.sql',import.meta.url),'utf8'));
    await as('partner');
    assert.deepEqual((await rpc('delivery_cloud_profile')).account.approved_roles,['merchant']);
  });
  await t.test('Rejection, reapplication, separate revoke and blocking retain an audited history',async()=>{
    await member('driver','request');
    await as('operator');
    await assert.rejects(member('driver','reject',ids.partner,4,''),/lý do/);
    await member('driver','reject',ids.partner,4,'Missing documents');
    await member('merchant','revoke',ids.partner,2,'Shop closed');
    await as('partner');
    await assert.rejects(market('workspace'),/đã được duyệt/);
    assert.equal((await market('cart')).items.length,0);
    await as('buyer');
    assert.equal((await market('catalog')).products.length,0);
    await as('operator');
    const account=(await rpc('delivery_cloud_accounts_manage')).accounts.find(a=>a.user_id===ids.partner);
    assert.deepEqual(account.approved_roles,[]);
    assert.equal(account.memberships.find(m=>m.role==='driver').reason,'Missing documents');
    await rpc('delivery_cloud_accounts_manage',[ids.partner,'customer',true]);
    await as('partner');
    await assert.rejects(member('driver','request'),/đang khóa/);
    await assert.rejects(rpc('delivery_cloud_profile',[{full_name:'Blocked',phone:'0901234567',requested_role:'customer'}]),/đang khóa/);
    await assert.rejects(market('cart'),/đang hoạt động/);
    await assert.rejects(rpc('delivery_cloud_accounts_manage'),/quản trị/);
    await db.exec('reset role');
    const audit=await db.query("select count(*)::int n from delivery_cloud_admin_audit where action like 'membership_%'");
    assert.ok(audit.rows[0].n>=8);
  });

  await t.test('Operator account governance RPC manages incomplete Auth accounts, profile edits, direct grants and self-lockout guards',async()=>{
    await db.exec('reset role');
    for (const extra of ['20261102_local_address_import','20261103_catalog_stock_versions','20261104_market_media',
      '20261105_market_browse','20261106_catalog_configuration','20261107_cloud_commercial_suite','20261108_cloud_logistics','20261109_admin_account_management','20261110_cloud_promo_events']) {
      await db.exec(await readFile(new URL(`../../database/migrations/${extra}.sql`,import.meta.url),'utf8'));
    }
    const incompleteId=randomUUID();
    await db.query('insert into auth.users values($1)',[incompleteId]);
    const adminAcc=(action,payload={})=>rpc('delivery_cloud_admin_accounts',[action,payload]);

    await as('buyer');
    await assert.rejects(adminAcc('list'),/quản trị/);
    await assert.rejects(member('driver','grant',ids.other,0,'Illegal grant'),/quản trị/);

    await as('operator');
    const listed=await adminAcc('list');
    assert.equal(listed.summary.total_accounts,5);
    assert.equal(listed.summary.incomplete_profiles,1);
    assert.equal(listed.summary.operators,1);
    assert.equal(listed.accounts.find(a=>a.user_id===incompleteId).has_profile,false);

    // Initialize incomplete Auth profile and fix full_name/phone
    const initialized=await adminAcc('update_profile',{user_id:incompleteId,full_name:'Tài khoản Hoàn thiện',phone:'0987654321',reason:'Bổ sung hồ sơ'});
    assert.equal(initialized.account.has_profile,true);
    assert.equal(initialized.account.full_name,'Tài khoản Hoàn thiện');

    // Direct partner grant without user pre-request (version=0 -> 1)
    const granted=await member('driver','grant',incompleteId,0,'Cấp trực tiếp tài xế');
    assert.equal(granted.membership.state,'active');
    assert.equal(granted.membership.version,1);
    await assert.rejects(member('driver','grant',incompleteId,0,'Stale version'),/thay đổi/);

    // Self-lockout & self-demotion protection
    await assert.rejects(adminAcc('set_blocked',{user_id:ids.operator,blocked:true,reason:'Self lock'}),/tự khóa/);
    await assert.rejects(adminAcc('set_operator',{user_id:ids.operator,operator:false,reason:'Self demote'}),/tự thu hồi/);

    // Grant & revoke secondary operator with audit trail
    const opGranted=await adminAcc('set_operator',{user_id:incompleteId,operator:true,reason:'Bổ nhiệm điều hành ca đêm'});
    assert.equal(opGranted.account.is_operator,true);
    const opRevoked=await adminAcc('set_operator',{user_id:incompleteId,operator:false,reason:'Kết thúc ca trực'});
    assert.equal(opRevoked.account.is_operator,false);

    // Detail returns shops and targeted audit entries
    const detail=await adminAcc('detail',{user_id:incompleteId});
    assert.ok(detail.audit.some(e=>e.action==='account_profile'));
    assert.ok(detail.audit.some(e=>e.action==='membership_grant'));
    assert.ok(detail.audit.some(e=>e.action==='operator_grant'));
    assert.ok(detail.audit.some(e=>e.action==='operator_revoke'));
  });
});
