import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {
  scan,
  rootPath,
  safePath,
  fingerprint,
  relativeSafe,
  atomicJson,
} from '../host/storage.mjs';
import { fixture } from './helpers.mjs';

test('scanner confirms equal content despite different names', async t => {
  const root = await fixture(t, {
    'a.txt': 'same content',
    'old/different-name.bin': 'same content',
    'b.txt': 'other value!',
  });
  const result = await scan(root);
  assert.equal(result.files.length, 3);
  assert.equal(result.duplicates.length, 1);
  assert.deepEqual(result.duplicates[0].sort(), ['a.txt', 'old/different-name.bin']);
});

test('same size is not sufficient evidence of duplicate content', async t => {
  const root = await fixture(t, {
    'one.dat': 'ABC',
    'two.dat': 'XYZ',
  });
  const result = await scan(root);
  assert.equal(result.files[0].size, result.files[1].size);
  assert.equal(result.duplicates.length, 0);
});

test('zero-byte files are recognized as duplicates', async t => {
  const root = await fixture(t, {
    'empty.txt': '',
    'empty2.txt': '',
    'nonempty.txt': 'x',
  });
  const result = await scan(root);
  assert.equal(result.duplicates.length, 1);
  assert.equal(result.duplicates[0].length, 2);
});

test('byte comparison handles files spanning multiple read buffers', async t => {
  const bytes = Buffer.alloc(150000, 65);
  const other = Buffer.from(bytes);
  other[149999] = 66;
  const root = await fixture(t, {
    'a.bin': bytes,
    'b.bin': bytes,
    'c.bin': other,
  });
  const result = await scan(root);
  assert.deepEqual(result.duplicates[0].sort(), ['a.bin', 'b.bin']);
});

test('exclusions hide files but preserve occupancy information', async t => {
  const root = await fixture(t, {
    'readme.txt': 'a',
    'backup/old.txt': 'b',
    '.private': 'c',
    '.git/config': 'd',
    '重复文件隔离/old.txt': 'e',
  });
  const result = await scan(root, { exclude: ['backup'] });
  assert.deepEqual(result.files.map(f => f.path), ['readme.txt']);
  assert.ok(result.occupied.includes('backup'));
  assert.ok(result.occupied.includes('.private'));
  assert.ok(result.occupied.includes('重复文件隔离'));
});

test('extension filters are case-insensitive and accept leading dots', async t => {
  const root = await fixture(t, {
    'a.PDF': 'a',
    'b.txt': 'b',
    'nested/c.pdf': 'c',
  });
  const result = await scan(root, { extensions: ['.pdf'] });
  assert.deepEqual(result.files.map(f => f.path).sort(), ['a.PDF', 'nested/c.pdf']);
});

test('nonrecursive scan skips children while retaining their directory occupancy', async t => {
  const root = await fixture(t, {
    'a.txt': 'a',
    'nested/b.txt': 'b',
  });
  const result = await scan(root, { recursive: false });
  assert.deepEqual(result.files.map(f => f.path), ['a.txt']);
  assert.ok(result.occupied.includes('nested'));
});

test('explicit hidden option includes dotfiles but never internal state', async t => {
  const root = await fixture(t, {
    '.env.local': 'local example',
    '.filenest/history/private.json': '{}',
    'visible.txt': 'visible',
  });
  const result = await scan(root, { hidden: true });
  assert.deepEqual(result.files.map(f => f.path).sort(), ['.env.local', 'visible.txt']);
});

test('selected root must be a directory rather than a file', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  await assert.rejects(rootPath(path.join(root, 'a.txt')), /文件夹/);
  assert.equal(await rootPath(root), await fs.realpath(root));
});

test('path validator rejects traversal, absolute and reserved paths', () => {
  for (const value of ['', '../x', 'a/../x', '/tmp/x', 'C:/x', 'a\\b', '.git/config', 'a//b']) {
    assert.throws(() => relativeSafe(value));
  }
  assert.deepEqual(relativeSafe('照片/一.jpg'), ['照片', '一.jpg']);
});

test('destination traversal rejects a file used as a parent directory', async t => {
  const root = await fixture(t, { 'blocked': 'file content' });
  await assert.rejects(safePath(root, 'blocked/a.txt'), /父路径/);
});

test('directory junctions are skipped by scanner and rejected by executor path guard', async t => {
  const root = await fixture(t, { 'outside/a.txt': 'outside', 'inside/b.txt': 'inside' });
  try {
    await fs.symlink(path.join(root, 'outside'), path.join(root, 'inside/link'), 'junction');
  } catch (error) {
    if (['EPERM', 'ENOSYS'].includes(error.code)) {
      t.skip('当前平台不允许创建链接');
      return;
    }
    throw error;
  }
  const result = await scan(path.join(root, 'inside'));
  assert.deepEqual(result.files.map(f => f.path), ['b.txt']);
  assert.equal(result.warnings.length, 1);
  await assert.rejects(safePath(root, 'inside/link/a.txt'), /链接|联接/);
});

test('fingerprints include content and modification time', async t => {
  const root = await fixture(t, { 'a.txt': 'before' });
  const first = await fingerprint(path.join(root, 'a.txt'));
  await fs.writeFile(path.join(root, 'a.txt'), 'after!');
  const second = await fingerprint(path.join(root, 'a.txt'));
  assert.equal(first.size, second.size);
  assert.notEqual(first.sha256, second.sha256);
  assert.equal(typeof second.mtimeMs, 'number');
});

test('atomic JSON replacement remains valid with concurrent readers', async t => {
  const root = await fixture(t);
  const file = path.join(root, 'journal.json');
  await atomicJson(file, { revision: 0, values: [] });
  let reading = true;
  const readers = Array.from({ length: 2 }, async () => {
    while (reading) {
      const value = JSON.parse(await fs.readFile(file, 'utf8'));
      assert.equal(typeof value.revision, 'number');
      await new Promise(resolve => setImmediate(resolve));
    }
  });
  try {
    for (let revision = 1; revision <= 8; revision++) {
      await atomicJson(file, { revision, values: Array(revision % 7).fill(revision) });
    }
  } finally {
    reading = false;
    await Promise.all(readers);
  }
  assert.equal(JSON.parse(await fs.readFile(file, 'utf8')).revision, 8);
  assert.deepEqual((await fs.readdir(root)).filter(name => name.endsWith('.tmp')), []);
});
