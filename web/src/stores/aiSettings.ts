import { defineStore } from 'pinia'
import { ref } from 'vue'
import axios from 'axios'
import type { MediaType } from '@/types/rule'
import { distillContentForAi } from '@/utils/htmlDistiller'

export interface AiConfig {
  provider: 'openai' | 'gemini' | 'claude' | string
  baseUrl: string
  apiKey: string
  model: string
  temperature: number
}

export interface ProcessRuleParams {
  code?: string
  targetUrl?: string
  mediaType?: MediaType | string

  prompt?: string
  errorMessage?: string
  action?: string
  actionParams?: any
  rawResult?: any

  contextData?: string
  listHtml?: string
  detailHtml?: string
  parseHtml?: string
}

export interface ProcessRuleResult {
  code: string
  analysis: string
  name?: string
  description?: string
  mediaType?: string
  isFix?: boolean
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

  /**
   * 🌟 AI 统一规则演进器 (涵盖全新生成、需求迭代与测试报错诊断修复)
   * - 彻底解耦抓取：HTML 样本完全可选；输入 API 说明、报错堆栈或纯自然语言即可驱动
   * - 统一生命周期规范与 JSON 契约：输出标准化 ESModule 脚本与诊断说明
   */
  const processRuleCode = async (params: ProcessRuleParams): Promise<ProcessRuleResult> => {
    const isFixMode = Boolean(params.code?.trim() || params.errorMessage)
    const mediaType = params.mediaType || 'video'
    const promptText = params.prompt || ''
    const listHtml = params.listHtml || ''
    const detailHtml = params.detailHtml || ''
    const parseHtml = params.parseHtml || ''

    const systemPrompt = `你是一个资深的 JavaScript 网页抓取与规则引擎专家。
你的任务是：根据用户的指令、现有规则代码、报错信息或数据样本，编写或优化/修复 FluxForge 规则脚本。

【FluxForge 规则引擎标准规范】：
1. 模块导出标准：使用 export default defineRule({ ... })，严禁编写任何 import 语句。
2. 全局预置环境（在各生命周期函数内直接访问）：
   - baseUrl: 当前源站根域名字符串（请求时直接使用 \`\${baseUrl}/list\`）
   - axios: 全局 HTTP 请求客户端实例
   - cheerio: 全局 HTML DOM 解析器
   - ua: 标准移动端/桌面端 User-Agent 字符串
   - defineRule: 全局规则定义辅助函数
3. 核心返回值契约（严格遵循标准属性名，所有链接统一为 url，严禁使用 key、href、path 或其他别名）：
   - MediaItem: { title: string, url: string, cover?: string, desc?: string, badge?: string }
   - 选集项: { title: string, url: string }
   - 视频直链: playUrl?: string
   - 图集大图数组: images?: string[]
   - 小说正文文本: content?: string
4. 四大生命周期方法：
   - async discovery({ category, page = 1 }): 返回 { categories?: Array<{ title: string, url: string }>, items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
   - async search({ keyword, page = 1 }): 返回 { items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
   - async detail({ url, item }): 返回 { title: string, cover?: string, desc?: string, tags?: string[], author?: string, playUrl?: string, images?: string[], content?: string, groups?: [{ name: string, items: [{ title: string, url: string }] }], recommendations?: MediaItem[] }
   - async parse({ url, groupName }): 返回 { playUrl?: string, content?: string, headers?: Record<string, string> }
5. 数据源自适应处理规范：
   - 若提供的数据样本是 HTML：使用 const $ = cheerio.load(res.data) 提取选择器；
   - 若提供的数据样本是 JSON (REST API)：直接解析返回的 JSON 对象，无需使用 cheerio。

【代码处理与修复原则】：
1. 若提供了现有规则代码：以现有代码为基准，保持未受影响且正常的提取逻辑不动，针对报错点或用户诉求进行局部精准修改/修复；
2. 若未提供代码（或为空骨架）：编写完整、语法规范的四大生命周期实现；
3. 保证 URL 的合法性与完整性，避免相对路径拼接错误。

【强制输出要求】：
必须严格返回合法的 JSON 格式（可包含在 \`\`\`json 块中），格式字段如下：
{
  "analysis": "设计思路、问题排查分析或修改要点说明（50~300字）",
  "name": "提炼出的源站/规则简短名称（可选，2~15字）",
  "description": "规则特性简介（可选，50字以内）",
  "mediaType": "${mediaType}",
  "code": "完整的 ESModule JavaScript 规则代码..."
}`

    // 动态组装用户消息（按需挂载插槽，解绑网页强依赖）
    const promptSections: string[] = []

    if (params.code && params.code.trim()) {
      promptSections.push(`【现有规则代码】：\n\`\`\`javascript\n${params.code.trim()}\n\`\`\``)
    }

    if (params.action || params.errorMessage) {
      let testSection = `【测试运行上下文】：`
      if (params.action) testSection += `\n- 触发动作: ${params.action}()`
      if (params.actionParams) testSection += `\n- 传入参数: ${JSON.stringify(params.actionParams)}`
      if (params.errorMessage) testSection += `\n- 报错堆栈: ${params.errorMessage}`
      if (params.rawResult) testSection += `\n- 实际返回值: ${JSON.stringify(params.rawResult).slice(0, 2000)}`
      promptSections.push(testSection)
    }

    if (promptText.trim()) {
      promptSections.push(`【用户诉求 / 修改要求】：\n${promptText.trim()}`)
    }

    if (params.targetUrl) {
      promptSections.push(`目标源站 BaseURL: ${params.targetUrl}`)
    }

    if (params.contextData && params.contextData.trim()) {
      const distilled = distillContentForAi(params.contextData, 30000)
      if (distilled) {
        promptSections.push(`【参考数据样本 (已智能脱水提纯)】：\n\`\`\`html\n${distilled}\n\`\`\``)
      }
    } else {
      if (listHtml) {
        const distilledList = distillContentForAi(listHtml, 30000)
        if (distilledList) {
          promptSections.push(`【列表页数据样本 (已智能脱水提纯)】：\n\`\`\`html\n${distilledList}\n\`\`\``)
        }
      }
      if (detailHtml) {
        const distilledDetail = distillContentForAi(detailHtml, 30000)
        if (distilledDetail) {
          promptSections.push(`【详情页数据样本 (已智能脱水提纯)】：\n\`\`\`html\n${distilledDetail}\n\`\`\``)
        }
      }
      if (parseHtml) {
        const distilledParse = distillContentForAi(parseHtml, 30000)
        if (distilledParse) {
          promptSections.push(`【解析页数据样本 (已智能脱水提纯)】：\n\`\`\`html\n${distilledParse}\n\`\`\``)
        }
      }
    }

    const userPrompt = promptSections.length > 0
      ? promptSections.join('\n\n') + '\n\n请针对上述信息进行分析处理，严格以 JSON 格式输出 analysis, name, description, mediaType, code。'
      : '请编写一个标准的 FluxForge 规则脚本，严格以 JSON 格式输出。'

    const rawOutput = await callLlm({ systemPrompt, userPrompt, jsonMode: true })

    // JSON 清洗与解析
    let cleanJson = rawOutput.trim()
    if (cleanJson.includes('```json')) {
      cleanJson = cleanJson.replace(/^[\s\S]*?```json/i, '').replace(/```[\s\S]*$/, '').trim()
    } else if (cleanJson.includes('```')) {
      cleanJson = cleanJson.replace(/^[\s\S]*?```(?:javascript|js)?/i, '').replace(/```[\s\S]*$/, '').trim()
    }

    let parsed: any = null
    try {
      parsed = JSON.parse(cleanJson)
    } catch {
      const sanitized = cleanJson.replace(/[\u0000-\u001F\u007F-\u009F]/g, (c) => {
        return c === '\n' ? '\\n' : c === '\r' ? '\\r' : c === '\t' ? '\\t' : ''
      })
      try {
        parsed = JSON.parse(sanitized)
      } catch {}
    }

    // 兜底提取代码
    let code = parsed?.code || ''
    if (!code) {
      code = rawOutput.replace(/^```(?:javascript|js|json)?\n/i, '').replace(/```$/i, '').trim()
    }

    const fallbackInfo = extractMetadataFallback(listHtml || detailHtml || params.contextData || '', params.targetUrl)
    const name = parsed?.name || fallbackInfo.name || ''
    const description = parsed?.description || fallbackInfo.description || ''
    const analysis = parsed?.analysis || (isFixMode ? '已完成规则代码针对性排查与修复。' : '已根据需求生成规则代码。')

    return {
      code,
      analysis,
      name,
      description,
      mediaType: parsed?.mediaType || mediaType,
      isFix: isFixMode
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
    processRuleCode,
    fetchRemoteModels
  }
})

