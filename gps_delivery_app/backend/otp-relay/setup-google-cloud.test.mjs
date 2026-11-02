import assert from 'node:assert/strict';
import test from 'node:test';
import { googleCloudPatch, googleCloudTarget, setupGoogleCloud } from './setup-google-cloud.mjs';

const env = {
  SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co', SUPABASE_ANON_KEY: 'public-test',
  GOOGLE_CLIENT_ID: 'web-test.apps.googleusercontent.com', GOOGLE_CLIENT_SECRET: 'private-test-secret',
};
const json = value => new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } });

test('Project target rejects arbitrary hosts, credentials and paths', () => {
  assert.equal(googleCloudTarget(env).project, 'abcdefghijklmnopqrst');
  for (const url of ['http://abcdefghijklmnopqrst.supabase.co', 'https://attacker.example',
    'https://user:password@abcdefghijklmnopqrst.supabase.co', 'https://abcdefghijklmnopqrst.supabase.co/other']) {
    assert.throws(() => googleCloudTarget({ ...env, SUPABASE_URL: url }));
  }
});

test('Google patch preserves existing client IDs and redirects without changing other Auth settings', () => {
  const current = { site_url: 'https://live.example', external_github_enabled: true, external_google_enabled: false,
    external_google_client_id: `${env.GOOGLE_CLIENT_ID},android.apps.googleusercontent.com`,
    uri_allow_list: 'https://live.example/callback,http://127.0.0.1:8080/' };
  const patch = googleCloudPatch(current, { ...env, PUBLIC_APP_URL: 'https://live.example/#/home' });
  assert.equal(patch.external_google_client_id, current.external_google_client_id);
  assert.ok(patch.uri_allow_list.split(',').includes('https://live.example/callback'));
  assert.equal(patch.uri_allow_list.split(',').filter(url => url === 'http://127.0.0.1:8080/').length, 1);
  assert.ok(patch.uri_allow_list.includes('http://127.0.0.1:8766/auth/callback'));
  assert.ok(patch.uri_allow_list.includes('com.giaohanggps.gpsdelivery://auth/callback'));
  assert.deepEqual(Object.keys(patch).sort(), ['external_google_client_id', 'external_google_enabled', 'external_google_secret', 'uri_allow_list']);
  assert.equal(current.external_github_enabled, true);
});

test('Conflicting Google IDs, missing credentials and malformed redirects abort before writes', () => {
  const current = { external_google_enabled: false, uri_allow_list: '' };
  assert.throws(() => googleCloudPatch({ ...current, external_google_client_id: 'other.apps.googleusercontent.com' }, env), /different Google/);
  assert.throws(() => googleCloudPatch(current, { ...env, GOOGLE_CLIENT_SECRET: '' }), /Client Secret/);
  assert.throws(() => googleCloudPatch({ ...current, uri_allow_list: ['unexpected'] }, env), /redirect configuration/);
  assert.throws(() => googleCloudPatch(current, { ...env, PUBLIC_APP_URL: 'http://live.example' }), /PUBLIC_APP_URL must use HTTPS/);
  const loopbackPatch = googleCloudPatch(current, { ...env, PUBLIC_APP_URL: 'http://127.0.0.1:8080' });
  assert.ok(loopbackPatch.uri_allow_list.split(',').includes('http://127.0.0.1:8080/'));
});

test('Saved SMTP settings sync custom Supabase Auth SMTP and 6-digit recovery OTP templates without leaking secrets', async () => {
  const smtpEnv = {
    ...env,
    SMTP_ENABLED: 'true',
    SMTP_HOST: 'smtp.gmail.com',
    SMTP_PORT: '465',
    SMTP_USER: 'relay-sender@example.com',
    SMTP_PASS: 'secret-app-pass-16',
  };
  let state = { external_google_enabled: false, uri_allow_list: '', rate_limit_email_sent: 2 };
  const report = await setupGoogleCloud({
    env: smtpEnv,
    token: 'management-test-token',
    apply: true,
    fetcher: async (url, options) => {
      if (url.endsWith('/auth/v1/settings')) return json({ external: { google: true } });
      if (options.method === 'PATCH') {
        const body = JSON.parse(options.body);
        assert.equal(body.smtp_host, 'smtp.gmail.com');
        assert.equal(body.smtp_port, '465');
        assert.equal(body.smtp_admin_email, 'relay-sender@example.com');
        assert.equal(body.mailer_otp_length, 6);
        assert.ok(body.mailer_templates_recovery_content.includes('{{ .Token }}'));
        assert.ok(body.mailer_templates_confirmation_content.includes('{{ .Token }}'));
        assert.equal(body.rate_limit_email_sent, 30);
        state = { ...state, ...body };
      }
      return json(state);
    },
  });
  assert.equal(report.applied, true);
  assert.equal(report.smtpSynced, true);
  assert.equal(report.recoveryOtpEnabled, true);
  assert.equal(JSON.stringify(report).includes(smtpEnv.SMTP_PASS), false);
  assert.equal(JSON.stringify(report).includes(smtpEnv.SMTP_USER), false);
});

