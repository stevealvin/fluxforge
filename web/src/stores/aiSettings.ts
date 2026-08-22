import { defineStore } from 'pinia'
import { ref } from 'vue'
import axios from 'axios'
import type { MediaType } from '@/types/rule'

export interface AiConfig {
  provider: string
  baseUrl: string
  apiKey: string
  model: string
  temperature: number
}

const STORAGE_KEY = 'fluxforge-ai-settings'

export const AI_PRESETS: Record<string, { label: string; baseUrl: string; defaultModel: string; models: string[] }> = {
  deepseek: {
    label: 'DeepSeek 官方',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat', 'deepseek-reasoner']
  },
  openai: {
    label: 'OpenAI 官方',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    models: ['gpt-4o-mini', 'gpt-4o', 'o3-mini']
  },
  siliconflow: {
    label: '硅基流动 (SiliconFlow)',
    baseUrl: 'https://api.siliconflow.cn/v1',
    defaultModel: 'deepseek-ai/DeepSeek-V3',
    models: ['deepseek-ai/DeepSeek-V3', 'deepseek-ai/DeepSeek-R1', 'Qwen/Qwen2.5-Coder-32B-Instruct']
  },
  dashscope: {
    label: '阿里百炼 (DashScope)',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    models: ['qwen-plus', 'qwen-max', 'qwen-turbo']
  },
  ollama: {
    label: 'Ollama 本地模型',
    baseUrl: 'http://localhost:11434/v1',
    defaultModel: 'qwen2.5-coder',
    models: ['qwen2.5-coder', 'deepseek-r1:14b', 'llama3.2']
  },
  custom: {
    label: '自定义 OpenAI 兼容接口',
    baseUrl: '',
    defaultModel: '',
    models: []
  }
}

export const useAiSettingsStore = defineStore('aiSettings', () => {
  const provider = ref<string>('deepseek')
  const baseUrl = ref<string>('https://api.deepseek.com/v1')
  const apiKey = ref<string>('')
  const model = ref<string>('deepseek-chat')
  const temperature = ref<number>(0.1)

  // 从 localStorage 加载配置
  const loadSettings = () => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) {
        const saved = JSON.parse(raw)
        provider.value = saved.provider || 'deepseek'
        baseUrl.value = saved.baseUrl || 'https://api.deepseek.com/v1'
        apiKey.value = saved.apiKey || ''
        model.value = saved.model || 'deepseek-chat'
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

  // 选择预设厂商
  const applyPreset = (key: string) => {
    const preset = AI_PRESETS[key]
    if (preset) {
      provider.value = key
      baseUrl.value = preset.baseUrl
      model.value = preset.defaultModel
    }
  }

  // 测试连接
  const testConnection = async (): Promise<{ success: boolean; message: string }> => {
    if (!baseUrl.value) {
      return { success: false, message: '请先填写 API 接口地址 (Base URL)' }
    }

    try {
      const targetUrl = `${baseUrl.value.replace(/\/+$/, '')}/chat/completions`
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      }
      if (apiKey.value) {
        headers['Authorization'] = `Bearer ${apiKey.value}`
      }

      const res = await axios.post(
        targetUrl,
        {
          model: model.value,
          messages: [{ role: 'user', content: 'Ping' }],
          max_tokens: 10
        },
        { headers, timeout: 15000 }
      )

      if (res.status === 200 && res.data?.choices?.length > 0) {
        return { success: true, message: `连接成功！模型 [${model.value}] 响应正常。` }
      }
      return { success: false, message: `响应异常: ${JSON.stringify(res.data)}` }
    } catch (error: any) {
      const msg = error.response?.data?.error?.message || error.message || String(error)
      return { success: false, message: `连接测试失败: ${msg}` }
    }
  }

  // 生成规则代码
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

    const targetUrl = `${baseUrl.value.replace(/\/+$/, '')}/chat/completions`
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    }
    if (apiKey.value) {
      headers['Authorization'] = `Bearer ${apiKey.value}`
    }

    const res = await axios.post(
      targetUrl,
      {
        model: model.value,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: `请根据以上 HTML 片段生成完整的 ${params.mediaType} 解析规则代码。` }
        ],
        temperature: temperature.value
      },
      { headers, timeout: 60000 }
    )

    let code = res.data?.choices?.[0]?.message?.content || ''
    // 去除 markdown 标记
    code = code.replace(/^```(?:javascript|js)?\n/i, '').replace(/```$/i, '').trim()
    return code
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
    generateRuleCode
  }
})
