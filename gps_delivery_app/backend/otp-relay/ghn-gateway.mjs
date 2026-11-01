import crypto from 'node:crypto';
import express from 'express';
import { IntegrationError, providerJson } from './provider-http.mjs';
import { configValue, providerConfigured } from './integration-config.mjs';
import { createCommerceDatabase, cloudActor, ownedOrder, orderId } from './commerce-db.mjs';

const shipmentDto = s => s ? Object.fromEntries(['order_id','ghn_order_code','client_order_code','status','total_fee','expected_delivery_time','updated_at']
  .map(key => [key,s[key]])) : null;
export function secretMatches(received, expected) {
  const a=Buffer.from(String(received ?? '')), b=Buffer.from(String(expected ?? ''));
  return b.length>0 && a.length===b.length && crypto.timingSafeEqual(a,b);
}
export function buildGhnPayload(order, fields) {
  if (!fields || typeof fields!=='object' || Array.isArray(fields)) throw new IntegrationError(400,'Cần thông tin kiện hàng GHN.');
  const payload = {};
  for (const key of ['from_province_name','from_ward_name','to_province_name','to_ward_name']) {
    if(typeof fields[key]!=='string' || !fields[key].trim() || fields[key].length>200) throw new IntegrationError(400,'Cần tỉnh/thành và phường/xã hai cấp cho điểm lấy/giao.');
    payload[key]=fields[key].trim();
  }
  for (const key of ['length','width','height']) {
    if(!Number.isInteger(fields[key]) || fields[key]<1 || fields[key]>200) throw new IntegrationError(400,'Kích thước GHN phải từ 1 đến 200 cm.');
    payload[key]=fields[key];
  }
  if (!['KHONGCHOXEMHANG','CHOXEMHANGKHONGTHU','CHOTHUHANG'].includes(fields.required_note)) throw new IntegrationError(400,'Cần chọn quy định xem hàng.');
  const details=order.details;
  const weight=Math.ceil(Number(details.weight_kg)*1000);
  if (!Number.isSafeInteger(weight) || weight<1 || weight>50000) throw new IntegrationError(400,'Khối lượng GHN không hợp lệ.');
  return { ...payload, is_new_to_address:true, is_new_from_address:true, weight,
    to_name:details.recipient_name,to_phone:details.recipient_phone,to_address:details.dropoff_address,
    from_name:order.sender_name,from_phone:order.sender_phone,from_address:details.pickup_address,
    content:details.package_description,service_type_id:weight<20000?2:5,payment_type_id:1,
    cod_amount:order.cod_amount,required_note:fields.required_note,client_order_code:`GHST-${order.id.replaceAll('-','')}` };
}
const stateMap = {
  ready_to_pick:'searching',picking:'accepted',money_collect_picking:'accepted',picked:'inTransit',storing:'inTransit',
  transporting:'inTransit',sorting:'inTransit',delivering:'inTransit',money_collect_delivering:'inTransit',
  delivered:'delivered',delivery_fail:'failed',waiting_to_return:'returning',return:'returning',returning:'returning',
  return_transporting:'returning',return_sorting:'returning',returned:'returned',cancel:'cancelled',lost:'failed',damage:'failed',
};

