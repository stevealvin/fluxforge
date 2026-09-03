import vm from 'node:vm';
import { createRequire } from 'node:module';
import axios from 'axios';
import * as cheerio from 'cheerio';
import crypto from 'node:crypto';
import iconv from 'iconv-lite';
import { DEFAULT_USER_AGENT } from './crawler.service.js';

const require = createRequire(import.meta.url);

export interface SandboxLog {
  level: 'log' | 'warn' | 'error' | 'info';
  time: string;
  message: string;
}

export interface ExecuteRulePayload {
  code?: string;
  action?: string;
  params?: Record<string, any>;
  baseUrl?: string;
  targetUrl?: string;
}

/**
 * 转换 ESModule 语法为适用于 Node.js VM 的 CommonJS 语法
 */
export function transformESMToCJS(code: string): string {
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

export const sandboxService = {
  /**
   * 在独立的 Node.js VM 沙箱中执行规则脚本
   */
  async executeRule(payload: ExecuteRulePayload): Promise<{ result: any; logs: SandboxLog[] }> {
    const { code, action, params, baseUrl, targetUrl } = payload;
    if (!code) {
      throw new Error('缺少规则脚本代码 (Missing rule code)');
    }

    const sandboxLogs: SandboxLog[] = [];
    const targetAction: string = action || 'discovery';
    const targetParams = params || {};

    // 智能提取或回填 baseUrl
    const currentBaseUrl =
      targetParams.baseUrl ||
      baseUrl ||
      targetUrl ||
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

    // 编译并在沙箱运行 (超时时间 30 秒)
    const script = new vm.Script(runCode, { filename: 'rule-sandbox.js' });
    script.runInContext(vmContext, { timeout: 30000 });

    const exported: any = vmContext.module.exports || vmContext.exports;
    let result: any = null;

    if (typeof exported === 'function') {
      result = await exported(targetParams);
    } else if (exported && typeof exported === 'object') {
      if (!exported.baseUrl && currentBaseUrl) {
        exported.baseUrl = currentBaseUrl;
      }

      // 动作方法查找映射（兼容常用别名）
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

        result = await actionFn.call(exported, targetParams);
      } else if (typeof exported.default === 'function') {
        result = await exported.default(targetParams);
      } else {
        throw new Error(`Rule does not export method "${targetAction}"`);
      }
    } else {
      result = exported;
    }

    return {
      result,
      logs: sandboxLogs
    };
  }
};
