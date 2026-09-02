import { Hono } from 'hono';
import { ruleDb } from '../db/index.js';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import axios from 'axios';
import * as cheerio from 'cheerio';
import crypto from 'node:crypto';

import iconv from 'iconv-lite';

const require = createRequire(import.meta.url);
const rules = new Hono();

const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

/**
 * 智能嗅探网页编码并转换为标准的 UTF-8 字符串 (完美解决 GBK / GB2312 / GB18030 等中文乱码问题)
 */
function detectAndDecodeHtml(buffer: ArrayBuffer | Buffer, contentTypeHeader?: string): string {
  const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);

  let encoding = 'utf-8';

  // 1. 尝试从响应头 Content-Type 中提取 charset
  if (contentTypeHeader) {
    const match = contentTypeHeader.match(/charset=([a-zA-Z0-9_-]+)/i);
    if (match && match[1]) {
      encoding = match[1].toLowerCase().trim();
    }
  }

  // 2. 从 HTML 前 2048 字节嗅探 <meta ... charset="...">
  const headSnippet = buf.subarray(0, 2048).toString('binary');
  const metaMatch =
    headSnippet.match(/<meta[^>]+charset=["']?([a-zA-Z0-9_-]+)/i) ||
    headSnippet.match(/<meta[^>]+http-equiv=["']?Content-Type["']?[^>]+content=["'][^"']*charset=([a-zA-Z0-9_-]+)/i);

  if (metaMatch && metaMatch[1]) {
    const detected = metaMatch[1].toLowerCase().trim();
    if (['gbk', 'gb2312', 'gb18030', 'big5', 'shift_jis', 'euc-jp', 'euc-kr', 'windows-1252', 'iso-8859-1'].includes(detected)) {
      encoding = detected;
    }
  }

  // 兼容别名
  if (encoding === 'gb2312') encoding = 'gbk';
  if (encoding === 'utf8') encoding = 'utf-8';

  try {
    if (iconv.encodingExists(encoding)) {
      const decoded = iconv.decode(buf, encoding);
      // 如果声明的是 UTF-8 但解码后存在大量无效字符 (\uFFFD)，尝试 GBK 挽救
      if (encoding === 'utf-8' && decoded.includes('\uFFFD')) {
        const gbkTry = iconv.decode(buf, 'gbk');
        if (!gbkTry.includes('\uFFFD')) {
          return gbkTry;
        }
      }
      return decoded;
    }
  } catch {
    // 降级 fallback
  }

  return iconv.decode(buf, 'utf-8');
}

// GET / -> 获取所有规则列表
rules.get('/', async (c) => {
  try {
    const data = await ruleDb.getAllRules();
    return c.json({ data, total: data.length });
  } catch (error: any) {
    return c.json({ message: error.message }, 500);
  }
});

// GET /:id -> 获取单条规则详情
rules.get('/:id', async (c) => {
  try {
    const id = c.req.param('id');
    const rule = await ruleDb.getRuleById(id);
    if (!rule) {
      return c.json({ message: `Rule [ID:${id}] not found` }, 404);
    }
    return c.json(rule);
  } catch (error: any) {
    return c.json({ message: error.message }, 500);
  }
});

// POST / -> 保存规则 (更新/插入)
rules.post('/', async (c) => {
  try {
    const body = await c.req.json();
    const result = await ruleDb.saveRule(body);
    return c.json(result);
  } catch (error: any) {
    return c.json({ message: error.message }, 500);
  }
});

// POST /edit -> 编辑规则
rules.post('/edit', async (c) => {
  try {
    const body = await c.req.json();
    const id = body.id || c.req.query('id');
    if (!id) {
      return c.json({ message: 'Missing id' }, 400);
    }
    const result = await ruleDb.saveRule({ ...body, id });
    return c.json(result);
  } catch (error: any) {
    return c.json({ message: error.message }, 500);
  }
});

// DELETE /:id -> 删除规则
rules.delete('/:id', async (c) => {
  try {
    const id = c.req.param('id');
    await ruleDb.deleteRule(id);
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ message: error.message }, 500);
  }
});

// PATCH /:id/toggle -> 切换规则启用状态
rules.patch('/:id/toggle', async (c) => {
  try {
    const id = c.req.param('id');
    const body = await c.req.json();
    const enabled = body.enabled ? 1 : 0;
    await ruleDb.toggleRuleEnabled(id, enabled);
    return c.json({ success: true, enabled });
  } catch (error: any) {
    return c.json({ message: error.message }, 500);
  }
});

// POST /fetch-html & POST /fetch-page -> 抓取目标地址数据 (自动识别编码 GBK/UTF-8 并直接返回文本)
const handleFetchPage = async (c: any) => {
  try {
    const body = await c.req.json();
    const targetUrl = body.url;
    if (!targetUrl || !targetUrl.startsWith('http')) {
      return c.json({ message: '请提供有效的 HTTP/HTTPS 目标网址' }, 400);
    }

    const res = await axios.get(targetUrl, {
      headers: {
        'User-Agent': DEFAULT_USER_AGENT,
        Accept: '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        ...(body.headers || {})
      },
      timeout: 15000,
      responseType: 'arraybuffer'
    });

    const contentType = (res.headers['content-type'] || res.headers['Content-Type'] || '') as string;
    const data = detectAndDecodeHtml(res.data, contentType);

    return c.json({
      url: targetUrl,
      status: res.status,
      data,
      html: data // 兼容已有别名
    });
  } catch (error: any) {
    return c.json(
      {
        message: '抓取数据失败: ' + (error.message || String(error))
      },
      500
    );
  }
};

rules.post('/fetch-html', handleFetchPage);
rules.post('/fetch-page', handleFetchPage);

/**
 * 转换 ESModule 语法为适用于 Node.js VM 的 CommonJS 语法
 */
function transformESMToCJS(code: string): string {
  let runCode = code.trim();

  // 1. 转换顶层 import 语句
  const importRegex = /^\s*import\s+[\s\S]*?from\s+['"][^'"]+['"];?/gm;
  const imports: string[] = [];
  let cleanCode = runCode
    .replace(importRegex, (match: string) => {
      imports.push(match.trim());
      return '';
    })
    .trim();

  const processedImports = imports.map((imp) => {
    let converted = imp;
    if (/import\s+\*\s+as\s+([\w]+)\s+from\s+['"]([^'"]+)['"]/.test(converted)) {
      converted = converted.replace(
        /import\s+\*\s+as\s+([\w]+)\s+from\s+['"]([^'"]+)['"]/g,
        'const $1 = require("$2")'
      );
    } else if (/import\s+\{\s*([\w\s,]+)\s*\}\s+from\s+['"]([^'"]+)['"]/.test(converted)) {
      converted = converted.replace(
        /import\s+\{\s*([\w\s,]+)\s*\}\s+from\s+['"]([^'"]+)['"]/g,
        'const { $1 } = require("$2")'
      );
    } else if (/import\s+([\w]+)\s+from\s+['"]([^'"]+)['"]/.test(converted)) {
      converted = converted.replace(
        /import\s+([\w]+)\s+from\s+['"]([^'"]+)['"]/g,
        'const $1 = require("$2")'
      );
    }
    return converted;
  });

  // 2. 转换 export default 语法
  if (cleanCode.includes('export default')) {
    cleanCode = cleanCode
      .replace(
        /export\s+default\s+async\s+function\s*([\w]+)?\s*\(\s*([\w\s,]*)\s*\)/g,
        'module.exports = async function $1 ($2)'
      )
      .replace(
        /export\s+default\s+function\s*([\w]+)?\s*\(\s*([\w\s,]*)\s*\)/g,
        'module.exports = function $1 ($2)'
      )
      .replace(
        /export\s+default\s+async\s*\(?\s*([\w\s,]*)\s*\)?\s*=>/g,
        'module.exports = async ($1) =>'
      )
      .replace(
        /export\s+default\s*\(?\s*([\w\s,]*)\s*\)?\s*=>/g,
        'module.exports = ($1) =>'
      )
      .replace(/export\s+default\s+/g, 'module.exports = ');
  } else if (!cleanCode.includes('module.exports') && !cleanCode.includes('exports.')) {
    cleanCode = `module.exports = ${cleanCode}`;
  }

  return (
    (processedImports.length > 0 ? processedImports.join('\n') + '\n\n' : '') + cleanCode
  );
}

/**
 * 统一执行沙箱 (POST /run 及 POST /execute)
 */
async function executeSandbox(c: any) {
  // 收集沙箱内所有 console 日志
  const sandboxLogs: Array<{ level: 'log' | 'warn' | 'error' | 'info'; time: string; message: string }> = [];

  try {
    const reqBody = await c.req.json();
    let { code, ruleId, action, params, baseUrl } = reqBody;

    let targetRule: any = null;
    // 1. 如果传了 ruleId，从数据库读取规则
    if (ruleId) {
      targetRule = await ruleDb.getRuleById(ruleId);
      if (!targetRule) {
        return c.json({ message: `Rule [ID:${ruleId}] not found in database` }, 404);
      }
      code = targetRule.code;
    }

    // 2. 校验代码存在
    if (!code) {
      return c.json({ message: 'Missing rule code or ruleId' }, 400);
    }

    const targetAction: string = action || 'discovery';
    const targetParams = params || {};

    // 智能提取或回填 baseUrl
    const currentBaseUrl =
      targetParams.baseUrl ||
      baseUrl ||
      reqBody.targetUrl ||
      (targetRule ? targetRule.baseUrl : '') ||
      '';

    targetParams.baseUrl = currentBaseUrl;

    const runCode = transformESMToCJS(code);

    const allowModules = ['axios', 'cheerio', 'crypto', 'buffer', 'url', 'querystring', 'iconv-lite', 'iconv'];
    const sandboxRequire = (name: string) => {
      if (!allowModules.includes(name)) {
        throw new Error(`Module "${name}" is not permitted in rule sandbox`);
      }
      if (name === 'iconv-lite' || name === 'iconv') {
        return iconv;
      }
      return require(name);
    };
    const formatLogArg = (arg: any): string => {
      if (arg === null) return 'null';
      if (arg === undefined) return 'undefined';
      if (typeof arg === 'string') return arg;
      if (arg instanceof Error) return arg.stack || arg.message;
      try {
        return JSON.stringify(arg, null, 2);
      } catch {
        return String(arg);
      }
    };

    const recordLog = (level: 'log' | 'warn' | 'error' | 'info', args: any[]) => {
      const now = new Date();
      const time = now.toTimeString().split(' ')[0] + '.' + String(now.getMilliseconds()).padStart(3, '0');
      const message = args.map(formatLogArg).join(' ');
      sandboxLogs.push({ level, time, message });
      console[level === 'info' ? 'log' : level]('[Rule Sandbox]', ...args);
    };

    const vmContext: any = {
      require: sandboxRequire,
      axios,
      cheerio,
      crypto,
      iconv,
      Buffer,
      URL,
      URLSearchParams,
      ua: DEFAULT_USER_AGENT,
      baseUrl: currentBaseUrl,
      defineRule: (r: any) => r,
      params: targetParams,
      module: { exports: {} },
      exports: {},
      console: {
        log: (...args: any[]) => recordLog('log', args),
        warn: (...args: any[]) => recordLog('warn', args),
        error: (...args: any[]) => recordLog('error', args),
        info: (...args: any[]) => recordLog('info', args)
      }
    };

    vm.createContext(vmContext);

    // 编译并在沙箱运行
    const script = new vm.Script(runCode, { filename: 'rule-sandbox.js' });
    script.runInContext(vmContext, { timeout: 30000 });

    const exported: any = vmContext.module.exports || vmContext.exports;

    let result: any = null;

    if (typeof exported === 'function') {
      result = await exported(targetParams);
    } else if (exported && typeof exported === 'object') {
      // 保证 this.baseUrl 在对象方法中直接可用
      if (!exported.baseUrl && currentBaseUrl) {
        exported.baseUrl = currentBaseUrl;
      }

      // 动作方法查找映射（支持常用别名如 explore -> discovery）
      const actionMap: Record<string, string[]> = {
        discovery: ['discovery', 'explore', 'latest', 'list'],
        detail: ['detail', 'getDetail', 'info'],
        search: ['search', 'searchList'],
        parse: ['parse', 'watch', 'content']
      };

      const candidates = actionMap[targetAction] || [targetAction];
      let actionFn: any = null;

      for (const name of candidates) {
        if (typeof exported[name] === 'function') {
          actionFn = exported[name];
          break;
        }
        if (exported.default && typeof exported.default[name] === 'function') {
          actionFn = exported.default[name];
          break;
        }
      }

      if (actionFn) {
        // 兼容 key 与 url 字段别名
        if (targetParams.key && !targetParams.url) targetParams.url = targetParams.key;
        if (targetParams.url && !targetParams.key) targetParams.key = targetParams.url;

        // 统一严格对象命名参数入参：{ keyword, page, category, key, url, baseUrl, ... }
        result = await actionFn.call(exported, targetParams);
      } else if (typeof exported.default === 'function') {
        result = await exported.default(targetParams);
      } else {
        throw new Error(`Rule does not export method "${targetAction}"`);
      }
    } else {
      result = exported;
    }

    // 返回执行结果及收集到的控制台日志
    if (result && typeof result === 'object' && !Array.isArray(result)) {
      return c.json({
        ...result,
        result,
        logs: sandboxLogs
      });
    }

    return c.json({
      result,
      data: result,
      logs: sandboxLogs
    });
  } catch (error: any) {
    console.error('❌ [Sandbox Execution Error]:', error);
    return c.json(
      {
        message: error.message || 'Rule execution failed',
        stack: error.stack,
        logs: sandboxLogs
      },
      500
    );
  }
}

rules.post('/run', executeSandbox);
rules.post('/execute', executeSandbox);
rules.post('/test-sandbox', executeSandbox);

export default rules;
