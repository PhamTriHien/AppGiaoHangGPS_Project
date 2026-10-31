import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createPublicTracking, startMarketJobs } from './market-operations.mjs';

test('Public tracking rejects arbitrary fields, uses only the fixed anon projection and strips unexpected private data', async t => {
  let calls = 0, status = 200, reply = {state:'ready',shop_name:'Shop',delivery_status:'delivered',phone:'private-phone',snapshot:{address:'private-address'}};
  const app = express(); app.use(express.json());
  app.use(createPublicTracking({env:{SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public'},fetcher:async(url,options) => {
    calls++;
    assert.equal(String(url),'https://project.supabase.co/rest/v1/rpc/delivery_market_public_tracking');
    assert.equal(options.headers.Authorization,undefined);
    assert.deepEqual(JSON.parse(options.body),{p_token:'a'.repeat(64)});
    return new Response(typeof reply === 'string' ? reply : JSON.stringify(reply),{status});
  }}));
  app.use((e,_req,res,_next) => res.status(e.status || 500).json({error:e.message}));
  const server = app.listen(0,'127.0.0.1'); t.after(() => server.close()); await new Promise(r => server.once('listening',r));
  const post = body => fetch(`http://127.0.0.1:${server.address().port}/tracking`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  for (const body of [{token:'guess'}, {token:'a'.repeat(64),table:'orders'},[],{}]) assert.equal((await post(body)).status,404);
  assert.equal(calls,0);
  let response = await post({token:'a'.repeat(64)});
  assert.equal(response.status,200); assert.equal(response.headers.get('cache-control'),'no-store');
  assert.equal(JSON.stringify(await response.json()).includes('private-'),false);
  status=404; reply={code:'PT404',message:'private-db-details'}; response=await post({token:'a'.repeat(64)});
  assert.equal(response.status,404); assert.equal((await response.text()).includes('private-db-details'),false);
  status=200; reply='x'.repeat(5000); assert.equal((await post({token:'a'.repeat(64)})).status,503);
  reply='invalid json'; assert.equal((await post({token:'a'.repeat(64)})).status,503);
});

test('Worker failure is sanitized and later ticks recover; shutdown waits for the in-flight transaction', async () => {
  let calls=0, closed=false, finish;
  const failures=[];
  const worker=startMarketJobs({env:{DATABASE_URL:'test-only',MARKET_JOBS_ENABLED:'true'},schedule:()=>1,unschedule:()=>{},
    onError:code=>failures.push(code), database:{
      query:async(sql,args)=>{ assert.equal(sql,'select public.delivery_market_run_jobs($1) as result');assert.deepEqual(args,[25]); calls++; if(calls===1) throw new Error('private-password'); await new Promise(r=>{finish=r;}); },
      close:async()=>{closed=true;},
    }});
  await worker.tick(); assert.deepEqual(failures,['market_jobs_unavailable']);
  const next=worker.tick(),stop=worker.close(); assert.equal(closed,false); finish(); await Promise.all([next,stop]); assert.equal(closed,true);
  await worker.tick(); assert.equal(calls,2);
});
