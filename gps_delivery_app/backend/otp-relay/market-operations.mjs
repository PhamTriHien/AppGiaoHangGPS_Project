import express from 'express';
import { createCommerceDatabase } from './commerce-db.mjs';
import { IntegrationError } from './provider-http.mjs';
import { providerConfigured } from './integration-config.mjs';

// The public projection is enforced by SQL too: no address, phone or proof files.
export function createPublicTracking({ env = process.env, fetcher = fetch } = {}) {
  const router = express.Router();
  router.post('/tracking', (req, res, next) => {
    Promise.resolve().then(async () => {
      res.set('Cache-Control', 'no-store');
      if (!req.body || Object.keys(req.body).some(k => k !== 'token') ||
          typeof req.body.token !== 'string' || !/^[a-f0-9]{64}$/.test(req.body.token)) {
        throw new IntegrationError(404, 'Liên kết không tồn tại hoặc hết hạn.');
      }
      if (!providerConfigured('supabase', env)) throw new IntegrationError(503, 'Dịch vụ theo dõi tạm thời chưa khả dụng.');
      let response;
      try {
        response = await fetcher(new URL('/rest/v1/rpc/delivery_market_public_tracking', env.SUPABASE_URL), {
          method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
          headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_token: req.body.token }),
        });
        const chunks = []; let size = 0;
        for await (const chunk of response.body ?? []) {
          size += chunk.length;
          if (size > 4000) throw new Error('oversized');
          chunks.push(chunk);
        }
        const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        if (!response.ok) {
          if (data.code === 'PT404') throw new IntegrationError(404, 'Liên kết không tồn tại hoặc hết hạn.');
          throw new Error('unavailable');
        }
        if (!data || typeof data !== 'object' || Array.isArray(data) || !data.state) throw new Error('invalid');
        res.json(Object.fromEntries(['shop_name','state','delivery_status','updated_at','expires_at'].map(k => [k, data[k]])));
      } catch (error) {
        if (error instanceof IntegrationError) throw error;
        throw new IntegrationError(503, 'Dịch vụ theo dõi tạm thời chưa khả dụng.');
      }
    }).catch(next);
  });

  router.post('/tracking/lookup', (req, res, next) => {
    Promise.resolve().then(async () => {
      res.set('Cache-Control', 'no-store');
      const code = typeof req.body?.tracking_code === 'string' ? req.body.tracking_code.trim().toUpperCase() : '';
      const last4 = typeof req.body?.phone_last4 === 'string' ? req.body.phone_last4.trim() : '';
      if (!req.body || Array.isArray(req.body) || Object.keys(req.body).some(k => !['tracking_code', 'phone_last4'].includes(k)) ||
          !/^CL-[A-F0-9]{32}$/.test(code) || !/^[0-9]{4}$/.test(last4)) {
        throw new IntegrationError(404, 'Không tìm thấy vận đơn khớp mã vận đơn và 4 số cuối điện thoại.');
      }
      if (!providerConfigured('supabase', env)) throw new IntegrationError(503, 'Dịch vụ theo dõi tạm thời chưa khả dụng.');
      let response;
      try {
        response = await fetcher(new URL('/rest/v1/rpc/delivery_cloud_public_lookup', env.SUPABASE_URL), {
          method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
          headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_tracking_code: code, p_phone_last4: last4 }),
        });
        const chunks = []; let size = 0;
        for await (const chunk of response.body ?? []) {
          size += chunk.length;
          if (size > 16000) throw new Error('oversized');
          chunks.push(chunk);
        }
        const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        if (!response.ok) {
          if (data.code === 'PT404') throw new IntegrationError(404, 'Không tìm thấy vận đơn khớp mã vận đơn và 4 số cuối điện thoại.');
          throw new Error('unavailable');
        }
        if (!data || typeof data !== 'object' || Array.isArray(data) || !data.status) throw new Error('invalid');
        const timeline = Array.isArray(data.timeline)
          ? data.timeline.slice(0, 50).map(item => ({ action: item?.action ?? '', status: item?.status ?? '', created_at: item?.created_at ?? null }))
          : [];
        res.json({
          tracking_code: data.tracking_code,
          status: data.status,
          service_type: data.service_type,
          distance_meters: data.distance_meters,
          created_at: data.created_at,
          updated_at: data.updated_at,
          timeline,
        });
      } catch (error) {
        if (error instanceof IntegrationError) throw error;
        throw new IntegrationError(503, 'Dịch vụ theo dõi tạm thời chưa khả dụng.');
      }
    }).catch(next);
  });
  return router;
}

export function startMarketJobs({ env = process.env, database = createCommerceDatabase(env),
  schedule = setInterval, unschedule = clearInterval, onError = () => {} } = {}) {
  let running = false, stopped = false, pending;
  const tick = () => {
    if (stopped || running || env.MARKET_JOBS_ENABLED !== 'true' || !env.DATABASE_URL?.trim()) return pending ?? Promise.resolve();
    running = true;
    pending = database.query('select public.delivery_market_run_jobs($1) as result', [25])
      .catch(() => onError('market_jobs_unavailable'))
      .finally(() => { running = false; pending = undefined; });
    return pending;
  };
  const timer = schedule(tick, 15000);
  timer?.unref?.();
  return { tick, async close() { stopped = true; unschedule(timer); await pending; await database.close(); } };
}
