import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { parseRuleFile } from '../host/rules.mjs';
import { runCli } from '../host/cli.mjs';
import { fixture } from './helpers.mjs';

test('MoonBit readable rules compile to normal FileNest options', () => {
  const options = parseRuleFile(`
    scan extensions "JPG,png"
    classify month
    conflict number
    sequence start 7 width 4
    rename prefix "旅行_"
    rename extension_lower
  `);
  assert.equal(options.classify, 'month');
  assert.equal(options.conflict, 'number');
  assert.equal(options.sequenceStart, '7');
  assert.equal(options.sequenceWidth, '4');
  assert.deepEqual(options.extensions, ['jpg', 'png']);
  assert.deepEqual(options.rules.map(rule => rule.kind), ['prefix', 'extension_lower']);
});

test('readable rules return useful line diagnostics', () => {
  assert.throws(() => parseRuleFile('classify unknown\nrename replace one'), /第 1 行.*第 2 行/);
});

test('preview CLI accepts a .fnrules file', async t => {
  const root = await fixture(t, { 'Old Name.TXT': 'content' });
  const rulePath = path.join(root, 'preview.fnrules');
  await fs.writeFile(rulePath, 'scan exclude preview.fnrules\nclassify none\nrename separator "_"\nrename extension_lower\n');
  const output = [];
  await runCli(['preview', root, '--rules', rulePath], value => output.push(value));
  const plan = JSON.parse(output[0]);
  assert.equal(plan.rows.length, 1);
  assert.equal(plan.rows[0].target, 'Old_Name.txt');
});
