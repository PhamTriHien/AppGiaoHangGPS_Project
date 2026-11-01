import crypto from 'node:crypto';
import { appendFile, mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import nodemailer from 'nodemailer';
import pg from 'pg';
import { databaseConnectionOptions, validateDatabaseCa } from './database-connection.mjs';

const directory = path.dirname(fileURLToPath(import.meta.url));
const configPath = (env) => env.INTEGRATION_CONFIG_PATH?.trim()
  ? path.resolve(env.INTEGRATION_CONFIG_PATH.trim()) : path.join(directory, '.integration-config.json');
const queues = new Map();
const checks = new Map();
const bool = (label, defaultValue = 'true') => ({ label, type: 'boolean', defaultValue });
const field = (label, options = {}) => ({ label, ...options });
const secret = (label) => field(label, { secret: true });
const url = (label, defaultValue = '') => field(label, { type: 'url', defaultValue });

export const INTEGRATION_DEFINITIONS = {
  backend: { label: 'Triển khai backend', required: ['DATABASE_URL'], fields: {
    DATABASE_URL: secret('Kết nối PostgreSQL (DATABASE_URL)'),
    DATABASE_CA_CERT: field('Chung chi CA PostgreSQL (PEM)', { type: 'certificate' }),
    PUBLIC_BASE_URL: url('URL HTTPS công khai của backend', 'http://127.0.0.1:8787'),
    PUBLIC_APP_URL: url('URL ứng dụng nhận liên kết theo dõi'),
    MARKET_JOBS_ENABLED: bool('Tự xử lý đơn mua quá hạn (sau cập nhật schema)', 'false'),
  } },
  google: { label: 'Google OAuth desktop', toggle: 'GOOGLE_ENABLED', required: ['GOOGLE_CLIENT_ID'], fields: {
    GOOGLE_CLIENT_ID: field('OAuth Client ID'), GOOGLE_CLIENT_SECRET: secret('Client secret'),
  } },
  sms: { label: 'SMS OTP', toggle: 'SMS_ENABLED', required: ['SMS_PROVIDER', 'SMS_API_KEY'], fields: {
    SMS_PROVIDER: field('Nhà cung cấp', { type: 'select', options: ['TEXTBEE', 'ESMS', 'SPEEDSMS', 'TWILIO'] }),
    SMS_API_KEY: secret('API key / Account SID'), SMS_API_SECRET: secret('API secret / Auth token'),
    SMS_BRANDNAME: field('Device ID / Brandname / From / Verify SID'),
  } },
  supabase: { label: 'Supabase Cloud', toggle: 'SUPABASE_ENABLED', required: ['SUPABASE_URL', 'SUPABASE_ANON_KEY'], fields: {
    SUPABASE_URL: url('Project URL'), SUPABASE_ANON_KEY: secret('Publishable / anon key'),
    SUPABASE_SERVICE_ROLE_KEY: secret('Server secret / service role key'), DELIVERY_WEBHOOK_SECRET: secret('Webhook secret'),
  } },
  smtp: { label: 'Gmail / SMTP', toggle: 'SMTP_ENABLED', required: ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS'], fields: {
    SMTP_HOST: field('SMTP host', { defaultValue: 'smtp.gmail.com' }), SMTP_PORT: field('Port', { type: 'number', defaultValue: '465' }),
    SMTP_USER: field('Email gửi'), SMTP_PASS: secret('App Password'),
  } },
  photon: { label: 'Photon địa chỉ', toggle: 'PHOTON_ENABLED', required: ['PHOTON_BASE_URL'], fields: {
    PHOTON_BASE_URL: url('Base URL', 'https://photon.komoot.io/'), PHOTON_AUTOCOMPLETE: bool('Autocomplete', 'false'),
  } },
  trackasia: { label: 'TrackAsia Maps Việt Nam (Địa chỉ / Tuyến đường / ETA)', toggle: 'TRACKASIA_ENABLED', required: ['TRACKASIA_API_KEY'], fields: {
    TRACKASIA_API_KEY: secret('TrackAsia API key'),
  } },
  google_maps: { label: 'Google Maps Platform (Places / Geocoding / Routes)', toggle: 'GOOGLE_MAPS_ENABLED', required: ['GOOGLE_MAPS_API_KEY'], fields: {
    GOOGLE_MAPS_API_KEY: secret('Google Maps API key'),
  } },
  osrm: { label: 'OSRM tuyến đường / ETA', toggle: 'OSRM_ENABLED', required: ['OSRM_BASE_URL'], fields: {
    OSRM_BASE_URL: url('Base URL', 'https://router.project-osrm.org/'),
  } },
  banks: { label: 'VietQR danh mục ngân hàng', toggle: 'BANKS_ENABLED', required: [], fields: {} },
  weather: { label: 'MET Norway thời tiết', toggle: 'WEATHER_ENABLED', required: [], fields: {} },
  ocr: { label: 'OCR Việt / Anh', toggle: 'OCR_ENABLED', required: [], fields: {} },
  vroom: { label: 'VROOM phân tuyến', toggle: 'VROOM_ENABLED', required: ['VROOM_BASE_URL'], fields: {
    VROOM_BASE_URL: url('Base URL'),
  } },
  firebase: { label: 'Firebase Push', toggle: 'FIREBASE_ENABLED', required: ['GOOGLE_APPLICATION_CREDENTIALS'], fields: {
    GOOGLE_APPLICATION_CREDENTIALS: secret('Đường dẫn JSON service account trên server'),
  } },
  turnstile: { label: 'Cloudflare Turnstile', toggle: 'TURNSTILE_ENABLED', required: ['TURNSTILE_SITE_KEY', 'TURNSTILE_SECRET_KEY', 'TURNSTILE_HOSTNAME'], fields: {
    TURNSTILE_SITE_KEY: field('Site key'), TURNSTILE_SECRET_KEY: secret('Secret key'),
    TURNSTILE_HOSTNAME: field('Hostname'), TURNSTILE_ENFORCE_OTP: bool('Bắt buộc xác thực OTP', 'false'),
  } },
  telegram: { label: 'Telegram cảnh báo', toggle: 'TELEGRAM_ALERTS_ENABLED', required: ['TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHAT_ID'], fields: {
    TELEGRAM_BOT_TOKEN: secret('Bot token'), TELEGRAM_CHAT_ID: field('Chat ID'),
  } },
  gemini: { label: 'Gemini AI', toggle: 'GEMINI_ENABLED', required: ['GEMINI_API_KEY', 'GEMINI_MODEL'], fields: {
    GEMINI_API_KEY: secret('API key'), GEMINI_MODEL: field('Model'),
  } },
  ghn: { label: 'GHN vận chuyển', toggle: 'GHN_ENABLED', required: ['GHN_BASE_URL', 'GHN_TOKEN', 'GHN_SHOP_ID'], fields: {
    GHN_BASE_URL: url('Base URL', 'https://dev-online-gateway.ghn.vn/shiip/public-api/'),
    GHN_TOKEN: secret('API token'), GHN_SHOP_ID: field('Shop ID'), GHN_WEBHOOK_SECRET: secret('Webhook secret'),
  } },
  payos: { label: 'payOS thanh toán', toggle: 'PAYOS_ENABLED', required: ['PAYOS_CLIENT_ID', 'PAYOS_API_KEY', 'PAYOS_CHECKSUM_KEY'], fields: {
    PAYOS_CLIENT_ID: field('Client ID'), PAYOS_API_KEY: secret('API key'), PAYOS_CHECKSUM_KEY: secret('Checksum key'),
    PAYOS_RETURN_URL: url('URL trả về', 'http://127.0.0.1:8080/#/cloud'),
    PAYOS_CANCEL_URL: url('URL hủy', 'http://127.0.0.1:8080/#/cloud'),
  } },
  momo: { label: 'MoMo thanh toán', available: false, required: ['MOMO_PARTNER_CODE', 'MOMO_ACCESS_KEY', 'MOMO_SECRET_KEY'], fields: {
    MOMO_PARTNER_CODE: field('Partner code'), MOMO_ACCESS_KEY: secret('Access key'), MOMO_SECRET_KEY: secret('Secret key'),
  } },
  vnpay: { label: 'VNPAY thanh toán', available: false, required: ['VNPAY_TMN_CODE', 'VNPAY_HASH_SECRET'], fields: {
    VNPAY_TMN_CODE: field('TMN code'), VNPAY_HASH_SECRET: secret('Hash secret'),
  } },
  meilisearch: { label: 'Meilisearch tìm kiếm', toggle: 'MEILISEARCH_ENABLED', required: ['MEILISEARCH_URL', 'MEILISEARCH_MASTER_KEY'], fields: {
    MEILISEARCH_URL: url('Base URL'), MEILISEARCH_MASTER_KEY: secret('API key'),
  } },
};
const defaultOff = new Set(['ghn', 'payos', 'telegram', 'meilisearch', 'sms', 'google_maps', 'trackasia']);
for (const [id, definition] of Object.entries(INTEGRATION_DEFINITIONS)) {
  if (definition.toggle) definition.fields[definition.toggle] = bool('Cho phép backend sử dụng', defaultOff.has(id) ? 'false' : 'true');
}
const fieldsByKey = new Map(Object.entries(INTEGRATION_DEFINITIONS).flatMap(([provider, definition]) =>
  Object.entries(definition.fields).map(([key, value]) => [key, { ...value, provider }])));
