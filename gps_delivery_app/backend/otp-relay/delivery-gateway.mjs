import express from 'express';
import { configValue, providerConfigured } from './integration-config.mjs';
import { coordinate, IntegrationError, providerJson } from './provider-http.mjs';

const parseGoogleDuration = value =>
  typeof value === 'string' && /^\d+(?:\.\d+)?s$/.test(value) ? Number(value.slice(0, -1)) : NaN;

function decodeEncodedPolyline(encoded) {
  if (typeof encoded !== 'string' || !encoded) return [];
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let b = 0;
    let shift = 0;
    let result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    if (b >= 0x20) break;
    lat += (result & 1) ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    if (index >= encoded.length) break;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    if (b >= 0x20) break;
    lng += (result & 1) ? ~(result >> 1) : (result >> 1);
    const point = [Number((lng / 1e5).toFixed(5)), Number((lat / 1e5).toFixed(5))];
    if (coordinate(point)) points.push(point);
  }
  return points;
}

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
  const cached = async (url, options = {}, ttl = 60000, cacheKey = url.toString()) => {
    // Cache only public catalogues and routing data, never privileged provider responses.
    const old = cache.get(cacheKey);
    if (old && old.expires > Date.now()) return old.data;
    if (pending.has(cacheKey)) return pending.get(cacheKey);
    const operation = providerJson(url, options, fetcher).then(data => {
      if (cache.size >= 100) cache.delete(cache.keys().next().value);
      cache.set(cacheKey, { data, expires: Date.now() + ttl });
      return data;
    });
    pending.set(cacheKey, operation);
    try { return await operation; } finally { pending.delete(cacheKey); }
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
    const useTrackAsia = providerConfigured('trackasia', env);
    const useGoogle = !useTrackAsia && providerConfigured('google_maps', env);
    if (!useTrackAsia && !useGoogle) requireProvider('osrm');
    const coords = points(req.query.coordinates);
    const pairs = coords.split(';');
    if (pairs.length !== 2) throw new IntegrationError(400, 'Tuyen duong can hai diem.');
    if (useTrackAsia) {
      const tUrl = new URL(`https://maps.track-asia.com/route/v1/car/${coords}.json`);
      tUrl.search = new URLSearchParams({ overview: 'full', geometries: 'geojson', key: env.TRACKASIA_API_KEY }).toString();
      const tResult = await cached(tUrl, {}, 60000, `trackasia:route:${coords}`);
      if (tResult.code !== 'Ok' || !tResult.routes?.length) throw new IntegrationError(502, 'Khong tim duoc tuyen duong.');
      return res.json({ code: 'Ok', routes: tResult.routes, attribution: 'TrackAsia' });
    }
    if (useGoogle) {
      const [[lon1, lat1], [lon2, lat2]] = pairs.map(pair => pair.split(',').map(Number));
      const payload = await cached('https://routes.googleapis.com/directions/v2:computeRoutes', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': env.GOOGLE_MAPS_API_KEY,
          'X-Goog-Maps-Solution-ID': 'gmp_git_agentskills_v1',
          'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
        },
        body: JSON.stringify({
          origin: { location: { latLng: { latitude: lat1, longitude: lon1 } } },
          destination: { location: { latLng: { latitude: lat2, longitude: lon2 } } },
          travelMode: 'DRIVE',
          routingPreference: 'TRAFFIC_AWARE',
          languageCode: 'vi',
          units: 'METRIC',
        }),
      }, 60000, `gmaps:route:${coords}`);
      const first = payload?.routes?.[0];
      const distance = Number(first?.distanceMeters ?? (first?.duration === '0s' ? 0 : NaN));
      const duration = parseGoogleDuration(first?.duration);
      const decoded = decodeEncodedPolyline(first?.polyline?.encodedPolyline);
      const coordinates = decoded.length >= 2 ? decoded : (distance === 0 ? [[lon1, lat1], [lon2, lat2]] : []);
      if (!first || !Number.isFinite(distance) || distance < 0 || !Number.isFinite(duration) || duration < 0 || coordinates.length < 2) {
        throw new IntegrationError(502, 'Khong tim duoc tuyen duong.');
      }
      return res.json({
        code: 'Ok',
        routes: [{ distance, duration, geometry: { type: 'LineString', coordinates } }],
        attribution: 'Google Maps',
      });
    }
    const url = endpoint('OSRM_BASE_URL', `route/v1/driving/${coords}`);
    url.search = 'overview=full&geometries=geojson';
    const result = await cached(url);
    if (result.code !== 'Ok' || !result.routes?.length) throw new IntegrationError(502, 'Khong tim duoc tuyen duong.');
    res.json(result);
  }));
  router.get('/matrix', route(async (req, res) => {
    const useTrackAsia = providerConfigured('trackasia', env);
    const useGoogle = !useTrackAsia && providerConfigured('google_maps', env);
    if (!useTrackAsia && !useGoogle) requireProvider('osrm');
    const coords = points(req.query.coordinates);
    const pairs = coords.split(';');
    const count = pairs.length;
    // Default: every point to the last one (ETA). full=1: all-pairs table for stop ordering.
    const full = req.query.full === '1';
    const oneToLast = full ? {} : {
      sources: Array.from({ length: count - 1 }, (_, i) => i).join(';'),
      destinations: String(count - 1),
    };
    if (useTrackAsia) {
      const tUrl = new URL(`https://maps.track-asia.com/distance-matrix/v1/car/${coords}.json`);
      tUrl.search = new URLSearchParams({
        ...oneToLast,
        annotations: 'duration,distance',
        key: env.TRACKASIA_API_KEY,
      }).toString();
      const tResult = await cached(tUrl, {}, 60000, `trackasia:matrix:${full ? 'full:' : ''}${coords}`);
      if (tResult.code !== 'Ok' || !Array.isArray(tResult.durations) || !Array.isArray(tResult.distances)) {
        throw new IntegrationError(502, 'Khong tinh duoc ETA.');
      }
      return res.json({ code: 'Ok', durations: tResult.durations, distances: tResult.distances, attribution: 'TrackAsia' });
    }
    if (useGoogle) {
      const parsed = pairs.map(pair => pair.split(',').map(Number));
      const waypoint = ([lon, lat]) => ({ waypoint: { location: { latLng: { latitude: lat, longitude: lon } } } });
      const origins = (full ? parsed : parsed.slice(0, -1)).map(waypoint);
      const destinations = full ? parsed.map(waypoint) : [waypoint(parsed[parsed.length - 1])];
      const elements = await cached('https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': env.GOOGLE_MAPS_API_KEY,
          'X-Goog-Maps-Solution-ID': 'gmp_git_agentskills_v1',
          'X-Goog-FieldMask': 'originIndex,destinationIndex,duration,distanceMeters,status,condition',
        },
        body: JSON.stringify({
          origins,
          destinations,
          travelMode: 'DRIVE',
          routingPreference: 'TRAFFIC_AWARE',
        }),
      }, 60000, `gmaps:matrix:${full ? 'full:' : ''}${coords}`);
      if (!Array.isArray(elements)) throw new IntegrationError(502, 'Khong tinh duoc ETA.');
      const durations = Array.from({ length: origins.length }, () => Array(destinations.length).fill(null));
      const distances = Array.from({ length: origins.length }, () => Array(destinations.length).fill(null));
      for (const item of elements) {
        const idx = item?.originIndex ?? 0;
        const destIdx = item?.destinationIndex ?? 0;
        if (!Number.isInteger(idx) || idx < 0 || idx >= origins.length ||
            !Number.isInteger(destIdx) || destIdx < 0 || destIdx >= destinations.length) continue;
        if ((item?.status?.code ?? 0) !== 0 || item?.condition !== 'ROUTE_EXISTS') continue;
        const duration = parseGoogleDuration(item.duration);
        const distance = Number(item.distanceMeters ?? (item.duration === '0s' ? 0 : NaN));
        if (Number.isFinite(duration) && duration >= 0 && Number.isFinite(distance) && distance >= 0) {
          durations[idx][destIdx] = duration;
          distances[idx][destIdx] = distance;
        }
      }
      if (durations.some(row => row.includes(null)) || distances.some(row => row.includes(null))) {
        throw new IntegrationError(502, 'Khong tinh duoc ETA.');
      }
      return res.json({ code: 'Ok', durations, distances, attribution: 'Google Maps' });
    }
    const url = endpoint('OSRM_BASE_URL', `table/v1/driving/${coords}`);
    url.search = new URLSearchParams({ ...oneToLast, annotations: 'duration,distance', skip_waypoints: 'true' }).toString();
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
    if (!providerConfigured('trackasia', env) && !providerConfigured('google_maps', env) && !providerConfigured('photon', env)) {
      throw new IntegrationError(503, 'Dich vu chua duoc cau hinh hoac dang tat.');
    }
    if (typeof req.query.lon !== 'string' || typeof req.query.lat !== 'string' || !req.query.lon.trim() || !req.query.lat.trim() ||
        !coordinate([Number(req.query.lon), Number(req.query.lat)])) throw new IntegrationError(400, 'Toa do khong hop le.');
    const lat = Number(req.query.lat).toFixed(5);
    const lon = Number(req.query.lon).toFixed(5);
    if (providerConfigured('trackasia', env)) {
      const cacheKey = `trackasia:reverse:${lat},${lon}`;
      const hit = cache.get(cacheKey);
      if (hit && hit.expires > Date.now()) return res.json(hit.data);
      const tUrl = new URL('https://maps.track-asia.com/api/v2/geocode/json');
      tUrl.search = new URLSearchParams({ latlng: `${lat},${lon}`, language: 'vi', key: env.TRACKASIA_API_KEY }).toString();
      const tData = await providerJson(tUrl, {}, fetcher);
      if (!['OK', 'ZERO_RESULTS'].includes(tData.status)) {
        throw new IntegrationError(502, 'Khong tra cuu duoc dia chi tu toa do.');
      }
      const payload = { address: tData.results?.[0]?.formatted_address || '', attribution: 'TrackAsia' };
      if (cache.size >= 100) cache.delete(cache.keys().next().value);
      cache.set(cacheKey, { data: payload, expires: Date.now() + 300000 });
      return res.json(payload);
    }
    if (providerConfigured('google_maps', env)) {
      const cacheKey = `gmaps:reverse:${lat},${lon}`;
      const hit = cache.get(cacheKey);
      if (hit && hit.expires > Date.now()) return res.json(hit.data);
      const gUrl = new URL('https://maps.googleapis.com/maps/api/geocode/json');
      gUrl.search = new URLSearchParams({
        latlng: `${lat},${lon}`,
        language: 'vi',
        key: env.GOOGLE_MAPS_API_KEY,
        solution_id: 'gmp_git_agentskills_v1',
      }).toString();
      const gData = await providerJson(gUrl, {}, fetcher);
      if (!['OK', 'ZERO_RESULTS'].includes(gData.status)) {
        throw new IntegrationError(502, 'Khong tra cuu duoc dia chi tu toa do.');
      }
      const payload = { address: gData.results?.[0]?.formatted_address || '', attribution: 'Google Maps' };
      if (cache.size >= 100) cache.delete(cache.keys().next().value);
      cache.set(cacheKey, { data: payload, expires: Date.now() + 300000 });
      return res.json(payload);
    }
    const url = endpoint('PHOTON_BASE_URL', 'reverse');
    url.search = new URLSearchParams({ lat, lon, limit: '1' }).toString();
    const old = cache.get(url.toString());
    if ((!old || old.expires <= Date.now()) && !pending.has(url.toString())) {
      if (Date.now() < nextReverseAt) throw new IntegrationError(429, 'Vui long cho truoc khi tra cuu tiep.');
      nextReverseAt = Date.now() + 400;
    }
    const result = await cached(url, { headers: { 'User-Agent': 'GHSTDelivery/1.0' } }, 300000);
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
