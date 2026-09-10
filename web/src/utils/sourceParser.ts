/**
 * 外部源数据智能解析与单源转译 Prompt 构建器
 * 支持: 阅读 3.0 (Legado) 书源、TVBox 影视配置源、FluxForge 原生备份及通用 JSON 爬虫源
 */

export type SourceFormat = 'legado' | 'tvbox' | 'native' | 'generic'

export interface ParsedSourceItem {
  id: string
  name: string
  baseUrl: string
  format: SourceFormat
  formatLabel: string
  type: 'video' | 'novel' | 'picture'
  raw: any
  status: 'idle' | 'pending' | 'translating' | 'success' | 'failed' | 'native_ready'
  selected: boolean
  error?: string
  resultRule?: {
    name: string
    baseUrl: string
    type: 'video' | 'novel' | 'picture'
    code: string
    description?: string
    author?: string
  }
}

/**
 * 安全尝试 Base64 解密
 */
function tryDecodeBase64(str: string): string | null {
  const trimmed = str.trim()
  // 简易正则检测是否可能是 Base64 字符串
  if (!/^[A-Za-z0-9+/=\r\n]+$/.test(trimmed) || trimmed.length < 16) {
    return null
  }
  try {
    const decoded = atob(trimmed.replace(/\s+/g, ''))
    // 检查解码后是否包含 JSON 特征
    if (decoded.includes('{') || decoded.includes('[')) {
      return decoded
    }
  } catch {
    // 忽略异常
  }
  return null
}

/**
 * 从原始输入文本中解析出结构化条目列表 (纯本地 0 Token 计算)
 */
export function parseExternalSources(rawContent: string): ParsedSourceItem[] {
  if (!rawContent || !rawContent.trim()) {
    return []
  }

  let text = rawContent.trim()

  // 1. 如果是 Base64 编码的订阅内容，自动先行解密
  const b64Decoded = tryDecodeBase64(text)
  if (b64Decoded) {
    text = b64Decoded
  }

  let parsed: any
  try {
    parsed = JSON.parse(text)
  } catch {
    // 若直接解析失败，尝试清洗常见外部截断字符（如前置注释或尾部逗号）
    const cleaned = text
      .replace(/\/\*[\s\S]*?\*\/|([^\\:]|^)\/\/.*$/gm, '$1') // 去除注释
      .replace(/,\s*([\]}])/g, '$1') // 去除尾部多余逗号
    try {
      parsed = JSON.parse(cleaned)
    } catch (e: any) {
      throw new Error(`无法识别为有效的 JSON 数据: ${e.message}`)
    }
  }

  const items: ParsedSourceItem[] = []

  // 2. 判定格式并展开
  if (Array.isArray(parsed)) {
    parsed.forEach((item, index) => {
      const parsedItem = extractSingleItem(item, index)
      if (parsedItem) items.push(parsedItem)
    })
  } else if (typeof parsed === 'object' && parsed !== null) {
    // TVBox 格式检测: { sites: [...] }
    if (Array.isArray(parsed.sites)) {
      parsed.sites.forEach((site: any, index: number) => {
        const parsedItem = extractTvboxSite(site, index)
        if (parsedItem) items.push(parsedItem)
      })
    }
    // 常见包装层: { data: [...] } 或 { list: [...] } 或 { sources: [...] }
    else if (Array.isArray(parsed.data)) {
      parsed.data.forEach((item: any, index: number) => {
        const parsedItem = extractSingleItem(item, index)
        if (parsedItem) items.push(parsedItem)
      })
    } else if (Array.isArray(parsed.sources)) {
      parsed.sources.forEach((item: any, index: number) => {
        const parsedItem = extractSingleItem(item, index)
        if (parsedItem) items.push(parsedItem)
      })
    }
    // 单条独立对象
    else {
      const parsedItem = extractSingleItem(parsed, 0)
      if (parsedItem) items.push(parsedItem)
    }
  }

  return items
}

/**
 * 提取单个 TVBox 站点配置
 */
