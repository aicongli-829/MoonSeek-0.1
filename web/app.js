import {
  element,
  button,
  formatBytes,
  renderRules,
  renderCategories,
  statusNames,
  fileIcon,
  download,
} from './components.js';

const $ = id => document.getElementById(id);
let token = '';
let inventory = null;
let preview = null;
let busy = false;
let page = 0;
let templates = [];
let rules = [];
let categories = [];
const excluded = new Set();
const quarantine = new Set();
const pageSize = 50;

const descriptions = {
  organize: ['分类与改名', '让每个文件，各归其位。', '分类、改名、检查重复。从一份清晰的预览开始。'],
  duplicates: ['重复文件', '相同的内容，不必存很多份。', '逐字节确认重复，自己决定保留哪一份。'],
  history: ['操作历史', '每一次整理，都有来路。', '查看文件的新位置，或把一次整理恢复原状。'],
  templates: ['规则模板', '整理一次，轻松用很多次。', '把常用的分类与命名方式保存下来。'],
};

function notify(text, error = false) {
  $('message').hidden = false;
  $('message').className = error ? 'error-message' : 'success-message';
  $('message').textContent = text;
}

async function api(route, input = {}) {
  const response = await fetch('/api/' + route, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-FileNest-Token': token,
    },
    body: JSON.stringify(input),
  });
  const value = await response.json();
  if (!response.ok || value.error) {
    throw new Error(value.error || '请求失败');
  }
  return value;
}

function guarded(handler) {
  return async (...args) => {
    try {
      await handler(...args);
    } catch (error) {
      notify(error.message, true);
    }
  };
}

function commaList(id) {
  return $(id).value.split(/[,，]/).map(s => s.trim()).filter(Boolean);
}

function options() {
  return {
    classify: $('classify').value,
    conflict: $('conflict').value,
    sort: $('sort').value,
    sequenceStart: $('sequence-start').value,
    sequenceWidth: $('sequence-width').value,
    recursive: $('recursive').checked,
    hidden: $('hidden-files').checked,
    extensions: commaList('extensions'),
    exclude: commaList('exclude'),
    excluded: [...excluded],
    quarantine: [...quarantine],
    rules,
    categories,
  };
}

function setOptions(value) {
  $('classify').value = value.classify || 'type';
  $('conflict').value = value.conflict || 'skip';
  $('sort').value = value.sort || 'name';
  $('sequence-start').value = value.sequenceStart ?? '1';
  $('sequence-width').value = value.sequenceWidth ?? '3';
  $('recursive').checked = value.recursive !== false;
  $('hidden-files').checked = value.hidden === true;
  $('extensions').value = (value.extensions || []).join(', ');
  $('exclude').value = (value.exclude || []).join(', ');
  rules = structuredClone(value.rules || []);
  categories = structuredClone(value.categories || []);
  renderEditors();
  invalidate();
}

function renderEditors() {
  renderRules($('rule-list'), rules, invalidate);
  renderCategories($('category-list'), categories, invalidate);
  $('category-editor').hidden = $('classify').value !== 'custom';
}

function invalidate() {
  preview = null;
  $('preview-hint').textContent = inventory
    ? '规则已更新，请重新生成预览。扫描范围改变时需重新扫描。'
    : '扫描后配置规则，查看文件将去往哪里。';
  updateButtons();
}

function updateButtons() {
  $('scan').disabled = busy;
  $('preview').disabled = busy || !inventory;
  $('execute').disabled = busy || !preview || !preview.summary.ready || preview.summary.invalid > 0;
  for (const format of ['csv', 'json', 'md']) {
    $('export-' + format).disabled = busy || !preview;
  }
  $('duplicate-preview').disabled = busy || !inventory;
  $('save-template').disabled = busy || !inventory;
}

function switchView(view) {
  for (const section of document.querySelectorAll('.view')) {
    section.hidden = section.id !== 'view-' + view;
  }
  for (const item of document.querySelectorAll('.nav-item')) {
    item.classList.toggle('active', item.dataset.view === view);
  }
  const [title, heading, description] = descriptions[view];
  $('breadcrumb').textContent = title;
  $('page-title').textContent = heading;
  $('page-description').textContent = description;
  if (view === 'history' && inventory) {
    guarded(loadHistory)();
  }
}

