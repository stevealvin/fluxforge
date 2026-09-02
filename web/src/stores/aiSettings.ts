import { defineStore } from 'pinia'
import { ref } from 'vue'
import axios from 'axios'
import type { MediaType } from '@/types/rule'

export interface AiConfig {
  provider: 'openai' | 'gemini' | 'claude' | string
  baseUrl: string
  apiKey: string
  model: string
  temperature: number
}

export interface GeneratedRuleResult {
  code: string
  name?: string
  description?: string
  mediaType?: string
  baseUrl?: string
}

/**
 * 辅助提取器：从 HTML 或 JSON 源码中兜底提取站点名称与描述
 */
export const extractMetadataFallback = (rawContent: string, url: string = '') => {
  let name = ''
  let description = ''
  if (!rawContent) return { name, description }

  const trimmed = rawContent.trim()
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const data = JSON.parse(trimmed)
      name = data.name || data.title || data.sitename || data.site_name || data.app_name || ''
      description = data.description || data.desc || data.intro || ''
    } catch {}
  } else {
    try {
      const parser = new DOMParser()
      const doc = parser.parseFromString(rawContent, 'text/html')

      const titleEl = doc.querySelector('title')
      if (titleEl && titleEl.textContent) {
        let rawTitle = titleEl.textContent.trim()
        // 清理类似 "- 免费在线电影高清播放" 等冗余后缀
        rawTitle = rawTitle.replace(/\s*[-_–—|]\s*(免费|在线|高清|官方|首页|最新|播放|下载|聚合|APP|官网|主页).*$/i, '').trim()
        name = rawTitle.slice(0, 30)
      }

      const metaDesc = doc.querySelector('meta[name="description"], meta[property="og:description"]')
      if (metaDesc) {
        description = (metaDesc.getAttribute('content') || '').trim().slice(0, 150)
      }
    } catch {}
  }

  if (!name && url) {
    try {
      const u = new URL(url)
      const hostPart = u.hostname.replace(/^www\./, '').split('.')[0]
      if (hostPart) name = hostPart.toUpperCase() + ' 资源站'
    } catch {}
  }

  return { name, description }
}

const STORAGE_KEY = 'fluxforge-ai-settings'

/**
 * 仅保留 API 协议本质不同的主流厂商类型：
 * 1. OpenAI 兼容协议 (涵盖 OpenAI, DeepSeek, 阿里百炼, 硅基流动, Ollama, LM Studio, OneAPI 等)
 * 2. Google Gemini 协议 (Generative Language API)
 * 3. Anthropic Claude 协议 (Messages API)
 */
export const AI_PRESETS: Record<
  string,
  { label: string; desc: string; baseUrl: string; defaultModel: string; models: string[] }
> = {
  openai: {
    label: 'OpenAI / 兼容协议',
    desc: '标准 ChatCompletions 接口，支持 OpenAI、DeepSeek、阿里通义、硅基流动、Ollama、OneAPI 等',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    models: ['gpt-4o', 'gpt-4o-mini']
  },
  gemini: {
    label: 'Google Gemini 协议',
    desc: 'Google 原生 Generative Language REST 协议，支持 Gemini 1.5/2.0 全系列',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModel: 'gemini-2.0-flash',
    models: ['gemini-2.0-flash', 'gemini-1.5-pro']
  },
  claude: {
    label: 'Anthropic Claude 协议',
    desc: 'Anthropic 原生 Messages 接口，支持 Claude 3.5 Sonnet / Haiku / Opus',
    baseUrl: 'https://api.anthropic.com/v1',
    defaultModel: 'claude-3-5-sonnet-20241022',
    models: ['claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022']
  }
}

