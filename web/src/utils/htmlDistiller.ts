/**
 * HTML & 数据样本智能语义蒸馏器 (HTML Semantic Distiller)
 * 
 * 核心目标：
 * 1. 消除 90%+ 的无用代码（head、style、svg、广告、埋点等），大幅减少 Token 占用；
 * 2. 精准保留分类导航骨架 (<nav>, <header>)，确保 AI 能提取 categories；
 * 3. 智能嗅探并放行包含真实数据的 <script>（如苹果CMS player_aaaa、m3u8、Next/Nuxt SSR 数据岛）；
 * 4. 列表页重复卡片自动折叠（同构节点只留前 2~3 个作为选择器样本）；
 * 5. JSON 接口大数组智能抽样。
 */

/**
 * 强力剔除 HTML 中的纯噪音标签：
 * - 移除所有的 link 标签（无论是 CSS 样式表、图标还是预加载，包括自闭合与闭合标签）
 * - 移除所有的外部 script 标签（带 src 的外部脚本不包含内联数据，占用海量 token）
 * - 移除所有的 style 标签（内联 CSS 规则）
 * - 移除所有的 svg 标签（复杂矢量图形与图标）
 * - 移除所有的 noscript、iframe 等无用多媒体与回退节点
 * - 移除所有的 HTML 注释
 */
export function stripHtmlNoise(html: string): string {
  if (!html) return ''
  return html
    // 1. 消除所有 HTML 注释
    .replace(/<!--[\s\S]*?-->/g, '')
    // 2. 消除所有 link 标签（自闭合与普通标签，无论在 head 还是 body）
    .replace(/<link\b[^>]*\/?>/gi, '')
    .replace(/<link\b[^>]*>[\s\S]*?<\/link>/gi, '')
    // 3. 消除所有带 src 属性的 script 标签（无论各种单双引号、无引号或自闭合格式）
    .replace(/<script\b[^>]*\bsrc\s*=\s*['"][^'"]*['"][^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<script\b[^>]*\bsrc\s*=[^>\s]+[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<script\b[^>]*\bsrc\s*=[^>]*\/?>/gi, '')
    // 4. 消除内联样式表与矢量图
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, '')
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, '')
    .replace(/<iframe\b[^>]*>[\s\S]*?<\/iframe>/gi, '')
}

/**
 * 递归截取 JSON 数据中的长数组，只保留前 maxItems 个元素作为结构样本
 */
export function compactJsonForAi(data: any, maxItems: number = 2): any {
  if (Array.isArray(data)) {
    const sliced = data.slice(0, maxItems).map(item => compactJsonForAi(item, maxItems))
    if (data.length > maxItems) {
      sliced.push(`<!-- 其余 ${data.length - maxItems} 项已省略，结构与上方一致 -->` as any)
    }
    return sliced
  }

  if (typeof data === 'object' && data !== null) {
    const result: Record<string, any> = {}
    for (const key of Object.keys(data)) {
      result[key] = compactJsonForAi(data[key], maxItems)
    }
    return result
  }

  return data
}

/**
 * 判断内联脚本是否包含播放直链、选集数据或 SSR 水合状态
 */
function isDataBearingScript(scriptContent: string, scriptType: string): boolean {
  if (!scriptContent || !scriptContent.trim()) return false

  // 1. JSON 数据岛与结构化数据
  if (scriptType === 'application/json' || scriptType === 'application/ld+json') {
    return true
  }

  // 2. 核心播放器直链与选集关键字
  const dataKeywords = [
    'player_aaaa',     // 苹果CMS MacCMS 经典播放器变量
    'player_data',     // 常见影视 CMS 播放变量
    'play_url',
    'playurl',
    'videourl',
    'video_url',
    'm3u8',
    '.mp4',
    'dplayer',
    'artplayer',
    '__NEXT_DATA__',   // Next.js SSR 数据岛
    '__NUXT__',        // Nuxt.js SSR 数据岛
    '__INITIAL_STATE__',
    'chapter_list',    // 小说目录列表
    'chapterlist',
    'photos:',         // 漫画/图片列表
    'image_list',
    'imagelist'
  ]

  const lower = scriptContent.toLowerCase()
  return dataKeywords.some(keyword => lower.includes(keyword))
}

