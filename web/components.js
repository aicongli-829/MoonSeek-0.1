export function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  if (text !== undefined) {
    node.textContent = text;
  }
  return node;
}

export function button(label, handler, className = 'ghost') {
  const node = element('button', className, label);
  node.type = 'button';
  node.addEventListener('click', handler);
  return node;
}

export function select(items, value, handler, label) {
  const node = element('select');
  node.setAttribute('aria-label', label);
  for (const [key, name] of items) {
    const option = element('option', '', name);
    option.value = key;
    node.append(option);
  }
  node.value = value;
  node.addEventListener('change', () => handler(node.value));
  return node;
}

export function input(value, placeholder, handler) {
  const node = element('input');
  node.value = value;
  node.placeholder = placeholder;
  node.setAttribute('aria-label', placeholder);
  node.addEventListener('input', () => handler(node.value));
  return node;
}

export function formatBytes(value) {
  if (!value) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
  return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`;
}

export const ruleTypes = [
  ['prefix', '添加前缀'],
  ['suffix', '添加后缀'],
  ['replace', '替换文字'],
  ['remove', '删除文字'],
  ['spaces', '整理多余空格'],
  ['separator', '空格转分隔符'],
  ['number', '统一名称 + 编号'],
  ['number_suffix', '原名称 + 编号'],
  ['lower', '名称转小写'],
  ['upper', '名称转大写'],
  ['extension_lower', '扩展名转小写'],
  ['regex', '正则替换（字面替换值）'],
];

export function renderRules(container, rules, changed) {
  container.replaceChildren();
  if (!rules.length) {
    container.append(element('p', 'small muted', '尚未添加规则，将保留原文件名。'));
  }
  rules.forEach((rule, index) => {
    const card = element('div', 'rule-card');
    const header = element('div', 'rule-header');
    header.append(element('span', 'rule-number', String(index + 1).padStart(2, '0')));
    header.append(select(ruleTypes, rule.kind, kind => {
      rule.kind = kind;
      changed();
      renderRules(container, rules, changed);
    }, `第 ${index + 1} 条命名规则`));
    const controls = element('div', 'rule-controls');
    const up = button('↑', () => {
      [rules[index - 1], rules[index]] = [rules[index], rules[index - 1]];
      changed();
      renderRules(container, rules, changed);
    });
    up.disabled = index === 0;
    up.setAttribute('aria-label', '上移规则');
    const down = button('↓', () => {
      [rules[index + 1], rules[index]] = [rules[index], rules[index + 1]];
      changed();
      renderRules(container, rules, changed);
    });
    down.disabled = index === rules.length - 1;
    down.setAttribute('aria-label', '下移规则');
    const remove = button('×', () => {
      rules.splice(index, 1);
      changed();
      renderRules(container, rules, changed);
    });
    remove.setAttribute('aria-label', '删除规则');
    controls.append(up, down, remove);
    card.append(header, controls);
    if (!['spaces', 'lower', 'upper', 'extension_lower'].includes(rule.kind)) {
      card.append(input(rule.value, rule.kind.startsWith('number') ? '名称或分隔符，例如 照片_' : '规则内容', value => {
        rule.value = value;
        changed();
      }));
    }
    if (['replace', 'regex'].includes(rule.kind)) {
      card.append(input(rule.replacement, '替换为（可留空）', value => {
        rule.replacement = value;
        changed();
      }));
    }
    container.append(card);
  });
}

export function renderCategories(container, rules, changed) {
  container.replaceChildren();
  rules.forEach((rule, index) => {
    const card = element('div', 'rule-card');
    card.append(select([
      ['extension', '扩展名匹配'],
      ['keyword', '文件名包含'],
    ], rule.kind, value => {
      rule.kind = value;
      changed();
    }, `第 ${index + 1} 条分类规则`));
    card.append(input(rule.value, '匹配内容，例如 pdf, docx', value => {
      rule.value = value;
      changed();
    }));
    card.append(input(rule.folder, '目标文件夹，例如 工作/合同', value => {
      rule.folder = value;
      changed();
    }));
    const controls = element('div', 'rule-controls');
    const up = button('↑ 上移', () => {
      [rules[index - 1], rules[index]] = [rules[index], rules[index - 1]];
      changed();
      renderCategories(container, rules, changed);
    });
    up.disabled = index === 0;
    controls.append(up, button('删除', () => {
      rules.splice(index, 1);
      changed();
      renderCategories(container, rules, changed);
    }));
    card.append(controls);
    container.append(card);
  });
}

export const statusNames = {
  ready: '准备整理',
  conflict: '名称冲突',
  invalid: '需要修正',
  unchanged: '无需改变',
  excluded: '已排除',
};

export function fileIcon(name) {
  const ext = name.split('.').at(-1).toLowerCase();
  if (['jpg', 'jpeg', 'png', 'gif', 'svg', 'heic', 'webp'].includes(ext)) {
    return ['image-file', '▧'];
  }
  if (['zip', 'rar', '7z', 'gz'].includes(ext)) {
    return ['archive-file', '▥'];
  }
  if (['mp4', 'mov', 'mkv'].includes(ext)) {
    return ['video-file', '▷'];
  }
  return ['document-file', '▤'];
}

export function download(content, name) {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = element('a');
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
