import 'dotenv/config';
import dns from 'node:dns';
import https from 'node:https';
import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { configValue, loadIntegrationConfig, providerConfigured } from './integration-config.mjs';

const RECOVERY_EMAIL_SUBJECT = '[GHST EXPRESS] Mã xác thực khôi phục mật khẩu';
const RECOVERY_EMAIL_TEMPLATE = [
  '<div style="font-family:\'Segoe UI\',Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:2px solid #111111;background:#F7F5EE;color:#111111">',
  '<div style="display:inline-block;background:#C6FF00;border:1.5px solid #111111;padding:4px 10px;font-family:Consolas,monospace;font-size:11px;font-weight:900;margin-bottom:14px">GHST • GIAO HÀNG SIÊU TỐC</div>',
  '<h2 style="margin:0 0 10px;font-size:20px;font-weight:900">Khôi phục mật khẩu tài khoản</h2>',
  '<p style="margin:0 0 14px;font-size:14px;line-height:1.55">Nhập mã xác nhận email gồm 6 chữ số bên dưới vào ứng dụng GHST EXPRESS để đặt mật khẩu mới:</p>',
  '<div style="margin:16px 0;padding:14px 18px;background:#FFFFFF;border:2px solid #111111;text-align:center;font-family:Consolas,monospace;font-size:30px;font-weight:900;letter-spacing:8px;color:#6C3CE9">{{ .Token }}</div>',
  '<p style="margin:0;font-size:12.5px;color:#4B5563">Mã có hiệu lực trong 15 phút và chỉ sử dụng một lần. Nếu bạn không yêu cầu khôi phục mật khẩu, vui lòng bỏ qua email này.</p>',
  '</div>',
].join('\n');

const CONFIRMATION_EMAIL_SUBJECT = '[GHST EXPRESS] Xác nhận đăng ký tài khoản';
const CONFIRMATION_EMAIL_TEMPLATE = [
  '<div style="font-family:\'Segoe UI\',Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;border:2px solid #111111;background:#F7F5EE;color:#111111">',
  '<div style="display:inline-block;background:#C6FF00;border:1.5px solid #111111;padding:4px 10px;font-family:Consolas,monospace;font-size:11px;font-weight:900;margin-bottom:14px">GHST • GIAO HÀNG SIÊU TỐC</div>',
  '<h2 style="margin:0 0 10px;font-size:20px;font-weight:900">Xác nhận địa chỉ email</h2>',
  '<p style="margin:0 0 14px;font-size:14px;line-height:1.55">Chào mừng bạn đến với GHST EXPRESS. Bấm nút bên dưới để kích hoạt tài khoản:</p>',
  '<p style="margin:16px 0"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 18px;background:#6C3CE9;color:#FFFFFF;text-decoration:none;font-weight:900;border:2px solid #111111">XÁC NHẬN EMAIL</a></p>',
  '<p style="margin:12px 0 0;font-size:13px">Mã xác nhận dự phòng: <strong style="font-family:Consolas,monospace;font-size:16px;letter-spacing:2px">{{ .Token }}</strong></p>',
  '</div>',
].join('\n');

export function googleCloudTarget(env) {
  const url = new URL(configValue('SUPABASE_URL', env));
  const match = /^([a-z]{20})\.supabase\.co$/.exec(url.hostname);
  if (url.protocol !== 'https:' || !match || url.username || url.password ||
      url.port || url.search || url.hash || !['', '/'].includes(url.pathname)) {
    throw new Error('A hosted Supabase project URL is required.');
  }
  return { project: match[1], origin: url.origin };
}

