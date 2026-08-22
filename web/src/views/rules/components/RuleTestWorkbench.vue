<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
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
  RotateCcw
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
}>()

const message = useMessage()

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

// 动作标签选项
const actionTabs = [
  { label: 'discovery() 发现流', value: 'discovery' as RuleAction, icon: Compass },
  { label: 'search() 聚合搜索', value: 'search' as RuleAction, icon: Search },
  { label: 'detail() 媒体详情', value: 'detail' as RuleAction, icon: FileText },
  { label: 'parse() 动态解析', value: 'parse' as RuleAction, icon: Terminal }
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
    const res = await http.post('/rules/execute', {
      code: props.code,
      action: targetAction,
      params: requestParams
    })

    const duration = Math.round(performance.now() - startTime)
    executionTimeMs.value = duration
    statusCode.value = 200
    rawResult.value = res
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
              实时向 Node.js 沙箱注入 ESModule 规则代码，支持多动作链式调试与真实多态视觉预览
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
      <!-- 1. 顶部控制栏：动作切换与动态参数 -->
      <div class="glass-panel rounded-2xl p-4 space-y-3 shadow-xs border border-emerald-100/60 dark:border-white/5">
        <!-- 动作 Tab 组 -->
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
                placeholder="可选分类 (如: 热门, 最新, 吃瓜)..."
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
                placeholder="详情唯一标识或相对 URL..."
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
        <!-- 结果顶部工具栏 (视觉预览 / JSON 查看) -->
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

          <!-- 报错面板 -->
          <div
            v-if="errorMessage"
            class="p-5 rounded-2xl bg-rose-500/10 border border-rose-500/30 space-y-2 text-rose-600 dark:text-rose-400 text-xs"
          >
            <div class="flex items-center gap-2 font-bold text-sm">
              <AlertCircle class="w-4 h-4" />
              <span>沙箱执行捕获到异常</span>
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
                      :alt="item.title"
                      class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                      loading="lazy"
                    />
                    <div v-else class="w-full h-full flex items-center justify-center text-zinc-400 text-xs">无封面</div>
                    <span v-if="item.badge" class="absolute top-1.5 right-1.5 px-1.5 py-0.5 text-[9px] font-bold rounded-md bg-black/60 text-white backdrop-blur-xs">
                      {{ item.badge }}
                    </span>
                  </div>

                  <div class="p-2.5 flex flex-col justify-between flex-1 space-y-2">
                    <div>
                      <h4 class="text-xs font-bold text-zinc-800 dark:text-zinc-200 line-clamp-1 leading-snug">{{ item.title }}</h4>
                      <p v-if="item.desc" class="text-[10px] text-zinc-400 line-clamp-1 mt-0.5">{{ item.desc }}</p>
                    </div>

                    <!-- 快捷流转测试 detail 按钮 -->
                    <n-button
                      size="tiny"
                      type="primary"
                      secondary
                      block
                      class="!rounded-lg !text-[10px] !font-bold"
                      @click="testItemDetail(item)"
                    >
                      <span>调试此项详情</span>
                      <ArrowRight class="w-3 h-3 ml-1" />
                    </n-button>
                  </div>
                </div>
              </div>
              <div v-else class="text-center py-10 text-zinc-400 text-xs">
                返回的 items 列表为空
              </div>
            </div>

            <!-- (B) Detail 结果展示 (多态详情) -->
            <div v-else-if="activeAction === 'detail'" class="space-y-5">
              <div class="grid grid-cols-1 lg:grid-cols-12 gap-5 items-start">
                <!-- 视频播放测试 (如有 playUrl) -->
                <div v-if="rawResult.playUrl" class="lg:col-span-8 flex flex-col gap-3">
                  <div class="aspect-video w-full rounded-2xl overflow-hidden bg-black shadow-lg border border-zinc-200/50 dark:border-white/10">
                    <ArtPlayer :url="rawResult.playUrl" :title="rawResult.title" />
                  </div>
                </div>

                <!-- 详情文字信息 -->
                <div :class="rawResult.playUrl ? 'lg:col-span-4' : 'lg:col-span-12'" class="glass-panel rounded-2xl p-5 space-y-3">
                  <h3 class="text-base font-black text-zinc-900 dark:text-white">{{ rawResult.title }}</h3>
                  <div v-if="rawResult.tags && rawResult.tags.length > 0" class="flex flex-wrap gap-1">
                    <span v-for="t in rawResult.tags" :key="t" class="px-2 py-0.5 text-[10px] font-bold rounded-md bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/40">
                      {{ t }}
                    </span>
                  </div>
                  <p v-if="rawResult.desc" class="text-xs text-zinc-600 dark:text-zinc-300 whitespace-pre-line leading-relaxed">{{ rawResult.desc }}</p>
                </div>
              </div>

              <!-- 选集测试与流转 (groups) -->
              <div v-if="rawResult.groups && rawResult.groups.length > 0" class="space-y-3">
                <div v-for="g in rawResult.groups" :key="g.name" class="space-y-2">
                  <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
                    <div class="w-1.5 h-3.5 rounded-full bg-emerald-500"></div>
                    <span>{{ g.name }} (点击任意分集直接测试 parse)</span>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <n-button
                      v-for="ep in g.items"
                      :key="ep.key"
                      size="small"
                      secondary
                      class="!rounded-xl !text-xs !font-bold"
                      @click="testEpisodeParse(ep.key, g.name)"
                    >
                      <span>{{ ep.title }}</span>
                      <Terminal class="w-3 h-3 ml-1 opacity-60" />
                    </n-button>
                  </div>
                </div>
              </div>

              <!-- 图集预览 (images) -->
              <div v-if="rawResult.images && rawResult.images.length > 0" class="space-y-2">
                <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300">图集画廊预览 ({{ rawResult.images.length }} 张)</div>
                <div class="grid gap-3 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
                  <div
                    v-for="(img, idx) in rawResult.images"
                    :key="idx"
                    class="rounded-xl overflow-hidden aspect-[16/10] bg-zinc-100 dark:bg-zinc-900 border border-zinc-200/60 dark:border-white/5"
                  >
                    <img :src="img" referrerpolicy="no-referrer" class="w-full h-full object-cover" loading="lazy" />
                  </div>
                </div>
              </div>
            </div>

            <!-- (C) Parse 结果展示 (直链或正文) -->
            <div v-else-if="activeAction === 'parse'" class="space-y-4">
              <!-- 视频播放器测试 -->
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
</template>

<style scoped>
</style>
