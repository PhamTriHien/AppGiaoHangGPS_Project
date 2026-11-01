import { X509Certificate } from 'node:crypto';
import dns from 'node:dns';
import net from 'node:net';
import tls from 'node:tls';

dns.setDefaultResultOrder('ipv4first');
net.setDefaultAutoSelectFamily(false);
tls.DEFAULT_ECDH_CURVE = 'X25519:prime256v1:secp384r1';

const originalLookup = dns.lookup.bind(dns);
const ipv4Resolver = new dns.promises.Resolver();
const systemIpv4Servers = dns.getServers().filter(server => net.isIP(server.replace(/:\d+$/, '')) === 4);
ipv4Resolver.setServers([...new Set(['1.1.1.1', '8.8.8.8', ...systemIpv4Servers])]);
const ipv4Cache = new Map();
const pendingLookups = new Map();

function probeFastestIpv4(addresses) {
  if (addresses.length <= 1) return Promise.resolve(addresses);
  return new Promise(resolve => {
    const ordered = [];
    let settled = 0;
    const finish = () => {
      const rest = addresses.filter(ip => !ordered.includes(ip));
      resolve([...ordered, ...rest]);
    };
    const timer = setTimeout(finish, 1200);
    for (const ip of addresses) {
      const sock = net.connect({ host: ip, port: 443 });
      const done = ok => {
        sock.destroy();
        if (ok && !ordered.includes(ip)) ordered.push(ip);
        settled++;
        if (ordered.length === 1 || settled === addresses.length) {
          clearTimeout(timer);
          finish();
        }
      };
      sock.once('connect', () => done(true));
      sock.once('error', () => done(false));
    }
  });
}

function replyIpv4(addresses, opts, cb) {
  if (opts?.all) {
    cb(null, addresses.map(address => ({ address, family: 4 })));
  } else {
    cb(null, addresses[0], 4);
  }
}

dns.lookup = function cachedIpv4Lookup(hostname, options, callback) {
  const cb = typeof options === 'function' ? options : callback;
  const opts = typeof options === 'function'
    ? {}
    : typeof options === 'number'
      ? { family: options }
      : (options || {});

  if (
    !hostname ||
    opts.family === 6 ||
    net.isIP(hostname) !== 0 ||
    hostname === 'localhost' ||
    /\.(?:example|test|invalid|local)$/i.test(hostname) ||
    !hostname.includes('.')
  ) {
    return originalLookup(hostname, options, callback);
  }

  const hit = ipv4Cache.get(hostname);
  if (hit && hit.expires > Date.now()) {
    queueMicrotask(() => replyIpv4(hit.addresses, opts, cb));
    return;
  }

  let inflight = pendingLookups.get(hostname);
  if (!inflight) {
    inflight = (async () => {
      try {
        const v4 = await Promise.race([
          ipv4Resolver.resolve4(hostname),
          new Promise((_, reject) => setTimeout(() => reject(new Error('DNS_TIMEOUT')), 2500)),
        ]);
        if (Array.isArray(v4) && v4.length > 0) {
          const ranked = await probeFastestIpv4(v4);
          if (ipv4Cache.size >= 200) ipv4Cache.delete(ipv4Cache.keys().next().value);
          ipv4Cache.set(hostname, { addresses: ranked, expires: Date.now() + 1_800_000 });
          return ranked;
        }
      } catch {}
      return await new Promise((resolve, reject) => {
        originalLookup(hostname, { family: 4, all: true }, (err, res) => {
          if (err || !Array.isArray(res) || res.length === 0) return reject(err || new Error('ENOTFOUND'));
          const addrs = res.map(r => r.address).filter(Boolean);
          if (addrs.length === 0) return reject(new Error('ENOTFOUND'));
          if (ipv4Cache.size >= 200) ipv4Cache.delete(ipv4Cache.keys().next().value);
          ipv4Cache.set(hostname, { addresses: addrs, expires: Date.now() + 300_000 });
          resolve(addrs);
        });
      });
    })().finally(() => pendingLookups.delete(hostname));
    pendingLookups.set(hostname, inflight);
  }

  inflight.then(
    addresses => replyIpv4(addresses, opts, cb),
    () => originalLookup(hostname, options, callback),
  );
};


