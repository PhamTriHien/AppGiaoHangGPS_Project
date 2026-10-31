import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import express from 'express';
import sharp from 'sharp';
import { createPublicTracking } from './market-operations.mjs';
import { createCloudOrders } from './cloud-orders.mjs';
import { createNotificationRouter } from './delivery-notifications.mjs';

test('Public cloud tracking lookup validates tracking_code + phone_last4 and strips private fields', async t => {
  let rpcBody = null;
  const app = express();
  app.use(express.json());
  app.use(createPublicTracking({
    env: { SUPABASE_URL: 'https://project.supabase.co', SUPABASE_ANON_KEY: 'public' },
    fetcher: async (url, options) => {
      assert.equal(String(url), 'https://project.supabase.co/rest/v1/rpc/delivery_cloud_public_lookup');
      assert.equal(options.headers.Authorization, undefined);
      rpcBody = JSON.parse(options.body);
      return new Response(JSON.stringify({
        tracking_code: rpcBody.p_tracking_code,
        status: 'inTransit',
        service_type: 'same_day_2h',
        distance_meters: 4200,
        created_at: '2026-10-31T01:00:00Z',
        updated_at: '2026-10-31T01:15:00Z',
        recipient_phone: '0912345678',
        dropoff_address: 'Private St',
        timeline: [{ action: 'pickup', status: 'inTransit', created_at: '2026-10-31T01:15:00Z', reason: 'secret' }],
      }), { status: 200 });
    },
  }));
  app.use((e, _req, res, _next) => res.status(e.status || 500).json({ error: e.message }));
  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(r => server.once('listening', r));
  const lookup = body => fetch(`http://127.0.0.1:${server.address().port}/tracking/lookup`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });

  const code = `CL-${'A'.repeat(32)}`;
  for (const invalid of [{}, { tracking_code: code, phone_last4: '12' }, { tracking_code: 'BAD', phone_last4: '5678' }, { tracking_code: code, phone_last4: '5678', extra: 1 }]) {
    assert.equal((await lookup(invalid)).status, 404);
  }
  assert.equal(rpcBody, null);

  const res = await lookup({ tracking_code: code.toLowerCase(), phone_last4: '5678' });
  assert.equal(res.status, 200);
  const json = await res.json();
  assert.equal(json.tracking_code, code);
  assert.equal(json.service_type, 'same_day_2h');
  assert.equal(JSON.stringify(json).includes('0912345678'), false);
  assert.equal(JSON.stringify(json).includes('Private St'), false);
  assert.equal(JSON.stringify(json).includes('secret'), false);
});

