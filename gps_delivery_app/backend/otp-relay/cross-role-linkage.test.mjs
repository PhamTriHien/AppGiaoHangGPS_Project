import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';
import { createNotificationRouter } from './delivery-notifications.mjs';

test('Cross-Role Linkage HTTP routes enforce allowlists, reason bounds, single-order lookup & driver finance RPCs', async t => {
  const calls = [];
  let local = false;
  const orderId = '00000000-0000-4000-8000-000000000010';
  const reqKey = '00000000-0000-4000-8000-000000000099';

  const app = express();
  app.use(express.json());
  app.use(
    '/cloud',
    createCloudOrders({
      env: { SUPABASE_URL: 'https://project.supabase.co', SUPABASE_ANON_KEY: 'public' },
      authenticate(req, _res, next) {
        req.deliveryIdentity = { id: 'driver-user', token: 'verified-jwt', local };
        next();
      },
      fetcher: async (url, options) => {
        const path = new URL(url).pathname;
        const body = options.body ? JSON.parse(options.body) : null;
        calls.push({ path, body, auth: options.headers.Authorization });
        if (path.endsWith('/delivery_cloud_profile')) {
          return new Response(JSON.stringify({ schema_version: 3 }), { status: 200 });
        }
        return new Response(JSON.stringify({ id: orderId, ok: true }), { status: 200 });
      },
    }),
  );
  app.use((error, _req, res, _next) => res.status(error.status || 500).json({ error: error.message }));

  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/cloud`;

  // 1. GET /orders/:id calls delivery_cloud_get and wraps { order }
  const badGet = await fetch(`${base}/orders/not-a-uuid`);
  assert.equal(badGet.status, 400);
  const goodGet = await fetch(`${base}/orders/${orderId}`);
  assert.equal(goodGet.status, 200);
  assert.deepEqual(await goodGet.json(), { order: { id: orderId, ok: true } });
  assert.equal(calls.at(-1).path, '/rest/v1/rpc/delivery_cloud_get');
  assert.deepEqual(calls.at(-1).body, { p_order: orderId });

  // 2. POST /driver-finance/:action enforces allowlist
  assert.equal(
    (await fetch(`${base}/driver-finance/drop_all`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    })).status,
    400,
  );
  for (const action of ['summary', 'remit_cod', 'request_payout', 'admin_list', 'admin_decide']) {
    const res = await fetch(`${base}/driver-finance/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount: 50000 }),
    });
    assert.equal(res.status, 200);
    assert.equal(calls.at(-1).path, '/rest/v1/rpc/delivery_driver_finance');
    assert.equal(calls.at(-1).body.p_action, action);
  }

  // 3. POST /logistics/pickup_transition is allowed
  const pickupRes = await fetch(`${base}/logistics/pickup_transition`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: orderId, action: 'claim', version: 1 }),
  });
  assert.equal(pickupRes.status, 200);
  assert.equal(calls.at(-1).path, '/rest/v1/rpc/delivery_cloud_logistics');
  assert.equal(calls.at(-1).body.p_action, 'pickup_transition');

  // 4. POST /orders/:id/transition enforces >= 3-char reason for release & reassign
  for (const action of ['release', 'reassign']) {
    const missingReason = await fetch(`${base}/orders/${orderId}/transition`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, version: 1, request_key: reqKey, reason: 'ab' }),
    });
    assert.equal(missingReason.status, 400);

    const okTransition = await fetch(`${base}/orders/${orderId}/transition`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, version: 1, request_key: reqKey, reason: 'Kẹt xe khu vực trung tâm' }),
    });
    assert.equal(okTransition.status, 200);
    assert.equal(calls.at(-1).path, '/rest/v1/rpc/delivery_cloud_transition');
    assert.equal(calls.at(-1).body.p_action, action);
  }
});

test('Market notification webhook respects market_updates=false preference', async t => {
  let pushSent = 0;
  const app = express();
  app.use(express.json());
  app.use(
    '/delivery',
    createNotificationRouter({
      env: {
        SUPABASE_URL: 'https://project.supabase.co',
        SUPABASE_ANON_KEY: 'public',
        SUPABASE_SERVICE_ROLE_KEY: 'service-role-secret',
        DELIVERY_WEBHOOK_SECRET: 'hook-secret',
        FIREBASE_ENABLED: 'true',
      },
      authenticate: (_req, _res, next) => next(),
      sendPush: async () => {
        pushSent++;
        return { successCount: 1, failureCount: 0, responses: [{ success: true }] };
      },
      fetcher: async url => {
        const u = String(url);
        if (u.includes('delivery_market_notifications')) {
          return new Response(
            JSON.stringify([{ id: 'notif-1', user_id: 'u-1', order_id: 'ord-1', kind: 'new_order' }]),
            { status: 200 },
          );
        }
        if (u.includes('delivery_notification_preferences')) {
          return new Response(
            JSON.stringify([{ push_enabled: true, market_updates: false }]),
            { status: 200 },
          );
        }
        return new Response(JSON.stringify([{ user_id: 'u-1', token: 'fcm-token-12345678901234567890' }]), {
          status: 200,
        });
      },
    }),
  );

  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(resolve => server.once('listening', resolve));

  const res = await fetch(`http://127.0.0.1:${server.address().port}/delivery/market-notification-webhook`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer hook-secret',
    },
    body: JSON.stringify({
      type: 'INSERT',
      table: 'delivery_market_notifications',
      record: { id: 'notif-1' },
    }),
  });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { sent: 0, skipped: true });
  assert.equal(pushSent, 0);
});
