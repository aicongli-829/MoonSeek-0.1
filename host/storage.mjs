import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';

export const stateName = '.filenest';
const blocked = new Set(['.git', '.filenest', 'node_modules', '.tools', '_build', 'target']);
export async function rootPath(input) {
  const root = await fs.realpath(path.resolve(input));
  if (!(await fs.stat(root)).isDirectory()) throw new Error('请选择文件夹');
  if (path.parse(root).root === root) throw new Error('请选具体文件夹，不要选整个磁盘');
  return root;
}
export function relativeSafe(rel, internal = false) {
  if (typeof rel !== 'string' || !rel || rel.includes('\\') || path.posix.isAbsolute(rel) || /^[a-z]:/i.test(rel)) throw new Error('不安全的相对路径');
  const pieces = rel.split('/');
  if (pieces.some(p => !p || p === '.' || p === '..')) throw new Error('路径不能包含空段或 ..');
  if (!internal && pieces.some(p => blocked.has(p.toLowerCase()))) throw new Error('不能操作保留目录');
  return pieces;
}
export async function safePath(root, rel, { internal = false, missing = true } = {}) {
  const pieces = relativeSafe(rel, internal);
  let current = root;
  if ((await fs.lstat(root)).isSymbolicLink()) throw new Error('根目录不能是链接');
  for (let i = 0; i < pieces.length; i++) {
    current = path.join(current, pieces[i]);
    try {
      const s = await fs.lstat(current);
      if (s.isSymbolicLink()) throw new Error('不处理符号链接或目录联接');
      if (i < pieces.length - 1 && !s.isDirectory()) throw new Error('父路径不是文件夹');
    } catch (e) { if (e.code !== 'ENOENT' || !missing) throw e; }
  }
  return current;
}
export async function digest(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
export async function fingerprint(file) {
  const before = await fs.lstat(file);
  if (!before.isFile() || before.isSymbolicLink()) throw new Error('只处理普通文件');
  const sha256 = await digest(file);
  const after = await fs.lstat(file);
  if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ino !== after.ino) throw new Error('文件扫描期间发生变化');
  return { size: after.size, mtimeMs: after.mtimeMs, sha256 };
}
export async function scan(root, options = {}) {
  const files = [], occupied = [], directories = [], warnings = [];
  const exclusions = (options.exclude || []).map(s => s.replaceAll('\\', '/').replace(/\/$/, '').toLowerCase());
  const exts = (options.extensions || []).map(s => s.replace(/^\./, '').toLowerCase());
  async function walk(folder, prefix = '', depth = 0) {
    if (depth > 50) { warnings.push(`${prefix}：超过目录深度上限`); return; }
    const entries = await fs.readdir(folder, { withFileTypes: true });
    for (const entry of entries) {
      const rel = prefix + entry.name;
      occupied.push(rel);
      if (entry.isDirectory()) directories.push(rel);
      if (blocked.has(entry.name.toLowerCase()) || entry.name === '重复文件隔离' || exclusions.some(x => rel.toLowerCase() === x || rel.toLowerCase().startsWith(x + '/'))) continue;
      if (!options.hidden && entry.name.startsWith('.')) continue;
      const file = path.join(folder, entry.name);
      const info = await fs.lstat(file);
      if (info.isSymbolicLink()) { warnings.push(`${rel}：已跳过链接`); continue; }
      if (info.isDirectory()) { if (options.recursive !== false) await walk(file, rel + '/', depth + 1); continue; }
      if (!info.isFile()) continue;
      if (exts.length && !exts.includes(path.extname(entry.name).slice(1).toLowerCase())) continue;
      if (files.length >= 10000) throw new Error('首版每次最多处理 10,000 个文件，请缩小范围');
      try {
        const fp = await fingerprint(file);
        const d = new Date(fp.mtimeMs);
        const month = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
        files.push({ path: rel, name: entry.name, month, size: String(fp.size), hash: fp.sha256, fingerprint: fp });
      } catch(e) { warnings.push(`${rel}：${e.message}`); }
    }
  }
  await walk(root);
  const groups = new Map();
  for (const file of files) { const k = file.size + ':' + file.hash; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(file); }
  // Hash narrows candidates; byte comparison confirms equality before offering cleanup.
  const duplicates = [];
  for (const group of groups.values()) {
    if (group.length < 2) continue;
    const clusters = [];
    for (const file of group) {
      let found;
      for (const cluster of clusters) if (await sameBytes(path.join(root, cluster[0].path), path.join(root, file.path))) { found = cluster; break; }
      if (found) found.push(file); else clusters.push([file]);
    }
    for (const cluster of clusters) if (cluster.length > 1) duplicates.push(cluster.map(f => f.path));
  }
  return { files, occupied, directories, duplicates, warnings };
}
async function sameBytes(a, b) {
  const left = await fs.open(a, 'r'), right = await fs.open(b, 'r');
  try {
    const x = Buffer.alloc(65536), y = Buffer.alloc(65536);
    while (true) {
      const p = await left.read(x), q = await right.read(y);
      if (p.bytesRead !== q.bytesRead || !x.subarray(0,p.bytesRead).equals(y.subarray(0,q.bytesRead))) return false;
      if (!p.bytesRead) return true;
    }
  } finally { await left.close(); await right.close(); }
}
export async function atomicJson(file, data) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temp = file + '.' + randomUUID() + '.tmp';
  const handle = await fs.open(temp, 'wx');
  try { await handle.writeFile(JSON.stringify(data, null, 2)); await handle.sync(); } finally { await handle.close(); }
  await fs.rename(temp, file);
}
export async function stateDir(root) {
  const dir = await safePath(root, stateName, { internal: true });
  await fs.mkdir(dir, { recursive: true });
  await safePath(root, `${stateName}/history`, { internal: true });
  await fs.mkdir(path.join(dir, 'history'), { recursive: true });
  return dir;
}
