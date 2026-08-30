<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import { useAiSettingsStore, type GeneratedRuleResult } from '@/stores/aiSettings'
import type { RuleAction, MediaType, MediaItem } from '@/types/rule'
import ArtPlayer from '@/components/ArtPlayer.vue'
import CodeEditor from '@/components/CodeEditor/index.vue'
import {
  Sparkles,
  Play,
  Layers,
  Compass,
  Search,
  FileText,
  Terminal,
  Clock,
  CheckCircle2,
  AlertCircle,
  Copy,
  ExternalLink,
  BookOpen,
  Image as ImageIcon,
  ArrowRight,
  Maximize2,
  Minimize2,
  RotateCcw,
  Bot,
  DownloadCloud,
  Wrench,
  Check,
  Globe,
  SlidersHorizontal,
  Code2,
  SearchCheck,
  Video,
  FileCode2
} from '@lucide/vue'

const props = defineProps<{
  show: boolean
  code: string
  baseUrl?: string
  ruleType?: MediaType | string
  ruleName?: string
  ruleDescription?: string
}>()

const emit = defineEmits<{
  (e: 'update:show', val: boolean): void
  (e: 'update:code', val: string): void
  (e: 'apply', payload: { code: string; baseUrl: string; type: string; name?: string; description?: string }): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

// 全局工作台模式: 'ai' (AI 智能生成) | 'test' (沙箱测试) | 'debug' (AI 诊断修复)
const currentTab = ref<'ai' | 'test' | 'debug'>('ai')
const isFullscreen = ref(false)

// ==========================================
// 1. AI 智能生成状态与逻辑 (AI Rule Generator)
// ==========================================
const aiTargetUrl = ref(props.baseUrl || '')
const aiDetailUrl = ref('')
const aiParseUrl = ref('')
const aiMediaType = ref<MediaType | string>(props.ruleType || 'video')
const aiRequirement = ref('')

const listHtml = ref('')
const detailHtml = ref('')
const parseHtml = ref('')
const fetchingList = ref(false)
const fetchingDetail = ref(false)
const fetchingParse = ref(false)
const autoSniffed = ref(false)

const generating = ref(false)
const generatedResult = ref<GeneratedRuleResult | null>(null)
const activeHtmlTab = ref<'list' | 'detail' | 'parse'>('list')

const mediaTypeOptions = [
  { label: '视频规则 (video)', value: 'video' },
  { label: '图片规则 (picture)', value: 'picture' },
  { label: '小说规则 (novel)', value: 'novel' }
]

// 智能嗅探详情页链接
const sniffDetailUrl = (rawContent: string, base: string): string => {
  if (!rawContent || !base) return ''
  const trimmed = rawContent.trim()

  // JSON 嗅探
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const data = JSON.parse(trimmed)
      let items: any[] = []
      if (Array.isArray(data)) {
        items = data
      } else if (typeof data === 'object' && data !== null) {
        const candidates = ['list', 'data', 'items', 'results', 'vod_list', 'books', 'rows', 'data_list', 'posts']
        for (const key of candidates) {
          if (Array.isArray(data[key]) && data[key].length > 0) {
            items = data[key]
            break
          }
        }
        if (items.length === 0 && data.data && typeof data.data === 'object') {
          for (const key of candidates) {
            if (Array.isArray(data.data[key]) && data.data[key].length > 0) {
              items = data.data[key]
              break
            }
          }
        }
      }

      if (items.length > 0 && items[0] && typeof items[0] === 'object') {
        const first = items[0]
        const urlKeys = ['url', 'link', 'detail_url', 'detailUrl', 'href', 'page_url', 'view_url']
        for (const k of urlKeys) {
          if (typeof first[k] === 'string' && first[k].trim()) {
            return new URL(first[k].trim(), base).href
          }
        }
        const idKeys = ['id', 'vod_id', 'vodId', 'book_id', 'bookId', 'media_id', 'mediaId', 'code', 'key']
        for (const k of idKeys) {
          if (first[k] !== undefined && first[k] !== null && String(first[k]).trim()) {
            const idVal = String(first[k]).trim()
            if (base.includes('?ac=list') || base.includes('?ac=videolist')) {
              return base.replace(/\?ac=(list|videolist)/, `?ac=detail&ids=${idVal}`)
            }
            if (base.includes('/list')) {
              return base.replace(/\/list.*$/, `/detail/${idVal}`)
            }
            const u = new URL(base)
            return `${u.origin}${u.pathname.replace(/\/+$/, '')}/${idVal}`
          }
        }
      }
    } catch {}
  }

  // HTML 嗅探
  try {
    const parser = new DOMParser()
    const doc = parser.parseFromString(rawContent, 'text/html')
    const ignoredSelectors = 'header, nav, footer, .menu, .navbar, .sidebar, #header, #footer, .header, .footer, .nav, .top-bar, .user-panel'
    doc.querySelectorAll(ignoredSelectors).forEach(el => el.remove())

    const links = Array.from(doc.querySelectorAll('a[href]'))
    const candidateLinks = links.filter(a => {
      const href = (a.getAttribute('href') || '').trim()
      if (!href || href === '#' || href === '/' || href.startsWith('javascript:') || href.startsWith('mailto:')) return false
      if (href.includes('login') || href.includes('register') || href.includes('about') || href.includes('contact') || href.includes('search')) return false
      if (href.match(/\.(jpg|jpeg|png|gif|webp|svg|css|js|ico|mp4)$/i)) return false
      return true
    })

    if (candidateLinks.length > 0) {
      let chosen = candidateLinks.find(a => a.querySelector('img') || (a.textContent || '').length >= 3) || candidateLinks[0]
      const rawHref = chosen.getAttribute('href') || ''
      return new URL(rawHref, base).href
    }
  } catch {}

  return ''
}