export function createGhnGateway({ env=process.env,authenticate,database=createCommerceDatabase(env),fetcher=fetch }={}) {
  const router=express.Router();
  const route=fn=>(req,res,next)=>Promise.resolve(fn(req,res)).catch(next);
  function settings(settlement=false) {
    const keysReady=['GHN_TOKEN','GHN_SHOP_ID'].every(key=>env[key]?.trim());
    if(!keysReady || (!settlement && !providerConfigured('ghn',env))) throw new IntegrationError(503,'GHN đang tắt hoặc chưa đủ cấu hình.');
    const base=new URL(configValue('GHN_BASE_URL',env));
    if(base.protocol!=='https:' || !['dev-online-gateway.ghn.vn','online-gateway.ghn.vn'].includes(base.hostname) || base.pathname!=='/shiip/public-api/' || base.port || base.username || base.password || base.search || base.hash) throw new IntegrationError(503,'Endpoint GHN không hợp lệ.');
    if(!/^\d{1,12}$/.test(env.GHN_SHOP_ID || '')) throw new IntegrationError(503,'Shop ID GHN không hợp lệ.');
    return { base:base.href,shop:env.GHN_SHOP_ID };
  }
  async function call(path,body,settlement=false) {
    const config=settings(settlement);
    const data=await providerJson(new URL(path,config.base),{method:body?'POST':'GET',
      headers:{Token:env.GHN_TOKEN,ShopId:config.shop,'Content-Type':'application/json'},
      ...(body?{body:JSON.stringify(body)}:{})},fetcher);
    if(data.code!==200 || !data.data || typeof data.data!=='object') throw new IntegrationError(502,'GHN chưa trả kết quả hợp lệ.');
    return data.data;
  }
  function sameProvider(shipment) {
    const current=settings(true);
    if(shipment.base_url!==current.base || shipment.shop_id!==current.shop) throw new IntegrationError(409,'Cấu hình GHN đã đổi. Cần dùng đúng shop/môi trường của vận đơn.');
  }
  async function synchronize(shipment,detail,eventKey) {
    sameProvider(shipment);
    if(detail.client_order_code!==shipment.client_order_code || String(detail.shop_id)!==shipment.shop_id ||
      typeof detail.order_code!=='string' || !/^[A-Z0-9-]{1,40}$/.test(detail.order_code) ||
      (shipment.ghn_order_code && detail.order_code!==shipment.ghn_order_code) ||
      typeof detail.status!=='string' || detail.status.length>80 || !Number.isFinite(Date.parse(detail.updated_date))) throw new IntegrationError(502,'Thông tin GHN không khớp vận đơn đã lưu.');
    return database.transaction(async db=>{
      const order=(await db.query('select * from public.delivery_cloud_orders where id=$1 for update',[shipment.order_id])).rows[0];
      const current=(await db.query('select * from public.delivery_ghn_shipments where order_id=$1 for update',[shipment.order_id])).rows[0];
      if(eventKey) await db.query('insert into public.delivery_ghn_events(event_key,shipment_id) values($1,$2) on conflict do nothing',[eventKey,current.id]);
      if(current.provider_updated_at && Date.parse(detail.updated_date)<=new Date(current.provider_updated_at).getTime()) return current;
      const updated=(await db.query(`update public.delivery_ghn_shipments set ghn_order_code=$1,status=$2,
        provider_updated_at=$3,expected_delivery_time=$4,updated_at=now() where id=$5 returning *`,
      [detail.order_code,detail.status,detail.updated_date,Number.isFinite(Date.parse(detail.leadtime))?detail.leadtime:null,current.id])).rows[0];
      const next=stateMap[detail.status] ?? order.status;
      await db.query("set local ghst.carrier_sync='on'");
      await db.query(`update public.delivery_cloud_orders set carrier_code=$1,carrier_status=$2,status=$3,
        version=version+1,updated_at=now() where id=$4`,[detail.order_code,detail.status,next,order.id]);
      await db.query(`insert into public.delivery_cloud_history(order_id,actor_id,action,status,version,reason)
        values($1,$2,'ghn_sync',$3,$4,$5)`,[order.id,current.created_by,next,order.version+1,detail.status]);
      return updated;
    });
  }
  async function refresh(shipment,eventKey) {
    sameProvider(shipment);
    if(!shipment.ghn_order_code) throw new IntegrationError(409,'GHN chưa xác nhận mã vận đơn. Thử tạo lại với báo giá cũ.');
    const detail=await call(`v2/shipping-order/detail?order_code=${encodeURIComponent(shipment.ghn_order_code)}`,undefined,true);
    return synchronize(shipment,detail,eventKey);
  }
  router.post('/webhooks/ghn',route(async(req,res)=>{
    if(!secretMatches(req.get('x-ghn-webhook-secret'),env.GHN_WEBHOOK_SECRET)) throw new IntegrationError(401,'Webhook GHN không hợp lệ.');
    const e=req.body;
    if(!e || typeof e.OrderCode!=='string' || !/^[A-Z0-9-]{1,40}$/.test(e.OrderCode) || typeof e.Type!=='string' || e.Type.length>80 || !Number.isFinite(Date.parse(e.Time)) || String(e.ShopID)!==settings(true).shop) throw new IntegrationError(400,'Dữ liệu webhook GHN không hợp lệ.');
    const key=crypto.createHash('sha256').update(JSON.stringify([e.OrderCode,e.Type,e.Time])).digest('hex');
    const existing=await database.query('select event_key from public.delivery_ghn_events where event_key=$1',[key]);
    if(existing.rows.length) return res.json({accepted:true,duplicate:true});
    const shipment=(await database.query('select * from public.delivery_ghn_shipments where ghn_order_code=$1 or client_order_code=$2',[e.OrderCode,e.ClientOrderCode ?? ''])).rows[0];
    if(!shipment) return res.json({accepted:false});
    // Re-read GHN: callback payloads never directly change delivery or COD state.
    const detail=await call(`v2/shipping-order/detail?order_code=${encodeURIComponent(e.OrderCode)}`,undefined,true);
    await synchronize(shipment,detail,key);
    res.json({accepted:true});
  }));
  router.use('/cloud/orders/:id/shipment',authenticate,(req,_res,next)=>{
    try { cloudActor(req); next(); } catch(error) { next(error); }
  });
  router.get('/cloud/orders/:id/shipment',route(async(req,res)=>{
    await ownedOrder(database,req,req.params.id);
    const shipment=(await database.query('select * from public.delivery_ghn_shipments where order_id=$1',[req.params.id])).rows[0];
    res.json({configured:providerConfigured('ghn',env),shipment:shipmentDto(shipment)});
  }));
  router.post('/cloud/orders/:id/shipment/preview',route(async(req,res)=>{
    const config=settings();
    const order=await ownedOrder(database,req,req.params.id,{operator:true});
    if(order.status!=='searching' || order.driver_id || order.fulfillment_provider) throw new IntegrationError(409,'Chỉ chuyển GHN cho đơn chưa điều phối.');
    const payload=buildGhnPayload(order,req.body);
    const preview=await call('v2/shipping-order/preview',payload);
    if(!Number.isSafeInteger(preview.total_fee) || preview.total_fee<0) throw new IntegrationError(502,'GHN không trả cước hợp lệ.');
    const quote=(await database.query(`insert into public.delivery_ghn_quotes(order_id,order_version,created_by,payload,total_fee,base_url,shop_id)
      values($1,$2,$3,$4,$5,$6,$7) returning id,expires_at`,[order.id,order.version,cloudActor(req).id,payload,preview.total_fee,config.base,config.shop])).rows[0];
    res.json({quote_id:quote.id,expires_at:quote.expires_at,total_fee:preview.total_fee,expected_delivery_time:preview.expected_delivery_time ?? null});
  }));
  router.post('/cloud/orders/:id/shipment',route(async(req,res)=>{
    const config=settings();
    const shipment=await database.transaction(async db=>{
      const order=await ownedOrder(db,req,req.params.id,{lock:true,operator:true});
      const old=(await db.query('select * from public.delivery_ghn_shipments where order_id=$1',[order.id])).rows[0];
      if(old) { sameProvider(old); return old; }
      const quote=(await db.query('select * from public.delivery_ghn_quotes where id=$1 and order_id=$2',[orderId(req.body?.quote_id),order.id])).rows[0];
      if(!quote || quote.order_version!==order.version || new Date(quote.expires_at)<=new Date() || quote.base_url!==config.base || quote.shop_id!==config.shop) throw new IntegrationError(409,'Báo giá GHN đã hết hạn hoặc đơn đã đổi. Xem phí lại.');
      if(order.status!=='searching' || order.driver_id || order.fulfillment_provider) throw new IntegrationError(409,'Đơn đã được điều phối.');
      // This update also invokes the payment guard under the same order lock.
      await db.query("update public.delivery_cloud_orders set fulfillment_provider='ghn',merchant_ready=false,version=version+1,updated_at=now() where id=$1",[order.id]);
      await db.query("insert into public.delivery_cloud_history(order_id,actor_id,action,status,version,reason) values($1,$2,'ghn_reserve',$3,$4,'GHN')",[order.id,cloudActor(req).id,order.status,order.version+1]);
      return (await db.query(`insert into public.delivery_ghn_shipments(order_id,created_by,quote_id,client_order_code,payload,base_url,shop_id,total_fee)
        values($1,$2,$3,$4,$5,$6,$7,$8) returning *`,[order.id,cloudActor(req).id,quote.id,quote.payload.client_order_code,quote.payload,config.base,config.shop,quote.total_fee])).rows[0];
    });
    if(shipment.ghn_order_code) return res.json({shipment:shipmentDto(shipment)});
    // GHN documents client_order_code as its create retry/idempotency key.
    const result=await call('v2/shipping-order/create',shipment.payload);
    if(typeof result.order_code!=='string' || !/^[A-Z0-9-]{1,40}$/.test(result.order_code)) throw new IntegrationError(502,'GHN chưa xác nhận mã vận đơn. Thử lại sẽ dùng cùng mã shop.');
    const saved=await database.transaction(async db=>{
      await db.query('select id from public.delivery_cloud_orders where id=$1 for update',[shipment.order_id]);
      const updated=(await db.query(`update public.delivery_ghn_shipments set ghn_order_code=$1,
        total_fee=$2,expected_delivery_time=$3,updated_at=now() where id=$4 returning *`,
      [result.order_code,Number.isSafeInteger(result.total_fee)?result.total_fee:shipment.total_fee,Number.isFinite(Date.parse(result.expected_delivery_time))?result.expected_delivery_time:null,shipment.id])).rows[0];
      await db.query('update public.delivery_cloud_orders set carrier_code=$1,updated_at=now() where id=$2',[result.order_code,shipment.order_id]);
      return updated;
    });
    // A failure here keeps the created tracking code durable for later refresh.
    const detail=await refresh(saved);
    res.json({shipment:shipmentDto(detail)});
  }));
  router.post('/cloud/orders/:id/shipment/refresh',route(async(req,res)=>{
    await ownedOrder(database,req,req.params.id);
    const shipment=(await database.query('select * from public.delivery_ghn_shipments where order_id=$1',[req.params.id])).rows[0];
    if(!shipment) throw new IntegrationError(404,'Chưa có vận đơn GHN.');
    res.json({shipment:shipmentDto(await refresh(shipment))});
  }));
  router.post('/cloud/orders/:id/shipment/cancel',route(async(req,res)=>{
    await ownedOrder(database,req,req.params.id,{operator:true});
    const shipment=(await database.query('select * from public.delivery_ghn_shipments where order_id=$1',[req.params.id])).rows[0];
    if(!shipment?.ghn_order_code) throw new IntegrationError(409,'Chưa có mã vận đơn GHN.');
    sameProvider(shipment);
    const result=await call('v2/switch-status/cancel',{order_codes:[shipment.ghn_order_code]},true);
    const cancellation=Array.isArray(result)?result.find(item=>item.order_code===shipment.ghn_order_code):null;
    if(!cancellation) throw new IntegrationError(502,'GHN chưa trả kết quả hủy cho đúng vận đơn.');
    const updated=await refresh(shipment);
    if(cancellation.result!==true && updated.status!=='cancel') throw new IntegrationError(409,'GHN chưa chấp nhận hủy vận đơn. Trạng thái mới nhất đã được đồng bộ.');
    res.json({shipment:shipmentDto(updated)});
  }));
  return router;
}
