<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import type { RuleAction, MediaType } from '@/types/rule'
import ArtPlayer from '@/components/ArtPlayer.vue'
import {
  Compass,
  Search,
  FileText,
  Terminal,
  Play,
  AlertCircle,
  CheckCircle2,
  Copy,
  ExternalLink,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  Layers,
  Sparkles,
  Trash2
} from '@lucide/vue'

const props = withDefaults(
  defineProps<{
    code: string
    ruleType?: MediaType | string
    baseUrl?: string
    collapsed?: boolean
  }>(),
  {
    collapsed: false
  }
)

const emit = defineEmits<{
  (e: 'update:collapsed', val: boolean): void
  (e: 'logs', logs: any[]): void
  (e: 'fix-error', context: { action: RuleAction; actionParams: any; rawResult: any; errorMessage: string }): void
}>()

const isCollapsed = ref(props.collapsed)
watch(
  () => props.collapsed,
  (val) => {
    isCollapsed.value = val
  }
)

const toggleCollapsed = () => {
  isCollapsed.value = !isCollapsed.value
  emit('update:collapsed', isCollapsed.value)
}

const message = useMessage()

// ----------------------------------------------------
// 1. 动作与参数配置
// ----------------------------------------------------
const activeAction = ref<RuleAction>('discovery')
const actionTabs = [
  { label: 'discovery', desc: '发现', value: 'discovery' as RuleAction, icon: Compass },
  { label: 'search', desc: '搜索', value: 'search' as RuleAction, icon: Search },
  { label: 'detail', desc: '详情', value: 'detail' as RuleAction, icon: FileText },
  { label: 'parse', desc: '解析', value: 'parse' as RuleAction, icon: Terminal }
]

const paramsDiscovery = ref({ tab: '', page: 1 })
const paramsSearch = ref({ keyword: '', page: 1 })
const paramsDetail = ref({ url: '', item: null as any })
const paramsParse = ref({ url: '', groupName: '' })

const viewMode = ref<'visual' | 'json' | 'logs'>('visual')
const running = ref(false)
const rawResult = ref<any>(null)
const executionTimeMs = ref<number | null>(null)
const statusCode = ref<number | null>(null)
const errorMessage = ref<string>('')
const sandboxLogs = ref<Array<{ level: 'log' | 'warn' | 'error' | 'info'; time: string; message: string }>>([])

const jsonOutput = computed(() => {
  if (errorMessage.value) return JSON.stringify({ error: errorMessage.value }, null, 2)
  if (!rawResult.value) return ''
  return JSON.stringify(rawResult.value, null, 2)
})

const getActionParams = (action: RuleAction) => {
  switch (action) {
    case 'discovery': return paramsDiscovery.value
    case 'search': return paramsSearch.value
    case 'detail': return paramsDetail.value
    case 'parse': return paramsParse.value
  }
}

// 智能归一化测试结果
const parsedVisualData = computed(() => {
  if (!rawResult.value) return null
  const r = rawResult.value

  let items: any[] | null = null
  if (Array.isArray(r)) {
    items = r
  } else if (r && typeof r === 'object') {
    if (Array.isArray(r.items)) items = r.items
    else if (Array.isArray(r.list)) items = r.list
    else if (Array.isArray(r.data)) items = r.data
    else if (Array.isArray(r.results)) items = r.results
    else if (Array.isArray(r.books)) items = r.books
    else if (Array.isArray(r.images)) items = r.images
    else if (Array.isArray(r.pictures)) items = r.pictures
  }

  const tabs = r && typeof r === 'object' && Array.isArray(r.tabs) ? r.tabs : []

  return {
    items,
    isDetail: activeAction.value === 'detail' || (r && typeof r === 'object' && (r.title || r.groups || r.playUrl)),
    isParse: activeAction.value === 'parse',
    tabs,
    raw: r
  }
})

