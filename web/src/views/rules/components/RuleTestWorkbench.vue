<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import { useAiSettingsStore } from '@/stores/aiSettings'
import type { RuleAction, MediaType, MediaItem, MediaDetail } from '@/types/rule'
import ArtPlayer from '@/components/ArtPlayer.vue'
import CodeEditor from '@/components/CodeEditor/index.vue'
import {
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
  Sparkles,
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
  Check
} from '@lucide/vue'

const props = defineProps<{
  show: boolean
  code: string
  baseUrl?: string
  ruleType?: MediaType | string
  ruleName?: string
}>()

const emit = defineEmits<{
  (e: 'update:show', val: boolean): void
  (e: 'update:code', val: string): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

// 当前测试动作: discovery | search | detail | parse
const activeAction = ref<RuleAction>('discovery')
const viewMode = ref<'visual' | 'json'>('visual')

// 动态参数表单
const paramsDiscovery = ref({ category: '', page: 1 })
const paramsSearch = ref({ keyword: '测试', page: 1 })
const paramsDetail = ref({ key: '', item: null as Partial<MediaItem> | null })
const paramsParse = ref({ key: '', groupName: '默认线路' })

// 运行状态与指标
const running = ref(false)
const rawResult = ref<any>(null)
const executionTimeMs = ref<number | null>(null)
const statusCode = ref<number | null>(null)
const errorMessage = ref<string>('')
const isFullscreen = ref(false)

// 🌟 AI 智能诊断与代码修复状态
const showAiDebugModal = ref(false)
const debugUserFeedback = ref('')
const debugTargetUrl = ref('')
const debugTargetHtml = ref('')
const fetchingDebugHtml = ref(false)
const debugging = ref(false)
const debugAnalysis = ref('')
const fixedCode = ref('')

// 动作标签选项
const actionTabs = [
  { label: 'discovery() 发现流', value: 'discovery' as RuleAction, icon: Compass },
  { label: 'search() 聚合搜索', value: 'search' as RuleAction, icon: Search },
  { label: 'detail() 媒体详情', value: 'detail' as RuleAction, icon: FileText },
  { label: 'parse() 动态解析', value: 'parse' as RuleAction, icon: Terminal }
]

// 常用问题快捷标签
const quickProblemTags = [
  '封面 cover 未能解析',
  '选集列表 groups 提取为空',
  '正文 content 提取为空',
  '播放直链 playUrl 未解析',
  '列表 items 数据为空',
  '简介 desc 中有多余广告标签'
]

// 格式化输出 JSON
const jsonOutput = computed(() => {
  if (errorMessage.value) {
    return JSON.stringify({ error: errorMessage.value }, null, 2)
  }
  if (!rawResult.value) {
    return ''
  }
  return JSON.stringify(rawResult.value, null, 2)
})

// 执行测试沙箱
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

  // 构造对应的参数载荷
  let requestParams: Record<string, any> = {
    baseUrl: props.baseUrl || ''
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
    const res: any = await http.post('/rules/run', {
      code: props.code,
      action: targetAction,
      params: requestParams
    })

    const duration = Math.round(performance.now() - startTime)
    executionTimeMs.value = duration
    statusCode.value = 200
    rawResult.value = res?.result !== undefined ? res.result : res
  } catch (error: any) {
    const duration = Math.round(performance.now() - startTime)
    executionTimeMs.value = duration
    statusCode.value = error.response?.status || 500
    errorMessage.value = error.response?.data?.message || error.message || '执行异常'
  } finally {
    running.value = false
  }
}

// 联动流转 1: 从 discovery / search 结果一键流转测试 detail
const testItemDetail = (item: MediaItem) => {
  paramsDetail.value.key = item.key
  paramsDetail.value.item = item
  activeAction.value = 'detail'
  executeAction('detail')
}

// 联动流转 2: 从 detail 选集一键流转测试 parse
const testEpisodeParse = (epKey: string, groupName = '默认线路') => {
  paramsParse.value.key = epKey
  paramsParse.value.groupName = groupName
  activeAction.value = 'parse'
  executeAction('parse')
}

// 复制 JSON 结果
const copyJson = async () => {
  if (!jsonOutput.value) return
  if (navigator.clipboard) {
    await navigator.clipboard.writeText(jsonOutput.value)
    message.success('已复制 JSON 结果到剪贴板')
  }
}

