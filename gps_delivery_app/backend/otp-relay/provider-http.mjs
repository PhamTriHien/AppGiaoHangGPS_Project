import { observeFetch, providerName } from './integration-monitor.mjs';

export class IntegrationError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export async function fetchWithRetry(url, options = {}, fetcher = fetch) {
  if (fetcher !== fetch) {
    return fetcher(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(15000) });
  }
  let host = '';
  try { host = new URL(url).hostname; } catch {}
  const timeouts = host.includes('project-osrm.org')
    ? [4000]
    : host.endsWith('.supabase.co')
      ? [3500, 4500, 6500]
      : [5500, 9000];
  let lastError;
  for (const timeoutMs of timeouts) {
    try {
      return await fetch(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(timeoutMs) });
    } catch (err) {
      lastError = err;
      if (timeouts.length > 1) await new Promise(resolve => setTimeout(resolve, 250));
    }
  }
  throw lastError;
}

export async function providerJson(url, options = {}, fetcher = fetch) {
  let response;
  try {
    response = await observeFetch(providerName(url), () => fetchWithRetry(url, options, fetcher));
  } catch { throw new IntegrationError(502, 'Khong ket noi duoc dich vu.'); }
  if (!response.ok) throw new IntegrationError(response.status === 429 ? 429 : 502,
    response.status === 429 ? 'Dich vu dang gioi han yeu cau.' : 'Dich vu chua kha dung.');
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body ?? []) {
    size += chunk.length;
    if (size > 4_000_000) throw new IntegrationError(502, 'Phan hoi dich vu qua lon.');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new IntegrationError(502, 'Phan hoi dich vu khong hop le.'); }
}

export function coordinate(value) {
  return Array.isArray(value) && value.length === 2 && value.every(Number.isFinite) &&
    Math.abs(value[0]) <= 180 && Math.abs(value[1]) <= 90;
}
