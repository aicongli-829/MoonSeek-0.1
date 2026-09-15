import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { execute, undo, history } from '../host/transactions.mjs';
import { fixture, read, present, row, inventory } from './helpers.mjs';

test('classification and rename can be undone without changing content', async t => {
  const root = await fixture(t, { 'notes.txt': 'important notes' });
  const scanned = await inventory(root);
  const result = await execute(root, [row('notes.txt', '文档/notes_001.txt')], scanned.files);
  assert.equal(result.status, 'completed');
  assert.equal(await present(root, 'notes.txt'), false);
  assert.equal(await read(root, '文档/notes_001.txt'), 'important notes');
  const restored = await undo(root, result.id);
  assert.equal(restored.status, 'undone');
  assert.equal(await read(root, 'notes.txt'), 'important notes');
  assert.equal(await present(root, '文档/notes_001.txt'), false);
});

test('a two-file name exchange stages both sources before placement', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  const scanned = await inventory(root);
  const result = await execute(root, [row('a.txt', 'b.txt'), row('b.txt', 'a.txt')], scanned.files);
  assert.equal(result.status, 'completed');
  assert.equal(await read(root, 'a.txt'), 'B');
  assert.equal(await read(root, 'b.txt'), 'A');
  await undo(root, result.id);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, 'b.txt'), 'B');
});

test('existing unselected destination is never overwritten', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  const scanned = await inventory(root);
  await assert.rejects(execute(root, [row('a.txt', 'b.txt')], scanned.files), /目标已存在/);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, 'b.txt'), 'B');
});

test('content changes after preview block the entire batch before staging', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  const scanned = await inventory(root);
  await fs.writeFile(path.join(root, 'b.txt'), 'Changed');
  await assert.rejects(execute(root, [row('a.txt', 'new/a.txt'), row('b.txt', 'new/b.txt')], scanned.files), /文件已改变/);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, 'b.txt'), 'Changed');
  assert.equal(await present(root, 'new/a.txt'), false);
});

test('a newly created original path prevents undo without overwriting it', async t => {
  const root = await fixture(t, { 'a.txt': 'original' });
  const result = await execute(root, [row('a.txt', 'new/a.txt')], (await inventory(root)).files);
  await fs.writeFile(path.join(root, 'a.txt'), 'new owner');
  await assert.rejects(undo(root, result.id), /原位置已被占用/);
  assert.equal(await read(root, 'a.txt'), 'new owner');
  assert.equal(await read(root, 'new/a.txt'), 'original');
});

test('edited destination blocks undo and keeps edited data intact', async t => {
  const root = await fixture(t, { 'a.txt': 'original' });
  const result = await execute(root, [row('a.txt', 'new/a.txt')], (await inventory(root)).files);
  await fs.writeFile(path.join(root, 'new/a.txt'), 'user edited this');
  await assert.rejects(undo(root, result.id), /文件已改变/);
  assert.equal(await read(root, 'new/a.txt'), 'user edited this');
  assert.equal(await present(root, 'a.txt'), false);
});

test('stopping during staging leaves a recoverable journal', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  let stop = false;
  const result = await execute(root, [row('a.txt', 'new/a.txt'), row('b.txt', 'new/b.txt')], (await inventory(root)).files, {
    shouldStop: () => stop,
    onProgress: () => { stop = true; },
  });
  assert.equal(result.status, 'interrupted');
  assert.equal(result.operations[0].phase, 'staged');
  assert.equal(result.operations[1].phase, 'pending');
  const restored = await undo(root, result.id);
  assert.equal(restored.status, 'undone');
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, 'b.txt'), 'B');
});

test('stopping during placement restores both placed and staged files', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  let stop = false;
  const result = await execute(root, [row('a.txt', 'new/a.txt'), row('b.txt', 'new/b.txt')], (await inventory(root)).files, {
    shouldStop: () => stop,
    onProgress: p => { if (p.phase === 'applying') stop = true; },
  });
  assert.equal(result.status, 'interrupted');
  assert.equal(result.operations[0].phase, 'done');
  assert.equal(result.operations[1].phase, 'staged');
  await undo(root, result.id);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, 'b.txt'), 'B');
});

test('an unfinished journal blocks another execution in the same root', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const scanned = await inventory(root);
  const plan = [row('a.txt', 'new/a.txt')];
  const result = await execute(root, plan, scanned.files, { shouldStop: () => true });
  assert.equal(result.status, 'interrupted');
  await assert.rejects(execute(root, plan, scanned.files), /未完成批次/);
  await undo(root, result.id);
});

test('external creation between preflight and placement is never overwritten', async t => {
  const root = await fixture(t, { 'a.txt': 'source' });
  let injected = false;
  const result = await execute(root, [row('a.txt', 'a2.txt')], (await inventory(root)).files, {
    onProgress: p => {
      if (p.phase === 'staging') {
        writeFileSync(path.join(root, 'a2.txt'), 'outside writer');
        injected = true;
      }
    },
    shouldStop: () => false,
  });
  assert.equal(injected, true);
  assert.equal(result.status, 'interrupted');
  assert.equal(await read(root, 'a2.txt'), 'outside writer');
  assert.equal(await read(root, result.operations[0].stage), 'source');
});

