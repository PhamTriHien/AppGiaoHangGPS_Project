import assert from 'node:assert/strict';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import pg from 'pg';
import { startNativePostgres } from './native-postgres.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from '../deployment-readiness.mjs';
import { testConfiguredCatalog } from './configured-catalog-acceptance.mjs';
import { testCommercialSuite } from './commercial-suite-acceptance.mjs';
import { testCloudLogistics } from './cloud-logistics-acceptance.mjs';

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
      '20261030_marketplace','20261031_market_operations','20261101_partner_memberships','20261102_local_address_import','20261103_catalog_stock_versions','20261104_market_media','20261105_market_browse','20261106_catalog_configuration','20261107_cloud_commercial_suite','20261108_cloud_logistics','20261109_admin_account_management','20261110_cloud_promo_events','20261111_profile_push_shipping_coins','20261112_shipping_cash_settlement','20261113_cloud_sync_and_journey','20261114_merchant_cloud_suite']) {
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
  await testCloudLogistics({db,as,operator,merchant,driver,buyers,check});
  await check('P7 cloud preferences, AI history, enriched queue privacy, live GPS/chat/checkpoints and driver reviews',async()=>{
    for(const file of ['20261109_admin_account_management','20261110_cloud_promo_events','20261111_profile_push_shipping_coins','20261112_shipping_cash_settlement','20261113_cloud_sync_and_journey','20261114_merchant_cloud_suite']) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`,import.meta.url),'utf8'));
    }
    const schemaAfterReapply=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for(const [key,value] of Object.entries(schemaAfterReapply))assert.equal(value,true,`reapplied schema ${key}`);
    const customer=buyers[0],journeyDriver=randomUUID();
    await db.query('insert into auth.users values($1)',[journeyDriver]);
    await as(journeyDriver,'delivery_cloud_profile',[{full_name:'Tai Xe Hanh Trinh',phone:'0908887776',requested_role:'customer'}]);
    await as(journeyDriver,'delivery_cloud_membership',['driver','request']);
    await as(operator,'delivery_cloud_membership',['driver','approve',journeyDriver,1,'']);
    const savedUi=await as(customer,'delivery_cloud_preferences',['save_ui',{theme_mode:'dark',preferred_role:'customer'}]);
    assert.deepEqual(savedUi.ui_preferences,{theme_mode:'dark',preferred_role:'customer'});
    await as(customer,'delivery_cloud_preferences',['save_draft',{draft:{pickup_address:'12 Nguyen Hue, Ben Nghe, Quan 1, TP HCM',dropoff_address:'20 Le Loi, Ben Thanh, Quan 1, TP HCM',service_type:'express'}}]);
    const prof=await as(customer,'delivery_cloud_profile');
    assert.equal(prof.account.ui_preferences.theme_mode,'dark');
    assert.equal(prof.account.shipping_draft.service_type,'express');
    const adminAcc=(await as(operator,'delivery_cloud_accounts_manage')).accounts.find(a=>a.user_id===customer);
    assert.equal(adminAcc.shipping_draft,undefined);

    await as(customer,'delivery_cloud_ai_history',['append_exchange',{user_text:'Tra cuu don hang',assistant_text:'Ban co the xem muc Don hang.'}]);
    const aiHist=await as(customer,'delivery_cloud_ai_history',['list',{}]);
    assert.equal(aiHist.messages.length,2);
    assert.equal(aiHist.messages[0].role,'user');
    assert.equal(aiHist.messages[1].role,'assistant');
    await as(customer,'delivery_cloud_ai_history',['clear',{}]);
    assert.equal((await as(customer,'delivery_cloud_ai_history',['list',{}])).messages.length,0);

    const tripDetails={
      pickup_address:'12 Nguyen Hue, Phuong Ben Nghe, Quan 1, TP HCM',
      dropoff_address:'20 Le Loi, Phuong Ben Thanh, Quan 1, TP HCM',
      recipient_name:'Khach Hang A',
      recipient_phone:'0912345678',
      package_description:'Tai lieu khan',
      pickup_lat:10.77312,pickup_lng:106.70425,
      dropoff_lat:10.77195,dropoff_lng:106.69831,
      extra_stops:[{address:'45 Ham Nghi, Quan 1, TP HCM',lat:10.7708,lng:106.7019,contact_name:'Diem dung 1',contact_phone:'0909111222'}],
      is_round_trip:true,
      prefer_ev:true,
      require_pod:false,
      require_otp:false,
      weight_kg:2,cod_amount:50000,service_type:'express',payment_method:'recipient_cash',
    };
    const tripQuote=await as(customer,'delivery_cloud_quote',[tripDetails]);
    const created=await as(customer,'delivery_cloud_create',[tripDetails,randomUUID(),tripQuote.pricing_version,tripQuote.shipping_fee]);
    assert.equal((await as(customer,'delivery_cloud_preferences',['get',{}])).shipping_draft,null);

    const queue=(await as(journeyDriver,'delivery_cloud_list',[true,null,null])).orders;
    const queued=queue.find(o=>o.id===created.id);
    assert.ok(queued);
    assert.equal(JSON.stringify(queued).includes('0912345678'),false);
    assert.equal(JSON.stringify(queued).includes('Nguyen Hue'),false);
    assert.equal(queued.details.pickup_area,'Quan 1, TP HCM');
    assert.equal(queued.details.stops_count,1);
    assert.equal(queued.details.is_round_trip,true);
    assert.equal(queued.details.prefer_ev,true);

    let claimed=await as(journeyDriver,'delivery_cloud_transition',[created.id,'claim',created.version,randomUUID(),'']);
    claimed=await as(journeyDriver,'delivery_cloud_transition',[created.id,'arrive',claimed.version,randomUUID(),'']);
    claimed=await as(journeyDriver,'delivery_cloud_transition',[created.id,'pickup',claimed.version,randomUUID(),'']);

    const t0=Date.now();
    const gpsOk=await as(journeyDriver,'delivery_cloud_order_live',['push_gps',{order_id:created.id,latitude:10.77312,longitude:106.70425,heading:180,speed_kmh:32,timestamp_ms:t0}]);
    assert.equal(gpsOk.ok,true);
    await assert.rejects(
      as(journeyDriver,'delivery_cloud_order_live',['push_gps',{order_id:created.id,latitude:10.95,longitude:106.95,timestamp_ms:t0+1000}]),
      e=>e.code==='PT409'
    );
    await as(customer,'delivery_cloud_order_live',['send_chat',{order_id:created.id,text:'Goi cho minh khi toi cong nhe'}]);
    await as(journeyDriver,'delivery_cloud_order_live',['send_chat',{order_id:created.id,text:'Da nhan thong tin, minh dang di'}]);
    const cp=await as(journeyDriver,'delivery_cloud_order_live',['mark_checkpoint',{order_id:created.id,checkpoint_key:'stop:0',note:'Da giao diem dung 1'}]);
    assert.equal(cp.order.completed_checkpoints.length,1);

    const snap=await as(customer,'delivery_cloud_order_live',['snapshot',{order_id:created.id}]);
    assert.equal(snap.messages.length,2);
    assert.equal(snap.gps_trail.length,1);
    assert.equal(snap.order.driver_profile.user_id,journeyDriver);
    assert.equal(snap.order.sender_profile.phone,'0901234567');

    let done=await as(journeyDriver,'delivery_cloud_transition',[created.id,'collect_cash',cp.order.version,randomUUID(),'']);
    done=await as(journeyDriver,'delivery_cloud_transition',[created.id,'deliver',done.version,randomUUID(),'Da giao tan tay']);
    const revRes=await as(customer,'delivery_market_operations',['partner_review_save',{target_kind:'driver',cloud_order_id:done.id,rating:5,body:'Tai xe giao cuc nhanh va lich su'}]);
    assert.equal(revRes.partner_review.rating,5);
    const driverRevs=await as(journeyDriver,'delivery_cloud_logistics',['driver_reviews',{}]);
    assert.ok(driverRevs.rating_count>=1);
    assert.ok(driverRevs.reviews.some(r=>r.id===revRes.partner_review.id));
    await as(journeyDriver,'delivery_market_operations',['review_reply',{review_kind:'partner',id:revRes.partner_review.id,reply:'Cam on anh chi rat nhieu!'}]);
    const finalOrder=(await as(customer,'delivery_cloud_list',[false,null,null])).orders.find(o=>o.id===done.id);
    assert.equal(finalOrder.driver_review.rating,5);
    assert.equal(finalOrder.driver_review.reply,'Cam on anh chi rat nhieu!');
  });
  await check('P8 merchant cloud suite RBAC, quick storefront/catalog controls, stock ledger, promotions, settlement math and delegated staff live journey',async()=>{
    const managerUser=randomUUID(),staffUser=randomUUID(),outsiderUser=randomUUID(),suiteDriver=randomUUID(),suiteBuyer=randomUUID();
    for(const [uid,name,phone] of [
      [managerUser,'Quan Ly Shop','0931112233'],
      [staffUser,'Nhan Vien Shop','0934445566'],
      [outsiderUser,'Nguoi Ngoai','0937778899'],
      [suiteDriver,'Tai Xe Suite','0939998877'],
      [suiteBuyer,'Nguoi Mua Suite','0912345678'],
    ]){
      await db.query('insert into auth.users values($1)',[uid]);
      await as(uid,'delivery_cloud_profile',[{full_name:name,phone,requested_role:'customer'}]);
    }
    await as(suiteBuyer,'delivery_cloud_addresses_manage',[randomUUID(),{
      label:'Nha Rieng',recipient_name:'Nguoi Mua Suite',recipient_phone:'0912345678',
      full_address:'20 Le Loi TP HCM',latitude:10.78,longitude:106.71,is_default:true,
    },false,null]);
    await as(suiteDriver,'delivery_cloud_membership',['driver','request']);
    await as(operator,'delivery_cloud_membership',['driver','approve',suiteDriver,1,'']);

    await rpc(merchant,'staff_save',{shop_id:shop.id,phone:'0931112233',role:'manager',active:true});
    await rpc(merchant,'staff_save',{shop_id:shop.id,phone:'0934445566',role:'staff',active:true});

    await assert.rejects(as(outsiderUser,'delivery_merchant_suite',['dashboard',{}]),e=>e.code==='PT403');
    const ownerDash=await as(merchant,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    assert.equal(ownerDash.my_role,'owner');
    assert.ok(ownerDash.kpis.finance!==null);
    const managerDash=await as(managerUser,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    assert.equal(managerDash.my_role,'manager');
    assert.ok(managerDash.kpis.finance!==null);
    const staffDash=await as(staffUser,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    assert.equal(staffDash.my_role,'staff');
    assert.equal(staffDash.kpis.finance,null);

    await assert.rejects(
      as(staffUser,'delivery_merchant_suite',['shop_quick_pause',{shop_id:shop.id,paused:true,version:ownerDash.shops[0].version}]),
      e=>e.code==='PT403'
    );
    const pausedShop=(await as(managerUser,'delivery_merchant_suite',['shop_quick_pause',{shop_id:shop.id,paused:true,version:ownerDash.shops[0].version}])).shop;
    assert.equal(pausedShop.paused,true);
    assert.equal(pausedShop.status,'active');
    const resumedShop=(await as(managerUser,'delivery_merchant_suite',['shop_quick_pause',{shop_id:shop.id,paused:false,version:pausedShop.version}])).shop;
    assert.equal(resumedShop.paused,false);
    assert.equal(resumedShop.status,'active');

    const suiteProd=(await rpc(managerUser,'product_save',{
      id:randomUUID(),shop_id:shop.id,name:'Ca Phe Hat Rang Moc',description:'100% Arabica',
      category:'Do uong',sku:'CF-SUITE-1',price:120000,stock:5,weight_kg:0.5,published:true,
    })).product;
    await assert.rejects(
      as(staffUser,'delivery_merchant_suite',['product_quick_update',{product_id:suiteProd.id,version:suiteProd.version,stock:20}]),
      e=>e.code==='PT403'
    );
    const updatedProd=(await as(managerUser,'delivery_merchant_suite',['product_quick_update',{product_id:suiteProd.id,version:suiteProd.version,stock:18,published:true}])).product;
    assert.equal(updatedProd.stock,18);
    const stockLedger=await as(managerUser,'delivery_merchant_suite',['stock_ledger',{shop_id:shop.id,product_id:suiteProd.id}]);
    assert.ok(stockLedger.entries.some(e=>e.reason==='merchant_quick_adjust' && e.delta===13));
    await assert.rejects(as(staffUser,'delivery_merchant_suite',['stock_ledger',{shop_id:shop.id}]),e=>e.code==='PT403');

    const starts=new Date(Date.now()-60_000).toISOString();
    const ends=new Date(Date.now()+86_400_000).toISOString();
    const shopVoucher=(await rpc(managerUser,'voucher_save',{
      shop_id:shop.id,code:'MERCHSUITE10',title:'Giam 10k tai shop',discount_kind:'fixed',
      discount_value:10000,max_discount:10000,min_subtotal:50000,budget_total:500000,per_user_limit:2,
      starts_at:starts,ends_at:ends,active:true,
    })).voucher;
    await db.query(
      `insert into delivery_market_vouchers(id,code,shop_id,owner_user_id,title,discount_kind,discount_value,max_discount,min_subtotal,budget_total,per_user_limit,starts_at,ends_at,active,created_by)
       values($1,'PERSONALONLY',$2,$3,'Voucher ca nhan','fixed',5000,5000,0,5000,1,$4,$5,true,$3)`,
      [randomUUID(),shop.id,suiteBuyer,starts,ends]
    );
    const shopFlash=(await rpc(managerUser,'flash_sale_save',{
      product_id:suiteProd.id,sale_price:99000,allocated_stock:5,per_user_limit:2,starts_at:starts,ends_at:ends,active:true,
    })).flash_sale;
    const promos=await as(managerUser,'delivery_merchant_suite',['promotions',{shop_id:shop.id}]);
    assert.ok(promos.vouchers.some(v=>v.id===shopVoucher.id));
    assert.equal(promos.vouchers.some(v=>v.code==='PERSONALONLY'),false);
    assert.ok(promos.flash_sales.some(f=>f.id===shopFlash.id && f.product_name==='Ca Phe Hat Rang Moc'));

    const cartSnap=await rpc(suiteBuyer,'cart');
    await rpc(suiteBuyer,'cart_set',{product_id:suiteProd.id,quantity:1,version:cartSnap.version});
    const addrList=(await as(suiteBuyer,'delivery_cloud_addresses_manage')).addresses;
    const suiteQuote=(await rpc(suiteBuyer,'quote',{address_id:addrList[0].id})).quote;
    const suiteCheckout=await rpc(suiteBuyer,'checkout',{quote_id:suiteQuote.id,request_key:randomUUID()});
    assert.ok(suiteCheckout.purchase.id);

    const staffOrders=await as(staffUser,'delivery_merchant_suite',['orders_list',{shop_id:shop.id,filter:'pending'}]);
    const queuedOrder=staffOrders.orders.find(o=>o.purchase_id===suiteCheckout.purchase.id);
    assert.ok(queuedOrder);
    const suiteOrderId=queuedOrder.id;
    assert.equal(queuedOrder.buyer_profile.phone,'0912345678');

    const acceptedOrder=(await rpc(staffUser,'order_action',{order_id:suiteOrderId,action:'accept',version:queuedOrder.version})).order;
    const readyOrder=(await rpc(staffUser,'order_action',{order_id:suiteOrderId,action:'ready',version:acceptedOrder.version})).order;
    assert.ok(readyOrder.delivery_id);

    const staffLiveSnap=await as(staffUser,'delivery_cloud_order_live',['snapshot',{order_id:readyOrder.delivery_id}]);
    assert.equal(staffLiveSnap.order.id,readyOrder.delivery_id);
    const staffHist=await as(staffUser,'delivery_cloud_history_read',[readyOrder.delivery_id]);
    assert.ok(staffHist.history.length>=1);
    const staffMsg=await as(staffUser,'delivery_cloud_order_live',['send_chat',{order_id:readyOrder.delivery_id,text:'Shop da dong goi xong kien hang'}]);
    assert.equal(staffMsg.message.sender_role,'merchant');
    await assert.rejects(
      as(staffUser,'delivery_cloud_order_live',['push_gps',{order_id:readyOrder.delivery_id,latitude:10.77,longitude:106.7}]),
      e=>e.code==='PT403'
    );

    let deliv=await as(suiteDriver,'delivery_cloud_transition',[readyOrder.delivery_id,'claim',1,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'arrive',deliv.version,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'pickup',deliv.version,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'collect_cash',deliv.version,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'deliver',deliv.version,randomUUID(),'Giao thanh cong']);

    await as(suiteBuyer,'delivery_market_operations',['review_save',{order_id:suiteOrderId,product_id:suiteProd.id,rating:5,body:'Hat thom va dong goi ky'}]);
    const staffReviews=await as(staffUser,'delivery_merchant_suite',['aftersales_inbox',{shop_id:shop.id,tab:'reviews',filter:'unreplied'}]);
    const prodRev=staffReviews.reviews.find(r=>r.product_id===suiteProd.id);
    assert.ok(prodRev);
    await as(staffUser,'delivery_market_operations',['review_reply',{review_kind:'product',id:prodRev.id,reply:'Cam on quy khach da ung ho shop!'}]);
    await assert.rejects(
      as(staffUser,'delivery_merchant_suite',['aftersales_inbox',{shop_id:shop.id,tab:'finance'}]),
      e=>e.code==='PT403'
    );

    const dueAmount=Number(readyOrder.snapshot.payable_subtotal??readyOrder.snapshot.subtotal)+Number(readyOrder.snapshot.shipping_fee);
    const colReq=(await as(suiteDriver,'delivery_market_operations',['finance_request',{
      order_id:suiteOrderId,kind:'collection',amount:dueAmount,reason:'Nop COD du',evidence:'COD-SUITE-1',request_key:randomUUID(),
    }])).finance;
    await as(operator,'delivery_market_operations',['finance_action',{id:colReq.id,action:'approve',version:colReq.version,reason:'Duyet thu COD'}]);
    await as(operator,'delivery_market_operations',['finance_action',{id:colReq.id,action:'complete',version:colReq.version+1,evidence:'BANK-COD-1'}]);
    await db.query("update delivery_market_shop_orders set delivered_at=now()-interval '8 days' where id=$1",[suiteOrderId]);

    const settleDash=await as(managerUser,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    const eligibleRow=settleDash.kpis.finance.eligible_orders.find(e=>e.order_id===suiteOrderId);
    assert.ok(eligibleRow && eligibleRow.eligible_amount>0);
    const settleReq=(await as(managerUser,'delivery_market_operations',['finance_request',{
      order_id:suiteOrderId,kind:'settlement',amount:eligibleRow.eligible_amount,reason:'De nghi quyet toan ky nay',evidence:'SETTLE-SUITE-1',request_key:randomUUID(),
    }])).finance;
    assert.equal(settleReq.amount,eligibleRow.eligible_amount);
    const financeInbox=await as(managerUser,'delivery_merchant_suite',['aftersales_inbox',{shop_id:shop.id,tab:'finance',filter:'settlement'}]);
    assert.ok(financeInbox.finance.some(f=>f.id===settleReq.id));
  });
  const output=path.resolve(import.meta.dirname,'../../../build/verification/postgres-acceptance.json');
  await mkdir(path.dirname(output),{recursive:true});
  await writeFile(output,JSON.stringify({environment:'disposable-loopback-postgresql',checkedAt:new Date().toISOString(),durationMs:Date.now()-startedAt,results},null,2));
  console.log('PostgreSQL acceptance complete. No cloud writes or provider transactions.');
}finally{
  await pool.end();await db.end();await cluster.stop();
}