export const useAiSettingsStore = defineStore('aiSettings', () => {
  const provider = ref<string>('openai')
  const baseUrl = ref<string>('https://api.openai.com/v1')
  const apiKey = ref<string>('')
  const model = ref<string>('gpt-4o-mini')
  const temperature = ref<number>(0.1)

  // 从 localStorage 加载配置
  const loadSettings = () => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) {
        const saved = JSON.parse(raw)
        provider.value = saved.provider || 'openai'
        baseUrl.value = saved.baseUrl || 'https://api.openai.com/v1'
        apiKey.value = saved.apiKey || ''
        model.value = saved.model || 'gpt-4o-mini'
        temperature.value = saved.temperature ?? 0.1
      }
    } catch (e) {
      console.warn('加载 AI 配置失败:', e)
    }
  }

  // 保存配置
  const saveSettings = (config: Partial<AiConfig>) => {
    if (config.provider !== undefined) provider.value = config.provider
    if (config.baseUrl !== undefined) baseUrl.value = config.baseUrl
    if (config.apiKey !== undefined) apiKey.value = config.apiKey
    if (config.model !== undefined) model.value = config.model
    if (config.temperature !== undefined) temperature.value = config.temperature

    const data: AiConfig = {
      provider: provider.value,
      baseUrl: baseUrl.value,
      apiKey: apiKey.value,
      model: model.value,
      temperature: temperature.value
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
  }

  // 选择厂商预设
  const applyPreset = (key: string) => {
    const preset = AI_PRESETS[key]
    if (preset) {
      provider.value = key
      baseUrl.value = preset.baseUrl
      model.value = preset.defaultModel
    }
  }

  // 测试连接 (按不同 API 协议分发)
  const testConnection = async (): Promise<{ success: boolean; message: string }> => {
    if (!baseUrl.value) {
      return { success: false, message: '请先填写 API 接口地址 (Base URL)' }
    }

    const cleanBase = baseUrl.value.replace(/\/+$/, '')
    const currentProvider = provider.value

    try {
      // 1. Google Gemini 协议
      if (currentProvider === 'gemini') {
        const url = `${cleanBase}/models/${model.value}:generateContent`
        const headers: Record<string, string> = {
          'Content-Type': 'application/json'
        }
        if (apiKey.value) {
          headers['x-goog-api-key'] = apiKey.value
        }

        const res = await axios.post(
          url,
          {
            contents: [{ role: 'user', parts: [{ text: 'Ping' }] }],
            generationConfig: { maxOutputTokens: 10 }
          },
          { headers, timeout: 15000 }
        )

        if (res.status === 200 && res.data?.candidates?.length > 0) {
          return { success: true, message: `连接成功！Gemini [${model.value}] 响应正常。` }
        }
        return { success: false, message: `响应格式不符合预期: ${JSON.stringify(res.data)}` }
      }

      // 2. Anthropic Claude 协议
      if (currentProvider === 'claude') {
        const url = `${cleanBase}/messages`
        const headers: Record<string, string> = {
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true'
        }
        if (apiKey.value) {
          headers['x-api-key'] = apiKey.value
        }

        const res = await axios.post(
          url,
          {
            model: model.value,
            max_tokens: 10,
            messages: [{ role: 'user', content: 'Ping' }]
          },
          { headers, timeout: 15000 }
        )

        if (res.status === 200 && res.data?.content?.length > 0) {
          return { success: true, message: `连接成功！Claude [${model.value}] 响应正常。` }
        }
        return { success: false, message: `响应格式不符合预期: ${JSON.stringify(res.data)}` }
      }

      // 3. 默认 OpenAI / 兼容协议
      const url = `${cleanBase}/chat/completions`
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      }
      if (apiKey.value) {
        headers['Authorization'] = `Bearer ${apiKey.value}`
      }

      const res = await axios.post(
        url,
        {
          model: model.value,
          messages: [{ role: 'user', content: 'Ping' }],
          max_tokens: 10
        },
        { headers, timeout: 15000 }
      )

      if (res.status === 200 && res.data?.choices?.length > 0) {
        return { success: true, message: `连接成功！OpenAI兼容模型 [${model.value}] 响应正常。` }
      }
      return { success: false, message: `响应异常: ${JSON.stringify(res.data)}` }
    } catch (error: any) {
      const msg =
        error.response?.data?.error?.message ||
        error.response?.data?.message ||
        error.message ||
        String(error)
      return { success: false, message: `连接测试失败: ${msg}` }
    }
  }

  /**
   * 通用 LLM 调用底层分发器 (自动适配 OpenAI, Gemini, Claude 协议)
   */
  const callLlm = async (options: {
    systemPrompt: string
    userPrompt: string
    temperatureOverride?: number
    jsonMode?: boolean
  }): Promise<string> => {
    if (!baseUrl.value) {
      throw new Error('请先在「系统设置」中配置 AI 模型的 API 接口地址')
    }

    const cleanBase = baseUrl.value.replace(/\/+$/, '')
    const currentProvider = provider.value
    const currentTemp = options.temperatureOverride ?? temperature.value
    let rawOutput = ''

    // 1. Google Gemini 协议
    if (currentProvider === 'gemini') {
      const url = `${cleanBase}/models/${model.value}:generateContent`
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (apiKey.value) headers['x-goog-api-key'] = apiKey.value

      const generationConfig: Record<string, any> = { temperature: currentTemp }
      if (options.jsonMode) {
        generationConfig.responseMimeType = 'application/json'
      }

      const res = await axios.post(
        url,
        {
          systemInstruction: { parts: [{ text: options.systemPrompt }] },
          contents: [{ role: 'user', parts: [{ text: options.userPrompt }] }],
          generationConfig
        },
        { headers, timeout: 60000 }
      )
      rawOutput = res.data?.candidates?.[0]?.content?.parts?.[0]?.text || ''
    }
    // 2. Anthropic Claude 协议
    else if (currentProvider === 'claude') {
      const url = `${cleanBase}/messages`
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true'
      }
      if (apiKey.value) headers['x-api-key'] = apiKey.value

      const res = await axios.post(
        url,
        {
          model: model.value,
          max_tokens: 4096,
          system: options.systemPrompt,
          messages: [{ role: 'user', content: options.userPrompt }],
          temperature: currentTemp
        },
        { headers, timeout: 60000 }
      )
      rawOutput = res.data?.content?.[0]?.text || ''
    }
    // 3. OpenAI / 兼容协议 (DeepSeek, 阿里百炼, 硅基流动, Ollama 等)
    else {
      const url = `${cleanBase}/chat/completions`
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (apiKey.value) headers['Authorization'] = `Bearer ${apiKey.value}`

      const payload: Record<string, any> = {
        model: model.value,
        messages: [
          { role: 'system', content: options.systemPrompt },
          { role: 'user', content: options.userPrompt }
        ],
        temperature: currentTemp
      }

      if (options.jsonMode) {
        payload.response_format = { type: 'json_object' }
      }

      const res = await axios.post(url, payload, { headers, timeout: 60000 })
      rawOutput = res.data?.choices?.[0]?.message?.content || ''
    }

    return rawOutput
  }

  const generateRuleCode = async (params: {
    targetUrl: string
    mediaType: MediaType | string
    htmlSnippet?: string
    listHtml?: string
    detailUrl?: string
    detailHtml?: string
    parseUrl?: string
    parseHtml?: string
    requirement?: string
  }): Promise<GeneratedRuleResult> => {
    const listHtml = params.listHtml || params.htmlSnippet || ''
    const detailHtml = params.detailHtml || ''
    const parseHtml = params.parseHtml || ''

    const systemPrompt = `你是一个资深的 JavaScript 网页抓取与数据规则引擎专家。
你需要为 FluxForge 编写一个标准的 ESModule 解析规则脚本，并提炼该源站的名称与简介。

【FluxForge 规则引擎标准规范】：
1. 模块导出标准：使用 export default defineRule({ ... })
2. 全局预置环境（无需且切勿编写 import 语句）：
   - axios: 全局 HTTP 请求客户端实例
   - cheerio: 全局 HTML DOM 解析器
   - ua: 标准移动端/桌面端 User-Agent 字符串
   - baseUrl: 当前源站的根域名（字符串）
   - defineRule: 全局规则定义辅助函数
3. 数据源自适应处理规范：
   - 若提供的数据样本是 HTML：直接使用 const $ = cheerio.load(res.data) 提取选择器；
   - 若提供的数据样本是 JSON (REST API)：直接解析返回的 JSON 对象（如 const { data } = await axios.get(...)，遍历 data.list / data.items 等），无需使用 cheerio；
   - 若混合（如列表为 JSON 接口，详情为 HTML 页面）：按各自接口的数据类型分别处理。
4. 四大生命周期方法规范：
   - async discovery({ category, page = 1, baseUrl })：发现列表。返回 { categories?: string[], items: MediaItem[], hasMore?: boolean } 或直接返回 MediaItem[]
     其中 MediaItem: { key: string (唯一标识/详情URL相对或绝对路径), title: string, cover?: string, badge?: string, desc?: string }
   - async search({ keyword, page = 1, baseUrl })：搜索列表。返回 { items: MediaItem[], hasMore?: boolean } 或直接返回 MediaItem[]
   - async detail({ key, item, baseUrl })：媒体详情。返回扁平化结构：
     {
       title: string,
       cover?: string,
       desc?: string (支持换行符),
       tags?: string[],
       author?: string,
       playUrl?: string (如果是视频直链/M3U8/MP4，切记字段名为 playUrl),
       images?: string[] (如果是图片画廊/写真/漫画，大图URL数组),
       content?: string (如果是小说正文),
       groups?: [{ name: string, items: [{ key: string, title: string }] }],
       recommendations?: MediaItem[]
     }
   - async parse({ key, groupName, baseUrl })：动态解析播放直链或小说正文。返回 { playUrl?: string, content?: string }

【代码示例模版】：
export default defineRule({
  async discovery({ category, page = 1, baseUrl }) {
    const url = \`\${baseUrl}/list?page=\${page}\`
    const { data } = await axios.get(url, { headers: { 'User-Agent': ua } })
    const $ = cheerio.load(data)
    return $('.item').map((i, el) => ({
      key: $(el).find('a').attr('href'),
      title: $(el).find('.title').text().trim(),
      cover: $(el).find('img').attr('src')
    })).toArray()
  },
  async detail({ key, baseUrl }) {
    const url = key.startsWith('http') ? key : \`\${baseUrl}\${key}\`
    const { data } = await axios.get(url, { headers: { 'User-Agent': ua } })
    const $ = cheerio.load(data)
    return {
      title: $('h1').text().trim(),
      cover: $('.cover img').attr('src'),
      images: $('.photos img').map((i, el) => $(el).attr('src')).toArray()
    }
  }
})

【任务输入】：
- 目标源站 BaseURL: ${params.targetUrl || '无'}
- 期望媒体类型: ${params.mediaType}
${params.detailUrl ? `- 详情页/接口示例 URL: ${params.detailUrl}\n` : ''}
${params.parseUrl ? `- 播放/解析接口示例 URL: ${params.parseUrl}\n` : ''}
${listHtml ? `【1. 列表/发现数据样本 (HTML 或 JSON，供 discovery & search 参考)】:\n\`\`\`\n${listHtml.slice(0, 10000)}\n\`\`\`\n` : ''}
${detailHtml ? `【2. 详情/选集数据样本 (HTML 或 JSON，供 detail 参考)】:\n\`\`\`\n${detailHtml.slice(0, 10000)}\n\`\`\`\n` : ''}
${parseHtml ? `【3. 播放/解析数据样本 (HTML 或 JSON，供 parse 参考)】:\n\`\`\`\n${parseHtml.slice(0, 8000)}\n\`\`\`\n` : ''}
- 特殊需求说明: ${params.requirement || '请根据提供的数据结构精准提取标题、封面、链接、描述、选集等字段'}

