import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createSnapshot, compareSnapshot } from '../host/snapshot.mjs';
import { fixture, inventory } from './helpers.mjs';

test('snapshot records a stable portable inventory', async t => {
  const root = await fixture(t, { 'z.txt': 'z', 'folder/a.txt': 'aa' });
  const result = createSnapshot(await inventory(root), '2026-09-15T00:00:00.000Z');
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.created, '2026-09-15T00:00:00.000Z');
  assert.deepEqual(result.files.map(file => file.path), ['folder/a.txt', 'z.txt']);
  assert.equal('fingerprint' in result.files[0], false);
});

test('snapshot comparison finds moves, edits and additions', async t => {
  const root = await fixture(t, { 'old.txt': 'move me', 'edit.txt': 'before' });
  const saved = createSnapshot(await inventory(root));
  await fs.rename(path.join(root, 'old.txt'), path.join(root, 'new.txt'));
  await fs.writeFile(path.join(root, 'edit.txt'), 'after content');
  await fs.writeFile(path.join(root, 'added.txt'), 'new');
  const result = compareSnapshot(saved, await inventory(root));
  assert.equal(result.summary.moved, 1);
  assert.equal(result.summary.modified, 1);
  assert.equal(result.summary.added, 1);
  assert.deepEqual(result.changes.map(change => change.kind), ['modified', 'moved', 'added']);
});

test('snapshot adapter rejects unsupported schema versions', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  await assert.rejects(
    async () => compareSnapshot({ schemaVersion: 99, files: [] }, await inventory(root)),
    /不支持的快照版本/,
  );
});