/**
 * 针对列表页的大量同类重复子节点进行折叠，保留前 N 个作为 AI 推导样本
 * 默认提升至 6 条，既能完整覆盖常见状态变体（连载、完结、角标、无图等），又极大节省 Token
 */
function foldRepeatedElements(root: Element | null, maxSamples: number = 6) {
  if (!root) return

  const containers = Array.from(root.querySelectorAll('*'))
  containers.forEach(container => {
    // 若容器在父层折叠中已被移出文档树，跳过处理
    if (!container.isConnected && container !== root) return

    const children = Array.from(container.children)
    if (children.length <= maxSamples + 1) return

    // 按 tagName + 主 class 分组
    const groups = new Map<string, Element[]>()
    children.forEach(child => {
      const tag = child.tagName.toLowerCase()
      if (tag === 'script' || tag === 'style' || tag === 'link') return
      const className = typeof child.className === 'string' ? child.className : ''
      const firstClass = className.trim().split(/\s+/)[0] || ''
      const key = `${tag}:${firstClass}`
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key)!.push(child)
    })

    // 对命中同构特征且数量较多的分组进行折叠
    groups.forEach((items) => {
      if (items.length > maxSamples + 1) {
        const toRemove = items.slice(maxSamples)
        toRemove.forEach(el => el.remove())

        // 插入明确且不会被后置正则清除的 HTML 注释节点
        const comment = document.createComment(` 💡 [同类列表项已折叠 (已省略其余 ${items.length - maxSamples} 项)，DOM结构与上方一致] `)
        container.appendChild(comment)
      }
    })
  })
}

/**
 * 后置残留噪音清洗函数：仅剔除 link 与 script src，绝不误伤我们生成的折叠提示注释
 */
