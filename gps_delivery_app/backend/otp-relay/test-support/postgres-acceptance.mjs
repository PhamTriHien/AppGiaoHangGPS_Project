import assert from 'node:assert/strict';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import pg from 'pg';
import { startNativePostgres } from './native-postgres.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from '../deployment-readiness.mjs';
import { testConfiguredCatalog } from './configured-catalog-acceptance.mjs';
import { testCommercialSuite } from './commercial-suite-acceptance.mjs';

const startedAt=Date.now();
const cluster=await startNativePostgres();
const db=cluster.client();const pool=new pg.Pool({...cluster.settings,max:24});
const results=[];
async function check(name,fn){const start=Date.now();await fn();results.push({name,status:'passed',durationMs:Date.now()-start});console.log(`PASS ${name}`);}
async function authenticatedQuery(user,sql,args=[]){
  const client=await pool.connect();
  try{
    await client.query('begin');await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claim.sub',$1,true)",[user]);
    const response=await client.query(sql,args);
    await client.query('commit');return response;
  }catch(error){await client.query('rollback');throw error;}finally{client.release();}
}
const as=async(user,name,args=[])=>(await authenticatedQuery(user,`select public.${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) data`,args)).rows[0].data;
const rpc=(id,action,payload={})=>as(id,'delivery_marketplace',[action,payload]);
try{
  await db.connect();
  await db.query(`create role authenticated;create role anon;create schema auth;create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
    create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;create publication supabase_realtime;`);
  await check('P0 latest additive migrations and catalog privacy',async()=>{
    for(const file of ['20261027_delivery_integrations','20261028_cloud_orders','20261029_payments_ghn','20261029_cloud_addresses',
      '20261030_marketplace','20261031_market_operations','20261101_partner_memberships','20261102_local_address_import','20261103_catalog_stock_versions','20261104_market_media','20261105_market_browse','20261106_catalog_configuration','20261107_cloud_commercial_suite']) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`,import.meta.url),'utf8'));
    }
    const schema=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for(const [key,value] of Object.entries(schema))assert.equal(value,true,`schema ${key}`);
  });
  const operator=randomUUID(),merchant=randomUUID(),driver=randomUUID(),secondDriver=randomUUID();
  const buyers=Array.from({length:8},()=>randomUUID());
  for(const id of [operator,merchant,driver,secondDriver,...buyers]){
    await db.query('insert into auth.users values($1)',[id]);
    await as(id,'delivery_cloud_profile',[{full_name:'Isolated PostgreSQL test',phone:'0901234567',requested_role:'customer'}]);
  }
  await db.query("insert into delivery_api_profiles values($1,'operator')",[operator]);
  for(const [id,role] of [[merchant,'merchant'],[driver,'driver'],[secondDriver,'driver']]){
    await as(id,'delivery_cloud_membership',[role,'request']);
    await as(operator,'delivery_cloud_membership',[role,'approve',id,1,'']);
  }
  const shop=(await rpc(merchant,'shop_save',{name:'Isolated stock shop',description:'',address:'12 Nguyen Hue TP HCM',latitude:10.77,longitude:106.7,paused:false})).shop;
  const product=(await rpc(merchant,'product_save',{id:randomUUID(),shop_id:shop.id,name:'Stock race item',description:'',category:'Food',sku:'RACE-1',price:50000,stock:2,weight_kg:1,published:true})).product;
  await rpc(operator,'shop_moderate',{id:shop.id,version:1,status:'active'});
  const quotes=[];
  for(const buyer of buyers){
    const address=(await as(buyer,'delivery_cloud_addresses_manage',[randomUUID(),{label:'Home',recipient_name:'Recipient',recipient_phone:'0912345678',
      full_address:'20 Le Loi TP HCM',latitude:10.78,longitude:106.71,is_default:true},false,null])).addresses[0];
    await rpc(buyer,'cart_set',{product_id:product.id,quantity:1,version:1});
    quotes.push((await rpc(buyer,'quote',{address_id:address.id})).quote);
  }
  let winner,order;
  await check('P1-P2 eight concurrent buyers cannot oversell two units',async()=>{
    const submitted=await Promise.allSettled(buyers.map((b,i)=>rpc(b,'checkout',{quote_id:quotes[i].id,request_key:randomUUID()})));
    const succeeded=submitted.filter(r=>r.status==='fulfilled'),rejected=submitted.filter(r=>r.status==='rejected');
    assert.equal(succeeded.length,2);assert.equal(rejected.length,6);
    assert.ok(rejected.every(r=>r.reason.code==='PT409'),rejected.map(r=>r.reason.code).join(','));
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[product.id])).rows[0].stock,0);
    assert.equal((await db.query('select count(*)::int n from delivery_market_purchases')).rows[0].n,2);
    winner=buyers[submitted.findIndex(r=>r.status==='fulfilled')];
    order=(await rpc(winner,'orders')).orders[0];
  });
  await check('P2 parallel checkout replay returns one purchase and one stock allocation',async()=>{
    const quote=quotes[buyers.indexOf(winner)],key=randomUUID();
    const replay=await Promise.all(Array.from({length:6},()=>rpc(winner,'checkout',{quote_id:quote.id,request_key:key})));
    assert.equal(new Set(replay.map(r=>r.purchase.id)).size,1);
    assert.equal((await db.query("select count(*)::int n from delivery_market_stock where reason='purchase_allocate'")).rows[0].n,2);
  });
  await check('P1-P2 price changes and hidden products invalidate quotes without allocating stock',async()=>{
    const buyer=buyers[7];
    const address=(await as(buyer,'delivery_cloud_addresses_manage')).addresses[0];
    await db.query('update delivery_market_products set stock=10,version=version+1 where id=$1',[product.id]);
    const quote=(await rpc(buyer,'quote',{address_id:address.id})).quote;
    await db.query('update delivery_market_products set price=price+1000,version=version+1 where id=$1',[product.id]);
    await assert.rejects(rpc(buyer,'checkout',{quote_id:quote.id,request_key:randomUUID()}),e=>e.code==='PT409');
    const next=(await rpc(buyer,'quote',{address_id:address.id})).quote;
    await db.query('update delivery_market_products set published=false,version=version+1 where id=$1',[product.id]);
    await assert.rejects(rpc(buyer,'checkout',{quote_id:next.id,request_key:randomUUID()}),e=>e.code==='PT409');
    const state=(await db.query('select stock,terms_version from delivery_market_products where id=$1',[product.id])).rows[0];
    assert.equal(state.stock,10);assert.equal(state.terms_version,3);
    assert.equal((await db.query('select count(*)::int n from delivery_market_purchases')).rows[0].n,2);
  });
  await check('P1 reserved product media enforces real Storage RLS, ownership, blocking and immutable writes',async()=>{
    const hash='b'.repeat(64);
    const reserved=await as(merchant,'delivery_market_media_reserve',[shop.id,hash,200]);
    assert.equal((await as(merchant,'delivery_market_media_reserve',[shop.id,hash,200])).name,reserved.name);
    await assert.rejects(as(merchant,'delivery_market_media_reserve',[shop.id,hash,201]),e=>e.code==='PT409');
    await assert.rejects(as(buyers[0],'delivery_market_media_reserve',[shop.id,hash,200]),e=>e.code==='PT403');
    await assert.rejects(authenticatedQuery(merchant,'select * from delivery_market_media'),e=>e.code==='42501');
    await assert.rejects(authenticatedQuery(buyers[0],'insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket,reserved.name]),e=>e.code==='42501');
    await assert.rejects(authenticatedQuery(merchant,'insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket,reserved.name+'forged']),e=>e.code==='42501');
    await authenticatedQuery(merchant,'insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket,reserved.name]);
    await assert.rejects(authenticatedQuery(merchant,'update storage.objects set name=$1 where name=$2',['changed',reserved.name]),e=>e.code==='42501');
    await db.query('update delivery_cloud_accounts set blocked=true where user_id=$1',[merchant]);
    assert.equal(await as(merchant,'delivery_market_media_can_upload',[reserved.name]),false);
    await assert.rejects(as(merchant,'delivery_market_media_reserve',[shop.id,'c'.repeat(64),200]),e=>e.code==='PT403');
    await db.query('update delivery_cloud_accounts set blocked=false where user_id=$1',[merchant]);
  });
  await check('P1-P2 server filters, tied-price pagination and public shop projection',async()=>{
    for(let i=0;i<55;i++)await rpc(merchant,'product_save',{id:randomUUID(),shop_id:shop.id,name:`Browse ${i}`,description:'',
      category:i%2?'A':'B',sku:`BROWSE-${i}`,price:1000+(i%3)*1000,stock:i%4===0?0:1,weight_kg:1,published:true});
    const browse=d=>as(buyers[0],'delivery_market_browse',[d]);
    const first=await browse({sort:'price_asc'}),second=await browse({sort:'price_asc',...first.next});
    const all=[...first.products,...second.products];
    assert.equal(first.products.length,50);assert.equal(second.products.length,5);assert.equal(second.next,null);
    assert.equal(new Set(all.map(p=>p.id)).size,55);
    assert.deepEqual(all.map(p=>p.price),all.map(p=>p.price).sort((a,b)=>a-b));
    assert.ok(all.every(p=>!('sort_value' in p)));assert.deepEqual(first.categories,['A','B']);
    const filtered=await browse({shop_id:shop.id,category:'A',min_price:2000,max_price:3000,in_stock:true,sort:'price_desc'});
    assert.ok(filtered.products.length>0);assert.ok(filtered.products.every(p=>p.category==='A'&&p.stock>0&&p.price>=2000&&p.price<=3000));
    assert.deepEqual(Object.keys(filtered.shop).sort(),['address','description','id','name','open','opening_schedule','paused']);
    for(const d of [{min_price:-1},{max_price:1.5},{min_price:3000,max_price:1000},{in_stock:'true'},{sort:'random'},{after:randomUUID()},{owner_id:merchant}]){
      await assert.rejects(browse(d),e=>e.code==='PT400');
    }
    await assert.rejects(authenticatedQuery(buyers[0],"set local role anon; select public.delivery_market_browse('{}')"),e=>e.code==='42501');
    await db.query('update delivery_market_shops set paused=true where id=$1',[shop.id]);
    const paused=await browse({shop_id:shop.id});assert.equal(paused.products.length,0);assert.equal(paused.shop.paused,true);
    await db.query('update delivery_market_shops set paused=false where id=$1',[shop.id]);
  });
  await check('P0 partner revoke racing a new trip never strands an unauthorized assignment',async()=>{
    let ready=(await rpc(merchant,'order_action',{order_id:order.id,version:order.version,action:'accept'})).order;
    ready=(await rpc(merchant,'order_action',{order_id:order.id,version:ready.version,action:'ready'})).order;
    order=ready;
    const shipping=(await as(winner,'delivery_cloud_list')).orders.find(o=>o.id===ready.delivery_id);
    const raced=await Promise.allSettled([
      as(driver,'delivery_cloud_transition',[shipping.id,'claim',shipping.version,randomUUID(),'']),
      as(operator,'delivery_cloud_membership',['driver','revoke',driver,2,'Operational review']),
    ]);
    assert.equal(raced.filter(r=>r.status==='fulfilled').length,1);
    assert.ok(raced.filter(r=>r.status==='rejected').every(r=>['PT409','PT404'].includes(r.reason.code)));
    const assigned=(await db.query('select driver_id from delivery_cloud_orders where id=$1',[shipping.id])).rows[0].driver_id;
    const active=(await db.query("select state='active' as active from delivery_cloud_memberships where user_id=$1 and role='driver'",[driver])).rows[0].active;
    if(assigned)assert.equal(active,true);else assert.equal(active,false);
  });
  await check('P4 competing drivers commit exactly one claim',async()=>{
    let shipping=(await as(winner,'delivery_cloud_list')).orders.find(o=>o.id===order.delivery_id);
    if(shipping.driver_id){
      for(const action of ['arrive','pickup','deliver']) {
        shipping=await as(driver,'delivery_cloud_transition',[shipping.id,action,shipping.version,randomUUID(),'']);
      }
    }
    const state=(await as(driver,'delivery_cloud_profile')).account.memberships.find(m=>m.role==='driver');
    if(state.state!=='active'){
      await as(driver,'delivery_cloud_membership',['driver','request']);
      const pending=(await as(driver,'delivery_cloud_profile')).account.memberships.find(m=>m.role==='driver');
      await as(operator,'delivery_cloud_membership',['driver','approve',driver,pending.version,'']);
    }
    // Use a fresh isolated shipment instead of resetting a committed status.
    const details={pickup_address:'12 Nguyen Hue',dropoff_address:'20 Le Loi',recipient_name:'Recipient',recipient_phone:'0912345678',package_description:'Claim race',
      pickup_lat:10.77,pickup_lng:106.7,dropoff_lat:10.78,dropoff_lng:106.71,weight_kg:1,cod_amount:0,service_type:'standard',payment_method:'recipient_cash'};
    const quote=await as(winner,'delivery_cloud_quote',[details]);
    const fresh=await as(winner,'delivery_cloud_create',[details,randomUUID(),quote.pricing_version,quote.shipping_fee]);
    const claims=await Promise.allSettled([driver,secondDriver].map(id=>as(id,'delivery_cloud_transition',[fresh.id,'claim',fresh.version,randomUUID(),''])));
    assert.equal(claims.filter(r=>r.status==='fulfilled').length,1);
    assert.ok(claims.filter(r=>r.status==='rejected').every(r=>['PT409','PT404'].includes(r.reason.code)));
  });
  await check('P0 concurrent address imports deduplicate without cross-account ownership',async()=>{
    const payload=[{source_key:'a'.repeat(64),details:{label:'Imported',recipient_name:'Recipient',recipient_phone:'0912345678',full_address:'99 Le Loi TP HCM',latitude:10.78,longitude:106.71}}];
    const imported=await Promise.all(Array.from({length:4},()=>as(buyers[7],'delivery_cloud_import',['commit',JSON.stringify(payload)])));
    assert.equal(imported.reduce((sum,r)=>sum+r.ready,0),1);
    const owner=(await db.query('select user_id from delivery_cloud_imports where source_key=$1',['a'.repeat(64)])).rows;
    assert.equal(owner.length,1);assert.equal(owner[0].user_id,buyers[7]);
  });
  await testConfiguredCatalog({db,as,rpc,operator,merchant,buyer:buyers[7],shop,check});
  await testCommercialSuite({db,as,rpc,operator,merchant,driver,secondDriver,buyers,shop,check,authenticatedQuery});
  const output=path.resolve(import.meta.dirname,'../../../build/verification/postgres-acceptance.json');
  await mkdir(path.dirname(output),{recursive:true});
  await writeFile(output,JSON.stringify({environment:'disposable-loopback-postgresql',checkedAt:new Date().toISOString(),durationMs:Date.now()-startedAt,results},null,2));
  console.log('PostgreSQL acceptance complete. No cloud writes or provider transactions.');
}finally{
  await pool.end();await db.end();await cluster.stop();
}