const identityKeys = new Set(['SUPABASE_URL', 'SUPABASE_ANON_KEY']);
const localOnlyKeys = identityKeys;
const cloudExcludedKeys = new Set(['DATABASE_URL', 'DATABASE_CA_CERT', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']);

export class ConfigError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export function configValue(key, env = process.env) {
  return String(env[key] ?? fieldsByKey.get(key)?.defaultValue ?? '').trim();
}
function providerReady(provider, env) {
  const definition = INTEGRATION_DEFINITIONS[provider];
  if (provider === 'sms') {
    const type = configValue('SMS_PROVIDER', env);
    if (!['TEXTBEE', 'ESMS', 'SPEEDSMS', 'TWILIO'].includes(type) ||
        (['ESMS', 'TWILIO'].includes(type) && !configValue('SMS_API_SECRET', env)) ||
        (type === 'TWILIO' && !configValue('SMS_BRANDNAME', env))) return false;
  }
  return Boolean(definition && definition.required.every(key => configValue(key, env)));
}
export function providerConfigured(provider, env = process.env) {
  const definition = INTEGRATION_DEFINITIONS[provider];
  return Boolean(providerReady(provider, env) && definition.available !== false &&
    (!definition.toggle || configValue(definition.toggle, env) === 'true'));
}
export function integrationStatus(env = process.env) {
  return Object.fromEntries(Object.entries(INTEGRATION_DEFINITIONS).map(([provider, definition]) => [provider, {
    label: definition.label, available: definition.available !== false,
    configured: providerReady(provider, env), enabled: providerConfigured(provider, env),
    lastCheck: checks.get(provider) ?? null,
    fields: Object.entries(definition.fields).map(([key, metadata]) => ({
      key, label: metadata.label, type: metadata.type ?? 'text', secret: metadata.secret === true,
      ...(metadata.options ? { options: metadata.options } : {}),
      configured: Boolean(configValue(key, env)), localOnly: localOnlyKeys.has(key),
      ...(metadata.secret ? {} : { value: configValue(key, env) }),
    })),
  }]));
}

function validate(key, value) {
  const metadata = fieldsByKey.get(key);
  if (!metadata) throw new ConfigError(`Khóa cấu hình không được hỗ trợ: ${key}`);
  if (metadata.type === 'certificate') {
    try { validateDatabaseCa(value); } catch { throw new ConfigError(`Chung chi CA khong hop le: ${key}`); }
    return;
  }
  if (typeof value !== 'string' || value.length > 8192 || /[\r\n\0]/.test(value)) throw new ConfigError(`Giá trị không hợp lệ: ${key}`);
  if (!value) return;
  if (key === 'DATABASE_URL') {
    let parsed;
    try { parsed = new URL(value); } catch { throw new ConfigError('Kết nối PostgreSQL không hợp lệ.'); }
    if (!['postgres:', 'postgresql:'].includes(parsed.protocol) || !parsed.hostname || !parsed.pathname.slice(1) || parsed.hash) {
      throw new ConfigError('Cần PostgreSQL connection string có tên máy chủ và database.');
    }
  }
  if (metadata.options && !metadata.options.includes(value)) throw new ConfigError(`Lựa chọn không hợp lệ: ${key}`);
  if (key === 'GOOGLE_CLIENT_ID' && !value.endsWith('.apps.googleusercontent.com')) throw new ConfigError('Google Client ID không hợp lệ.');
  if (metadata.type === 'boolean' && !['true', 'false'].includes(value)) throw new ConfigError(`Cần true / false: ${key}`);
  if (key === 'SMTP_PORT' && (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > 65535)) throw new ConfigError('SMTP port không hợp lệ.');
  if (metadata.type === 'url') {
    let parsed;
    try { parsed = new URL(value); } catch { throw new ConfigError(`URL không hợp lệ: ${key}`); }
    const paymentRedirect = ['PAYOS_RETURN_URL', 'PAYOS_CANCEL_URL'].includes(key);
    if (!['https:', 'http:'].includes(parsed.protocol) || parsed.username || parsed.password || (!paymentRedirect && (parsed.search || parsed.hash))) throw new ConfigError(`URL không hợp lệ: ${key}`);
    if (paymentRedirect && parsed.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(parsed.hostname)) throw new ConfigError('URL thanh toán công khai yêu cầu HTTPS.');
    if (key === 'SUPABASE_URL' && parsed.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(parsed.hostname)) throw new ConfigError('Supabase yêu cầu HTTPS.');
    if (key === 'GHN_BASE_URL' && (parsed.protocol !== 'https:' || !['dev-online-gateway.ghn.vn', 'online-gateway.ghn.vn'].includes(parsed.hostname) || parsed.port || parsed.pathname !== '/shiip/public-api/')) throw new ConfigError('Dùng endpoint GHN staging hoặc production chính thức, kết thúc bằng /shiip/public-api/.');
  }
  if (key === 'TURNSTILE_HOSTNAME' && !/^[a-zA-Z0-9.-]+$/.test(value)) throw new ConfigError('Hostname không bao gồm scheme hoặc đường dẫn.');
  if (key === 'SUPABASE_ANON_KEY' && (value.startsWith('sb_secret_') || jwtRole(value) === 'service_role')) throw new ConfigError('Chỉ dùng publishable / anon key cho ứng dụng.');
}
function jwtRole(value) { try { return JSON.parse(Buffer.from(value.split('.')[1], 'base64url')).role; } catch { return null; } }

async function readStored(env) {
  try {
    const value = JSON.parse(await readFile(configPath(env), 'utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ConfigError('Tệp cấu hình backend không hợp lệ.', 500);
    return value;
  } catch (error) { if (error.code === 'ENOENT') return {}; throw error; }
}

async function withConfigDb(env, db, operation) {
  if (db) return operation(db);
  if (env !== process.env || !configValue('DATABASE_URL', env)) return null;
  const client = new pg.Client({
    ...databaseConnectionOptions(env),
    connectionTimeoutMillis: 8000,
    query_timeout: 8000,
    application_name: 'ghst-backend-config',
  });
  await client.connect();
  try { return await operation(client); }
  finally { await client.end().catch(() => {}); }
}

export async function loadIntegrationConfig({ env = process.env, db } = {}) {
  const values = await readStored(env);
  for (const [key, value] of Object.entries(values)) if (fieldsByKey.has(key)) validate(key, String(value ?? ''));
  for (const [key, value] of Object.entries(values)) if (fieldsByKey.has(key)) env[key] = String(value ?? '');
  try {
    await withConfigDb(env, db, async client => {
      const existing = await client.query('select key, value from public.delivery_backend_config');
      const cloudValues = new Map();
      for (const row of existing.rows) {
        if (!fieldsByKey.has(row.key) || cloudExcludedKeys.has(row.key)) continue;
        const text = String(row.value ?? '');
        validate(row.key, text);
        cloudValues.set(row.key, text);
      }
      for (const key of fieldsByKey.keys()) {
        if (cloudExcludedKeys.has(key) || cloudValues.has(key)) continue;
        const hasLocal = Object.hasOwn(values, key) || Object.hasOwn(env, key);
        if (!hasLocal) continue;
        const seedValue = String((Object.hasOwn(values, key) ? values[key] : env[key]) ?? '').trim();
        validate(key, seedValue);
        await client.query(
          `insert into public.delivery_backend_config (key, value, updated_by, updated_at)
           values ($1, $2, 'bootstrap', now())
           on conflict (key) do nothing`,
          [key, seedValue],
        );
        cloudValues.set(key, seedValue);
      }
      for (const [key, value] of cloudValues) {
        env[key] = value;
        values[key] = value;
      }
    });
  } catch (error) {
    if (db && error?.code !== '42P01') throw error;
  }
  return values;
}

export async function updateIntegrationConfig(values, { clear = [], actor = 'unknown', local = false, env = process.env, db } = {}) {
  if (!values || typeof values !== 'object' || Array.isArray(values) || !Array.isArray(clear) || clear.some(key => typeof key !== 'string')) throw new ConfigError('Cấu hình phải là một object và clear là danh sách khóa.');
  const patch = Object.fromEntries(Object.entries(values).map(([key, value]) => {
    if (!['string', 'number', 'boolean'].includes(typeof value) && value !== null) throw new ConfigError(`Giá trị không hợp lệ: ${key}`);
    return [key, String(value ?? '').trim()];
  }));
  for (const key of clear) patch[key] = '';
  for (const [key, value] of Object.entries(patch)) {
    validate(key, value);
    if (!local && localOnlyKeys.has(key) && value !== configValue(key, env)) throw new ConfigError('Chỉ thay đổi project xác thực tại máy chủ backend.', 403);
  }
  const filename = configPath(env);
  const previous = queues.get(filename) ?? Promise.resolve();
  const operation = previous.catch(() => {}).then(async () => {
    const stored = await readStored(env);
    const changed = Object.keys(patch).filter(key => patch[key] !== configValue(key, env));
    if (changed.length) {
      const candidate = { ...env, ...patch };
      if (candidate.TURNSTILE_ENFORCE_OTP === 'true' && !providerConfigured('turnstile', candidate)) throw new ConfigError('Cần đầy đủ cấu hình Turnstile trước khi bắt buộc OTP.');
      try {
        await withConfigDb(candidate, db, async client => {
          const actorName = String(actor || 'unknown').slice(0, 120);
          await client.query('begin');
          try {
            for (const key of changed) {
              if (cloudExcludedKeys.has(key)) continue;
              await client.query(
                `insert into public.delivery_backend_config (key, value, updated_by, updated_at)
                 values ($1, $2, $3, now())
                 on conflict (key) do update
                   set value = excluded.value,
                       updated_by = excluded.updated_by,
                       updated_at = now()`,
                [key, patch[key], actorName],
              );
            }
            await client.query(
              'insert into public.delivery_backend_config_audit (actor, changed) values ($1, $2::jsonb)',
              [actorName, JSON.stringify(changed)],
            );
            await client.query('commit');
          } catch (innerError) {
            await client.query('rollback').catch(() => {});
            throw innerError;
          }
        });
      } catch (error) {
        if (error?.code !== '42P01') {
          if (db) throw error;
          throw new ConfigError('Không lưu được cấu hình lên database cloud. Kiểm tra kết nối PostgreSQL.', 503);
        }
      }
      await mkdir(path.dirname(filename), { recursive: true });
      const temporary = `${filename}.${crypto.randomUUID()}.tmp`;
      await writeFile(temporary, `${JSON.stringify({ ...stored, ...patch }, null, 2)}\n`, { mode: 0o600 });
      await rename(temporary, filename);
      Object.assign(env, patch);
      for (const key of changed) checks.delete(fieldsByKey.get(key).provider);
      await appendFile(path.join(path.dirname(filename), '.integration-audit.log'), `${JSON.stringify({ at: new Date().toISOString(), actor, changed })}\n`, { mode: 0o600 });
    }
    return { changed, status: integrationStatus(env) };
  });
  queues.set(filename, operation);
  try { return await operation; } finally { if (queues.get(filename) === operation) queues.delete(filename); }
}

export async function integrationAudit(env = process.env, { db } = {}) {
  try {
    const cloudEntries = await withConfigDb(env, db, async client => {
      const res = await client.query(
        'select at, actor, changed from public.delivery_backend_config_audit order by id desc limit 30',
      );
      return res.rows.map(row => ({
        at: row.at instanceof Date ? row.at.toISOString() : String(row.at),
        actor: row.actor,
        changed: row.changed,
      }));
    });
    if (Array.isArray(cloudEntries) && cloudEntries.length > 0) return cloudEntries;
  } catch (error) {
    if (db && error?.code !== '42P01') throw error;
  }
  try {
    const raw = await readFile(path.join(path.dirname(configPath(env)), '.integration-audit.log'), 'utf8');
    return raw.trim().split('\n').filter(Boolean).slice(-30).reverse().map(line => JSON.parse(line));
  } catch (error) { if (error.code === 'ENOENT') return []; throw error; }
}

export async function testIntegration(provider, { env = process.env, fetcher = fetch } = {}) {
  if (!Object.hasOwn(INTEGRATION_DEFINITIONS, provider)) throw new ConfigError('Dịch vụ không tồn tại.');
  const started = Date.now();
  const finish = (ok, message, verified = ok) => {
    const result = { provider, ok, verified, message, latencyMs: Date.now() - started, checkedAt: new Date().toISOString() };
    checks.set(provider, result);
    return result;
  };
  if (!providerConfigured(provider, env)) return finish(false, 'Chưa cấu hình, đang tắt hoặc chưa có adapter nghiệp vụ.');
  const getJson = async (endpoint, options = {}) => {
    const response = await fetcher(endpoint, { ...options, redirect: 'error', signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('upstream');
    return response.json();
  };
  try {
    if (provider === 'supabase') {
      const settings = await getJson(new URL('/auth/v1/settings', configValue('SUPABASE_URL', env)), { headers: { apikey: env.SUPABASE_ANON_KEY } });
      if (!settings.external) throw new Error('invalid');
    } else if (provider === 'smtp') {
      const transport = nodemailer.createTransport({ host: env.SMTP_HOST, port: Number(env.SMTP_PORT || 465), secure: Number(env.SMTP_PORT || 465) === 465,
        connectionTimeout: 8000, socketTimeout: 10000, auth: { user: env.SMTP_USER, pass: env.SMTP_PASS } });
      try { await transport.verify(); } finally { transport.close(); }
    } else if (provider === 'photon') {
      const endpoint = new URL('api/?q=Ben%20Thanh&limit=1', `${configValue('PHOTON_BASE_URL', env).replace(/\/$/, '')}/`);
      if (!Array.isArray((await getJson(endpoint, { headers: { 'User-Agent': 'GHSTDelivery/1.0' } })).features)) throw new Error('invalid');
    } else if (provider === 'trackasia') {
      const key = env.TRACKASIA_API_KEY;
      const autoUrl = new URL('https://maps.track-asia.com/api/v1/autocomplete');
      autoUrl.search = new URLSearchParams({ text: 'Chợ Bến Thành', size: '1', lang: 'vi', key }).toString();
      const geoUrl = new URL('https://maps.track-asia.com/api/v2/geocode/json');
      geoUrl.search = new URLSearchParams({ latlng: '10.77251,106.69802', language: 'vi', key }).toString();
      const routeUrl = new URL('https://maps.track-asia.com/route/v1/car/106.69802,10.77251;106.69902,10.77978.json');
      routeUrl.search = new URLSearchParams({ overview: 'false', key }).toString();
      const [placesOk, geoOk, routeOk] = await Promise.all([
        getJson(autoUrl).then(d => Array.isArray(d.features)).catch(() => false),
        getJson(geoUrl).then(d => ['OK', 'ZERO_RESULTS'].includes(d.status)).catch(() => false),
        getJson(routeUrl).then(d => d.code === 'Ok').catch(() => false),
      ]);
      const missing = [!placesOk && 'Autocomplete', !geoOk && 'Geocoding', !routeOk && 'Routing'].filter(Boolean);
      if (missing.length) return finish(false, `Kiểm tra TrackAsia thất bại tại: ${missing.join(', ')}.`);
      return finish(true, 'Đã xác minh đủ 3 dịch vụ TrackAsia (Autocomplete, Geocoding, Routing).');
    } else if (provider === 'google_maps') {
      const geocodeUrl = new URL('https://maps.googleapis.com/maps/api/geocode/json');
      geocodeUrl.search = new URLSearchParams({ latlng: '10.77251,106.69802', language: 'vi', key: env.GOOGLE_MAPS_API_KEY, solution_id: 'gmp_git_agentskills_v1' }).toString();
      const commonHeaders = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': env.GOOGLE_MAPS_API_KEY,
        'X-Goog-Maps-Solution-ID': 'gmp_git_agentskills_v1',
      };
      const [geoOk, placesOk, routesOk] = await Promise.all([
        getJson(geocodeUrl).then(d => ['OK', 'ZERO_RESULTS'].includes(d.status)).catch(() => false),
        getJson('https://places.googleapis.com/v1/places:searchText', {
          method: 'POST',
          headers: { ...commonHeaders, 'X-Goog-FieldMask': 'places.id' },
          body: JSON.stringify({ textQuery: 'Chợ Bến Thành', languageCode: 'vi', regionCode: 'VN', pageSize: 1 }),
        }).then(d => Array.isArray(d.places) || Object.keys(d || {}).length === 0).catch(() => false),
        getJson('https://routes.googleapis.com/directions/v2:computeRoutes', {
          method: 'POST',
          headers: { ...commonHeaders, 'X-Goog-FieldMask': 'routes.distanceMeters' },
          body: JSON.stringify({
            origin: { location: { latLng: { latitude: 10.77251, longitude: 106.69802 } } },
            destination: { location: { latLng: { latitude: 10.77978, longitude: 106.69902 } } },
            travelMode: 'DRIVE',
          }),
        }).then(d => Array.isArray(d.routes) && d.routes.length > 0).catch(() => false),
      ]);
      const missingApis = [
        !placesOk && 'Places API (New)',
        !geoOk && 'Geocoding API',
        !routesOk && 'Routes API',
      ].filter(Boolean);
      if (missingApis.length) {
        return finish(false, `Kiểm tra thất bại hoặc chưa bật đủ API trên Google Cloud: ${missingApis.join(', ')}.`);
      }
      return finish(true, 'Đã xác minh đủ 3 dịch vụ Google Maps (Places API New, Geocoding API, Routes API).');
    } else if (provider === 'osrm') {
      const data = await getJson(new URL('route/v1/driving/106.7,10.77;106.71,10.78?overview=false', `${configValue('OSRM_BASE_URL', env).replace(/\/$/, '')}/`));
      if (data.code !== 'Ok') throw new Error('invalid');
    } else if (provider === 'banks') {
      if ((await getJson('https://api.vietqr.io/v2/banks')).code !== '00') throw new Error('invalid');
    } else if (provider === 'weather') {
      const data = await getJson('https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=10.77&lon=106.7', { headers: { 'User-Agent': 'GHSTDelivery/1.0 https://github.com/PhamTriHien/AppGiaoHangGPS_Project' } });
      if (!data.properties?.timeseries?.length) throw new Error('invalid');
    } else if (provider === 'telegram') {
      if (!(await getJson(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getMe`)).ok) throw new Error('invalid');
    } else if (provider === 'gemini') {
      const model = env.GEMINI_MODEL.replace(/^models\//, '');
      await getJson(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}`, { headers: { 'x-goog-api-key': env.GEMINI_API_KEY } });
    } else if (provider === 'ghn') {
      const data = await getJson(new URL('master-data/province', env.GHN_BASE_URL), { headers: { Token: env.GHN_TOKEN, ShopId: env.GHN_SHOP_ID } });
      if (data.code !== 200 || !Array.isArray(data.data)) throw new Error('invalid');
    } else if (provider === 'meilisearch') {
      const data = await getJson(new URL('/stats', env.MEILISEARCH_URL), { headers: { Authorization: `Bearer ${env.MEILISEARCH_MASTER_KEY}` } });
      if (!data.indexes || typeof data.indexes !== 'object') throw new Error('invalid');
    } else if (provider === 'firebase') {
      const json = JSON.parse(await readFile(env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
      if (!json.project_id || !json.private_key || !json.client_email) throw new Error('invalid');
      return finish(false, 'JSON hợp lệ; chưa xác minh giao push trên thiết bị.', false);
    } else if (provider === 'ocr') {
      for (const language of ['vie', 'eng']) {
        const model = await stat(path.join(directory, '.cache', 'ocr', `${language}.traineddata`));
        if (model.size < 1000) throw new Error('invalid');
      }
      return finish(true, 'Đã kiểm tra hai mô hình OCR trên backend.');
    } else {
      return finish(false, 'Chưa kiểm tra nghiệp vụ thực tế; không tự gửi giao dịch hoặc thử thách.', false);
    }
    return finish(true, 'Kết nối đã được xác minh; không tạo đơn hoặc gửi thanh toán.');
  } catch {
    return finish(false, 'Kiểm tra thất bại. Kiểm tra cấu hình, quyền tài khoản hoặc kết nối mạng.');
  }
}
