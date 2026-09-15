import fs from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve('.scratch', 'demo-' + Date.now());
await fs.mkdir(path.join(root, '旧资料'), { recursive: true });
const samples = [
  ['第10讲 (副本).txt', 'MoonBit lesson ten\n'],
  ['第2讲.txt', 'MoonBit lesson two\n'],
  ['旅行清单.md', '# 旅行清单\n- 相机\n- 水杯\n'],
  ['旧资料/旅行清单副本.md', '# 旅行清单\n- 相机\n- 水杯\n'],
  ['收支记录.csv', '项目,金额\n午餐,25\n'],
  ['项目说明.TXT', 'FileNest demo\n'],
  ['会议  笔记.txt', '会议记录\n'],
];
for (const [name, content] of samples) {
  await fs.writeFile(path.join(root, name), content, { flag: 'wx' });
}
const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="#2e6e56"/><text x="12" y="45" fill="white">FileNest</text></svg>';
await fs.writeFile(path.join(root, '旅行照片.svg'), svg);
await fs.writeFile(path.join(root, '旧资料/照片副本.svg'), svg);
console.log('演示文件夹已生成（仅使用合成样例）：');
console.log(root);
console.log('复制此路径到 FileNest，或启动：');
console.log(`node host/server.mjs --root "${root}"`);
