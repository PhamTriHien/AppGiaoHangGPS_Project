import assert from 'node:assert/strict';
import { X509Certificate } from 'node:crypto';
import { rootCertificates } from 'node:tls';
import test from 'node:test';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { databaseConnectionOptions, validateDatabaseCa } from './database-connection.mjs';
import { loadIntegrationConfig, updateIntegrationConfig } from './integration-config.mjs';
import { databaseRevision } from './deployment-readiness.mjs';

test('Managed database CA survives restart and changes the migration revision', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'delivery-ca-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const env = { INTEGRATION_CONFIG_PATH: path.join(directory, 'config.json'),
    DATABASE_URL: 'postgresql://user:password@db.example.test/postgres?sslmode=disable' };
  const revision = databaseRevision(env);
  const ca = rootCertificates.find(value => new X509Certificate(value).ca).trim();
  await updateIntegrationConfig({ DATABASE_CA_CERT: ca }, { env });
  assert.notEqual(databaseRevision(env), revision);
  const restarted = { INTEGRATION_CONFIG_PATH: env.INTEGRATION_CONFIG_PATH, DATABASE_URL: env.DATABASE_URL };
  await loadIntegrationConfig({ env: restarted });
  const options = databaseConnectionOptions(restarted);
  assert.equal(options.ssl.ca, ca);
  assert.equal(options.ssl.rejectUnauthorized, true);
  assert.equal(new URL(options.connectionString).searchParams.has('sslmode'), false);
  for (const invalid of ['not a certificate', `${ca}\n${ca}`, `${ca}\n-----BEGIN PRIVATE KEY-----`]) {
    assert.throws(() => validateDatabaseCa(invalid));
    await assert.rejects(updateIntegrationConfig({ DATABASE_CA_CERT: invalid }, { env }));
    assert.equal(env.DATABASE_CA_CERT, ca);
  }
  await updateIntegrationConfig({}, { clear: ['DATABASE_CA_CERT'], env });
  assert.deepEqual(databaseConnectionOptions(env).ssl, { rejectUnauthorized: true });
});
