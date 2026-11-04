import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createDeploymentReadiness, publicBackendUrl, COMMERCE_MIGRATION, databaseRevision } from './deployment-readiness.mjs';
import { createDeliveryIntegrations } from './delivery-integrations.mjs';

const validSchema={cloud_schema:true,commerce_schema:true,commerce_guard:true,commerce_permissions:true,commerce_privacy:true,address_schema:true,marketplace_schema:true,operations_schema:true,membership_schema:true,import_schema:true,stock_terms_schema:true,market_media_schema:true,browse_schema:true,configuration_schema:true,commercial_suite_schema:true,logistics_schema:true,admin_accounts_schema:true,promo_events_schema:true,profile_push_coins_schema:true,shipping_cash_schema:true,cloud_sync_journey_schema:true,merchant_suite_schema:true,cross_role_linkage_schema:true};
const configuration=()=>({DATABASE_URL:'postgresql://postgres:private-db-password@db.example/postgres',
  SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public-key',PUBLIC_BASE_URL:'https://api.example/prefix/',MARKET_JOBS_ENABLED:'true',
  PAYOS_ENABLED:'true',PAYOS_CLIENT_ID:'client',PAYOS_API_KEY:'private-payos',PAYOS_CHECKSUM_KEY:'private-checksum',
  GHN_ENABLED:'true',GHN_TOKEN:'private-ghn',GHN_SHOP_ID:'123',GHN_WEBHOOK_SECRET:'private-hook'});

test('Readiness distinguishes missing setup, failed database access and verified schema without leaking credentials',async()=>{
  let calls=0;
  let env={};
  const now=()=>new Date('2026-10-28T10:00:00Z');
  let check=createDeploymentReadiness({env,now,database:{query:async()=>{calls++;throw new Error('private-db-password');}}});
  let result=await check();
  assert.equal(calls,0);
  assert.equal(result.checks.find(c=>c.id==='database').status,'missing');
  assert.equal(result.checks.find(c=>c.id==='commerce_schema').status,'unchecked');
  assert.equal(result.features.payos.prerequisitesMet,false);
  assert.ok(result.callbacks.every(c=>c.url===null));
  env.DATABASE_URL='postgresql://postgres:private-db-password@db.example/postgres';
  result=await check();
  assert.equal(calls,1);
  assert.equal(result.checks.find(c=>c.id==='database').status,'error');
  assert.equal(result.checks.find(c=>c.id==='cloud_schema').status,'unchecked');
  assert.equal(JSON.stringify(result).includes('private-db-password'),false);
  env=configuration();
  check=createDeploymentReadiness({env,now,database:{query:async()=>({rows:[validSchema]})}});
  result=await check();
  assert.ok(result.checks.every(c=>c.status==='ok'));
  assert.equal(result.features.payos.prerequisitesMet,true);
  assert.equal(result.features.ghn.prerequisitesMet,true);
  assert.equal(result.features.payos.liveVerified,false);
  assert.equal(result.liveTransactionsVerified,false);
  assert.equal(result.callbacks[0].url,'https://api.example/prefix/delivery/payments/webhook');
  assert.ok(result.callbacks.every(c=>c.registrationVerified===false));
  for(const value of ['private-db-password','private-payos','private-checksum','private-ghn','private-hook','public-key']) {
    assert.equal(JSON.stringify(result).includes(value),false);
  }
  env.GHN_ENABLED='false';delete env.PAYOS_API_KEY;
  result=await check();
  assert.equal(result.checks.find(c=>c.id==='ghn').status,'disabled');
  assert.deepEqual(result.checks.find(c=>c.id==='payos').missingFields,['PAYOS_API_KEY']);
  assert.equal(result.features.ghn.prerequisitesMet,false);
});

