import crypto from 'node:crypto';
import express from 'express';
import { IntegrationError, providerJson } from './delivery-integrations.mjs';
import { providerConfigured } from './integration-config.mjs';

export function createTurnstile({ env = process.env, fetcher = fetch, authenticate } = {}) {
  const router = express.Router();
  const sessions = new Map();
  const grants = new Map();
  const enabled = () => env.TURNSTILE_ENFORCE_OTP === 'true';
  const sweep = () => {
    for (const map of [sessions, grants]) for (const [id, value] of map) if (value.expires < Date.now()) map.delete(id);
  };
  const ready = () => {
    if (!providerConfigured('turnstile', env))
      throw new IntegrationError(503, 'Chua cau hinh xac thuc chong bot.');
  };
  router.get('/auth-policy', (_req, res) => res.json({ turnstileRequired: enabled() }));
  router.post('/challenge-session', authenticate, (_req, res, next) => {
    try {
      ready(); sweep();
      if (sessions.size > 1000) throw new IntegrationError(429, 'Qua nhieu phien xac thuc.');
      const id = crypto.randomBytes(24).toString('hex');
      sessions.set(id, { expires: Date.now() + 180000, status: 'pending', owner: _req.deliveryIdentity.id });
      const origin = env.PUBLIC_BASE_URL || `http://127.0.0.1:${Number(env.PORT || 8787)}`;
      res.json({ id, url: new URL(`/delivery/challenge/${id}`, origin).toString() });
    } catch (e) { next(e); }
  });
  router.get('/challenge-session/:id', authenticate, (req, res) => {
    sweep();
    const session = sessions.get(req.params.id);
    if (!session || session.owner !== req.deliveryIdentity.id) return res.status(404).json({ error: 'Phien da het han.' });
    res.set('Cache-Control', 'no-store').json({ status: session.status, ...(session.grant ? { grant: session.grant } : {}) });
  });
  router.get('/challenge/:id', (req, res) => {
    sweep();
    if (!sessions.has(req.params.id)) return res.status(404).send('Phien da het han.');
    res.set('Cache-Control', 'no-store');
    res.set('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; connect-src 'self'; style-src 'unsafe-inline'");
    res.type('html').send(`<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GO-MAU</title><body style="font-family:Arial;padding:24px"><h2>GO-MAU</h2><p id="status">Xac thuc yeu cau gui OTP</p><div id="challenge"></div><script>function boot(){turnstile.render('#challenge',{sitekey:${JSON.stringify(env.TURNSTILE_SITE_KEY).replace(/</g, '\\u003c')},action:'otp',callback:async function(token){const r=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})});document.getElementById('status').textContent=r.ok?'Da xac thuc. Quay lai ung dung.':'Xac thuc that bai. Vui long thu lai.';}})}</script><script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=boot" async defer></script></body></html>`);
  });
  router.post('/challenge/:id', async (req, res, next) => {
    try {
      ready(); sweep();
      const session = sessions.get(req.params.id);
      if (!session || session.status !== 'pending') throw new IntegrationError(400, 'Phien khong hop le.');
      session.status = 'verifying';
      const token = req.body?.token;
      if (typeof token !== 'string' || token.length > 2048) throw new IntegrationError(400, 'Token khong hop le.');
      const result = await providerJson('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ secret: env.TURNSTILE_SECRET_KEY,
          response: token, remoteip: req.ip, idempotency_key: crypto.randomUUID() }),
      }, fetcher);
      if (!result.success || result.action !== 'otp' || result.hostname !== env.TURNSTILE_HOSTNAME)
        throw new IntegrationError(403, 'Xac thuc chong bot that bai.');
      const grant = crypto.randomBytes(24).toString('hex');
      grants.set(grant, { owner: session.owner, expires: Date.now() + 120000 });
      session.status = 'verified'; session.grant = grant;
      res.json({ verified: true });
    } catch (e) { sessions.delete(req.params.id); next(e); }
  });
  return { router, consume(req, res, next) {
    if (!enabled()) return next();
    sweep();
    const grant = grants.get(req.body?.turnstileGrant);
    if (!grant || grant.owner !== req.deliveryIdentity?.id) return res.status(403).json({ error: 'Can xac thuc chong bot truoc khi gui OTP.' });
    grants.delete(req.body.turnstileGrant);
    next();
  } };
}
