import fs from 'node:fs/promises';
import path from 'node:path';
const groups = new Map();
const skip = new Set(['.git', '.tools', '.scratch', '.filenest', '_build', 'target', 'dist', 'node_modules']);
const allowed = new Set(['.mbt', '.mjs', '.js', '.html', '.css']);
async function walk(folder) {
  for (const entry of await fs.readdir(folder, { withFileTypes: true })) {
    if (skip.has(entry.name)) {
      continue;
    }
    const file = path.join(folder, entry.name);
    if (entry.isDirectory()) {
      await walk(file);
      continue;
    }
    const ext = path.extname(file);
    if (!allowed.has(ext)) {
      continue;
    }
    const content = await fs.readFile(file, 'utf8');
    const lines = content.split(/\r?\n/);
    // Conservative physical source count: excludes empty lines and standalone
    // comments. Generated compiler output and third-party files are excluded.
    const effective = lines.filter(line => {
      const s = line.trim();
      return s && !s.startsWith('//') && !s.startsWith('/*') && !s.startsWith('*') && !s.startsWith('<!--');
    }).length;
    const category = file.includes('test') ? '测试' : ext === '.mbt' ? 'MoonBit 核心' : file.startsWith('web') ? '界面' : '本地适配与工具';
    const item = groups.get(category) || { physical: 0, effective: 0, files: 0 };
    item.physical += lines.length;
    item.effective += effective;
    item.files++;
    groups.set(category, item);
  }
}
await walk('.');
let total = 0;
for (const [group, counts] of groups) {
  total += counts.effective;
  console.log(`${group}: ${counts.files} files, ${counts.physical} physical, ${counts.effective} nonblank/noncomment`);
}
console.log(`TOTAL effective source lines: ${total}`);
if (process.argv.includes('--require-4000') && total < 4000) {
  process.exitCode = 1;
}
