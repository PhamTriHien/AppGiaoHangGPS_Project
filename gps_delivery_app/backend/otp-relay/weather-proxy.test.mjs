import assert from 'node:assert/strict';
import test from 'node:test';
import { createWeatherProxy } from './weather-proxy.mjs';

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    status(code) { this.statusCode = code; return this; },
    set(key, value) { this.headers[key] = value; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('Reject invalid coordinates before calling the upstream', async () => {
  const proxy = createWeatherProxy({ fetchImpl() { throw new Error('must not fetch'); } });
  for (const query of [{}, { lat: '', lon: '106' }, { lat: '91', lon: '106' }, { lat: ['10'], lon: '106' }]) {
    const res = responseRecorder();
    await proxy({ query }, res);
    assert.equal(res.statusCode, 400);
  }
});

test('Cache and coalesce requests while preserving provider expiry', async () => {
  let now = Date.parse('2026-10-27T06:00:00Z');
  let calls = 0;
  const body = { properties: { timeseries: [{ time: '2026-10-27T06:00:00Z', data: {} }] } };
  const proxy = createWeatherProxy({ now: () => now, fetchImpl: async (url, options) => {
    calls++;
    assert.equal(url.hostname, 'api.met.no');
    assert.equal(url.searchParams.get('lat'), '10.78');
    assert.match(options.headers['User-Agent'], /github.com/);
    if (calls === 1) return new Response(JSON.stringify(body), { headers: {
      expires: 'Tue, 27 Oct 2026 08:00:00 GMT',
      'last-modified': 'Tue, 27 Oct 2026 05:00:00 GMT',
    } });
    assert.equal(options.headers['If-Modified-Since'], 'Tue, 27 Oct 2026 05:00:00 GMT');
    return new Response(null, { status: 304 });
  } });
  const req = { query: { lat: '10.7769', lon: '106.6953' } };
  const first = responseRecorder();
  const second = responseRecorder();
  await Promise.all([proxy(req, first), proxy(req, second)]);
  assert.equal(calls, 1);
  assert.deepEqual(first.body, body);
  assert.deepEqual(second.body, body);
  now += 60 * 60 * 1000;
  await proxy(req, responseRecorder());
  assert.equal(calls, 1);
  now += 2 * 60 * 60 * 1000;
  await proxy(req, responseRecorder());
  assert.equal(calls, 2);
});

test('Respect upstream 429 cooldown and never fabricate weather on failure', async () => {
  let calls = 0;
  const proxy = createWeatherProxy({ fetchImpl: async () => {
    calls++;
    return new Response('', { status: 429, headers: { 'retry-after': '120' } });
  } });
  const req = { query: { lat: '10', lon: '106' } };
  const first = responseRecorder();
  const second = responseRecorder();
  await proxy(req, first);
  await proxy(req, second);
  assert.equal(first.statusCode, 429);
  assert.equal(second.statusCode, 429);
  assert.equal(calls, 1);
  assert.ok(Number(second.headers['Retry-After']) >= 119);
  assert.equal(first.body.properties, undefined);
});