export function googleCloudPatch(current, env) {
  if (typeof current.external_google_enabled !== 'boolean' || !Object.hasOwn(current, 'uri_allow_list')) {
    throw new Error('Incomplete Supabase Auth settings; no settings were changed.');
  }
  const clientId = configValue('GOOGLE_CLIENT_ID', env);
  const secret = configValue('GOOGLE_CLIENT_SECRET', env);
  if (!clientId.endsWith('.apps.googleusercontent.com') || !secret) {
    throw new Error('Saved Google Client ID and Client Secret are required.');
  }
  const existingIds = String(current.external_google_client_id || '')
    .split(',').map(value => value.trim()).filter(Boolean);
  if (existingIds.length && !existingIds.includes(clientId)) {
    throw new Error('Supabase has a different Google Client ID; no settings were changed.');
  }
  if (current.uri_allow_list != null && typeof current.uri_allow_list !== 'string') {
    throw new Error('Unexpected Supabase redirect configuration; no settings were changed.');
  }
  const redirects = new Set((current.uri_allow_list || '').split(',').map(value => value.trim()).filter(Boolean));
  redirects.add('http://127.0.0.1:8080/');
  redirects.add('http://localhost:8080/');
  redirects.add('http://127.0.0.1:8766/auth/callback');
  redirects.add('com.giaohanggps.gpsdelivery://auth/callback');
  const publicApp = configValue('PUBLIC_APP_URL', env);
  if (publicApp) {
    const url = new URL(publicApp);
    const isLoopback = ['127.0.0.1', 'localhost'].includes(url.hostname) && ['http:', 'https:'].includes(url.protocol);
    if (url.username || url.password || (!isLoopback && url.protocol !== 'https:')) {
      throw new Error('PUBLIC_APP_URL must use HTTPS without credentials.');
    }
    redirects.add(`${url.origin}/`);
  }
  const patch = {
    external_google_enabled: true,
    external_google_client_id: existingIds.length ? current.external_google_client_id : clientId,
    external_google_secret: secret,
    uri_allow_list: [...redirects].join(','),
  };
  if (providerConfigured('smtp', env)) {
    const smtpHost = configValue('SMTP_HOST', env);
    const smtpPort = String(configValue('SMTP_PORT', env) || '465');
    const smtpUser = configValue('SMTP_USER', env);
    const smtpPass = configValue('SMTP_PASS', env);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(smtpUser) || !/^\d+$/.test(smtpPort)) {
      throw new Error('Saved SMTP user or port is invalid; no settings were changed.');
    }
    Object.assign(patch, {
      smtp_host: smtpHost,
      smtp_port: smtpPort,
      smtp_user: smtpUser,
      smtp_pass: smtpPass,
      smtp_admin_email: smtpUser,
      smtp_sender_name: 'GHST EXPRESS',
      smtp_max_frequency: 15,
      rate_limit_email_sent: Math.max(Number(current.rate_limit_email_sent) || 0, 30),
      mailer_otp_length: 6,
      mailer_otp_exp: 900,
      mailer_subjects_recovery: RECOVERY_EMAIL_SUBJECT,
      mailer_templates_recovery_content: RECOVERY_EMAIL_TEMPLATE,
      mailer_subjects_confirmation: CONFIRMATION_EMAIL_SUBJECT,
      mailer_templates_confirmation_content: CONFIRMATION_EMAIL_TEMPLATE,
    });
  }
  return patch;
}

async function jsonRequest(fetcher, url, options = {}) {
  let response;
  const attempts = options.method === 'PATCH' ? 1 : 3;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      response = await fetcher(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(15000) });
      break;
    } catch (error) {
      if (attempt + 1 < attempts) continue;
      const cause = error.cause?.code || error.code || error.name;
      const code = typeof cause === 'string' && /^[A-Z_a-z0-9]+$/.test(cause) ? cause : 'network';
      throw new Error(`Supabase request failed at ${new URL(url).hostname} (${code}). Credentials were not logged.`);
    }
  }
  if (!response.ok) throw new Error(`Supabase returned HTTP ${response.status}. Check access and project permissions.`);
  try {
    const data = await response.json();
    if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error();
    return data;
  } catch {
    throw new Error('Unexpected Supabase response. Credentials were not logged.');
  }
}

// Use all resolved IPv4 addresses when this workstation cannot reach a DNS peer.
// TLS still validates the original hostname, and writes are never replayed.
function setupFetcher(url, options = {}) {
  return new Promise((resolve, reject) => {
    const request = https.request(url, {
      method: options.method || 'GET', headers: options.headers, signal: options.signal,
      autoSelectFamily: true,
      lookup: (hostname, settings, callback) => dns.resolve4(hostname, (error, addresses) => {
        if (error) { callback(error); return; }
        callback(null, settings.all ? addresses.map(address => ({ address, family: 4 })) : addresses[0], 4);
      }),
    }, response => {
      const chunks = [];
      let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 1000000) { response.destroy(new Error('Oversized response')); return; }
        chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => resolve(new Response(Buffer.concat(chunks), { status: response.statusCode })));
    });
    request.on('error', reject);
    request.end(options.body);
  });
}

