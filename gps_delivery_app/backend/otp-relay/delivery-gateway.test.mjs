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
    if (url.pathname.includes('106.30000')) {
      assert.equal(url.searchParams.has('sources'), false); assert.equal(url.searchParams.has('destinations'), false);
      return json({ code: 'Ok', distances: [[0, 5], [5, 0]], durations: [[0, 1], [1, 0]] });
    }
    assert.equal(url.searchParams.get('sources'), '0;1'); assert.equal(url.searchParams.get('destinations'), '2');
    assert.equal(url.searchParams.has('fallback_speed'), false);
    return json({ code: 'Ok', distances: [[10], [20]], durations: [[1], [2]] });
  } }));
  for (const invalid of ['0,91;10,10', 'https://internal;0,0', ',;0,0', '1,2', '106,10;106.1,10.1;106.2,10.2;106.3,10.3;106.4,10.4;106.5,10.5;106.6,10.6;106.7,10.7']) assert.equal((await app.get(`/route?coordinates=${encodeURIComponent(invalid)}`)).status, 400);
  assert.equal(calls, 0);
  const route = '/route?coordinates=106,10;106.1,10.1';
  assert.equal((await app.get(route)).status, 200); assert.equal((await app.get(route)).status, 200); assert.equal(calls, 1);
  assert.equal((await app.get('/route?coordinates=106,10;106.05,10.05;106.1,10.1')).status, 200); assert.equal(calls, 2);
  env.OSRM_ENABLED = 'false'; assert.equal((await app.get(route)).status, 503); assert.equal(calls, 2);
  env.OSRM_ENABLED = 'true'; assert.equal((await app.get('/matrix?coordinates=106,10;106.1,10.1;106.2,10.2')).status, 200);
  const fullTable = await (await app.get('/matrix?full=1&coordinates=106,10;106.3,10.3')).json();
  assert.deepEqual(fullTable.distances, [[0, 5], [5, 0]]);
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

test('Reverse geocoding sends User-Agent to Photon and uses Google Geocoding API when google_maps is enabled', async t => {
  const env = { PHOTON_BASE_URL: 'https://photon.example/' };
  let calls = 0;
  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity('user'), operatorOnly, fetcher: async (url, options) => {
    calls++;
    const u = new URL(url);
    if (u.hostname === 'maps.googleapis.com') {
      assert.equal(u.searchParams.get('solution_id'), 'gmp_git_agentskills_v1');
      assert.equal(u.searchParams.get('key'), 'gmaps-secret-key');
      return json({ status: 'OK', results: [{ formatted_address: 'Chợ Bến Thành, Quận 1, TP. Hồ Chí Minh, Việt Nam' }] });
    }
    assert.equal(options.headers['User-Agent'], 'GHSTDelivery/1.0');
    return json({ features: [{ properties: { name: 'Chợ Bến Thành', district: 'Bến Thành', city: 'Thành phố Hồ Chí Minh' } }] });
  } }));
  assert.equal((await app.get('/reverse?lat=99&lon=106')).status, 400);
  const pRes = await (await app.get('/reverse?lat=10.77251&lon=106.69802')).json();
  assert.match(pRes.address, /Chợ Bến Thành/);
  assert.match(pRes.attribution, /Photon/);
  env.GOOGLE_MAPS_ENABLED = 'true';
  env.GOOGLE_MAPS_API_KEY = 'gmaps-secret-key';
  const gRes = await (await app.get('/reverse?lat=10.77978&lon=106.69902')).json();
  assert.equal(gRes.address, 'Chợ Bến Thành, Quận 1, TP. Hồ Chí Minh, Việt Nam');
  assert.equal(gRes.attribution, 'Google Maps');
  assert.equal(JSON.stringify(gRes).includes('gmaps-secret-key'), false);
  assert.equal(calls, 2);
});