const handleSelectTab = (t: any) => {
  const val = typeof t === 'object' ? (t.title || t.url || '') : String(t)
  paramsDiscovery.value.tab = val
  paramsDiscovery.value.page = 1
  executeAction('discovery')
}

// 执行沙箱动作
const executeAction = async (actionToRun?: RuleAction, overrideCode?: string) => {
  const targetAction = actionToRun || activeAction.value
  activeAction.value = targetAction

  const codeToRun = overrideCode || props.code
  if (!codeToRun || !codeToRun.trim()) {
    message.warning('请先输入或由 AI 生成规则脚本代码')
    return
  }

  if (isCollapsed.value) {
    isCollapsed.value = false
    emit('update:collapsed', false)
  }

  running.value = true
  errorMessage.value = ''
  statusCode.value = null
  executionTimeMs.value = null
  rawResult.value = null
  sandboxLogs.value = []

  const startTime = performance.now()
  try {
    const payload = {
      code: codeToRun,
      action: targetAction,
      params: getActionParams(targetAction),
      baseUrl: props.baseUrl || ''
    }

    const res: any = await http.post('/rules/run', payload)
    executionTimeMs.value = Math.round(performance.now() - startTime)
    statusCode.value = 200

    rawResult.value = res?.result ?? res
    sandboxLogs.value = res?.logs || []
    emit('logs', sandboxLogs.value)

    if (rawResult.value === undefined || rawResult.value === null) {
      errorMessage.value = '沙箱执行返回了空数据 (null/undefined)'
    } else {
      message.success(`测试完成: ${targetAction} (${executionTimeMs.value}ms)`)
    }
  } catch (err: any) {
    executionTimeMs.value = Math.round(performance.now() - startTime)
    statusCode.value = err.response?.status || 500
    const errData = err.response?.data
    errorMessage.value = errData?.message || err.message || '沙箱执行异常'
    sandboxLogs.value = errData?.logs || []
    emit('logs', sandboxLogs.value)
    message.error(`执行失败: ${errorMessage.value}`)
  } finally {
    running.value = false
  }
}

// 快速跳转到详情测试
const testDetailWithItem = (item: any) => {
  if (!item) return
  paramsDetail.value = {
    url: item.url || '',
    item: {
      title: item.title,
      cover: item.cover,
      desc: item.desc
    }
  }
  executeAction('detail')
}

// 快速跳转到选集解析测试
const testParseWithEpisode = (ep: any, groupName: string) => {
  if (!ep) return
  paramsParse.value = {
    url: ep.url || '',
    groupName
  }
  executeAction('parse')
}

// 触发 AI 修复此问题
const triggerFixError = () => {
  emit('fix-error', {
    action: activeAction.value,
    actionParams: getActionParams(activeAction.value),
    rawResult: rawResult.value,
    errorMessage: errorMessage.value || '测试结果为空或不符合预期'
  })
}

// 复制 JSON 结果
const copyJsonResult = async () => {
  if (!jsonOutput.value) return
  try {
    await navigator.clipboard.writeText(jsonOutput.value)
    message.success('已复制测试结果 JSON')
  } catch {
    message.error('复制失败')
  }
}

const clearLogs = () => {
  sandboxLogs.value = []
  emit('logs', [])
}

defineExpose({
  executeAction,
  activeAction,
  isCollapsed,
  toggleCollapsed,
  clearLogs
})
</script>

