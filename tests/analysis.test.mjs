import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeInventory } from '../host/analysis.mjs';
import { runCli } from '../host/cli.mjs';
import { fixture, inventory } from './helpers.mjs';

test('MoonBit inventory analysis reports totals, duplicates and suggestions', async t => {
  const root = await fixture(t, {
    'a.txt': 'same content',
    'copies/a.txt': 'same content',
    'photo.jpg': 'image bytes',
  });
  const scanned = await inventory(root);
  const analysis = analyzeInventory(scanned);
  assert.equal(analysis.schemaVersion, 1);
  assert.equal(analysis.totalFiles, 3);
  assert.equal(analysis.duplicateGroups, 1);
  assert.equal(analysis.duplicateFiles, 2);
  assert.equal(analysis.reclaimableBytes, String(Buffer.byteLength('same content')));
  assert.equal(analysis.categories[0].category, '文档');
  assert.equal(analysis.duplicateAdvice.length, 1);
  assert.equal(analysis.duplicateAdvice[0].keeper, 'a.txt');
  assert.deepEqual(analysis.duplicateAdvice[0].quarantine, ['copies/a.txt']);
  assert.match(analysis.recommendations.join(' '), /重复副本/);
});

test('analyze CLI exposes the MoonBit report without changing files', async t => {
  const root = await fixture(t, { 'notes.txt': 'notes' });
  const output = [];
  await runCli(['analyze', root], value => output.push(value));
  const report = JSON.parse(output[0]);
  assert.equal(report.totalFiles, 1);
  assert.equal(report.totalBytes, '5');
  assert.equal(report.extensions[0].extension, '.txt');
});

test('analysis adapter rejects incomplete inventories', () => {
  assert.throws(() => analyzeInventory({ files: [] }), /有效的扫描结果/);
});
