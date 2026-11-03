import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import express from 'express';
import { PGlite } from '@electric-sql/pglite';
import { createCloudOrders } from './cloud-orders.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from './deployment-readiness.mjs';

test('Cloud Promo Events enforces server-side check-in, spin wheel, blind box, missions, personal voucher ownership & operator controls', async t => {
  const db = new PGlite();
  t.after(() => db.close());

  await db.exec(`create role authenticated; create role anon;
    create schema auth;
    create table auth.users(id uuid primary key, email text, raw_app_meta_data jsonb default '{}'::jsonb);
    create table auth.identities(id text primary key, user_id uuid references auth.users(id) on delete cascade, provider text not null);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
    alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated;
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
    '20261110_cloud_promo_events.sql',
    '20261111_profile_push_shipping_coins.sql',
    '20261112_shipping_cash_settlement.sql',
  ];
  for (const file of files) {
    await db.exec(await readFile(new URL(`../../database/migrations/${file}`, import.meta.url), 'utf8'));
  }

  const schema = (await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
  assert.equal(schema.promo_events_schema, true);

  const ids = {
    buyerA: randomUUID(),
    buyerB: randomUUID(),
    merchant: randomUUID(),
    operator: randomUUID(),
  };

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
      const out = await db.query(sql, vals);
      await db.exec('commit');
      return out.rows[0].data;
    } catch (err) {
      await db.exec('rollback');
      throw err;
    }
  }

  for (const [key, uid] of Object.entries(ids)) {
    await db.query('insert into auth.users(id, email) values($1, $2)', [uid, `${key}@example.com`]);
    if (key !== 'operator') {
      await callRpc(uid, 'delivery_cloud_profile', {
        p_details: { full_name: `User ${key}`, phone: '0901234567', requested_role: 'customer' },
      });
    }
  }
  await db.query("insert into public.delivery_api_profiles values($1, 'operator')", [ids.operator]);
  await callRpc(ids.merchant, 'delivery_cloud_membership', { p_role: 'merchant', p_decision: 'request' });
  await callRpc(ids.operator, 'delivery_cloud_membership', {
    p_role: 'merchant',
    p_decision: 'approve',
    p_user: ids.merchant,
    p_version: 1,
    p_reason: 'Duyet cua hang',
  });

  // Mount HTTP gateway against PGlite RPC bridge
  const env = {
    SUPABASE_ENABLED: 'true',
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'anon-key',
  };
  const fetcher = async (url, options) => {
    const fn = new URL(url).pathname.split('/').pop();
    const actor = options.headers.Authorization.replace('Bearer ', '');
    const body = options.body ? JSON.parse(options.body) : {};
    try {
      const data = await callRpc(actor, fn, body);
      return new Response(JSON.stringify(data), { status: 200 });
    } catch (err) {
      return new Response(JSON.stringify({ code: err.code || 'P0001', message: err.message }), { status: 400 });
    }
  };
  const app = express();
  app.use(express.json());
  app.use('/delivery/cloud', createCloudOrders({
    env,
    fetcher,
    authenticate(req, _res, next) {
      const token = req.get('x-actor') || ids.buyerA;
      req.deliveryIdentity = { id: token, token, role: token === ids.operator ? 'operator' : 'user', local: false };
      next();
    },
  }));
  app.use((err, _req, res, _next) => res.status(err.status || 500).json({ error: err.message }));
  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/delivery/cloud`;

  const postPromo = async (actor, action, body = {}) => {
    const res = await fetch(`${base}/promo-events/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-actor': actor },
      body: JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  };

  // 1. Unknown action rejected at gateway
  const unknown = await postPromo(ids.buyerA, 'hack_coins', {});
  assert.equal(unknown.status, 400);

  // 2. Operator without consumer profile can still read status & admin_stats
  const opStatus = await postPromo(ids.operator, 'status');
  assert.equal(opStatus.status, 200);
  assert.equal(opStatus.body.enabled, true);
  assert.equal(typeof opStatus.body.admin_stats.participants, 'number');

  // 3. Buyer A Day-1 check-in grants +50 coins and +1 spin ticket; duplicate check-in returns 409
  const checkin1 = await postPromo(ids.buyerA, 'checkin');
  assert.equal(checkin1.status, 200);
  assert.equal(checkin1.body.coin_balance, 50);
  assert.equal(checkin1.body.wallet.spin_tickets, 1);
  assert.equal(checkin1.body.wallet.checked_in_today, true);
  assert.equal(checkin1.body.reward.coins_delta, 50);

  const checkinDup = await postPromo(ids.buyerA, 'checkin');
  assert.equal(checkinDup.status, 409);

  // 4. Spin wheel consumes 1 spin ticket and returns valid wheel_segment 0..7
  const spin1 = await postPromo(ids.buyerA, 'spin_wheel');
  assert.equal(spin1.status, 200);
  assert.equal(spin1.body.wallet.spin_tickets, 0);
  assert.equal(spin1.body.wallet.total_spins, 1);
  assert.ok(spin1.body.wheel_segment >= 0 && spin1.body.wheel_segment <= 7);

  const spinEmpty = await postPromo(ids.buyerA, 'spin_wheel');
  assert.equal(spinEmpty.status, 409);

  // 5. Mission cannot be claimed before real delivered Cloud order, succeeds after delivered order
  const prematureMission = await postPromo(ids.buyerA, 'claim_mission', { mission_id: 'first_shipping' });
  assert.equal(prematureMission.status, 409);

  await db.query(
    `insert into public.delivery_cloud_orders(
      owner_id, request_key, request_payload, details, distance_meters,
      shipping_fee, cod_amount, pricing_version, status, merchant_ready
    ) values ($1, $2, '{}'::jsonb, $3, 2500, 25000, 0, 1, 'delivered', true)`,
    [
      ids.buyerA,
      randomUUID(),
      JSON.stringify({
        pickup_address: '12 Nguyen Hue',
        dropoff_address: '20 Le Loi',
        recipient_name: 'Buyer A',
        recipient_phone: '0901234567',
        package_description: 'Test parcel',
        prefer_ev: true,
      }),
    ],
  );

  const shipMission = await postPromo(ids.buyerA, 'claim_mission', { mission_id: 'first_shipping' });
  assert.equal(shipMission.status, 200);
  assert.equal(shipMission.body.reward.coins_delta, 100);
  assert.equal(shipMission.body.reward.spin_tickets_delta, 1);

  const evMission = await postPromo(ids.buyerA, 'claim_mission', { mission_id: 'green_ev' });
  assert.equal(evMission.status, 200);
  assert.equal(evMission.body.reward.coins_delta, 150);

  // 6. Exchange coins for blind box ticket + open blind box + reset tray
  const buyBox = await postPromo(ids.buyerA, 'exchange_coins', { item_id: 'blind_box_ticket' });
  assert.equal(buyBox.status, 200);
  assert.ok(buyBox.body.wallet.blind_box_tickets >= 1);

  const openBox = await postPromo(ids.buyerA, 'open_blind_box', { box_index: 2 });
  assert.equal(openBox.status, 200);
  assert.equal(openBox.body.box_index, 2);
  assert.ok(openBox.body.wallet.opened_boxes['2']);

  const dupBox = await postPromo(ids.buyerA, 'open_blind_box', { box_index: 2 });
  assert.equal(dupBox.status, 409);

  const resetBoxes = await postPromo(ids.buyerA, 'reset_blind_boxes');
  assert.equal(resetBoxes.status, 200);
  assert.deepEqual(resetBoxes.body.wallet.opened_boxes, {});

  // 7. Personal voucher minted via coin exchange is isolated strictly to Buyer A
  await db.query(
    `insert into public.delivery_market_coin_wallets(user_id, balance) values($1, 500)
     on conflict(user_id) do update set balance = public.delivery_market_coin_wallets.balance + 500`,
    [ids.buyerA],
  );
  const exVoucher = await postPromo(ids.buyerA, 'exchange_coins', { item_id: 'voucher_20k' });
  assert.equal(exVoucher.status, 200);
  const personalCode = exVoucher.body.reward.voucher_code;
  assert.match(personalCode, /^XU20K-[A-Z0-9]{8}$/);

  const vouchersA = await callRpc(ids.buyerA, 'delivery_market_operations', { p_action: 'vouchers', p_payload: {} });
  const vouchersB = await callRpc(ids.buyerB, 'delivery_market_operations', { p_action: 'vouchers', p_payload: {} });
  assert.ok(vouchersA.vouchers.some(v => v.code === personalCode && v.personal === true));
  assert.equal(vouchersB.vouchers.some(v => v.code === personalCode), false);

  // Set up shop + product so Buyer B and Buyer A test checkout quote with personalCode
  const shop = (await callRpc(ids.merchant, 'delivery_marketplace', {
    p_action: 'shop_save',
    p_payload: {
      name: 'Quan Ngon Cloud',
      description: 'Real cloud shop',
      address: '10 Nguyen Hue, Q1',
      latitude: 10.77,
      longitude: 106.70,
      paused: false,
    },
  })).shop;
  await callRpc(ids.operator, 'delivery_marketplace', {
    p_action: 'shop_moderate',
    p_payload: { id: shop.id, version: 1, status: 'active' },
  });
  const prod = (await callRpc(ids.merchant, 'delivery_marketplace', {
    p_action: 'product_save',
    p_payload: {
      id: randomUUID(),
      shop_id: shop.id,
      name: 'Combo Com Tam',
      description: '',
      category: 'Food',
      sku: 'COM-1',
      price: 100000,
      stock: 10,
      weight_kg: 0.5,
      published: true,
    },
  })).product;

  for (const buyer of [ids.buyerA, ids.buyerB]) {
    const addr = (await callRpc(buyer, 'delivery_cloud_addresses_manage', {
      p_id: randomUUID(),
      p_details: {
        label: 'Nha',
        recipient_name: 'Khach',
        recipient_phone: '0912345678',
        full_address: '20 Le Loi, Q1',
        latitude: 10.775,
        longitude: 106.705,
        is_default: true,
      },
      p_delete: false,
      p_version: null,
    })).addresses[0];
    await callRpc(buyer, 'delivery_marketplace', {
      p_action: 'cart_set',
      p_payload: { product_id: prod.id, quantity: 1, version: 1 },
    });
    if (buyer === ids.buyerB) {
      await assert.rejects(
        callRpc(ids.buyerB, 'delivery_marketplace', {
          p_action: 'quote',
          p_payload: { address_id: addr.id, voucher_code: personalCode },
        }),
        err => err.code === 'PT409',
      );
    } else {
      const quoted = await callRpc(ids.buyerA, 'delivery_marketplace', {
        p_action: 'quote',
        p_payload: { address_id: addr.id, voucher_code: personalCode },
      });
      assert.equal(quoted.quote.snapshot.voucher_discount, 20000);
    }
  }

  // 8. Non-operator cannot toggle promo settings; Operator can pause and resume
  const nonOpSave = await postPromo(ids.buyerA, 'admin_settings_save', { enabled: false, version: 1 });
  assert.equal(nonOpSave.status, 403);

  const paused = await postPromo(ids.operator, 'admin_settings_save', { enabled: false, version: 1 });
  assert.equal(paused.status, 200);
  assert.equal(paused.body.enabled, false);

  const blockedWhenPaused = await postPromo(ids.buyerB, 'checkin');
  assert.equal(blockedWhenPaused.status, 409);

  // Immutable claim log rejects delete
  await assert.rejects(db.query('delete from public.delivery_promo_reward_claims'));
});
