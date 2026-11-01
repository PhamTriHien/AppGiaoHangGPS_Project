import 'dotenv/config';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { loadIntegrationConfig } from './integration-config.mjs';

await loadIntegrationConfig();
const root = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const args = ['build', 'web', '--no-wasm-dry-run', '--no-web-resources-cdn',
  `--dart-define=DELIVERY_API_BASE_URL=http://127.0.0.1:${Number(process.env.PORT || 8787)}/delivery/`,
  `--dart-define=SUPABASE_URL=${process.env.SUPABASE_URL || ''}`,
  `--dart-define=SUPABASE_ANON_KEY=${process.env.SUPABASE_ANON_KEY || ''}`];
// Only public connection settings enter the web build. No relay token or provider secret.
const executable = process.env.FLUTTER_BIN || (process.platform === 'win32' ? 'C:\\src\\flutter\\bin\\flutter.bat' : 'flutter');
const sdk = path.resolve(path.dirname(executable), '..');
const dart = path.join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', process.platform === 'win32' ? 'dart.exe' : 'dart');
const child = spawn(dart, [`--packages=${path.join(sdk, 'packages', 'flutter_tools', '.dart_tool', 'package_config.json')}`,
  path.join(sdk, 'bin', 'cache', 'flutter_tools.snapshot'), ...args], { cwd: root, stdio: 'inherit', env: { ...process.env, FLUTTER_ROOT: sdk } });
child.on('error', () => { console.error('Cannot start Flutter. Set FLUTTER_BIN to the installed SDK executable.'); process.exitCode = 1; });
child.on('exit', code => { process.exitCode = code ?? 1; });
