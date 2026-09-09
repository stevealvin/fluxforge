import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import axios from 'axios'
import type { MediaType } from '@/types/rule'
import { distillContentForAi } from '@/utils/htmlDistiller'

export interface AiProfile {
  id: string
  name: string
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

export interface SiteMetadataResult {
  name: string
  description: string
}

export interface ProcessRuleResult {
  code: string
  analysis: string
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

const PROFILES_STORAGE_KEY = 'fluxforge-ai-profiles'
const ACTIVE_PROFILE_ID_KEY = 'fluxforge-active-profile-id'

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
  // 🌟 多配置列表与当前激活生效 ID
  const profiles = ref<AiProfile[]>([])
  const activeProfileId = ref<string>('')

  // 当前激活生效的配置对象 (自动防空安全兜底)
  const activeProfile = computed<AiProfile>(() => {
    if (profiles.value.length === 0) {
      return {
        id: 'fallback',
        name: '默认配置',
        provider: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: '',
        model: 'gpt-4o-mini',
        temperature: 0.1
      }
    }
    const found = profiles.value.find((p) => p.id === activeProfileId.value)
    return found || profiles.value[0]
  })

  // 默认推荐配置工厂
  const createDefaultProfiles = (): AiProfile[] => [
    {
      id: 'profile_deepseek',
      name: 'DeepSeek 官方',
      provider: 'openai',
      baseUrl: 'https://api.deepseek.com',
      apiKey: '',
      model: 'deepseek-chat',
      temperature: 0.1
    },
    {
      id: 'profile_gemini',
      name: 'Google Gemini 2.0',
      provider: 'gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      apiKey: '',
      model: 'gemini-2.0-flash',
      temperature: 0.1
    },
    {
      id: 'profile_openai',
      name: 'OpenAI 兼容中转',
      provider: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'gpt-4o-mini',
      temperature: 0.1
    }
  ]

  // 持久化保存到 localStorage
  const persistProfiles = () => {
    try {
      localStorage.setItem(PROFILES_STORAGE_KEY, JSON.stringify(profiles.value))
      localStorage.setItem(ACTIVE_PROFILE_ID_KEY, activeProfileId.value)
    } catch (e) {
      console.error('持久化 AI 配置失败:', e)
    }
  }

  // 从 localStorage 加载配置并执行去重自愈
  const loadSettings = () => {
    try {
      const rawProfiles = localStorage.getItem(PROFILES_STORAGE_KEY)
      const rawActiveId = localStorage.getItem(ACTIVE_PROFILE_ID_KEY)
      if (rawProfiles) {
        const list = JSON.parse(rawProfiles)
        if (Array.isArray(list) && list.length > 0) {
          // 🌟 脏数据自愈：检查并消除可能存在的重复 ID
          const seenIds = new Set<string>()
          let hasDuplicateId = false
          for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p.id || seenIds.has(p.id)) {
              p.id = 'profile_' + Date.now() + '_' + i + '_' + Math.random().toString(36).substring(2, 7)
              hasDuplicateId = true
            }
            seenIds.add(p.id)
          }

          profiles.value = list
          activeProfileId.value = rawActiveId && list.some((p: any) => p.id === rawActiveId) ? rawActiveId : list[0].id
          
          if (hasDuplicateId) {
            console.warn('检测到本地缓存存在重复或缺失的 Profile ID，已自动完成自愈重分配')
            persistProfiles()
          }
          return
        }
      }

