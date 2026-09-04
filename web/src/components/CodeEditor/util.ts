import { libTypes } from './lib.type';

// 内存级类型定义文本缓存 (libName -> d.ts content)
const extraLibCache = new Map<string, string>();

/**
 * 使用 fetch 获取类型定义文件 并添加到 monaco 中 (带 Map 内存缓存加速)
 */
export const addExtraLibFromFetch = async (monaco: typeof import('monaco-editor'), libName: string) => {
  const filePath = `node_modules/@types/${libName}/index.d.ts`;

  // 1. 如果 Map 已经缓存过：直接从 Map 提取并注入 Monaco（0 毫秒、0 网络请求）
  if (extraLibCache.has(libName)) {
    const cachedContent = extraLibCache.get(libName)!;
    monaco.typescript.javascriptDefaults.addExtraLib(cachedContent, filePath);
    return;
  }

  // 2. 如果 Map 暂无：发起网络 fetch，获取后存入 Map 并注入 Monaco
  try {
    const response = await fetch(`https://cdn.jsdelivr.net/npm/@types/${libName}/index.d.ts`);
    if (!response.ok) return;
    const content = await response.text();

    extraLibCache.set(libName, content);
    monaco.typescript.javascriptDefaults.addExtraLib(content, filePath);
  } catch (error) {
    console.warn(`[CodeEditor] 获取类型定义 ${libName} 失败 (已静默跳过):`, error);
  }
}

/**
 * 添加第三方库类型定义
 */
export const addExtraLibs = async (monaco: typeof import('monaco-editor')) => {
  for (const [key, value] of Object.entries(libTypes)) {
    monaco.typescript.javascriptDefaults.addExtraLib(
      value,
      `node_modules/@types/${key}/index.d.ts`
    )
  }
}

/**
 * 添加沙箱全局预置类型定义 (如 ua, baseUrl, axios, cheerio, defineRule)
 */
export const addGlobalSandboxTypes = (monaco: typeof import('monaco-editor')) => {
  const globalTypes = `
    import type { AxiosStatic } from 'axios';
    import type * as cheerioType from 'cheerio';

    declare global {
      /**
       * 当前规则的目标源站 BaseURL
       */
      const baseUrl: string;

      /**
       * 移动端标准 User-Agent 字符串
       */
      const ua: string;

      /**
       * 全局内置 Axios HTTP 客户端实例
       */
      const axios: AxiosStatic;

      /**
       * 全局内置 Cheerio HTML DOM 解析库
       */
      const cheerio: typeof cheerioType;

      /**
       * 列表项标准模型
       */
      interface MediaItem {
        url: string;
        title: string;
        cover?: string;
        badge?: string;
        desc?: string;
        subtitle?: string;
        tags?: string;
        date?: string;
      }

      /**
       * 详情选集项标准模型
       */
      interface EpisodeItem {
        title: string;
        url: string;
      }

      /**
       * 详情选集线路分组
       */
      interface EpisodeGroup {
        name: string;
        items: EpisodeItem[];
      }

      /**
       * 详情页标准返回数据结构
       */
      interface DetailResult {
        title: string;
        cover?: string;
        desc?: string;
        tags?: string[];
        author?: string;
        /** 视频直链地址 (MP4 / M3U8) */
        playUrl?: string;
        /** 写真/漫画大图数组 (支持九宫格缩略图预览与长图浏览) */
        images?: string[];
        /** 小说正文内容 (若为小说源) */
        content?: string;
        /** 选集/分集线路列表 */
        groups?: EpisodeGroup[];
        /** 底部相关推荐/同模特作品 */
        recommendations?: MediaItem[];
      }

      /**
       * 发现/列表页标准返回数据结构
       */
      interface DiscoveryResult {
        categories?: string[] | Array<{ title: string; url: string }>;
        items: MediaItem[];
        hasMore?: boolean;
      }

      /**
       * 搜索页标准返回数据结构
       */
      interface SearchResult {
        items: MediaItem[];
        hasMore?: boolean;
      }

      /**
       * 规则定义接口
       */
      interface RuleDefinition {
        discovery?: (params: { category?: string; page?: number; baseUrl?: string }) => Promise<DiscoveryResult | MediaItem[] | any>;
        search?: (params: { keyword: string; page?: number; baseUrl?: string }) => Promise<SearchResult | MediaItem[] | any>;
        detail?: (params: { url: string; item?: any; baseUrl?: string }) => Promise<DetailResult | any>;
        parse?: (params: { url: string; groupName?: string; baseUrl?: string }) => Promise<{ playUrl?: string; content?: string } | any>;
        [key: string]: any;
      }

      /**
       * 辅助函数：定义 FluxForge 规范规则对象（提供完整的参数与返回值类型推导）
       */
      function defineRule<T extends RuleDefinition>(rule: T): T;
    }

    export {};
  `;

  monaco.typescript.javascriptDefaults.addExtraLib(
    globalTypes,
    'node_modules/@types/fluxforge-globals/index.d.ts'
  );

  monaco.typescript.typescriptDefaults.addExtraLib(
    globalTypes,
    'node_modules/@types/fluxforge-globals/index.d.ts'
  );
}

/**
 * 语言检测器：仅在明显匹配特定非 JS 格式（如 JSON、HTML、CSS、Python、SQL）时才识别切换
 */
export function detectLanguage(code: string): string | null {
  const trimmed = code.trim();
  if (!trimmed || trimmed.length < 3) return null;

  // 1. JSON (以 { 开头 } 结尾，或 [ 开头 ] 结尾，且可以被 JSON.parse 解析)
  if (
    (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
    (trimmed.startsWith('[') && trimmed.endsWith(']'))
  ) {
    try {
      JSON.parse(trimmed);
      return 'json';
    } catch {}
  }

  // 2. HTML / XML
  if (
    /^<!DOCTYPE html/i.test(trimmed) ||
    /^<html[\s>]/i.test(trimmed) ||
    /^<\?xml/i.test(trimmed) ||
    /^<([a-zA-Z][a-zA-Z0-9-]*)[^>]*>[\s\S]*<\/\1>$/.test(trimmed)
  ) {
    return 'html';
  }

  // 3. CSS / SCSS
  if (
    /(?:[\.#][\w-]+\s*\{|@media|@keyframes|--[\w-]+:)/.test(trimmed) &&
    trimmed.includes('{') &&
    trimmed.includes('}')
  ) {
    return 'css';
  }

  // 4. SQL
  if (
    /^(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE)\b/i.test(trimmed)
  ) {
    return 'sql';
  }

  // 5. Python (以 def / import / class 开头且无 JS 关键字)
  if (
    /^(def\s+\w+\s*\(|class\s+\w+(\(.*\))?\s*:|import\s+\w+|from\s+\w+\s+import)/m.test(trimmed) &&
    !/(const|let|var|function|export|export\s+default)\b/.test(trimmed)
  ) {
    return 'python';
  }

  // 6. JavaScript / TypeScript
  if (
    /^(import\s+|export\s+|const\s+|let\s+|var\s+|function\s+|async\s+function|module\.exports)/m.test(trimmed)
  ) {
    return 'javascript';
  }

  return null;
}