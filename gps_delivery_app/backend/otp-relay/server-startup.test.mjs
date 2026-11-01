import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

test('Cloud server starts without relay credentials and refuses missing authentication setup', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ghst-startup-'));
  t.after(() => rm(directory, {recursive:true,force:true}));
  for (const [name, settings, starts] of [
    ['cloud', {SUPABASE_ENABLED:'true'}, true],
    ['missing-auth', {SUPABASE_ANON_KEY:''}, false],
    ['disabled-cloud', {SUPABASE_ENABLED:'false'}, false],
    ['local', {SUPABASE_ANON_KEY:'',RELAY_TOKEN:'private-local-token'}, true],
  ]) {
    await t.test(name, async () => {
      const child = spawn(process.execPath, ['server.mjs'], {
        cwd: new URL('.', import.meta.url), windowsHide:true,
        env: {...process.env, INTEGRATION_CONFIG_PATH:path.join(directory,'config.json'),
          PORT:'0',BIND_HOST:'127.0.0.1',RELAY_TOKEN:'',SUPABASE_URL:'https://project.supabase.co',
          SUPABASE_ANON_KEY:'public-key',SUPABASE_ENABLED:'true',...settings},
        stdio:['ignore','pipe','pipe'],
      });
      let stderr = '';
      child.stderr.on('data', chunk => {stderr += chunk;});
      try {
        const started = await new Promise((resolve,reject) => {
          const timeout = setTimeout(() => reject(new Error('Server startup timed out')),10000);
          const finish = value => {clearTimeout(timeout);resolve(value);};
          child.stdout.on('data', chunk => {if (chunk.toString().includes('GO-MAU OTP relay')) finish(true);});
          child.once('exit', () => finish(false));
          child.once('error', error => {clearTimeout(timeout);reject(error);});
        });
        assert.equal(started, starts);
        if (!starts) assert.match(stderr, /Cần cấu hình Supabase/);
      } finally {
        if (child.exitCode === null && child.signalCode === null) {
          const exited = once(child,'exit');
          child.kill();
          await exited;
        }
      }
    });
  }
});

test('Cloud admin static hosting redirects root to /#/admin and allows same-origin while blocking foreign CORS', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'ghst-admin-static-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'index.html'), '<!doctype html><title>GHST Admin</title>');

  const child = spawn(process.execPath, ['server.mjs'], {
    cwd: new URL('.', import.meta.url),
    windowsHide: true,
    env: {
      ...process.env,
      INTEGRATION_CONFIG_PATH: path.join(directory, 'config.json'),
      STATIC_WEB_DIR: directory,
      TRUST_PROXY: '1',
      PORT: '0',
      BIND_HOST: '127.0.0.1',
      RELAY_TOKEN: '',
      WEB_ORIGINS: '',
      DATABASE_URL: '',
      SUPABASE_URL: 'https://project.supabase.co',
      SUPABASE_ANON_KEY: 'public-key',
      SUPABASE_ENABLED: 'true',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    const baseUrl = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Startup timed out')), 10000);
      child.stdout.on('data', chunk => {
        const match = chunk.toString().match(/http:\/\/127\.0\.0\.1:(\d+)/);
        if (match) {
          clearTimeout(timeout);
          resolve(`http://127.0.0.1:${match[1]}`);
        }
      });
      child.once('error', reject);
    });

    const rootRes = await fetch(`${baseUrl}/`, { redirect: 'manual' });
    assert.equal(rootRes.status, 302);
    assert.equal(rootRes.headers.get('location'), '/#/admin');

    const adminRes = await fetch(`${baseUrl}/admin`);
    assert.equal(adminRes.status, 200);
    assert.match(await adminRes.text(), /GHST Admin/);

    const sameOriginRes = await fetch(`${baseUrl}/health`, { headers: { Origin: baseUrl } });
    assert.equal(sameOriginRes.status, 200);
    assert.equal(sameOriginRes.headers.get('access-control-allow-origin'), baseUrl);

    const foreignRes = await fetch(`${baseUrl}/health`, { headers: { Origin: 'https://evil.example' } });
    assert.equal(foreignRes.status, 403);
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      const exited = once(child, 'exit');
      child.kill();
      await exited;
    }
  }
});
