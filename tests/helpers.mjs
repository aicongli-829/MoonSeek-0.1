import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { scan } from '../host/storage.mjs';

export async function fixture(t, files = {}) {
  const base = path.resolve('.scratch/tests');
  await fs.mkdir(base, { recursive: true });
  const root = await fs.mkdtemp(path.join(base, 'case-'));
  for (const [name, content] of Object.entries(files)) {
    const dest = path.join(root, name);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.writeFile(dest, content);
  }
  t.after(async () => {
    const resolved = path.resolve(root);
    assert.ok(resolved.startsWith(base + path.sep));
    assert.ok(path.basename(resolved).startsWith('case-'));
    await fs.rm(resolved, { recursive: true, force: true });
  });
  return root;
}

export async function read(root, name) {
  return fs.readFile(path.join(root, name), 'utf8');
}

export async function present(root, name) {
  try {
    await fs.lstat(path.join(root, name));
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') {
      return false;
    }
    throw error;
  }
}

export function row(source, target) {
  return {
    source,
    target,
    status: 'ready',
    reason: 'test plan',
    category: 'test',
  };
}

export async function inventory(root) {
  return scan(root, { recursive: true });
}
