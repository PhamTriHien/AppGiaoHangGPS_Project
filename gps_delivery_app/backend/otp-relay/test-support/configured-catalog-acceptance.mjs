import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

export async function testConfiguredCatalog({db,as,rpc,operator,merchant,buyer,shop,check}) {
  const ops=(id,action,data)=>as(id,'delivery_market_operations',[action,data]);
  const groups=[{id:'size',name:'Size',min:1,max:1,options:[
    {id:'small',name:'Small',price:5000},{id:'large',name:'Large',price:15000}]}];
  const small=[{group_id:'size',option_id:'small'}],large=[{group_id:'size',option_id:'large'}];
  let product,cart,order;
  const details={id:randomUUID(),shop_id:shop.id,name:'Configured item',description:'',category:'Food',sku:'CONFIG',
    price:50000,stock:5,weight_kg:1,published:true,option_groups:groups,preparation_minutes:15,
    images:['https://example.test/product.webp'],sale_schedule:[]};
  const save=async(extra={})=>{
    const current=(await db.query('select stock,version from delivery_market_products where id=$1',[details.id])).rows[0];
    return (await rpc(merchant,'product_save',{...details,...current,...extra})).product;
  };
  await check('P1 option validation, schedule boundaries and private helper permissions',async()=>{
    product=await save();assert.deepEqual(product.option_groups,groups);assert.equal(product.preparation_minutes,15);
    for(const extra of [
      {option_groups:[...groups,...groups]},
      {option_groups:[{...groups[0],min:3}]},
      {option_groups:[{...groups[0],options:[{id:'x',name:'X',price:1.5}]}]},
      {preparation_minutes:1.5},
      {sale_schedule:[{day:8,open:100,close:200}]},
      {sale_schedule:[{day:1,open:100,close:200},{day:1,open:150,close:250}]},
      {images:['http://example.test/unsafe.jpg']},
    ])await assert.rejects(save(extra));
    await assert.rejects(as(buyer,'delivery_market_selection',[product.id,JSON.stringify(small)]),e=>e.code==='42501');
    const open=(await db.query("select delivery_market_is_open('[{\"day\":1,\"open\":480,\"close\":540}]','2026-11-02 01:00Z') start,delivery_market_is_open('[{\"day\":1,\"open\":480,\"close\":540}]','2026-11-02 02:00Z') finish")).rows[0];
    assert.equal(open.start,true);assert.equal(open.finish,false);
  });
  await check('P2 configured lines derive prices, aggregate stock and reject forged selections',async()=>{
    cart=await rpc(buyer,'cart');
    for(const item of cart.items)cart=await rpc(buyer,'cart_set',{product_id:item.id,line_id:item.line_id,quantity:0,version:cart.version});
    for(const selected_options of [[],[{group_id:'size',option_id:'missing'}],[...small,...small],
      [{group_id:'size',option_id:'small',price:1}]]) {
      await assert.rejects(rpc(buyer,'cart_set',{product_id:product.id,selected_options,quantity:1,version:cart.version}));
    }
    cart=await rpc(buyer,'cart_set',{product_id:product.id,selected_options:small,quantity:1,version:cart.version});
    const old=cart.version;
    cart=await rpc(buyer,'cart_set',{product_id:product.id,selected_options:large,quantity:1,version:cart.version});
    assert.equal(cart.items.length,2);assert.equal(new Set(cart.items.map(i=>i.line_id)).size,2);
    assert.deepEqual(cart.items.map(i=>i.unit_price).sort((a,b)=>a-b),[55000,65000]);
    await assert.rejects(rpc(buyer,'cart_set',{product_id:product.id,selected_options:small,quantity:5,version:cart.version}),e=>e.code==='PT409');
    await assert.rejects(rpc(buyer,'cart_set',{product_id:product.id,selected_options:small,quantity:1,version:old}),e=>e.code==='PT409');
    await assert.rejects(rpc(buyer,'cart_set',{product_id:product.id,line_id:randomUUID(),quantity:0,version:cart.version}),e=>e.code==='PT409');
    assert.ok(cart.items.every(i=>i.available));
  });
  await check('P2 quotes require the displayed cart and address versions without trusting client amounts',async()=>{
    const address=(await as(buyer,'delivery_cloud_addresses_manage')).addresses[0];
    const versions={address_id:address.id,cart_version:cart.version,address_version:address.version};
    const quote=(await rpc(buyer,'quote',versions)).quote;
    assert.equal(quote.snapshot.cart_version,cart.version);
    assert.equal(quote.snapshot.address_version,address.version);
    for(const extra of [{cart_version:cart.version-1},{address_version:address.version+1}]) {
      await assert.rejects(rpc(buyer,'quote',{...versions,...extra}),e=>e.code==='PT409');
    }
    for(const extra of [{cart_version:'1'},{cart_version:1.5},{address_version:null},{total:1},{owner_id:merchant}]) {
      await assert.rejects(rpc(buyer,'quote',{...versions,...extra}),e=>e.code==='PT400');
    }
    await db.query('update delivery_cloud_addresses set version=version+1 where id=$1',[address.id]);
    await assert.rejects(rpc(buyer,'quote',versions),e=>e.code==='PT409');
    assert.equal((await rpc(buyer,'quote',{...versions,address_version:address.version+1})).quote.snapshot.address_version,address.version+1);
  });
  await check('P2 option price changes invalidate quotes; configured checkout and replay stay atomic',async()=>{
    const address=(await as(buyer,'delivery_cloud_addresses_manage')).addresses[0];
    const stale=(await rpc(buyer,'quote',{address_id:address.id})).quote;
    await save({option_groups:[{...groups[0],options:[{...groups[0].options[0],price:6000},groups[0].options[1]]}]});
    await assert.rejects(rpc(buyer,'checkout',{quote_id:stale.id,request_key:randomUUID()}),e=>e.code==='PT409');
    await save();
    const quote=(await rpc(buyer,'quote',{address_id:address.id})).quote;
    assert.equal(quote.snapshot.shops[0].subtotal,120000);
    assert.equal(quote.snapshot.shops[0].items.length,2);
    const key=randomUUID(),purchase=(await rpc(buyer,'checkout',{quote_id:quote.id,request_key:key})).purchase;
    assert.equal((await rpc(buyer,'checkout',{quote_id:quote.id,request_key:key})).purchase.id,purchase.id);
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[product.id])).rows[0].stock,3);
    order=(await rpc(buyer,'orders')).orders.find(o=>o.purchase_id===purchase.id);
    assert.ok(order);
  });
  await check('P2 reorder preserves separate choices; closed schedules block checkout and retired lines remain removable',async()=>{
    cart=await rpc(buyer,'cart');
    const payload={order_id:order.id,version:cart.version,request_key:randomUUID()};
    cart=await ops(buyer,'reorder',payload);assert.equal(cart.items.length,2);
    assert.equal((await ops(buyer,'reorder',payload)).version,cart.version);
    const tomorrow=(await db.query("select extract(isodow from now() at time zone 'Asia/Ho_Chi_Minh')::int%7+1 as next_day")).rows[0].next_day;
    await save({sale_schedule:[{day:tomorrow,open:0,close:1440}]});
    const browse=await as(buyer,'delivery_market_browse',[{shop_id:shop.id,search:'CONFIG'}]);
    assert.equal(browse.products.find(p=>p.id===product.id).available,false);
    assert.equal((await ops(buyer,'product_details',{product_id:product.id})).product.available,false);
    const address=(await as(buyer,'delivery_cloud_addresses_manage')).addresses[0];
    await assert.rejects(rpc(buyer,'quote',{address_id:address.id}),e=>e.code==='PT409');
    assert.ok((await rpc(buyer,'cart')).items.every(i=>!i.available));
    await save({option_groups:[]});
    cart=await rpc(buyer,'cart');assert.ok(cart.items.every(i=>!i.available));
    for(const item of cart.items)cart=await rpc(buyer,'cart_set',{product_id:item.id,line_id:item.line_id,quantity:0,version:cart.version});
    assert.equal(cart.items.length,0);await save();
    const current=(await db.query('select * from delivery_market_shops where id=$1',[shop.id])).rows[0];
    const fields=Object.fromEntries(['name','description','address','latitude','longitude','paused','version'].map(k=>[k,current[k]]));
    let saved=(await rpc(merchant,'shop_save',{...fields,opening_schedule:[{day:tomorrow,open:0,close:1440}]})).shop;
    assert.equal((await as(buyer,'delivery_market_browse',[{shop_id:shop.id}])).shop.open,false);
    await assert.rejects(rpc(buyer,'cart_set',{product_id:product.id,selected_options:small,quantity:1,version:cart.version}),e=>e.code==='PT409');
    saved=(await rpc(merchant,'shop_save',{...fields,version:saved.version,opening_schedule:[]})).shop;
    assert.deepEqual(saved.opening_schedule,[]);
  });
  await check('P3-P5 returns and refunds cannot borrow quantities or prices from a different choice',async()=>{
    await db.query('update delivery_market_shop_orders set delivered_at=now() where id=$1',[order.id]);
    const low=order.snapshot.items.find(i=>i.unit_price===55000),high=order.snapshot.items.find(i=>i.unit_price===65000);
    const request=(item,extra={})=>ops(buyer,'return_request',{order_id:order.id,product_id:item.product_id,line_id:item.line_id,
      quantity:1,reason:'Damaged item',request_key:randomUUID(),...extra});
    let ret=(await request(low)).return;
    await assert.rejects(request(low),e=>e.code==='PT409');
    assert.equal((await request(high)).return.quantity,1);
    await assert.rejects(request(low,{line_id:randomUUID()}),e=>e.code==='PT409');
    ret=(await ops(merchant,'return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'approve',response:'Verified item'})).return;
    ret=(await ops(merchant,'return_action',{order_id:order.id,id:ret.id,version:ret.version,action:'receive',response:'Received item'})).return;
    const approver=randomUUID();await db.query('insert into auth.users values($1)',[approver]);
    await as(approver,'delivery_cloud_profile',[{full_name:'Independent approver',phone:'0901234567',requested_role:'customer'}]);
    await db.query("insert into delivery_api_profiles values($1,'operator')",[approver]);
    const complete=async(proposer,kind,amount,returnId)=>{
      let f=(await ops(proposer,'finance_request',{order_id:order.id,kind,amount,return_id:returnId,reason:'Verified accounting',evidence:'Isolated receipt',request_key:randomUUID()})).finance;
      f=(await ops(approver,'finance_action',{id:f.id,version:f.version,action:'approve',reason:'Verified independently'})).finance;
      return ops(approver,'finance_action',{id:f.id,version:f.version,action:'complete',evidence:'Isolated bank receipt'});
    };
    await complete(operator,'collection',order.snapshot.subtotal+order.snapshot.shipping_fee);
    const refund=amount=>ops(buyer,'finance_request',{order_id:order.id,return_id:ret.id,kind:'refund',amount,
      reason:'Return refund',evidence:'Isolated receipt',request_key:randomUUID()});
    await assert.rejects(refund(65000),e=>e.code==='PT409');
    await complete(buyer,'refund',55000,ret.id);
    await assert.rejects(refund(1),e=>e.code==='PT409');
    const journals=(await db.query('select journal_id,sum(amount)::bigint balance from delivery_market_ledger group by journal_id')).rows;
    assert.ok(journals.length>=2);assert.ok(journals.every(j=>j.balance==='0'));
  });
  await check('P1 media byte and hourly budgets reject new uploads while allowing content retries',async()=>{
    const existing=(await db.query('select * from delivery_market_media where shop_id=$1 limit 1',[shop.id])).rows[0];
    const insert=(count,bytes)=>db.query(`insert into delivery_market_media(name,shop_id,owner_id,content_hash,byte_size)
      select 'isolated-budget-'||n,$1,$2,md5('isolated-'||n)||md5('isolated-'||n),$3 from generate_series(1,$4) n`,[shop.id,merchant,bytes,count]);
    const cleanup=()=>db.query("delete from delivery_market_media where name like 'isolated-budget-%' and shop_id=$1",[shop.id]);
    try {
      await insert(20,5000000);
      await assert.rejects(as(merchant,'delivery_market_media_reserve',[shop.id,'d'.repeat(64),1]),e=>e.code==='PT409');
      assert.equal((await as(merchant,'delivery_market_media_reserve',[shop.id,existing.content_hash,existing.byte_size])).name,existing.name);
      await cleanup();await insert(60,1);
      await assert.rejects(as(merchant,'delivery_market_media_reserve',[shop.id,'d'.repeat(64),1]),e=>e.code==='PT409');
    } finally {await cleanup();}
  });
  await check('P1 reapplying configured catalog migration preserves live option data and return identities',async()=>{
    const before=(await db.query('select line_id,quantity,reason from delivery_market_returns where order_id=$1 order by line_id',[order.id])).rows;
    await db.query(await readFile(new URL('../../../database/migrations/20261106_catalog_configuration.sql',import.meta.url),'utf8'));
    assert.deepEqual((await db.query('select line_id,quantity,reason from delivery_market_returns where order_id=$1 order by line_id',[order.id])).rows,before);
    assert.deepEqual((await ops(buyer,'product_details',{product_id:product.id})).product.option_groups,groups);
  });
}