// 🌟 打开 AI 智能诊断修复弹窗并自动装配上下文
const openAiDebugger = () => {
  if (!props.code.trim()) {
    message.warning('当前规则代码为空')
    return
  }

  // 智能推断当前测试页面的真实 URL
  let inferredUrl = props.baseUrl || ''
  if (activeAction.value === 'detail' && paramsDetail.value.key) {
    const key = paramsDetail.value.key
    if (key.startsWith('http')) {
      inferredUrl = key
    } else if (props.baseUrl) {
      try {
        inferredUrl = new URL(key, props.baseUrl).href
      } catch {
        inferredUrl = `${props.baseUrl.replace(/\/+$/, '')}/${key.replace(/^\/+/, '')}`
      }
    }
  } else if (activeAction.value === 'discovery' && props.baseUrl) {
    inferredUrl = props.baseUrl
  }

  debugTargetUrl.value = inferredUrl
  debugUserFeedback.value = errorMessage.value ? `运行时报错: ${errorMessage.value}` : ''
  debugAnalysis.value = ''
  fixedCode.value = ''
  showAiDebugModal.value = true

  // 若有推断出的 URL 且未拉取 HTML，则自动静默拉取目标网页源码
  if (inferredUrl && inferredUrl.startsWith('http') && !debugTargetHtml.value) {
    handleFetchDebugHtml()
  }
}

// 抓取诊断目标页面源码
const handleFetchDebugHtml = async () => {
  if (!debugTargetUrl.value.trim() || !debugTargetUrl.value.startsWith('http')) {
    message.warning('请先输入有效的目标网页 URL')
    return
  }
  fetchingDebugHtml.value = true
  try {
    const res: any = await http.post('/rules/fetch-html', {
      url: debugTargetUrl.value.trim()
    })
    if (res?.html) {
      debugTargetHtml.value = res.html.slice(0, 25000)
      message.success(`已成功抓取目标页面源码 (${(res.html.length / 1024).toFixed(1)} KB)`)
    }
  } catch (err: any) {
    message.error(err.response?.data?.message || err.message || '抓取网页源码失败')
  } finally {
    fetchingDebugHtml.value = false
  }
}

// 快速添加反馈标签
const addQuickTag = (tag: string) => {
  if (!debugUserFeedback.value.includes(tag)) {
    debugUserFeedback.value = debugUserFeedback.value ? `${debugUserFeedback.value}；${tag}` : tag
  }
}

// 启动 AI 智能诊断
const handleStartDebug = async () => {
  if (!aiStore.baseUrl) {
    message.error('尚未配置 AI 模型 API 地址，请在左侧侧边栏「系统设置」中配置')
    return
  }

  debugging.value = true
  try {
    let currentActionParams: any = {}
    if (activeAction.value === 'discovery') currentActionParams = paramsDiscovery.value
    else if (activeAction.value === 'search') currentActionParams = paramsSearch.value
    else if (activeAction.value === 'detail') currentActionParams = paramsDetail.value
    else if (activeAction.value === 'parse') currentActionParams = paramsParse.value

    const res = await aiStore.debugAndOptimizeRule({
      currentCode: props.code,
      action: activeAction.value,
      actionParams: currentActionParams,
      rawResult: rawResult.value,
      errorMessage: errorMessage.value,
      targetUrl: debugTargetUrl.value.trim(),
      targetHtml: debugTargetHtml.value.trim(),
      userFeedback: debugUserFeedback.value.trim(),
      mediaType: props.ruleType
    })

    if (res && res.fixedCode) {
      fixedCode.value = res.fixedCode
      debugAnalysis.value = res.analysis
      message.success('AI 诊断完成，已输出修复代码！')
    } else {
      message.error('AI 未能生成有效的修复代码')
    }
  } catch (err: any) {
    message.error('诊断失败: ' + err.message)
  } finally {
    debugging.value = false
  }
}

// 采纳修复代码并立即重新运行测试
const handleApplyFixAndRetry = () => {
  if (!fixedCode.value.trim()) return
  emit('update:code', fixedCode.value.trim())
  message.success('已应用修复代码，正在重新执行沙箱测试...')
  showAiDebugModal.value = false
  setTimeout(() => {
    executeAction(activeAction.value)
  }, 150)
}
</script>