export async function setupGoogleCloud({ env = process.env, token = '', apply = false, fetcher = fetch } = {}) {
  const target = googleCloudTarget(env);
  const status = await jsonRequest(fetcher, `${target.origin}/auth/v1/settings`, {
    headers: { apikey: configValue('SUPABASE_ANON_KEY', env) },
  });
  const smtpSaved = providerConfigured('smtp', env);
  const report = {
    project: target.project,
    clientIdSaved: Boolean(configValue('GOOGLE_CLIENT_ID', env)),
    clientSecretSaved: Boolean(configValue('GOOGLE_CLIENT_SECRET', env)),
    smtpSaved,
    managementAccessProvided: Boolean(token.trim()),
    googleEnabled: status.external?.google === true,
    applied: false,
    callback: `${target.origin}/auth/v1/callback`,
  };
  if (!apply && !token.trim()) return report;
  if (!token.trim()) throw new Error('Supabase management access is missing. Provide SUPABASE_ACCESS_TOKEN or the local token file; saved Google credentials are already available.');
  if (/[\r\n\s]/.test(token.trim())) throw new Error('Invalid Supabase management token.');
  const endpoint = `https://api.supabase.com/v1/projects/${target.project}/config/auth`;
  const headers = { Authorization: `Bearer ${token.trim()}`, 'Content-Type': 'application/json' };
  const current = await jsonRequest(fetcher, endpoint, { headers });
  const patch = googleCloudPatch(current, env);
  if (!apply) return {
    ...report,
    planReady: true,
    redirectsToAdd: patch.uri_allow_list.split(',').filter(value => !(current.uri_allow_list || '').split(',').map(item => item.trim()).includes(value)),
    smtpWillSync: Boolean(patch.smtp_host),
    recoveryOtpTemplateReady: Boolean(patch.mailer_templates_recovery_content?.includes('{{ .Token }}')),
    otherAuthSettingsPreserved: true,
  };
  await jsonRequest(fetcher, endpoint, { method: 'PATCH', headers, body: JSON.stringify(patch) });
  const verified = await jsonRequest(fetcher, endpoint, { headers });
  const smtpVerified = !patch.smtp_host || (
    verified.smtp_host === patch.smtp_host &&
    String(verified.smtp_port || '') === patch.smtp_port &&
    verified.mailer_otp_length === patch.mailer_otp_length &&
    String(verified.mailer_templates_recovery_content || '').includes('{{ .Token }}')
  );
  if (verified.external_google_enabled !== true || verified.external_google_client_id !== patch.external_google_client_id ||
      !patch.uri_allow_list.split(',').every(value => String(verified.uri_allow_list || '').split(',').includes(value)) ||
      !smtpVerified) {
    throw new Error('Settings were submitted but read-back verification failed. Recheck Supabase before retrying.');
  }
  const publicStatus = await jsonRequest(fetcher, `${target.origin}/auth/v1/settings`, {
    headers: { apikey: configValue('SUPABASE_ANON_KEY', env) },
  });
  return {
    ...report,
    applied: true,
    managementVerified: true,
    smtpSynced: Boolean(patch.smtp_host),
    recoveryOtpEnabled: Boolean(patch.smtp_host),
    googleEnabled: publicStatus.external?.google === true,
    googleSignInVerified: false,
  };
}

async function main() {
  const args = process.argv.slice(2);
  if (args.some(value => !['--check', '--apply'].includes(value)) || args.includes('--check') && args.includes('--apply')) {
    throw new Error('Usage: node setup-google-cloud.mjs [--check | --apply]');
  }
  await loadIntegrationConfig();
  const nativeDirectory = path.join(process.env.LOCALAPPDATA || process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'GHST');
  let native = {};
  try { native = JSON.parse(await readFile(path.join(nativeDirectory, 'auth-providers.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw new Error('Cannot read saved native configuration.'); }
  const env = { ...process.env,
    GOOGLE_CLIENT_ID: configValue('GOOGLE_CLIENT_ID') || native.googleClientId || '',
    GOOGLE_CLIENT_SECRET: configValue('GOOGLE_CLIENT_SECRET') || native.googleClientSecret || '' };
  let token = (process.env.SUPABASE_ACCESS_TOKEN || '').trim();
  if (!token && args.includes('--apply')) {
    const filename = process.env.SUPABASE_ACCESS_TOKEN_FILE || path.join(nativeDirectory, 'supabase-management-token.txt');
    try { token = (await readFile(filename, 'utf8')).trim(); }
    catch (error) { if (error.code !== 'ENOENT') throw new Error('Cannot read the local Supabase management token file.'); }
  }
  console.log(JSON.stringify(await setupGoogleCloud({ env, token, apply: args.includes('--apply'), fetcher: setupFetcher }), null, 2));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
