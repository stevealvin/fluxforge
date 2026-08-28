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

      const res = await axios.post(
        url,
        {
          systemInstruction: { parts: [{ text: options.systemPrompt }] },
          contents: [{ role: 'user', parts: [{ text: options.userPrompt }] }],
          generationConfig: { temperature: currentTemp }
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
    // 3. OpenAI / 兼容协议
    else {
      const url = `${cleanBase}/chat/completions`
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (apiKey.value) headers['Authorization'] = `Bearer ${apiKey.value}`

      const res = await axios.post(
        url,
        {
          model: model.value,
          messages: [
            { role: 'system', content: options.systemPrompt },
            { role: 'user', content: options.userPrompt }
          ],
          temperature: currentTemp
        },
        { headers, timeout: 60000 }
      )
      rawOutput = res.data?.choices?.[0]?.message?.content || ''
    }

    return rawOutput
  }

  // 生成规则代码 (支持多页面 HTML 采样：列表页 + 详情页 + 播放页)
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
  }): Promise<string> => {
    const listHtml = params.listHtml || params.htmlSnippet || ''
    const detailHtml = params.detailHtml || ''
    const parseHtml = params.parseHtml || ''

    const systemPrompt = `你是一个资深的 JavaScript 网页抓取与规则引擎专家。
你需要为 FluxForge 编写一个标准的 ESModule 解析规则脚本。

【FluxForge 规则引擎标准规范】：
1. 模块导出标准：使用 export default { ... }
2. 必须引入标准依赖：
   import axios from 'axios'
   import * as cheerio from 'cheerio'
3. 全局沙箱预置变量：
   - ua: 标准浏览器 User-Agent 字符串
4. 四大生命周期方法规范：
   - async discovery({ category, page = 1, baseUrl })：发现列表。返回 { categories: string[], items: MediaItem[], hasMore: boolean }
     其中 MediaItem: { key: string (唯一标识/详情URL相对或绝对路径), title: string, cover?: string, badge?: string, desc?: string }
   - async search({ keyword, page = 1, baseUrl })：搜索列表。返回 { items: MediaItem[], hasMore: boolean }
   - async detail({ key, item, baseUrl })：媒体详情。返回扁平化结构：
     {
       title: string,
       cover?: string,
       desc?: string (支持换行符),
       tags?: string[],
       author?: string,
       playUrl?: string (如果是视频直链/M3U8/MP4，切记字段名为 playUrl),
       images?: string[] (如果是图片画廊/剧照，大图URL数组),
       content?: string (如果是小说正文),
       groups?: [{ name: string, items: [{ key: string, title: string }] }],
       recommendations?: MediaItem[]
     }
   - async parse({ key, groupName, baseUrl })：动态解析播放直链或小说正文。返回 { playUrl?: string, content?: string }

【任务输入】：
- 目标源站 BaseURL: ${params.targetUrl || '无'}
- 媒体类型: ${params.mediaType}
${params.detailUrl ? `- 详情页示例 URL: ${params.detailUrl}\n` : ''}
${params.parseUrl ? `- 播放/解析页示例 URL: ${params.parseUrl}\n` : ''}
${listHtml ? `【1. 列表页/发现页 HTML 片段 (供 discovery & search 参考)】:\n\`\`\`html\n${listHtml.slice(0, 10000)}\n\`\`\`\n` : ''}
${detailHtml ? `【2. 详情页/选集页 HTML 片段 (供 detail 参考)】:\n\`\`\`html\n${detailHtml.slice(0, 10000)}\n\`\`\`\n` : ''}
${parseHtml ? `【3. 播放/解析页 HTML 片段 (供 parse 参考)】:\n\`\`\`html\n${parseHtml.slice(0, 8000)}\n\`\`\`\n` : ''}
- 特殊需求说明: ${params.requirement || '请根据 HTML 结构精准提取标题、封面、链接、描述、选集等字段'}

