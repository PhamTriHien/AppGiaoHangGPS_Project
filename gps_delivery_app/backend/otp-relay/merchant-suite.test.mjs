import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createCloudOrders } from './cloud-orders.mjs';

test('Merchant Suite HTTP enforces action allowlist, bounded JSON, user JWT forwarding and safe RPC errors', async t => {
  const calls = [];
  let local = true;
  let status = 200;
  let data = { shops: [], selected_shop_id: null, kpis: null };

  const app = express();
  app.use(express.json());
  app.use(
    '/cloud',
    createCloudOrders({
      env: { SUPABASE_URL: 'https://project.supabase.co', SUPABASE_ANON_KEY: 'public' },
      authenticate(req, _res, next) {
        req.deliveryIdentity = { id: 'merchant-user', token: 'verified-merchant-jwt', local };
        next();
      },
      fetcher: async (url, options) => {
        calls.push({ url: String(url), options, body: JSON.parse(options.body) });
        return new Response(JSON.stringify(data), { status });
      },
    }),
  );
  app.use((error, _req, res, _next) => res.status(error.status || 500).json({ error: error.message }));

  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise(resolve => server.once('listening', resolve));

  const post = (action, body) =>
    fetch(`http://127.0.0.1:${server.address().port}/cloud/merchant/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

  assert.equal((await post('dashboard', {})).status, 401);
  assert.equal(calls.length, 0);

  local = false;
  for (const [action, body] of [
    ['delivery_is_operator', {}],
    ['drop_table', {}],
    ['dashboard', []],
    ['orders_list', { search: 'x'.repeat(16001) }],
  ]) {
    assert.equal((await post(action, body)).status, 400);
  }
  assert.equal(calls.length, 0);

  for (const action of [
    'dashboard',
    'shop_quick_pause',
    'product_quick_update',
    'stock_ledger',
    'promotions',
    'orders_list',
    'aftersales_inbox',
  ]) {
    const response = await post(action, { shop_id: '00000000-0000-4000-8000-000000000001' });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(calls.at(-1).url, 'https://project.supabase.co/rest/v1/rpc/delivery_merchant_suite');
    assert.equal(calls.at(-1).body.p_action, action);
    assert.equal(calls.at(-1).options.headers.Authorization, 'Bearer verified-merchant-jwt');
  }

  status = 404;
  data = { code: 'PGRST202', message: 'internal SQL function missing' };
  const missing = await post('dashboard', {});
  assert.equal(missing.status, 503);
  assert.match((await missing.json()).error, /quản trị/);
});