async function pollJob(id, label) {
  busy = true;
  updateButtons();
  $('progress-panel').hidden = false;
  $('stop').disabled = label !== '整理';
  $('progress-text').textContent = `${label}中，请稍候…`;
  $('progress').removeAttribute('value');
  try {
    while (true) {
      const job = await api('job', { id });
      if (job.progress.total) {
        const { phase, completed, total } = job.progress;
        $('progress').value = completed / total * 100;
        const prefix = phase === 'staging' ? '准备文件' : label;
        $('progress-text').textContent = `${prefix} · ${completed} / ${total}`;
      }
      if (job.status === 'failed') {
        throw new Error(job.error);
      }
      if (job.status === 'finished') {
        return job.result;
      }
      await new Promise(resolve => setTimeout(resolve, 350));
    }
  } finally {
    busy = false;
    $('progress-panel').hidden = true;
    updateButtons();
  }
}

async function doScan() {
  if (busy) {
    return;
  }
  const root = $('root').value.trim().replace(/^"|"$/g, '');
  if (!root) {
    throw new Error('请先粘贴一个文件夹路径');
  }
  excluded.clear();
  quarantine.clear();
  invalidate();
  const started = await api('scan', { root, options: options() });
  const result = await pollJob(started.id, '扫描');
  inventory = result.inventory;
  $('root').value = result.root;
  $('stat-total').textContent = inventory.files.length;
  $('stat-duplicates').textContent = inventory.duplicates.length;
  $('duplicate-count').textContent = inventory.duplicates.length;
  $('warnings').replaceChildren(...inventory.warnings.map(text => element('li', '', text)));
  $('warnings-panel').hidden = inventory.warnings.length === 0;
  page = 0;
  renderDuplicates();
  await loadTemplates();
  await doPreview();
  if (!$('view-history').hidden) {
    await loadHistory();
  }
  notify(`扫描完成，找到 ${inventory.files.length} 个文件。还没有移动或改名任何文件。`);
}

async function doPreview() {
  if (!inventory) {
    throw new Error('请先扫描文件夹');
  }
  preview = await api('preview', { options: options() });
  $('stat-ready').textContent = preview.summary.ready;
  $('stat-conflict').textContent = preview.summary.conflict + preview.summary.invalid;
  $('stat-savings').textContent = `重复副本共 ${formatBytes(preview.summary.duplicateBytes)}`;
  $('preview-hint').textContent = `${preview.summary.ready} 个文件可整理，${preview.summary.conflict} 个冲突会跳过。`;
  renderTable();
  updateButtons();
}

function visibleRows() {
  if (!preview) {
    return [];
  }
  const query = $('search').value.toLowerCase();
  const status = $('status-filter').value;
  return preview.rows.filter(row => {
    const matchesText = (row.source + ' ' + row.target).toLowerCase().includes(query);
    const matchesStatus = status === 'all' || row.status === status;
    return matchesText && matchesStatus;
  });
}

function renderTable() {
  if (!preview) {
    return;
  }
  const filtered = visibleRows();
  const pageCount = Math.max(1, Math.ceil(filtered.length / pageSize));
  page = Math.min(page, pageCount - 1);
  const current = filtered.slice(page * pageSize, (page + 1) * pageSize);
  $('empty-state').hidden = preview.rows.length > 0;
  $('table-wrap').hidden = preview.rows.length === 0;
  $('row-count').textContent = `${filtered.length} 个文件`;
  $('file-rows').replaceChildren();
  const sizes = new Map(inventory.files.map(file => [file.path, Number(file.size)]));
  for (const row of current) {
    const tr = element('tr');
    const choice = element('input');
    choice.type = 'checkbox';
    choice.checked = !excluded.has(row.source);
    choice.setAttribute('aria-label', `包含 ${row.source}`);
    choice.addEventListener('change', () => {
      if (choice.checked) {
        excluded.delete(row.source);
      } else {
        excluded.add(row.source);
        quarantine.delete(row.source);
      }
      invalidate();
    });
    const checkCell = element('td');
    checkCell.append(choice);
    const sourceCell = element('td');
    const nameLine = element('div', 'file-name');
    const [iconClass, icon] = fileIcon(row.source);
    nameLine.append(element('span', 'file-icon ' + iconClass, icon));
    nameLine.append(element('span', '', row.source.split('/').at(-1)));
    sourceCell.append(nameLine);
    sourceCell.append(element('div', 'file-path', `${row.source} · ${formatBytes(sizes.get(row.source))}`));
    const targetCell = element('td', 'target-path', row.target);
    const stateCell = element('td');
    const badge = element('span', 'state state-' + row.status, statusNames[row.status]);
    badge.title = row.reason;
    stateCell.append(badge);
    if (['invalid', 'conflict'].includes(row.status)) {
      stateCell.append(element('small', 'reason', row.reason));
    }
    tr.append(checkCell, sourceCell, targetCell, stateCell);
    $('file-rows').append(tr);
  }
  $('page-info').textContent = `第 ${page + 1} / ${pageCount} 页`;
  $('prev-page').disabled = page === 0;
  $('next-page').disabled = page >= pageCount - 1;
  $('select-all').checked = excluded.size === 0;
}

