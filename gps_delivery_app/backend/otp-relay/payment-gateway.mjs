import express from 'express';
import { PayOS } from '@payos/node';
import { IntegrationError } from './provider-http.mjs';
import { configValue, providerConfigured } from './integration-config.mjs';
import { createCommerceDatabase, cloudActor, ownedOrder, ownedPurchase } from './commerce-db.mjs';
import { observeFetch } from './integration-monitor.mjs';

export const paymentDto = p => p ? {
  ...Object.fromEntries([
    'id','order_id','provider_order_code','amount','status','checkout_url','qr_code','expires_at','created_at',
  ].map(key => [key, p[key]])),
  ...(p.purchase_id ? { purchase_id: p.purchase_id } : {}),
} : null;

const orderPayableFee = order => Number(
  order.payable_fee ?? Math.max(0, Number(order.shipping_fee) - Number(order.coin_discount || 0)),
);

export function createPaymentGateway({ env = process.env, authenticate,
  database = createCommerceDatabase(env), clientFactory = () => new PayOS({
    clientId: env.PAYOS_CLIENT_ID, apiKey: env.PAYOS_API_KEY, checksumKey: env.PAYOS_CHECKSUM_KEY,
    baseURL: 'https://api-merchant.payos.vn', timeout: 10000, maxRetries: 0, logger: null,
    fetch: (url,options) => observeFetch('payos', () => fetch(url,{...options,redirect:'error'})),
  }),
} = {}) {
  const router = express.Router();
  const route = fn => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
  const ready = (settlement = false) => {
    const keysReady = ['PAYOS_CLIENT_ID','PAYOS_API_KEY','PAYOS_CHECKSUM_KEY'].every(key => env[key]?.trim());
    if (!keysReady || (!settlement && !providerConfigured('payos', env))) throw new IntegrationError(503, 'payOS đang tắt hoặc chưa đủ cấu hình.');
    if (!env.DATABASE_URL) throw new IntegrationError(503, 'Cần DATABASE_URL backend và migration thanh toán.');
  };
  async function paymentFor(req) {
    await ownedOrder(database, req, req.params.id);
    return (await database.query('select * from public.delivery_payment_transactions where order_id=$1 order by created_at desc,id desc limit 1', [req.params.id])).rows[0];
  }
  async function purchasePaymentFor(req) {
    const purchase = await ownedPurchase(database, req, req.params.id);
    const payment = (await database.query('select * from public.delivery_payment_transactions where purchase_id=$1 order by created_at desc,id desc limit 1', [purchase.id])).rows[0];
    return { purchase, payment };
  }
  async function createOrRecoverPayosLink(reserved) {
    const payos = clientFactory();
    let link;
    try {
      link = await payos.paymentRequests.create({
        orderCode: Number(reserved.provider_order_code), amount: reserved.amount,
        description: `GHST ${reserved.provider_order_code}`, cancelUrl: configValue('PAYOS_CANCEL_URL', env),
        returnUrl: configValue('PAYOS_RETURN_URL', env), expiredAt: Math.floor(new Date(reserved.expires_at).getTime() / 1000),
      });
    } catch {
      try {
        const recovered = await payos.paymentRequests.get(Number(reserved.provider_order_code));
        if (recovered.orderCode === Number(reserved.provider_order_code) && recovered.amount === reserved.amount && /^[a-zA-Z0-9-]{1,80}$/.test(recovered.id)) {
          link = { paymentLinkId: recovered.id, orderCode: recovered.orderCode, amount: recovered.amount,
            checkoutUrl: `https://pay.payos.vn/web/${recovered.id}`, qrCode: null };
        }
      } catch { /* Preserve CREATING for a safe retry and reconciliation. */ }
      if (!link) throw new IntegrationError(502, 'Chưa xác định được kết quả payOS. Thử lại sẽ dùng cùng mã thanh toán.');
    }
    const checkout = new URL(link.checkoutUrl);
    if (checkout.protocol !== 'https:' || checkout.hostname !== 'pay.payos.vn' || checkout.username || checkout.password ||
        link.orderCode !== Number(reserved.provider_order_code) || link.amount !== reserved.amount || !link.paymentLinkId) {
      throw new IntegrationError(502, 'Liên kết payOS không khớp yêu cầu.');
    }
    return { link, checkoutHref: checkout.href };
  }
  async function settle(data) {
    if (!Number.isSafeInteger(data.orderCode) || !Number.isSafeInteger(data.amount) || data.amount <= 0 ||
        data.currency !== 'VND' || typeof data.reference !== 'string' || !data.reference.trim() || data.reference.length > 200 ||
        typeof data.paymentLinkId !== 'string' || !data.paymentLinkId) throw new IntegrationError(400, 'Giao dịch payOS không hợp lệ.');
    return database.transaction(async db => {
      const payment = (await db.query('select * from public.delivery_payment_transactions where provider_order_code=$1', [data.orderCode])).rows[0];
      // payOS sends signed sample data when validating the callback URL.
      if (!payment) return { accepted: false, reason: 'unknown_order' };
      if (payment.purchase_id) {
        const purchase = (await db.query('select * from public.delivery_market_purchases where id=$1 for update', [payment.purchase_id])).rows[0];
        const current = (await db.query('select * from public.delivery_payment_transactions where id=$1 for update', [payment.id])).rows[0];
        if (current.payment_link_id && current.payment_link_id !== data.paymentLinkId) throw new IntegrationError(409, 'Mã liên kết thanh toán không khớp.');
        const previous = (await db.query('select * from public.delivery_payment_receipts where reference=$1', [data.reference])).rows[0];
        if (previous) {
          if (previous.payment_id !== current.id || Number(previous.amount) !== data.amount) throw new IntegrationError(409, 'Mã giao dịch trùng với dữ liệu khác.');
          return { accepted: true, duplicate: true, status: current.status };
        }
        await db.query('insert into public.delivery_payment_receipts(payment_id,reference,amount) values($1,$2,$3)', [current.id, data.reference, data.amount]);
        const total = Number((await db.query('select sum(amount) as amount from public.delivery_payment_receipts where payment_id=$1', [current.id])).rows[0].amount);
        let status = 'REVIEW';
        if (total === Number(current.amount) && Number(purchase.total) === total &&
            purchase.payment_method === 'prepaid' && !['CANCELLED','EXPIRED','REVIEW'].includes(current.status)) {
          status = (await db.query('select public.delivery_market_record_prepaid_capture($1,$2) as status', [purchase.id, data.reference])).rows[0].status;
        } else {
          await db.query("update public.delivery_market_purchases set payment_status='REVIEW' where id=$1", [purchase.id]);
        }
        await db.query('update public.delivery_payment_transactions set status=$1,payment_link_id=$2,updated_at=now() where id=$3', [status, data.paymentLinkId, current.id]);
        return { accepted: true, status };
      }
      const order = (await db.query('select * from public.delivery_cloud_orders where id=$1 for update', [payment.order_id])).rows[0];
      const current = (await db.query('select * from public.delivery_payment_transactions where id=$1 for update', [payment.id])).rows[0];
      if (current.payment_link_id && current.payment_link_id !== data.paymentLinkId) throw new IntegrationError(409, 'Mã liên kết thanh toán không khớp.');
      const previous = (await db.query('select * from public.delivery_payment_receipts where reference=$1', [data.reference])).rows[0];
      if (previous) {
        if (previous.payment_id !== current.id || Number(previous.amount) !== data.amount) throw new IntegrationError(409, 'Mã giao dịch trùng với dữ liệu khác.');
        return { accepted: true, duplicate: true, status: current.status };
      }
      await db.query('insert into public.delivery_payment_receipts(payment_id,reference,amount) values($1,$2,$3)', [current.id, data.reference, data.amount]);
      const total = Number((await db.query('select sum(amount) as amount from public.delivery_payment_receipts where payment_id=$1', [current.id])).rows[0].amount);
      const status = total === Number(current.amount) && orderPayableFee(order) === total &&
        !['cancelled','returned'].includes(order.status) && !['CANCELLED','EXPIRED','REVIEW'].includes(current.status) ? 'PAID' : 'REVIEW';
      await db.query('update public.delivery_payment_transactions set status=$1,payment_link_id=$2,updated_at=now() where id=$3', [status, data.paymentLinkId, current.id]);
      await db.query('update public.delivery_cloud_orders set payment_status=$1,updated_at=now() where id=$2', [status, current.order_id]);
      return { accepted: true, status };
    });
  }
  router.post('/payments/webhook', route(async (req, res) => {
    // Disabling new checkouts must not drop receipts for existing links.
    ready(true);
    let data;
    try { data = await clientFactory().webhooks.verify(req.body); }
    catch { throw new IntegrationError(400, 'Chữ ký webhook payOS không hợp lệ.'); }
    if (data.code !== '00') return res.json({ accepted: false });
    res.json(await settle(data));
  }));
  router.use('/cloud/orders/:id/payment', authenticate, (req, _res, next) => {
    try { cloudActor(req); next(); } catch (error) { next(error); }
  });
  router.get('/cloud/orders/:id/payment', route(async (req, res) => {
    const payment = await paymentFor(req);
    res.json({ configured: providerConfigured('payos', env), payment: paymentDto(payment) });
  }));
  router.post('/cloud/orders/:id/payment', route(async (req, res) => {
    ready();
    const reserved = await database.transaction(async db => {
      const order = await ownedOrder(db, req, req.params.id, { lock: true });
      if (req.deliveryIdentity.role !== 'operator' && order.owner_id !== req.deliveryIdentity.id) throw new IntegrationError(403, 'Chỉ chủ đơn hoặc operator được mở thanh toán.');
      if (order.payment_status !== 'UNPAID') throw new IntegrationError(409, 'Đơn đã thanh toán hoặc đang cần đối soát.');
      const payableFee = orderPayableFee(order);
      if (order.status !== 'searching' || order.driver_id || order.fulfillment_provider || order.details.payment_method !== 'sender_cash' || payableFee <= 0) {
        throw new IntegrationError(409, 'Thanh toán trước chỉ áp dụng đơn người gửi trả phí, chưa điều phối.');
      }
      const existing = (await db.query("select * from public.delivery_payment_transactions where order_id=$1 and status in ('CREATING','PENDING','PAID','REVIEW') for update", [order.id])).rows[0];
      if (existing) return existing;
      return (await db.query(`insert into public.delivery_payment_transactions(order_id,owner_id,amount,status)
        values($1,$2,$3,'CREATING') returning *`, [order.id, order.owner_id, payableFee])).rows[0];
    });
    if (reserved.checkout_url || ['PAID','REVIEW'].includes(reserved.status)) return res.json({ payment: paymentDto(reserved) });
    const { link, checkoutHref } = await createOrRecoverPayosLink(reserved);
    const payment = await database.transaction(async db => {
      await db.query('select id from public.delivery_cloud_orders where id=$1 for update', [reserved.order_id]);
      return (await db.query(`update public.delivery_payment_transactions set payment_link_id=$1,checkout_url=$2,qr_code=$3,
        status=case when status='CREATING' then 'PENDING' else status end,updated_at=now() where id=$4 returning *`,
      [link.paymentLinkId, checkoutHref, link.qrCode || null, reserved.id])).rows[0];
    });
    res.json({ payment: paymentDto(payment) });
  }));
  router.post('/cloud/orders/:id/payment/cancel', route(async (req, res) => {
    ready(true);
    const payment = await paymentFor(req);
    const actor = cloudActor(req);
    if (!payment || !['CREATING','PENDING'].includes(payment.status)) throw new IntegrationError(409, 'Không có liên kết chờ thanh toán.');
    if (actor.id !== payment.owner_id && actor.role !== 'operator') throw new IntegrationError(403, 'Không có quyền hủy thanh toán.');
    let result;
    try { result = await clientFactory().paymentRequests.cancel(Number(payment.provider_order_code), 'Khách hủy thanh toán'); }
    catch { throw new IntegrationError(502, 'Chưa xác nhận hủy từ payOS. Vui lòng thử lại.'); }
    if (result.orderCode !== Number(payment.provider_order_code) || (payment.payment_link_id && result.id!==payment.payment_link_id) || result.amount!==payment.amount || result.status !== 'CANCELLED' || result.amountPaid !== 0) throw new IntegrationError(409, 'Liên kết có giao dịch hoặc chưa được hủy. Cần đối soát.');
    const updated = await database.transaction(async db => {
      await db.query('select id from public.delivery_cloud_orders where id=$1 for update', [payment.order_id]);
      return (await db.query("update public.delivery_payment_transactions set status='CANCELLED',updated_at=now() where id=$1 and status in ('CREATING','PENDING') returning *", [payment.id])).rows[0];
    });
    res.json({ payment: paymentDto(updated ?? payment) });
  }));
  router.post('/cloud/orders/:id/payment/refresh', route(async(req,res) => {
    ready(true);
    const payment=await paymentFor(req);
    if(!payment) return res.json({payment:null});
    let result;
    try { result=await clientFactory().paymentRequests.get(Number(payment.provider_order_code)); }
    catch { throw new IntegrationError(502,'Không đối soát được với payOS. Vui lòng thử lại.'); }
    if(result.orderCode!==Number(payment.provider_order_code) || result.amount!==payment.amount ||
      (payment.payment_link_id && result.id!==payment.payment_link_id) || !Array.isArray(result.transactions) ||
      !Number.isSafeInteger(result.amountPaid) || result.amountPaid<0 ||
      result.transactions.reduce((sum,t)=>sum+t.amount,0)!==result.amountPaid) throw new IntegrationError(502,'Dữ liệu đối soát payOS không khớp.');
    for(const receipt of result.transactions) await settle({orderCode:result.orderCode,amount:receipt.amount,
      currency:'VND',reference:receipt.reference,paymentLinkId:result.id});
    if(['EXPIRED','CANCELLED'].includes(result.status) && result.amountPaid===0) {
      await database.transaction(async db=>{
        await db.query('select id from public.delivery_cloud_orders where id=$1 for update',[payment.order_id]);
        await db.query("update public.delivery_payment_transactions set status=$1,updated_at=now() where id=$2 and status in ('CREATING','PENDING')",[result.status,payment.id]);
      });
    }
    res.json({payment:paymentDto((await database.query('select * from public.delivery_payment_transactions where id=$1',[payment.id])).rows[0])});
  }));

  router.use('/cloud/purchases/:id/payment', authenticate, (req, _res, next) => {
    try { cloudActor(req); next(); } catch (error) { next(error); }
  });
  router.get('/cloud/purchases/:id/payment', route(async (req, res) => {
    const { purchase, payment } = await purchasePaymentFor(req);
    res.json({ configured: providerConfigured('payos', env), purchase_status: purchase.payment_status, payment: paymentDto(payment) });
  }));
  router.post('/cloud/purchases/:id/payment', route(async (req, res) => {
    ready();
    const reserved = await database.transaction(async db => {
      const purchase = await ownedPurchase(db, req, req.params.id, { lock: true });
      if (req.deliveryIdentity.role !== 'operator' && purchase.owner_id !== req.deliveryIdentity.id) {
        throw new IntegrationError(403, 'Chỉ người mua hoặc quản trị viên được mở thanh toán giỏ hàng.');
      }
      if (purchase.payment_method !== 'prepaid' || purchase.total <= 0) {
        throw new IntegrationError(409, 'Thanh toán trực tuyến chỉ áp dụng cho đơn mua trả trước.');
      }
      if (purchase.payment_status !== 'UNPAID') {
        throw new IntegrationError(409, 'Giao dịch mua hàng đã thanh toán hoặc đang cần đối soát.');
      }
      const cancelled = await db.query("select 1 from public.delivery_market_shop_orders where purchase_id=$1 and state='cancelled' limit 1", [purchase.id]);
      if (cancelled.rows.length) {
        throw new IntegrationError(409, 'Một đơn cửa hàng trong giỏ đã hủy, không thể tạo thanh toán gộp.');
      }
      const existing = (await db.query("select * from public.delivery_payment_transactions where purchase_id=$1 and status in ('CREATING','PENDING','PAID','REVIEW') for update", [purchase.id])).rows[0];
      if (existing) return existing;
      return (await db.query(`insert into public.delivery_payment_transactions(purchase_id,owner_id,amount,status)
        values($1,$2,$3,'CREATING') returning *`, [purchase.id, purchase.owner_id, purchase.total])).rows[0];
    });
    if (reserved.checkout_url || ['PAID','REVIEW'].includes(reserved.status)) return res.json({ payment: paymentDto(reserved) });
    const { link, checkoutHref } = await createOrRecoverPayosLink(reserved);
    const payment = await database.transaction(async db => {
      await db.query('select id from public.delivery_market_purchases where id=$1 for update', [reserved.purchase_id]);
      return (await db.query(`update public.delivery_payment_transactions set payment_link_id=$1,checkout_url=$2,qr_code=$3,
        status=case when status='CREATING' then 'PENDING' else status end,updated_at=now() where id=$4 returning *`,
      [link.paymentLinkId, checkoutHref, link.qrCode || null, reserved.id])).rows[0];
    });
    res.json({ payment: paymentDto(payment) });
  }));
  router.post('/cloud/purchases/:id/payment/cancel', route(async (req, res) => {
    ready(true);
    const { payment } = await purchasePaymentFor(req);
    const actor = cloudActor(req);
    if (!payment || !['CREATING','PENDING'].includes(payment.status)) throw new IntegrationError(409, 'Không có liên kết chờ thanh toán.');
    if (actor.id !== payment.owner_id && actor.role !== 'operator') throw new IntegrationError(403, 'Không có quyền hủy thanh toán.');
    let result;
    try { result = await clientFactory().paymentRequests.cancel(Number(payment.provider_order_code), 'Khách hủy thanh toán'); }
    catch { throw new IntegrationError(502, 'Chưa xác nhận hủy từ payOS. Vui lòng thử lại.'); }
    if (result.orderCode !== Number(payment.provider_order_code) || (payment.payment_link_id && result.id !== payment.payment_link_id) || result.amount !== payment.amount || result.status !== 'CANCELLED' || result.amountPaid !== 0) {
      throw new IntegrationError(409, 'Liên kết có giao dịch hoặc chưa được hủy. Cần đối soát.');
    }
    const updated = await database.transaction(async db => {
      await db.query('select id from public.delivery_market_purchases where id=$1 for update', [payment.purchase_id]);
      return (await db.query("update public.delivery_payment_transactions set status='CANCELLED',updated_at=now() where id=$1 and status in ('CREATING','PENDING') returning *", [payment.id])).rows[0];
    });
    res.json({ payment: paymentDto(updated ?? payment) });
  }));
  router.post('/cloud/purchases/:id/payment/refresh', route(async (req, res) => {
    ready(true);
    const { payment } = await purchasePaymentFor(req);
    if (!payment) return res.json({ payment: null });
    let result;
    try { result = await clientFactory().paymentRequests.get(Number(payment.provider_order_code)); }
    catch { throw new IntegrationError(502, 'Không đối soát được với payOS. Vui lòng thử lại.'); }
    if (result.orderCode !== Number(payment.provider_order_code) || result.amount !== payment.amount ||
        (payment.payment_link_id && result.id !== payment.payment_link_id) || !Array.isArray(result.transactions) ||
        !Number.isSafeInteger(result.amountPaid) || result.amountPaid < 0 ||
        result.transactions.reduce((sum, t) => sum + t.amount, 0) !== result.amountPaid) {
      throw new IntegrationError(502, 'Dữ liệu đối soát payOS không khớp.');
    }
    for (const receipt of result.transactions) {
      await settle({ orderCode: result.orderCode, amount: receipt.amount, currency: 'VND', reference: receipt.reference, paymentLinkId: result.id });
    }
    if (['EXPIRED','CANCELLED'].includes(result.status) && result.amountPaid === 0) {
      await database.transaction(async db => {
        await db.query('select id from public.delivery_market_purchases where id=$1 for update', [payment.purchase_id]);
        await db.query("update public.delivery_payment_transactions set status=$1,updated_at=now() where id=$2 and status in ('CREATING','PENDING')", [result.status, payment.id]);
      });
    }
    const refreshed = (await database.query('select * from public.delivery_payment_transactions where id=$1', [payment.id])).rows[0];
    const purchase = (await database.query('select payment_status from public.delivery_market_purchases where id=$1', [payment.purchase_id])).rows[0];
    res.json({ payment: paymentDto(refreshed), purchase_status: purchase?.payment_status });
  }));
  return router;
}