【输出格式要求（极为重要）】：
必须返回合法的 JSON 格式（可包含在 \`\`\`json 块中），格式字段如下：
{
  "name": "从数据源/标题中智能提炼出的规则或源站简短名称 (例如: 极光影视、煎蛋美图、笔趣阁等，2~15字)",
  "description": "从网页/接口简介中提炼的特性或内容说明 (50字以内)",
  "mediaType": "${params.mediaType}",
  "code": "完整的 ESModule JavaScript 代码..."
}`

    const userPrompt = `请根据以上数据样本与结构信息，智能分析并输出包含 name, description, mediaType, code 的 JSON 数据。`
    const rawOutput = await callLlm({ systemPrompt, userPrompt })

    // 默认兜底信息
    const fallbackInfo = extractMetadataFallback(listHtml || detailHtml, params.targetUrl)
    let extractedName = fallbackInfo.name || ''
    let extractedDesc = fallbackInfo.description || ''
    let extractedType = params.mediaType
    let extractedCode = ''

    // 尝试解析 JSON 输出
    try {
      let jsonStr = rawOutput.trim()
      if (jsonStr.includes('```json')) {
        jsonStr = jsonStr.replace(/^[\s\S]*?```json/i, '').replace(/```[\s\S]*$/, '').trim()
      } else if (jsonStr.includes('```')) {
        jsonStr = jsonStr.replace(/^[\s\S]*?```(?:javascript|js)?/i, '').replace(/```[\s\S]*$/, '').trim()
      }

      if (jsonStr.startsWith('{') && jsonStr.endsWith('}')) {
        const parsed = JSON.parse(jsonStr)
        if (parsed.code) {
          extractedCode = parsed.code
          if (parsed.name) extractedName = parsed.name
          if (parsed.description) extractedDesc = parsed.description
          if (parsed.mediaType) extractedType = parsed.mediaType
        }
      }
    } catch {
      // JSON 解析失败则回退到代码匹配
    }

    // 如果未成功从 JSON 提取到代码，则将输出整体清洗后作为代码
    if (!extractedCode) {
      extractedCode = rawOutput.replace(/^```(?:javascript|js|json)?\n/i, '').replace(/```$/i, '').trim()
    }

    return {
      code: extractedCode,
      name: extractedName,
      description: extractedDesc,
      mediaType: extractedType,
      baseUrl: params.targetUrl
    }
  }

  // 🌟 AI 智能诊断与规则增量优化 (纯前端基于已有规则与测试结果精准修复)
  const debugAndOptimizeRule = async (params: {
    currentCode: string
    action: string
    actionParams: any
    rawResult: any
    errorMessage?: string
    targetUrl?: string
    targetHtml?: string
    userFeedback?: string
    mediaType?: MediaType | string
  }): Promise<{ fixedCode: string; analysis: string }> => {
    const systemPrompt = `你是一个资深的 JavaScript 网页抓取与规则引擎 Debug 专家。
你的任务是：基于用户已有的 FluxForge 规则代码、沙箱测试实际运行结果、报错信息以及页面真实 HTML，定位问题并精确修复代码。

【FluxForge 规则引擎核心规范】：
1. 模块导出标准：使用 export default defineRule({ ... })
2. 全局预置环境（无需编写 import 语句）：
   - axios, cheerio, ua, baseUrl, defineRule 均为全局变量
3. 各生命周期返回值规范：
   - discovery: { categories?: string[], items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
   - search: { items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
   - detail: { title: string, cover?: string, desc?: string, tags?: string[], author?: string, playUrl?: string, images?: string[], content?: string, groups?: [{ name: string, items: [{ key: string, title: string }] }], recommendations?: MediaItem[] }
   - parse: { playUrl?: string, content?: string }

【修复原则】：
1. 保持原代码整体结构与正常工作的提取逻辑不变，切勿破坏已成功的字段。
2. 针对解析失败、为空或报错的字段，深入分析提供的 HTML 结构，使用更健壮的 Cheerio 选择器、属性读取或正则提取方案。
3. 保证 URL 的正确补全（使用 new URL(href, baseUrl).href 或手动拼接）。
4. 代码中使用 export default defineRule({ ... })，切勿编写 import 语句。

【强制输出要求】：
必须严格返回合法 JSON 对象，严禁输出任何 JSON 之外的额外说明或客套话。
JSON 结构必须严格符合以下字段定义：
{
  "analysis": "针对问题原因、选择器失效点与修复思路的详细说明（字符串，支持 Markdown 换行）",
  "fixedCode": "修复后的完整 JavaScript 规则代码（字符串）"
}`

    const userPrompt = `
【现有规则代码】：
\`\`\`javascript
${params.currentCode}
\`\`\`

【当前测试动作】：${params.action}()
【测试传入参数】：${JSON.stringify(params.actionParams || {}, null, 2)}
【测试实际运行输出】：
\`\`\`json
${JSON.stringify(params.rawResult || {}, null, 2)}
\`\`\`
${params.errorMessage ? `【测试报错信息】:\n${params.errorMessage}\n` : ''}
${params.userFeedback ? `【用户反馈的问题/期望】:\n${params.userFeedback}\n` : ''}
${params.targetHtml ? `【相关目标网页 HTML 片段】:\n\`\`\`html\n${params.targetHtml.slice(0, 15000)}\n\`\`\`\n` : ''}

