import fs from 'node:fs/promises';
import { rootPath, scan } from './storage.mjs';
import { createPlan, exportCsv } from './planning.mjs';
import { execute, undo, history } from './transactions.mjs';

const help = `FileNest · 本地文件整理

用法：
  node host/cli.mjs scan <文件夹>
  node host/cli.mjs preview <文件夹> [--config rules.json] [--csv]
  node host/cli.mjs apply <文件夹> [--config rules.json] --yes
  node host/cli.mjs history <文件夹>
  node host/cli.mjs undo <文件夹> <批次ID> --yes

规则文件是 JSON 对象，与界面导出报告中的 options 相同。
apply 会重新扫描并生成计划。要逐项审核同一份计划，请使用网页界面。
所有路径必须位于选中的文件夹内；文件不被覆盖，历史保存在 .filenest。
`;

export async function runCli(args, output = console.log) {
  const [command, inputRoot] = args;
  if (!command || command === '--help' || command === 'help') {
    output(help);
    return;
  }
  if (!['scan', 'preview', 'apply', 'history', 'undo'].includes(command)) {
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
  if (configIndex !== -1) {
    if (!args[configIndex + 1]) {
      throw new Error('--config 后需要规则文件路径');
    }
    options = JSON.parse(await fs.readFile(args[configIndex + 1], 'utf8'));
  }
  const inventory = await scan(root, options);
  if (command === 'scan') {
    output(JSON.stringify(inventory, null, 2));
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
