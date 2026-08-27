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

  // 生成规则代码 (按不同 API 协议分发)
  const generateRuleCode = async (params: {
    targetUrl: string
    mediaType: MediaType | string
    htmlSnippet: string
    requirement?: string
  }): Promise<string> => {
    if (!baseUrl.value) {
      throw new Error('请先在「系统设置」中配置 AI 模型的 API 接口地址')
    }

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
     其中 MediaItem: { key: string (唯一标识/详情URL), title: string, cover?: string, badge?: string, desc?: string }
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
- 网页 HTML 片段:
\`\`\`html
${params.htmlSnippet.slice(0, 15000)}
\`\`\`
- 特殊需求说明: ${params.requirement || '请根据 HTML 结构精准提取标题、封面、链接、描述等字段'}

【输出要求】：
- 只输出标准、完整、无语法错误的 JavaScript 代码。
- 不要包含任何解释性文字或 Markdown 外部说明，直接输出代码内容（可以包裹在 \`\`\`javascript 内）。`

    const userPrompt = `请根据以上 HTML 片段生成完整的 ${params.mediaType} 解析规则代码。`
    const cleanBase = baseUrl.value.replace(/\/+$/, '')
    const currentProvider = provider.value

    let rawOutput = ''

    // 1. Google Gemini 协议
    if (currentProvider === 'gemini') {
      const url = `${cleanBase}/models/${model.value}:generateContent`
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (apiKey.value) headers['x-goog-api-key'] = apiKey.value

      const res = await axios.post(
        url,
        {
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
          generationConfig: { temperature: temperature.value }
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
          system: systemPrompt,
          messages: [{ role: 'user', content: userPrompt }],
          temperature: temperature.value
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
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt }
          ],
          temperature: temperature.value
        },
        { headers, timeout: 60000 }
      )
      rawOutput = res.data?.choices?.[0]?.message?.content || ''
    }

    // 去除 markdown 标记
    let code = rawOutput.replace(/^```(?:javascript|js)?\n/i, '').replace(/```$/i, '').trim()
    return code
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
    fetchRemoteModels
  }
})

