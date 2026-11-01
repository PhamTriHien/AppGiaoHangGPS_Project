import { config, parse } from 'dotenv';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createWorker } from 'tesseract.js';

const directory = path.dirname(fileURLToPath(import.meta.url));
const filename = path.join(directory, '.env');
const original = await readFile(filename, 'utf8');
const existing = parse(original);
// The public Photon server is limited to manual lookups during local development.
const defaults = { PHOTON_BASE_URL: 'https://photon.komoot.io/', PHOTON_AUTOCOMPLETE: 'false' };
const missing = Object.entries(defaults).filter(([key]) => !Object.hasOwn(existing, key));
if (missing.length) await writeFile(filename, `${original.trimEnd()}\n\n# Local free integrations\n${missing.map(([k,v]) => `${k}=${v}`).join('\n')}\n`);
config({ path: filename });
await mkdir(path.join(directory, '.cache', 'ocr'), { recursive: true });
const worker = await createWorker('vie+eng', 1, {
  cachePath: path.join(directory, '.cache', 'ocr'), logger: () => {}, errorHandler: () => {},
});
await worker.terminate();
console.log('Vietnamese/English OCR models installed. Existing credentials preserved.');
console.log(JSON.stringify(Object.fromEntries([
  'SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','GEMINI_API_KEY',
  'GEMINI_MODEL','TELEGRAM_BOT_TOKEN','TELEGRAM_CHAT_ID','PHOTON_BASE_URL','VROOM_BASE_URL',
  'GOOGLE_APPLICATION_CREDENTIALS','TURNSTILE_SECRET_KEY',
].map(key => [key, Boolean(process.env[key]?.trim())]))));
