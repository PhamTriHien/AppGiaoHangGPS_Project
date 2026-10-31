import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';

test('Marketplace HTTP accepts only fixed actions, verified Supabase identity and bounded JSON',async t=>{
  const calls=[];let local=true,status=200,data={products:[]};
  const app=express();app.use(express.json());
  app.use('/cloud',createCloudOrders({env:{SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public'},
    authenticate(req,_res,next){req.deliveryIdentity={id:'user',token:'verified-user-jwt',local};next();},
    fetcher:async(url,options)=>{calls.push({url:String(url),options,body:JSON.parse(options.body)});return new Response(JSON.stringify(data),{status});}}));
  app.use((e,_req,res,_next)=>res.status(e.status||500).json({error:e.message}));
  const server=app.listen(0,'127.0.0.1');t.after(()=>server.close());await new Promise(resolve=>server.once('listening',resolve));
  const post=(action,body)=>fetch(`http://127.0.0.1:${server.address().port}/cloud/marketplace/${action}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  assert.equal((await post('catalog',{})).status,401);assert.equal(calls.length,0);
  local=false;
  for(const [action,body] of [['delivery_is_operator',{}],['catalog',[]],['catalog',{search:'x'.repeat(16001)}]]) {
    assert.equal((await post(action,body)).status,400);
  }
  assert.equal(calls.length,0);
  const response=await post('catalog',{search:'product'});
  assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');
  assert.equal(calls[0].url,'https://project.supabase.co/rest/v1/rpc/delivery_market_browse');
  assert.deepEqual(calls[0].body,{p_payload:{search:'product'}});
  assert.equal(calls[0].options.headers.Authorization,'Bearer verified-user-jwt');
  for(const action of ['finance_request','finance_action','return_request','return_action','tracking_share','tracking_revoke','reorder','review_save','favorites','product_details','operations']) {
    assert.equal((await post(action,{})).status,200);
    assert.equal(calls.at(-1).url,'https://project.supabase.co/rest/v1/rpc/delivery_market_operations');
    assert.equal(calls.at(-1).body.p_action,action);
    assert.equal(calls.at(-1).options.headers.Authorization,'Bearer verified-user-jwt');
  }
  status=404;data={code:'PGRST202',message:'internal SQL details'};
  const missing=await post('cart',{});assert.equal(missing.status,503);
  assert.match((await missing.json()).error,/quản trị/);
  for(const code of ['PT403','PT409','22P02','23505']) {
    status=400;data={code,message:code.startsWith('PT')?'Known conflict':'private details'};
    const result=await post('checkout',{});
    assert.equal(result.status,code==='PT403'?403:code==='22P02'?400:409);
    assert.equal(JSON.stringify(await result.json()).includes('private details'),false);
  }
});
