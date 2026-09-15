import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { safePath, stateDir, atomicJson, fingerprint, stateName } from './storage.mjs';
import { transaction_prepare_json, transaction_undo_plan_json, transaction_phase_json } from '../dist/core.mjs';

const validId = id => typeof id === 'string' && /^[a-f0-9-]{36}$/.test(id);
const journalQueues = new Map();
async function withJournalAccess(root, task) {
  const key = path.resolve(root).toLowerCase();
  const previous = journalQueues.get(key) || Promise.resolve();
  let release;
  const current = new Promise(resolve => { release = resolve; });
  journalQueues.set(key, current);
  await previous.catch(() => {});
  try { return await task(); }
  finally {
    release();
    if (journalQueues.get(key) === current) journalQueues.delete(key);
  }
}
async function exists(p) { try { await fs.lstat(p); return true; } catch(e) { if(e.code === 'ENOENT') return false; throw e; } }
function moonResult(fn, input) {
  const result = JSON.parse(fn(JSON.stringify(input)));
  if (result.error) throw new Error(result.error);
  return result;
}
function nextPhase(phase, event) {
  return moonResult(transaction_phase_json, { phase, event }).phase;
}
async function verify(file, expected) {
  const now = await fingerprint(file);
  if (now.sha256 !== expected.sha256 || now.size !== expected.size || now.mtimeMs !== expected.mtimeMs) throw new Error('文件已改变，请重新扫描或人工检查');
}
async function save(root, journal) {
  await withJournalAccess(root, async () => {
    const file = await safePath(root, `${stateName}/history/${journal.id}.json`, { internal: true });
    await atomicJson(file, journal);
  });
}
async function lock(root) {
  const dir = await stateDir(root), file = path.join(dir, 'lock');
  await safePath(root, `${stateName}/lock`, { internal: true });
  try {
    const handle = await fs.open(file, 'wx');
    await handle.writeFile(JSON.stringify({ pid: process.pid }));
    await handle.close();
  } catch(e) {
    if (e.code !== 'EEXIST') throw e;
    let pid;
    try { pid = JSON.parse(await fs.readFile(file, 'utf8')).pid; } catch { throw new Error('锁文件损坏，请确认没有操作运行后删除 .filenest/lock'); }
    try { process.kill(pid, 0); } catch(error) {
      if (error.code === 'ESRCH') { await fs.unlink(file); return lock(root); }
    }
    throw new Error('这个文件夹已有操作正在执行');
  }
  return async () => fs.unlink(file);
}

// Exclusive hard-link creation never replaces a destination. Unlink occurs only
// after destination content is verified. Both files must be on the same volume.
async function move(root, from, to, expected) {
  const src = await safePath(root, from, { internal: true, missing: false });
  const dst = await safePath(root, to, { internal: true });
  await verify(src, expected);
  await fs.mkdir(path.dirname(dst), { recursive: true });
  await safePath(root, to, { internal: true });
  await fs.link(src, dst);
  await verify(dst, expected);
  await fs.unlink(src);
}
export async function history(root) {
  return withJournalAccess(root, async () => {
    const dir = await stateDir(root);
    const records = [];
    for (const name of await fs.readdir(path.join(dir, 'history'))) {
      if (!/^[a-f0-9-]{36}\.json$/.test(name)) continue;
      try {
        await safePath(root, `${stateName}/history/${name}`, { internal: true, missing: false });
        records.push(JSON.parse(await fs.readFile(path.join(dir, 'history', name), 'utf8')));
      } catch(e) { records.push({ id: name, status: 'unreadable', error: e.message, operations: [] }); }
    }
    return records.sort((a,b) => (b.created || '').localeCompare(a.created || ''));
  });
}

export async function execute(root, plan, scanned, { onProgress = () => {}, shouldStop = () => false } = {}) {
  const release = await lock(root);
  try {
    const previous = await history(root);
    const id = randomUUID();
    const byPath = new Map(scanned.map(f => [f.path, f]));
    const prepared = moonResult(transaction_prepare_json, {
      id,
      plan,
      scanned: scanned.map(file => file.path),
      historyStatuses: previous.map(journal => journal.status),
    });
    const operations = prepared.operations.map(operation => ({
      ...operation,
      fingerprint: byPath.get(operation.source).fingerprint,
    }));
    for (const row of operations) {
      await safePath(root, row.source, { missing: false });
      await safePath(root, row.target); // User plans cannot address internal state.
    }
    for (const op of operations) {
      await verify(path.join(root, op.source), op.fingerprint);
      if (await exists(path.join(root, op.target)) && !operations.some(x => x.source === op.target)) throw new Error(`目标已存在：${op.target}`);
    }
    const journal = { id, created: new Date().toISOString(), status: 'running', operations, error: null };
    await save(root, journal);
    try {
      for (const op of operations) {
        if (shouldStop()) throw new Error('用户停止了后续操作，可在历史中恢复原状');
        await move(root, op.source, op.stage, op.fingerprint);
        op.phase = nextPhase(op.phase, 'stage'); await save(root, journal);
        onProgress({ phase: 'staging', completed: operations.filter(o => o.phase === 'staged').length, total: operations.length });
      }
      for (const op of operations) {
        if (shouldStop()) throw new Error('用户停止了后续操作，可在历史中恢复原状');
        op.phase = nextPhase(op.phase, 'apply-start'); await save(root, journal);
        await move(root, op.stage, op.target, op.fingerprint);
        op.phase = nextPhase(op.phase, 'apply-finish'); await save(root, journal);
        onProgress({ phase: 'applying', completed: operations.filter(o => o.phase === 'done').length, total: operations.length });
      }
      journal.status = 'completed'; await save(root, journal);
    } catch(e) { journal.status = 'interrupted'; journal.error = e.message; await save(root, journal); }
    return journal;
  } finally { await release(); }
}

