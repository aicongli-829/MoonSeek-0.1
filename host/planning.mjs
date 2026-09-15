import { randomUUID } from 'node:crypto';
import { plan_json } from '../dist/core.mjs';
import { validateOptions } from './options.mjs';

export function createPlan(inventory, input = {}) {
  const options = validateOptions(input);
  const known = new Set(inventory.files.map(f => f.path));
  for (const name of [...options.excluded, ...options.quarantine]) {
    if (!known.has(name)) {
      throw new Error(`文件不在本次扫描中：${name}`);
    }
  }
  const duplicatePaths = new Set(inventory.duplicates.flat());
  for (const name of options.quarantine) {
    if (!duplicatePaths.has(name)) {
      throw new Error(`未经内容比对确认的重复文件：${name}`);
    }
    if (options.excluded.includes(name)) {
      throw new Error('文件不能同时被排除和隔离');
    }
  }
  for (const group of inventory.duplicates) {
    if (group.every(name => options.quarantine.includes(name))) {
      throw new Error('每组重复文件必须保留至少一份');
    }
  }
  const result = JSON.parse(plan_json(JSON.stringify({
    files: inventory.files,
    occupied: inventory.occupied,
    options,
  })));
  if (result.error) {
    throw new Error(result.error);
  }
  const directories = new Set((inventory.directories || []).map(p => p.toLowerCase()));
  const occupied = new Set(inventory.occupied.map(p => p.toLowerCase()));
  for (const row of result.rows) {
    if (row.status !== 'ready') continue;
    const parts = row.target.split('/');
    for (let index = 1; index < parts.length; index++) {
      const parent = parts.slice(0, index).join('/').toLowerCase();
      if (occupied.has(parent) && !directories.has(parent)) {
        row.status = 'conflict';
        row.reason = '目标父路径被文件或链接占用';
        break;
      }
    }
  }
  return {
    id: randomUUID(),
    created: new Date().toISOString(),
    rows: result.rows,
    options,
    summary: summarize(result.rows, inventory),
  };
}

export function summarize(rows, inventory) {
  const counts = {
    ready: 0,
    conflict: 0,
    invalid: 0,
    unchanged: 0,
    excluded: 0,
  };
  for (const row of rows) {
    if (Object.hasOwn(counts, row.status)) {
      counts[row.status]++;
    }
  }
  const sizes = new Map(inventory.files.map(f => [f.path, Number(f.size)]));
  return {
    ...counts,
    total: rows.length,
    duplicateGroups: inventory.duplicates.length,
    duplicateBytes: inventory.duplicates.reduce((sum, group) => {
      return sum + group.slice(1).reduce((n, p) => n + sizes.get(p), 0);
    }, 0),
  };
}

function csvCell(input) {
  let text = String(input ?? '');
  // A report should remain data when opened in a spreadsheet program.
  if (/^[=+@\-\t\r]/.test(text)) {
    text = "'" + text;
  }
  return '"' + text.replaceAll('"', '""') + '"';
}

export function exportCsv(plan) {
  const lines = [['原路径', '目标路径', '状态', '说明']];
  for (const row of plan.rows) {
    lines.push([row.source, row.target, row.status, row.reason]);
  }
  return '\ufeff' + lines.map(row => row.map(csvCell).join(',')).join('\r\n');
}

export function exportMarkdown(plan) {
  const escape = value => String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
  return [
    '# FileNest 整理预览',
    '',
    `生成时间：${plan.created}`,
    '',
    '| 原路径 | 目标路径 | 状态 |',
    '| --- | --- | --- |',
    ...plan.rows.map(row => `| ${escape(row.source)} | ${escape(row.target)} | ${escape(row.status)} |`),
    '',
    '这是预览报告，实际执行会再次检查文件状态。',
  ].join('\n');
}
