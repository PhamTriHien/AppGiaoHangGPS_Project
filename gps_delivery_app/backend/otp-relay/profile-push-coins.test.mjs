import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { createHmac, randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { PayOS } from '@payos/node';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';
import { createNotificationRouter } from './delivery-notifications.mjs';
import { createPaymentGateway } from './payment-gateway.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from './deployment-readiness.mjs';

test('Profile birth_date & CCCD, unified notification center/push webhook, and shipping coin discounts work end-to-end', async t => {
  const db = new PGlite();
  t.after(() => db.close());

  await db.exec(`create role authenticated; create role anon;
    create schema auth;
    create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz default now(), created_at timestamptz default now(), raw_user_meta_data jsonb default '{}'::jsonb);
    create table auth.identities(id uuid default gen_random_uuid() primary key, user_id uuid references auth.users(id) on delete cascade, provider text not null);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
    alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated;
    grant select,insert on storage.objects to authenticated;
    create publication supabase_realtime;`);

  const files = [
    '20261027_delivery_integrations.sql',
    '20261028_cloud_orders.sql',
    '20261029_payments_ghn.sql',
    '20261029_cloud_addresses.sql',
    '20261030_marketplace.sql',
    '20261031_market_operations.sql',
    '20261101_partner_memberships.sql',
    '20261102_local_address_import.sql',
    '20261103_catalog_stock_versions.sql',
    '20261104_market_media.sql',
    '20261105_market_browse.sql',
    '20261106_catalog_configuration.sql',
    '20261107_cloud_commercial_suite.sql',
    '20261108_cloud_logistics.sql',
    '20261109_admin_account_management.sql',
    '20261110_cloud_promo_events.sql',
    '20261111_profile_push_shipping_coins.sql',
    '20261111_profile_push_shipping_coins.sql',
    '20261112_shipping_cash_settlement.sql',
  ];
  for (const file of files) {
    await db.exec(await readFile(new URL(`../../database/migrations/${file}`, import.meta.url), 'utf8'));
  }

  const schema = (await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
  assert.equal(schema.profile_push_coins_schema, true);

  const ids = {
    buyerA: randomUUID(),
    buyerB: randomUUID(),
    merchant: randomUUID(),
    driver: randomUUID(),
    operator: randomUUID(),
  };
  for (const [label, uid] of Object.entries(ids)) {
    await db.query('insert into auth.users(id, email) values($1, $2)', [uid, `${label}@example.com`]);
  }
  await db.query("insert into public.delivery_api_profiles(user_id, role) values($1, 'operator')", [ids.operator]);

  async function callRpc(actor, fn, argsObj = {}) {
    await db.exec('begin');
    try {
      await db.exec('set local role authenticated');
      await db.query("select set_config('request.jwt.claim.sub',$1,true)", [actor]);
      const keys = Object.keys(argsObj);
      const sql = keys.length === 0
        ? `select public.${fn}() as data`
        : `select public.${fn}(${keys.map((k, idx) => `${k} := $${idx + 1}`).join(', ')}) as data`;
      const vals = keys.map(k => (typeof argsObj[k] === 'object' && argsObj[k] !== null ? JSON.stringify(argsObj[k]) : argsObj[k]));
      const res = await db.query(sql, vals);
      await db.exec('commit');
      return res.rows[0]?.data;
    } catch (err) {
      await db.exec('rollback').catch(() => {});
      throw err;
    }
  }

  await t.test('Profile birth_date and 12-digit citizen_id validate strictly, enforce uniqueness, and stay private', async () => {
    await assert.rejects(
      callRpc(ids.buyerA, 'delivery_cloud_profile', {
        p_details: {
          full_name: 'Nguyễn Văn A',
          phone: '0901234567',
          requested_role: 'customer',
          birth_date: '2099-01-01',
          citizen_id: '079201001234',
        },
      }),
      e => e.code === 'PT400',
    );

    await assert.rejects(
      callRpc(ids.buyerA, 'delivery_cloud_profile', {
        p_details: {
          full_name: 'Nguyễn Văn A',
          phone: '0901234567',
          requested_role: 'customer',
          birth_date: '2001-05-19',
          citizen_id: '12345',
        },
      }),
      e => e.code === 'PT400',
    );

    const savedA = await callRpc(ids.buyerA, 'delivery_cloud_profile', {
      p_details: {
        full_name: 'Nguyễn Văn A',
        phone: '0901234567',
        requested_role: 'customer',
        birth_date: '2001-05-19',
        citizen_id: '079201001234',
      },
    });
    assert.equal(savedA.account.birth_date, '2001-05-19');
    assert.equal(savedA.account.citizen_id, '079201001234');
    assert.equal(savedA.account.identity_verified, true);

    const preserved = await callRpc(ids.buyerA, 'delivery_cloud_profile', {
      p_details: {
        full_name: 'Nguyễn Văn A Cập Nhật',
        phone: '0901234567',
        requested_role: 'customer',
      },
    });
    assert.equal(preserved.account.birth_date, '2001-05-19');
    assert.equal(preserved.account.citizen_id, '079201001234');

    await assert.rejects(
      callRpc(ids.buyerB, 'delivery_cloud_profile', {
        p_details: {
          full_name: 'Trần Thị B',
          phone: '0912345678',
          requested_role: 'customer',
          birth_date: '1999-10-20',
          citizen_id: '079201001234',
        },
      }),
      e => e.code === 'PT409',
    );

    await callRpc(ids.buyerB, 'delivery_cloud_profile', {
      p_details: {
        full_name: 'Trần Thị B',
        phone: '0912345678',
        requested_role: 'customer',
      },
    });
    await callRpc(ids.merchant, 'delivery_cloud_profile', {
      p_details: { full_name: 'Shop Minh Nhân', phone: '0933445566', requested_role: 'merchant' },
    });
    await callRpc(ids.driver, 'delivery_cloud_profile', {
      p_details: { full_name: 'Tài Xế GHST', phone: '0977889900', requested_role: 'driver' },
    });
    await callRpc(ids.operator, 'delivery_cloud_profile', {
      p_details: { full_name: 'Điều Hành', phone: '0988776655', requested_role: 'customer' },
    });

    const opUpdated = await callRpc(ids.operator, 'delivery_cloud_admin_accounts', {
      p_action: 'update_profile',
      p_payload: {
        user_id: ids.merchant,
        full_name: 'Shop Minh Nhân',
        phone: '0933445566',
        birth_date: '2002-08-15',
        citizen_id: '079202009999',
        reason: 'Xác minh hồ sơ cửa hàng',
      },
    });
    assert.equal(opUpdated.account.birth_date, '2002-08-15');
    assert.equal(opUpdated.account.citizen_id, '079202009999');
    assert.equal(opUpdated.account.identity_verified, true);

    const adminList = await callRpc(ids.operator, 'delivery_cloud_admin_accounts', {
      p_action: 'list',
      p_payload: {},
    });
    assert.equal(adminList.summary.identity_verified_accounts, 2);
  });

  await t.test('Partner approvals, promo claims, and shipping transitions populate unified notification center', async () => {
    const opInbox = await callRpc(ids.operator, 'delivery_cloud_notifications', {
      p_action: 'list',
      p_payload: { category: 'account' },
    });
    assert.ok(opInbox.notifications.some(n => n.kind === 'membership_pending'));

    await callRpc(ids.operator, 'delivery_cloud_membership', {
      p_role: 'merchant',
      p_decision: 'approve',
      p_user: ids.merchant,
      p_version: 1,
      p_reason: '',
    });
    await callRpc(ids.operator, 'delivery_cloud_membership', {
      p_role: 'driver',
      p_decision: 'approve',
      p_user: ids.driver,
      p_version: 1,
      p_reason: '',
    });

    const merchantUnread = await callRpc(ids.merchant, 'delivery_cloud_notifications', {
      p_action: 'unread_count',
      p_payload: {},
    });
    assert.equal(merchantUnread.unread_count, 1);
    assert.equal(merchantUnread.latest.kind, 'membership_active');

    await callRpc(ids.buyerA, 'delivery_cloud_promo_events', {
      p_action: 'checkin',
      p_payload: {},
    });
    const buyerPromoInbox = await callRpc(ids.buyerA, 'delivery_cloud_notifications', {
      p_action: 'list',
      p_payload: { category: 'promo', unread_only: true },
    });
    assert.equal(buyerPromoInbox.notifications.length, 1);
    assert.equal(buyerPromoInbox.notifications[0].kind, 'promo_checkin');

    const marked = await callRpc(ids.buyerA, 'delivery_cloud_notifications', {
      p_action: 'mark_read',
      p_payload: { id: buyerPromoInbox.notifications[0].id },
    });
    assert.equal(marked.unread_count, 0);

    const prefs = await callRpc(ids.buyerA, 'delivery_cloud_notifications', {
      p_action: 'save_preferences',
      p_payload: { promo_updates: false },
    });
    assert.equal(prefs.preferences.promo_updates, false);
    await callRpc(ids.buyerA, 'delivery_cloud_notifications', {
      p_action: 'save_preferences',
      p_payload: { promo_updates: true },
    });
  });

  await t.test('Shipping fee Xu discount deducts 20%, settles discounted payOS fee, refunds on cancel, and accrues 1% on deliver', async () => {
    await db.query(
      `insert into public.delivery_market_coin_wallets(user_id, balance)
       values ($1, 15000)
       on conflict (user_id) do update set balance = 15000`,
      [ids.buyerA],
    );

    const details = {
      pickup_address: '12 Nguyễn Huệ, Quận 1, TP HCM',
      dropoff_address: '20 Lê Lợi, Quận 1, TP HCM',
      pickup_lat: 10.77,
      pickup_lng: 106.70,
      dropoff_lat: 10.78,
      dropoff_lng: 106.71,
      weight_kg: 2,
      service_type: 'express',
      recipient_name: 'Người nhận A',
      recipient_phone: '0912345678',
      package_description: 'Hồ sơ tài liệu',
      cod_amount: 0,
      payment_method: 'sender_cash',
      use_coins: true,
    };

    const quote = await callRpc(ids.buyerA, 'delivery_cloud_quote', { p_details: details });
    assert.equal(quote.shipping_fee, 40000);
    assert.equal(quote.coin_discount, 8000);
    assert.equal(quote.payable_fee, 32000);
    assert.equal(quote.available_coins, 15000);

    await assert.rejects(
      callRpc(ids.buyerA, 'delivery_cloud_create', {
        p_details: details,
        p_request_key: randomUUID(),
        p_pricing_version: quote.pricing_version,
        p_expected_fee: quote.shipping_fee,
      }),
      e => e.code === 'PT409',
    );

    const createdCancel = await callRpc(ids.buyerA, 'delivery_cloud_create', {
      p_details: details,
      p_request_key: randomUUID(),
      p_pricing_version: quote.pricing_version,
      p_expected_fee: quote.payable_fee,
    });
    assert.equal(createdCancel.shipping_fee, 40000);
    assert.equal(createdCancel.coin_discount, 8000);
    assert.equal(createdCancel.payable_fee, 32000);

    let bal = (await callRpc(ids.buyerA, 'delivery_cloud_profile')).account.coin_balance;
    assert.equal(bal, 7000);

    await callRpc(ids.buyerA, 'delivery_cloud_transition', {
      p_order: createdCancel.id,
      p_action: 'cancel',
      p_version: createdCancel.version,
      p_request_key: randomUUID(),
      p_reason: 'Đổi địa chỉ lấy hàng',
    });
    bal = (await callRpc(ids.buyerA, 'delivery_cloud_profile')).account.coin_balance;
    assert.equal(bal, 15000);

    const createdDeliver = await callRpc(ids.buyerA, 'delivery_cloud_create', {
      p_details: details,
      p_request_key: randomUUID(),
      p_pricing_version: quote.pricing_version,
      p_expected_fee: quote.payable_fee,
    });
    assert.equal((await callRpc(ids.buyerA, 'delivery_cloud_profile')).account.coin_balance, 7000);

    // Verify payOS charges and settles payable_fee (32,000 VND) rather than raw shipping_fee (40,000 VND)
    const env = {
      DATABASE_URL: 'postgresql://test',
      PAYOS_ENABLED: 'true',
      PAYOS_CLIENT_ID: 'test-client',
      PAYOS_API_KEY: 'test-api',
      PAYOS_CHECKSUM_KEY: 'test-checksum',
    };
    const sdk = new PayOS({
      clientId: env.PAYOS_CLIENT_ID,
      apiKey: env.PAYOS_API_KEY,
      checksumKey: env.PAYOS_CHECKSUM_KEY,
    });
    const database = { query: (...args) => db.query(...args), transaction: op => db.transaction(tx => op(tx)) };
    const app = express();
    app.use(express.json());
    app.use('/delivery', createPaymentGateway({
      env,
      database,
      authenticate: (req, _res, next) => {
        req.deliveryIdentity = { id: ids.buyerA, role: 'user', local: false };
        next();
      },
      clientFactory: () => ({
        webhooks: sdk.webhooks,
        paymentRequests: {
          async create(input) {
            return {
              paymentLinkId: `link-${input.orderCode}`,
              orderCode: input.orderCode,
              amount: input.amount,
              checkoutUrl: `https://pay.payos.vn/web/link-${input.orderCode}`,
              qrCode: 'qr-discounted',
            };
          },
        },
      }),
    }));
    const srv = app.listen(0, '127.0.0.1');
    t.after(() => srv.close());
    await new Promise(resolve => srv.once('listening', resolve));
    const payBase = `http://127.0.0.1:${srv.address().port}/delivery`;
    const payRes = await (await fetch(`${payBase}/cloud/orders/${createdDeliver.id}/payment`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    })).json();
    assert.equal(payRes.payment.amount, 32000);

    const whData = {
      code: '00',
      currency: 'VND',
      orderCode: Number(payRes.payment.provider_order_code),
      amount: 32000,
      paymentLinkId: `link-${payRes.payment.provider_order_code}`,
      reference: randomUUID(),
    };
    const sigText = Object.keys(whData).sort().map(k => `${k}=${whData[k]}`).join('&');
    const signature = createHmac('sha256', env.PAYOS_CHECKSUM_KEY).update(sigText).digest('hex');
    const settled = await (await fetch(`${payBase}/payments/webhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: whData, signature }),
    })).json();
    assert.equal(settled.status, 'PAID');

    // Driver claims & delivers -> buyerA accrues 1% of 32,000 = 320 Xu + receives shipping & promo notifications!
    const driverQueue = await callRpc(ids.driver, 'delivery_cloud_list', { p_queue: true });
    assert.equal(JSON.stringify(driverQueue).includes('079201001234'), false);
    const pubLookup = (await db.query(
      'select public.delivery_cloud_public_lookup($1, $2) as data',
      [createdDeliver.tracking_code, '5678'],
    )).rows[0].data;
    assert.equal(JSON.stringify(pubLookup).includes('079201001234'), false);

    let step = createdDeliver;
    for (const action of ['claim', 'arrive', 'pickup', 'deliver']) {
      step = await callRpc(ids.driver, 'delivery_cloud_transition', {
        p_order: step.id,
        p_action: action,
        p_version: step.version,
        p_request_key: randomUUID(),
        p_reason: '',
      });
    }
    assert.equal(step.status, 'delivered');
    const finalProfile = await callRpc(ids.buyerA, 'delivery_cloud_profile');
    assert.equal(finalProfile.account.coin_balance, 7320);
    assert.ok(finalProfile.account.unread_notifications >= 4);

    const ledgerKinds = (await db.query(
      'select kind, delta from public.delivery_market_coin_ledger where user_id = $1 order by id',
      [ids.buyerA],
    )).rows.map(r => `${r.kind}:${r.delta}`);
    assert.ok(ledgerKinds.includes('redeem_shipping:-8000'));
    assert.ok(ledgerKinds.includes('release_shipping_cancel:8000'));
    assert.ok(ledgerKinds.includes('earn_shipping:320'));

    const cleared = await callRpc(ids.buyerA, 'delivery_cloud_notifications', {
      p_action: 'mark_all_read',
      p_payload: {},
    });
    assert.equal(cleared.unread_count, 0);
  });

  await t.test('Gateway /notifications/:action and FCM webhook respect user_notifications & push_enabled', async () => {
    const rpcCalls = [];
    const gwApp = express();
    gwApp.use(express.json());
    gwApp.use('/cloud', createCloudOrders({
      env: { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'anon' },
      authenticate(req, _res, next) {
        req.deliveryIdentity = { id: ids.buyerA, token: 'jwt' };
        next();
      },
      fetcher: async (url, options) => {
        rpcCalls.push({ url: String(url), body: JSON.parse(options.body) });
        return new Response(JSON.stringify({ unread_count: 2, schema_version: 3 }), { status: 200 });
      },
    }));
    let pushPayloads = [];
    let pushEnabled = true;
    gwApp.use('/notify', createNotificationRouter({
      env: {
        DELIVERY_WEBHOOK_SECRET: 'wh-secret',
        SUPABASE_URL: 'https://example.supabase.co',
        SUPABASE_ANON_KEY: 'anon',
        SUPABASE_SERVICE_ROLE_KEY: 'service',
      },
      authenticate: (_req, _res, next) => next(),
      fetcher: async url => {
        const u = new URL(url);
        if (u.pathname.endsWith('delivery_user_notifications')) {
          return new Response(JSON.stringify([{
            id: 'n-1',
            user_id: ids.buyerA,
            category: 'shipping',
            kind: 'order_delivered',
            title: 'Giao hàng thành công',
            body: 'Vận đơn CL-123 đã hoàn tất.',
            reference_type: 'cloud_order',
            reference_id: ids.merchant,
          }]), { status: 200 });
        }
        if (u.pathname.endsWith('delivery_notification_preferences')) {
          return new Response(JSON.stringify([{ push_enabled: pushEnabled }]), { status: 200 });
        }
        if (u.pathname.endsWith('delivery_device_tokens')) {
          return new Response(JSON.stringify([{ user_id: ids.buyerA, token: 'fcm-device-token-1234567890' }]), { status: 200 });
        }
        throw new Error(`Unexpected path ${u.pathname}`);
      },
      sendPush: async msg => {
        pushPayloads.push(msg);
        return { successCount: 1, failureCount: 0, responses: [{ success: true }] };
      },
    }));
    gwApp.use((err, _req, res, _next) => res.status(err.status || 500).json({ error: err.message }));
    const gwSrv = gwApp.listen(0, '127.0.0.1');
    t.after(() => gwSrv.close());
    await new Promise(resolve => gwSrv.once('listening', resolve));
    const base = `http://127.0.0.1:${gwSrv.address().port}`;

    assert.equal((await fetch(`${base}/cloud/notifications/unknown`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    })).status, 400);
    const okRes = await fetch(`${base}/cloud/notifications/unread_count`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    });
    assert.equal(okRes.status, 200);
    assert.equal(rpcCalls[0].body.p_action, 'unread_count');

    const cashTransition = await fetch(`${base}/cloud/orders/${ids.merchant}/transition`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'collect_cash', version: 2, request_key: randomUUID(), reason: '' }),
    });
    assert.equal(cashTransition.status, 200);
    assert.equal(rpcCalls.at(-1).body.p_action, 'collect_cash');

    const whRes = await fetch(`${base}/notify/market-notification-webhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer wh-secret' },
      body: JSON.stringify({ type: 'INSERT', table: 'delivery_user_notifications', record: { id: 'n-1' } }),
    });
    assert.equal(whRes.status, 200);
    assert.equal(pushPayloads.length, 1);
    assert.equal(pushPayloads[0].notification.title, 'Giao hàng thành công');

    pushEnabled = false;
    const mutedRes = await (await fetch(`${base}/notify/order-webhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer wh-secret' },
      body: JSON.stringify({ type: 'INSERT', table: 'delivery_user_notifications', record: { id: 'n-2' } }),
    })).json();
    assert.equal(mutedRes.skipped, true);
    assert.equal(pushPayloads.length, 1);
  });
});