test('Cloud orders gateway routes private attachments, POD upload, OTP read and cloud shares using caller bearer token', async t => {
  const userId = randomUUID();
  const orderId = randomUUID();
  const trackingCode = `CL-${'B'.repeat(32)}`;
  const pngBuffer = await sharp({ create: { width: 8, height: 8, channels: 3, background: { r: 20, g: 120, b: 60 } } }).png().toBuffer();
  const base64Img = pngBuffer.toString('base64');

  const calls = [];
  const app = express();
  app.use((req, res, next) => ['/cloud/attachments', '/cloud/pod'].includes(req.path) ? next() : express.json({ limit: '32kb' })(req, res, next));
  app.use('/cloud', createCloudOrders({
    env: { SUPABASE_URL: 'https://project.supabase.co', SUPABASE_ANON_KEY: 'anon-key', PUBLIC_APP_URL: 'https://app.example.com/' },
    authenticate(req, _res, next) {
      req.deliveryIdentity = { id: userId, role: 'customer', token: 'user-jwt', local: false };
      next();
    },
    fetcher: async (url, options) => {
      const path = new URL(url).pathname;
      calls.push({ path, auth: options.headers?.Authorization });
      if (path === '/rest/v1/rpc/delivery_market_attachment_reserve') {
        const body = JSON.parse(options.body);
        return new Response(JSON.stringify({
          id: randomUUID(),
          bucket: 'delivery-private-evidence',
          name: `${body.p_scope}/${body.p_order}/${body.p_hash}.webp`,
        }), { status: 200 });
      }
      if (path.startsWith('/storage/v1/object/delivery-private-evidence/')) {
        return new Response('{}', { status: 200 });
      }
      if (path.startsWith('/storage/v1/object/sign/delivery-private-evidence/')) {
        return new Response(JSON.stringify({ signedURL: '/object/sign/delivery-private-evidence/signed?token=xyz' }), { status: 200 });
      }
      if (path.startsWith('/storage/v1/object/delivery-evidence/')) {
        return new Response('{}', { status: 200 });
      }
      if (path === '/rest/v1/delivery_live_events') {
        return new Response('', { status: 201 });
      }
      if (path === '/rest/v1/rpc/delivery_cloud_order_otp') {
        return new Response(JSON.stringify({ required: true, otp_code: '654321', verified_at: null }), { status: 200 });
      }
      if (path === '/rest/v1/rpc/delivery_cloud_share_manage') {
        return new Response(JSON.stringify({ id: randomUUID(), token: 'c'.repeat(64), expires_at: '2026-11-01T00:00:00Z' }), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    },
  }));
  app.use((e, _req, res, _next) => res.status(e.status || 500).json({ error: e.message }));
  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(r => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}/cloud`;

  const upAtt = await fetch(`${base}/attachments`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ order_id: orderId, scope: 'return', image: base64Img }),
  });
  assert.equal(upAtt.status, 200);
  const attJson = await upAtt.json();
  assert.match(attJson.attachment.name, /^return\//);

  const signAtt = await fetch(`${base}/attachments/sign`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: attJson.attachment.name }),
  });
  assert.equal(signAtt.status, 200);
  assert.match((await signAtt.json()).url, /^https:\/\/project\.supabase\.co\/storage\/v1\/object\/sign\//);

  const upPod = await fetch(`${base}/pod`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tracking_code: trackingCode, image: base64Img }),
  });
  assert.equal(upPod.status, 200);
  assert.match((await upPod.json()).path, new RegExp(`^${trackingCode}/pod-`));

  const otpRes = await fetch(`${base}/orders/${orderId}/otp`);
  assert.equal((await otpRes.json()).otp_code, '654321');

  const shareRes = await fetch(`${base}/orders/${orderId}/shares`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
  const shareJson = await shareRes.json();
  assert.equal(shareJson.share_url, `https://app.example.com/#/share?token=${'c'.repeat(64)}`);
  assert.ok(calls.every(c => c.auth === 'Bearer user-jwt'));
});

test('Marketplace notification webhook re-reads row from Supabase and sends sanitized push without private text', async t => {
  let pushed = null;
  const notifId = randomUUID();
  const userId = randomUUID();
  const orderId = randomUUID();
  const app = express();
  app.use(express.json());
  app.use(createNotificationRouter({
    env: {
      SUPABASE_URL: 'https://project.supabase.co',
      SUPABASE_ANON_KEY: 'anon',
      SUPABASE_SERVICE_ROLE_KEY: 'service-key',
      DELIVERY_WEBHOOK_SECRET: 'hook-secret',
      FIREBASE_ENABLED: 'true',
    },
    authenticate: (_req, _res, next) => next(),
    sendPush: async msg => {
      pushed = msg;
      return { successCount: 1, failureCount: 0, responses: [{ success: true }] };
    },
    fetcher: async url => {
      const path = new URL(url).pathname + new URL(url).search;
      if (path.startsWith('/rest/v1/delivery_market_notifications')) {
        return new Response(JSON.stringify([{ id: notifId, user_id: userId, order_id: orderId, kind: 'new_order' }]), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (path.startsWith('/rest/v1/delivery_device_tokens')) {
        return new Response(JSON.stringify([{ user_id: userId, token: 'fcm-token-12345678901234567890' }]), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      return new Response('[]', { status: 200, headers: { 'Content-Type': 'application/json' } });
    },
  }));
  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(r => server.once('listening', r));

  const res = await fetch(`http://127.0.0.1:${server.address().port}/order-webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer hook-secret' },
    body: JSON.stringify({ type: 'INSERT', table: 'delivery_market_notifications', record: { id: notifId, forged_body: 'Private address' } }),
  });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).sent, 1);
  assert.equal(pushed.notification.body, 'Cửa hàng vừa có đơn mua hàng mới.');
  assert.equal(JSON.stringify(pushed).includes('Private address'), false);
});