test('Check mode only reads public status and never returns saved secrets', async () => {
  const calls = [];
  const report = await setupGoogleCloud({ env, fetcher: async (url, options) => {
    calls.push([url, options]); return json({ external: { google: false } });
  } });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][1].headers.Authorization, undefined);
  assert.equal(report.googleEnabled, false);
  assert.equal(report.applied, false);
  assert.equal(JSON.stringify(report).includes(env.GOOGLE_CLIENT_SECRET), false);
  assert.equal(JSON.stringify(report).includes('management-test-token'), false);
});

test('Authenticated check previews the exact redirect additions without a write', async () => {
  const calls = [];
  const report = await setupGoogleCloud({ env, token: 'management-test-token', fetcher: async (url, options) => {
    calls.push([url, options]);
    return json(url.endsWith('/auth/v1/settings') ? { external: { google: false } } : {
      external_google_enabled: false, uri_allow_list: 'https://live.example/callback',
    });
  } });
  assert.equal(calls.length, 2);
  assert.equal(calls.some(([, options]) => options.method === 'PATCH'), false);
  assert.equal(report.planReady, true);
  assert.equal(report.applied, false);
  assert.deepEqual(report.redirectsToAdd, [
    'http://127.0.0.1:8080/',
    'http://localhost:8080/',
    'http://127.0.0.1:8766/auth/callback',
    'com.giaohanggps.gpsdelivery://auth/callback',
  ]);
  assert.equal(JSON.stringify(report).includes(env.GOOGLE_CLIENT_SECRET), false);
});

test('Missing management access never sends a write or uses a service-role key as management identity', async () => {
  let calls = 0;
  await assert.rejects(setupGoogleCloud({ env: { ...env, SUPABASE_SERVICE_ROLE_KEY: 'not-management' }, apply: true,
    fetcher: async () => { calls++; return json({ external: { google: false } }); } }), /management access is missing/);
  assert.equal(calls, 1);
});

test('Apply only patches Google and additive redirects, then verifies management and public reads', async () => {
  let state = { external_google_enabled: false, uri_allow_list: 'https://live.example/callback', site_url: 'https://live.example' };
  let writes = 0;
  const report = await setupGoogleCloud({ env, token: 'management-test-token', apply: true, fetcher: async (url, options) => {
    assert.equal(options.redirect, 'error');
    if (url.endsWith('/auth/v1/settings')) return json({ external: { google: writes > 0 } });
    assert.equal(url, 'https://api.supabase.com/v1/projects/abcdefghijklmnopqrst/config/auth');
    assert.equal(options.headers.Authorization, 'Bearer management-test-token');
    if (options.method === 'PATCH') { writes++; state = { ...state, ...JSON.parse(options.body) }; }
    return json(state);
  } });
  assert.equal(writes, 1);
  assert.equal(state.site_url, 'https://live.example');
  assert.equal(report.managementVerified, true);
  assert.equal(report.googleEnabled, true);
  assert.equal(report.googleSignInVerified, false);
});

test('Upstream failures do not echo credentials or response bodies', async () => {
  await assert.rejects(setupGoogleCloud({ env, fetcher: async () => {
    throw new Error(`Failure ${env.GOOGLE_CLIENT_SECRET}`);
  } }), error => !error.message.includes(env.GOOGLE_CLIENT_SECRET));
  await assert.rejects(setupGoogleCloud({ env, fetcher: async () => new Response(env.GOOGLE_CLIENT_SECRET, { status: 403 }) }),
    error => /HTTP 403/.test(error.message) && !error.message.includes(env.GOOGLE_CLIENT_SECRET));
});

test('Read-back mismatch reports submitted state rather than claiming successful setup', async () => {
  const current = { external_google_enabled: false, uri_allow_list: '' };
  await assert.rejects(setupGoogleCloud({ env, token: 'management-test-token', apply: true,
    fetcher: async url => json(url.endsWith('/auth/v1/settings') ? { external: { google: false } } : current) }), /submitted but read-back verification failed/);
});

test('Incomplete management read prevents all writes', async () => {
  let writes = 0;
  await assert.rejects(setupGoogleCloud({ env, token: 'management-test-token', apply: true,
    fetcher: async (url, options) => {
      if (options.method === 'PATCH') writes++;
      return json(url.endsWith('/auth/v1/settings') ? { external: { google: false } } : {});
    } }), /Incomplete Supabase Auth settings/);
  assert.equal(writes, 0);
});

test('Transient reads retry but an uncertain PATCH is never replayed', async () => {
  let reads = 0;
  const report = await setupGoogleCloud({ env, fetcher: async () => {
    reads++;
    if (reads < 3) throw new Error('Transient read');
    return json({ external: { google: false } });
  } });
  assert.equal(reads, 3);
  assert.equal(report.applied, false);
  let writes = 0;
  await assert.rejects(setupGoogleCloud({ env, token: 'management-test-token', apply: true,
    fetcher: async (url, options) => {
      if (options.method === 'PATCH') { writes++; throw new Error('Uncertain write'); }
      return json(url.endsWith('/auth/v1/settings') ? { external: { google: false } } : {
        external_google_enabled: false, uri_allow_list: '',
      });
    } }), /Supabase request failed/);
  assert.equal(writes, 1);
});
