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
      '20261030_marketplace','20261031_market_operations','20261101_partner_memberships','20261102_local_address_import','20261103_catalog_stock_versions','20261104_market_media','20261105_market_browse','20261106_catalog_configuration','20261107_cloud_commercial_suite','20261108_cloud_logistics','20261109_admin_account_management','20261110_cloud_promo_events','20261111_profile_push_shipping_coins','20261112_shipping_cash_settlement','20261113_cloud_sync_and_journey','20261114_merchant_cloud_suite','20261115_cross_role_linkage_complete']) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`,import.meta.url),'utf8'));
    }
    const schema=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for(const [key,value] of Object.entries(schema))assert.equal(value,true,`schema ${key}`);
  });
  const operator=randomUUID(),merchant=randomUUID(),driver=randomUUID(),secondDriver=randomUUID();
  const buyers=Array.from({length:8},()=>randomUUID());
  for(const [idx,id] of [operator,merchant,driver,secondDriver,...buyers].entries()){
    await db.query('insert into auth.users values($1)',[id]);
    await as(id,'delivery_cloud_profile',[{
      full_name:'Isolated PostgreSQL test',
      phone:'0901234567',
      birth_date:'1995-05-15',
      citizen_id:String(79095000001 + idx).padStart(12,'0'),
      requested_role:'customer',
    }]);
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
    for(const file of ['20261109_admin_account_management','20261110_cloud_promo_events','20261111_profile_push_shipping_coins','20261112_shipping_cash_settlement','20261113_cloud_sync_and_journey','20261114_merchant_cloud_suite','20261115_cross_role_linkage_complete']) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`,import.meta.url),'utf8'));
    }
    const schemaAfterReapply=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for(const [key,value] of Object.entries(schemaAfterReapply))assert.equal(value,true,`reapplied schema ${key}`);
    const customer=buyers[0],journeyDriver=randomUUID();
    await db.query('insert into auth.users values($1)',[journeyDriver]);
    await as(journeyDriver,'delivery_cloud_profile',[{full_name:'Tai Xe Hanh Trinh',phone:'0908887776',birth_date:'1994-04-10',citizen_id:'079094000777',requested_role:'customer'}]);
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
    for(const [idx,[uid,name,phone]] of [
      [managerUser,'Quan Ly Shop','0931112233'],
      [staffUser,'Nhan Vien Shop','0934445566'],
      [outsiderUser,'Nguoi Ngoai','0937778899'],
      [suiteDriver,'Tai Xe Suite','0939998877'],
      [suiteBuyer,'Nguoi Mua Suite','0912345678'],
    ].entries()){
      await db.query('insert into auth.users values($1)',[uid]);
      await as(uid,'delivery_cloud_profile',[{full_name:name,phone,birth_date:'1992-08-20',citizen_id:String(79092000801 + idx).padStart(12,'0'),requested_role:'customer'}]);
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
  await check('P9 end-to-end 14 cross-role linkage items (prepaid/COD sync, returned/mixed parcels, pre-delivery refund, split OTP, anti-self-dealing, multi-branch, driver wallet, reverse return guard, pickup lifecycle, release/reassign, dual-control, KYC/block guards, notifications & deep-links)',async()=>{
    await db.query('alter table auth.users add column if not exists email text');
    const ops=(id,action,data={})=>as(id,'delivery_market_operations',[action,data]);

    // Item 12: KYC guard on partner membership request/grant
    const unverifiedUser=randomUUID();
    await db.query('insert into auth.users(id,email) values($1,$2)',[unverifiedUser,'unverified@ghst.test']);
    await as(unverifiedUser,'delivery_cloud_profile',[{full_name:'Chua KYC',phone:'0941110001',requested_role:'customer'}]);
    await assert.rejects(as(unverifiedUser,'delivery_cloud_membership',['driver','request']),e=>e.code==='PT409');
    await assert.rejects(as(operator,'delivery_cloud_membership',['merchant','grant',unverifiedUser,0,'Cap thu']),e=>e.code==='PT409');

    // Create dedicated verified actors for P9
    const branchManager=randomUUID(),branchStaff=randomUUID(),driverA=randomUUID(),driverB=randomUUID(),selfDriverMerchant=randomUUID(),buyerP9=randomUUID(),operator2=randomUUID();
    for(const [idx,[uid,name,phone,email]] of [
      [branchManager,'Quan Ly Chi Nhanh 2','0942220001','manager2@ghst.test'],
      [branchStaff,'Nhan Vien Chi Nhanh 2','0942220002','staff2@ghst.test'],
      [driverA,'Tai Xe Lien Ket A','0942220003','drivera@ghst.test'],
      [driverB,'Tai Xe Lien Ket B','0942220004','driverb@ghst.test'],
      [selfDriverMerchant,'Chu Shop Kiem Tai Xe','0942220005','selfpartner@ghst.test'],
      [buyerP9,'Khach Hang P9','0942220006','buyerp9@ghst.test'],
      [operator2,'Operator Thu Hai','0942220007','op2@ghst.test'],
    ].entries()){
      await db.query('insert into auth.users(id,email) values($1,$2)',[uid,email]);
      await as(uid,'delivery_cloud_profile',[{
        full_name:name,phone,birth_date:'1991-06-15',
        citizen_id:String(79091000901+idx).padStart(12,'0'),
        requested_role:'customer',
      }]);
    }
    for(const dId of [driverA,driverB,selfDriverMerchant]){
      await as(dId,'delivery_cloud_membership',['driver','request']);
      await as(operator,'delivery_cloud_membership',['driver','approve',dId,1,'']);
    }
    await as(selfDriverMerchant,'delivery_cloud_membership',['merchant','request']);
    await as(operator,'delivery_cloud_membership',['merchant','approve',selfDriverMerchant,1,'']);

    const buyerAddr=(await as(buyerP9,'delivery_cloud_addresses_manage',[randomUUID(),{
      label:'Nha P9',recipient_name:'Khach Hang P9',recipient_phone:'0942220006',
      full_address:'88 Dong Khoi Q1 TP HCM',latitude:10.776,longitude:106.703,is_default:true,
    },false,null])).addresses[0];

    // Item 6 & 13: Multi-branch shop creation, email staff assignment & delegated manager shop edit without overwriting Branch 1 or resetting active status
    const branch2Pending=(await rpc(merchant,'shop_save',{
      name:'Chi Nhanh Thu Duc',description:'Chi nhanh 2',address:'50 Vo Van Ngan TP HCM',
      latitude:10.85,longitude:106.77,paused:false,service_radius_km:30,
    })).shop;
    assert.notEqual(branch2Pending.id,shop.id);
    assert.equal(branch2Pending.status,'pending');
    const opPendingNotif=(await db.query("select count(*)::int n from delivery_user_notifications where user_id=$1 and kind='shop_pending_review' and reference_id=$2",[operator,branch2Pending.id])).rows[0].n;
    assert.equal(opPendingNotif>=1,true);

    const branch2Active=(await rpc(operator,'shop_moderate',{id:branch2Pending.id,version:branch2Pending.version,status:'active'})).shop;
    assert.equal(branch2Active.status,'active');

    // Delegate manager & staff by email lookup on auth.users (only shop owner can manage staff)!
    await rpc(merchant,'staff_save',{shop_id:branch2Active.id,email:'MANAGER2@ghst.test',role:'manager',active:true});
    await assert.rejects(rpc(branchManager,'staff_save',{shop_id:branch2Active.id,email:'staff2@ghst.test',role:'staff',active:true}),e=>e.code==='PT403');
    await rpc(merchant,'staff_save',{shop_id:branch2Active.id,email:'staff2@ghst.test',role:'staff',active:true});
    const staffAssignNotif=(await db.query("select count(*)::int n from delivery_user_notifications where user_id=$1 and kind='shop_staff_assigned' and reference_id=$2",[branchStaff,branch2Active.id])).rows[0].n;
    assert.equal(staffAssignNotif,1);

    const branch2Edited=(await rpc(branchManager,'shop_save',{
      id:branch2Active.id,name:branch2Active.name,description:'Cap nhat mo ta boi Manager',
      address:branch2Active.address,latitude:branch2Active.latitude,longitude:branch2Active.longitude,
      paused:false,version:branch2Active.version,banner_url:'https://example.test/branch2.webp',service_radius_km:35,
    })).shop;
    assert.equal(branch2Edited.status,'active');
    assert.equal(branch2Edited.description,'Cap nhat mo ta boi Manager');
    const branch1Unchanged=(await db.query('select name,status from delivery_market_shops where id=$1',[shop.id])).rows[0];
    assert.equal(branch1Unchanged.name,'Isolated stock shop');
    assert.equal(branch1Unchanged.status,'active');

    const prodBranch2=(await rpc(branchManager,'product_save',{
      id:randomUUID(),shop_id:branch2Edited.id,name:'Tra O Long Cao Cap',description:'Hop qua',
      category:'Do uong',sku:'OLONG-P9',price:100000,stock:20,weight_kg:0.5,published:true,
    })).product;

    // Item 5: Anti-self-dealing (shop owner & delegated staff cannot cart_set own shop product; driver cannot claim own/delegated order)
    await assert.rejects(rpc(merchant,'cart_set',{product_id:prodBranch2.id,quantity:1,version:1}),e=>e.code==='PT409');
    await assert.rejects(rpc(branchStaff,'cart_set',{product_id:prodBranch2.id,quantity:1,version:1}),e=>e.code==='PT409');

    const selfShipDetails={
      pickup_address:'10 Hai Ba Trung Q1',dropoff_address:'20 Le Loi Q1',recipient_name:'Khach',
      recipient_phone:'0942220006',package_description:'Self deal test',pickup_lat:10.775,pickup_lng:106.704,
      dropoff_lat:10.772,dropoff_lng:106.698,weight_kg:1,cod_amount:0,service_type:'standard',payment_method:'sender_cash',
    };
    const selfQ=await as(selfDriverMerchant,'delivery_cloud_quote',[selfShipDetails]);
    let selfOrd=await as(selfDriverMerchant,'delivery_cloud_create',[selfShipDetails,randomUUID(),selfQ.pricing_version,selfQ.shipping_fee]);
    if(!selfOrd.merchant_ready){
      selfOrd=await as(selfDriverMerchant,'delivery_cloud_transition',[selfOrd.id,'ready',selfOrd.version,randomUUID(),'']);
    }
    const selfQueue=(await as(selfDriverMerchant,'delivery_cloud_list',[true,null,null])).orders;
    assert.equal(selfQueue.some(o=>o.id===selfOrd.id),false);
    await assert.rejects(as(selfDriverMerchant,'delivery_cloud_transition',[selfOrd.id,'claim',selfOrd.version,randomUUID(),'']),e=>e.code==='PT403');

    // Item 10, 11, 12 & 14: Delegated staff cloud_list/ready, manager cancel, release/reassign, active-driver block guard & delivery_cloud_get
    let standOrd=await as(driverA,'delivery_cloud_transition',[selfOrd.id,'claim',selfOrd.version,randomUUID(),'']);
    // Driver release returns order to searching
    standOrd=await as(driverA,'delivery_cloud_transition',[standOrd.id,'release',standOrd.version,randomUUID(),'Xe bi xep lop']);
    assert.equal(standOrd.status,'searching');
    assert.equal(standOrd.driver_id,null);
    // Re-claim by driverA, then Operator reassigns back to searching
    standOrd=await as(driverA,'delivery_cloud_transition',[standOrd.id,'claim',standOrd.version,randomUUID(),'']);
    standOrd=await as(operator,'delivery_cloud_transition',[standOrd.id,'reassign',standOrd.version,randomUUID(),'Dieu phoi sang tai xe gan hon']);
    assert.equal(standOrd.status,'searching');
    assert.equal(standOrd.driver_id,null);
    // Claim by driverB -> pickup -> inTransit -> test active-driver block guard (Item 12)
    standOrd=await as(driverB,'delivery_cloud_transition',[standOrd.id,'claim',standOrd.version,randomUUID(),'']);
    standOrd=await as(driverB,'delivery_cloud_transition',[standOrd.id,'arrive',standOrd.version,randomUUID(),'']);
    standOrd=await as(driverB,'delivery_cloud_transition',[standOrd.id,'pickup',standOrd.version,randomUUID(),'']);
    await assert.rejects(as(operator,'delivery_cloud_accounts_manage',[driverB,'driver',true]),e=>e.code==='PT409');
    await assert.rejects(as(operator,'delivery_cloud_admin_accounts',['set_blocked',{user_id:driverB,blocked:true,reason:'Khoa thu'}]),e=>e.code==='PT409');
    standOrd=await as(driverB,'delivery_cloud_transition',[standOrd.id,'collect_cash',standOrd.version,randomUUID(),'']);
    standOrd=await as(driverB,'delivery_cloud_transition',[standOrd.id,'deliver',standOrd.version,randomUUID(),'Hoan tat']);
    assert.equal(standOrd.status,'delivered');
    const singleFetched=await as(buyerP9,'delivery_cloud_get',[standOrd.id]).catch(e=>e.code);
    assert.equal(singleFetched,'PT404');
    const ownerFetched=await as(selfDriverMerchant,'delivery_cloud_get',[standOrd.id]);
    assert.equal(ownerFetched.id,standOrd.id);

    // Item 1 & 4: Multi-shop Prepaid checkout -> purchase_total in orders, PAID/sender_cash forward parcels & 6-digit OTP on split parcels
    const prodBranch1=(await rpc(merchant,'product_save',{
      id:randomUUID(),shop_id:shop.id,name:'Banh Quy Bo Phap',description:'Hop thiec',
      category:'Banh',sku:'BANH-P9',price:80000,stock:20,weight_kg:0.4,published:true,
    })).product;
    let c9=await rpc(buyerP9,'cart');
    c9=await rpc(buyerP9,'cart_set',{product_id:prodBranch1.id,quantity:1,version:c9.version});
    c9=await rpc(buyerP9,'cart_set',{product_id:prodBranch2.id,quantity:2,version:c9.version});
    const prepQuote=(await rpc(buyerP9,'quote',{
      address_id:buyerAddr.id,payment_method:'prepaid',require_otp:true,service_type:'standard',
    })).quote;
    const prepPurchase=(await rpc(buyerP9,'checkout',{quote_id:prepQuote.id,request_key:randomUUID()})).purchase;
    await db.query('select public.delivery_market_record_prepaid_capture($1,$2)',[prepPurchase.id,'PAYOS-P9-1']);

    const buyerOrders=(await rpc(buyerP9,'orders')).orders.filter(o=>o.purchase_id===prepPurchase.id);
    assert.equal(buyerOrders.length,2);
    assert.ok(buyerOrders.every(o=>Number(o.purchase_total)===Number(prepPurchase.total)));
    const b1Order=buyerOrders.find(o=>o.shop_id===shop.id);
    const b2Order=buyerOrders.find(o=>o.shop_id===branch2Edited.id);

    // Item 3: Pre-delivery cancel on b1Order (paid prepaid) -> full buyer refund request & balanced ledger reversal!
    await rpc(merchant,'order_action',{order_id:b1Order.id,version:b1Order.version,action:'cancel',reason:'Het bao bi hop thiec'});
    const b1Svc=await ops(buyerP9,'order_services',{order_id:b1Order.id});
    assert.equal(b1Svc.order.state,'cancelled');
    assert.ok(b1Svc.collected>0);
    const preDelivRef=(await ops(buyerP9,'finance_request',{
      order_id:b1Order.id,kind:'refund',amount:b1Svc.collected,
      reason:'Hoan tien do shop huy truoc giao',evidence:'REQ-REF-PRE-1',request_key:randomUUID(),
    })).finance;
    await ops(operator,'finance_action',{id:preDelivRef.id,action:'approve',version:preDelivRef.version,reason:'Duyet hoan tien toan bo'});
    await ops(operator,'finance_action',{id:preDelivRef.id,action:'complete',version:preDelivRef.version+1,evidence:'BANK-REF-PRE-1'});
    const unbalancedAfterRef=(await db.query('select journal_id,sum(amount)::bigint s from delivery_market_ledger group by journal_id having sum(amount)<>0')).rows;
    assert.equal(unbalancedAfterRef.length,0);
    const netB1Ledger=(await db.query('select account,sum(amount)::bigint net from delivery_market_ledger l join delivery_market_journals j on j.id=l.journal_id where j.order_id=$1 group by account having sum(amount)<>0',[b1Order.id])).rows;
    assert.equal(netB1Ledger.length,0);

    // Item 1, 2 & 4: b2Order accepted & split into 2 OTP parcels -> prepaid forward parcels have payment_status='PAID' & sender_cash; mixed 1 delivered + 1 cancelled finalizes delivered_at!
    let b2Cur=(await rpc(branchStaff,'order_action',{order_id:b2Order.id,version:b2Order.version,action:'accept'})).order;
    b2Cur=(await rpc(branchManager,'order_shipment_split',{
      order_id:b2Cur.id,version:b2Cur.version,
      parcels:[{weight_kg:0.5,cod_amount:0},{weight_kg:0.5,cod_amount:0}],
    })).order;
    const b2Parcels=(await db.query('select ms.parcel_index,co.* from delivery_market_shipments ms join delivery_cloud_orders co on co.id=ms.delivery_id where ms.order_id=$1 order by ms.parcel_index',[b2Cur.id])).rows;
    assert.equal(b2Parcels.length,2);
    for(const pRow of b2Parcels){
      assert.equal(pRow.payment_status,'PAID');
      assert.equal(pRow.details.payment_method,'sender_cash');
      const staffOtp=await as(branchStaff,'delivery_cloud_order_otp',[pRow.id]);
      const buyerOtp=await as(buyerP9,'delivery_cloud_order_otp',[pRow.id]);
      assert.equal(staffOtp.required,true);
      assert.match(buyerOtp.otp_code,/^[0-9]{6}$/);
      assert.equal(staffOtp.otp_code,buyerOtp.otp_code);
      await assert.rejects(as(driverA,'delivery_cloud_order_otp',[pRow.id]),e=>e.code==='PT403');
    }
    // Delegated staff sees split parcels in delivery_cloud_list(false); staff cannot cancel, manager can cancel parcel 2!
    const staffCloudList=(await as(branchStaff,'delivery_cloud_list',[false,null,null])).orders;
    assert.ok(staffCloudList.some(o=>o.id===b2Parcels[0].id));
    await assert.rejects(as(branchStaff,'delivery_cloud_transition',[b2Parcels[1].id,'cancel',b2Parcels[1].version,randomUUID(),'Staff thu huy']),e=>e.code==='PT409');
    await as(branchManager,'delivery_cloud_transition',[b2Parcels[1].id,'cancel',b2Parcels[1].version,randomUUID(),'Gop chung vao kien 1']);

    // Deliver parcel 1 with OTP (no collect_cash needed because prepaid PAID!) -> mixed delivered + cancelled sets delivered_at!
    const otp1=(await as(buyerP9,'delivery_cloud_order_otp',[b2Parcels[0].id])).otp_code;
    let p1Step=await as(driverA,'delivery_cloud_transition',[b2Parcels[0].id,'claim',b2Parcels[0].version,randomUUID(),'']);
    // Item 12: Merchant revoke guard blocks revoking merchant while split parcel is active!
    const merchVer=(await as(merchant,'delivery_cloud_profile')).account.memberships.find(m=>m.role==='merchant').version;
    await assert.rejects(as(operator,'delivery_cloud_membership',['merchant','revoke',merchant,merchVer,'Thu thu hoi khi dang giao']),e=>e.code==='PT409');
    p1Step=await as(driverA,'delivery_cloud_transition',[p1Step.id,'arrive',p1Step.version,randomUUID(),'']);
    p1Step=await as(driverA,'delivery_cloud_transition',[p1Step.id,'pickup',p1Step.version,randomUUID(),'']);
    p1Step=await as(driverA,'delivery_cloud_transition',[p1Step.id,'deliver',p1Step.version,randomUUID(),otp1]);
    assert.equal(p1Step.status,'delivered');
    const b2DeliveredAt=(await db.query('select delivered_at from delivery_market_shop_orders where id=$1',[b2Cur.id])).rows[0].delivered_at;
    assert.notEqual(b2DeliveredAt,null);

    // Item 8: Return with reverse shipment -> PAID, active-driver receive guard, no shipping coins minted on return delivery!
    const b2Item=b2Cur.snapshot.items[0];
    let retP9=(await ops(buyerP9,'return_request',{
      order_id:b2Cur.id,product_id:b2Item.product_id,line_id:b2Item.line_id,quantity:1,
      reason:'Tra 1 hop tra',request_key:randomUUID(),
    })).return;
    retP9=(await ops(branchManager,'return_action',{
      order_id:b2Cur.id,id:retP9.id,version:retP9.version,action:'approve',
      response:'Dong y nhan lai 1 hop',create_return_shipment:true,
    })).return;
    const revShipRow=(await db.query('select * from delivery_cloud_orders where id=$1',[retP9.return_delivery_id])).rows[0];
    assert.equal(revShipRow.payment_status,'PAID');
    let revStep=await as(driverA,'delivery_cloud_transition',[revShipRow.id,'claim',revShipRow.version,randomUUID(),'']);
    // Shop manager CANNOT mark receive while driverA is actively carrying return shipment!
    await assert.rejects(ops(branchManager,'return_action',{
      order_id:b2Cur.id,id:retP9.id,version:retP9.version,action:'receive',response:'Nhap kho som',disposition:'restock',
    }),e=>e.code==='PT409');
    const buyerCoinsBefore=Number((await ops(buyerP9,'coins')).balance||0);
    revStep=await as(driverA,'delivery_cloud_transition',[revStep.id,'arrive',revStep.version,randomUUID(),'']);
    revStep=await as(driverA,'delivery_cloud_transition',[revStep.id,'pickup',revStep.version,randomUUID(),'']);
    revStep=await as(driverA,'delivery_cloud_transition',[revStep.id,'deliver',revStep.version,randomUUID(),'Da tra ve kho shop']);
    const buyerCoinsAfter=Number((await ops(buyerP9,'coins')).balance||0);
    assert.equal(buyerCoinsAfter,buyerCoinsBefore);
    retP9=(await ops(branchManager,'return_action',{
      order_id:b2Cur.id,id:retP9.id,version:retP9.version,action:'receive',response:'Da nhan du tu tai xe',disposition:'restock',
    })).return;
    assert.equal(retP9.state,'received');

    // Item 2: Forward shipment ending in 'returned' cancels COD shop order & releases stock!
    let cRet=await rpc(buyerP9,'cart');
    cRet=await rpc(buyerP9,'cart_set',{product_id:prodBranch2.id,quantity:1,version:cRet.version});
    const qRet=(await rpc(buyerP9,'quote',{address_id:buyerAddr.id,payment_method:'cod'})).quote;
    const pRet=(await rpc(buyerP9,'checkout',{quote_id:qRet.id,request_key:randomUUID()})).purchase;
    let oRet=(await rpc(buyerP9,'orders')).orders.find(o=>o.purchase_id===pRet.id);
    const stockBeforeReturnFail=(await db.query('select stock from delivery_market_products where id=$1',[prodBranch2.id])).rows[0].stock;
    oRet=(await rpc(branchStaff,'order_action',{order_id:oRet.id,version:oRet.version,action:'accept'})).order;
    oRet=(await rpc(branchStaff,'order_action',{order_id:oRet.id,version:oRet.version,action:'ready'})).order;
    let dRet=await as(driverA,'delivery_cloud_transition',[oRet.delivery_id,'claim',1,randomUUID(),'']);
    dRet=await as(driverA,'delivery_cloud_transition',[dRet.id,'arrive',dRet.version,randomUUID(),'']);
    dRet=await as(driverA,'delivery_cloud_transition',[dRet.id,'pickup',dRet.version,randomUUID(),'']);
    dRet=await as(driverA,'delivery_cloud_transition',[dRet.id,'fail',dRet.version,randomUUID(),'Khach khong nghe may']);
    dRet=await as(driverA,'delivery_cloud_transition',[dRet.id,'return',dRet.version,randomUUID(),'Hoan kho cho shop']);
    dRet=await as(driverA,'delivery_cloud_transition',[dRet.id,'complete_return',dRet.version,randomUUID(),'Da tra lai kho']);
    assert.equal(dRet.status,'returned');
    const oRetAfter=(await db.query('select state from delivery_market_shop_orders where id=$1',[oRet.id])).rows[0];
    assert.equal(oRetAfter.state,'cancelled');
    const stockAfterReturnFail=(await db.query('select stock from delivery_market_products where id=$1',[prodBranch2.id])).rows[0].stock;
    assert.equal(stockAfterReturnFail,stockBeforeReturnFail+1);

    // Item 1, 7 & 10: COD Marketplace order auto-proposes collection, Driver Wallet accrues 85%/15%, remits COD, requests payout & dual-control enforcement
    let cCod=await rpc(buyerP9,'cart');
    cCod=await rpc(buyerP9,'cart_set',{product_id:prodBranch2.id,quantity:1,version:cCod.version});
    const qCod=(await rpc(buyerP9,'quote',{address_id:buyerAddr.id,payment_method:'cod'})).quote;
    const pCod=(await rpc(buyerP9,'checkout',{quote_id:qCod.id,request_key:randomUUID()})).purchase;
    let oCod=(await rpc(buyerP9,'orders')).orders.find(o=>o.purchase_id===pCod.id);
    oCod=(await rpc(branchStaff,'order_action',{order_id:oCod.id,version:oCod.version,action:'accept'})).order;
    oCod=(await rpc(branchStaff,'order_action',{order_id:oCod.id,version:oCod.version,action:'ready'})).order;
    let dCod=await as(driverA,'delivery_cloud_transition',[oCod.delivery_id,'claim',1,randomUUID(),'']);
    dCod=await as(driverA,'delivery_cloud_transition',[dCod.id,'arrive',dCod.version,randomUUID(),'']);
    dCod=await as(driverA,'delivery_cloud_transition',[dCod.id,'pickup',dCod.version,randomUUID(),'']);
    dCod=await as(driverA,'delivery_cloud_transition',[dCod.id,'collect_cash',dCod.version,randomUUID(),'Thu du COD']);
    dCod=await as(driverA,'delivery_cloud_transition',[dCod.id,'deliver',dCod.version,randomUUID(),'Giao xong COD']);

    // Verify auto-proposed collection was created automatically!
    const autoCol=(await db.query("select * from delivery_market_finance where order_id=$1 and kind='collection'",[oCod.id])).rows[0];
    assert.ok(autoCol);
    assert.equal(autoCol.state,'requested');

    // Dual-control test: add 2nd unblocked operator -> proposer cannot self-approve, 2nd operator CAN approve!
    await as(operator,'delivery_cloud_admin_accounts',['set_operator',{user_id:operator2,operator:true,reason:'Them operator 2'}]);
    const opGrantNotif=(await db.query("select count(*)::int n from delivery_user_notifications where user_id=$1 and kind='operator_granted'",[operator2])).rows[0].n;
    assert.equal(opGrantNotif,1);
    const opProposedCol=(await ops(operator,'finance_request',{
      order_id:oCod.id,kind:'collection',amount:autoCol.amount,reason:'Operator cap nhat bien lai',evidence:'OP-COD-1',request_key:randomUUID(),
    })).finance;
    await assert.rejects(ops(operator,'finance_action',{id:opProposedCol.id,action:'approve',version:opProposedCol.version,reason:'Tu duyet'}),e=>e.code==='PT403');
    await ops(operator2,'finance_action',{id:opProposedCol.id,action:'approve',version:opProposedCol.version,reason:'Operator 2 duyet doc lap'});
    await ops(operator2,'finance_action',{id:opProposedCol.id,action:'complete',version:opProposedCol.version+1,evidence:'BANK-OP2-COD'});

    // Driver Wallet: 85%/15% earnings, COD remittance & payout + immutability
    const walletSum1=await as(driverA,'delivery_driver_finance',['summary',{}]);
    assert.ok(walletSum1.net_trip_earnings_total>0);
    assert.ok(walletSum1.platform_commission_total>0);
    assert.ok(walletSum1.cod_unremitted_total>0);
    await assert.rejects(db.query('delete from delivery_driver_wallet_entries where driver_id=$1',[driverA]));

    const codRemit=(await as(driverA,'delivery_driver_finance',['remit_cod',{
      amount:walletSum1.cod_unremitted_total,reference_code:'UNC-COD-DRIVERA-1',note:'Nop tien thu ho trong ngay',request_key:randomUUID(),
    }])).settlement;
    assert.equal(codRemit.state,'requested');

    // Item 9 & 14: Delegated staff pickup_create, admin_analytics pending KPIs, driver self-claim & full pickup lifecycle!
    const pickupAddr=(await as(branchStaff,'delivery_cloud_addresses_manage',[randomUUID(),{
      label:'Kho Chi Nhanh 2',recipient_name:'Nhan Vien Kho',recipient_phone:'0942220002',
      full_address:'50 Vo Van Ngan TP HCM',latitude:10.85,longitude:106.77,is_default:true,
    },false,null])).addresses[0];
    const pickupDate=(await db.query("select ((now() at time zone 'Asia/Ho_Chi_Minh')::date + 1)::text as d")).rows[0].d;
    let p9Pickup=await as(branchStaff,'delivery_cloud_logistics',['pickup_create',{
      address_id:pickupAddr.id,shop_id:branch2Edited.id,vehicle_type:'tricycle_300kg',
      pickup_date:pickupDate,time_slot:'morning',package_count:5,total_weight_kg:8,note:'Lay tai cua kho B',request_key:randomUUID(),
    }]);
    assert.equal(p9Pickup.status,'requested');
    assert.equal(p9Pickup.shop_id,branch2Edited.id);

    const kpiSnap=await ops(operator,'admin_analytics');
    assert.ok(kpiSnap.pickups_requested>=1);
    assert.ok(kpiSnap.driver_settlements_pending>=1);
    assert.equal(typeof kpiSnap.returns_escalated,'number');

    let settleDecided=(await as(operator,'delivery_driver_finance',['admin_decide',{
      id:codRemit.id,decision:'approve',version:codRemit.version,reason:'Khop sao ke',
    }])).settlement;
    settleDecided=(await as(operator,'delivery_driver_finance',['admin_decide',{
      id:codRemit.id,decision:'complete',version:settleDecided.version,evidence:'BANK-REMIT-OK',reason:'Da hach toan COD',
    }])).settlement;
    assert.equal(settleDecided.state,'completed');

    const walletAfterRemit=await as(driverA,'delivery_driver_finance',['summary',{}]);
    assert.equal(walletAfterRemit.cod_unremitted_total,0);
    assert.ok(walletAfterRemit.available_payout>0);
    const payoutReq=(await as(driverA,'delivery_driver_finance',['request_payout',{
      amount:walletAfterRemit.available_payout,reference_code:'VCB 0123456789 TAI XE A',note:'Rut thu nhap tuan',request_key:randomUUID(),
    }])).settlement;
    let payoutDecided=(await as(operator2,'delivery_driver_finance',['admin_decide',{
      id:payoutReq.id,decision:'approve',version:payoutReq.version,reason:'Du dieu kien rut',
    }])).settlement;
    payoutDecided=(await as(operator2,'delivery_driver_finance',['admin_decide',{
      id:payoutReq.id,decision:'complete',version:payoutDecided.version,evidence:'UNC-PAYOUT-DRIVERA',reason:'Da chuyen khoan',
    }])).settlement;
    const walletFinal=await as(driverA,'delivery_driver_finance',['summary',{}]);
    assert.equal(walletFinal.wallet_balance,0);

    // Driver sees unassigned requested pickup and completes full lifecycle: claim -> arrive -> pickup -> complete
    const driverPickups=(await as(driverA,'delivery_cloud_logistics',['pickup_list',{}])).pickups;
    assert.ok(driverPickups.some(p=>p.id===p9Pickup.id));
    for(const act of ['claim','arrive','pickup','complete']){
      p9Pickup=await as(driverA,'delivery_cloud_logistics',['pickup_transition',{id:p9Pickup.id,action:act,version:p9Pickup.version}]);
    }
    assert.equal(p9Pickup.status,'completed');
  });
  const output=path.resolve(import.meta.dirname,'../../../build/verification/postgres-acceptance.json');
  await mkdir(path.dirname(output),{recursive:true});
  await writeFile(output,JSON.stringify({environment:'disposable-loopback-postgresql',checkedAt:new Date().toISOString(),durationMs:Date.now()-startedAt,results},null,2));
  console.log('PostgreSQL acceptance complete. No cloud writes or provider transactions.');
}finally{
  await pool.end();await db.end();await cluster.stop();
}
