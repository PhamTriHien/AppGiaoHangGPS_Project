import express from 'express';
import { configValue, providerConfigured } from './integration-config.mjs';
import { IntegrationError, providerJson } from './provider-http.mjs';

// Compatibility for local SQLite accounts. Cloud clients use Supabase Auth sessions.
export function createLocalAuthGateway({ env = process.env, authenticate, fetcher = fetch, consumeChallenge } = {}) {
  const router = express.Router();
  const route = fn => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
  router.use(authenticate);
  router.use((req, res, next) => req.deliveryIdentity?.local === true ? next() : res.status(403).json({ error: 'Chi danh cho ung dung local.' }));
  router.get('/config', (_req, res) => res.set('Cache-Control', 'no-store').json({
    googleClientId: providerConfigured('google', env) ? configValue('GOOGLE_CLIENT_ID', env) : '',
    sms: providerConfigured('sms', env),
    smsProvider: configValue('SMS_PROVIDER', env),
    twilioVerify: configValue('SMS_PROVIDER', env) === 'TWILIO' && /^VA[a-fA-F0-9]{32}$/.test(configValue('SMS_BRANDNAME', env)),
  }));
  const phoneAndCode = body => {
    if (typeof body?.phone !== 'string' || !/^\+84\d{9,10}$/.test(body.phone) || !/^\d{6}$/.test(body?.otp ?? ''))
      throw new IntegrationError(400, 'So dien thoai hoac OTP khong hop le.');
    return { phone: body.phone, otp: body.otp };
  };
  const twilio = async (suffix, payload) => {
    const account = configValue('SMS_API_KEY', env);
    const sender = configValue('SMS_BRANDNAME', env);
    if (!/^AC[a-fA-F0-9]{32}$/.test(account)) throw new IntegrationError(503, 'Twilio Account SID khong hop le.');
    const verify = /^VA[a-fA-F0-9]{32}$/.test(sender);
    const url = verify ? `https://verify.twilio.com/v2/Services/${sender}/${suffix}` : `https://api.twilio.com/2010-04-01/Accounts/${account}/Messages.json`;
    return providerJson(url, { method: 'POST', headers: {
      Authorization: `Basic ${Buffer.from(`${account}:${configValue('SMS_API_SECRET', env)}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    }, body: new URLSearchParams(payload).toString() }, fetcher);
  };
  router.post('/sms', consumeChallenge || ((_req, _res, next) => next()), route(async (req, res) => {
    if (!providerConfigured('sms', env)) throw new IntegrationError(503, 'SMS chua duoc cau hinh hoac dang tat.');
    const { phone, otp } = phoneAndCode(req.body);
    const provider = configValue('SMS_PROVIDER', env);
    const key = configValue('SMS_API_KEY', env);
    const sender = configValue('SMS_BRANDNAME', env);
    const message = `[GHST] Ma OTP cua ban la ${otp}. Hieu luc 120 giay.`;
    let channel = provider;
    let result;
    if (provider === 'TEXTBEE') {
      result = await providerJson('https://api.textbee.dev/api/v1/gateway/send-sms', { method: 'POST',
        headers: { 'x-api-key': key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ recipients: [phone], message, ...(sender ? { deviceId: sender } : {}) }),
      }, fetcher);
      if (!result.smsBatchId && !result.data?.smsBatchId) throw new IntegrationError(502, 'TextBee chua xac nhan tiep nhan SMS.');
    } else if (provider === 'ESMS') {
      result = await providerJson('https://rest.esms.vn/MainService.svc/json/SendMultipleMessage_V4_post_json/', { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ApiKey: key, SecretKey: configValue('SMS_API_SECRET', env),
          Phone: `0${phone.slice(3)}`, Content: message, Brandname: sender, SmsType: '2' }),
      }, fetcher);
      if (String(result.CodeResult) !== '100') throw new IntegrationError(502, 'eSMS chua xac nhan tiep nhan SMS.');
    } else if (provider === 'SPEEDSMS') {
      result = await providerJson('https://api.speedsms.vn/index.php/sms/send', { method: 'POST', headers: {
        Authorization: `Basic ${Buffer.from(`${key}:x`).toString('base64')}`, 'Content-Type': 'application/json',
      }, body: JSON.stringify({ to: [`0${phone.slice(3)}`], content: message, sms_type: /^\d+$/.test(sender) ? 5 : sender ? 3 : 2,
        ...(sender ? { sender } : {}) }) }, fetcher);
      if (result.status !== 'success') throw new IntegrationError(502, 'SpeedSMS chua xac nhan tiep nhan SMS.');
    } else if (provider === 'TWILIO') {
      const verify = /^VA[a-fA-F0-9]{32}$/.test(sender);
      result = await twilio('Verifications', verify ? { To: phone, Channel: 'sms', Locale: 'vi' } : { To: phone, From: sender, Body: message });
      if (!result.sid || result.error_code || ['failed', 'undelivered', 'canceled'].includes(result.status)) throw new IntegrationError(502, 'Twilio chua xac nhan tiep nhan SMS.');
      channel = verify ? 'TWILIO_VERIFY_V2' : 'TWILIO_SMS';
    }
    res.json({ accepted: true, channel });
  }));
  router.post('/sms/verify', route(async (req, res) => {
    if (!providerConfigured('sms', env) || env.SMS_PROVIDER !== 'TWILIO' || !/^VA[a-fA-F0-9]{32}$/.test(env.SMS_BRANDNAME || '')) throw new IntegrationError(503, 'Twilio Verify dang tat.');
    const { phone, otp } = phoneAndCode(req.body);
    const result = await twilio('VerificationCheck', { To: phone, Code: otp });
    res.json({ approved: result.status === 'approved' && result.valid === true });
  }));
  router.post('/google/exchange', route(async (req, res) => {
    if (!providerConfigured('google', env)) throw new IntegrationError(503, 'Google OAuth dang tat.');
    const { code, codeVerifier } = req.body ?? {};
    if (typeof code !== 'string' || !code || code.length > 4096 || typeof codeVerifier !== 'string' || !/^[A-Za-z0-9._~-]{43,128}$/.test(codeVerifier))
      throw new IntegrationError(400, 'Phien OAuth khong hop le.');
    const token = await providerJson('https://oauth2.googleapis.com/token', { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ code,
        client_id: env.GOOGLE_CLIENT_ID, ...(env.GOOGLE_CLIENT_SECRET ? { client_secret: env.GOOGLE_CLIENT_SECRET } : {}),
        redirect_uri: 'http://127.0.0.1:8765/oauth2callback', grant_type: 'authorization_code', code_verifier: codeVerifier }).toString(),
    }, fetcher);
    if (!token.access_token) throw new IntegrationError(502, 'Google chua cap phien xac thuc.');
    const user = await providerJson('https://www.googleapis.com/oauth2/v3/userinfo', { headers: { Authorization: `Bearer ${token.access_token}` } }, fetcher);
    if (!user.sub || typeof user.email !== 'string' || user.email_verified !== true) throw new IntegrationError(403, 'Email Google chua duoc xac minh.');
    res.set('Cache-Control', 'no-store').json({ email: user.email, name: user.name || user.email.split('@')[0], sub: user.sub });
  }));
  return router;
}