<template>
  <n-modal
    :show="show"
    @update:show="(val) => emit('update:show', val)"
    preset="card"
    title="沙箱测试运行工作台"
    :class="[
      '!rounded-3xl shadow-2xl transition-all duration-300',
      isFullscreen ? 'w-screen h-screen !max-w-none !rounded-none !m-0' : 'max-w-6xl w-full'
    ]"
    :segmented="{ content: 'soft', footer: 'soft' }"
  >
    <template #header>
      <div class="flex items-center justify-between gap-4 w-full pr-6">
        <div class="flex items-center gap-3">
          <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center text-white shadow-md shadow-emerald-500/20">
            <Terminal class="w-4 h-4" />
          </div>
          <div>
            <h2 class="text-base font-black text-zinc-900 dark:text-white flex items-center gap-2">
              <span>规则沙箱交互式测试工作台</span>
              <span class="px-2 py-0.5 text-[10px] font-mono rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50">
                SANDBOX WORKBENCH
              </span>
            </h2>
            <p class="text-[11px] text-zinc-400">
              实时向 Node.js 沙箱注入 ESModule 规则代码，支持全链路多态调试与 AI 智能一键修复
            </p>
          </div>
        </div>

        <!-- 全屏切换按钮 -->
        <n-button
          quaternary
          circle
          size="small"
          @click="isFullscreen = !isFullscreen"
          :title="isFullscreen ? '还原窗口' : '全屏展开'"
        >
          <template #icon>
            <Minimize2 v-if="isFullscreen" class="w-4 h-4" />
            <Maximize2 v-else class="w-4 h-4" />
          </template>
        </n-button>
      </div>
    </template>

    <div class="flex flex-col gap-4" :class="isFullscreen ? 'h-[calc(100vh-160px)]' : 'h-[68vh]'">
      <!-- 1. 顶部控制栏：动作切换、动态参数与 AI 诊断 -->
      <div class="glass-panel rounded-2xl p-4 space-y-3 shadow-xs border border-emerald-100/60 dark:border-white/5">
        <!-- 动作 Tab 组与按键 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center gap-1.5 p-1 bg-zinc-100 dark:bg-white/[0.04] rounded-2xl">
            <button
              v-for="tab in actionTabs"
              :key="tab.value"
              type="button"
              @click="activeAction = tab.value"
              class="flex items-center gap-1.5 py-1.5 px-3 rounded-xl text-xs font-bold transition-all cursor-pointer select-none"
              :class="activeAction === tab.value
                ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs'
                : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
            >
              <component :is="tab.icon" class="w-3.5 h-3.5" />
              <span>{{ tab.label }}</span>
            </button>
          </div>

          <!-- 运行主按键与指标反馈 -->
          <div class="flex items-center gap-2.5">
            <!-- 耗时与状态指标 -->
            <div v-if="statusCode" class="flex items-center gap-2 text-xs font-mono">
              <span
                class="px-2 py-0.5 rounded-lg font-bold border"
                :class="statusCode === 200 ? 'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border-emerald-200/50' : 'bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 border-rose-200/50'"
              >
                {{ statusCode === 200 ? '200 OK' : `${statusCode} ERROR` }}
              </span>
              <span v-if="executionTimeMs" class="flex items-center gap-1 text-zinc-500 dark:text-zinc-400">
                <Clock class="w-3.5 h-3.5 text-emerald-500" />
                <span>{{ executionTimeMs }}ms</span>
              </span>
            </div>

            <!-- AI 智能诊断与代码修复按键 -->
            <n-button
              secondary
              type="primary"
              size="small"
              @click="openAiDebugger"
              class="!rounded-xl !font-bold"
              title="根据当前测试执行结果、缺失字段与目标 HTML，由 AI 自动定位并修复规则代码"
            >
              <template #icon>
                <Sparkles class="w-3.5 h-3.5 text-emerald-500" />
              </template>
              <span>AI 诊断与修复</span>
            </n-button>

            <!-- 运行按键 -->
            <n-button
              type="primary"
              size="small"
              :loading="running"
              @click="() => executeAction()"
              class="!rounded-xl !font-bold shadow-md shadow-emerald-500/20"
            >
              <template #icon>
                <Play class="w-3.5 h-3.5 fill-current" />
              </template>
              <span>{{ running ? '沙箱执行中...' : '运行测试 (Ctrl+Enter)' }}</span>
            </n-button>
          </div>
        </div>

        <!-- 动态结构化参数输入栏 -->
        <div class="pt-2 border-t border-emerald-100/50 dark:border-white/5 flex flex-wrap items-center gap-3">
          <!-- Discovery 参数 -->
          <template v-if="activeAction === 'discovery'">
            <div class="flex items-center gap-2 flex-1 min-w-[200px]">
              <span class="text-xs font-bold text-zinc-500 shrink-0">分类名称:</span>
              <n-input
                v-model:value="paramsDiscovery.category"
                size="small"
                placeholder="可选分类 (如: 热门, 最新, 动作)..."
                class="!rounded-xl text-xs"
                @keyup.enter="() => executeAction()"
              />
            </div>
            <div class="flex items-center gap-2 w-32">
              <span class="text-xs font-bold text-zinc-500 shrink-0">页码:</span>
              <n-input-number
                v-model:value="paramsDiscovery.page"
                size="small"
                :min="1"
                class="!rounded-xl text-xs w-full"
                @keyup.enter="() => executeAction()"
              />
            </div>
          </template>

          <!-- Search 参数 -->
          <template v-else-if="activeAction === 'search'">
            <div class="flex items-center gap-2 flex-1 min-w-[200px]">
              <span class="text-xs font-bold text-zinc-500 shrink-0">搜索关键词:</span>
              <n-input
                v-model:value="paramsSearch.keyword"
                size="small"
                placeholder="输入测试搜索关键字..."
                class="!rounded-xl text-xs"
                @keyup.enter="() => executeAction()"
              />
            </div>
            <div class="flex items-center gap-2 w-32">
              <span class="text-xs font-bold text-zinc-500 shrink-0">页码:</span>
              <n-input-number
                v-model:value="paramsSearch.page"
                size="small"
                :min="1"
                class="!rounded-xl text-xs w-full"
                @keyup.enter="() => executeAction()"
              />
            </div>
          </template>

          <!-- Detail 参数 -->
          <template v-else-if="activeAction === 'detail'">
            <div class="flex items-center gap-2 flex-1 min-w-[280px]">
              <span class="text-xs font-bold text-zinc-500 shrink-0">媒体 Key / 路径:</span>
              <n-input
                v-model:value="paramsDetail.key"
                size="small"
                placeholder="详情唯一标识或相对 URL (如: /detail/10086.html)..."
                class="!rounded-xl font-mono text-xs"
                @keyup.enter="() => executeAction()"
              />
            </div>
          </template>

          <!-- Parse 参数 -->
          <template v-else-if="activeAction === 'parse'">
            <div class="flex items-center gap-2 flex-1 min-w-[220px]">
              <span class="text-xs font-bold text-zinc-500 shrink-0">分集 Key / URL:</span>
              <n-input
                v-model:value="paramsParse.key"
                size="small"
                placeholder="分集唯一标识或链接..."
                class="!rounded-xl font-mono text-xs"
                @keyup.enter="() => executeAction()"
              />
            </div>
            <div class="flex items-center gap-2 w-48">
              <span class="text-xs font-bold text-zinc-500 shrink-0">线路分组:</span>
              <n-input
                v-model:value="paramsParse.groupName"
                size="small"
                placeholder="默认线路"
                class="!rounded-xl text-xs w-full"
                @keyup.enter="() => executeAction()"
              />
            </div>
          </template>
        </div>
      </div>

      <!-- 2. 结果展示面板 (双模态切换) -->
      <div class="flex-1 flex flex-col min-h-0 border border-emerald-100/60 dark:border-white/5 rounded-2xl overflow-hidden bg-white/50 dark:bg-black/20">
        <!-- 结果顶部工具栏 -->
        <div class="flex items-center justify-between px-4 py-2 border-b border-emerald-100/50 dark:border-white/5 bg-zinc-50/70 dark:bg-white/[0.02]">
          <div class="flex items-center gap-2">
            <div class="flex items-center gap-1 p-0.5 bg-zinc-200/60 dark:bg-white/[0.06] rounded-xl text-xs">
              <button
                type="button"
                @click="viewMode = 'visual'"
                class="px-2.5 py-1 rounded-lg font-bold transition-all cursor-pointer"
                :class="viewMode === 'visual' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-2xs' : 'text-zinc-500'"
              >
                视觉真实渲染 (Live View)
              </button>
              <button
                type="button"
                @click="viewMode = 'json'"
                class="px-2.5 py-1 rounded-lg font-bold transition-all cursor-pointer"
                :class="viewMode === 'json' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-2xs' : 'text-zinc-500'"
              >
                原始 JSON 数据 (Raw)
              </button>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <n-button
              v-if="rawResult"
              size="tiny"
              secondary
              @click="copyJson"
              class="!rounded-lg"
            >
              <template #icon>
                <Copy class="w-3 h-3" />
              </template>
              复制 JSON
            </n-button>
          </div>
        </div>

        <!-- 主内容视口 -->
        <div class="flex-1 overflow-y-auto p-4 relative">
          <!-- 加载遮罩 -->
          <div v-if="running" class="absolute inset-0 bg-white/70 dark:bg-zinc-950/70 backdrop-blur-xs flex flex-col items-center justify-center gap-3 z-10">
            <n-spin size="large" />
            <span class="text-xs font-bold text-zinc-500">Node.js 沙箱正在抓取与解析中...</span>
          </div>

          <!-- 报错面板与 AI 一键修复入口 -->
          <div
            v-if="errorMessage"
            class="p-5 rounded-2xl bg-rose-500/10 border border-rose-500/30 space-y-3 text-rose-600 dark:text-rose-400 text-xs"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2 font-bold text-sm">
                <AlertCircle class="w-4 h-4" />
                <span>沙箱执行捕获到异常</span>
              </div>
              <n-button
                type="error"
                secondary
                size="tiny"
                @click="openAiDebugger"
                class="!rounded-lg !font-bold"
              >
                <template #icon>
                  <Sparkles class="w-3.5 h-3.5" />
                </template>
                启动 AI 诊断与自动修复
              </n-button>
            </div>
            <pre class="font-mono text-[11px] whitespace-pre-wrap leading-relaxed">{{ errorMessage }}</pre>
          </div>

          <!-- 模式 1: 视觉多态渲染 (Visual Preview) -->
          <div v-else-if="viewMode === 'visual' && rawResult" class="space-y-4">
            <!-- (A) Discovery / Search 结果展示 (卡片流) -->
            <div v-if="activeAction === 'discovery' || activeAction === 'search'" class="space-y-3">
              <!-- 分类标签 -->
              <div v-if="rawResult.categories && rawResult.categories.length > 0" class="flex flex-wrap items-center gap-1.5 pb-2 border-b border-emerald-100/50 dark:border-white/5">
                <span class="text-xs text-zinc-400 font-bold mr-1">支持分类:</span>
                <span
                  v-for="cat in rawResult.categories"
                  :key="cat"
                  class="px-2 py-0.5 text-[10px] font-bold rounded-md bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/40"
                >
                  {{ cat }}
                </span>
              </div>

              <!-- 卡片网格 -->
              <div v-if="rawResult.items && rawResult.items.length > 0" class="grid gap-3 sm:gap-4 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
                <div
                  v-for="item in rawResult.items"
                  :key="item.key"
                  class="group relative flex flex-col rounded-2xl overflow-hidden bg-white dark:bg-white/[0.04] border border-emerald-100/60 dark:border-white/5 shadow-2xs hover:shadow-lg transition-all"
                >
                  <div class="aspect-[16/10] overflow-hidden relative bg-zinc-200 dark:bg-zinc-900">
                    <img
                      v-if="item.cover"
                      :src="item.cover"
                      referrerpolicy="no-referrer"
                      class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                      loading="lazy"
                    />
                    <div v-else class="w-full h-full flex items-center justify-center text-zinc-400">
                      <ImageIcon class="w-6 h-6" />
                    </div>

                    <span
                      v-if="item.badge"
                      class="absolute top-2 right-2 px-1.5 py-0.5 text-[9px] font-bold rounded bg-black/60 text-white backdrop-blur-xs"
                    >
                      {{ item.badge }}
                    </span>
                  </div>

                  <div class="p-2.5 flex flex-col gap-1.5 flex-1 justify-between">
                    <div class="text-xs font-bold text-zinc-800 dark:text-zinc-100 line-clamp-2" :title="item.title">
                      {{ item.title }}
                    </div>

                    <!-- 联动流转按钮 -->
                    <n-button
                      size="tiny"
                      quaternary
                      type="primary"
                      class="!rounded-lg !text-[10px] w-full"
                      @click="testItemDetail(item)"
                    >
                      <span>测试 Detail ➔</span>
                    </n-button>
                  </div>
                </div>
              </div>
              <div v-else class="text-center py-10 text-zinc-400 text-xs">
                返回列表为空 (items: [])
              </div>
            </div>

            <!-- (B) Detail 详情多态视觉展示 -->
            <div v-else-if="activeAction === 'detail'" class="space-y-4">
              <div class="grid grid-cols-1 md:grid-cols-12 gap-5">
                <!-- 封面大图 -->
                <div v-if="rawResult.cover" class="md:col-span-4 lg:col-span-3">
                  <div class="aspect-[3/4] rounded-2xl overflow-hidden shadow-lg border border-emerald-100/60 dark:border-white/5 bg-zinc-900">
                    <img
                      :src="rawResult.cover"
                      referrerpolicy="no-referrer"
                      class="w-full h-full object-cover"
                    />
                  </div>
                </div>

                <!-- 核心详情信息 -->
                <div :class="rawResult.cover ? 'md:col-span-8 lg:col-span-9' : 'md:col-span-12'" class="space-y-3">
                  <h1 class="text-lg font-black text-zinc-900 dark:text-white">
                    {{ rawResult.title || '（未解析出标题 title）' }}
                  </h1>

                  <div class="flex flex-wrap items-center gap-2 text-xs text-zinc-500">
                    <span v-if="rawResult.author" class="px-2 py-0.5 rounded-md bg-zinc-100 dark:bg-white/[0.06]">
                      作者: {{ rawResult.author }}
                    </span>
                    <div v-if="rawResult.tags && rawResult.tags.length > 0" class="flex flex-wrap gap-1">
                      <span
                        v-for="t in rawResult.tags"
                        :key="t"
                        class="px-2 py-0.5 rounded-md bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/40 text-[10px]"
                      >
                        {{ t }}
                      </span>
                    </div>
                  </div>

                  <p v-if="rawResult.desc" class="text-xs text-zinc-600 dark:text-zinc-300 leading-relaxed whitespace-pre-line bg-zinc-50 dark:bg-white/[0.02] p-3 rounded-xl border border-zinc-100 dark:border-white/5">
                    {{ rawResult.desc }}
                  </p>

                  <!-- 选集分组 Groups (含联动 Parse 调试) -->
                  <div v-if="rawResult.groups && rawResult.groups.length > 0" class="space-y-2 pt-2">
                    <div class="text-xs font-bold text-zinc-800 dark:text-zinc-200">
                      播放线路与选集 (点击可直接触发 Parse 测试)
                    </div>
                    <div v-for="g in rawResult.groups" :key="g.name" class="space-y-1.5 p-3 rounded-2xl bg-zinc-100/60 dark:bg-white/[0.03] border border-zinc-200/50 dark:border-white/5">
                      <div class="text-[11px] font-bold text-emerald-600 dark:text-emerald-400">
                        {{ g.name }} ({{ g.items?.length || 0 }} 集)
                      </div>
                      <div class="flex flex-wrap gap-1.5 max-h-36 overflow-y-auto">
                        <n-button
                          v-for="ep in g.items"
                          :key="ep.key"
                          size="tiny"
                          secondary
                          class="!rounded-lg !text-[11px]"
                          @click="testEpisodeParse(ep.key, g.name)"
                        >
                          {{ ep.title }}
                        </n-button>
                      </div>
                    </div>
                  </div>

                  <!-- 图片画廊预览 -->
                  <div v-if="rawResult.images && rawResult.images.length > 0" class="space-y-2 pt-2">
                    <div class="text-xs font-bold text-zinc-800 dark:text-zinc-200">画廊图集 ({{ rawResult.images.length }} 张)</div>
                    <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-2">
                      <div v-for="(img, idx) in rawResult.images" :key="idx" class="aspect-square rounded-xl overflow-hidden bg-zinc-900 border border-zinc-200 dark:border-white/10">
                        <img :src="img" referrerpolicy="no-referrer" class="w-full h-full object-cover" loading="lazy" />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- (C) Parse 播放/正文解析结果 -->
            <div v-else-if="activeAction === 'parse'" class="space-y-4">
              <!-- 视频播放器直链测试 -->
              <div v-if="rawResult.playUrl || (typeof rawResult === 'string' && rawResult.startsWith('http'))" class="space-y-3">
                <div class="aspect-video max-w-2xl mx-auto rounded-2xl overflow-hidden bg-black shadow-xl">
                  <ArtPlayer :url="rawResult.playUrl || rawResult" title="解析播放测试" />
                </div>
                <div class="p-3 rounded-xl bg-zinc-100 dark:bg-white/[0.04] font-mono text-xs text-zinc-700 dark:text-zinc-300 break-all text-center">
                  直链地址: {{ rawResult.playUrl || rawResult }}
                </div>
              </div>

              <!-- 小说正文排版预览 -->
              <div v-else-if="rawResult.content" class="glass-panel rounded-2xl p-6 max-w-3xl mx-auto space-y-4">
                <div class="text-sm font-bold text-zinc-800 dark:text-zinc-100 pb-2 border-b border-emerald-100/50 dark:border-white/5">
                  正文解析预览
                </div>
                <div class="text-sm leading-relaxed text-zinc-700 dark:text-zinc-300 whitespace-pre-line font-serif">
                  {{ rawResult.content }}
                </div>
              </div>
            </div>
          </div>

          <!-- 模式 2: 原始 JSON 查看 (Raw JSON View) -->
          <div v-else-if="viewMode === 'json' && rawResult" class="h-full">
            <code-editor
              v-model="jsonOutput"
              model-id="test_result_json"
              :height="isFullscreen ? 650 : 380"
              language="json"
            />
          </div>

          <!-- 空白待运行状态 -->
          <div v-else-if="!running && !rawResult && !errorMessage" class="h-full flex flex-col items-center justify-center text-zinc-400 gap-2 p-10 text-center">
            <Terminal class="w-12 h-12 text-zinc-300 dark:text-zinc-700" />
            <span class="text-xs text-zinc-500">选择上方动作与参数后，点击「运行测试 (Ctrl+Enter)」即可在此实时查看沙箱解析渲染。</span>
          </div>
        </div>
      </div>
    </div>

    <!-- 底部状态条 -->
    <template #footer>
      <div class="flex items-center justify-between gap-3 text-xs text-zinc-400">
        <div class="flex items-center gap-1.5">
          <Sparkles class="w-3.5 h-3.5 text-emerald-500" />
          <span>支持实时流转：Discovery ➔ 点击卡片调试 Detail ➔ 点击分集调试 Parse</span>
        </div>
        <n-button size="small" class="!rounded-xl" @click="emit('update:show', false)">
          关闭工作台
        </n-button>
      </div>
    </template>
  </n-modal>

  <!-- 🌟 AI 规则智能诊断与增量修复弹窗 (AI Smart Debugger Modal) -->
  <n-modal
    v-model:show="showAiDebugModal"
    preset="card"
    title="AI 规则智能诊断与自动修复"
    class="!rounded-3xl max-w-5xl shadow-2xl w-full"
    :segmented="{ content: 'soft', footer: 'soft' }"
  >
    <template #header>
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center shadow-md shadow-emerald-500/20 text-white">
          <Wrench class="w-4 h-4 animate-pulse" />
        </div>
        <div>
          <h2 class="text-base font-black text-zinc-900 dark:text-white flex items-center gap-2">
            <span>AI 规则智能诊断与修复</span>
            <span class="px-2 py-0.5 text-[10px] font-mono rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50">
              DEBUGGER 2.0
            </span>
          </h2>
          <p class="text-[11px] text-zinc-400">结合当前规则源码、沙箱执行报错/缺失字段与目标网页 DOM 源码，由 AI 大模型精准定位并修复选择器与解析逻辑</p>
        </div>
      </div>
    </template>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-5 h-[62vh]">
      <!-- 左侧：上下文与诉求栏 (lg:col-span-5) -->
      <div class="lg:col-span-5 flex flex-col gap-3 h-full overflow-y-auto pr-1">
        <!-- 诊断动作与状态展示 -->
        <div class="p-3 rounded-2xl bg-zinc-50 dark:bg-white/[0.03] border border-zinc-200/60 dark:border-white/5 space-y-1.5">
          <div class="flex items-center justify-between text-xs font-bold">
            <span class="text-zinc-500">诊断目标动作:</span>
            <span class="font-mono text-emerald-600 dark:text-emerald-400 font-black">{{ activeAction }}()</span>
          </div>
          <div class="flex items-center justify-between text-xs font-bold">
            <span class="text-zinc-500">沙箱运行状态:</span>
            <span class="font-mono" :class="errorMessage ? 'text-rose-500' : 'text-emerald-500'">
              {{ errorMessage ? '报错捕获 (Error)' : (rawResult ? '已返回数据 (有缺失)' : '未运行') }}
            </span>
          </div>
        </div>

        <!-- 目标页面 URL 与抓取 -->
        <div class="space-y-1">
          <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
            <span>目标网页 URL</span>
            <n-button
              size="tiny"
              secondary
              type="primary"
              :loading="fetchingDebugHtml"
              @click="handleFetchDebugHtml"
              class="!rounded-lg !font-bold"
            >
              <template #icon>
                <DownloadCloud class="w-3 h-3" />
              </template>
              抓取目标 HTML
            </n-button>
          </div>
          <n-input
            v-model:value="debugTargetUrl"
            placeholder="例如: https://site.com/detail/10086.html"
            class="!rounded-xl font-mono text-xs"
          />
        </div>

        <!-- 问题反馈描述与快捷标签 -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center justify-between">
            <span>遇到了什么问题 / 期望提取什么字段</span>
          </label>
          <div class="flex flex-wrap gap-1 pb-1">
            <span
              v-for="tag in quickProblemTags"
              :key="tag"
              @click="addQuickTag(tag)"
              class="px-2 py-0.5 text-[10px] rounded-lg bg-zinc-100 dark:bg-white/[0.05] hover:bg-emerald-50 dark:hover:bg-emerald-950/40 text-zinc-600 dark:text-zinc-300 hover:text-emerald-600 cursor-pointer transition-colors border border-zinc-200/50 dark:border-white/5"
            >
              + {{ tag }}
            </span>
          </div>
          <n-input
            v-model:value="debugUserFeedback"
            type="textarea"
            placeholder="在此描述具体问题（例如: 选集列表 groups 提取出来是空的，且封面没有提取到）..."
            class="!rounded-xl text-xs"
            :autosize="{ minRows: 2, maxRows: 4 }"
          />
        </div>

        <!-- 目标网页 HTML 片段展示/编辑 -->
        <div class="space-y-1 flex-1 flex flex-col min-h-[100px]">
          <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
            <span>目标网页 HTML 片段 (DOM)</span>
            <span class="text-[10px] font-mono text-zinc-400">{{ debugTargetHtml.length }} 字符</span>
          </div>
          <n-input
            v-model:value="debugTargetHtml"
            type="textarea"
            placeholder="若无法自动抓取，可在此直接粘贴目标页面的局部 HTML 片段..."
            class="!rounded-xl font-mono text-xs flex-1"
            :autosize="{ minRows: 3, maxRows: 6 }"
          />
        </div>

        <!-- 启动诊断按键 -->
        <n-button
          type="primary"
          block
          :loading="debugging"
          @click="handleStartDebug"
          class="!rounded-xl !font-bold !py-3.5 shadow-lg shadow-emerald-500/20 mt-1 shrink-0"
        >
          <template #icon>
            <Sparkles class="w-4 h-4" />
          </template>
          <span>{{ debugging ? 'AI 正在深入分析 DOM 并重构规则中...' : '开始 AI 智能诊断与修复' }}</span>
        </n-button>
      </div>

      <!-- 右侧：诊断结论与修复后代码预览 (lg:col-span-7) -->
      <div class="lg:col-span-7 flex flex-col gap-2 h-full border border-emerald-100/50 dark:border-white/5 rounded-2xl p-3 bg-zinc-50/50 dark:bg-black/20">
        <!-- 诊断分析说明结论 -->
        <div v-if="debugAnalysis" class="p-3 rounded-xl bg-emerald-50/80 dark:bg-emerald-950/40 border border-emerald-200/60 dark:border-emerald-800/40 text-xs text-emerald-800 dark:text-emerald-300 leading-relaxed shrink-0">
          <div class="font-bold flex items-center gap-1.5 mb-1 text-emerald-700 dark:text-emerald-200">
            <CheckCircle2 class="w-3.5 h-3.5 text-emerald-500" />
            <span>AI 诊断分析与修复总结：</span>
          </div>
          <div class="whitespace-pre-line text-[11px] font-medium">{{ debugAnalysis }}</div>
        </div>

        <div class="flex items-center justify-between pb-1 border-b border-emerald-100/50 dark:border-white/5 shrink-0">
          <div class="flex items-center gap-2">
            <div class="w-1.5 h-4 rounded-full bg-gradient-to-b from-emerald-500 to-cyan-500"></div>
            <span class="text-xs font-bold text-zinc-800 dark:text-zinc-200">修复后的规则代码</span>
          </div>
          <span v-if="fixedCode" class="text-[10px] font-mono text-emerald-600 dark:text-emerald-400">就绪待采纳</span>
        </div>

        <!-- Monaco 代码编辑器预览 -->
        <div class="flex-1 w-full rounded-xl overflow-hidden border border-zinc-200/60 dark:border-white/5 relative">
          <div v-if="debugging" class="w-full h-full flex flex-col items-center justify-center text-zinc-400 gap-3 bg-white/60 dark:bg-zinc-900/60 backdrop-blur-xs">
            <n-spin size="large" />
            <span class="text-xs font-bold">AI 正在对比 DOM 与旧选择器，生成精准补丁...</span>
          </div>
          <CodeEditor
            v-else-if="fixedCode"
            v-model="fixedCode"
            language="javascript"
          />
          <div v-else class="w-full h-full flex flex-col items-center justify-center text-zinc-400 gap-2 p-6 text-center">
            <Bot class="w-12 h-12 text-zinc-300 dark:text-zinc-700" />
            <span class="text-xs text-zinc-500">在左侧补充目标网页源码与问题描述后，点击「开始 AI 智能诊断与修复」即可在此查看优化后的代码并一键重跑验证。</span>
          </div>
        </div>
      </div>
    </div>

    <!-- 底部按钮 -->
    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <div class="text-[11px] text-zinc-400 flex items-center gap-1">
          <Sparkles class="w-3.5 h-3.5 text-emerald-500" />
          <span>采纳修复代码后将直接同步回主编辑器，并自动重跑沙箱验证效果</span>
        </div>

        <div class="flex items-center gap-2">
          <n-button size="small" class="!rounded-xl" @click="showAiDebugModal = false">
            取消
          </n-button>
          <n-button
            type="primary"
            size="small"
            :disabled="!fixedCode"
            class="!rounded-xl !font-bold"
            @click="handleApplyFixAndRetry"
          >
            <template #icon>
              <Check class="w-3.5 h-3.5" />
            </template>
            应用修复并重试测试
          </n-button>
        </div>
      </div>
    </template>
  </n-modal>
</template>

<style scoped>
</style>