请针对上述问题进行深度排查修复，并严格以 JSON 格式输出 analysis 与 fixedCode。`

    const rawOutput = await callLlm({ systemPrompt, userPrompt, jsonMode: true })

    // 纯 JSON 逻辑：剥离可能存在的外层 \`\`\`json 标记后直接 parse
    const cleanJson = rawOutput.replace(/^\`\`\`(?:json)?\s*/i, '').replace(/\s*\`\`\`$/i, '').trim()

    let parsed: any = null
    try {
      parsed = JSON.parse(cleanJson)
    } catch {
      // 轻量容错：若字符串中含有未转义换行等不可见控制字符，做标准清洗
      const sanitized = cleanJson.replace(/[\u0000-\u001F\u007F-\u009F]/g, (c) => {
        return c === '\n' ? '\\n' : c === '\r' ? '\\r' : c === '\t' ? '\\t' : ''
      })
      try {
        parsed = JSON.parse(sanitized)
      } catch (err: any) {
        throw new Error(`AI 返回的内容无法解析为有效 JSON 格式: ${err.message}`)
      }
    }

    return {
      analysis: parsed?.analysis || '已完成规则代码排查与修复。',
      fixedCode: parsed?.fixedCode || params.currentCode
    }
  }

  const fetchRemoteModels = async (overrideConfig?: Partial<AiConfig>): Promise<string[]> => {
    const currentProvider = overrideConfig?.provider || provider.value
    const currentBaseUrl = (overrideConfig?.baseUrl || baseUrl.value).replace(/\/+$/, '')
    const currentApiKey = overrideConfig?.apiKey !== undefined ? overrideConfig.apiKey : apiKey.value

    if (!currentBaseUrl) {
      throw new Error('请先填写 API 接口地址 (Base URL)')
    }

    try {
      // 1. Google Gemini 协议
      if (currentProvider === 'gemini') {
        const url = `${currentBaseUrl}/models`
        const headers: Record<string, string> = { 'Content-Type': 'application/json' }
        if (currentApiKey) headers['x-goog-api-key'] = currentApiKey

        const res = await axios.get(url, { headers, timeout: 15000 })
        const list = res.data?.models || []
        const modelNames: string[] = list
          .map((m: any) => (m.name || '').replace(/^models\//, ''))
          .filter((name: string) => name && !name.includes('embedding') && !name.includes('aqa'))
        return modelNames.length > 0 ? modelNames : AI_PRESETS.gemini.models
      }

      // 2. Anthropic Claude 协议
      if (currentProvider === 'claude') {
        const url = `${currentBaseUrl}/models`
        const headers: Record<string, string> = {
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true'
        }
        if (currentApiKey) headers['x-api-key'] = currentApiKey

        const res = await axios.get(url, { headers, timeout: 15000 })
        const list = res.data?.data || []
        const modelNames: string[] = list.map((m: any) => m.id).filter(Boolean)
        return modelNames.length > 0 ? modelNames : AI_PRESETS.claude.models
      }

      // 3. OpenAI / 兼容协议
      const url = `${currentBaseUrl}/models`
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (currentApiKey) headers['Authorization'] = `Bearer ${currentApiKey}`

      const res = await axios.get(url, { headers, timeout: 15000 })
      const list = res.data?.data || (Array.isArray(res.data) ? res.data : [])
      const modelNames: string[] = list
        .map((m: any) => m.id || m.name || (typeof m === 'string' ? m : ''))
        .filter(Boolean)

      return modelNames.length > 0 ? modelNames : AI_PRESETS.openai.models
    } catch (error: any) {
      const msg =
        error.response?.data?.error?.message ||
        error.response?.data?.message ||
        error.message ||
        String(error)
      throw new Error(`获取模型列表失败: ${msg}`)
    }
  }

  loadSettings()

  return {
    provider,
    baseUrl,
    apiKey,
    model,
    temperature,
    loadSettings,
    saveSettings,
    applyPreset,
    testConnection,
    generateRuleCode,
    debugAndOptimizeRule,
    fetchRemoteModels
  }
})

