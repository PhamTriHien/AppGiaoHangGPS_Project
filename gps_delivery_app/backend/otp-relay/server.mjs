import 'dotenv/config';
import './database-connection.mjs';
import crypto from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import nodemailer from 'nodemailer';
import { createWeatherProxy } from './weather-proxy.mjs';
import { createDeliveryIntegrations, createIdentity, operatorOnly, IntegrationError } from './delivery-integrations.mjs';
import { createNotificationRouter } from './delivery-notifications.mjs';
import { createTurnstile } from './turnstile.mjs';
import { ConfigError, configValue, loadIntegrationConfig, providerConfigured } from './integration-config.mjs';
import { createLocalAuthGateway } from './local-auth-gateway.mjs';
import { createCloudOrders } from './cloud-orders.mjs';
import { createPaymentGateway } from './payment-gateway.mjs';
import { createGhnGateway } from './ghn-gateway.mjs';
import { createPublicTracking, startMarketJobs } from './market-operations.mjs';

await loadIntegrationConfig({ env: process.env });

const port = Number(process.env.PORT || 8787);
const bindHost = process.env.BIND_HOST || '127.0.0.1';
const relayToken = process.env.RELAY_TOKEN?.trim() || '';
const allowedOrigins = (process.env.WEB_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

if (!relayToken && !providerConfigured('supabase')) {
  throw new Error(
    'Cần cấu hình Supabase để đăng nhập cloud hoặc RELAY_TOKEN để thiết lập backend local.',
  );
}

function normalizeOrigin(value) {
  try {
    const parsed = new URL(String(value || '').trim());
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed.origin : '';
  } catch {
    return '';
  }
}

function isAllowedOrigin(origin, req) {
  if (!origin) return true;
  if (allowedOrigins.includes(origin)) return true;
  for (const candidate of [
    configValue('PUBLIC_BASE_URL', process.env),
    configValue('PUBLIC_APP_URL', process.env),
    process.env.RENDER_EXTERNAL_URL,
    process.env.RAILWAY_PUBLIC_DOMAIN ? `https://${process.env.RAILWAY_PUBLIC_DOMAIN}` : '',
  ]) {
    const dynamicOrigin = normalizeOrigin(candidate);
    if (dynamicOrigin && origin === dynamicOrigin) return true;
  }
  const host = req.get('host');
  return Boolean(host && origin === `${req.protocol}://${host}`);
}

const app = express();
app.disable('x-powered-by');
if (
  ['1', 'true'].includes(String(process.env.TRUST_PROXY || '').trim().toLowerCase()) ||
  process.env.RENDER === 'true' ||
  Boolean(process.env.RAILWAY_ENVIRONMENT)
) {
  app.set('trust proxy', 1);
}
app.use((req, res, next) => ['/delivery/ocr','/delivery/cloud/media','/delivery/cloud/attachments','/delivery/cloud/pod'].includes(req.path) ? next() : express.json({ limit: '32kb' })(req, res, next));
app.use(
  cors((req, callback) => {
    const origin = req.get('origin');
    if (isAllowedOrigin(origin, req)) {
      callback(null, { origin: true });
      return;
    }
    callback(new Error('Origin không được phép'));
  }),
);

const otpLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Bạn đã gửi quá nhiều yêu cầu OTP. Hãy thử lại sau.' },
});

function tokenMatches(value) {
  const received = Buffer.from(value || '');
  const expected = Buffer.from(relayToken);
  return (
    expected.length > 0 && received.length === expected.length &&
    crypto.timingSafeEqual(received, expected)
  );
}

function isEmail(value) {
  return typeof value === 'string' &&
    value.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'go-mau-otp-relay' });
});

const weatherLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 60,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});
const authenticateDelivery = createIdentity({ tokenMatches });
const deliveryLimiter = rateLimit({ windowMs: 60000, limit: 90, standardHeaders: 'draft-7', legacyHeaders: false });
const ocrLimiter = rateLimit({ windowMs: 60000, limit: 5, standardHeaders: 'draft-7', legacyHeaders: false });
app.use('/delivery/ocr', ocrLimiter);
app.use('/delivery', deliveryLimiter);
app.use('/delivery', createPublicTracking());
const turnstile = createTurnstile({ authenticate: authenticateDelivery });
app.use('/delivery', turnstile.router);
app.use('/delivery/local-auth', otpLimiter, createLocalAuthGateway({ authenticate: authenticateDelivery, consumeChallenge: turnstile.consume }));
app.use('/delivery', createPaymentGateway({ authenticate: authenticateDelivery }));
app.use('/delivery', createGhnGateway({ authenticate: authenticateDelivery, operatorOnly }));
app.use('/delivery/cloud', createCloudOrders({ authenticate: authenticateDelivery }));
app.use('/delivery', createNotificationRouter({ authenticate: authenticateDelivery }));
app.use('/delivery', createDeliveryIntegrations({ authenticate: authenticateDelivery, operatorOnly }));
app.get('/delivery/weather', weatherLimiter, authenticateDelivery, (_req, res, next) => {
  if (!providerConfigured('weather')) return res.status(503).json({ error: 'Dich vu thoi tiet dang tat.' });
  next();
}, createWeatherProxy());