test('Route, matrix and connection check run 100% on Google Maps Platform when Photon and OSRM are disabled', async t => {
  const encodeCoord = value => {
    let v = value < 0 ? ~(value << 1) : (value << 1);
    let out = '';
    while (v >= 0x20) {
      out += String.fromCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    return out + String.fromCharCode(v + 63);
  };
  const encodePolyline = coords => {
    let prevLat = 0;
    let prevLng = 0;
    return coords.map(([lng, lat]) => {
      const iLat = Math.round(lat * 1e5);
      const iLng = Math.round(lng * 1e5);
      const chunk = encodeCoord(iLat - prevLat) + encodeCoord(iLng - prevLng);
      prevLat = iLat;
      prevLng = iLng;
      return chunk;
    }).join('');
  };
  const polyline = encodePolyline([[106.69802, 10.77251], [106.69902, 10.77978]]);
  const env = {
    GOOGLE_MAPS_ENABLED: 'true',
    GOOGLE_MAPS_API_KEY: 'gmaps-only-secret',
    PHOTON_ENABLED: 'false',
    OSRM_ENABLED: 'false',
  };
  let routeCalls = 0;
  let matrixCalls = 0;
  let routesEnabledOnCloud = true;
  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity('operator'), operatorOnly, fetcher: async (url, options = {}) => {
    const href = String(url);
    if (href === 'https://routes.googleapis.com/directions/v2:computeRoutes') {
      assert.equal(options.headers['X-Goog-Api-Key'], 'gmaps-only-secret');
      assert.equal(options.headers['X-Goog-Maps-Solution-ID'], 'gmp_git_agentskills_v1');
      if (!routesEnabledOnCloud) return new Response(JSON.stringify({ error: { status: 'PERMISSION_DENIED' } }), { status: 403 });
      if (options.headers['X-Goog-FieldMask'] === 'routes.distanceMeters') {
        return json({ routes: [{ distanceMeters: 950 }] });
      }
      routeCalls++;
      assert.equal(options.headers['X-Goog-FieldMask'], 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline');
      const body = JSON.parse(options.body);
      assert.equal(body.travelMode, 'DRIVE');
      assert.equal(body.origin.location.latLng.latitude, 10.77251);
      assert.equal(body.destination.location.latLng.longitude, 106.69902);
      return json({ routes: [{ distanceMeters: 1240, duration: '215s', polyline: { encodedPolyline: polyline } }] });
    }
    if (href === 'https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix') {
      matrixCalls++;
      assert.equal(options.headers['X-Goog-Api-Key'], 'gmaps-only-secret');
      assert.equal(options.headers['X-Goog-Maps-Solution-ID'], 'gmp_git_agentskills_v1');
      assert.equal(options.headers['X-Goog-FieldMask'], 'originIndex,destinationIndex,duration,distanceMeters,status,condition');
      const body = JSON.parse(options.body);
      if (body.destinations.length === 2) {
        assert.equal(body.origins.length, 2);
        return json([
          { originIndex: 0, destinationIndex: 1, status: {}, distanceMeters: 700, duration: '90s', condition: 'ROUTE_EXISTS' },
          { originIndex: 1, destinationIndex: 0, status: {}, distanceMeters: 800, duration: '95s', condition: 'ROUTE_EXISTS' },
          { originIndex: 0, destinationIndex: 0, status: {}, distanceMeters: 0, duration: '0s', condition: 'ROUTE_EXISTS' },
          { originIndex: 1, destinationIndex: 1, status: {}, distanceMeters: 0, duration: '0s', condition: 'ROUTE_EXISTS' },
        ]);
      }
      assert.equal(body.origins.length, 2);
      assert.equal(body.destinations.length, 1);
      return json([
        { originIndex: 1, destinationIndex: 0, status: {}, distanceMeters: 2400, duration: '380s', condition: 'ROUTE_EXISTS' },
        { status: {}, distanceMeters: 950, duration: '140s', condition: 'ROUTE_EXISTS' },
      ]);
    }
    if (href === 'https://places.googleapis.com/v1/places:searchText') {
      return json({ places: [{ id: 'place-1' }] });
    }
    if (href.startsWith('https://maps.googleapis.com/maps/api/geocode/json')) {
      return json({ status: 'OK', results: [{ formatted_address: 'Quận 1, TP. Hồ Chí Minh' }] });
    }
    throw new Error(`Unexpected upstream call: ${href}`);
  } }));

  const routeRes = await (await app.get('/route?coordinates=106.69802,10.77251;106.69902,10.77978')).json();
  assert.equal(routeRes.code, 'Ok');
  assert.equal(routeRes.attribution, 'Google Maps');
  assert.equal(routeRes.routes[0].distance, 1240);
  assert.equal(routeRes.routes[0].duration, 215);
  assert.deepEqual(routeRes.routes[0].geometry.coordinates, [[106.69802, 10.77251], [106.69902, 10.77978]]);
  assert.equal(JSON.stringify(routeRes).includes('gmaps-only-secret'), false);
  await app.get('/route?coordinates=106.69802,10.77251;106.69902,10.77978');
  assert.equal(routeCalls, 1);

  const matrixRes = await (await app.get('/matrix?coordinates=106.69,10.77;106.70,10.78;106.71,10.79')).json();
  assert.equal(matrixRes.code, 'Ok');
  assert.equal(matrixRes.attribution, 'Google Maps');
  assert.deepEqual(matrixRes.durations, [[140], [380]]);
  assert.deepEqual(matrixRes.distances, [[950], [2400]]);
  assert.equal(matrixCalls, 1);
  const fullMatrix = await (await app.get('/matrix?full=1&coordinates=106.69,10.77;106.70,10.78')).json();
  assert.deepEqual(fullMatrix.distances, [[0, 700], [800, 0]]);
  assert.deepEqual(fullMatrix.durations, [[0, 90], [95, 0]]);
  assert.equal(matrixCalls, 2);

  const checkOk = await (await app.post('/admin/integrations/test/google_maps', {})).json();
  assert.equal(checkOk.ok, true);
  assert.match(checkOk.message, /Places API New, Geocoding API, Routes API/);

  routesEnabledOnCloud = false;
  const checkMissingRoutes = await (await app.post('/admin/integrations/test/google_maps', {})).json();
  assert.equal(checkMissingRoutes.ok, false);
  assert.match(checkMissingRoutes.message, /Routes API/);

  env.GOOGLE_MAPS_ENABLED = 'false';
  assert.equal((await app.get('/route?coordinates=106.69802,10.77251;106.69902,10.77978')).status, 503);
  assert.equal((await app.get('/matrix?coordinates=106.69,10.77;106.70,10.78;106.71,10.79')).status, 503);
});