// 抓取通用数据
const fetchUrlData = async (url: string, type: 'list' | 'detail' | 'parse') => {
  if (!url) {
    message.warning('请输入待抓取的 URL 地址')
    return
  }

  if (type === 'list') fetchingList.value = true
  else if (type === 'detail') fetchingDetail.value = true
  else if (type === 'parse') fetchingParse.value = true

  try {
    const res: any = await http.post('/rules/fetch-page', { url })
    const rawText = (typeof res === 'string' ? res : res?.data || res?.html || res?.data?.data || '') as string
    if (rawText) {
      if (type === 'list') {
        listHtml.value = rawText
        activeHtmlTab.value = 'list'
        message.success(`列表页数据抓取成功 (${(rawText.length / 1024).toFixed(1)} KB)`)
        if (!aiDetailUrl.value) {
          const autoSniff = sniffDetailUrl(rawText, url)
          if (autoSniff) {
            aiDetailUrl.value = autoSniff
            autoSniffed.value = true
          }
        }
      } else if (type === 'detail') {
        detailHtml.value = rawText
        activeHtmlTab.value = 'detail'
        message.success(`详情页数据抓取成功 (${(rawText.length / 1024).toFixed(1)} KB)`)
      } else if (type === 'parse') {
        parseHtml.value = rawText
        activeHtmlTab.value = 'parse'
        message.success(`解析页数据抓取成功 (${(rawText.length / 1024).toFixed(1)} KB)`)
      }
    } else {
      message.error(res?.message || '抓取页面数据为空')
    }
  } catch (error: any) {
    message.error('抓取请求异常: ' + (error.response?.data?.message || error.message))
  } finally {
    if (type === 'list') fetchingList.value = false
    else if (type === 'detail') fetchingDetail.value = false
    else if (type === 'parse') fetchingParse.value = false
  }
}

// AI 一键生成规则并提取名称描述
const handleGenerateAiRule = async () => {
  if (!aiTargetUrl.value && !listHtml.value) {
    message.warning('请先输入源站 URL 或抓取列表数据样本')
    return
  }

  generating.value = true
  try {
    const result = await aiStore.generateRuleCode({
      targetUrl: aiTargetUrl.value,
      mediaType: aiMediaType.value,
      listHtml: listHtml.value,
      detailUrl: aiDetailUrl.value,
      detailHtml: detailHtml.value,
      parseUrl: aiParseUrl.value,
      parseHtml: parseHtml.value,
      requirement: aiRequirement.value
    })

    generatedResult.value = result
    message.success('AI 智能规则生成成功！已提炼源站名称与描述')
  } catch (error: any) {
    message.error('AI 规则生成失败: ' + error.message)
  } finally {
    generating.value = false
  }
}

// 应用生成的规则到父页面
const applyGeneratedRule = (andTest = false) => {
  if (!generatedResult.value?.code) {
    message.warning('尚无已生成的规则代码')
    return
  }

  emit('apply', {
    code: generatedResult.value.code,
    baseUrl: generatedResult.value.baseUrl || aiTargetUrl.value,
    type: (generatedResult.value.mediaType || aiMediaType.value) as string,
    name: generatedResult.value.name,
    description: generatedResult.value.description
  })

  emit('update:code', generatedResult.value.code)
  message.success('已成功将 AI 规则与元数据填充至表单与编辑器！')

  if (andTest) {
    currentTab.value = 'test'
    activeAction.value = 'discovery'
    setTimeout(() => {
      executeAction('discovery')
    }, 150)
  }
}

// ==========================================
// 2. 沙箱测试运行状态与逻辑 (Sandbox Runner)
// ==========================================
const activeAction = ref<RuleAction>('discovery')
const viewMode = ref<'visual' | 'json'>('visual')

const paramsDiscovery = ref({ category: '', page: 1 })
const paramsSearch = ref({ keyword: '测试', page: 1 })
const paramsDetail = ref({ key: '', item: null as Partial<MediaItem> | null })
const paramsParse = ref({ key: '', groupName: '默认线路' })

const running = ref(false)
const rawResult = ref<any>(null)
const executionTimeMs = ref<number | null>(null)
const statusCode = ref<number | null>(null)
const errorMessage = ref<string>('')

const actionTabs = [
  { label: 'discovery() 发现流', value: 'discovery' as RuleAction, icon: Compass },
  { label: 'search() 聚合搜索', value: 'search' as RuleAction, icon: Search },
  { label: 'detail() 媒体详情', value: 'detail' as RuleAction, icon: FileText },
  { label: 'parse() 动态解析', value: 'parse' as RuleAction, icon: Terminal }
]

const jsonOutput = computed(() => {
  if (errorMessage.value) return JSON.stringify({ error: errorMessage.value }, null, 2)
  if (!rawResult.value) return ''
  return JSON.stringify(rawResult.value, null, 2)
})