export function stripResidualNoise(html: string): string {
  if (!html) return ''
  return html
    .replace(/<link\b[^>]*\/?>/gi, '')
    .replace(/<link\b[^>]*>[\s\S]*?<\/link>/gi, '')
    .replace(/<script\b[^>]*\bsrc\s*=\s*['"][^'"]*['"][^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<script\b[^>]*\bsrc\s*=[^>\s]+[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<script\b[^>]*\bsrc\s*=[^>]*\/?>/gi, '')
}

/**
 * 核心方法：智能语义蒸馏 HTML / JSON 内容
 * 将原本数百 KB 的杂乱网页压缩提炼为高价值纯净 DOM，彻底过滤一切 link 和 script src
 */
export function distillContentForAi(rawContent: string, maxOutputLength: number = 30000): string {
  if (!rawContent || !rawContent.trim()) return ''

  const trimmed = rawContent.trim()

  // 1. 如果输入本身是 JSON（REST API 响应）
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const parsed = JSON.parse(trimmed)
      const compacted = compactJsonForAi(parsed, 3)
      return JSON.stringify(compacted, null, 2).slice(0, maxOutputLength)
    } catch {
      // JSON 解析失败则回退到普通文本处理
    }
  }

  // 2. 预清洗：第一道防线彻底消灭原始 HTML 中自带的 link、带 src 的 script、style、svg、垃圾注释等
  const preStripped = stripHtmlNoise(rawContent)

  // 3. 如果是 HTML 页面，使用原生 DOMParser 进行 DOM 级手术
  try {
    const parser = new DOMParser()
    const doc = parser.parseFromString(preStripped, 'text/html')

    // A. 提取并保留关键元数据（网页标题与有效描述）
    let metaHeader = ''
    const title = doc.querySelector('title')?.textContent?.trim() || ''
    const desc = doc.querySelector('meta[name="description"], meta[property="og:description"]')?.getAttribute('content')?.trim() || ''
    const ogVideo = doc.querySelector('meta[property="og:video"]')?.getAttribute('content')?.trim() || ''

    if (title || desc || ogVideo) {
      metaHeader = `<!-- 【源站元数据摘要】 -->\n`
      if (title) metaHeader += `<title>${title}</title>\n`
      if (desc) metaHeader += `<meta name="description" content="${desc}">\n`
      if (ogVideo) metaHeader += `<meta property="og:video" content="${ogVideo}">\n`
      metaHeader += `\n`
    }

    // 清理整个 head 避免残留无用 meta
    doc.head?.remove()

    // B. 二次确保彻底剔除无提取价值的纯噪音标签
    const pureNoiseSelectors = [
      'style',
      'svg',
      'link',
      'noscript',
      'iframe',
      'canvas',
      'audio'
    ]
    doc.querySelectorAll(pureNoiseSelectors.join(',')).forEach(el => el.remove())

    // C. 智能筛选 <script> 标签：严禁放行任何带 src 的外部脚本，仅放行命中核心数据特征的内联脚本
    const scripts = Array.from(doc.querySelectorAll('script'))
    scripts.forEach(script => {
      // 外部脚本一律剔除
      if (script.hasAttribute('src')) {
        script.remove()
        return
      }

      const scriptContent = script.textContent || ''
      const scriptType = (script.getAttribute('type') || '').toLowerCase().trim()

      if (!isDataBearingScript(scriptContent, scriptType)) {
        // 非数据脚本（统计、广告、UI框架等）全部剔除
        script.remove()
      } else {
        // 针对数据脚本：放宽至 20000 字符限制，避免破坏剧集选集与 JSON 数据岛结构
        if (scriptContent.length > 20000) {
          script.textContent = scriptContent.slice(0, 18000) + '\n// ... 超长非关键脚本尾部已截断 ...'
        }
      }
    })

    // D. 清洗所有 DOM 节点的内联样式与冗余属性
    const allElements = doc.querySelectorAll('*')
    allElements.forEach(el => {
      el.removeAttribute('style')

      const attrs = Array.from(el.attributes)
      for (const attr of attrs) {
        const name = attr.name.toLowerCase()
        if (name.startsWith('on') || name.startsWith('data-v-') || name.startsWith('data-track') || name.startsWith('data-spm')) {
          el.removeAttribute(attr.name)
        }
      }

      // 替换超长 Base64 图片
      const src = el.getAttribute('src') || ''
      if (src.startsWith('data:image/')) {
        el.setAttribute('src', '[BASE64_IMAGE]')
      }
      const dataSrc = el.getAttribute('data-src') || ''
      if (dataSrc.startsWith('data:image/')) {
        el.setAttribute('data-src', '[BASE64_IMAGE]')
      }
    })

    // E. 剔除常见的纯视觉装饰组件（严格保留 <nav>、<header> 等分类区域）
    const decorativeNoiseSelectors = [
      '.user-panel',
      '.user-info',
      '.login-modal',
      '.login-box',
      '.search-popup',
      '.ad-banner',
      '.advertisement',
      '.share-box',
      '.qrcode-box',
      '#footer-copy',
      '.copyright'
    ]
    doc.querySelectorAll(decorativeNoiseSelectors.join(',')).forEach(el => el.remove())

    // F. 对列表重复项进行安全折叠（默认保留前 6 条多样性样本）
    if (doc.body) {
      foldRepeatedElements(doc.body, 6)
    }

    // G. 提取序列化后的 HTML 并压缩多余空白
    const cleanedBody = (doc.body?.innerHTML || '')
      .replace(/(\r?\n\s*){2,}/g, '\n')
      .trim()

    // 拼装并进行后置清洗（使用 stripResidualNoise，确保残留 link/script-src 被消灭，同时保护折叠注释）
    let finalResult = `${metaHeader}${cleanedBody}`.trim()
    finalResult = stripResidualNoise(finalResult)

    return finalResult.slice(0, maxOutputLength)
  } catch {
    // 若 DOMParser 异常，使用预处理结果并再次兜底后置净化
    return stripResidualNoise(preStripped)
      .replace(/(\r?\n\s*){2,}/g, '\n')
      .trim()
      .slice(0, maxOutputLength)
  }
}