function extractTvboxSite(site: any, index: number): ParsedSourceItem | null {
  if (!site || typeof site !== 'object') return null
  const name = site.name || site.key || `TVBox影视源_${index + 1}`
  const api = site.api || ''

  return {
    id: `tvbox_${index}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    name,
    baseUrl: api.startsWith('http') ? api : '',
    format: 'tvbox',
    formatLabel: 'TVBox 影视配置',
    type: 'video',
    raw: site,
    status: 'idle',
    selected: true
  }
}

/**
 * 提取通用单条数据（自动识别 阅读3.0书源/订阅源、原生规则、海阔视界 或 通用源）
 */
function extractSingleItem(item: any, index: number): ParsedSourceItem | null {
  if (!item || typeof item !== 'object') return null

  // 1. 检查是否为 FluxForge 原生规则备份
  if (item.name && item.code && (typeof item.code === 'string') && item.code.includes('defineRule')) {
    return {
      id: `native_${index}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      name: item.name,
      baseUrl: item.baseUrl || '',
      format: 'native',
      formatLabel: 'FluxForge 原生规则',
      type: item.type === 'novel' ? 'novel' : item.type === 'picture' ? 'picture' : 'video',
      raw: item,
      status: 'native_ready', // 原生规则直接就绪，无需消耗 AI
      selected: true,
      resultRule: {
        name: item.name,
        baseUrl: item.baseUrl || '',
        type: item.type || 'video',
        code: item.code,
        description: item.description || '',
        author: item.author || ''
      }
    }
  }

  // 2. 检查是否为 阅读 3.0 / Legado 传统书源 (BookSource)
  if (item.bookSourceUrl || item.ruleSearch || item.ruleBookInfo || item.ruleToc || item.bookSourceName) {
    const name = item.bookSourceName || item.bookSourceGroup || `Legado书源_${index + 1}`
    const baseUrl = item.bookSourceUrl || ''
    const isPicture = item.bookSourceType === 2 || item.bookSourceType === '2' || (name.includes('漫') || name.includes('图'))
    const inferredType: 'video' | 'novel' | 'picture' = isPicture ? 'picture' : 'novel'

    return {
      id: `legado_${index}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      name,
      baseUrl,
      format: 'legado',
      formatLabel: '阅读 3.0 书源',
      type: inferredType,
      raw: item,
      status: 'idle',
      selected: true
    }
  }

  // 3. 检查是否为 阅读 3.0 / Legado 订阅源/发现源 (RssSource)
  // 特征: sourceName, sourceUrl, articleStyle, ruleArticles, loadWithBaseUrl, singleUrl 等
  if (
    item.sourceName !== undefined ||
    item.sourceUrl !== undefined ||
    item.articleStyle !== undefined ||
    item.ruleArticles !== undefined ||
    item.singleUrl !== undefined ||
    item.loadWithBaseUrl !== undefined
  ) {
    const name = item.sourceName || item.sourceGroup || `Legado订阅源_${index + 1}`
    const baseUrl = item.sourceUrl || ''
    
    // articleStyle: 0 默认小说/文章; 1 左右图文; 2 纯图片/漫画大图
    const isPicture =
      item.articleStyle === 2 ||
      (typeof name === 'string' && (name.includes('漫') || name.includes('图') || name.includes('壁纸')))
    const isVideo =
      typeof name === 'string' && (name.includes('影') || name.includes('剧') || name.includes('视') || name.includes('短剧'))
    
    const inferredType: 'video' | 'novel' | 'picture' = isVideo ? 'video' : isPicture ? 'picture' : 'novel'

    return {
      id: `legado_rss_${index}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      name,
      baseUrl,
      format: 'legado',
      formatLabel: '阅读 3.0 订阅源',
      type: inferredType,
      raw: item,
      status: 'idle',
      selected: true
    }
  }

  // 4. 检查是否为 海阔视界 / 嗅觉 / Hiker 规则
  if (item.find_rule || item.search_rule || item.col_type) {
    const name = item.title || item.name || `视界源_${index + 1}`
    const baseUrl = item.url || item.baseUrl || ''
    const inferredType: 'video' | 'novel' | 'picture' =
      name.includes('漫') || name.includes('图') ? 'picture' : 'video'

    return {
      id: `hiker_${index}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      name,
      baseUrl,
      format: 'generic',
      formatLabel: '海阔/视界源',
      type: inferredType,
      raw: item,
      status: 'idle',
      selected: true
    }
  }

  // 5. 通用外部爬虫源 (兜底，涵盖各类命名别名)
  const name =
    item.name ||
    item.sourceName ||
    item.bookSourceName ||
    item.title ||
    item.sitename ||
    item.site_name ||
    item.siteName ||
    item.appName ||
    item.app_name ||
    item.sourceGroup ||
    item.key ||
    `外部源_${index + 1}`

  const baseUrl =
    item.url ||
    item.sourceUrl ||
    item.bookSourceUrl ||
    item.baseUrl ||
    item.host ||
    item.api ||
    item.site ||
    ''

  const inferredType: 'video' | 'novel' | 'picture' =
    item.type === 'novel' ||
    (item.category && item.category.includes('书')) ||
    (typeof name === 'string' && (name.includes('书') || name.includes('小说') || name.includes('文')))
      ? 'novel'
      : item.type === 'picture' ||
        (item.category && item.category.includes('图')) ||
        (typeof name === 'string' && (name.includes('图') || name.includes('画') || name.includes('漫')))
        ? 'picture'
        : 'video'

  return {
    id: `generic_${index}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    name,
    baseUrl,
    format: 'generic',
    formatLabel: '通用配置/爬虫源',
    type: inferredType,
    raw: item,
    status: 'idle',
    selected: true
  }
}

