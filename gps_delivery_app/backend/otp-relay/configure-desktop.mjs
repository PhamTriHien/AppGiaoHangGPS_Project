import { config } from 'dotenv';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadIntegrationConfig } from './integration-config.mjs';

config({ path: fileURLToPath(new URL('.env', import.meta.url)) });
await loadIntegrationConfig();

const relayToken = process.env.RELAY_TOKEN?.trim();
const port = Number(process.env.PORT || 8787);
if (!relayToken || !Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('Missing relay token or invalid relay port.');
}

const root = process.platform === 'win32'
  ? process.env.LOCALAPPDATA
  : process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
if (!root) throw new Error('Local application data directory is unavailable.');
const directory = path.join(root, 'GHST');
const destination = path.join(directory, 'auth-providers.json');
let existing = {};
try {
  existing = JSON.parse(await readFile(destination, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
await mkdir(directory, { recursive: true });
await writeFile(destination, JSON.stringify({
  ...existing,
  deliveryApiBaseUrl: `http://127.0.0.1:${port}/delivery/`,
  ...(process.env.SUPABASE_URL?.trim() && process.env.SUPABASE_ANON_KEY?.trim() ? {
    supabaseUrl: process.env.SUPABASE_URL.trim(), supabaseAnonKey: process.env.SUPABASE_ANON_KEY.trim(),
  } : {}),
  otpEmailWebhookUrl: `http://127.0.0.1:${port}/otp-email`,
  otpEmailWebhookToken: relayToken,
}, null, 2), { mode: 0o600 });
console.log('Desktop email relay configuration saved. SMTP credentials remain on the backend.');
