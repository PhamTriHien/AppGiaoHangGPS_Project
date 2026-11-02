import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import express from 'express';
import { PGlite } from '@electric-sql/pglite';
import { buildOptimization, coordinate, createDeliveryIntegrations, createIdentity,
  extractLabelFields, IntegrationError, operatorOnly, providerJson } from './delivery-integrations.mjs';
import { loadIntegrationConfig, maskSecretValue, testIntegration, updateIntegrationConfig } from './integration-config.mjs';
import { createCloudOrders } from './cloud-orders.mjs';
import { createTurnstile } from './turnstile.mjs';
import { createNotificationRouter } from './delivery-notifications.mjs';

const payload = () => ({ vehicles: [{ id: 'driver-1', start: [106, 10], capacity: 30000 }],
  shipments: [{ id: 'ORDER-1', pickup: [106.1,10.1], delivery: [106.2,10.2], amount: 2000 }] });
const json = body => new Response(JSON.stringify(body));
const identity = (req, _res, next) => { req.deliveryIdentity = { id: 'user-1', role: 'operator', token: 'auth' }; next(); };

async function appFor(t, router, { large = false } = {}) {
  const app = express();
  if (!large) app.use(express.json());
  app.use('/delivery', router);
  app.use((error, _req, res, _next) => res.status(error.status || 500).json({ error: error.message }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}/delivery`;
  return { base, get: path => fetch(`${base}${path}`), post: (path, body, headers = {}) => fetch(`${base}${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body),
  }) };
}

