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
 * 添加沙箱全局预置类型定义 (如 ua)
 */
export const addGlobalSandboxTypes = (monaco: typeof import('monaco-editor')) => {
  monaco.typescript.javascriptDefaults.addExtraLib(
    'declare const ua: string;',
    'node_modules/@types/fluxforge-globals/index.d.ts'
  )
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