      // 全新环境用户，初始化推荐预设配置列表
      profiles.value = createDefaultProfiles()
      activeProfileId.value = profiles.value[0].id
      persistProfiles()
    } catch (e) {
      console.warn('加载 AI 配置失败:', e)
    }
  }

  // 切换当前激活配置
  const setActiveProfile = (id: string) => {
    if (profiles.value.some((p) => p.id === id)) {
      activeProfileId.value = id
      persistProfiles()
    }
  }

  // 新增一套 API 配置
  const addProfile = (presetKey: string = 'openai', customName?: string): AiProfile => {
    const preset = AI_PRESETS[presetKey] || AI_PRESETS.openai
    const newProfile: AiProfile = {
      id: 'profile_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7),
      name: customName || `新配置 (${preset.label.split('/')[0].trim()})`,
      provider: presetKey,
      baseUrl: preset.baseUrl,
      apiKey: '',
      model: preset.defaultModel,
      temperature: 0.1
    }
    profiles.value.push(newProfile)
    persistProfiles()
    return newProfile
  }

  // 更新指定 API 配置 (严格防止外部 data 中意外携带的 id 覆盖已有主键)
  const updateProfile = (id: string, data: Partial<AiProfile>) => {
    const idx = profiles.value.findIndex((p) => p.id === id)
    if (idx !== -1) {
      const { id: _ignoredId, ...safeData } = data
      profiles.value[idx] = { ...profiles.value[idx], ...safeData }
      persistProfiles()
    }
  }

  // 克隆复制指定配置 (保证深拷贝并生成全新的唯一独立 ID)
  const duplicateProfile = (id: string): AiProfile | null => {
    const source = profiles.value.find((p) => p.id === id)
    if (!source) return null
    const newProfile: AiProfile = {
      id: 'profile_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8),
      name: `${source.name} (副本)`,
      provider: source.provider,
      baseUrl: source.baseUrl,
      apiKey: source.apiKey,
      model: source.model,
      temperature: source.temperature
    }
    profiles.value.push(newProfile)
    persistProfiles()
    return newProfile
  }

  // 删除指定 API 配置 (至少保留 1 个)
  const deleteProfile = (id: string): boolean => {
    if (profiles.value.length <= 1) return false
    const idx = profiles.value.findIndex((p) => p.id === id)
    if (idx !== -1) {
      profiles.value.splice(idx, 1)
      if (activeProfileId.value === id) {
        activeProfileId.value = profiles.value[0].id
      }
      persistProfiles()
      return true
    }
    return false
  }

  // 选择厂商预设 (用于快速填充指定 profile)
  const applyPreset = (key: string, targetId?: string) => {
    const preset = AI_PRESETS[key]
    if (preset) {
      const idToUpdate = targetId || activeProfileId.value
      updateProfile(idToUpdate, {
        provider: key,
        baseUrl: preset.baseUrl,
        model: preset.defaultModel
      })
    }
  }

  // 测试连接 (支持传入任意待测试的 Profile，未传则测试当前激活的 Profile)
  const testConnection = async (targetProfile?: Partial<AiProfile>): Promise<{ success: boolean; message: string }> => {
    const current = activeProfile.value
    const testBaseUrl = (targetProfile?.baseUrl ?? current.baseUrl).trim()
    const testProvider = targetProfile?.provider ?? current.provider
    const testApiKey = (targetProfile?.apiKey ?? current.apiKey).trim()
    const testModel = (targetProfile?.model ?? current.model).trim()

    if (!testBaseUrl) {
      return { success: false, message: '请先填写 API 接口地址 (Base URL)' }
    }

    const cleanBase = testBaseUrl.replace(/\/+$/, '')

    try {
      // 1. Google Gemini 协议
      if (testProvider === 'gemini') {
        const url = `${cleanBase}/models/${testModel}:generateContent`
        const headers: Record<string, string> = {
          'Content-Type': 'application/json'
        }
        if (testApiKey) {
          headers['x-goog-api-key'] = testApiKey
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
          return { success: true, message: `连接成功！Gemini [${testModel}] 响应正常。` }
        }
        return { success: false, message: `响应格式不符合预期: ${JSON.stringify(res.data)}` }
      }

      // 2. Anthropic Claude 协议
      if (testProvider === 'claude') {
        const url = `${cleanBase}/messages`
        const headers: Record<string, string> = {
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true'
        }
        if (testApiKey) {
          headers['x-api-key'] = testApiKey
        }

        const res = await axios.post(
          url,
          {
            model: testModel,
            max_tokens: 10,
            messages: [{ role: 'user', content: 'Ping' }]
          },
          { headers, timeout: 15000 }
        )

        if (res.status === 200 && res.data?.content?.length > 0) {
          return { success: true, message: `连接成功！Claude [${testModel}] 响应正常。` }
        }
        return { success: false, message: `响应格式不符合预期: ${JSON.stringify(res.data)}` }
      }

      // 3. 默认 OpenAI / 兼容协议
      const url = `${cleanBase}/chat/completions`
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      }
      if (testApiKey) {
        headers['Authorization'] = `Bearer ${testApiKey}`
      }

      const res = await axios.post(
        url,
        {
          model: testModel,
          messages: [{ role: 'user', content: 'Ping' }],
          max_tokens: 10
        },
        { headers, timeout: 15000 }
      )

      if (res.status === 200 && res.data?.choices?.length > 0) {
        return { success: true, message: `连接成功！OpenAI兼容模型 [${testModel}] 响应正常。` }
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
    const current = activeProfile.value
    if (!current.baseUrl) {
      throw new Error('请先在「系统设置」中配置 AI 模型的 API 接口地址')
    }

    const cleanBase = current.baseUrl.replace(/\/+$/, '')
    const currentProvider = current.provider
    const currentTemp = options.temperatureOverride ?? current.temperature
    let rawOutput = ''

    // 1. Google Gemini 协议
    if (currentProvider === 'gemini') {
      const url = `${cleanBase}/models/${current.model}:generateContent`
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (current.apiKey) headers['x-goog-api-key'] = current.apiKey

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
      if (current.apiKey) headers['x-api-key'] = current.apiKey

      const res = await axios.post(
        url,
        {
          model: current.model,
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
      if (current.apiKey) headers['Authorization'] = `Bearer ${current.apiKey}`

      const payload: Record<string, any> = {
        model: current.model,
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

    const systemPrompt = `你是一个资深的跨媒体聚合规则引擎架构师与多源 DSL 代码转译专家。
你的任务是：根据用户提供的任意形态输入（自然语言指令、数据样本、报错堆栈、或异构外部源规则/脚本），编写、转译或优化/修复符合 FluxForge 规范的 ESModule 规则代码。

【FluxForge 规则引擎标准规范】：
1. 模块导出标准：必须使用 export default defineRule({ ... })，严禁编写任何 import 语句。
2. 全局预置宿主环境（在各生命周期函数内直接访问）：
   - baseUrl: 当前源站根域名字符串（请求时直接使用 \`\${baseUrl}/list\`）
   - axios: 全局 HTTP 请求客户端实例
   - cheerio: 全局 HTML DOM 解析器
   - ua: 标准 User-Agent 字符串
   - defineRule: 全局规则定义辅助函数
3. 核心返回值契约（严格遵循标准属性名，所有链接统一为 url，严禁使用 key、href、path 或其他别名）：
   - MediaItem: { title: string, url: string, cover?: string, desc?: string, badge?: string }
    - 子资源条目(全类型统一): items?: Array<{ title?: string, url: string } | string>
    - 视频/音频直链: playUrl?: string
    - 小说正文文本: content?: string
    - 剧照/截图预览图流: previews?: string[]
    - 相关推荐条目: related?: MediaItem[]
4. 四大生命周期方法契约：
    - async discovery({ tab, page = 1 }): 返回 { tabs?: Array<{ title: string, url: string }>, items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
    - async search({ keyword, page = 1 }): 返回 { items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
    - async detail({ url, item }): 返回 { title: string, cover?: string, desc?: string, tags?: string[], author?: string, playUrl?: string, content?: string, items?: Array<{ title?: string, url: string } | string>, groups?: [{ name: string, items: [{ title: string, url: string }] }], previews?: string[], related?: MediaItem[] }
    - async parse({ url, groupName }): 返回 { playUrl?: string, content?: string, headers?: Record<string, string> }

【多模态输入自适应识别与处理引擎（核心泛化能力）】：
无论用户的输入呈现何种形式，你都必须自动识别其本质意图并自适应融会贯通：
1. 外部规则配置与异构脚本转译模式：
   - 当输入包含任何外部平台的规则配置（DSL）、网络爬虫脚本、HTTP 调用流或接口规范时，自动将其作为“业务逻辑蓝图”，将其请求逻辑与数据提取语法无缝转译为 FluxForge 标准代码：
   - 提取全局 baseUrl: 解析目标站点的 Host / 基础服务根域名；
   - 映射到 discovery: 将分类浏览、探索或首页规则转换为标准的分类列表与条目提取逻辑；
   - 映射到 search: 将搜索请求构造（支持 GET/POST、URL 占位符宏或参数结构）与搜索结果提取逻辑转为 search 实现；
   - 映射到 detail: 将详情提取与目录/章节/剧集列表规则转为标准书籍/影视详情以及分组结构 groups: [{ name: '默认分组', items: [{ title, url }] }]；
   - 映射到 parse: 将正文内容或媒体直链解析逻辑转为 parse 实现（小说文本提取并保留段落排版/清洗净化返回 { content }，媒体播放直链提取返回 { playUrl }）；
   - 语法转写: 将外部 DSL 选择器（CSS 选择器、属性读取宏、文本节点提取、XPath、正则提取等）平滑转写为基于 Cheerio 与原生 JavaScript 的健壮语法。
2. 数据样本驱动模式（HTML DOM 源码 / REST API JSON 响应）：
   - 若提供的是 HTML 数据：使用 const $ = cheerio.load(res.data) 进行 CSS 选择器提取；
   - 若提供的是 JSON 数据：直接按对象层级安全解构提取，无需使用 cheerio。
3. 异常诊断与修复模式（含有触发动作、报错堆栈或异常返回值）：
   - 以现有代码为基准，准确定位报错原因（如未考虑相对路径拼接、选择器失效、空指针异常、未处理防盗链 Referer 等），做最小化精准修复。
4. 自然语言与需求变更模式：
   - 理解用户的微调指示（如“封面高清化”、“选集正序”、“正文段落排版”、“过滤广告节点”等），针对性优化。

【代码生成原则】：
1. 现有代码优先：若提供了现有正常代码，保留其正常部分，仅对需要修改或修复的点进行局部精准演进；
2. 保持健壮性：请求前检查并补全相对路径为完整绝对 URL；对提取文本进行 .trim()；对可能为空的属性使用可选链；
3. 输出纯净：严禁编造不存在的模块导入，严禁外部未定义依赖。

【强制输出要求】：
必须严格返回合法的 JSON 格式（可包含在 \`\`\`json 块中），格式字段如下：
{
  "analysis": "设计思路、输入意图识别说明或修改要点（50~300字）",
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
      ? promptSections.join('\n\n') + '\n\n请针对上述信息进行分析处理，严格以 JSON 格式输出 analysis 与 code。'
      : '请编写一个标准的 FluxForge 规则脚本，严格以 JSON 格式输出包含 analysis 与 code。'

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

    const analysis = parsed?.analysis || (isFixMode ? '已完成规则代码针对性排查与修复。' : '已根据需求生成规则代码。')

    return {
      code,
      analysis,
      isFix: isFixMode
    }
  }

  /**
   * 🌟 独立的站点元数据提取器 (优先 DOM 本地秒级嗅探，可选轻量 AI 提炼)
   */
  const extractSiteMetadata = async (params: {
    url: string
    htmlContent?: string
    useAi?: boolean
  }): Promise<SiteMetadataResult> => {
    const html = params.htmlContent || ''

    // 1. 本地精准 DOM 嗅探 (0 Token 消耗，秒级完成)
    const localMeta = extractMetadataFallback(html, params.url)

    // 若无网页 HTML 内容，直接返回兜底结果，中断大模型盲猜
    if (!html.trim()) {
      return localMeta
    }

    // 如果未开启 AI 润色，或本地已经提取到站点名称，优先直接返回
    if (!params.useAi && localMeta.name) {
      return localMeta
    }

    // 2. 仅当配置了可用模型且需要 AI 提炼时，使用轻量微型 Prompt 提炼纯净名称与描述
    if (activeProfile.value.baseUrl && activeProfile.value.model && (params.useAi || !localMeta.name)) {
      try {
        const systemPrompt = `你是一个网站信息提炼专家。
你的任务是：根据提供的网页源码或 URL，提炼出该网站的纯净中文站点名称与网站简介。

【强制输出要求】：
必须严格返回合法的 JSON 格式（严禁包含代码或额外客套废话）：
{
  "name": "提炼出的纯净网站名称（如'樱花动漫'、'极光影视'、'笔趣阁'，2~10字，切勿包含推广后缀，严禁填写规则名称）",
  "description": "网站自身的官方简介或主要资源特色（50字以内，切勿描述规则本身）"
}`

        const userPrompt = `
目标网站 URL: ${params.url || '未提供'}
参考网页 HTML 片段:
\`\`\`html
${html.slice(0, 8000)}
\`\`\`

请提炼出该网站的纯净站点名称与描述，严格输出 JSON。`

        const rawOutput = await callLlm({
          systemPrompt,
          userPrompt,
          temperatureOverride: 0.1,
          jsonMode: true
        })

        let cleanJson = rawOutput.trim()
        if (cleanJson.includes('```json')) {
          cleanJson = cleanJson.replace(/^[\s\S]*?```json/i, '').replace(/```[\s\S]*$/, '').trim()
        } else if (cleanJson.includes('```')) {
          cleanJson = cleanJson.replace(/^[\s\S]*?```/i, '').replace(/```[\s\S]*$/, '').trim()
        }

        const parsed = JSON.parse(cleanJson)
        return {
          name: parsed?.name?.trim() || localMeta.name || '未知站点',
          description: parsed?.description?.trim() || localMeta.description || ''
        }
      } catch (e) {
        console.warn('AI 提取站点元数据失败，回退使用本地嗅探结果:', e)
      }
    }

    return {
      name: localMeta.name || '新源站',
      description: localMeta.description || ''
    }
  }

  // 动态通过接口从厂商拉取模型列表
  const fetchRemoteModels = async (overrideConfig?: Partial<AiProfile>): Promise<string[]> => {
    const current = activeProfile.value
    const currentProvider = overrideConfig?.provider || current.provider
    const currentBaseUrl = (overrideConfig?.baseUrl || current.baseUrl).replace(/\/+$/, '')
    const currentApiKey = overrideConfig?.apiKey !== undefined ? overrideConfig.apiKey : current.apiKey

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
    // 多配置核心状态与激活项
    profiles,
    activeProfileId,
    activeProfile,
    loadSettings,
    setActiveProfile,
    addProfile,
    updateProfile,
    duplicateProfile,
    deleteProfile,
    applyPreset,
    testConnection,
    callLlm,
    processRuleCode,
    extractSiteMetadata,
    fetchRemoteModels
  }
})

