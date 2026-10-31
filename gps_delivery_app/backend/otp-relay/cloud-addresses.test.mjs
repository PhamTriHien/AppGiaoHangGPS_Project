import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';

test('Address book preserves data, isolates accounts, validates direct RPCs and serializes default/version edits', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`create role authenticated; create role anon;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create table delivery_cloud_accounts(user_id uuid primary key,blocked boolean default false);
    create function public.delivery_cloud_active() returns boolean language sql stable security definer set search_path='' as $$
      select exists(select 1 from public.delivery_cloud_accounts where user_id=auth.uid() and not blocked)$$;`);
  const sql = await readFile(new URL('../../database/migrations/20261029_cloud_addresses.sql', import.meta.url), 'utf8');
  await db.exec(sql);
  const alice=randomUUID(), bob=randomUUID(), unregistered=randomUUID(), id=randomUUID();
  await db.query('insert into delivery_cloud_accounts(user_id) values($1),($2)',[alice,bob]);
  const as = async user => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user || '']);
    await db.exec('set role authenticated');
  };
  const rpc = async (address=null,details=null,remove=false,version=null) =>
    (await db.query('select delivery_cloud_addresses_manage($1,$2,$3,$4) as result',[address,details,remove,version])).rows[0].result;
  const details={label:'Home',recipient_name:'Alice',recipient_phone:'0901234567',full_address:'12 Nguyen Hue',latitude:10.77,longitude:106.7,is_default:false};
  await as(null); await assert.rejects(rpc(),/đăng nhập/);
  await as(unregistered); await assert.rejects(rpc(),/hoạt động/);
  await as(alice);
  let list=(await rpc(id,details)).addresses;
  assert.equal(list.length,1); assert.equal(list[0].is_default,true); assert.equal(list[0].version,1);
  assert.equal((await rpc(id,details)).addresses.length,1);
  await assert.rejects(rpc(id,{...details,label:'Modified'}),/đã được dùng/);
  for (const invalid of [{user_id:bob},{latitude:91},{longitude:-181},{latitude:'10.77'},
    {is_default:null},{recipient_phone:'123'},{full_address:'  '},{label:7},{recipient_name:null}]) {
    await assert.rejects(rpc(randomUUID(),{...details,...invalid}),/không hợp lệ/);
  }
  await assert.rejects(db.query('update delivery_cloud_addresses set label=$1',['Override']),/permission denied/);
  await assert.rejects(db.query('delete from delivery_cloud_addresses'),/permission denied/);
  await as(bob);
  assert.deepEqual((await rpc()).addresses,[]);
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,0);
  await assert.rejects(rpc(id,details),/không khả dụng/);
  await assert.rejects(rpc(id,details,false,1),/Không tìm thấy/);
  await rpc(id,null,true,1);
  await as(alice);
  assert.equal((await rpc()).addresses.length,1);
  const second=randomUUID();
  list=(await rpc(second,{...details,label:'Office',is_default:true})).addresses;
  assert.equal(list.filter(a=>a.is_default).length,1); assert.equal(list[0].id,second);
  await assert.rejects(rpc(id,details,false,1),/đã thay đổi/);
  list=(await rpc(second,null,true,1)).addresses;
  assert.equal(list[0].id,id); assert.equal(list[0].is_default,true);
  assert.equal((await rpc(second,null,true,1)).addresses.length,1);
  for (let i=1;i<25;i++) await rpc(randomUUID(),{...details,label:`Address ${i}`});
  await assert.rejects(rpc(randomUUID(),details),/25 địa chỉ/);
  await db.exec('reset role'); await db.exec(sql);
  await as(alice); assert.equal((await rpc()).addresses.length,25);
  await db.exec('reset role'); await db.query('update delivery_cloud_accounts set blocked=true where user_id=$1',[alice]);
  await as(alice); await assert.rejects(rpc(),/hoạt động/);
  assert.equal((await db.query('select * from delivery_cloud_addresses')).rows.length,0);
  await db.exec('reset role; set role anon');
  await assert.rejects(rpc(),/permission denied/);
  await assert.rejects(db.query('select * from delivery_cloud_addresses'),/permission denied/);
});

test('Address gateway forwards only the fixed RPC and current JWT, rejecting invalid commands', async t => {
  let local=false; const calls=[];
  const app=express(); app.use(express.json());
  app.use('/cloud',createCloudOrders({env:{SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_ANON_KEY:'public-key'},
    authenticate(req,_res,next){ req.deliveryIdentity={token:'account-jwt',local}; next(); },
    fetcher:async(url,options)=>{calls.push({url:String(url),...options});return new Response('{"addresses":[]}',{status:200});}}));
  app.use((error,_req,res,_next)=>res.status(error.status||500).json({error:error.message}));
  const server=app.listen(0,'127.0.0.1'); t.after(()=>server.close());
  await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/cloud/addresses`;
  assert.equal((await fetch(base)).status,200);
  assert.equal(calls[0].url,'https://fixture.supabase.co/rest/v1/rpc/delivery_cloud_addresses_manage');
  assert.equal(calls[0].headers.Authorization,'Bearer account-jwt');
  const id=randomUUID();
  const post=body=>fetch(`${base}/${id}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  assert.equal((await post({delete:true,version:2})).status,200);
  assert.deepEqual(JSON.parse(calls[1].body),{p_id:id,p_details:null,p_delete:true,p_version:2});
  for (const body of [{version:1.5},{version:0},{version:'2'},{delete:'yes'},{owner_id:randomUUID()}]) {
    assert.equal((await post(body)).status,400);
  }
  assert.equal(calls.length,2);
  local=true; assert.equal((await fetch(base)).status,401); assert.equal(calls.length,2);
});
