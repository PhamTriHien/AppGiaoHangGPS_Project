import 'dotenv/config';
import { readFile } from 'node:fs/promises';
const port = Number(process.env.PORT || 8787);
const headers = { Authorization: `Bearer ${process.env.RELAY_TOKEN}`, 'Content-Type': 'application/json' };
async function request(path, body) {
  const response = await fetch(`http://127.0.0.1:${port}/delivery/${path}`, {
    headers, ...(body ? {method:'POST',body:JSON.stringify(body)} : {}), signal: AbortSignal.timeout(100000),
  });
  const data = await response.json();
  if (!response.ok) throw Error(`${path}: HTTP ${response.status}`);
  return data;
}
const status = await request('integrations');
console.log('Configured integrations:', Object.fromEntries(Object.entries(status.providers || {}).map(([id, provider]) =>
  [id, { configured: provider.configured, enabled: provider.enabled, available: provider.available }])));
for (const [name, path] of [
  ['banks', 'banks'], ['weather', 'weather?lat=10.77&lon=106.70'],
  ['route', 'route?coordinates=106.69160,10.77760;106.69530,10.77690'],
  ['matrix', 'matrix?coordinates=106.69160,10.77760;106.69530,10.77690'],
]) {
  try {
    const result = await request(path);
    console.log(name, { ok: true, rows: result.data?.length ?? result.durations?.length ?? result.routes?.length ?? result.properties?.timeseries?.length });
  } catch (error) { console.log(name, { ok: false, error: error.message }); process.exitCode = 1; }
}
if (status.photon) {
  const result = await request('places?q=Ben%20Thanh');
  console.log('Live address results:', result.places.length, 'autocomplete:', result.autocomplete);
  if (!result.places.length) throw Error('No live address results.');
}
if (process.argv[2]) {
  const result = await request('ocr', {image:(await readFile(process.argv[2])).toString('base64')});
  console.log('OCR recognition:', {nameDetected:Boolean(result.recipientName),phoneDetected:Boolean(result.recipientPhone),addressDetected:Boolean(result.dropoffAddress),confidence:result.confidence});
  if (!result.text?.trim()) throw Error('OCR returned no recognized text.');
}