const executeAction = async (targetAction = activeAction.value) => {
  if (!props.code.trim()) {
    message.warning('请先在编辑器中编写规则代码')
    return
  }

  running.value = true
  errorMessage.value = ''
  rawResult.value = null
  statusCode.value = null
  executionTimeMs.value = null

  const startTime = performance.now()
  let requestParams: Record<string, any> = {
    baseUrl: props.baseUrl || aiTargetUrl.value || ''
  }

  if (targetAction === 'discovery') {
    requestParams = {
      ...requestParams,
      category: paramsDiscovery.value.category,
      page: paramsDiscovery.value.page || 1
    }
  } else if (targetAction === 'search') {
    requestParams = {
      ...requestParams,
      keyword: paramsSearch.value.keyword,
      page: paramsSearch.value.page || 1
    }
  } else if (targetAction === 'detail') {
    requestParams = {
      ...requestParams,
      key: paramsDetail.value.key,
      item: paramsDetail.value.item
    }
  } else if (targetAction === 'parse') {
    requestParams = {
      ...requestParams,
      key: paramsParse.value.key,
      groupName: paramsParse.value.groupName
    }
  }

  try {
    const res: any = await http.post('/rules/test-sandbox', {
      code: props.code,
      action: targetAction,
      params: requestParams
    })

    const duration = Math.round(performance.now() - startTime)
    executionTimeMs.value = duration

    const targetResult = res?.result !== undefined ? res.result : res
    if (targetResult && !targetResult.message) {
      rawResult.value = targetResult
      statusCode.value = 200
      message.success(`沙箱方法 ${targetAction}() 执行完成 (${duration} ms)`)

      // 联动参数传递
      if (targetAction === 'discovery' || targetAction === 'search') {
        const items = targetResult?.items
        if (Array.isArray(items) && items.length > 0) {
          const first = items[0]
          paramsDetail.value.key = first.key || first.url || ''
          paramsDetail.value.item = first
        }
      } else if (targetAction === 'detail') {
        if (targetResult?.groups?.length > 0 && targetResult.groups[0]?.items?.length > 0) {
          paramsParse.value.key = targetResult.groups[0].items[0].key
          paramsParse.value.groupName = targetResult.groups[0].name
        } else if (targetResult?.playUrl) {
          paramsParse.value.key = targetResult.playUrl
        }
      }
    } else {
      statusCode.value = 500
      errorMessage.value = targetResult?.message || res?.message || '沙箱执行发生未捕获异常'
      message.error(`沙箱执行失败: ${errorMessage.value}`)
    }
  } catch (error: any) {
    executionTimeMs.value = Math.round(performance.now() - startTime)
    statusCode.value = 500
    errorMessage.value = error.response?.data?.message || error.message || '网络或沙箱连接异常'
    message.error(`沙箱异常: ${errorMessage.value}`)
  } finally {
    running.value = false
  }
}

// 快速运行整个生命周期
const runAllLifecycles = async () => {
  activeAction.value = 'discovery'
  await executeAction('discovery')
  if (paramsDetail.value.key) {
    activeAction.value = 'detail'
    await executeAction('detail')
    if (paramsParse.value.key) {
      activeAction.value = 'parse'
      await executeAction('parse')
    }
  }
}

// ==========================================
// 3. AI 智能诊断与差量修复 (AI Diagnostic)
// ==========================================
const debugUserFeedback = ref('')
const debugTargetUrl = ref('')
const debugTargetHtml = ref('')
const fetchingDebugHtml = ref(false)
const debugging = ref(false)
const debugAnalysis = ref('')
const fixedCode = ref('')

const quickProblemTags = [
  '封面 cover 未能解析',
  '选集列表 groups 提取为空',
  '正文 content 提取为空',
  '播放直链 playUrl 未解析',
  '列表 items 数据为空',
  '简介 desc 中有多余广告标签'
]

const startDiagnosticFromTest = () => {
  currentTab.value = 'debug'
  if (errorMessage.value) {
    debugUserFeedback.value = `测试 ${activeAction.value}() 时报错: ${errorMessage.value}`
  } else if (!rawResult.value || (rawResult.value.items && rawResult.value.items.length === 0)) {
    debugUserFeedback.value = `测试 ${activeAction.value}() 返回的数据为空`
  }
}

const handleStartDebugging = async () => {
  debugging.value = true
  debugAnalysis.value = ''
  fixedCode.value = ''

  try {
    const result = await aiStore.debugAndOptimizeRule({
      currentCode: props.code,
      action: activeAction.value,
      actionParams: {
        discovery: paramsDiscovery.value,
        search: paramsSearch.value,
        detail: paramsDetail.value,
        parse: paramsParse.value
      }[activeAction.value],
      rawResult: rawResult.value,
      errorMessage: errorMessage.value,
      targetUrl: debugTargetUrl.value || props.baseUrl || aiTargetUrl.value,
      targetHtml: debugTargetHtml.value || listHtml.value,
      userFeedback: debugUserFeedback.value,
      mediaType: props.ruleType || aiMediaType.value
    })

    debugAnalysis.value = result.analysis
    fixedCode.value = result.fixedCode
    message.success('AI 规则诊断修复完成！请确认右侧修复代码')
  } catch (error: any) {
    message.error('AI 诊断失败: ' + error.message)
  } finally {
    debugging.value = false
  }
}

const applyFixedCode = () => {
  if (!fixedCode.value) return
  emit('update:code', fixedCode.value)
  message.success('已应用修复后的代码到编辑器')
  currentTab.value = 'test'
  executeAction(activeAction.value)
}

// 监听默认属性同步
watch(
  () => props.baseUrl,
  (val) => {
    if (val && !aiTargetUrl.value) aiTargetUrl.value = val
  }
)
watch(
  () => props.ruleType,
  (val) => {
    if (val) aiMediaType.value = val
  }
)
</script>

