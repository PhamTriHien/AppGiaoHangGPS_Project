import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';

test('Membership HTTP fixes the RPC and subject while rejecting forged approvals and invalid versions', async t => {
  const calls=[]; let local=false;
  const app=express(); app.use(express.json());
  app.use('/cloud',createCloudOrders({env:{SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public'},
    authenticate(req,_res,next){req.deliveryIdentity={id:'user',token:'verified-jwt',local}; next();},
    fetcher:async(url,options)=>{calls.push({url:String(url),options,body:JSON.parse(options.body)});
      return new Response(JSON.stringify({membership:{state:'pending'}}));}}));
  app.use((e,_req,res,_next)=>res.status(e.status||500).json({error:e.message}));
  const server=app.listen(0,'127.0.0.1'); t.after(()=>server.close());
  await new Promise(resolve=>server.once('listening',resolve));
  const post=(path,body)=>fetch(`http://127.0.0.1:${server.address().port}/cloud/${path}`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  for(const body of [{role:'operator'},{role:'driver',state:'active'},{role:'merchant',user_id:'someone'},[]]) {
    assert.equal((await post('memberships',body)).status,400);
  }
  assert.equal(calls.length,0);
  const response=await post('memberships',{role:'driver'});
  assert.equal(response.status,200); assert.equal(response.headers.get('cache-control'),'no-store');
  assert.equal(calls[0].url,'https://project.supabase.co/rest/v1/rpc/delivery_cloud_membership');
  assert.deepEqual(calls[0].body,{p_role:'driver',p_decision:'request'});
  assert.equal(calls[0].options.headers.Authorization,'Bearer verified-jwt');
  const path='accounts/00000000-0000-0000-0000-000000000001/memberships/driver';
  for(const body of [{decision:'approve',version:0,reason:''},{decision:'approve',version:1.5,reason:''},
    {decision:'revoke',version:1,reason:''},{decision:'request',version:1,reason:''},
    {decision:'approve',version:1,reason:'',operator:true}]) {
    assert.equal((await post(path,body)).status,400);
  }
  assert.equal((await post(path,{decision:'revoke',version:2,reason:'Review complete'})).status,200);
  assert.deepEqual(calls.at(-1).body,{p_user:'00000000-0000-0000-0000-000000000001',p_role:'driver',
    p_decision:'revoke',p_version:2,p_reason:'Review complete'});
  // No local Admin identity can invoke a cloud approval.
  local=true;
  assert.equal((await post(path,{decision:'approve',version:2,reason:''})).status,401);
  assert.equal(calls.length,2);
});
