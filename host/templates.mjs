import fs from 'node:fs/promises';
import path from 'node:path';
import { stateDir, safePath, atomicJson } from './storage.mjs';
import { builtInTemplates, validateTemplate } from './options.mjs';

export async function listTemplates(root) {
  await stateDir(root);
  const file = await safePath(root, '.filenest/templates.json', { internal: true });
  let custom = [];
  try {
    const parsed = JSON.parse(await fs.readFile(file, 'utf8'));
    if (!Array.isArray(parsed)) {
      throw new Error('模板文件格式错误');
    }
    custom = parsed.map(validateTemplate);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }
  return {
    builtIn: structuredClone(builtInTemplates),
    custom,
  };
}

export async function saveTemplate(root, input) {
  const template = validateTemplate(input);
  const all = await listTemplates(root);
  const remaining = all.custom.filter(item => item.name !== template.name);
  if (remaining.length >= 30) {
    throw new Error('最多保存 30 个自定义模板');
  }
  remaining.push(template);
  const dir = await stateDir(root);
  await atomicJson(path.join(dir, 'templates.json'), remaining);
  return listTemplates(root);
}

export async function deleteTemplate(root, name) {
  const all = await listTemplates(root);
  const remaining = all.custom.filter(item => item.name !== name);
  const dir = await stateDir(root);
  await atomicJson(path.join(dir, 'templates.json'), remaining);
  return listTemplates(root);
}