test('TrackAsia powers places, reverse geocode, route, matrix and connection check with Photon/OSRM/Google disabled', async t => {
  const env = {
    TRACKASIA_ENABLED: 'true',
    TRACKASIA_API_KEY: 'trackasia-unit-secret',
    PHOTON_ENABLED: 'false',
    OSRM_ENABLED: 'false',
    GOOGLE_MAPS_ENABLED: 'false',
  };
  const app = await appFor(t, createDeliveryIntegrations({ env, authenticate: identity('operator'), operatorOnly, fetcher: async url => {
    const u = new URL(url);
    assert.equal(u.hostname, 'maps.track-asia.com');
    assert.equal(u.searchParams.get('key'), 'trackasia-unit-secret');
    if (u.pathname === '/api/v1/autocomplete') {
      return json({
        type: 'FeatureCollection',
        features: [{
          geometry: { coordinates: [106.70512, 10.77298] },
          properties: { name: '12 Nguyễn Huệ', label: '12 Nguyễn Huệ, Phường Bến Nghé, Quận 1, Thành phố Hồ Chí Minh' },
        }],
      });
    }
    if (u.pathname === '/api/v2/geocode/json') {
      return json({ status: 'OK', results: [{ formatted_address: 'Công trường Quách Thị Trang, Quận 1, TP. Hồ Chí Minh' }] });
    }
    if (u.pathname.startsWith('/route/v1/car/')) {
      return json({ code: 'Ok', routes: [{ distance: 1073.5, duration: 285.5, geometry: { type: 'LineString', coordinates: [[106.69802, 10.77251], [106.69902, 10.77978]] } }] });
    }
    if (u.pathname.startsWith('/distance-matrix/v1/car/')) {
      return json({ code: 'Ok', durations: [[285.5], [223.7]], distances: [[1073.5], [1015.4]] });
    }
    throw new Error(`Unexpected path: ${u.pathname}`);
  } }));

  const placesRes = await (await app.get('/places?q=12%20Nguyen%20Hue&lat=10.7769&lon=106.7009')).json();
  assert.equal(placesRes.places.length, 1);
  assert.equal(placesRes.places[0].title, '12 Nguyễn Huệ');
  assert.equal(placesRes.attribution, 'TrackAsia');
  assert.equal(JSON.stringify(placesRes).includes('trackasia-unit-secret'), false);

  const revRes = await (await app.get('/reverse?lat=10.77251&lon=106.69802')).json();
  assert.equal(revRes.address, 'Công trường Quách Thị Trang, Quận 1, TP. Hồ Chí Minh');
  assert.equal(revRes.attribution, 'TrackAsia');
  assert.equal(JSON.stringify(revRes).includes('trackasia-unit-secret'), false);

  const routeRes = await (await app.get('/route?coordinates=106.69802,10.77251;106.69902,10.77978')).json();
  assert.equal(routeRes.code, 'Ok');
  assert.equal(routeRes.attribution, 'TrackAsia');
  assert.equal(routeRes.routes[0].distance, 1073.5);
  assert.equal(JSON.stringify(routeRes).includes('trackasia-unit-secret'), false);

  const matrixRes = await (await app.get('/matrix?coordinates=106.69802,10.77251;106.70,10.775;106.69902,10.77978')).json();
  assert.equal(matrixRes.code, 'Ok');
  assert.equal(matrixRes.attribution, 'TrackAsia');
  assert.deepEqual(matrixRes.durations, [[285.5], [223.7]]);

  const checkOk = await (await app.post('/admin/integrations/test/trackasia', {})).json();
  assert.equal(checkOk.ok, true);
  assert.match(checkOk.message, /Autocomplete, Geocoding, Routing/);
});
