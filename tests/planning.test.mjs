import test from 'node:test';
import assert from 'node:assert/strict';
import { createPlan, exportCsv, exportMarkdown } from '../host/planning.mjs';
import { validateOptions, validateTemplate, builtInTemplates } from '../host/options.mjs';
import { listTemplates, saveTemplate, deleteTemplate } from '../host/templates.mjs';
import { fixture, inventory } from './helpers.mjs';

test('every shipped template generates a valid plan for a real inventory', async t => {
  const root = await fixture(t, {
    '课程 (副本).txt': 'lesson',
    'image.JPG': 'synthetic image bytes',
    'scan.png': 'synthetic scan',
    'notes.pdf': 'synthetic document',
  });
  const scanned = await inventory(root);
  for (const template of builtInTemplates) {
    const result = createPlan(scanned, template.options);
    assert.equal(result.summary.invalid, 0, template.name);
    assert.equal(result.rows.length, 4);
  }
});

test('planning detects a file occupying the category directory', async t => {
  const root = await fixture(t, { '文档': 'a file', 'notes.txt': 'notes' });
  const result = createPlan(await inventory(root));
  const item = result.rows.find(r => r.source === 'notes.txt');
  assert.equal(item.status, 'conflict');
  assert.match(item.reason, /父路径/);
});

test('normal directories are valid category parents', async t => {
  const root = await fixture(t, { '文档/existing.txt': 'a', 'notes.txt': 'b' });
  const result = createPlan(await inventory(root));
  assert.equal(result.rows.find(r => r.source === 'notes.txt').status, 'ready');
});

test('quarantine rejects files not confirmed as duplicates', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'B' });
  const scanned = await inventory(root);
  assert.throws(() => createPlan(scanned, { quarantine: ['a.txt'] }), /未经内容比对/);
});

test('quarantine cannot select the entire duplicate group', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'A' });
  const scanned = await inventory(root);
  assert.throws(() => createPlan(scanned, { quarantine: ['a.txt', 'b.txt'] }), /至少一份/);
});

test('quarantine and exclusion cannot contradict each other', async t => {
  const root = await fixture(t, { 'a.txt': 'A', 'b.txt': 'A' });
  const scanned = await inventory(root);
  assert.throws(() => createPlan(scanned, { quarantine: ['b.txt'], excluded: ['b.txt'] }), /同时/);
});

test('preview summary counts duplicate bytes and actionable rows', async t => {
  const root = await fixture(t, { 'a.txt': 'same', 'b.txt': 'same', 'c.txt': 'same' });
  const result = createPlan(await inventory(root));
  assert.equal(result.summary.duplicateGroups, 1);
  assert.equal(result.summary.duplicateBytes, 8);
  assert.equal(result.summary.ready, 3);
});

test('unscanned file names are rejected rather than injected into plans', async t => {
  const root = await fixture(t, { 'a.txt': 'A' });
  const scanned = await inventory(root);
  assert.throws(() => createPlan(scanned, { excluded: ['../../secret'] }), /不在本次扫描/);
});

test('CSV export quotes delimiters and prevents spreadsheet formula interpretation', () => {
  const plan = {
    rows: [{ source: '=SUM(1,2).txt', target: 'a,"b".txt', status: 'ready', reason: 'line\nbreak' }],
  };
  const csv = exportCsv(plan);
  assert.ok(csv.startsWith('\ufeff'));
  assert.ok(csv.includes("'=SUM(1,2).txt"));
  assert.ok(csv.includes('"a,""b"".txt"'));
  assert.ok(csv.includes('"line\nbreak"'));
});

test('Markdown report escapes table separators and includes preview caveat', () => {
  const text = exportMarkdown({
    created: '2026-09-15',
    rows: [{ source: 'a|b', target: 'folder/file', status: 'ready' }],
  });
  assert.ok(text.includes('a\\|b'));
  assert.ok(text.includes('实际执行会再次检查'));
});

test('option validation normalizes integers but rejects out-of-range values', () => {
  assert.equal(validateOptions({ sequenceStart: 12 }).sequenceStart, '12');
  for (const sequenceStart of [-1, 1.5, 'x', 1000001]) {
    assert.throws(() => validateOptions({ sequenceStart }));
  }
  assert.throws(() => validateOptions({ sequenceWidth: 9 }));
  assert.throws(() => validateOptions({ conflict: 'overwrite' }));
});

test('invalid options do not silently become executable defaults', () => {
  assert.throws(() => validateOptions(null));
  assert.throws(() => validateOptions({ rules: 'wrong' }));
  assert.throws(() => validateOptions({ extensions: 'pdf' }));
  assert.throws(() => validateOptions({ rules: [{ kind: 'executeShell' }] }));
  assert.throws(() => validateOptions({ categories: [{ kind: 'extension', value: 'pdf' }] }));
});

test('template snapshots remove per-scan file selections', () => {
  const value = validateTemplate({
    name: 'My rules',
    options: { excluded: ['a.txt'], quarantine: ['b.txt'] },
  });
  assert.deepEqual(value.options.excluded, []);
  assert.deepEqual(value.options.quarantine, []);
});

test('custom templates persist, replace by name and can be removed', async t => {
  const root = await fixture(t);
  await saveTemplate(root, { name: '课程', options: { classify: 'month' } });
  const first = await listTemplates(root);
  assert.equal(first.custom.length, 1);
  assert.equal(first.custom[0].options.classify, 'month');
  await saveTemplate(root, { name: '课程', options: { classify: 'none' } });
  const updated = await listTemplates(root);
  assert.equal(updated.custom.length, 1);
  assert.equal(updated.custom[0].options.classify, 'none');
  await deleteTemplate(root, '课程');
  assert.equal((await listTemplates(root)).custom.length, 0);
});
