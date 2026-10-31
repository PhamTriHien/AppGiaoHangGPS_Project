import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import express from 'express';
import { buildOptimization, coordinate, createDeliveryIntegrations, createIdentity,
  extractLabelFields, IntegrationError, operatorOnly, providerJson } from './delivery-integrations.mjs';
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