<template>
  <div
    class="glass-panel rounded-2xl border border-emerald-100/60 dark:border-white/5 shadow-xs flex flex-col transition-all duration-300 overflow-hidden"
    :class="isCollapsed ? 'shrink-0' : 'flex-1 min-h-[260px] max-h-[440px]'"
  >
    <!-- 测试控制栏与 Tab 切换 -->
    <div class="px-3.5 py-2 border-b border-zinc-100 dark:border-white/5 flex flex-wrap items-center justify-between gap-2 bg-zinc-50/70 dark:bg-white/[0.02] shrink-0 select-none">
      <div class="flex items-center gap-3">
        <!-- 4 大动作 Tabs 切换 -->
        <div class="flex items-center p-0.5 rounded-xl bg-zinc-200/50 dark:bg-white/[0.04] border border-zinc-200/60 dark:border-white/5">
          <button
            v-for="tab in actionTabs"
            :key="tab.value"
            type="button"
            class="flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-lg transition-all cursor-pointer"
            :class="activeAction === tab.value ? 'bg-white dark:bg-zinc-800 text-zinc-900 dark:text-white shadow-xs font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-300'"
            @click="activeAction = tab.value"
          >
            <component :is="tab.icon" class="w-3.5 h-3.5" />
            <span>{{ tab.desc }}</span>
          </button>
        </div>

        <!-- 快速入参提示 (折叠或宽屏时显示) -->
        <div class="hidden md:flex items-center gap-2 text-xs font-mono text-zinc-400">
          <span v-if="activeAction === 'discovery'">tab: {{ paramsDiscovery.tab || '默认' }} (p{{ paramsDiscovery.page }})</span>
          <span v-else-if="activeAction === 'search'">wd: {{ paramsSearch.keyword || '未输入' }} (p{{ paramsSearch.page }})</span>
          <span v-else-if="activeAction === 'detail'">url: {{ paramsDetail.url ? '已设置' : '未设置' }}</span>
          <span v-else-if="activeAction === 'parse'">url: {{ paramsParse.url ? '已设置' : '未设置' }}</span>
        </div>
      </div>

      <!-- 运行按钮与快捷键提示 -->
      <div class="flex items-center gap-2">
        <span v-if="executionTimeMs !== null" class="text-[10px] font-mono px-2 py-0.5 rounded-md bg-zinc-100 dark:bg-white/5 text-zinc-500">
          {{ executionTimeMs }}ms · {{ statusCode }}
        </span>

        <n-button
          size="small"
          type="primary"
          class="!rounded-xl !font-bold !px-3 shadow-xs"
          :loading="running"
          @click="executeAction()"
        >
          <template #icon>
            <Play class="w-3.5 h-3.5 fill-current" />
          </template>
          <span>运行测试 (Ctrl+R)</span>
        </n-button>

        <n-button
          quaternary
          size="small"
          class="!p-1.5 !rounded-xl text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
          :title="isCollapsed ? '展开沙箱测试与结果面板' : '收起沙箱面板'"
          @click="toggleCollapsed"
        >
          <template #icon>
            <component :is="isCollapsed ? ChevronUp : ChevronDown" class="w-4 h-4" />
          </template>
        </n-button>
      </div>
    </div>

    <!-- 展开后的主体内容 -->
    <div v-if="!isCollapsed" class="p-3 space-y-3 flex-1 flex flex-col min-h-0 overflow-hidden">
      <!-- 动态入参配置面板 -->
      <div class="p-2 rounded-xl bg-zinc-50/70 dark:bg-zinc-900/40 border border-zinc-200/40 dark:border-white/5 space-y-2 shrink-0">
        <!-- discovery 参数 -->
        <div v-if="activeAction === 'discovery'" class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div class="flex items-center gap-1.5 min-w-0 sm:col-span-2">
            <span class="text-[11px] text-zinc-400 w-8 shrink-0">tab:</span>
            <n-input
              v-model:value="paramsDiscovery.tab"
              placeholder="页签名称/路径(可选)"
              size="tiny"
              class="!rounded-lg text-xs"
            />
          </div>
          <div class="flex items-center gap-1.5 min-w-0 sm:col-span-2">
            <span class="text-[11px] text-zinc-400 w-10 shrink-0">page:</span>
            <n-input-number v-model:value="paramsDiscovery.page" :min="1" size="tiny" class="!rounded-lg text-xs flex-1" />
          </div>
        </div>

        <!-- search 参数 -->
        <div v-else-if="activeAction === 'search'" class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div class="flex items-center gap-1.5 min-w-0 sm:col-span-2">
            <span class="text-[11px] text-zinc-400 w-14 shrink-0">keyword:</span>
            <n-input v-model:value="paramsSearch.keyword" placeholder="搜索关键词" size="tiny" class="!rounded-lg text-xs" />
          </div>
          <div class="flex items-center gap-1.5 min-w-0 sm:col-span-2">
            <span class="text-[11px] text-zinc-400 w-10 shrink-0">page:</span>
            <n-input-number v-model:value="paramsSearch.page" :min="1" size="tiny" class="!rounded-lg text-xs flex-1" />
          </div>
        </div>

        <!-- detail 参数 -->
        <div v-else-if="activeAction === 'detail'" class="space-y-1.5">
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="text-[11px] text-zinc-400 w-8 shrink-0">url:</span>
            <n-input v-model:value="paramsDetail.url" placeholder="详情页相对或完整 URL" size="tiny" class="!rounded-lg text-xs" />
          </div>
        </div>

        <!-- parse 参数 -->
        <div v-else-if="activeAction === 'parse'" class="grid grid-cols-1 sm:grid-cols-3 gap-2">
          <div class="flex items-center gap-1.5 min-w-0 sm:col-span-2">
            <span class="text-[11px] text-zinc-400 w-8 shrink-0">url:</span>
            <n-input v-model:value="paramsParse.url" placeholder="解析目标直链 / 播放页 URL" size="tiny" class="!rounded-lg text-xs" />
          </div>
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="text-[11px] text-zinc-400 w-12 shrink-0">group:</span>
            <n-input v-model:value="paramsParse.groupName" placeholder="选集组名(可选)" size="tiny" class="!rounded-lg text-xs" />
          </div>
        </div>
      </div>

      <!-- 异常提示条 -->
      <div
        v-if="errorMessage"
        class="p-2.5 rounded-xl border border-rose-500/30 bg-rose-500/10 flex items-center justify-between gap-2 shrink-0"
      >
        <div class="flex items-center gap-2 min-w-0">
          <AlertCircle class="w-4 h-4 text-rose-500 shrink-0" />
          <span class="text-xs text-rose-700 dark:text-rose-300 font-medium truncate">{{ errorMessage }}</span>
        </div>
        <n-button
          size="tiny"
          type="error"
          secondary
          class="!rounded-lg !font-bold shrink-0 shadow-2xs"
          @click="triggerFixError"
        >
          <template #icon>
            <Sparkles class="w-3.5 h-3.5 text-rose-500" />
          </template>
          <span>由 AI 诊断修复</span>
        </n-button>
      </div>

      <!-- 结果视口顶栏与视图模式切换 -->
      <div class="flex items-center justify-between shrink-0 pt-0.5">
        <div class="flex items-center gap-2">
          <span class="text-xs font-bold text-zinc-800 dark:text-zinc-200">执行结果</span>
          <!-- 模式切换 Pills -->
          <div class="flex items-center p-0.5 rounded-lg bg-zinc-100 dark:bg-white/[0.04] border border-zinc-200/40 dark:border-white/5">
            <button
              type="button"
              class="px-2.5 py-0.5 text-[11px] font-medium rounded cursor-pointer transition-all"
              :class="viewMode === 'visual' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 font-bold shadow-2xs' : 'text-zinc-500'"
              @click="viewMode = 'visual'"
            >
              可视化预览
            </button>
            <button
              type="button"
              class="px-2.5 py-0.5 text-[11px] font-medium rounded cursor-pointer transition-all"
              :class="viewMode === 'json' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 font-bold shadow-2xs' : 'text-zinc-500'"
              @click="viewMode = 'json'"
            >
              JSON 数据
            </button>
            <button
              type="button"
              class="px-2.5 py-0.5 text-[11px] font-medium rounded cursor-pointer transition-all"
              :class="viewMode === 'logs' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 font-bold shadow-2xs' : 'text-zinc-500'"
              @click="viewMode = 'logs'"
            >
              沙箱日志 ({{ sandboxLogs.length }})
            </button>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <n-button
            v-if="rawResult"
            size="tiny"
            quaternary
            class="!rounded-lg text-[10px]"
            @click="copyJsonResult"
          >
            <template #icon>
              <Copy class="w-3 h-3" />
            </template>
            <span>复制 JSON</span>
          </n-button>
        </div>
      </div>

      <!-- 结果呈现区 (支持滚动与不同视图) -->
      <div class="flex-1 overflow-y-auto min-h-0 pr-1 space-y-3">
        <!-- 模式 A: 原始 JSON 视图 -->
        <div v-if="viewMode === 'json'" class="h-full">
          <pre class="p-3 rounded-xl bg-zinc-950 text-zinc-200 text-xs font-mono whitespace-pre-wrap break-all h-full overflow-y-auto">{{ jsonOutput || '暂无运行结果数据' }}</pre>
        </div>

        <!-- 模式 B: 沙箱 Console 日志 -->
        <div v-else-if="viewMode === 'logs'" class="h-full">
          <div v-if="sandboxLogs.length === 0" class="h-full flex items-center justify-center text-xs text-zinc-400">
            沙箱未产生任何 console 输出
          </div>
          <div v-else class="p-2 space-y-1.5 bg-zinc-950 rounded-xl font-mono text-xs overflow-y-auto h-full relative">
            <div class="sticky top-0 z-10 flex items-center justify-between pb-1.5 mb-1.5 border-b border-zinc-800 bg-zinc-950/90 backdrop-blur-xs">
              <span class="text-[10px] text-zinc-400">输出日志 ({{ sandboxLogs.length }} 条)</span>
              <button
                type="button"
                class="text-[10px] text-zinc-400 hover:text-white flex items-center gap-1 cursor-pointer transition-colors"
                @click="clearLogs"
              >
                <Trash2 class="w-3 h-3" />
                <span>清空</span>
              </button>
            </div>
            <div
              v-for="(log, idx) in sandboxLogs"
              :key="idx"
              class="flex items-start gap-2 py-0.5 text-zinc-300"
            >
              <span class="text-[10px] text-zinc-500 shrink-0">{{ log.time }}</span>
              <span
                class="text-[9px] px-1 py-0.2 rounded font-bold uppercase shrink-0"
                :class="{
                  'bg-sky-500/20 text-sky-300': log.level === 'log' || log.level === 'info',
                  'bg-amber-500/20 text-amber-300': log.level === 'warn',
                  'bg-rose-500/20 text-rose-300': log.level === 'error'
                }"
              >
                {{ log.level }}
              </span>
              <pre class="flex-1 whitespace-pre-wrap break-all text-xs font-mono">{{ log.message }}</pre>
            </div>
          </div>
        </div>

      <!-- 模式 C: 可视化渲染视图 (重点) -->
      <div v-else class="space-y-3">
        <div v-if="!rawResult && !running" class="h-44 flex flex-col items-center justify-center text-zinc-400 text-xs gap-2">
          <Play class="w-8 h-8 opacity-20" />
          <span>点击上方「运行测试」按钮启动沙箱</span>
        </div>

        <!-- C.1 列表流网格卡片 (discovery / search) -->
        <div v-if="parsedVisualData?.items && parsedVisualData.items.length > 0" class="space-y-2">
          <!-- 分类/页签呈现 (若有) -->
          <div v-if="parsedVisualData.tabs && parsedVisualData.tabs.length > 0" class="flex flex-wrap items-center gap-1.5 pb-1">
            <span class="text-[10px] text-zinc-400 mr-0.5">页签:</span>
            <button
              v-for="(t, idx) in parsedVisualData.tabs"
              :key="idx"
              type="button"
              @click="handleSelectTab(t)"
              class="px-2 py-0.5 text-[10px] rounded-md transition-all cursor-pointer border"
              :class="
                (paramsDiscovery.tab === (typeof t === 'object' ? (t.title || t.url) : t))
                  ? 'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border-emerald-300 dark:border-emerald-800/50 font-bold shadow-2xs'
                  : 'bg-zinc-100 dark:bg-white/[0.06] text-zinc-600 dark:text-zinc-300 border-transparent hover:border-zinc-300 dark:hover:border-white/20'
              "
              title="点击选中此页签并立即重新运行"
            >
              {{ typeof t === 'object' ? (t.title || t.url) : t }}
            </button>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-2.5">
            <div
              v-for="(item, idx) in parsedVisualData.items"
              :key="idx"
              class="group flex flex-col rounded-xl overflow-hidden border border-zinc-200/70 dark:border-white/5 bg-white dark:bg-zinc-900/60 hover:shadow-md transition-all"
            >
              <!-- 封面图 -->
              <div class="relative aspect-[3/4] bg-zinc-100 dark:bg-zinc-800 overflow-hidden">
                <img
                  v-if="item.cover"
                  :src="item.cover"
                  referrerpolicy="no-referrer"
                  class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                  loading="lazy"
                />
                <div v-else class="w-full h-full flex items-center justify-center text-zinc-400 text-xs">
                  无封面
                </div>

                <span v-if="item.badge" class="absolute top-1 right-1 px-1.5 py-0.2 rounded text-[9px] font-bold bg-black/60 text-white backdrop-blur-xs">
                  {{ item.badge }}
                </span>
              </div>

              <!-- 标题与操作栏 -->
              <div class="p-2 space-y-1.5 flex-1 flex flex-col justify-between">
                <div>
                  <div class="text-xs font-bold text-zinc-800 dark:text-zinc-200 line-clamp-1" :title="item.title">
                    {{ item.title || '无标题' }}
                  </div>
                  <div v-if="item.desc" class="text-[10px] text-zinc-400 line-clamp-1 mt-0.5">
                    {{ item.desc }}
                  </div>
                </div>

                <div class="pt-1.5 space-y-1 border-t border-zinc-100 dark:border-white/5">
                  <div class="text-[9px] font-mono text-zinc-400 truncate" :title="item.url">
                    {{ item.url || '' }}
                  </div>
                  <button
                    type="button"
                    class="w-full py-1 px-1.5 rounded-lg text-[10px] font-bold text-emerald-600 dark:text-emerald-400 bg-emerald-50/80 dark:bg-emerald-950/40 hover:bg-emerald-500 hover:text-white transition-all flex items-center justify-center gap-0.5 cursor-pointer shadow-2xs"
                    @click="testDetailWithItem(item)"
                  >
                    <span>测试详情</span>
                    <ChevronRight class="w-3 h-3" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- C.2 详情结构呈现 (detail) -->
        <div v-else-if="parsedVisualData?.isDetail" class="space-y-3">
          <!-- 媒体元信息卡片 -->
          <div class="flex gap-3 p-3 rounded-xl bg-zinc-50 dark:bg-zinc-900/40 border border-zinc-200/50 dark:border-white/5">
            <div class="w-20 aspect-[3/4] rounded-lg overflow-hidden shrink-0 bg-zinc-200 dark:bg-zinc-800">
              <img v-if="parsedVisualData.raw.cover" :src="parsedVisualData.raw.cover" referrerpolicy="no-referrer" class="w-full h-full object-cover" />
            </div>
            <div class="flex-1 space-y-1 text-xs min-w-0">
              <h3 class="font-bold text-sm text-zinc-900 dark:text-white truncate">{{ parsedVisualData.raw.title || '无标题' }}</h3>
              <div v-if="parsedVisualData.raw.author" class="text-zinc-500 text-[11px]">作者/演员: {{ parsedVisualData.raw.author }}</div>
              <div v-if="parsedVisualData.raw.tags" class="flex flex-wrap gap-1">
                <span v-for="tag in parsedVisualData.raw.tags" :key="tag" class="px-1.5 py-0.2 rounded text-[9px] bg-zinc-200/60 dark:bg-white/10 text-zinc-600 dark:text-zinc-300">
                  {{ tag }}
                </span>
              </div>
              <p v-if="parsedVisualData.raw.desc" class="text-zinc-400 text-[11px] line-clamp-3 leading-relaxed">
                {{ parsedVisualData.raw.desc }}
              </p>
            </div>
          </div>

          <!-- 视频播放直链测试结果 -->
          <div v-if="parsedVisualData.raw.playUrl" class="space-y-1.5">
            <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <Play class="w-3.5 h-3.5 text-emerald-500" />
              <span>播放器直出预览</span>
            </div>
            <div class="w-full aspect-video rounded-xl overflow-hidden bg-black shadow-lg">
              <art-player
                :url="parsedVisualData.raw.playUrl"
                :poster="parsedVisualData.raw.cover"
                :headers="parsedVisualData.raw.headers"
                class="w-full h-full"
              />
            </div>
          </div>

          <!-- 小说正文预览 -->
          <div v-if="parsedVisualData.raw.content" class="space-y-1.5">
            <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <FileText class="w-3.5 h-3.5 text-emerald-500" />
              <span>小说正文预览</span>
            </div>
            <div class="p-3 rounded-xl bg-amber-50/50 dark:bg-zinc-900 text-xs font-serif leading-loose whitespace-pre-wrap max-h-60 overflow-y-auto text-zinc-800 dark:text-zinc-200">
              {{ parsedVisualData.raw.content }}
            </div>
          </div>

          <!-- 选集线路列表 -->
          <div v-if="parsedVisualData.raw.groups && parsedVisualData.raw.groups.length > 0" class="space-y-2">
            <div v-for="(group, gIdx) in parsedVisualData.raw.groups" :key="gIdx" class="space-y-1.5">
              <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
                <Layers class="w-3.5 h-3.5 text-emerald-500" />
                <span>{{ group.name || `线路 ${Number(gIdx) + 1}` }}</span>
              </div>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="(ep, epIdx) in group.items"
                  :key="epIdx"
                  type="button"
                  class="px-2 py-1 text-xs rounded-lg bg-zinc-100 dark:bg-white/[0.06] hover:bg-emerald-500 hover:text-white transition-colors cursor-pointer text-zinc-700 dark:text-zinc-300 truncate max-w-[120px]"
                  :title="`${ep.title} (${ep.url})`"
                  @click="testParseWithEpisode(ep, group.name)"
                >
                  {{ ep.title }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- C.3 解析直链与正文呈现 (parse) -->
        <div v-else-if="parsedVisualData?.isParse" class="space-y-3">
          <div v-if="parsedVisualData.raw.playUrl" class="space-y-1.5">
            <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <Play class="w-3.5 h-3.5 text-emerald-500" />
              <span>解析视频播放测试</span>
            </div>
            <div class="w-full aspect-video rounded-xl overflow-hidden bg-black shadow-lg">
              <art-player
                :url="parsedVisualData.raw.playUrl"
                :headers="parsedVisualData.raw.headers"
                class="w-full h-full"
              />
            </div>
          </div>
          <div v-if="parsedVisualData.raw.content" class="space-y-1.5">
            <div class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <FileText class="w-3.5 h-3.5 text-emerald-500" />
              <span>小说正文解析测试</span>
            </div>
            <div class="p-3 rounded-xl bg-amber-50/50 dark:bg-zinc-900 text-xs font-serif leading-loose whitespace-pre-wrap max-h-72 overflow-y-auto text-zinc-800 dark:text-zinc-200">
              {{ parsedVisualData.raw.content }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
</template>
