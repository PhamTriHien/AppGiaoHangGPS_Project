import { X509Certificate } from 'node:crypto';
import dns from 'node:dns';

dns.setDefaultResultOrder('ipv4first');

export function validateDatabaseCa(value) {
  if (!value) return;
  if (value.length > 8192 || !/^-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+\r?\n-----END CERTIFICATE-----$/.test(value)) {
    throw new Error('INVALID_DATABASE_CA');
  }
  if (!new X509Certificate(value).ca) throw new Error('INVALID_DATABASE_CA');
}

export function databaseConnectionOptions(env) {
  const target = new URL(env.DATABASE_URL);
  if (!['postgres:', 'postgresql:'].includes(target.protocol)) throw new Error('INVALID_DATABASE_URL');
  for (const key of ['ssl', 'sslmode', 'sslcert', 'sslkey', 'sslrootcert']) target.searchParams.delete(key);
  const ca = env.DATABASE_CA_CERT?.trim();
  validateDatabaseCa(ca);
  return {
    connectionString: target.toString(),
    ssl: ['localhost', '127.0.0.1', '[::1]'].includes(target.hostname)
      ? false : { rejectUnauthorized: true, ...(ca ? { ca } : {}) },
  };
}