/**
 * 针对单条源，构建精炼、高效的 AI 转译 Prompt
 */
export function buildSingleRuleTranslatePrompt(item: ParsedSourceItem) {
  const systemPrompt = `你是一个资深的跨媒体聚合规则引擎架构师与 DSL 编译器专家。
你的任务是将用户提供的【单个外部数据源配置/规则】精准编译转译为符合 FluxForge 规范的标准 ESModule 规则代码。

【FluxForge 规则引擎标准规范】：
1. 模块导出标准：必须使用 export default defineRule({ ... })，严禁编写任何 import 语句。
2. 全局预置环境（在各生命周期函数内直接使用）：
   - baseUrl: 当前源站根域名字符串（请求时直接使用 \`\${baseUrl}/path\`）
   - axios: 全局 HTTP 请求客户端实例
   - cheerio: 全局 HTML DOM 解析器
   - ua: 标准 User-Agent 字符串
   - defineRule: 全局规则定义辅助函数
3. 四大核心生命周期（必须根据源类型完整实现，特别是搜索、发现和详情）：
   - async discovery({ tab, page = 1 }): 返回 { items: MediaItem[], hasMore?: boolean }
   - async search({ keyword, page = 1 }): 返回 { items: MediaItem[], hasMore?: boolean }
   - async detail({ url, item }): 返回 { title, cover, desc, author, content, items: [{ title, url }], previews?: string[], related?: MediaItem[] }
   - async parse({ url, groupName }): 小说返回 { content: '章节正文...' }，视频返回 { playUrl: 'http...' }
4. 契约优先与彻底去兼容化（严格禁止防御性代码与无意义字段猜测）：
   - 跳转链接统一命名为 url（严禁使用 href, key, path, src 等别名）；
   - 描述简介统一命名为 desc（严禁使用 description 或 intro）；
   - 子资源/章节/选集列表统一命名为 items（严禁使用 list, episodes, chapters, images）；
   - 剧照预览统一命名为 previews，相关推荐统一命名为 related；
   - 补全绝对 URL 统一使用 Web 标准 API \`new URL(path, baseUrl).href\`，严禁编写多层三元字符串拼接；
   - 严禁在转译代码中写一堆 || 或 ?? 字段猜测判断，严格输出纯净的标准契约代码。

【强制输出要求】：
请严格输出合法的 JSON 格式（可包含在 \`\`\`json 块中），格式字段如下：
{
  "name": "清洗后的规则名称",
  "baseUrl": "目标站点根域名(如 https://example.com)",
  "type": "${item.type}",
  "description": "简要说明(如: 转译自阅读3.0书源)",
  "code": "完整可运行的 JavaScript 规则代码..."
}`

  const userPrompt = `请将以下【${item.formatLabel}】转译为 FluxForge 标准规则：
源名称: ${item.name}
目标媒体类型: ${item.type}
${item.baseUrl ? `参考 BaseURL: ${item.baseUrl}` : ''}

原始源配置数据 (JSON):
\`\`\`json
${JSON.stringify(item.raw, null, 2)}
\`\`\`

请确保代码健壮完整，将原始规则中定义的选择器、请求路径和列表结构正确转写为 Cheerio 或 JSON 提取逻辑。`

  return { systemPrompt, userPrompt }
}