test('VROOM payload keeps pickup/delivery precedence, capacity, truck skills and windows', () => {
  const input = payload(); input.vehicles[0].truck = true;
  input.shipments[0].truck = true; input.shipments[0].timeWindow = [100,200];
  const value = buildOptimization(input);
  assert.deepEqual(value.vehicles[0].capacity, [30000]);
  assert.deepEqual(value.vehicles[0].skills, [1]);
  assert.deepEqual(value.shipments[0].skills, [1]);
  assert.deepEqual(value.shipments[0].delivery.time_windows, [[100,200]]);
  assert.equal(value.shipments[0].pickup.id, 1);
  assert.equal(value.shipments[0].delivery.id, 2);
});
test('VROOM rejects invalid GPS, duplicate order IDs, excessive batches and capacity', () => {
  for (const change of [p => { p.vehicles[0].capacity = -1; }, p => { p.shipments[0].pickup = [0,91]; },
    p => p.shipments.push({...p.shipments[0]}), p => { p.shipments = Array(31).fill(p.shipments[0]); },
    p => { p.shipments[0].timeWindow = [200,100]; }]) {
    const p = payload(); change(p); assert.throws(() => buildOptimization(p), IntegrationError);
  }
  assert.equal(coordinate([NaN,0]), false);
});
test('OCR extracts Vietnamese shipping fields without fabricating missing data', () => {
  assert.deepEqual(extractLabelFields('Người nhận: Mai Anh\nSĐT: 0912 345 678\nĐịa chỉ: 1 Nguyễn Trãi'), {
    text: 'Người nhận: Mai Anh\nSĐT: 0912 345 678\nĐịa chỉ: 1 Nguyễn Trãi', recipientName: 'Mai Anh', recipientPhone: '0912345678', dropoffAddress: '1 Nguyễn Trãi',
  });
  assert.equal(extractLabelFields('unreadable').recipientName, '');
});
test('Missing provider config returns 503 and does not make a network call', async t => {
  const app = await appFor(t, createDeliveryIntegrations({ env: { PHOTON_BASE_URL: '' }, authenticate: identity, operatorOnly, fetcher() { throw Error('not expected'); } }));
  assert.equal((await app.get('/places?q=Saigon')).status, 503);
  assert.equal((await app.post('/optimize', payload())).status, 503);
  assert.equal((await app.post('/support-summary', {text:'x',redacted:true})).status, 503);
  const status = await (await app.get('/integrations')).json();
  assert.equal(status.ocr, true); assert.equal(status.gemini, false);
});
test('Photon caches results, caps lookup rate, validates coordinates and preserves OSM attribution', async t => {
  let calls = 0;
  const app = await appFor(t, createDeliveryIntegrations({ env: { PHOTON_BASE_URL: 'https://photon.example/' }, authenticate: identity,
    fetcher: async url => {
      calls++; assert.equal(url.hostname, 'photon.example'); assert.equal(url.searchParams.get('limit'), '5');
      return json({ features: [{ geometry: { coordinates: [106.7,10.7] }, properties: { name: 'Chợ', city: 'HCM' } },
        { geometry: { coordinates: [106,99] }, properties: { name: 'bad' } }] });
    } }));
  const first = await (await app.get('/places?q=Saigon')).json();
  assert.equal(first.places.length, 1); assert.match(first.attribution, /OpenStreetMap/);
  assert.equal(first.autocomplete, false);
  await app.get('/places?q=Saigon'); assert.equal(calls, 1);
  assert.equal((await app.get('/places?q=Hanoi')).status, 429);
});
test('Places search uses Google Places API (New) with solution ID and field mask when google_maps is enabled', async t => {
  let calls = 0;
  const env = { GOOGLE_MAPS_ENABLED: 'true', GOOGLE_MAPS_API_KEY: 'gmaps-places-secret' };
  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity, operatorOnly, fetcher: async (url, options) => {
    calls++;
    assert.equal(String(url), 'https://places.googleapis.com/v1/places:searchText');
    assert.equal(options.method, 'POST');
    assert.equal(options.headers['X-Goog-Api-Key'], 'gmaps-places-secret');
    assert.equal(options.headers['X-Goog-Maps-Solution-ID'], 'gmp_git_agentskills_v1');
    assert.equal(options.headers['X-Goog-FieldMask'], 'places.displayName,places.formattedAddress,places.location');
    const body = JSON.parse(options.body);
    assert.equal(body.regionCode, 'VN');
    assert.equal(body.locationBias.circle.center.latitude, 10.775);
    return json({ places: [{ displayName: { text: 'Chợ Bến Thành' }, formattedAddress: 'Lê Lợi, Phường Bến Thành, Quận 1, Hồ Chí Minh', location: { latitude: 10.77251, longitude: 106.69802 } }] });
  } }));
  const res = await (await app.get('/places?q=Ben%20Thanh&lat=10.775&lon=106.7')).json();
  assert.equal(res.places.length, 1);
  assert.equal(res.places[0].title, 'Chợ Bến Thành');
  assert.equal(res.autocomplete, true);
  assert.equal(res.attribution, 'Google Maps');
  assert.equal(JSON.stringify(res).includes('gmaps-places-secret'), false);
  await app.get('/places?q=Ben%20Thanh&lat=10.775&lon=106.7');
  assert.equal(calls, 1);
});
test('Photon places forwards Vietnam location bias by default', async t => {
  let seenLat = '';
  const app = await appFor(t, createDeliveryIntegrations({ env: { PHOTON_BASE_URL: 'https://photon.example/' }, authenticate: identity, fetcher: async url => {
    seenLat = url.searchParams.get('lat');
    return json({ features: [] });
  } }));
  assert.equal((await app.get('/places?q=Nguyen%20Hue')).status, 200);
  assert.equal(seenLat, '10.7769');
});
test('Operator endpoints reject ordinary members', async t => {
  const app = await appFor(t, createDeliveryIntegrations({ authenticate(req, _res, next) {
    req.deliveryIdentity = {role:'user'}; next(); }, operatorOnly }));
  assert.equal((await app.post('/optimize', payload())).status, 403);
  assert.equal((await app.get('/integrations')).status, 403);
});
test('Admin integration config persists backend values without returning secrets', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ghst-integration-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const env = {
    INTEGRATION_CONFIG_PATH: path.join(directory, 'config.json'),
    PHOTON_BASE_URL: 'https://photon.example/',
  };
  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity, operatorOnly }));
  const saved = await app.post('/admin/integrations/config', {
    values: {
      GHN_BASE_URL: 'https://dev-online-gateway.ghn.vn/shiip/public-api/',
      GHN_TOKEN: 'ghn-secret-token',
      GHN_SHOP_ID: '12345',
      GHN_ENABLED: 'true',
    },
  });
  assert.equal(saved.status, 200);
  const body = await saved.json();
  assert.equal(body.providers.ghn.enabled, true);
  const tokenField = body.providers.ghn.fields.find(field => field.key === 'GHN_TOKEN');
  assert.equal(tokenField.configured, true);
  assert.equal(Object.prototype.hasOwnProperty.call(tokenField, 'value'), false);
  assert.equal(tokenField.maskedValue, '••••••••••••oken');
  assert.equal(maskSecretValue('short6'), '••••••••');
  assert.equal(maskSecretValue('medium89'), '••••••••••89');
  assert.equal(
    maskSecretValue('postgresql://postgres:private-db-password@db.example:5432/postgres', 'DATABASE_URL'),
    'postgresql://••••••••@db.example:5432/postgres',
  );
  const persisted = JSON.parse(await readFile(env.INTEGRATION_CONFIG_PATH, 'utf8'));
  assert.equal(persisted.GHN_TOKEN, 'ghn-secret-token');
  assert.equal((await app.get('/admin/integrations')).status, 200);
});