【输出要求】：
- 只输出标准、完整、无语法错误的 JavaScript 代码。
- 不要包含任何解释性文字或 Markdown 外部说明，直接输出代码内容（可以包裹在 \`\`\`javascript 内）。`

    const userPrompt = `请根据以上 HTML 结构与页面信息生成完整的 ${params.mediaType} 解析规则代码。`
    const rawOutput = await callLlm({ systemPrompt, userPrompt })

    // 去除 markdown 标记
    let code = rawOutput.replace(/^```(?:javascript|js)?\n/i, '').replace(/```$/i, '').trim()
    return code
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
你的任务是：基于用户当前已有的 FluxForge 规则代码、沙箱测试实际运行结果、报错信息以及页面真实 HTML，定位问题并精确修复代码。

【FluxForge 规则引擎核心规范】：
1. 模块导出标准：使用 export default { ... }
2. 依赖引入：
   import axios from 'axios'
   import * as cheerio from 'cheerio'
3. 全局沙箱预置变量：
   - ua: 标准浏览器 User-Agent 字符串
4. 各生命周期返回值规范：
   - discovery: { categories: string[], items: MediaItem[], hasMore: boolean }
     其中 MediaItem: { key: string, title: string, cover?: string, badge?: string, desc?: string }
   - search: { items: MediaItem[], hasMore: boolean }
   - detail: { title: string, cover?: string, desc?: string, tags?: string[], author?: string, playUrl?: string (视频直链), images?: string[], content?: string (小说正文), groups?: [{ name: string, items: [{ key: string, title: string }] }], recommendations?: MediaItem[] }
   - parse: { playUrl?: string, content?: string }

【修复原则】：
1. 保持原代码整体结构与正常工作的提取逻辑不变，切勿破坏已成功的字段。
2. 针对解析失败、为空或报错的字段，深入分析提供的 HTML 结构，使用更健壮的 Cheerio 选择器、属性读取或正则提取方案。
3. 保证 URL 的正确补全（使用 new URL(href, baseUrl).href 或手动拼接）。
4. 严格输出 JSON 格式（包含 analysis 与 fixedCode 两个字段），例如：
\`\`\`json
{
  "analysis": "1. 修复了 detail() 中 cover 封面选择器，原页面 class 是 .poster-img 而非 .pic；\\n2. 修复了 groups 选集列表提取，增加了线路支持...",
  "fixedCode": "import axios from 'axios'\\nimport * as cheerio from 'cheerio'\\n\\nexport default { ... }"
}
\`\`\``

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
${params.errorMessage ? `【测试报错信息】：\n${params.errorMessage}\n` : ''}
${params.userFeedback ? `【用户反馈的问题/期望】：\n${params.userFeedback}\n` : ''}
${params.targetHtml ? `【相关目标网页 HTML 片段】：\n\`\`\`html\n${params.targetHtml.slice(0, 15000)}\n\`\`\`\n` : ''}

请针对上述问题进行诊断，并输出修复后的完整代码与分析说明（以 JSON 结构输出）。`

    const rawOutput = await callLlm({ systemPrompt, userPrompt })

    let analysis = '已完成规则优化与修复'
    let fixedCode = params.currentCode

    try {
      const cleaned = rawOutput.replace(/^```(?:json)?\n/i, '').replace(/```$/i, '').trim()
      const parsed = JSON.parse(cleaned)
      if (parsed.fixedCode) {
        fixedCode = parsed.fixedCode
        analysis = parsed.analysis || analysis
      }
    } catch {
      // 容错处理：如果大模型直接返回了 JS 代码
      fixedCode = rawOutput.replace(/^```(?:javascript|js)?\n/i, '').replace(/```$/i, '').trim()
      analysis = '已自动修复选择器与解析逻辑'
    }

    return { fixedCode, analysis }
  }

  // 动态从 API 接口获取可用模型列表
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

