import { randomUUID } from 'node:crypto';
import { plan_bundle_json, report_json } from '../dist/core.mjs';
import { validateOptions } from './options.mjs';

export function createPlan(inventory, input = {}) {
  const options = validateOptions(input);
  const result = JSON.parse(plan_bundle_json(JSON.stringify({
    files: inventory.files,
    occupied: inventory.occupied,
    directories: inventory.directories,
    duplicates: inventory.duplicates,
    options,
  })));
  if (result.error) {
    throw new Error(result.error);
  }
  result.summary.duplicateBytes = Number(result.summary.duplicateBytes);
  return {
    id: randomUUID(),
    created: new Date().toISOString(),
    rows: result.rows,
    options,
    summary: result.summary,
  };
}

export function exportCsv(plan) {
  return createReport(plan, 'csv');
}

export function exportMarkdown(plan) {
  return createReport(plan, 'md');
}

export function exportJson(plan) {
  return createReport(plan, 'json');
}

function createReport(plan, format) {
  const result = JSON.parse(report_json(JSON.stringify({
    format,
    plan,
  })));
  if (result.error) throw new Error(result.error);
  return result.content;
}
