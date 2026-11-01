import 'dotenv/config';
import { loadIntegrationConfig } from './integration-config.mjs';
await loadIntegrationConfig();
if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) {
  console.log(JSON.stringify({ configured: false, schema: 'unknown' }));
  process.exitCode = 1;
} else {
  try {
    const response = await fetch(new URL('/rest/v1/rpc/delivery_cloud_profile', process.env.SUPABASE_URL), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { apikey: process.env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' }, body: '{}',
    });
    const result = await response.json();
    console.log(JSON.stringify({ configured: true, schema: result.code === 'PGRST202' ? 'missing' : result.code === '42501' ? 'present-auth-required' : 'unknown',
      authenticatedWorkflowVerified: false }));
  } catch { console.log(JSON.stringify({ configured: true, schema: 'unreachable', authenticatedWorkflowVerified: false })); process.exitCode = 1; }
}
