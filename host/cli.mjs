import fs from 'node:fs/promises';
import { rootPath, scan } from './storage.mjs';
import { createPlan, exportCsv } from './planning.mjs';
import { execute, undo, history } from './transactions.mjs';
import { analyzeInventory } from './analysis.mjs';
import { createSnapshot, compareSnapshot } from './snapshot.mjs';
import { parseRuleFile } from './rules.mjs';

const help = `FileNest · 本地文件整理

用法：
  node host/cli.mjs scan <文件夹>
  node host/cli.mjs analyze <文件夹> [--config rules.json]
  node host/cli.mjs snapshot <文件夹> [--output snapshot.json]
  node host/cli.mjs diff <文件夹> --snapshot snapshot.json
  node host/cli.mjs preview <文件夹> [--config rules.json | --rules rules.fnrules] [--csv]
  node host/cli.mjs apply <文件夹> [--config rules.json | --rules rules.fnrules] --yes
  node host/cli.mjs history <文件夹>
  node host/cli.mjs undo <文件夹> <批次ID> --yes

规则文件是 JSON 对象，与界面导出报告中的 options 相同。
.fnrules 是逐行可读规则，示例见 examples/downloads.fnrules。
apply 会重新扫描并生成计划。要逐项审核同一份计划，请使用网页界面。
所有路径必须位于选中的文件夹内；文件不被覆盖，历史保存在 .filenest。
`;

export async function runCli(args, output = console.log) {
  const [command, inputRoot] = args;
  if (!command || command === '--help' || command === 'help') {
    output(help);
    return;
  }
  if (!['scan', 'analyze', 'snapshot', 'diff', 'preview', 'apply', 'history', 'undo'].includes(command)) {
    throw new Error('未知命令，使用 --help 查看帮助');
  }
  if (!inputRoot) {
    throw new Error('缺少文件夹路径');
  }
  const root = await rootPath(inputRoot);
  if (command === 'history') {
    output(JSON.stringify(await history(root), null, 2));
    return;
  }
  if (command === 'undo') {
    if (!args.includes('--yes')) {
      throw new Error('撤销需要显式传入 --yes');
    }
    const result = await undo(root, args[2]);
    output(JSON.stringify(result, null, 2));
    if (result.status !== 'undone') {
      throw new Error(result.error || '撤销未完成');
    }
    return;
  }
  let options = {};
  const configIndex = args.indexOf('--config');
  const rulesIndex = args.indexOf('--rules');
  if (configIndex !== -1 && rulesIndex !== -1) {
    throw new Error('--config 和 --rules 只能选择一种');
  }
  if (configIndex !== -1) {
    if (!args[configIndex + 1]) {
      throw new Error('--config 后需要规则文件路径');
    }
    options = JSON.parse(await fs.readFile(args[configIndex + 1], 'utf8'));
  }
  if (rulesIndex !== -1) {
    if (!args[rulesIndex + 1]) throw new Error('--rules 后需要 .fnrules 文件路径');
    options = parseRuleFile(await fs.readFile(args[rulesIndex + 1], 'utf8'));
  }
  const inventory = await scan(root, options);
  if (command === 'scan') {
    output(JSON.stringify(inventory, null, 2));
    return;
  }
  if (command === 'analyze') {
    output(JSON.stringify(analyzeInventory(inventory), null, 2));
    return;
  }
  if (command === 'snapshot') {
    const snapshot = JSON.stringify(createSnapshot(inventory), null, 2);
    const outputIndex = args.indexOf('--output');
    if (outputIndex !== -1) {
      if (!args[outputIndex + 1]) throw new Error('--output 后需要文件路径');
      await fs.writeFile(args[outputIndex + 1], snapshot + '\n', 'utf8');
      output(`快照已保存：${args[outputIndex + 1]}`);
    } else {
      output(snapshot);
    }
    return;
  }
  if (command === 'diff') {
    const snapshotIndex = args.indexOf('--snapshot');
    if (snapshotIndex === -1 || !args[snapshotIndex + 1]) {
      throw new Error('diff 需要 --snapshot 快照文件路径');
    }
    const saved = JSON.parse(await fs.readFile(args[snapshotIndex + 1], 'utf8'));
    output(JSON.stringify(compareSnapshot(saved, inventory), null, 2));
    return;
  }
  const plan = createPlan(inventory, options);
  if (command === 'preview') {
    output(args.includes('--csv') ? exportCsv(plan) : JSON.stringify(plan, null, 2));
    return;
  }
  if (!args.includes('--yes')) {
    output(JSON.stringify(plan, null, 2));
    throw new Error('以上仅为预览。执行需要显式传入 --yes');
  }
  if (plan.summary.invalid) {
    throw new Error('计划包含无效路径或规则');
  }
  let stopped = false;
  const signal = () => {
    stopped = true;
  };
  process.once('SIGINT', signal);
  try {
    const result = await execute(root, plan.rows, inventory.files, {
      shouldStop: () => stopped,
    });
    output(JSON.stringify(result, null, 2));
    if (result.status !== 'completed') {
      throw new Error(result.error || '批次未完成');
    }
  } finally {
    process.removeListener('SIGINT', signal);
  }
}

if (process.argv[1]?.endsWith('cli.mjs')) {
  runCli(process.argv.slice(2)).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
