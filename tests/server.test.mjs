import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { once } from 'node:events';
import http from 'node:http';
import { createServer } from '../host/server.mjs';
import { fixture, read } from './helpers.mjs';

async function app(t) {
  const { server } = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const session = await (await fetch(origin + '/api/session')).json();
  async function post(route, payload = {}, headers = {}) {
    const response = await fetch(origin + '/api/' + route, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-FileNest-Token': session.token,
        ...headers,
      },
      body: JSON.stringify(payload),
    });
    return { status: response.status, value: await response.json() };
  }
  async function finish(id) {
    for (let count = 0; count < 300; count++) {
      const result = await post('job', { id });
      if (result.value.status !== 'running') {
        return result.value;
      }
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error('Test job timed out');
  }
  return { origin, post, finish };
}

test('HTTP flow scans, previews, executes and undoes actual files', async t => {
  const root = await fixture(t, { 'hello.txt': 'hello' });
  const client = await app(t);
  const started = await client.post('scan', { root });
  assert.equal(started.status, 200);
  const scanned = await client.finish(started.value.id);
  assert.equal(scanned.status, 'finished');
  assert.equal(scanned.result.inventory.files.length, 1);
  const preview = await client.post('preview');
  assert.equal(preview.value.rows[0].target, '文档/hello.txt');
  const execution = await client.post('execute', {
    planId: preview.value.id,
    confirm: true,
  });
  const completed = await client.finish(execution.value.id);
  assert.equal(completed.result.status, 'completed');
  assert.equal(await read(root, '文档/hello.txt'), 'hello');
  const history = await client.post('history');
  assert.equal(history.value.records.length, 1);
  const recovery = await client.post('undo', { id: completed.result.id });
  const restored = await client.finish(recovery.value.id);
  assert.equal(restored.result.status, 'undone');
  assert.equal(await read(root, 'hello.txt'), 'hello');
});

test('HTTP analysis and snapshot diff use the current scanned inventory', async t => {
  const root = await fixture(t, { 'a.txt': 'before' });
  const client = await app(t);
  let started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const analysis = await client.post('analyze');
  assert.equal(analysis.value.totalFiles, 1);
  const snapshot = await client.post('snapshot');
  assert.equal(snapshot.value.schemaVersion, 1);
  await fs.rename(path.join(root, 'a.txt'), path.join(root, 'renamed.txt'));
  await fs.writeFile(path.join(root, 'new.txt'), 'new');
  started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const comparison = await client.post('diff', { snapshot: snapshot.value });
  assert.equal(comparison.value.summary.moved, 1);
  assert.equal(comparison.value.summary.added, 1);
});

test('API requires per-process token', async t => {
  const client = await app(t);
  const result = await client.post('history', {}, { 'X-FileNest-Token': 'wrong' });
  assert.equal(result.status, 403);
});

test('API rejects cross-origin requests even with a valid token', async t => {
  const client = await app(t);
  const result = await client.post('history', {}, { Origin: 'https://example.com' });
  assert.equal(result.status, 403);
});

test('API rejects hostile Host headers', async t => {
  const client = await app(t);
  const status = await new Promise((resolve, reject) => {
    const request = http.get(client.origin + '/api/session', {
      headers: { Host: 'attacker.example' },
    }, response => {
      response.resume();
      resolve(response.statusCode);
    });
    request.on('error', reject);
  });
  assert.equal(status, 403);
});

test('only an explicit confirmation can execute the active preview', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  const client = await app(t);
  const started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const preview = await client.post('preview');
  const result = await client.post('execute', { planId: preview.value.id });
  assert.equal(result.status, 400);
  assert.equal(await read(root, 'a.txt'), 'a');
});

test('generating a new preview invalidates an earlier plan ID', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  const client = await app(t);
  const started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const old = await client.post('preview');
  await client.post('preview', { options: { classify: 'month' } });
  const result = await client.post('execute', { planId: old.value.id, confirm: true });
  assert.equal(result.status, 400);
  assert.equal(await read(root, 'a.txt'), 'a');
});

test('changing scan filters requires a new inventory', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  const client = await app(t);
  const started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const result = await client.post('preview', { options: { recursive: false } });
  assert.equal(result.status, 400);
  assert.match(result.value.error, /重新扫描/);
});

test('exported plans are reports and do not move files', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  const client = await app(t);
  const started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const preview = await client.post('preview');
  for (const format of ['csv', 'json', 'md']) {
    const result = await client.post('export', { planId: preview.value.id, format });
    assert.equal(result.status, 200);
    assert.ok(result.value.content.includes('a.txt'));
  }
  const jsonReport = await client.post('export', { planId: preview.value.id, format: 'json' });
  const savedPlan = JSON.parse(jsonReport.value.content);
  assert.equal(savedPlan.id, preview.value.id);
  assert.deepEqual(savedPlan.options, preview.value.options);
  assert.deepEqual(savedPlan.summary, preview.value.summary);
  assert.equal(await read(root, 'a.txt'), 'a');
});

test('static UI is served with restrictive CSP and no arbitrary file access', async t => {
  const client = await app(t);
  const response = await fetch(client.origin + '/');
  assert.equal(response.status, 200);
  assert.ok(response.headers.get('content-security-policy').includes("frame-ancestors 'none'"));
  assert.ok((await response.text()).includes('FileNest'));
  const forbidden = await fetch(client.origin + '/host/server.mjs');
  assert.notEqual(forbidden.status, 200);
});

test('file changes after preview surface as job failure', async t => {
  const root = await fixture(t, { 'a.txt': 'a' });
  const client = await app(t);
  const started = await client.post('scan', { root });
  await client.finish(started.value.id);
  const preview = await client.post('preview');
  await fs.writeFile(path.join(root, 'a.txt'), 'changed');
  const execution = await client.post('execute', { planId: preview.value.id, confirm: true });
  const result = await client.finish(execution.value.id);
  assert.equal(result.status, 'failed');
  assert.match(result.error, /文件已改变/);
  assert.equal(await read(root, 'a.txt'), 'changed');
});
