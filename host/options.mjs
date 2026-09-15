export const defaultOptions = {
  classify: 'type',
  conflict: 'skip',
  sort: 'name',
  sequenceStart: '1',
  sequenceWidth: '3',
  recursive: true,
  hidden: false,
  extensions: [],
  exclude: [],
  excluded: [],
  quarantine: [],
  rules: [],
  categories: [],
};

export const builtInTemplates = [
  {
    name: '下载文件夹',
    description: '按类型归档，统一扩展名，保留原文件名',
    options: {
      ...defaultOptions,
      rules: [{ kind: 'extension_lower', value: '', replacement: '' }],
    },
  },
  {
    name: '旅行照片',
    description: '只选择图片，按修改月份分类并编号',
    options: {
      ...defaultOptions,
      classify: 'month',
      conflict: 'number',
      extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
      rules: [
        { kind: 'number', value: '旅行_', replacement: '' },
        { kind: 'extension_lower', value: '', replacement: '' },
      ],
    },
  },
  {
    name: '课程资料',
    description: '清除“副本”，规范空格，按类型分类',
    options: {
      ...defaultOptions,
      conflict: 'number',
      rules: [
        { kind: 'remove', value: ' (副本)', replacement: '' },
        { kind: 'remove', value: '（副本）', replacement: '' },
        { kind: 'spaces', value: '', replacement: '' },
        { kind: 'extension_lower', value: '', replacement: '' },
      ],
    },
  },
  {
    name: '扫描件编号',
    description: '保持文件夹位置，按自然顺序重新编号',
    options: {
      ...defaultOptions,
      classify: 'none',
      conflict: 'number',
      extensions: ['jpg', 'png', 'pdf'],
      rules: [{ kind: 'number', value: '扫描_第', replacement: '' }],
    },
  },
];

const ruleKinds = new Set([
  'prefix',
  'suffix',
  'replace',
  'remove',
  'lower',
  'upper',
  'spaces',
  'separator',
  'extension_lower',
  'number',
  'number_suffix',
  'regex',
]);

function object(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label}必须是对象`);
  }
  return value;
}

function text(value, label, limit = 200) {
  if (typeof value !== 'string' || value.length > limit) {
    throw new Error(`${label}必须是长度不超过 ${limit} 的文字`);
  }
  return value;
}

function choice(value, choices, label) {
  if (!choices.includes(value)) {
    throw new Error(`${label}不支持：${String(value)}`);
  }
  return value;
}

function stringList(value, label, max = 10000) {
  if (!Array.isArray(value) || value.length > max) {
    throw new Error(`${label}数量过多或格式错误`);
  }
  return [...new Set(value.map(x => text(x, label, 1000)))];
}

function boundedInteger(value, min, max, label) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < min || number > max) {
    throw new Error(`${label}必须是 ${min}–${max} 的整数`);
  }
  return String(number);
}

export function validateOptions(input = {}) {
  object(input, '设置');
  const merged = { ...defaultOptions, ...input };
  const result = {
    classify: choice(merged.classify, ['none', 'type', 'month', 'type_month', 'custom'], '分类方式'),
    conflict: choice(merged.conflict, ['skip', 'number'], '冲突方式'),
    sort: choice(merged.sort, ['name', 'path', 'month', 'size'], '排序'),
    sequenceStart: boundedInteger(merged.sequenceStart, 0, 1000000, '起始编号'),
    sequenceWidth: boundedInteger(merged.sequenceWidth, 1, 8, '编号宽度'),
    recursive: merged.recursive !== false,
    hidden: merged.hidden === true,
    extensions: stringList(merged.extensions, '扩展名', 100),
    exclude: stringList(merged.exclude, '排除目录', 100),
    excluded: stringList(merged.excluded, '排除文件'),
    quarantine: stringList(merged.quarantine, '隔离文件'),
    rules: [],
    categories: [],
  };
  if (!Array.isArray(merged.rules) || merged.rules.length > 30) {
    throw new Error('最多允许 30 条命名规则');
  }
  for (const raw of merged.rules) {
    const rule = object(raw, '命名规则');
    if (!ruleKinds.has(rule.kind)) {
      throw new Error('未知命名规则');
    }
    result.rules.push({
      kind: rule.kind,
      value: text(rule.value ?? '', '规则内容'),
      replacement: text(rule.replacement ?? '', '替换内容'),
    });
  }
  if (!Array.isArray(merged.categories) || merged.categories.length > 30) {
    throw new Error('最多允许 30 条分类规则');
  }
  for (const raw of merged.categories) {
    const rule = object(raw, '分类规则');
    result.categories.push({
      kind: choice(rule.kind, ['extension', 'keyword'], '分类匹配方式'),
      value: text(rule.value, '分类匹配内容'),
      folder: text(rule.folder, '分类文件夹'),
    });
  }
  return result;
}

export function validateTemplate(input) {
  object(input, '模板');
  const name = text(input.name, '模板名称', 40).trim();
  if (!name) {
    throw new Error('模板名称不能为空');
  }
  const options = validateOptions(input.options);
  options.excluded = [];
  options.quarantine = [];
  return {
    name,
    description: text(input.description ?? '我的整理规则', '模板说明', 120),
    options,
  };
}
