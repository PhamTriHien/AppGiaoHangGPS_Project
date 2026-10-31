import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
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