<template>
  <n-modal
    :show="props.show"
    :mask-closable="true"
    preset="card"
    :class="[
      '!rounded-2xl glass-panel !p-0 overflow-hidden shadow-2xl transition-all duration-300 border border-emerald-100/60 dark:border-white/10 flex flex-col',
      isFullscreen ? '!w-[99vw] !h-[98vh] !max-w-none !m-2' : '!w-[94vw] !max-w-[1440px] !h-[88vh]'
    ]"
    @update:show="(val: boolean) => emit('update:show', val)"
  >
    <template #header>
      <div class="flex items-center justify-between w-full pr-2">
        <!-- 标题与状态条 -->
        <div class="flex items-center gap-3">
          <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 text-white flex items-center justify-center shadow-md shadow-emerald-500/25 shrink-0">
            <Sparkles class="w-4 h-4" />
          </div>
          <div>
            <div class="flex items-center gap-2">
              <span class="text-sm sm:text-base font-black text-zinc-900 dark:text-white">
                规则智能调试工作台 (Rule Studio)
              </span>
              <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50 dark:border-emerald-800/40">
                ALL-IN-ONE
              </span>
            </div>
            <p class="text-[11px] text-zinc-400">
              数据采样 ➔ AI 智能生成与提取 ➔ 沙箱生命周期测试 ➔ AI 诊断修复
            </p>
          </div>
        </div>

        <!-- 工作台顶部三模态切换 Tab -->
        <div class="flex items-center gap-1.5 p-1 bg-zinc-100 dark:bg-white/[0.04] rounded-xl border border-emerald-100/40 dark:border-white/5">
          <button
            type="button"
            class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-lg transition-all"
            :class="currentTab === 'ai' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
            @click="currentTab = 'ai'"
          >
            <Sparkles class="w-3.5 h-3.5" />
            <span>AI 智能生成</span>
          </button>

          <button
            type="button"
            class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-lg transition-all"
            :class="currentTab === 'test' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
            @click="currentTab = 'test'"
          >
            <Play class="w-3.5 h-3.5 fill-current" />
            <span>沙箱测试运行</span>
          </button>

          <button
            type="button"
            class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-lg transition-all"
            :class="currentTab === 'debug' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
            @click="currentTab = 'debug'"
          >
            <Wrench class="w-3.5 h-3.5" />
            <span>AI 诊断修复</span>
          </button>
        </div>

        <!-- 窗口动作 (全屏切换，关闭由 n-modal 自带 close 按钮负责) -->
        <div class="flex items-center gap-1">
          <n-button
            quaternary
            circle
            size="small"
            class="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
            :title="isFullscreen ? '还原窗口' : '全屏窗口'"
            @click="isFullscreen = !isFullscreen"
          >
            <template #icon>
              <Minimize2 v-if="isFullscreen" class="w-4 h-4" />
              <Maximize2 v-else class="w-4 h-4" />
            </template>
          </n-button>
        </div>
      </div>
    </template>

    <!-- 工作台主体分栏内容 (根据当前 Tab 切换) -->
    <div class="flex-1 flex flex-col min-h-0 h-full p-4 sm:p-5 overflow-hidden">
      <!-- ========================================================================= -->
      <!-- TAB 1: 🚀 AI 智能生成与多源采样 (AI Rule Generator) -->
      <!-- ========================================================================= -->
      <div v-if="currentTab === 'ai'" class="flex-1 flex flex-col lg:flex-row gap-4 min-h-0 h-full overflow-hidden">
        <!-- 左栏：多源采样输入与生成配置 -->
        <div class="w-full lg:w-[440px] xl:w-[480px] flex flex-col gap-3.5 shrink-0 overflow-y-auto pr-1">
          <!-- 1. URL 抓取采样面板 -->
          <div class="glass-panel rounded-2xl p-4 space-y-3 border border-emerald-100/60 dark:border-white/5">
            <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
              <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
                <Globe class="w-3.5 h-3.5 text-emerald-500" />
                <span>目标源站与多级采样 URL</span>
              </div>
              <span class="text-[10px] text-zinc-400">支持 HTML 与 REST JSON</span>
            </div>

            <!-- 发现 / 列表页 URL -->
            <div class="space-y-1">
              <div class="flex items-center justify-between text-xs text-zinc-600 dark:text-zinc-400">
                <span class="font-medium">1. 发现 / 列表页 URL (discovery/search)</span>
                <span class="text-[10px] text-rose-500 font-mono">* 必填</span>
              </div>
              <div class="flex gap-1.5">
                <n-input
                  v-model:value="aiTargetUrl"
                  placeholder="https://example.com/vod/list 或 JSON API"
                  clearable
                  class="!rounded-xl text-xs font-mono flex-1"
                  @keyup.enter="fetchUrlData(aiTargetUrl, 'list')"
                />
                <n-button
                  size="small"
                  type="primary"
                  secondary
                  class="!rounded-xl !font-bold shrink-0"
                  :loading="fetchingList"
                  @click="fetchUrlData(aiTargetUrl, 'list')"
                >
                  抓取采样
                </n-button>
              </div>
            </div>

            <!-- 详情页示例 URL -->
            <div class="space-y-1">
              <div class="flex items-center justify-between text-xs text-zinc-600 dark:text-zinc-400">
                <div class="flex items-center gap-1">
                  <span class="font-medium">2. 详情 / 选集页 URL (detail)</span>
                  <span v-if="autoSniffed" class="px-1.5 py-0.2 text-[9px] rounded bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20 font-bold">
                    自动嗅探
                  </span>
                </div>
                <span class="text-[10px] text-zinc-400 font-mono">选填</span>
              </div>
              <div class="flex gap-1.5">
                <n-input
                  v-model:value="aiDetailUrl"
                  placeholder="https://example.com/detail/123"
                  clearable
                  class="!rounded-xl text-xs font-mono flex-1"
                  @keyup.enter="fetchUrlData(aiDetailUrl, 'detail')"
                />
                <n-button
                  size="small"
                  secondary
                  class="!rounded-xl shrink-0"
                  :loading="fetchingDetail"
                  @click="fetchUrlData(aiDetailUrl, 'detail')"
                >
                  抓取
                </n-button>
              </div>
            </div>

            <!-- 播放 / 解析页示例 URL -->
            <div class="space-y-1">
              <div class="flex items-center justify-between text-xs text-zinc-600 dark:text-zinc-400">
                <span class="font-medium">3. 播放 / 正文页 URL (parse)</span>
                <span class="text-[10px] text-zinc-400 font-mono">选填</span>
              </div>
              <div class="flex gap-1.5">
                <n-input
                  v-model:value="aiParseUrl"
                  placeholder="https://example.com/play/123/1"
                  clearable
                  class="!rounded-xl text-xs font-mono flex-1"
                  @keyup.enter="fetchUrlData(aiParseUrl, 'parse')"
                />
                <n-button
                  size="small"
                  secondary
                  class="!rounded-xl shrink-0"
                  :loading="fetchingParse"
                  @click="fetchUrlData(aiParseUrl, 'parse')"
                >
                  抓取
                </n-button>
              </div>
            </div>
          </div>

          <!-- 2. 生成选项与特性提示 -->
          <div class="glass-panel rounded-2xl p-4 space-y-3 border border-emerald-100/60 dark:border-white/5">
            <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
              <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
                <SlidersHorizontal class="w-3.5 h-3.5 text-teal-500" />
                <span>生成类型与定制提示</span>
              </div>
            </div>

            <div class="space-y-1">
              <label class="text-xs text-zinc-600 dark:text-zinc-400">规则媒体分类</label>
              <n-select
                v-model:value="aiMediaType"
                :options="mediaTypeOptions"
                class="!rounded-xl text-xs"
              />
            </div>

            <div class="space-y-1">
              <label class="text-xs text-zinc-600 dark:text-zinc-400">自定义解析需求 (可选)</label>
              <n-input
                v-model:value="aiRequirement"
                type="textarea"
                :autosize="{ minRows: 2, maxRows: 3 }"
                placeholder="如: 封面在 img.lazyload 的 data-src 属性中，视频直链需提取 m3u8 变量..."
                class="!rounded-xl text-xs"
              />
            </div>

            <!-- AI 核心生成触发按钮 -->
            <n-button
              type="primary"
              class="w-full !rounded-xl !font-black !py-4 shadow-lg shadow-emerald-500/25 !bg-gradient-to-r !from-emerald-600 !via-teal-500 !to-cyan-500"
              :loading="generating"
              @click="handleGenerateAiRule"
            >
              <template #icon>
                <Sparkles class="w-4 h-4 animate-pulse" />
              </template>
              <span>🚀 AI 智能生成规则 (自动提取名称 & 描述)</span>
            </n-button>
          </div>
        </div>

        <!-- 右栏：采样源码预览与 AI 生成结果回填面板 -->
        <div class="flex-1 flex flex-col min-w-0 glass-panel rounded-2xl overflow-hidden border border-emerald-100/60 dark:border-white/5 h-full">
          <!-- 切换：采样源码 vs 生成结果 -->
          <div class="px-4 py-2.5 border-b border-emerald-100/50 dark:border-white/5 flex flex-wrap items-center justify-between gap-2 bg-zinc-50/70 dark:bg-white/[0.02] shrink-0">
            <!-- 采样数据 Tab -->
            <div class="flex items-center gap-1.5">
              <span class="text-xs font-bold text-zinc-700 dark:text-zinc-300 mr-1">数据源视图:</span>
              <button
                type="button"
                class="px-2.5 py-1 text-xs rounded-lg font-mono transition-colors"
                :class="activeHtmlTab === 'list' ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
                @click="activeHtmlTab = 'list'"
              >
                列表样本 ({{ listHtml.length ? (listHtml.length / 1024).toFixed(1) + ' KB' : '空' }})
              </button>
              <button
                type="button"
                class="px-2.5 py-1 text-xs rounded-lg font-mono transition-colors"
                :class="activeHtmlTab === 'detail' ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
                @click="activeHtmlTab = 'detail'"
              >
                详情样本 ({{ detailHtml.length ? (detailHtml.length / 1024).toFixed(1) + ' KB' : '空' }})
              </button>
              <button
                type="button"
                class="px-2.5 py-1 text-xs rounded-lg font-mono transition-colors"
                :class="activeHtmlTab === 'parse' ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
                @click="activeHtmlTab = 'parse'"
              >
                解析样本 ({{ parseHtml.length ? (parseHtml.length / 1024).toFixed(1) + ' KB' : '空' }})
              </button>
            </div>

            <!-- 若已生成，展示回填操作按钮组 -->
            <div v-if="generatedResult?.code" class="flex items-center gap-2">
              <n-button
                size="small"
                secondary
                class="!rounded-xl !font-bold"
                @click="applyGeneratedRule(false)"
              >
                <template #icon>
                  <Check class="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400" />
                </template>
                <span>应用到表单与编辑器</span>
              </n-button>

              <n-button
                size="small"
                type="primary"
                class="!rounded-xl !font-bold shadow-md shadow-emerald-500/20"
                @click="applyGeneratedRule(true)"
              >
                <template #icon>
                  <Play class="w-3.5 h-3.5 fill-current" />
                </template>
                <span>应用并立即运行测试</span>
              </n-button>
            </div>
          </div>

          <!-- AI 生成的元数据卡片 (提取的名称与描述展示) -->
          <div v-if="generatedResult" class="p-3 bg-emerald-50/70 dark:bg-emerald-950/20 border-b border-emerald-100/50 dark:border-white/5 flex flex-wrap items-center justify-between gap-3 shrink-0">
            <div class="flex items-center gap-3 min-w-0">
              <div class="w-8 h-8 rounded-lg bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 flex items-center justify-center shrink-0">
                <Sparkles class="w-4 h-4" />
              </div>
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-xs font-bold text-zinc-900 dark:text-white">智能提取名称:</span>
                  <span class="text-xs font-black text-emerald-600 dark:text-emerald-400 font-mono">{{ generatedResult.name || '默认规则' }}</span>
                  <span class="px-1.5 py-0.2 text-[10px] font-bold rounded bg-emerald-100/80 dark:bg-white/10 text-emerald-700 dark:text-emerald-300">
                    {{ generatedResult.mediaType }}
                  </span>
                </div>
                <p class="text-[11px] text-zinc-500 dark:text-zinc-400 truncate max-w-xl">
                  {{ generatedResult.description || '暂无描述' }}
                </p>
              </div>
            </div>
          </div>

          <!-- 源码 / 生成代码高亮展示区 -->
          <div class="flex-1 min-h-0 w-full relative overflow-hidden">
            <!-- 优先展示生成的代码 -->
            <code-editor
              v-if="generatedResult?.code"
              v-model="generatedResult.code"
              model-id="ai_generated_code"
              height="100%"
              class="w-full h-full"
            />
            <!-- 未生成时展示采样抓取的源码片段 -->
            <code-editor
              v-else
              :model-value="activeHtmlTab === 'list' ? listHtml : activeHtmlTab === 'detail' ? detailHtml : parseHtml"
              model-id="ai_sample_source"
              height="100%"
              readonly
              class="w-full h-full"
            />
          </div>
        </div>
      </div>

      <!-- ========================================================================= -->
      <!-- TAB 2: ⚡ 沙箱测试与生命周期调试 (Sandbox Runner) -->
      <!-- ========================================================================= -->
      <div v-else-if="currentTab === 'test'" class="flex-1 flex flex-col lg:flex-row gap-4 min-h-0 h-full overflow-hidden">
        <!-- 左栏：生命周期方法切换与动态入参 -->
        <div class="w-full lg:w-[440px] xl:w-[480px] flex flex-col gap-3.5 shrink-0 overflow-y-auto pr-1">
          <!-- 1. 生命周期方法选择 -->
          <div class="glass-panel rounded-2xl p-4 space-y-3 border border-emerald-100/60 dark:border-white/5">
            <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
              <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
                <Compass class="w-3.5 h-3.5 text-emerald-500" />
                <span>沙箱测试方法</span>
              </div>
              <span class="text-[10px] text-zinc-400">生命周期</span>
            </div>

            <div class="grid grid-cols-2 gap-2">
              <button
                v-for="tab in actionTabs"
                :key="tab.value"
                type="button"
                class="flex items-center gap-2 p-2.5 rounded-xl border text-left text-xs font-bold transition-all"
                :class="activeAction === tab.value ? 'bg-emerald-500/10 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 border-emerald-500/40 shadow-xs' : 'border-zinc-200/60 dark:border-white/5 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-white/5'"
                @click="activeAction = tab.value"
              >
                <component :is="tab.icon" class="w-4 h-4 shrink-0" />
                <span class="truncate">{{ tab.label }}</span>
              </button>
            </div>
          </div>

          <!-- 2. 动态参数表单 -->
          <div class="glass-panel rounded-2xl p-4 space-y-3 border border-emerald-100/60 dark:border-white/5">
            <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
              <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
                <SlidersHorizontal class="w-3.5 h-3.5 text-teal-500" />
                <span>方法调用入参 (Params)</span>
              </div>
            </div>

            <!-- Discovery 入参 -->
            <div v-if="activeAction === 'discovery'" class="space-y-2.5">
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">分类 (category)</label>
                <n-input v-model:value="paramsDiscovery.category" placeholder="空表示默认分类" class="!rounded-xl text-xs" />
              </div>
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">页码 (page)</label>
                <n-input-number v-model:value="paramsDiscovery.page" :min="1" class="!rounded-xl text-xs w-full" />
              </div>
            </div>

            <!-- Search 入参 -->
            <div v-else-if="activeAction === 'search'" class="space-y-2.5">
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">关键词 (keyword)</label>
                <n-input v-model:value="paramsSearch.keyword" placeholder="搜索关键词" class="!rounded-xl text-xs" />
              </div>
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">页码 (page)</label>
                <n-input-number v-model:value="paramsSearch.page" :min="1" class="!rounded-xl text-xs w-full" />
              </div>
            </div>

            <!-- Detail 入参 -->
            <div v-else-if="activeAction === 'detail'" class="space-y-2.5">
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">项目标识/链接 (key)</label>
                <n-input v-model:value="paramsDetail.key" placeholder="/vod/detail/123.html" class="!rounded-xl text-xs font-mono" />
              </div>
            </div>

            <!-- Parse 入参 -->
            <div v-else-if="activeAction === 'parse'" class="space-y-2.5">
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">选集播放标识 (key)</label>
                <n-input v-model:value="paramsParse.key" placeholder="播放地址或分集ID" class="!rounded-xl text-xs font-mono" />
              </div>
              <div class="space-y-1">
                <label class="text-xs text-zinc-600 dark:text-zinc-400">线路名称 (groupName)</label>
                <n-input v-model:value="paramsParse.groupName" placeholder="默认线路" class="!rounded-xl text-xs" />
              </div>
            </div>

            <!-- 执行测试按钮组 -->
            <div class="pt-2 flex flex-col gap-2">
              <n-button
                type="primary"
                class="w-full !rounded-xl !font-bold !py-3.5 shadow-md shadow-emerald-500/20"
                :loading="running"
                @click="executeAction(activeAction)"
              >
                <template #icon>
                  <Play class="w-4 h-4 fill-current" />
                </template>
                <span>运行 {{ activeAction }}() 测试 (Ctrl+Enter)</span>
              </n-button>

              <n-button
                secondary
                class="w-full !rounded-xl !font-semibold text-xs"
                :disabled="running"
                @click="runAllLifecycles"
              >
                <span>⚡ 一键串联测试 (Discovery ➔ Detail ➔ Parse)</span>
              </n-button>
            </div>
          </div>
        </div>

        <!-- 右栏：测试结果渲染 (视觉卡片 + 播放器 + 结构化 JSON) -->
        <div class="flex-1 flex flex-col min-w-0 glass-panel rounded-2xl overflow-hidden border border-emerald-100/60 dark:border-white/5 h-full">
          <!-- 状态指标条与视图切换 -->
          <div class="px-4 py-2.5 border-b border-emerald-100/50 dark:border-white/5 flex flex-wrap items-center justify-between gap-2 bg-zinc-50/70 dark:bg-white/[0.02] shrink-0">
            <!-- 运行耗时与状态码 -->
            <div class="flex items-center gap-2">
              <span
                v-if="statusCode"
                class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-md"
                :class="statusCode === 200 ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20' : 'bg-rose-500/10 text-rose-600 border border-rose-500/20'"
              >
                HTTP {{ statusCode }}
              </span>

              <span v-if="executionTimeMs !== null" class="flex items-center gap-1 text-[11px] font-mono text-zinc-400">
                <Clock class="w-3.5 h-3.5" />
                <span>{{ executionTimeMs }} ms</span>
              </span>

              <span v-if="rawResult?.items" class="text-[11px] font-mono text-emerald-600 dark:text-emerald-400 font-bold">
                (已解析 {{ rawResult.items.length }} 项)
              </span>
            </div>

            <!-- 视图切换与诊断入口 -->
            <div class="flex items-center gap-2">
              <!-- 若发生错误，提供 AI 诊断入口 -->
              <n-button
                v-if="errorMessage || (rawResult && (!rawResult.items || rawResult.items.length === 0))"
                size="small"
                type="warning"
                secondary
                class="!rounded-xl !font-bold animate-bounce"
                @click="startDiagnosticFromTest"
              >
                <template #icon>
                  <Wrench class="w-3.5 h-3.5" />
                </template>
                <span>🩺 发起 AI 诊断修复</span>
              </n-button>

              <div class="flex items-center gap-1 p-0.5 bg-zinc-200/60 dark:bg-white/10 rounded-lg">
                <button
                  type="button"
                  class="px-2.5 py-1 text-xs rounded-md transition-all font-medium"
                  :class="viewMode === 'visual' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
                  @click="viewMode = 'visual'"
                >
                  视觉渲染
                </button>
                <button
                  type="button"
                  class="px-2.5 py-1 text-xs rounded-md transition-all font-medium font-mono"
                  :class="viewMode === 'json' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
                  @click="viewMode = 'json'"
                >
                  JSON 源码
                </button>
              </div>
            </div>
          </div>

          <!-- 主体呈现区 (Visual / JSON) -->
          <div class="flex-1 min-h-0 overflow-y-auto p-4 relative">
            <!-- 1. 错误提示卡片 -->
            <div v-if="errorMessage" class="p-4 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 space-y-2">
              <div class="flex items-center gap-2 font-bold text-sm">
                <AlertCircle class="w-4 h-4" />
                <span>沙箱执行报错</span>
              </div>
              <pre class="text-xs font-mono whitespace-pre-wrap">{{ errorMessage }}</pre>
            </div>

            <!-- 2. JSON 代码视图 -->
            <div v-else-if="viewMode === 'json'" class="h-full">
              <code-editor
                :model-value="jsonOutput"
                model-id="sandbox_json_output"
                height="100%"
                readonly
                class="w-full h-full"
              />
            </div>

            <!-- 3. 视觉化媒体渲染视图 -->
            <div v-else-if="rawResult" class="space-y-4">
              <!-- 发现/搜索 列表渲染 -->
              <div v-if="rawResult.items && Array.isArray(rawResult.items)" class="space-y-3">
                <div v-if="rawResult.categories?.length > 0" class="flex flex-wrap gap-1.5 pb-2 border-b border-emerald-100/40 dark:border-white/5">
                  <span
                    v-for="cat in rawResult.categories"
                    :key="cat"
                    class="px-2.5 py-1 text-xs rounded-lg bg-zinc-100 dark:bg-white/5 text-zinc-700 dark:text-zinc-300 font-medium"
                  >
                    {{ cat }}
                  </span>
                </div>

                <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
                  <div
                    v-for="(item, idx) in rawResult.items"
                    :key="idx"
                    class="p-2.5 rounded-xl border border-zinc-200/50 dark:border-white/5 bg-white/40 dark:bg-white/[0.02] space-y-1.5 group cursor-pointer hover:border-emerald-500/40 transition-colors"
                    @click="paramsDetail.key = item.key; paramsDetail.item = item; activeAction = 'detail'"
                  >
                    <div class="aspect-[3/4] rounded-lg bg-zinc-100 dark:bg-white/5 overflow-hidden relative">
                      <img
                        v-if="item.cover"
                        :src="item.cover"
                        class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                        loading="lazy"
                      />
                      <div v-else class="w-full h-full flex items-center justify-center text-zinc-400 text-xs">
                        暂无封面
                      </div>
                      <span v-if="item.badge" class="absolute top-1.5 right-1.5 px-1.5 py-0.5 text-[9px] font-bold rounded bg-black/60 text-white backdrop-blur-xs">
                        {{ item.badge }}
                      </span>
                    </div>
                    <div class="min-w-0">
                      <h4 class="text-xs font-bold text-zinc-900 dark:text-white truncate" :title="item.title">
                        {{ item.title }}
                      </h4>
                      <p v-if="item.desc" class="text-[10px] text-zinc-400 truncate">
                        {{ item.desc }}
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <!-- 详情页渲染 (封面、正文、剧集线路与播放器) -->
              <div v-else-if="activeAction === 'detail' || rawResult.title" class="space-y-4">
                <div class="flex flex-col sm:flex-row gap-4">
                  <img
                    v-if="rawResult.cover"
                    :src="rawResult.cover"
                    class="w-28 sm:w-36 aspect-[3/4] rounded-xl object-cover shadow-md shrink-0"
                  />
                  <div class="space-y-2 flex-1 min-w-0">
                    <h2 class="text-base font-black text-zinc-900 dark:text-white">
                      {{ rawResult.title }}
                    </h2>
                    <div v-if="rawResult.tags?.length > 0" class="flex flex-wrap gap-1">
                      <span v-for="tag in rawResult.tags" :key="tag" class="px-2 py-0.5 text-[10px] rounded bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 font-bold">
                        {{ tag }}
                      </span>
                    </div>
                    <p class="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed whitespace-pre-wrap">
                      {{ rawResult.desc || '暂无详细介绍' }}
                    </p>
                  </div>
                </div>

                <!-- 选集线路列表 -->
                <div v-if="rawResult.groups?.length > 0" class="space-y-3 pt-3 border-t border-emerald-100/40 dark:border-white/5">
                  <div v-for="(grp, gIdx) in rawResult.groups" :key="gIdx" class="space-y-2">
                    <h4 class="text-xs font-bold text-zinc-800 dark:text-zinc-200">
                      线路: {{ grp.name }}
                    </h4>
                    <div class="flex flex-wrap gap-1.5">
                      <button
                        v-for="(ep, eIdx) in grp.items"
                        :key="eIdx"
                        type="button"
                        class="px-2.5 py-1 text-xs rounded-lg border border-zinc-200/60 dark:border-white/5 bg-white/50 dark:bg-white/[0.02] hover:bg-emerald-500/15 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
                        @click="paramsParse.key = ep.key; paramsParse.groupName = grp.name; activeAction = 'parse'"
                      >
                        {{ ep.title }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- 播放 / 解析页渲染 -->
              <div v-else-if="activeAction === 'parse' || rawResult.playUrl || rawResult.content" class="space-y-4">
                <!-- 视频播放器 -->
                <div v-if="rawResult.playUrl" class="space-y-2">
                  <div class="flex items-center justify-between text-xs font-mono text-zinc-500">
                    <span>直链地址: {{ rawResult.playUrl }}</span>
                  </div>
                  <div class="w-full aspect-video rounded-2xl overflow-hidden bg-black shadow-lg">
                    <ArtPlayer :url="rawResult.playUrl" />
                  </div>
                </div>

                <!-- 小说正文 -->
                <div v-if="rawResult.content" class="p-4 rounded-xl bg-zinc-50 dark:bg-white/[0.02] border border-zinc-200/50 dark:border-white/5 leading-relaxed text-sm text-zinc-800 dark:text-zinc-200 whitespace-pre-wrap font-serif">
                  {{ rawResult.content }}
                </div>
              </div>
            </div>

            <!-- 空白状态 -->
            <div v-else class="h-full flex flex-col items-center justify-center text-center p-8 space-y-2 text-zinc-400">
              <Play class="w-8 h-8 opacity-40" />
              <span class="text-xs">点击左侧「运行测试」按钮启动沙箱</span>
            </div>
          </div>
        </div>
      </div>

      <!-- ========================================================================= -->
      <!-- TAB 3: 🩺 AI 智能诊断与差量修复 (AI Diagnostic) -->
      <!-- ========================================================================= -->
      <div v-else-if="currentTab === 'debug'" class="flex-1 flex flex-col lg:flex-row gap-4 min-h-0 h-full overflow-hidden">
        <!-- 左栏：诊断问题描述与触发 -->
        <div class="w-full lg:w-[440px] xl:w-[480px] flex flex-col gap-3.5 shrink-0 overflow-y-auto pr-1">
          <div class="glass-panel rounded-2xl p-4 space-y-3 border border-emerald-100/60 dark:border-white/5">
            <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
              <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
                <Wrench class="w-3.5 h-3.5 text-amber-500" />
                <span>AI 诊断与问题定位</span>
              </div>
            </div>

            <div class="space-y-1">
              <label class="text-xs text-zinc-600 dark:text-zinc-400">问题现象与修复需求</label>
              <n-input
                v-model:value="debugUserFeedback"
                type="textarea"
                :autosize="{ minRows: 3, maxRows: 4 }"
                placeholder="请描述遇到的问题，如：封面链接包含相对路径未能补全协议，或者正文提取为空..."
                class="!rounded-xl text-xs"
              />
            </div>

            <!-- 快捷标签 -->
            <div class="space-y-1.5">
              <span class="text-[11px] text-zinc-400">快捷问题标签:</span>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="tag in quickProblemTags"
                  :key="tag"
                  type="button"
                  class="px-2 py-1 text-[11px] rounded-lg bg-zinc-100 dark:bg-white/5 text-zinc-600 dark:text-zinc-400 hover:bg-emerald-500/10 hover:text-emerald-600 transition-colors"
                  @click="debugUserFeedback = tag"
                >
                  {{ tag }}
                </button>
              </div>
            </div>

            <n-button
              type="primary"
              class="w-full !rounded-xl !font-bold !py-3.5 shadow-md shadow-emerald-500/20"
              :loading="debugging"
              @click="handleStartDebugging"
            >
              <template #icon>
                <Sparkles class="w-4 h-4" />
              </template>
              <span>🩺 开始 AI 诊断并修复代码</span>
            </n-button>
          </div>
        </div>

        <!-- 右栏：AI 诊断分析报告与修复代码预览 -->
        <div class="flex-1 flex flex-col min-w-0 glass-panel rounded-2xl overflow-hidden border border-emerald-100/60 dark:border-white/5 h-full">
          <div class="px-4 py-2.5 border-b border-emerald-100/50 dark:border-white/5 flex items-center justify-between bg-zinc-50/70 dark:bg-white/[0.02] shrink-0">
            <span class="text-xs font-bold text-zinc-800 dark:text-zinc-200">
              修复代码对比与应用
            </span>
            <n-button
              v-if="fixedCode"
              size="small"
              type="primary"
              class="!rounded-xl !font-bold"
              @click="applyFixedCode"
            >
              <template #icon>
                <Check class="w-3.5 h-3.5" />
              </template>
              <span>一键应用修复代码到当前规则</span>
            </n-button>
          </div>

          <!-- 分析报告与代码编辑器 -->
          <div class="flex-1 flex flex-col min-h-0 overflow-hidden">
            <div v-if="debugAnalysis" class="p-3 bg-amber-500/10 border-b border-amber-500/20 text-xs text-amber-800 dark:text-amber-300 shrink-0 leading-relaxed">
              <strong>诊断分析:</strong> {{ debugAnalysis }}
            </div>

            <div class="flex-1 min-h-0 w-full relative overflow-hidden">
              <code-editor
                :model-value="fixedCode || props.code"
                model-id="diagnostic_fixed_code"
                height="100%"
                :readonly="!fixedCode"
                class="w-full h-full"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </n-modal>
</template>

<style scoped>
</style>
