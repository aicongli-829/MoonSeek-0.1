import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { rootPath, scan } from './storage.mjs';
import { createPlan, exportCsv, exportMarkdown } from './planning.mjs';
import { execute, undo, history } from './transactions.mjs';
import { builtInTemplates, validateOptions } from './options.mjs';
import { listTemplates, saveTemplate, deleteTemplate } from './templates.mjs';

const publicDir = fileURLToPath(new URL('../web/', import.meta.url));
const assets = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/components.js', ['components.js', 'text/javascript; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
]);

async function body(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 2 * 1024 * 1024) {
      throw new Error('请求内容过大');
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

function json(res, value, status = 200) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(JSON.stringify(value));
}

export function createServer({ initialRoot = '', port = 4173 } = {}) {
  const token = randomBytes(32).toString('hex');
  let root = null;
  let inventory = null;
  let preview = null;
  let scanOptions = null;
  let job = null;

  function idle() {
    if (job?.status === 'running') {
      throw new Error('请等待当前操作结束');
    }
  }

  function requireRoot() {
    if (!root) {
      throw new Error('请先扫描一个文件夹');
    }
  }

  function launch(task) {
    idle();
    const current = {
      id: randomUUID(),
      status: 'running',
      progress: { phase: 'starting', completed: 0, total: 0 },
      stop: false,
      result: null,
      error: null,
    };
    job = current;
    Promise.resolve().then(() => task(current)).then(result => {
      current.result = result;
      current.status = 'finished';
    }).catch(error => {
      current.error = error.message;
      current.status = 'failed';
    });
    return { id: current.id };
  }

  const server = http.createServer(async (req, res) => {
    try {
      const address = server.address();
      const expectedHost = `127.0.0.1:${address.port}`;
      const origin = `http://${expectedHost}`;
      if (req.headers.host !== expectedHost) {
        return json(res, { error: 'Host 不匹配' }, 403);
      }
      if (req.headers.origin && req.headers.origin !== origin) {
        return json(res, { error: '只允许本地应用访问' }, 403);
      }
      if (req.headers['sec-fetch-site'] === 'cross-site') {
        return json(res, { error: '拒绝跨站请求' }, 403);
      }
      const url = new URL(req.url, origin);
      if (req.method === 'GET' && assets.has(url.pathname)) {
        const [name, type] = assets.get(url.pathname);
        res.writeHead(200, {
          'Content-Type': type,
          'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff',
          'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
        });
        res.end(await fs.readFile(path.join(publicDir, name)));
        return;
      }
      if (req.method === 'GET' && url.pathname === '/api/session') {
        return json(res, { token, initialRoot, builtInTemplates });
      }
      if (req.headers['x-filenest-token'] !== token) {
        return json(res, { error: '会话已失效，请刷新页面' }, 403);
      }
      if (req.method !== 'POST') {
        return json(res, { error: '不支持的请求方式' }, 405);
      }
      if (!req.headers['content-type']?.startsWith('application/json')) {
        return json(res, { error: '请使用 JSON 请求' }, 415);
      }
      const input = await body(req);
      switch (url.pathname) {
        case '/api/scan': {
          idle();
          if (typeof input.root !== 'string') {
            throw new Error('请输入文件夹路径');
          }
          const options = validateOptions(input.options);
          const selectedRoot = await rootPath(input.root);
          preview = null;
          inventory = null;
          return json(res, launch(async current => {
            const result = await scan(selectedRoot, options);
            root = selectedRoot;
            scanOptions = options;
            inventory = result;
            current.progress = {
              phase: 'scanned',
              completed: result.files.length,
              total: result.files.length,
            };
            return { root, inventory: result };
          }));
        }
        case '/api/preview': {
          idle();
          if (!inventory) {
            throw new Error('请先扫描文件夹');
          }
          const options = validateOptions(input.options);
          for (const key of ['recursive', 'hidden', 'extensions', 'exclude']) {
            if (JSON.stringify(options[key]) !== JSON.stringify(scanOptions[key])) {
              throw new Error('扫描范围已改变，请重新扫描');
            }
          }
          preview = createPlan(inventory, options);
          return json(res, preview);
        }
        case '/api/execute': {
          idle();
          requireRoot();
          if (!preview || input.planId !== preview.id || input.confirm !== true) {
            throw new Error('预览已失效，请重新预览后执行');
          }
          if (preview.rows.some(row => row.status === 'invalid')) {
            throw new Error('请先修复无效规则，或排除对应文件');
          }
          const approved = preview;
          const files = inventory.files;
          preview = null;
          inventory = null;
          return json(res, launch(current => execute(root, approved.rows, files, {
            shouldStop: () => current.stop,
            onProgress: progress => { current.progress = progress; },
          })));
        }
        case '/api/job': {
          if (!job || input.id !== job.id) {
            throw new Error('没有找到该操作');
          }
          return json(res, job);
        }
        case '/api/stop': {
          if (job?.status === 'running') {
            job.stop = true;
          }
          return json(res, { ok: true });
        }
        case '/api/history': {
          requireRoot();
          return json(res, { records: await history(root) });
        }
        case '/api/undo': {
          idle();
          requireRoot();
          preview = null;
          inventory = null;
          return json(res, launch(() => undo(root, input.id)));
        }
        case '/api/templates': {
          requireRoot();
          return json(res, await listTemplates(root));
        }
        case '/api/template/save': {
          idle();
          requireRoot();
          return json(res, await saveTemplate(root, input));
        }
        case '/api/template/delete': {
          idle();
          requireRoot();
          return json(res, await deleteTemplate(root, input.name));
        }
        case '/api/export': {
          if (!preview || input.planId !== preview.id) {
            throw new Error('请先生成最新预览');
          }
          const format = input.format;
          if (!['csv', 'json', 'md'].includes(format)) {
            throw new Error('不支持的报告格式');
          }
          const content = format === 'csv'
            ? exportCsv(preview)
            : format === 'md'
              ? exportMarkdown(preview)
              : JSON.stringify(preview, null, 2);
          return json(res, { content, filename: `filenest-preview.${format}` });
        }
        default:
          return json(res, { error: '接口不存在' }, 404);
      }
    } catch (error) {
      json(res, { error: error.message }, 400);
    }
  });
  return { server, port };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const rootIndex = args.indexOf('--root');
  const portIndex = args.indexOf('--port');
  const port = portIndex >= 0 ? Number(args[portIndex + 1]) : 4173;
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error('端口必须在 1024–65535 之间');
  }
  const { server } = createServer({
    initialRoot: rootIndex >= 0 ? args[rootIndex + 1] : '',
    port,
  });
  server.on('error', error => {
    console.error(error.code === 'EADDRINUSE' ? '端口已占用，请使用 --port 4174' : error.message);
    process.exitCode = 1;
  });
  server.listen(port, '127.0.0.1', () => {
    console.log(`FileNest 已启动：http://127.0.0.1:${port}`);
    console.log('在浏览器中打开上面的地址。按 Ctrl+C 退出。');
  });
}
