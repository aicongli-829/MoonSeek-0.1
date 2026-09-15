import { create_snapshot_json, compare_snapshot_json } from '../dist/core.mjs';

function moonResult(fn, input) {
  const result = JSON.parse(fn(JSON.stringify(input)));
  if (result.error) throw new Error(result.error);
  return result;
}

export function createSnapshot(inventory, created = new Date().toISOString()) {
  if (!inventory || !Array.isArray(inventory.files)) {
    throw new Error('请先提供有效的扫描结果');
  }
  return moonResult(create_snapshot_json, { created, files: inventory.files });
}

export function compareSnapshot(snapshot, inventory) {
  if (!inventory || !Array.isArray(inventory.files)) {
    throw new Error('请先提供有效的当前扫描结果');
  }
  return moonResult(compare_snapshot_json, { snapshot, current: { files: inventory.files } });
}
