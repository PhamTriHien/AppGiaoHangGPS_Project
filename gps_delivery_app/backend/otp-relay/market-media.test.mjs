import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import express from 'express';
import sharp from 'sharp';
import { normalizeMarketImage } from './market-media.mjs';
import { createCloudOrders } from './cloud-orders.mjs';

test('Product images decode completely, strip metadata, bound resources and reject active or malformed formats',async()=>{
  const image=await sharp({create:{width:40,height:24,channels:3,background:'#12aa55'}}).jpeg()
    .withMetadata({exif:{IFD0:{Artist:'Private photographer'}}}).toBuffer();
  const normalized=await normalizeMarketImage(image.toString('base64'));
  const info=await sharp(normalized).metadata();
  assert.equal(info.format,'webp');assert.equal(info.width,40);assert.equal(info.exif,undefined);
  for(const input of [null,'','????',Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>').toString('base64'),
    image.subarray(0,40).toString('base64'),'a'.repeat(6_666_672)]){
    await assert.rejects(normalizeMarketImage(input),e=>e.status===400);
  }
});

test('Media HTTP preserves verified identity and fixed storage paths; duplicate retries verify the stored bytes',async t=>{
  const shop='20000000-0000-0000-0000-000000000001',user='10000000-0000-0000-0000-000000000001';
  const calls=[];let local=true,owned=true,duplicate=false,badReservation=false,corruptDuplicate=false,stored;
  const image=await sharp({create:{width:16,height:16,channels:3,background:'#123456'}}).png().toBuffer();
  const app=express();
  app.use('/cloud',createCloudOrders({env:{SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public'},
    authenticate(req,_res,next){req.deliveryIdentity={id:user,token:'verified-user-jwt',local};next();},
    fetcher:async(url,options={})=>{
      calls.push({url:String(url),options});
      if(String(url).endsWith('/rpc/delivery_marketplace'))return Response.json({shops:owned?[{id:shop}]:[]});
      if(String(url).endsWith('/rpc/delivery_market_media_reserve')){
        const p=JSON.parse(options.body);
        return Response.json({bucket:'delivery-market-media',name:badReservation?'../private':`${user}/${shop}/${p.p_hash}.webp`});
      }
      if(options.method==='POST'){
        assert.equal(options.headers.Authorization,'Bearer verified-user-jwt');
        assert.equal(options.headers['Content-Type'],'image/webp');assert.equal(options.headers['x-upsert'],'false');
        stored=Buffer.from(options.body);return Response.json({}, {status:duplicate?409:200});
      }
      return new Response(corruptDuplicate?Buffer.from('unexpected data'):stored);
    }}));
  app.use((e,_req,res,_next)=>res.status(e.status||500).json({error:e.message}));
  const server=app.listen(0,'127.0.0.1');t.after(()=>server.close());await new Promise(resolve=>server.once('listening',resolve));
  const post=body=>fetch(`http://127.0.0.1:${server.address().port}/cloud/media`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const payload={shop_id:shop,image:image.toString('base64')};
  assert.equal((await post(payload)).status,401);assert.equal(calls.length,0);local=false;
  assert.equal((await post({...payload,url:'https://attacker.example'})).status,400);
  owned=false;assert.equal((await post(payload)).status,403);assert.equal(calls.length,1);owned=true;
  const result=await post(payload);assert.equal(result.status,200);
  const output=await result.json(),hash=createHash('sha256').update(stored).digest('hex');
  assert.equal(output.image_url,`https://project.supabase.co/storage/v1/object/public/delivery-market-media/${user}/${shop}/${hash}.webp`);
  duplicate=true;assert.equal((await post(payload)).status,200);
  corruptDuplicate=true;assert.equal((await post(payload)).status,502);
  badReservation=true;const count=calls.length;assert.equal((await post(payload)).status,502);
  assert.equal(calls.length,count+2); // No upload is attempted with an untrusted name.
});