test('execution ignores non-ready preview rows', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  const plan = [row('a.txt', 'new/a.txt'), { ...row('b.txt', 'new/b.txt'), status: 'excluded' }];
  const result = await execute(root, plan, (await inventory(root)).files);
  assert.equal(result.operations.length, 1);
  assert.equal(await read(root, 'b.txt'), 'B');
  assert.equal(await present(root, 'new/b.txt'), false);
});

test('repeated undo is idempotent', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const result = await execute(root, [row('a.txt', 'b.txt')], (await inventory(root)).files);
  await undo(root, result.id);
  const second = await undo(root, result.id);
  assert.equal(second.status, 'undone');
  assert.equal(await read(root, 'a.txt'), 'A');
});

test('user plans cannot target internal state or escape the selected root', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const scanned = await inventory(root);
  for (const target of ['../outside.txt', '.filenest/history/x.json', '/tmp/file']) {
    await assert.rejects(execute(root, [row('a.txt', target)], scanned.files));
  }
  assert.equal(await read(root, 'a.txt'), 'A');
});

test('multiple operations cannot claim the same target', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  await assert.rejects(execute(root, [row('a.txt', 'c.txt'), row('b.txt', 'c.txt')], (await inventory(root)).files), /重复源或目标/);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, 'b.txt'), 'B');
});

test('quarantine remains reversible and does not delete duplicates', async t => {
  const root = await fixture(t, { 'a.txt': 'same', 'b.txt': 'same' });
  const result = await execute(root, [row('b.txt', '重复文件隔离/b.txt')], (await inventory(root)).files);
  assert.equal(await read(root, 'a.txt'), 'same');
  assert.equal(await read(root, '重复文件隔离/b.txt'), 'same');
  await undo(root, result.id);
  assert.equal(await read(root, 'b.txt'), 'same');
});

test('journal tampering cannot redirect recovery outside the root', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const result = await execute(root, [row('a.txt', 'b.txt')], (await inventory(root)).files);
  const file = path.join(root, '.filenest/history', result.id + '.json');
  const saved = JSON.parse(await fs.readFile(file, 'utf8'));
  saved.operations[0].source = '../outside.txt';
  await fs.writeFile(file, JSON.stringify(saved));
  await assert.rejects(undo(root, result.id));
  assert.equal(await read(root, 'b.txt'), 'A');
});

test('undo validates journal identifier before reading a file', async t => {
  const root = await fixture(t);
  await assert.rejects(undo(root, '../../secret'), /编号不合法/);
});

test('history returns latest journals and excludes partial temporary files', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const first = await execute(root, [row('a.txt', 'b.txt')], (await inventory(root)).files);
  await undo(root, first.id);
  const second = await execute(root, [row('a.txt', 'c.txt')], (await inventory(root)).files);
  await fs.writeFile(path.join(root, '.filenest/history/partial.tmp'), '{}');
  const records = await history(root);
  assert.equal(records.length, 2);
  assert.equal(records[0].id, second.id);
  assert.equal(records[1].status, 'undone');
});

test('recovery reconciles a crash after source unlink but before phase update', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const result = await execute(root, [row('a.txt', 'b.txt')], (await inventory(root)).files, { shouldStop: () => true });
  const op = result.operations[0];
  await fs.mkdir(path.dirname(path.join(root, op.stage)), { recursive: true });
  await fs.link(path.join(root, op.source), path.join(root, op.stage));
  await fs.unlink(path.join(root, op.source));
  await undo(root, result.id);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await present(root, op.stage), false);
});

test('recovery recognizes dual hardlinks after an interrupted staging move', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const result = await execute(root, [row('a.txt', 'b.txt')], (await inventory(root)).files, { shouldStop: () => true });
  const op = result.operations[0];
  await fs.mkdir(path.dirname(path.join(root, op.stage)), { recursive: true });
  await fs.link(path.join(root, op.source), path.join(root, op.stage));
  await undo(root, result.id);
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await present(root, op.stage), false);
});

test('recovery does not treat an independent equal-content file as a hardlink', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const result = await execute(root, [row('a.txt', 'b.txt')], (await inventory(root)).files, { shouldStop: () => true });
  const op = result.operations[0];
  await fs.mkdir(path.dirname(path.join(root, op.stage)), { recursive: true });
  await fs.copyFile(path.join(root, op.source), path.join(root, op.stage));
  const time = new Date(op.fingerprint.mtimeMs);
  await fs.utimes(path.join(root, op.stage), time, time);
  await assert.rejects(undo(root, result.id));
  assert.equal(await read(root, 'a.txt'), 'A');
  assert.equal(await read(root, op.stage), 'A');
});