test('Verified cloud operator manages database and SMTP while members and trust changes are denied', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ghst-cloud-admin-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const env = { INTEGRATION_CONFIG_PATH: path.join(directory, 'config.json'),
    SUPABASE_URL: 'https://own.supabase.co', SUPABASE_ANON_KEY: 'publishable',
    SMTP_PASS: 'existing-smtp-password', GOOGLE_CLIENT_ID: 'existing.apps.googleusercontent.com' };
  const authenticate = createIdentity({ env, tokenMatches: () => false, fetcher: async (url, options) => {
    const token = options.headers.Authorization;
    if (!['Bearer operator-session','Bearer member-session'].includes(token)) throw new Error('Invalid session');
    return json(url.pathname === '/auth/v1/user' ? {id:'cloud-user-id'} : [{role:token === 'Bearer operator-session' ? 'operator' : 'user'}]);
  } });
  const app = await appFor(t, createDeliveryIntegrations({env,authenticate,operatorOnly}));
  const values = {DATABASE_URL:'postgresql://postgres:private-db-password@db.example/postgres'};
  assert.equal((await app.post('/admin/integrations/config',{values})).status,401);
  assert.equal((await app.post('/admin/integrations/config',{values},{Authorization:'Bearer member-session'})).status,403);
  const headers = {Authorization:'Bearer operator-session'};
  const saved = await app.post('/admin/integrations/config',{values},headers);
  assert.equal(saved.status,200);
  assert.equal((await saved.text()).includes('private-db-password'),false);
  assert.equal(env.SMTP_PASS,'existing-smtp-password');
  assert.equal(env.GOOGLE_CLIENT_ID,'existing.apps.googleusercontent.com');
  assert.equal((await app.post('/admin/integrations/config',{values:{SMTP_PASS:'replacement-password'}},headers)).status,200);
  assert.equal(env.SMTP_PASS,'replacement-password');
  for(const values of [{SUPABASE_URL:'https://other.supabase.co'},{SUPABASE_ANON_KEY:'different-key'},{RELAY_TOKEN:'new-relay'}]) {
    const denied=await app.post('/admin/integrations/config',{values},headers);
    assert.ok([400,403].includes(denied.status));
  }
  assert.equal(env.SUPABASE_URL,'https://own.supabase.co');
  const metadata=await (await fetch(app.base+'/admin/integrations',{headers})).json();
  assert.equal(metadata.local,false);
  assert.equal(metadata.providers.backend.fields.find(field=>field.key==='DATABASE_URL').localOnly,false);
  const audit=await (await fetch(app.base+'/admin/integrations/audit',{headers})).json();
  assert.equal(audit.entries[0].actor,'cloud-user-id');
  assert.equal(JSON.stringify(audit).includes('replacement-password'),false);
});
test('OCR rejects URLs, invalid image data, oversized decoded image before invoking worker', async t => {
  let calls = 0;
  const app = await appFor(t, createDeliveryIntegrations({authenticate: identity, ocr: async () => { calls++; return {text:'real text'}; } }), {large:true});
  for (const image of ['https://private/image.png', Buffer.from('not image').toString('base64')])
    assert.equal((await app.post('/ocr', {image})).status, 400);
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1sAAAAASUVORK5CYII=', 'base64');
  assert.equal((await app.post('/ocr', {image:png.toString('base64')})).status, 200);
  const huge = Buffer.from(png); huge.writeUInt32BE(50000,16); huge.writeUInt32BE(50000,20);
  assert.equal((await app.post('/ocr', {image:huge.toString('base64')})).status, 400);
  assert.equal(calls, 1);
});
test('Provider failures retain 429 and never leak provider credentials', async () => {
  await assert.rejects(providerJson('https://example.test/?key=secret', {}, async () => new Response('', {status:429})),
    e => e.status === 429 && !e.message.includes('secret'));
});
test('Local relay token is never accepted from a non-loopback address', async () => {
  const auth = createIdentity({env:{}, tokenMatches: token => token === 'secret'});
  let status; let passed = false;
  await auth({ get:() => 'Bearer secret', socket:{remoteAddress:'192.168.1.2'} }, {
    status(code) { status=code; return this; }, json() {},
  }, () => { passed = true; });
  assert.equal(status,401); assert.equal(passed,false);
});
test('Turnstile verifies hostname/action and grants one OTP request only', async t => {
  let verifyCalls = 0;
  const turnstile = createTurnstile({ env:{ TURNSTILE_SITE_KEY:'site', TURNSTILE_SECRET_KEY:'secret', TURNSTILE_HOSTNAME:'localhost', TURNSTILE_ENFORCE_OTP:'true' },
    authenticate: identity, fetcher: async (url, options) => {
      verifyCalls++; assert.match(url,/siteverify/); assert.equal(JSON.parse(options.body).response,'challenge-token');
      return json({success:true,hostname:'localhost',action:'otp'});
    } });
  const router = express.Router(); router.use(turnstile.router);
  router.post('/otp',identity,turnstile.consume,(_req,res)=>res.json({ok:true}));
  const app=await appFor(t,router);
  assert.equal((await app.post('/otp',{})).status,403);
  const session = await (await app.post('/challenge-session',{})).json();
  assert.equal((await app.post(`/challenge/${session.id}`,{token:'challenge-token'})).status,200);
  const poll = await (await app.get(`/challenge-session/${session.id}`)).json();
  assert.equal(poll.status,'verified');
  assert.equal((await app.post('/otp',{turnstileGrant:poll.grant})).status,200);
  assert.equal((await app.post('/otp',{turnstileGrant:poll.grant})).status,403);
  assert.equal(verifyCalls,1);
});
test('Push webhook is authenticated, reads actual event recipients and ignores request injection', async t => {
  let sends=0;
  const router=createNotificationRouter({env:{DELIVERY_WEBHOOK_SECRET:'hook',SUPABASE_URL:'https://cloud.example',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service'},
    authenticate:identity, fetcher:async url=>{
      const path=new URL(url).pathname;
      if(path.endsWith('delivery_live_events')) return json([{id:'e1',room_id:'REAL',kind:'status',payload:{status:'delivered'}}]);
      if(path.endsWith('delivery_live_members')) return json([{user_id:'real-user'}]);
      if(path.endsWith('delivery_device_tokens')) return json([{user_id:'real-user',token:'actual-device-token-long'}]);
      throw Error('Unexpected path');
    },sendPush:async message=>{sends++;assert.deepEqual(message.tokens,['actual-device-token-long']);assert.equal(message.data.roomId,'REAL');
      return {successCount:1,failureCount:0,responses:[{success:true}]};} });
  const app=await appFor(t,router);
  const body={type:'INSERT',table:'delivery_live_events',record:{id:'e1',room_id:'INJECTED',tokens:['attacker']}};
  assert.equal((await app.post('/order-webhook',body)).status,401);
  assert.equal((await app.post('/order-webhook',body,{Authorization:'Bearer hook'})).status,200);
  assert.equal((await app.post('/order-webhook',body,{Authorization:'Bearer hook'})).status,200);
  assert.equal(sends,1);
});
test('Managed integration config syncs non-bootstrap settings and audit to RLS-locked Cloud PostgreSQL', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create role authenticated; create role anon;
    create table public.delivery_backend_config (
      key text primary key check (length(key) between 1 and 120),
      value text not null check (length(value) <= 8192),
      updated_by text not null default 'system' check (length(updated_by) between 1 and 120),
      updated_at timestamptz not null default now()
    );
    create table public.delivery_backend_config_audit (
      id bigserial primary key,
      at timestamptz not null default now(),
      actor text not null check (length(actor) between 1 and 120),
      changed jsonb not null check (jsonb_typeof(changed) = 'array')
    );
    alter table public.delivery_backend_config enable row level security;
    alter table public.delivery_backend_config_audit enable row level security;
    revoke all on table public.delivery_backend_config, public.delivery_backend_config_audit from public, anon, authenticated;
  `);
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ghst-cloud-cfg-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const env = {
    INTEGRATION_CONFIG_PATH: path.join(directory, 'local-a.json'),
    DATABASE_URL: 'postgresql://postgres:bootstrap-secret@db.example/postgres',
    SUPABASE_URL: 'https://own.supabase.co',
    SUPABASE_ANON_KEY: 'publishable',
    TRACKASIA_API_KEY: 'seed-trackasia-key',
    TRACKASIA_ENABLED: 'true',
  };
  await loadIntegrationConfig({ env, db });
  const seeded = await db.query('select key, value from public.delivery_backend_config order by key');
  const seededMap = Object.fromEntries(seeded.rows.map(r => [r.key, r.value]));
  assert.equal(seededMap.TRACKASIA_API_KEY, 'seed-trackasia-key');
  assert.equal(seededMap.TRACKASIA_ENABLED, 'true');
  assert.equal(Object.hasOwn(seededMap, 'DATABASE_URL'), false);
  assert.equal(Object.hasOwn(seededMap, 'SUPABASE_URL'), false);
  assert.equal(Object.hasOwn(seededMap, 'SUPABASE_ANON_KEY'), false);

  await assert.rejects(async () => {
    await db.exec('begin; set local role authenticated; select * from public.delivery_backend_config; commit;');
  });
  await db.exec('rollback;').catch(() => {});

  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity, operatorOnly, configDb: db }));
  const meta = await (await app.get('/admin/integrations')).json();
  assert.equal(meta.storage, 'cloud_postgres');

  const updated = await app.post('/admin/integrations/config', {
    values: { MARKET_JOBS_ENABLED: 'true', TRACKASIA_API_KEY: 'rotated-trackasia-key', PHOTON_ENABLED: 'false' },
  });
  assert.equal(updated.status, 200);

  const auditRes = await (await app.get('/admin/integrations/audit')).json();
  assert.equal(auditRes.entries[0].actor, 'user-1');
  assert.deepEqual(auditRes.entries[0].changed.sort(), ['MARKET_JOBS_ENABLED', 'PHOTON_ENABLED', 'TRACKASIA_API_KEY']);
  assert.equal(JSON.stringify(auditRes).includes('rotated-trackasia-key'), false);

  const restartedEnv = {
    INTEGRATION_CONFIG_PATH: path.join(directory, 'empty-local-b.json'),
    DATABASE_URL: 'postgresql://postgres:bootstrap-secret@db.example/postgres',
    SUPABASE_URL: 'https://own.supabase.co',
    SUPABASE_ANON_KEY: 'publishable',
  };
  await loadIntegrationConfig({ env: restartedEnv, db });
  assert.equal(restartedEnv.TRACKASIA_API_KEY, 'rotated-trackasia-key');
  assert.equal(restartedEnv.TRACKASIA_ENABLED, 'true');
  assert.equal(restartedEnv.MARKET_JOBS_ENABLED, 'true');
  assert.equal(restartedEnv.PHOTON_ENABLED, 'false');
});

test('Customer AI chatbot uses backend API URL and API key for OpenAI-compatible and Gemini endpoints with RLS user context', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'delivery-ai-chat-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const env = {
    INTEGRATION_CONFIG_PATH: path.join(directory, 'ai.json'),
    SUPABASE_URL: 'https://own.supabase.co',
    SUPABASE_ANON_KEY: 'publishable',
    GEMINI_ENABLED: 'true',
    GEMINI_BASE_URL: 'https://api.openai.com/v1',
    GEMINI_API_KEY: 'sk-backend-secret-key',
    GEMINI_MODEL: 'gpt-4o-mini',
  };
  let capturedAiRequest = null;
  const fetcher = async (url, options = {}) => {
    const u = new URL(String(url));
    if (u.hostname === 'own.supabase.co') {
      if (u.pathname === '/rest/v1/rpc/delivery_cloud_profile') {
        return json({ account: { full_name: 'Nguyễn Văn A', coin_balance: 2500, approved_roles: [] } });
      }
      if (u.pathname === '/rest/v1/rpc/delivery_cloud_list') {
        return json({ orders: [{ tracking_code: 'CL-AI-001', status: 'inTransit', shipping_fee: 28000, cod_amount: 150000, details: { service_type: 'express', pickup_address: '12 Nguyễn Huệ', dropoff_address: '20 Lê Lợi' }, otp_code: '999999' }] });
      }
      if (u.pathname === '/rest/v1/rpc/delivery_marketplace') {
        return json({ orders: [] });
      }
    }
    if (u.hostname === 'api.openai.com' && u.pathname === '/v1/chat/completions') {
      capturedAiRequest = { headers: options.headers, body: JSON.parse(options.body) };
      return json({ choices: [{ message: { content: 'Đơn CL-AI-001 của bạn đang trên đường giao đến 20 Lê Lợi.' } }] });
    }
    if (u.hostname === 'api.openai.com' && u.pathname === '/v1/models') {
      assert.equal(options.headers.Authorization, 'Bearer sk-backend-secret-key');
      return json({ object: 'list', data: [{ id: 'gpt-4o-mini' }] });
    }
    if (u.hostname === 'generativelanguage.googleapis.com' && u.pathname === '/v1beta/models/gemini-2.5-flash:generateContent') {
      assert.equal(options.headers['x-goog-api-key'], 'sk-backend-secret-key');
      return json({ candidates: [{ content: { parts: [{ text: 'GHST hỗ trợ 5 gói giao hàng Cloud.' }] } }] });
    }
    throw new Error(`Unexpected URL: ${url}`);
  };

  const probe = await testIntegration('gemini', { env, fetcher });
  assert.equal(probe.ok, true);

  let currentIdentity = { id: 'customer-uuid-1', role: 'user', token: 'user-jwt', local: false };
  const router = express.Router();
  router.use('/cloud', createCloudOrders({ env, authenticate: (req, _res, next) => { req.deliveryIdentity = currentIdentity; next(); }, fetcher }));
  router.use(createDeliveryIntegrations({ env, authenticate: (req, _res, next) => { req.deliveryIdentity = currentIdentity; next(); }, operatorOnly, fetcher }));
  const app = await appFor(t, router);

  const chatRes = await app.post('/cloud/ai-chat', {
    messages: [
      { role: 'user', content: 'Xin chào' },
      { role: 'assistant', content: 'Chào bạn, tôi có thể giúp gì?' },
      { role: 'user', content: 'Đơn hàng của tôi đang ở đâu?' },
    ],
  });
  assert.equal(chatRes.status, 200);
  const chatBody = await chatRes.json();
  assert.match(chatBody.reply, /CL-AI-001/);
  assert.equal(chatBody.model, 'gpt-4o-mini');
  assert.equal(JSON.stringify(chatBody).includes('sk-backend-secret-key'), false);
  assert.equal(capturedAiRequest.headers.Authorization, 'Bearer sk-backend-secret-key');
  assert.equal(capturedAiRequest.body.model, 'gpt-4o-mini');
  assert.match(capturedAiRequest.body.messages[0].content, /CL-AI-001/);
  assert.equal(capturedAiRequest.body.messages[0].content.includes('999999'), false);

  env.GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';
  env.GEMINI_MODEL = 'gemini-2.5-flash';
  const geminiRes = await app.post('/ai/chat', {
    messages: [{ role: 'user', content: 'Các gói giao hàng là gì?' }],
  });
  assert.equal(geminiRes.status, 200);
  assert.match((await geminiRes.json()).reply, /5 gói giao hàng/);

  assert.equal((await app.post('/cloud/ai-chat', { messages: [] })).status, 400);
  assert.equal((await app.post('/cloud/ai-chat', { messages: [{ role: 'assistant', content: 'sai vai tro cuoi' }] })).status, 400);

  currentIdentity = { id: 'local', role: 'operator', token: 'relay', local: true };
  assert.equal((await app.post('/cloud/ai-chat', { messages: [{ role: 'user', content: 'test' }] })).status, 401);
  assert.equal((await app.post('/ai/chat', { messages: [{ role: 'user', content: 'test' }] })).status, 401);

  currentIdentity = { id: 'customer-uuid-1', role: 'user', token: 'user-jwt', local: false };
  env.GEMINI_ENABLED = 'false';
  assert.equal((await app.post('/cloud/ai-chat', { messages: [{ role: 'user', content: 'test' }] })).status, 503);

  for (const unsafeUrl of [
    'http://api.openai.com/v1',
    'https://169.254.169.254/latest/meta-data',
    'https://10.0.0.5/v1',
    'https://192.168.1.10/v1',
    'http://127.0.0.1:11434/v1',
    'https://generativelanguage.googleapis.com/v1beta?key=leaked',
  ]) {
    await assert.rejects(updateIntegrationConfig({ GEMINI_BASE_URL: unsafeUrl }, { env, local: false }));
  }
});

test('Multi-instance pool-backed Cloud PostgreSQL sync persists candidate patch without configDb and syncs across Render and local instances', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create table public.delivery_backend_config (
      key text primary key check (length(key) between 1 and 120),
      value text not null check (length(value) <= 8192),
      updated_by text not null default 'system' check (length(updated_by) between 1 and 120),
      updated_at timestamptz not null default now()
    );
    create table public.delivery_backend_config_audit (
      id bigserial primary key,
      at timestamptz not null default now(),
      actor text not null check (length(actor) between 1 and 120),
      changed jsonb not null check (jsonb_typeof(changed) = 'array')
    );
  `);
  let released = 0;
  const configPool = () => ({
    async connect() {
      return {
        query: (sql, params) => db.query(sql, params),
        release() { released++; },
      };
    },
  });
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ghst-multi-sync-'));
  t.after(() => rm(directory, { recursive: true, force: true }));

  const renderEnv = {
    INTEGRATION_CONFIG_PATH: path.join(directory, 'render.json'),
    DATABASE_URL: 'postgresql://postgres:bootstrap-secret@db.example/postgres',
    SUPABASE_URL: 'https://own.supabase.co',
    SUPABASE_ANON_KEY: 'publishable',
  };
  const localEnv = {
    INTEGRATION_CONFIG_PATH: path.join(directory, 'local.json'),
    DATABASE_URL: 'postgresql://postgres:bootstrap-secret@db.example/postgres',
    SUPABASE_URL: 'https://own.supabase.co',
    SUPABASE_ANON_KEY: 'publishable',
    GOOGLE_MAPS_API_KEY: 'local-only-unsynced-key',
  };

  await loadIntegrationConfig({ env: renderEnv, connectPool: configPool });
  const renderApp = await appFor(t, createDeliveryIntegrations({
    env: renderEnv,
    authenticate: identity,
    operatorOnly,
    configPool,
  }));
  const localApp = await appFor(t, createDeliveryIntegrations({
    env: localEnv,
    authenticate: identity,
    operatorOnly,
    configPool,
  }));

  const saveOnRender = await renderApp.post('/admin/integrations/config', {
    values: {
      GEMINI_BASE_URL: 'https://api.openai.com/v1',
      GEMINI_API_KEY: 'sk-live-cloud-synced',
      GEMINI_MODEL: 'gpt-4o-mini',
      GEMINI_ENABLED: 'true',
    },
  });
  assert.equal(saveOnRender.status, 200);
  const saveBody = await saveOnRender.json();
  assert.equal(saveBody.storage, 'cloud_postgres');
  assert.equal(saveBody.providers.gemini.configured, true);
  assert.equal(saveBody.providers.gemini.enabled, true);
  assert.ok(released >= 2);

  const cloudRows = await db.query('select key, value, updated_by from public.delivery_backend_config order by key');
  const cloudMap = Object.fromEntries(cloudRows.rows.map(r => [r.key, r]));
  assert.equal(cloudMap.GEMINI_API_KEY.value, 'sk-live-cloud-synced');
  assert.equal(cloudMap.GEMINI_API_KEY.updated_by, 'user-1');

  const syncedLocalMeta = await (await localApp.get('/admin/integrations')).json();
  assert.equal(syncedLocalMeta.storage, 'cloud_postgres');
  assert.equal(syncedLocalMeta.providers.gemini.configured, true);
  assert.equal(syncedLocalMeta.providers.gemini.enabled, true);
  assert.equal(localEnv.GEMINI_API_KEY, 'sk-live-cloud-synced');
  assert.equal(localEnv.GEMINI_BASE_URL, 'https://api.openai.com/v1');

  const resyncExistingLocalSecret = await localApp.post('/admin/integrations/config', {
    values: { GOOGLE_MAPS_API_KEY: 'local-only-unsynced-key' },
  });
  assert.equal(resyncExistingLocalSecret.status, 200);
  const gmapsRow = await db.query("select value from public.delivery_backend_config where key = 'GOOGLE_MAPS_API_KEY'");
  assert.equal(gmapsRow.rows[0]?.value, 'local-only-unsynced-key');

  const clearOnLocal = await localApp.post('/admin/integrations/config', {
    values: {},
    clear: ['GEMINI_API_KEY'],
  });
  assert.equal(clearOnLocal.status, 200);
  const syncedRenderAfterClear = await (await renderApp.get('/admin/integrations')).json();
  assert.equal(syncedRenderAfterClear.providers.gemini.configured, false);
  assert.equal(renderEnv.GEMINI_API_KEY, '');
});