app.post('/otp-email', otpLimiter, authenticateDelivery, turnstile.consume, async (req, res) => {
  const authorization = req.get('authorization') || '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length).trim()
    : '';
  if (!tokenMatches(token)) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const recipient = typeof req.body?.to === 'string'
    ? req.body.to.trim()
    : '';
  const otp = typeof req.body?.otp === 'string'
    ? req.body.otp.trim()
    : '';
  if (!isEmail(recipient) || !/^\d{6}$/.test(otp)) {
    res.status(400).json({ error: 'Email hoặc OTP không hợp lệ' });
    return;
  }

  try {
    if (!providerConfigured('smtp')) return res.status(503).json({ error: 'Dich vu email dang tat.' });
    const mailer = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com', port: Number(process.env.SMTP_PORT || 465),
      secure: Number(process.env.SMTP_PORT || 465) === 465, connectionTimeout: 10000, socketTimeout: 15000,
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
    await mailer.sendMail({
      from: `GO-MAU <${process.env.SMTP_USER}>`,
      to: recipient,
      subject: '[GO-MAU] Mã xác thực OTP',
      text: `Mã OTP của bạn là ${otp}. Mã có hiệu lực trong 120 giây.`,
      html: [
        '<div style="font-family:Arial,sans-serif;max-width:460px">',
        '<h2>GO-MAU - Mã xác thực OTP</h2>',
        `<p>Mã xác thực của bạn là: <strong style="font-size:28px;letter-spacing:6px">${otp}</strong></p>`,
        '<p>Mã có hiệu lực trong 120 giây.</p>',
        '</div>',
      ].join(''),
    });
    res.json({ success: true });
  } catch (error) {
    console.error('SMTP delivery failed.');
    res.status(502).json({ error: 'Không gửi được email OTP' });
  }
});

const defaultAdminWebDir = fileURLToPath(new URL('./public-admin', import.meta.url));
const staticWebDir = process.env.STATIC_WEB_DIR?.trim()
  ? path.resolve(process.env.STATIC_WEB_DIR.trim())
  : (existsSync(path.join(defaultAdminWebDir, 'index.html')) ? defaultAdminWebDir : '');

if (staticWebDir && existsSync(path.join(staticWebDir, 'index.html'))) {
  const indexHtmlPath = path.join(staticWebDir, 'index.html');
  const rawIndexHtml = readFileSync(indexHtmlPath, 'utf8');
  const adminHashBootstrap = '<script>if(location.pathname==="/"&&(!location.hash||location.hash==="#"||location.hash==="#/"))location.replace("/#/admin");</script>';
  const adminPortalHtml = rawIndexHtml.includes('</head>')
    ? rawIndexHtml.replace('</head>', `${adminHashBootstrap}</head>`)
    : `${adminHashBootstrap}${rawIndexHtml}`;
  const sendSpaIndex = (_req, res) => {
    res.set('Cache-Control', 'no-store');
    res.type('html').send(process.env.ADMIN_PORTAL_ONLY !== 'false' ? adminPortalHtml : rawIndexHtml);
  };
  app.get('/', sendSpaIndex);
  app.use(express.static(staticWebDir, { index: false, maxAge: '1h' }));
  app.get(['/admin', '/admin/', '/cloud-admin', '/cloud-admin/', '/track', '/track/', '/share', '/share/'], sendSpaIndex);
}

app.use((error, _req, res, _next) => {
  if (error instanceof IntegrationError || error instanceof ConfigError) {
    res.status(error.status).json({ error: error.message });
    return;
  }
  if (error.type === 'entity.too.large') {
    res.status(413).json({ error: 'Du lieu gui len qua lon.' });
    return;
  }
  if (error.type === 'entity.parse.failed') {
    res.status(400).json({ error: 'JSON khong hop le.' });
    return;
  }
  if (error?.message === 'Origin không được phép') {
    res.status(403).json({ error: error.message });
    return;
  }
  console.error('Unhandled backend error.');
  res.status(500).json({ error: 'Lỗi máy chủ relay OTP' });
});

const server = app.listen(port, bindHost, () => {
  const actualPort = server.address()?.port ?? port;
  console.log(`GO-MAU OTP relay đang chạy tại http://${bindHost}:${actualPort}`);
  if (port !== 0) {
    if (providerConfigured('supabase')) {
      fetch(new URL('/auth/v1/settings', process.env.SUPABASE_URL), { headers: { apikey: process.env.SUPABASE_ANON_KEY }, signal: AbortSignal.timeout(8000) }).then(r => r.arrayBuffer()).catch(() => {});
    }
    if (providerConfigured('photon')) {
      const photonBase = `${configValue('PHOTON_BASE_URL', process.env).replace(/\/$/, '')}/`;
      fetch(new URL('reverse?lat=10.77690&lon=106.70090&limit=1', photonBase), { headers: { 'User-Agent': 'GHSTDelivery/1.0' }, signal: AbortSignal.timeout(12000) }).then(r => r.arrayBuffer()).catch(() => {});
    }
  }
});
const marketJobs = startMarketJobs();
for (const signal of ['SIGINT','SIGTERM']) process.once(signal, () => {
  Promise.all([new Promise(resolve => server.close(resolve)),marketJobs.close()]).finally(() => process.exit(0));
});