test('Readiness refuses incomplete guards/privacy/permissions and coalesces concurrent catalog reads',async()=>{
  for(const key of ['cloud_schema','commerce_schema','commerce_guard','commerce_permissions','commerce_privacy']) {
    const report=await createDeploymentReadiness({env:configuration(),database:{query:async()=>({rows:[{...validSchema,[key]:false}]})}})();
    assert.equal(report.features.payos.prerequisitesMet,false);
    assert.equal(report.features.ghn.prerequisitesMet,false);
  }
  let finish,calls=0;
  const pending=new Promise(resolve=>{finish=resolve;});
  const read=createDeploymentReadiness({env:configuration(),database:{query:async()=>{calls++;return pending;}}});
  const first=read(),second=read();
  finish({rows:[validSchema]});
  assert.deepEqual(await first,await second);assert.equal(calls,1);
  const malformed=await createDeploymentReadiness({env:configuration(),database:{query:async()=>({rows:[{}]})}})();
  assert.equal(malformed.features.payos.prerequisitesMet,false);
  assert.equal(malformed.checks.find(c=>c.id==='database').status,'error');
});

test('Only nonlocal HTTPS callback bases are offered and prefixes are preserved',()=>{
  for(const url of ['http://api.example','https://localhost','https://127.0.0.1','https://10.1.1.1','https://192.168.1.1',
    'https://172.16.0.1','https://[::1]','https://api.local','https://name:password@api.example','https://api.example/#x','https://api.example/?x=1']) {
    assert.equal(publicBackendUrl(url),null,url);
  }
  assert.equal(publicBackendUrl('https://api.example/prefix').href,'https://api.example/prefix/');
});

test('Cloud migration requires an operator, exact confirmation, database and a single active run',async t=>{
  const env=configuration();let migrateCalls=0,finish,fail=false;
  const pending=new Promise(resolve=>{finish=resolve;});
  const app=express();app.use(express.json());
  app.use(createDeliveryIntegrations({env,
    authenticate(req,_res,next){req.deliveryIdentity={id:'operator',role:req.get('x-role')||'operator',local:req.get('x-local')==='true'};next();},
    operatorOnly(req,res,next){if(req.deliveryIdentity.role!=='operator') return res.status(403).json({error:'operator'});next();},
    readiness:async()=>({databaseConfigured:true,liveTransactionsVerified:false}),
    migrate:async({env:received})=>{migrateCalls++;assert.notEqual(received,env);if(fail) throw new Error(env.DATABASE_URL);await pending;return {ready:true,migration:COMMERCE_MIGRATION};},
  }));
  app.use((error,_req,res,_next)=>res.status(error.status||500).json({error:error.message}));
  const server=app.listen(0,'127.0.0.1');t.after(()=>server.close());
  await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/admin/integrations`;
  const post=(body,headers={})=>fetch(base+'/migrate-cloud',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify({databaseRevision:databaseRevision(env),...body})});
  assert.equal((await fetch(base+'/readiness',{headers:{'x-role':'user'}})).status,403);
  const report=await fetch(base+'/readiness');
  assert.equal(report.headers.get('cache-control'),'no-store');
  assert.equal((await report.json()).canMigrate,true);
  assert.equal((await post({confirm:COMMERCE_MIGRATION},{'x-role':'user'})).status,403);
  assert.equal((await post({confirm:'wrong'},{'x-local':'true'})).status,400);
  const connection=env.DATABASE_URL;env.DATABASE_URL='';
  assert.equal((await post({confirm:COMMERCE_MIGRATION},{'x-local':'true'})).status,503);env.DATABASE_URL=connection;
  assert.equal(migrateCalls,0);
  assert.equal((await post({confirm:COMMERCE_MIGRATION,databaseRevision:'stale-revision'},{'x-local':'true'})).status,409);
  const running=post({confirm:COMMERCE_MIGRATION});
  while(!migrateCalls) await new Promise(resolve=>setTimeout(resolve,1));
  assert.equal((await post({confirm:COMMERCE_MIGRATION},{'x-local':'true'})).status,409);
  for(const body of [{values:{DATABASE_URL:'postgresql://other/db'}},{values:{},clear:['DATABASE_URL']}]) {
    const save=await fetch(base+'/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    assert.equal(save.status,409);
    assert.equal(env.DATABASE_URL,connection);
  }
  finish();
  const completed=await (await running).json();
  assert.equal(completed.completed,true);
  assert.equal(completed.readiness.canMigrate,true);
  fail=true;
  const failed=await post({confirm:COMMERCE_MIGRATION},{'x-local':'true'});
  assert.equal(failed.status,503);assert.equal((await failed.text()).includes('private-db-password'),false);
});