function renderDuplicates() {
  const container = $('duplicate-list');
  container.replaceChildren();
  if (!inventory?.duplicates.length) {
    container.append(element('p', 'placeholder', '没有发现内容完全相同的文件。'));
    return;
  }
  const byPath = new Map(inventory.files.map(file => [file.path, file]));
  inventory.duplicates.forEach((group, index) => {
    const card = element('article', 'duplicate-card');
    const header = element('div', 'panel-title');
    const title = element('h3', '', `重复组 ${index + 1}`);
    const size = formatBytes(Number(byPath.get(group[0]).size));
    header.append(title, element('span', 'muted small', `${group.length} 份 · 每份 ${size}`));
    card.append(header);
    for (const name of group) {
      const label = element('label', 'duplicate-file');
      const checkbox = element('input');
      checkbox.type = 'checkbox';
      checkbox.checked = quarantine.has(name);
      checkbox.addEventListener('change', () => {
        if (checkbox.checked && group.filter(p => !quarantine.has(p)).length <= 1) {
          checkbox.checked = false;
          notify('每组至少保留一份文件。', true);
          return;
        }
        if (checkbox.checked) {
          quarantine.add(name);
          excluded.delete(name);
        } else {
          quarantine.delete(name);
        }
        invalidate();
      });
      label.append(checkbox, element('span', '', name), element('small', 'muted', '勾选隔离'));
      card.append(label);
    }
    container.append(card);
  });
}

async function loadHistory() {
  const { records } = await api('history');
  const container = $('history-list');
  container.replaceChildren();
  if (!records.length) {
    container.append(element('p', 'placeholder', '还没有执行记录。整理完成后会自动保存在这里。'));
  }
  const labels = {
    completed: '整理完成',
    interrupted: '中途停止',
    running: '意外中断，待恢复',
    undone: '已撤销',
    undoing: '撤销中断，待恢复',
    'undo-failed': '撤销待处理',
    unreadable: '记录无法读取',
  };
  for (const record of records) {
    const card = element('article', 'history-card');
    const header = element('div', 'panel-title');
    const title = element('div');
    title.append(element('h3', '', labels[record.status] || record.status));
    title.append(element('p', 'small muted', `${record.created ? new Date(record.created).toLocaleString() : '未知时间'} · ${record.operations.length} 个文件`));
    header.append(title);
    if (!['undone', 'unreadable'].includes(record.status)) {
      header.append(button('恢复原状', guarded(async () => {
        if (!await confirmUndo(record)) return;
        const started = await api('undo', { id: record.id });
        const result = await pollJob(started.id, '恢复');
        inventory = null;
        invalidate();
        notify(result.error || '恢复完成。新增的空目录会保留。', Boolean(result.error));
        await loadHistory();
      }), 'secondary'));
    }
    card.append(header);
    if (record.error) {
      card.append(element('p', 'error-text', record.error));
    }
    const details = element('details');
    details.append(element('summary', '', '查看文件去向与执行状态'));
    for (const op of record.operations) {
      details.append(element('p', 'history-operation', `${op.source} → ${op.target} · ${op.phase}`));
    }
    card.append(details);
    container.append(card);
  }
}

function confirmUndo(record) {
  $('undo-description').textContent = `这次将恢复 ${record.operations.length} 个文件。`;
  $('undo-dialog').showModal();
  return new Promise(resolve => {
    const finish = result => {
      $('undo-dialog').close();
      $('cancel-undo').onclick = null;
      $('confirm-undo').onclick = null;
      $('undo-dialog').oncancel = null;
      resolve(result);
    };
    $('cancel-undo').onclick = () => finish(false);
    $('confirm-undo').onclick = () => finish(true);
    $('undo-dialog').oncancel = event => {
      event.preventDefault();
      finish(false);
    };
  });
}

