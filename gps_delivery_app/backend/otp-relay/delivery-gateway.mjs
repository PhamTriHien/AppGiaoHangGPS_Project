import express from 'express';
import { configValue, providerConfigured } from './integration-config.mjs';
import { coordinate, IntegrationError, providerJson } from './provider-http.mjs';

export function createDeliveryGateway({ env = process.env, fetcher = fetch,
  operatorOnly = (_req, res) => res.status(403).json({ error: 'Can quyen dieu hanh.' }) } = {}) {
  const router = express.Router();
  const cache = new Map();
  const pending = new Map();
  let nextReverseAt = 0;
  const route = fn => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
  const requireProvider = id => {
    if (!providerConfigured(id, env)) throw new IntegrationError(503, 'Dich vu chua duoc cau hinh hoac dang tat.');
  };
  const endpoint = (key, suffix) => new URL(suffix, `${configValue(key, env).replace(/\/$/, '')}/`);
  const cached = async (url, options = {}, ttl = 60000) => {
    // Cache only public catalogues and routing data, never privileged provider responses.
    const key = url.toString();
    const old = cache.get(key);
    if (old && old.expires > Date.now()) return old.data;
    if (pending.has(key)) return pending.get(key);
    const operation = providerJson(url, options, fetcher).then(data => {
      if (cache.size >= 100) cache.delete(cache.keys().next().value);
      cache.set(key, { data, expires: Date.now() + ttl });
      return data;
    });
    pending.set(key, operation);
    try { return await operation; } finally { pending.delete(key); }
  };
  const points = raw => {
    if (typeof raw !== 'string' || raw.length > 600) throw new IntegrationError(400, 'Toa do khong hop le.');
    const rows = raw.split(';').map(row => {
      const parts = row.split(',');
      if (parts.length !== 2 || parts.some(part => !part.trim())) throw new IntegrationError(400, 'Toa do khong hop le.');
      return parts.map(Number);
    });
    if (rows.length < 2 || rows.length > 11 || !rows.every(coordinate)) throw new IntegrationError(400, 'Can 2-11 toa do hop le.');
    return rows.map(row => row.map(n => n.toFixed(5)).join(',')).join(';');
  };
  router.get('/route', route(async (req, res) => {
    requireProvider('osrm');
    const coords = points(req.query.coordinates);
    if (coords.split(';').length !== 2) throw new IntegrationError(400, 'Tuyen duong can hai diem.');
    const url = endpoint('OSRM_BASE_URL', `route/v1/driving/${coords}`);
    url.search = 'overview=full&geometries=geojson';
    const result = await cached(url);
    if (result.code !== 'Ok' || !result.routes?.length) throw new IntegrationError(502, 'Khong tim duoc tuyen duong.');
    res.json(result);
  }));
  router.get('/matrix', route(async (req, res) => {
    requireProvider('osrm');
    const coords = points(req.query.coordinates);
    const count = coords.split(';').length;
    const url = endpoint('OSRM_BASE_URL', `table/v1/driving/${coords}`);
    url.search = new URLSearchParams({ sources: Array.from({ length: count - 1 }, (_, i) => i).join(';'),
      destinations: String(count - 1), annotations: 'duration,distance', skip_waypoints: 'true' }).toString();
    const result = await cached(url);
    if (result.code !== 'Ok' || !Array.isArray(result.durations) || !Array.isArray(result.distances)) throw new IntegrationError(502, 'Khong tinh duoc ETA.');
    res.json(result);
  }));
  router.get('/banks', route(async (_req, res) => {
    requireProvider('banks');
    const result = await cached('https://api.vietqr.io/v2/banks', {}, 86400000);
    if (result.code !== '00' || !Array.isArray(result.data)) throw new IntegrationError(502, 'Danh muc ngan hang khong hop le.');
    res.json(result);
  }));
  router.get('/reverse', route(async (req, res) => {
    requireProvider('photon');
    if (typeof req.query.lon !== 'string' || typeof req.query.lat !== 'string' || !req.query.lon.trim() || !req.query.lat.trim() ||
        !coordinate([Number(req.query.lon), Number(req.query.lat)])) throw new IntegrationError(400, 'Toa do khong hop le.');
    const url = endpoint('PHOTON_BASE_URL', 'reverse');
    url.search = new URLSearchParams({ lat: Number(req.query.lat).toFixed(5), lon: Number(req.query.lon).toFixed(5), limit: '1' }).toString();
    const old = cache.get(url.toString());
    if ((!old || old.expires <= Date.now()) && !pending.has(url.toString())) {
      if (Date.now() < nextReverseAt) throw new IntegrationError(429, 'Vui long cho truoc khi tra cuu tiep.');
      nextReverseAt = Date.now() + 1100;
    }
    const result = await cached(url, {}, 300000);
    const properties = result.features?.[0]?.properties;
    const address = properties ? [...new Set([properties.name, [properties.housenumber, properties.street].filter(Boolean).join(' '),
      properties.district, properties.city, properties.state, properties.country].filter(Boolean))].join(', ') : '';
    res.json({ address, attribution: 'OpenStreetMap contributors / Photon' });
  }));
  const integer = (value, max = 100000000) => Number.isInteger(value) && value > 0 && value <= max;
  const ghn = async (suffix, body) => {
    requireProvider('ghn');
    const data = await providerJson(endpoint('GHN_BASE_URL', suffix), {
      method: body ? 'POST' : 'GET', headers: { Token: env.GHN_TOKEN, ShopId: env.GHN_SHOP_ID, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    }, fetcher);
    if (data.code !== 200) throw new IntegrationError(502, 'GHN chua tra ve ket qua hop le.');
    return { data: data.data };
  };
  router.get('/admin/ghn/provinces', operatorOnly, route(async (_req, res) => res.json(await ghn('master-data/province'))));
  router.post('/admin/ghn/quote', operatorOnly, route(async (req, res) => {
    const body = req.body ?? {};
    if (!integer(body.to_district_id) || typeof body.to_ward_code !== 'string' || !/^\d{1,12}$/.test(body.to_ward_code) ||
        !integer(body.weight, 200000) || ![2, 5].includes(body.service_type_id)) throw new IntegrationError(400, 'Can quan/huyen, ma phuong, khoi luong gram va loai dich vu GHN.');
    const payload = { to_district_id: body.to_district_id, to_ward_code: body.to_ward_code, weight: body.weight, service_type_id: body.service_type_id };
    for (const key of ['from_district_id', 'length', 'width', 'height', 'insurance_value']) {
      if (body[key] != null) {
        if (!integer(body[key])) throw new IntegrationError(400, 'Thong so GHN khong hop le.');
        payload[key] = body[key];
      }
    }
    if (body.from_ward_code != null) {
      if (typeof body.from_ward_code !== 'string' || !/^\d{1,12}$/.test(body.from_ward_code)) throw new IntegrationError(400, 'Ma phuong khong hop le.');
      payload.from_ward_code = body.from_ward_code;
    }
    res.json(await ghn('v2/shipping-order/fee', payload));
  }));
  router.post('/admin/search', operatorOnly, route(async (req, res) => {
    requireProvider('meilisearch');
    const { q, index } = req.body ?? {};
    if (!['orders', 'merchants', 'drivers'].includes(index) || typeof q !== 'string' || !q.trim() || q.length > 200)
      throw new IntegrationError(400, 'Truy van tim kiem khong hop le.');
    const result = await providerJson(endpoint('MEILISEARCH_URL', `indexes/${index}/search`), {
      method: 'POST', headers: { Authorization: `Bearer ${env.MEILISEARCH_MASTER_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: q.trim(), limit: 20 }),
    }, fetcher);
    if (!Array.isArray(result.hits)) throw new IntegrationError(502, 'Ket qua tim kiem khong hop le.');
    res.json({ hits: result.hits, processingTimeMs: result.processingTimeMs, estimatedTotalHits: result.estimatedTotalHits });
  }));
  return router;
}