async function readJournal(root, id) {
  if (!validId(id)) throw new Error('批次编号不合法');
  const j = await withJournalAccess(root, async () => {
    const file = await safePath(root, `${stateName}/history/${id}.json`, { internal: true, missing: false });
    return JSON.parse(await fs.readFile(file, 'utf8'));
  });
  if (j.id !== id || !Array.isArray(j.operations)) throw new Error('操作记录损坏');
  moonResult(transaction_undo_plan_json, j);
  for (let i = 0; i < j.operations.length; i++) {
    const o = j.operations[i];
    await safePath(root, o.source); await safePath(root, o.target);
    if (o.stage !== `${stateName}/stage/${id}/${i}`) throw new Error('暂存路径不匹配');
    await safePath(root, o.stage, { internal: true });
  }
  return j;
}
// Reconcile a crash between link/unlink and journal persistence. Only recognize
// duplicates if they are the same hard-linked file, never merely equal content.
async function reconcilePair(root, from, to, expected) {
  const src = await safePath(root, from, { internal: true });
  const dst = await safePath(root, to, { internal: true });
  if (!await exists(dst)) return false;
  await verify(dst, expected);
  if (await exists(src)) {
    const a = await fs.stat(src), b = await fs.stat(dst);
    if (a.dev !== b.dev || a.ino !== b.ino) throw new Error('恢复路径被其他文件占用');
    await fs.unlink(src);
  }
  return true;
}
export async function undo(root, id) {
  const release = await lock(root);
  try {
    const j = await readJournal(root, id);
    if (j.status === 'undone') return j;
    // Reconcile moves performed just before an unexpected process exit.
    for (const op of j.operations) {
      if (op.phase === 'pending' && await reconcilePair(root, op.source, op.stage, op.fingerprint)) op.phase = nextPhase(op.phase, 'reconcile-moved');
      if (op.phase === 'applying') {
        const moved = await reconcilePair(root, op.stage, op.target, op.fingerprint);
        op.phase = nextPhase(op.phase, moved ? 'reconcile-moved' : 'reconcile-stationary');
      }
      if (op.phase === 'undo-staging') {
        const moved = await reconcilePair(root, op.target, op.stage, op.fingerprint);
        op.phase = nextPhase(op.phase, moved ? 'reconcile-moved' : 'reconcile-stationary');
      }
      if (op.phase === 'restoring' && await reconcilePair(root, op.stage, op.source, op.fingerprint)) op.phase = nextPhase(op.phase, 'reconcile-moved');
    }
    // Check all content and original destinations before changing anything.
    const undoPlan = moonResult(transaction_undo_plan_json, j);
    const targetPaths = new Set(undoPlan.targets);
    for (let position = 0; position < undoPlan.validate.length; position++) {
      const op = j.operations[undoPlan.validate[position]];
      const current = undoPlan.locations[position];
      await verify(await safePath(root, current, { internal: true, missing: false }), op.fingerprint);
      if (await exists(path.join(root, op.source)) && !targetPaths.has(op.source)) throw new Error(`原位置已被占用：${op.source}`);
    }
    j.status = 'undoing'; j.error = null; await save(root, j);
    try {
      for (const index of undoPlan.restage) {
        const op = j.operations[index];
        op.phase = nextPhase(op.phase, 'undo-stage-start'); await save(root, j);
        await move(root, op.target, op.stage, op.fingerprint);
        op.phase = nextPhase(op.phase, 'undo-stage-finish'); await save(root, j);
      }
      for (const index of undoPlan.restore) {
        const op = j.operations[index];
        op.phase = nextPhase(op.phase, 'restore-start'); await save(root, j);
        await move(root, op.stage, op.source, op.fingerprint);
        op.phase = nextPhase(op.phase, 'restore-finish'); await save(root, j);
      }
      j.status = 'undone'; j.undoneAt = new Date().toISOString(); await save(root, j);
    } catch(e) { j.status = 'undo-failed'; j.error = e.message; await save(root, j); }
    return j;
  } finally { await release(); }
}
