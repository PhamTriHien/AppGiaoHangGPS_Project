import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

export async function testCommercialSuite({ db, as, rpc, operator, merchant, driver, secondDriver, buyers, shop, check, authenticatedQuery }) {
  const ops = (id, action, data = {}) => as(id, 'delivery_market_operations', [action, data]);

  await check('P1-P6 reapplying 20261107_cloud_commercial_suite preserves live orders and verifies deployment schema', async () => {
    for (const file of [
      '20261107_cloud_commercial_suite',
      '20261108_cloud_logistics',
      '20261109_admin_account_management',
      '20261110_cloud_promo_events',
      '20261111_profile_push_shipping_coins',
      '20261112_shipping_cash_settlement',
      '20261113_cloud_sync_and_journey',
      '20261114_merchant_cloud_suite',
      '20261115_cross_role_linkage_complete',
    ]) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`, import.meta.url), 'utf8'));
    }
    const { DEPLOYMENT_SCHEMA_SQL } = await import('../deployment-readiness.mjs');
    const schema = (await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for (const [key, value] of Object.entries(schema)) assert.equal(value, true, `schema ${key}`);
  });

  const staffManager = buyers[2];
  const staffClerk = buyers[3];
  const busyDrivers = new Set((await db.query("select driver_id from delivery_cloud_orders where status in ('accepted','arrivingPickup','inTransit','returning') and driver_id is not null")).rows.map(r => r.driver_id));
  const freeDriver = [driver, secondDriver].find(d => !busyDrivers.has(d)) ?? secondDriver;
  let skuProduct, smallVar, largeVar;

  await check('P1 shop banner, service radius, staff delegation and multi-SKU variant concurrency', async () => {
    const curShop = (await db.query('select * from delivery_market_shops where id=$1', [shop.id])).rows[0];
    const updatedShop = (await rpc(merchant, 'shop_save', {
      name: curShop.name, description: 'Full cloud suite', address: curShop.address,
      latitude: curShop.latitude, longitude: curShop.longitude, paused: false, version: curShop.version,
      banner_url: 'https://example.test/banner.webp', service_radius_km: 25,
    })).shop;
    assert.equal(updatedShop.banner_url, 'https://example.test/banner.webp');
    assert.equal(Number(updatedShop.service_radius_km), 25);

    await rpc(merchant, 'staff_save', { shop_id: shop.id, user_id: staffManager, role: 'manager', active: true });
    await rpc(merchant, 'staff_save', { shop_id: shop.id, user_id: staffClerk, role: 'staff', active: true });

    const profileSnap = await as(staffManager, 'delivery_cloud_profile');
    assert.ok(profileSnap.account.staff_shops.some(s => s.shop_id === shop.id && s.role === 'manager'));

    // Clerk cannot edit catalog, delegated manager can
    const pid = randomUUID();
    await assert.rejects(rpc(staffClerk, 'product_save', {
      id: pid, shop_id: shop.id, name: 'SKU Product', description: '', category: 'Fashion',
      sku: 'SKU-BASE', price: 100000, stock: 0, weight_kg: 0.5, length_cm: 20, width_cm: 15, height_cm: 10, published: true,
    }), e => e.code === 'PT403');

    skuProduct = (await rpc(staffManager, 'product_save', {
      id: pid, shop_id: shop.id, name: 'SKU Product', description: '', category: 'Fashion',
      sku: 'SKU-BASE', price: 100000, stock: 0, weight_kg: 0.5, length_cm: 20, width_cm: 15, height_cm: 10, published: true,
    })).product;

    smallVar = (await rpc(staffManager, 'variant_save', {
      product_id: skuProduct.id, sku: 'SKU-S', title: 'Size S', price: 95000, stock: 2,
      weight_kg: 0.4, length_cm: 20, width_cm: 15, height_cm: 10, published: true,
    })).variant;
    largeVar = (await rpc(staffManager, 'variant_save', {
      product_id: skuProduct.id, sku: 'SKU-L', title: 'Size L', price: 120000, stock: 5,
      weight_kg: 0.6, length_cm: 30, width_cm: 20, height_cm: 15, published: true,
    })).variant;

    // Far buyer outside 25km radius is filtered in browse and blocked in quote
    const browseNear = await as(buyers[0], 'delivery_market_browse', [{ shop_id: shop.id, search: 'SKU Product', buyer_lat: 10.78, buyer_lng: 106.71 }]);
    assert.equal(browseNear.shop_meta.banner_url, 'https://example.test/banner.webp');
    assert.ok(browseNear.products.some(p => p.id === skuProduct.id && p.variants_count === 2));
    const browseFar = await as(buyers[0], 'delivery_market_browse', [{ shop_id: shop.id, search: 'SKU Product', buyer_lat: 21.0285, buyer_lng: 105.8542 }]);
    assert.equal(browseFar.products.length, 0);

    // 4 concurrent buyers racing for 2 units of Size S
    const racers = [buyers[0], buyers[1], buyers[4], buyers[5]];
    const varQuotes = [];
    for (const b of racers) {
      let c = await rpc(b, 'cart');
      for (const it of c.items) c = await rpc(b, 'cart_set', { product_id: it.id, line_id: it.line_id, quantity: 0, version: c.version });
      await rpc(b, 'cart_set', { product_id: skuProduct.id, variant_id: smallVar.id, quantity: 1, version: c.version });
      const addr = (await as(b, 'delivery_cloud_addresses_manage')).addresses[0];
      varQuotes.push((await rpc(b, 'quote', { address_id: addr.id })).quote);
    }
    const raced = await Promise.allSettled(racers.map((b, i) => rpc(b, 'checkout', { quote_id: varQuotes[i].id, request_key: randomUUID() })));
    assert.equal(raced.filter(r => r.status === 'fulfilled').length, 2);
    assert.equal(raced.filter(r => r.status === 'rejected').length, 2);
    assert.equal((await db.query('select stock from delivery_market_variants where id=$1', [smallVar.id])).rows[0].stock, 0);
  });

  await check('P2 5-mode shipping quote, volumetric weight, multi-stop, insurance, round-trip & EV CO2', async () => {
    const baseDetails = {
      pickup_address: '12 Nguyen Hue Q1', dropoff_address: '20 Le Loi Q1',
      recipient_name: 'Buyer', recipient_phone: '0912345678', package_description: 'Fragile electronics',
      pickup_lat: 10.77, pickup_lng: 106.70, dropoff_lat: 10.80, dropoff_lng: 106.73,
      weight_kg: 2, length_cm: 50, width_cm: 40, height_cm: 30, // volumetric = 12 kg > 2 kg
      declared_value: 10000000, is_round_trip: true, prefer_ev: true, green_fund: true,
      extra_stops: [{ address: '45 Pasteur Q1', lat: 10.778, lng: 106.698 }],
      service_type: 'same_day_2h', payment_method: 'sender_cash', cod_amount: 0,
      require_pod: true, require_otp: true,
    };
    const q = await as(buyers[4], 'delivery_cloud_quote', [baseDetails]);
    assert.equal(Number(q.volumetric_weight_kg), 12);
    assert.equal(Number(q.effective_weight_kg), 12);
    assert.equal(q.stop_count, 1);
    assert.ok(q.estimated_co2_saved_grams > 0);
    assert.equal(q.breakdown.stop_fee, 5000);
    assert.equal(q.breakdown.insurance_fee, 50000);
    assert.equal(q.breakdown.green_fee, 1000);
    assert.equal(q.shipping_fee, Object.values(q.breakdown).reduce((s, v) => s + v, 0));

    // Truck supports >30kg while standard rejects >30kg
    await assert.rejects(as(buyers[4], 'delivery_cloud_quote', [{ ...baseDetails, weight_kg: 120, service_type: 'standard' }]), e => e.code === 'PT400');
    const truckQuote = await as(buyers[4], 'delivery_cloud_quote', [{ ...baseDetails, weight_kg: 120, service_type: 'truck' }]);
    assert.equal(truckQuote.service_type, 'truck');
    assert.equal(truckQuote.shipping_fee, Object.values(truckQuote.breakdown).reduce((s, v) => s + v, 0));
  });

  await check('P4 server GPS jump guard, POD requirement, recipient OTP gate & public lookup', async () => {
    // Finish any active trip for secondDriver first
    const openTrips = (await db.query("select id,version,status from delivery_cloud_orders where driver_id=$1 and status not in ('delivered','returned','cancelled')", [secondDriver])).rows;
    for (const t of openTrips) {
      let cur = t;
      for (const act of ['arrive', 'pickup', 'deliver']) {
        cur = await as(operator, 'delivery_cloud_transition', [cur.id, act, cur.version, randomUUID(), '']);
      }
    }

    const details = {
      pickup_address: '12 Nguyen Hue Q1', dropoff_address: '20 Le Loi Q1',
      recipient_name: 'OTP Receiver', recipient_phone: '0987654321', package_description: 'OTP & POD parcel',
      pickup_lat: 10.77, pickup_lng: 106.70, dropoff_lat: 10.78, dropoff_lng: 106.71,
      weight_kg: 1, cod_amount: 0, service_type: 'express', payment_method: 'sender_cash',
      require_pod: true, require_otp: true,
    };
    const q = await as(buyers[4], 'delivery_cloud_quote', [details]);
    let ord = await as(buyers[4], 'delivery_cloud_create', [details, randomUUID(), q.pricing_version, q.shipping_fee]);

    // Driver cannot read recipient OTP; sender can
    ord = await as(freeDriver, 'delivery_cloud_transition', [ord.id, 'claim', ord.version, randomUUID(), '']);
    await assert.rejects(as(freeDriver, 'delivery_cloud_order_otp', [ord.id]), e => e.code === 'PT403');
    const otpInfo = await as(buyers[4], 'delivery_cloud_order_otp', [ord.id]);
    assert.equal(otpInfo.required, true);
    assert.match(otpInfo.otp_code, /^[0-9]{6}$/);

    ord = await as(freeDriver, 'delivery_cloud_transition', [ord.id, 'arrive', ord.version, randomUUID(), '']);
    ord = await as(freeDriver, 'delivery_cloud_transition', [ord.id, 'pickup', ord.version, randomUUID(), '']);

    // Valid GPS vs teleport jump (>120 km/h)
    const t0 = Date.now();
    await authenticatedQuery(freeDriver, 'insert into delivery_live_events(room_id,kind,payload) values($1,$2,$3)', [
      ord.tracking_code, 'gps', JSON.stringify({ latitude: 10.77, longitude: 106.70, timestamp_ms: t0 }),
    ]);
    await assert.rejects(authenticatedQuery(freeDriver, 'insert into delivery_live_events(room_id,kind,payload) values($1,$2,$3)', [
      ord.tracking_code, 'gps', JSON.stringify({ latitude: 10.90, longitude: 106.90, timestamp_ms: t0 + 1000 }),
    ]));

    // Deliver without POD fails
    await assert.rejects(as(freeDriver, 'delivery_cloud_transition', [ord.id, 'deliver', ord.version, randomUUID(), otpInfo.otp_code]), e => e.code === 'PT409');

    // Upload POD object + live event, then wrong OTP fails, right OTP succeeds and scrubs history!
    const podPath = `${ord.tracking_code}/pod-${'e'.repeat(64)}.webp`;
    await authenticatedQuery(freeDriver, "insert into storage.objects(bucket_id,name) values('delivery-evidence',$1)", [podPath]);
    await authenticatedQuery(freeDriver, "insert into delivery_live_events(room_id,kind,payload) values($1,'pod',$2)", [
      ord.tracking_code, JSON.stringify({ path: podPath }),
    ]);
    await assert.rejects(as(freeDriver, 'delivery_cloud_transition', [ord.id, 'deliver', ord.version, randomUUID(), '000000']), e => e.code === 'PT409');
    ord = await as(freeDriver, 'delivery_cloud_transition', [ord.id, 'deliver', ord.version, randomUUID(), otpInfo.otp_code]);
    assert.equal(ord.status, 'delivered');

    const hist = await as(buyers[4], 'delivery_cloud_history_read', [ord.id]);
    assert.equal(JSON.stringify(hist).includes(otpInfo.otp_code), false);

    // Public cloud lookup + standalone share token
    await assert.rejects(as(buyers[4], 'delivery_cloud_public_lookup', [ord.tracking_code, '0000']), e => e.code === 'PT404');
    const pub = await as(buyers[4], 'delivery_cloud_public_lookup', [ord.tracking_code, '4321']);
    assert.equal(pub.status, 'delivered');
    assert.equal('recipient_phone' in pub, false);

    const share = await as(buyers[4], 'delivery_cloud_share_manage', [ord.id, 'create', null]);
    const sharedView = await as(buyers[0], 'delivery_market_public_tracking', [share.token]);
    assert.equal(sharedView.delivery_status, 'delivered');

    // Driver partner review
    const dRev = await ops(buyers[4], 'partner_review_save', { target_kind: 'driver', cloud_order_id: ord.id, rating: 5, body: 'Giao nhanh đúng hẹn' });
    assert.equal(dRev.partner_review.rating, 5);
  });

  await check('P3, P5 & P6 vouchers, flash sales, prepaid capture, coins, private attachments, return restock & analytics', async () => {
    const starts = new Date(Date.now() - 60000).toISOString();
    const ends = new Date(Date.now() + 3600000).toISOString();

    // Platform voucher with tight budget (only 1 buyer of 15,000 VND can claim)
    await rpc(operator, 'voucher_save', {
      code: 'PLAT15K', title: 'Giảm 15K toàn sàn', discount_kind: 'fixed', discount_value: 15000,
      max_discount: 15000, min_subtotal: 50000, budget_total: 15000, per_user_limit: 1, starts_at: starts, ends_at: ends, active: true,
    });
    // Flash sale on largeVar's parent product (120,000 -> 80,000, allocated_stock = 1)
    await rpc(staffManager, 'flash_sale_save', {
      product_id: skuProduct.id, sale_price: 80000, allocated_stock: 1, per_user_limit: 1, starts_at: starts, ends_at: ends, active: true,
    });

    // Two buyers race on the single voucher & flash sale slot with prepaid payment_method
    const raceBuyers = [buyers[5], buyers[6]];
    const pQuotes = [];
    for (const b of raceBuyers) {
      let c = await rpc(b, 'cart');
      for (const it of c.items) c = await rpc(b, 'cart_set', { product_id: it.id, line_id: it.line_id, quantity: 0, version: c.version });
      await rpc(b, 'cart_set', { product_id: skuProduct.id, variant_id: largeVar.id, quantity: 1, version: c.version });
      const addr = (await as(b, 'delivery_cloud_addresses_manage')).addresses[0];
      pQuotes.push((await rpc(b, 'quote', {
        address_id: addr.id, voucher_code: 'PLAT15K', payment_method: 'prepaid', service_type: 'saving', buyer_note: 'Gọi trước khi giao',
      })).quote);
    }
    assert.equal(pQuotes[0].snapshot.voucher_discount, 15000);
    assert.equal(pQuotes[0].snapshot.shops[0].subtotal, 80000);

    const pRaced = await Promise.allSettled(raceBuyers.map((b, i) => rpc(b, 'checkout', { quote_id: pQuotes[i].id, request_key: randomUUID() })));
    assert.equal(pRaced.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(pRaced.filter(r => r.status === 'rejected').length, 1);

    const winIdx = pRaced.findIndex(r => r.status === 'fulfilled');
    const pBuyer = raceBuyers[winIdx];
    const purchase = pRaced[winIdx].value.purchase;
    const pOrder = (await rpc(pBuyer, 'orders')).orders.find(o => o.purchase_id === purchase.id);

    // Merchant cannot accept unpaid prepaid order yet
    await assert.rejects(rpc(staffClerk, 'order_action', { order_id: pOrder.id, version: pOrder.version, action: 'accept' }), e => e.code === 'PT409');

    // Simulate backend payOS capture inside transaction -> double-entry ledger balances to 0!
    const capStatus = (await db.query('select public.delivery_market_record_prepaid_capture($1,$2) as s', [purchase.id, 'PAYOS-REF-1'])).rows[0].s;
    assert.equal(capStatus, 'PAID');
    const unbal = (await db.query('select journal_id,sum(amount)::bigint bal from delivery_market_ledger group by journal_id having sum(amount)<>0')).rows;
    assert.equal(unbal.length, 0);

    // Staff clerk accepts, manager splits into 2 parcels (prepaid COD = 0)
    let curOrd = (await rpc(staffClerk, 'order_action', { order_id: pOrder.id, version: pOrder.version, action: 'accept' })).order;
    curOrd = (await rpc(staffManager, 'order_shipment_split', {
      order_id: curOrd.id, version: curOrd.version,
      parcels: [{ weight_kg: 0.3, cod_amount: 0 }, { weight_kg: 0.3, cod_amount: 0 }],
    })).order;
    assert.equal(curOrd.state, 'ready');
    const shipments = (await db.query('select delivery_id from delivery_market_shipments where order_id=$1 order by parcel_index', [curOrd.id])).rows;
    assert.equal(shipments.length, 2);

    // Delivering parcel 1 alone does NOT mark shop order delivered; delivering parcel 2 marks delivered_at!
    for (const [idx, sRow] of shipments.entries()) {
      const co = (await db.query('select id,version from delivery_cloud_orders where id=$1', [sRow.delivery_id])).rows[0];
      let step = co;
      for (const act of ['claim', 'arrive', 'pickup', 'deliver']) {
        step = await as(freeDriver, 'delivery_cloud_transition', [step.id, act, step.version, randomUUID(), '']);
      }
      const deliveredAt = (await db.query('select delivered_at from delivery_market_shop_orders where id=$1', [curOrd.id])).rows[0].delivered_at;
      if (idx === 0) assert.equal(deliveredAt, null);
      else assert.notEqual(deliveredAt, null);
    }

    // Private evidence attachment RLS: buyer reserves + uploads, merchant can read, unrelated buyer[0] cannot!
    const attHash = 'f'.repeat(64);
    const attRes = await as(pBuyer, 'delivery_market_attachment_reserve', [curOrd.id, 'return', attHash, 512]);
    await authenticatedQuery(pBuyer, 'insert into storage.objects(bucket_id,name) values($1,$2)', [attRes.bucket, attRes.name]);
    const canMerchantRead = (await authenticatedQuery(staffClerk, "select count(*)::int n from storage.objects where bucket_id='delivery-private-evidence' and name=$1", [attRes.name])).rows[0].n;
    const canStrangerRead = (await authenticatedQuery(buyers[0], "select count(*)::int n from storage.objects where bucket_id='delivery-private-evidence' and name=$1", [attRes.name])).rows[0].n;
    assert.equal(canMerchantRead, 1);
    assert.equal(canStrangerRead, 0);

    // Return with reverse shipment & restock disposition restores variant stock!
    const stockBefore = (await db.query('select stock from delivery_market_variants where id=$1', [largeVar.id])).rows[0].stock;
    const snapItem = curOrd.snapshot.items[0];
    let ret = (await ops(pBuyer, 'return_request', {
      order_id: curOrd.id, product_id: snapItem.product_id, line_id: snapItem.line_id,
      quantity: 1, reason: 'Đổi size', attachments: [attRes.name], request_key: randomUUID(),
    })).return;
    ret = (await ops(staffManager, 'return_action', {
      order_id: curOrd.id, id: ret.id, version: ret.version, action: 'approve', response: 'Đồng ý thu hồi', create_return_shipment: true,
    })).return;
    assert.ok(ret.return_delivery_id);
    ret = (await ops(staffManager, 'return_action', {
      order_id: curOrd.id, id: ret.id, version: ret.version, action: 'receive', response: 'Đã nhập lại kho', disposition: 'restock',
    })).return;
    assert.equal(ret.disposition, 'restock');
    const stockAfter = (await db.query('select stock from delivery_market_variants where id=$1', [largeVar.id])).rows[0].stock;
    assert.equal(stockAfter, stockBefore + 1);

    // Shop follow + shop partner review + reply + report + moderation + admin analytics
    const follow = await ops(pBuyer, 'shop_follow_set', { shop_id: shop.id, enabled: true });
    assert.equal(follow.following, true);
    const sRev = (await ops(pBuyer, 'partner_review_save', { target_kind: 'shop', order_id: curOrd.id, rating: 5, body: 'Shop hỗ trợ đổi hàng rất tốt' })).partner_review;
    const replied = (await ops(staffClerk, 'review_reply', { review_kind: 'partner', id: sRev.id, reply: 'Cảm ơn quý khách đã ủng hộ!' })).partner_review;
    assert.equal(replied.reply, 'Cảm ơn quý khách đã ủng hộ!');
    await ops(buyers[0], 'review_report', { review_kind: 'partner', id: sRev.id, reason: 'Kiểm tra luồng báo cáo' });

    const analytics = await ops(operator, 'admin_analytics');
    assert.ok(analytics.cloud_orders.total >= 1);
    assert.equal(analytics.reported_reviews >= 1, true);
    await ops(operator, 'review_moderate', { review_kind: 'partner', id: sRev.id, hidden: true, reason: 'Ẩn sau kiểm tra' });
  });
}
