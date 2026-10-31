import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { integrationAudit, integrationStatus, loadIntegrationConfig, providerConfigured, testIntegration, updateIntegrationConfig } from './integration-config.mjs';

async function temporary(t) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'delivery-config-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return { INTEGRATION_CONFIG_PATH: path.join(dir, 'config.json') };
}

test('Invalid config patches fail atomically, including unknown fields and forged URLs', async t => {
  const env = await temporary(t);
  for (const invalid of [{ NOT_ALLOWED: 'x' }, { GHN_BASE_URL: 'https://attacker.example/' },
    { GHN_ENABLED: 'yes' }, { OSRM_BASE_URL: 'file:///private' }, { SMTP_PORT: '0' },
    { SUPABASE_ANON_KEY: 'sb_secret_test' }, { SMS_PROVIDER: 'UNKNOWN' }]) {
    await assert.rejects(updateIntegrationConfig({ SMTP_USER: 'new@example.com', ...invalid }, { env, local: true }));
    assert.equal(env.SMTP_USER, undefined);
    await assert.rejects(readFile(env.INTEGRATION_CONFIG_PATH), { code: 'ENOENT' });
  }
});

test('Auth trust cannot change through cloud admin, and Turnstile enforcement cannot be misconfigured', async t => {
  const env = await temporary(t);
  await assert.rejects(updateIntegrationConfig({ SUPABASE_URL: 'https://other.supabase.co' }, { env }), e => e.status === 403);
  await assert.rejects(updateIntegrationConfig({ TURNSTILE_ENFORCE_OTP: 'true' }, { env }));
  await updateIntegrationConfig({ SUPABASE_URL: 'https://own.supabase.co', SUPABASE_ANON_KEY: 'publishable' }, { env, local: true });
  await updateIntegrationConfig({ SMTP_PASS: 'smtp-secret' }, { env, actor: 'operator-id' });
  const status = integrationStatus(env);
  assert.equal(status.smtp.fields.find(f => f.key === 'SMTP_PASS').configured, true);
  assert.equal(JSON.stringify(status).includes('smtp-secret'), false);
  assert.equal(JSON.stringify(await integrationAudit(env)).includes('smtp-secret'), false);
  assert.equal((await integrationAudit(env))[0].actor, 'operator-id');
});

test('Concurrent saves preserve both providers and survive restart; clear overrides env without restoring secrets', async t => {
  const env = await temporary(t);
  await Promise.all([
    updateIntegrationConfig({ SMTP_PASS: 'secret-one' }, { env }),
    updateIntegrationConfig({ GEMINI_API_KEY: 'secret-two', GEMINI_MODEL: 'model-id' }, { env }),
  ]);
  const restarted = { INTEGRATION_CONFIG_PATH: env.INTEGRATION_CONFIG_PATH };
  await loadIntegrationConfig({ env: restarted });
  assert.equal(restarted.SMTP_PASS, 'secret-one'); assert.equal(restarted.GEMINI_API_KEY, 'secret-two');
  await updateIntegrationConfig({}, { clear: ['SMTP_PASS'], env });
  restarted.SMTP_PASS = 'old-env-secret';
  await loadIntegrationConfig({ env: restarted });
  assert.equal(restarted.SMTP_PASS, '');
});

test('Health reports remain unverified for missing adapters and never expose upstream errors or tokens', async () => {
  const env = { GEMINI_API_KEY: 'super-secret', GEMINI_MODEL: 'valid', VROOM_BASE_URL: 'http://localhost:3000/' };
  const result = await testIntegration('gemini', { env, fetcher: async () => { throw Error('upstream super-secret'); } });
  assert.equal(result.ok, false); assert.equal(result.verified, false);
  assert.equal(JSON.stringify(result).includes('super-secret'), false);
  assert.equal((await testIntegration('vroom', { env })).verified, false);
  assert.equal(providerConfigured('momo', { MOMO_PARTNER_CODE: 'p', MOMO_ACCESS_KEY: 'a', MOMO_SECRET_KEY: 's' }), false);
  assert.equal(providerConfigured('sms', { SMS_ENABLED: 'true', SMS_PROVIDER: 'TWILIO', SMS_API_KEY: 'sid' }), false);
});

test('Cloud admin PostgreSQL settings are validated, masked and survive restart', async t => {
  const env = await temporary(t);
  const connection = 'postgresql://postgres:private-database-password@db.project.supabase.co:5432/postgres';
  for(const DATABASE_URL of ['https://db.example/postgres','postgresql:///postgres','postgresql://db.example','postgresql://db.example/postgres#fragment']) {
    await assert.rejects(updateIntegrationConfig({DATABASE_URL},{env}));
  }
  await updateIntegrationConfig({DATABASE_URL:connection,PUBLIC_BASE_URL:'https://api.example/delivery-app/'},{env,actor:'cloud-operator'});
  const status=integrationStatus(env);
  const field=status.backend.fields.find(f=>f.key==='DATABASE_URL');
  assert.equal(field.secret,true);assert.equal(field.localOnly,false);assert.equal(field.configured,true);
  assert.equal(field.value,undefined);
  assert.equal(JSON.stringify(status).includes('private-database-password'),false);
  assert.equal(JSON.stringify(await integrationAudit(env)).includes('private-database-password'),false);
  const restored={INTEGRATION_CONFIG_PATH:env.INTEGRATION_CONFIG_PATH};
  await loadIntegrationConfig({env:restored});
  assert.equal(restored.DATABASE_URL,connection);
  await updateIntegrationConfig({}, {clear:['DATABASE_URL'],env,actor:'cloud-operator'});
  assert.equal(env.DATABASE_URL,'');
});
