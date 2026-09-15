import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, copyFileSync } from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const local = path.join(root, '.tools/moon');
const bundled = path.join(local, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const moon = existsSync(bundled) ? bundled : 'moon';
const env = { ...process.env };
if (existsSync(bundled)) { env.MOON_HOME = local; env.PATH = path.join(local, 'bin') + path.delimiter + env.PATH; }
function run(args, cwd = root) {
  const result = spawnSync(moon, args, { cwd, env, stdio: 'inherit' });
  if (result.error) { console.error('请安装 MoonBit 工具链：https://www.moonbitlang.com/download'); throw result.error; }
  if (result.status !== 0) process.exit(result.status || 1);
}
if (existsSync(bundled)) run(['bundle', '--target', 'js'], path.join(local, 'lib/core'));
run(['check', '--target', 'js']);
if (process.argv.includes('--test')) run(['test', '--target', 'js']);
run(['build', '--target', 'js']);
mkdirSync(path.join(root, 'dist'), { recursive: true });
const candidates = ['_build/js/release/build/core.js', '_build/js/debug/build/core.js', 'target/js/release/build/core.js'];
const output = candidates.map(p => path.join(root, p)).find(existsSync);
if (!output) throw new Error('找不到 MoonBit 构建输出，请检查 _build/js');
copyFileSync(output, path.join(root, 'dist/core.mjs'));
console.log('FileNest MoonBit core ready.');
