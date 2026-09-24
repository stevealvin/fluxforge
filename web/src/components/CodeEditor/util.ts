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
    const filePath = `node_modules/@types/${key}/index.d.ts`;
    monaco.typescript.javascriptDefaults.addExtraLib(value, filePath);
    monaco.typescript.typescriptDefaults.addExtraLib(value, filePath);
  }
}

/**
 * 添加沙箱全局预置类型定义 (如 ua, baseUrl, axios, cheerio, defineRule 各函数的入参与返回值智能提示)
 */
export const addGlobalSandboxTypes = (monaco: typeof import('monaco-editor')) => {
  const globalTypes = `
    declare global {
      /**
       * 当前规则的目标源站 BaseURL（站点根域名，如 https://example.com）
       */
      const baseUrl: string;

      /**
       * 移动端标准 User-Agent 字符串
       */
      const ua: string;

      /**
       * 全局内置 Axios HTTP 客户端实例
       */
      const axios: import('axios').AxiosStatic;

      /**
       * 全局内置 Cheerio HTML DOM 解析库
       */
      const cheerio: import('cheerio').CheerioAPI;

      /**
       * 基础媒体简项 (用于发现网格、搜索列表、相关推荐)
       */
      interface MediaItem {
        /** 详情页相对路径或完整 URL (核心跳转标识，必填) */
        url: string;
        /** 媒体主标题 (必填) */
        title: string;
        /** 高清封面海报图完整 URL (可选) */
        cover?: string;
        /** 状态角标 (如 "4K超清", "完结", "更新至第12集") */
        badge?: string;
        /** 副标题 / 简要描述 / 更新状态说明 */
        desc?: string;
        /** 上架时间 / 发布日期 */
        date?: string;
        /** 题材标签 (支持标签数组或空格隔开的字符串) */
        tags?: string[] | string;
        /** 附加扩展元数据字典 */
        extra?: Record<string, any>;
        [key: string]: any;
      }

      /**
       * 选集/章节条目模型
       */
      interface MediaEpisode {
        /** 目标播放页或章节阅读资源相对路径/完整 URL (必填) */
        url: string;
        /** 选集/章节标题 (如 "第01集", "第一章 破晓") */
        title?: string;
        /** 选集简要介绍 */
        desc?: string;
        /** 附加上下文 */
        extra?: Record<string, any>;
        [key: string]: any;
      }

      /**
       * 详情选集线路/分卷多分组模型
       */
      interface EpisodeGroup {
        /** 线路或分组名称 (如 "主线路", "备用4K", "第一卷") */
        name: string;
        /** 该分组下的选集列表 */
        items: Array<MediaEpisode | { title?: string; url: string } | string>;
        [key: string]: any;
      }

      /**
       * 发现/分类页标准返回数据结构 (discovery 返回值)
       */
      interface DiscoveryResult {
        /**
         * 分类页签列表（可选）
         * - 数组对象：[{ title: '分类标题', url: '/category-url' }]
         * - 纯字符串数组：['最新', '热门']
         */
        tabs?: Array<{ title: string; url: string }> | string[];
        /**
         * 媒体卡片列表 (必填/核心数据流)
         * 每个卡片包含 url、title、cover、badge、desc、tags 等字段
         */
        items: MediaItem[];
        /**
         * 是否还有下一页数据 (true 表示可继续翻页，false 表示已到最后一页)
         */
        hasMore?: boolean;
        /**
         * 当前返回的页码 (可选，从 1 开始计数)
         */
        page?: number;
        [key: string]: any;
      }

      /**
       * 搜索页标准返回数据结构 (search 返回值)
       */
      interface SearchResult {
        /**
         * 搜索结果媒体卡片列表 (必填/核心数据流)
         * 与 discovery 列表中的 MediaItem 完全复用
         */
        items: MediaItem[];
        /**
         * 是否还有下一页数据 (true 表示可继续翻页，false 表示已到最后一页)
         */
        hasMore?: boolean;
        /**
         * 搜索结果匹配到的作品总数 (可选，供分页计算或展示使用)
         */
        total?: number;
        [key: string]: any;
      }

      /**
       * 媒体详情页标准返回数据结构 (detail 返回值)
       */
      interface DetailResult {
        /**
         * 媒体主标题 (必填)
         */
        title: string;
        /**
         * 高清封面海报图完整 URL (可选)
         */
        cover?: string;
        /**
         * 剧情简介 / 正文描述 (可选，支持换行排版)
         */
        desc?: string;
        /**
         * 分类/题材标签数组 (可选，如 ['科幻', '动作', '热血'])
         */
        tags?: string[];
        /**
         * 作者 / 演员 / 导演等主创信息 (可选)
         */
        author?: string;
        /**
         * 作品评分 (可选，如 "9.2" 或 9.2)
         */
        rating?: string | number;
        /**
         * 核心子资源列表 (全类型大一统核心字段)
         * - 影视类型: 选集列表 [{ title: '第01集', url: '/play-1' }, { title: '第02集', url: '/play-2' }]
         * - 图集类型: 高清大图直链数组 ['https://...1.jpg', 'https://...2.jpg'] 或 [{ url: '...' }]
         * - 小说类型: 章节列表 [{ title: '第1章', url: '/c-1' }, { title: '第2章', url: '/c-2' }]
         * 注意：单一线路或同线路下的多清晰度变体请一律直接平铺在 items，严禁包裹伪 groups！
         */
        items?: Array<MediaEpisode | { title?: string; url: string } | string>;
        /**
         * 多播放线路 / 分卷多线路分组 (仅当存在多套互斥资源列表时使用，如线路一/线路二、小说多卷、漫画番外)
         */
        groups?: EpisodeGroup[];
        /**
         * 剧照 / 截帧 / 插图预览大图数组 (可选，用于详情页下方大图预览展厅)
         */
        previews?: string[];
        /**
         * 相关推荐 / 相似作品 / 关联条目列表 (可选，用于详情页底部猜你喜欢)
         */
        related?: MediaItem[];
        /**
         * 视频播放直链 (MP4 / M3U8)，若详情页直接提取出了播放直链可填此字段，客户端将跳过 parse 阶段直接起播
         */
        playUrl?: string;
        /**
         * 小说/文章单篇完整正文，若为单篇小说直出可填此字段，客户端将跳过 parse 阶段直接进入阅读
         */
        content?: string;
        /**
         * 播放器或图片加载所需自定义请求头 (如 { Referer: 'https://...', 'User-Agent': '...' })
         */
        headers?: Record<string, string>;
        /**
         * 扩展元数据字典 (可选)
         */
        extra?: Record<string, any>;
        [key: string]: any;
      }

      /**
       * 直链嗅探与正文解析标准返回数据结构 (parse 返回值)
       */
      interface ParseResult {
        /**
         * 解析出的最终音视频播放直链 (MP4 / M3U8 等)，直接交付播放器播放
         */
        playUrl?: string;
        /**
         * 解析出的小说章节/长文章纯正文内容，直接交付小说阅读引擎渲染
         */
        content?: string;
        /**
         * 专用的防盗链请求头 (如 Referer, Cookie, User-Agent 等)
         */
        headers?: Record<string, string>;
        /**
         * 视频封装或流媒体格式 (可选，如 "m3u8", "mp4", "flv")
         */
        format?: string;
        /**
         * 附加元数据字典 (可选)
         */
        extra?: Record<string, any>;
        [key: string]: any;
      }

      /**
       * discovery 方法入参结构
       */
      interface DiscoveryParams {
        /** 当前选中的分类相对路径或标识（严格对应 tabs[i].url；冷启动未选中时默认为 ''） */
        tab?: string;
        /** 当前分页页码，从 1 开始计数 (默认为 1) */
        page?: number;
        /** 目标站点根域名 (如 https://example.com) */
        baseUrl?: string;
        [key: string]: any;
      }

      /**
       * search 方法入参结构
       */
      interface SearchParams {
        /** 用户检索词 (必填) */
        keyword: string;
        /** 分页页码 (默认为 1) */
        page?: number;
        /** 目标站点根域名 */
        baseUrl?: string;
        [key: string]: any;
      }

      /**
       * detail 方法入参结构
       */
      interface DetailParams {
        /** 媒体详情页相对路径或完整 URL */
        url: string;
        /** 从上一级卡片带来的预热上下文 (封面、标题等) */
        item?: Partial<MediaItem>;
        /** 目标站点根域名 */
        baseUrl?: string;
        [key: string]: any;
      }

      /**
       * parse 方法入参结构
       */
      interface ParseParams {
        /** 当前选中选集/章节的资源地址 */
        url: string;
        /** 选集所在线路/分组名称 (如 "默认线路", "4K极速") */
        groupName?: string;
        /** 目标站点根域名 */
        baseUrl?: string;
        [key: string]: any;
      }

      type MaybePromise<T> = T | Promise<T>;

      /**
       * 规则定义契约对象
       */
      interface RuleDefinition {
        /**
         * 1. 发现与分类列表
         * 触发时机：进入分类浏览、首屏信息流、切换分类标签页或下拉加载更多时触发。
         *
         * @param params 发现参数对象，包含当前选中分类标识 tab 与分页页码 page
         * @returns 返回包含 tabs（可选）、items（卡片列表）、hasMore（是否有下一页）的 DiscoveryResult 对象
         */
        discovery?: (params: DiscoveryParams) => MaybePromise<DiscoveryResult | MediaItem[]>;

        /**
         * 2. 全局搜索检索
         * 触发时机：用户在全局搜索框输入关键字并发起检索时触发。
         *
         * @param params 搜索参数对象，包含用户关键字 keyword 与分页页码 page
         * @returns 返回包含 items（搜索结果卡片列表）、hasMore、total 的 SearchResult 对象
         */
        search?: (params: SearchParams) => MaybePromise<SearchResult | MediaItem[]>;

        /**
         * 3. 媒体详情与子资源聚合
         * 触发时机：点击任意媒体卡片进入详情页时触发。
         *
         * @param params 详情参数对象，包含详情页地址 url 与预热条目 item
         * @returns 返回包含 title、cover、desc、tags、items（选集/章节/大图）、groups（多线路）、playUrl、content 等的 DetailResult 详情对象
         */
        detail?: (params: DetailParams) => MaybePromise<DetailResult>;

        /**
         * 4. 直链嗅探与正文解析
         * 触发时机：点击视频选集按钮播放、或点击小说章节阅读时，如果条目的 url 为页面跳转链接而非播放直链/正文时触发。
         *
         * @param params 解析参数对象，包含资源地址 url 与线路名称 groupName
         * @returns 返回包含 playUrl（音视频直链）、content（小说章节正文）、headers（防盗链请求头）等的 ParseResult 解析结果对象
         */
        parse?: (params: ParseParams) => MaybePromise<ParseResult>;

        [key: string]: any;
      }

      /**
       * 辅助函数：定义并导出 FluxForge 规范规则对象（提供完整的生命周期参数与返回值类型推导与智能提示）
       *
       * @example
       * export default defineRule({
       *   async discovery({ tab = '', page = 1 }) {
       *     return { tabs: [], items: [], hasMore: false };
       *   },
       *   async search({ keyword, page = 1 }) {
       *     return { items: [], hasMore: false };
       *   },
       *   async detail({ url, item }) {
       *     return { title: '', items: [] };
       *   },
       *   async parse({ url, groupName }) {
       *     return { playUrl: url };
       *   }
       * });
       */
      function defineRule(rule: RuleDefinition): RuleDefinition;
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