function renderTemplates() {
  $('template-select').replaceChildren(element('option', '', '选择一个模板…'));
  $('template-select').firstChild.value = '';
  $('template-cards').replaceChildren();
  templates.forEach((template, index) => {
    const option = element('option', '', template.name);
    option.value = String(index);
    $('template-select').append(option);
    const card = element('article', 'template-card');
    card.append(element('div', 'template-symbol', '◇'));
    card.append(element('h3', '', template.name));
    card.append(element('p', 'muted', template.description));
    card.append(button('应用模板 →', () => {
      setOptions(template.options);
      switchView('organize');
      notify('已应用模板。如果扫描范围改变，请重新扫描。');
    }, 'secondary'));
    if (template.custom) {
      card.append(button('删除', guarded(async () => {
        await api('template/delete', { name: template.name });
        await loadTemplates();
      }), 'text-button'));
    }
    $('template-cards').append(card);
  });
}

async function loadTemplates() {
  const all = await api('templates');
  templates = [...all.builtIn, ...all.custom.map(t => ({ ...t, custom: true }))];
  renderTemplates();
}

for (const item of document.querySelectorAll('.nav-item')) {
  item.addEventListener('click', () => switchView(item.dataset.view));
}
$('scan').addEventListener('click', guarded(doScan));
$('preview').addEventListener('click', guarded(doPreview));
$('root').addEventListener('input', () => {
  inventory = null;
  invalidate();
});
$('add-rule').addEventListener('click', () => {
  if (rules.length >= 30) {
    return notify('最多支持 30 条规则', true);
  }
  rules.push({ kind: 'prefix', value: '', replacement: '' });
  renderEditors();
  invalidate();
});
$('add-category').addEventListener('click', () => {
  categories.push({ kind: 'keyword', value: '', folder: '' });
  renderEditors();
  invalidate();
});
for (const id of ['classify', 'conflict', 'sort', 'sequence-start', 'sequence-width', 'recursive', 'hidden-files', 'extensions', 'exclude']) {
  $(id).addEventListener('input', () => {
    invalidate();
    if (id === 'classify') {
      renderEditors();
    }
  });
}
$('reset').addEventListener('click', () => setOptions({}));
$('template-select').addEventListener('change', () => {
  if ($('template-select').value !== '') {
    setOptions(templates[Number($('template-select').value)].options);
  }
});
for (const id of ['search', 'status-filter']) {
  $(id).addEventListener('input', () => {
    page = 0;
    renderTable();
  });
}
$('prev-page').addEventListener('click', () => {
  page--;
  renderTable();
});
$('next-page').addEventListener('click', () => {
  page++;
  renderTable();
});
$('select-all').addEventListener('change', guarded(async () => {
  const checked = $('select-all').checked;
  for (const file of inventory.files) {
    if (checked) {
      excluded.delete(file.path);
    } else {
      excluded.add(file.path);
      quarantine.delete(file.path);
    }
  }
  await doPreview();
}));
$('duplicate-preview').addEventListener('click', guarded(async () => {
  switchView('organize');
  await doPreview();
}));
$('execute').addEventListener('click', () => {
  $('confirm-description').textContent = `本次将处理 ${preview.summary.ready} 个文件。请确认预览中的目标位置。`;
  $('confirm-dialog').showModal();
});
$('cancel-execute').addEventListener('click', () => $('confirm-dialog').close());
$('confirm-execute').addEventListener('click', guarded(async () => {
  $('confirm-dialog').close();
  const started = await api('execute', { planId: preview.id, confirm: true });
  invalidate();
  inventory = null;
  const result = await pollJob(started.id, '整理');
  notify(result.error || '整理完成！可以在操作历史中查看或撤销。', Boolean(result.error));
  switchView('history');
  await loadHistory();
}));
$('stop').addEventListener('click', guarded(async () => {
  await api('stop');
  $('stop').disabled = true;
  $('progress-text').textContent = '正在完成当前文件，随后停止…';
}));
$('refresh-history').addEventListener('click', guarded(loadHistory));
for (const format of ['csv', 'json', 'md']) {
  $('export-' + format).addEventListener('click', guarded(async () => {
    const result = await api('export', { planId: preview.id, format });
    download(result.content, result.filename);
  }));
}
$('save-template').addEventListener('click', () => $('template-dialog').showModal());
$('cancel-template').addEventListener('click', () => $('template-dialog').close());
$('confirm-template').addEventListener('click', guarded(async () => {
  await api('template/save', { name: $('template-name').value, options: options() });
  $('template-dialog').close();
  await loadTemplates();
  notify('模板已保存。');
}));

guarded(async () => {
  const response = await fetch('/api/session');
  const session = await response.json();
  token = session.token;
  $('root').value = session.initialRoot;
  templates = session.builtInTemplates;
  renderTemplates();
  renderEditors();
  updateButtons();
})();
