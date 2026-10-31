const startedAt = new Date().toISOString();
const counters = new Map();
const allowed = new Set(['payos','ghn','osrm','photon','banks','weather','gemini','supabase','telegram','vroom','custom']);

export function providerName(url) {
  const host = new URL(url).hostname;
  if (host.endsWith('.ghn.vn')) return 'ghn';
  if (host.endsWith('.payos.vn')) return 'payos';
  if (host.endsWith('.supabase.co')) return 'supabase';
  if (host.includes('project-osrm')) return 'osrm';
  if (host.includes('photon')) return 'photon';
  if (host==='api.vietqr.io') return 'banks';
  if (host==='api.met.no') return 'weather';
  if (host==='generativelanguage.googleapis.com') return 'gemini';
  if (host==='api.telegram.org') return 'telegram';
  return 'custom';
}
export function recordUsage(provider, duration, status) {
  const key = allowed.has(provider) ? provider : 'custom';
  const row = counters.get(key) ?? { provider:key,requests:0,successes:0,failures:0,rateLimited:0,totalMs:0,maxMs:0 };
  row.requests++;
  if (status>=200 && status<300) row.successes++; else row.failures++;
  if (status===429) row.rateLimited++;
  row.totalMs+=Math.max(0,duration);
  row.maxMs=Math.max(row.maxMs,duration);
  row.lastStatus=status;
  row.lastRequestAt=new Date().toISOString();
  counters.set(key,row);
}
export async function observeFetch(provider, operation) {
  const start=Date.now();
  try {
    const response=await operation();
    recordUsage(provider,Date.now()-start,response.status);
    return response;
  } catch(error) { recordUsage(provider,Date.now()-start,0); throw error; }
}
export function integrationUsage() {
  return { since:startedAt,scope:'process',providers:[...counters.values()].map(row=>{
    const {totalMs,...publicRow}=row;
    return {...publicRow,averageMs:Math.round(totalMs/row.requests)};
  }) };
}
