import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { loadIntegrationConfig, updateIntegrationConfig } from './integration-config.mjs';

await loadIntegrationConfig();
const root = process.env.LOCALAPPDATA || process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
let native = {};
try { native = JSON.parse(await readFile(path.join(root, 'GHST', 'auth-providers.json'), 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw new Error('Cannot read existing native configuration.'); }
const mapping = { googleClientId: 'GOOGLE_CLIENT_ID', googleClientSecret: 'GOOGLE_CLIENT_SECRET',
  smtpSenderEmail: 'SMTP_USER', smtpAppPassword: 'SMTP_PASS', smtpHost: 'SMTP_HOST', smtpPort: 'SMTP_PORT',
  smsProvider: 'SMS_PROVIDER', smsApiKey: 'SMS_API_KEY', smsApiSecret: 'SMS_API_SECRET', smsBrandname: 'SMS_BRANDNAME' };
const values = {};
for (const [local, key] of Object.entries(mapping)) {
  if (!process.env[key]?.trim() && native[local] != null && String(native[local]).trim()) values[key] = String(native[local]).trim();
}
if (values.SMS_PROVIDER && !['TEXTBEE', 'ESMS', 'SPEEDSMS', 'TWILIO'].includes(values.SMS_PROVIDER)) delete values.SMS_PROVIDER;
if ((process.env.SMS_API_KEY || values.SMS_API_KEY) && process.env.SMS_ENABLED == null) values.SMS_ENABLED = 'true';
const result = await updateIntegrationConfig(values, { local: true, actor: 'local-setup' });
console.log(JSON.stringify({ migrated: result.changed, preservedExistingValues: true, providers: Object.fromEntries(Object.entries(result.status)
  .map(([id, value]) => [id, { configured: value.configured, enabled: value.enabled, available: value.available }])) }));
