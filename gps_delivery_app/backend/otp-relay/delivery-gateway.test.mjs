import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createDeliveryIntegrations, operatorOnly } from './delivery-integrations.mjs';
import { createLocalAuthGateway } from './local-auth-gateway.mjs';

const json = value => new Response(JSON.stringify(value));
const identity = (role = 'operator', local = false) => (req, _res, next) => { req.deliveryIdentity = { id: 'id', role, local }; next(); };
async function appFor(t, router) {
  const app = express(); app.use(express.json()); app.use(router);
  app.use((error, _req, res, _next) => res.status(error.status || 500).json({ error: error.message }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  return { get: path => fetch(base + path), post: (path, body) => fetch(base + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) };
}
test('Route and matrix gateway validate coordinates, generate fixed OSRM options and obey toggle before cache', async t => {
  const env = { OSRM_BASE_URL: 'https://router.example/' }; let calls = 0;
  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity('user'), operatorOnly, fetcher: async url => {
    calls++;
    if (url.pathname.includes('/route/')) return json({ code: 'Ok', routes: [{ distance: 100, duration: 60 }] });
    assert.equal(url.searchParams.get('sources'), '0;1'); assert.equal(url.searchParams.get('destinations'), '2');
    assert.equal(url.searchParams.has('fallback_speed'), false);
    return json({ code: 'Ok', distances: [[10], [20]], durations: [[1], [2]] });
  } }));
  for (const invalid of ['0,91;10,10', 'https://internal;0,0', ',;0,0', '1,2']) assert.equal((await app.get(`/route?coordinates=${encodeURIComponent(invalid)}`)).status, 400);
  assert.equal(calls, 0);
  const route = '/route?coordinates=106,10;106.1,10.1';
  assert.equal((await app.get(route)).status, 200); assert.equal((await app.get(route)).status, 200); assert.equal(calls, 1);
  env.OSRM_ENABLED = 'false'; assert.equal((await app.get(route)).status, 503); assert.equal(calls, 1);
  env.OSRM_ENABLED = 'true'; assert.equal((await app.get('/matrix?coordinates=106,10;106.1,10.1;106.2,10.2')).status, 200);
});
test('Catalogues are cached but disabled banks fail; privileged adapters are role gated and secrets stay server side', async t => {
  const env = { GHN_ENABLED: 'true', GHN_BASE_URL: 'https://dev-online-gateway.ghn.vn/shiip/public-api/', GHN_TOKEN: 'private-token', GHN_SHOP_ID: '12' };
  let calls = 0;
  const fetcher = async (url, options) => {
    calls++;
    if (String(url).includes('vietqr')) return json({ code: '00', data: [{ bin: '970000' }] });
    assert.equal(options.headers.Token, 'private-token');
    assert.equal(JSON.parse(options.body).injected, undefined);
    assert.match(url.pathname, /shipping-order\/fee$/);
    return json({ code: 200, data: { total: 25000 } });
  };
  const user = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity('user'), operatorOnly, fetcher }));
  assert.equal((await user.get('/banks')).status, 200); assert.equal((await user.get('/banks')).status, 200); assert.equal(calls, 1);
  env.BANKS_ENABLED = 'false'; assert.equal((await user.get('/banks')).status, 503);
  for (const path of ['/admin/integrations', '/admin/integrations/audit', '/admin/ghn/provinces']) assert.equal((await user.get(path)).status, 403);
  for (const path of ['/admin/integrations/config', '/admin/integrations/test/ghn', '/admin/search', '/admin/ghn/quote']) assert.equal((await user.post(path, {})).status, 403);
  const admin = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity(), operatorOnly, fetcher }));
  assert.equal((await admin.post('/admin/ghn/quote', { weight: -1 })).status, 400);
  const quote = await admin.post('/admin/ghn/quote', { to_district_id: 123, to_ward_code: '1234', weight: 1000, service_type_id: 2, injected: 'discard' });
  assert.deepEqual(await quote.json(), { data: { total: 25000 } });
  assert.equal(calls, 2);
});
test('Local Google exchange requires PKCE, validates verified email and never returns provider tokens', async t => {
  const env = { GOOGLE_CLIENT_ID: 'id.apps.googleusercontent.com', GOOGLE_CLIENT_SECRET: 'google-secret' }; let calls = 0;
  const fetcher = async (url, options) => {
    calls++;
    if (url.includes('/token')) {
      const form = new URLSearchParams(options.body);
      assert.equal(form.get('client_secret'), 'google-secret');
      assert.equal(form.get('redirect_uri'), 'http://127.0.0.1:8765/oauth2callback');
      assert.equal(form.get('code_verifier').length, 64);
      return json({ access_token: 'provider-token', refresh_token: 'private-refresh' });
    }
    return json({ sub: 'google-user', email: 'user@example.com', name: 'User', email_verified: true });
  };
  const remote = await appFor(t, createLocalAuthGateway({ env, authenticate: identity(), fetcher }));
  assert.equal((await remote.get('/config')).status, 403);
  const local = await appFor(t, createLocalAuthGateway({ env, authenticate: identity('operator', true), fetcher }));
  const config = await (await local.get('/config')).text(); assert.equal(config.includes('google-secret'), false);
  assert.equal((await local.post('/google/exchange', { code: 'x' })).status, 400); assert.equal(calls, 0);
  const result = await local.post('/google/exchange', { code: 'one-use-code', codeVerifier: 'a'.repeat(64), redirectUri: 'https://attacker' });
  assert.deepEqual(await result.json(), { sub: 'google-user', email: 'user@example.com', name: 'User' });
  env.GOOGLE_ENABLED = 'false'; assert.equal((await local.post('/google/exchange', { code: 'x', codeVerifier: 'a'.repeat(64) })).status, 503);
});
test('SMS delivery only reports accepted after provider confirmation and forwards no caller credentials', async t => {
  const env = { SMS_ENABLED: 'true', SMS_PROVIDER: 'TEXTBEE', SMS_API_KEY: 'real-key', SMS_BRANDNAME: 'device-id' };
  let accepted = false; let calls = 0;
  const app = await appFor(t, createLocalAuthGateway({ env, authenticate: identity('operator', true), fetcher: async (url, options) => {
    calls++; assert.equal(url, 'https://api.textbee.dev/api/v1/gateway/send-sms');
    assert.equal(options.headers['x-api-key'], 'real-key');
    assert.equal(JSON.parse(options.body).deviceId, 'device-id');
    return json(accepted ? { smsBatchId: 'batch-id' } : {});
  } }));
  assert.equal((await app.post('/sms', { phone: 'invalid', otp: '123456' })).status, 400);
  const body = { phone: '+84912345678', otp: '123456', apiKey: 'attacker-key' };
  assert.equal((await app.post('/sms', body)).status, 502);
  accepted = true; assert.equal((await (await app.post('/sms', body)).json()).accepted, true);
  env.SMS_ENABLED = 'false'; assert.equal((await app.post('/sms', body)).status, 503); assert.equal(calls, 2);
});
