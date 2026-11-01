const endpoint = 'https://api.met.no/weatherapi/locationforecast/2.0/compact';
const userAgent = 'GHSTDelivery/1.0 https://github.com/PhamTriHien/AppGiaoHangGPS_Project';

export function createWeatherProxy({ fetchImpl = fetch, now = Date.now } = {}) {
  const cache = new Map();
  const pending = new Map();
  let retryAt = 0;

  async function load(latitude, longitude, key) {
    const previous = cache.get(key);
    if (previous && previous.expiresAt > now()) return previous;
    if (retryAt > now()) {
      throw Object.assign(new Error('Weather rate limited'), { status: 429 });
    }
    const uri = new URL(endpoint);
    uri.search = new URLSearchParams({ lat: latitude, lon: longitude });
    const response = await fetchImpl(uri, {
      headers: {
        'User-Agent': userAgent,
        Accept: 'application/json',
        ...(previous?.lastModified ? { 'If-Modified-Since': previous.lastModified } : {}),
      },
      signal: AbortSignal.timeout(8000),
    });
    if (response.status === 429) {
      const delay = Number(response.headers.get('retry-after')) || 60;
      retryAt = now() + Math.min(86400, Math.max(1, delay)) * 1000;
      throw Object.assign(new Error('Weather rate limited'), { status: 429 });
    }
    const unchanged = response.status === 304 && previous;
    if (!response.ok && !unchanged) throw new Error('Weather upstream failed');
    const data = unchanged ? previous.data : await response.json();
    if (!Array.isArray(data?.properties?.timeseries) || !data.properties.timeseries.length) {
      throw new Error('Invalid weather response');
    }
    const providerExpiry = Date.parse(response.headers.get('expires') || '');
    const item = {
      data,
      expiresAt: Math.max(now() + 15 * 60 * 1000, Number.isFinite(providerExpiry) ? providerExpiry : 0),
      lastModified: response.headers.get('last-modified') || previous?.lastModified,
    };
    if (cache.size >= 32 && !cache.has(key)) cache.delete(cache.keys().next().value);
    cache.set(key, item);
    return item;
  }

  return async (req, res) => {
    const rawLat = req.query?.lat;
    const rawLon = req.query?.lon;
    const latitude = typeof rawLat === 'string' && rawLat.trim() ? Number(rawLat) : NaN;
    const longitude = typeof rawLon === 'string' && rawLon.trim() ? Number(rawLon) : NaN;
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
      res.status(400).json({ error: 'Tọa độ không hợp lệ' });
      return;
    }
    const lat = latitude.toFixed(2);
    const lon = longitude.toFixed(2);
    const key = `${lat},${lon}`;
    try {
      let request = pending.get(key);
      if (!request) {
        request = load(lat, lon, key);
        pending.set(key, request);
      }
      let item;
      try {
        item = await request;
      } finally {
        if (pending.get(key) === request) pending.delete(key);
      }
      res.set('Expires', new Date(item.expiresAt).toUTCString());
      res.set('Cache-Control', 'private');
      if (item.lastModified) res.set('Last-Modified', item.lastModified);
      res.json(item.data);
    } catch (error) {
      const status = error?.status === 429 ? 429 : 502;
      if (status === 429) res.set('Retry-After', String(Math.max(1, Math.ceil((retryAt - now()) / 1000))));
      res.status(status).json({ error: 'Chưa tải được dự báo thời tiết' });
    }
  };
}