const SUPABASE_ROOT_2021_CA = `-----BEGIN CERTIFICATE-----
MIIDxDCCAqygAwIBAgIUbLxMod62P2ktCiAkxnKJwtE9VPYwDQYJKoZIhvcNAQEL
BQAwazELMAkGA1UEBhMCVVMxEDAOBgNVBAgMB0RlbHdhcmUxEzARBgNVBAcMCk5l
dyBDYXN0bGUxFTATBgNVBAoMDFN1cGFiYXNlIEluYzEeMBwGA1UEAwwVU3VwYWJh
c2UgUm9vdCAyMDIxIENBMB4XDTIxMDQyODEwNTY1M1oXDTMxMDQyNjEwNTY1M1ow
azELMAkGA1UEBhMCVVMxEDAOBgNVBAgMB0RlbHdhcmUxEzARBgNVBAcMCk5ldyBD
YXN0bGUxFTATBgNVBAoMDFN1cGFiYXNlIEluYzEeMBwGA1UEAwwVU3VwYWJhc2Ug
Um9vdCAyMDIxIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqQXW
QyHOB+qR2GJobCq/CBmQ40G0oDmCC3mzVnn8sv4XNeWtE5XcEL0uVih7Jo4Dkx1Q
DmGHBH1zDfgs2qXiLb6xpw/CKQPypZW1JssOTMIfQppNQ87K75Ya0p25Y3ePS2t2
GtvHxNjUV6kjOZjEn2yWEcBdpOVCUYBVFBNMB4YBHkNRDa/+S4uywAoaTWnCJLUi
cvTlHmMw6xSQQn1UfRQHk50DMCEJ7Cy1RxrZJrkXXRP3LqQL2ijJ6F4yMfh+Gyb4
O4XajoVj/+R4GwywKYrrS8PrSNtwxr5StlQO8zIQUSMiq26wM8mgELFlS/32Uclt
NaQ1xBRizkzpZct9DwIDAQABo2AwXjALBgNVHQ8EBAMCAQYwHQYDVR0OBBYEFKjX
uXY32CztkhImng4yJNUtaUYsMB8GA1UdIwQYMBaAFKjXuXY32CztkhImng4yJNUt
aUYsMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAB8spzNn+4VU
tVxbdMaX+39Z50sc7uATmus16jmmHjhIHz+l/9GlJ5KqAMOx26mPZgfzG7oneL2b
VW+WgYUkTT3XEPFWnTp2RJwQao8/tYPXWEJDc0WVQHrpmnWOFKU/d3MqBgBm5y+6
jB81TU/RG2rVerPDWP+1MMcNNy0491CTL5XQZ7JfDJJ9CCmXSdtTl4uUQnSuv/Qx
Cea13BX2ZgJc7Au30vihLhub52De4P/4gonKsNHYdbWjg7OWKwNv/zitGDVDB9Y2
CMTyZKG3XEu5Ghl1LEnI3QmEKsqaCLv12BnVjbkSeZsMnevJPs1Ye6TjjJwdik5P
o/bKiIz+Fq8=
-----END CERTIFICATE-----`;

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
  const isSupabaseHost = /(?:^|\.)supabase\.(?:com|co)$/i.test(target.hostname);
  return {
    connectionString: target.toString(),
    ssl: ['localhost', '127.0.0.1', '[::1]'].includes(target.hostname)
      ? false
      : ca
        ? { rejectUnauthorized: true, ca }
        : isSupabaseHost
          ? { rejectUnauthorized: true, ca: [...tls.rootCertificates, SUPABASE_ROOT_2021_CA] }
          : { rejectUnauthorized: true },
  };
}
