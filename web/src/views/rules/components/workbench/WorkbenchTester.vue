<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import type { RuleAction } from '@/types/rule'
import ArtPlayer from '@/components/ArtPlayer.vue'
import CodeEditor from '@/components/CodeEditor/index.vue'
import {
  Play,
  Compass,
  Search,
  FileText,
  Terminal,
  Clock,
  AlertCircle,
  ExternalLink,
  Layers,
  Sparkles
} from '@lucide/vue'

const props = defineProps<{
  code: string
  baseUrl?: string
}>()

const emit = defineEmits<{
  (e: 'startDiagnostic', info: { error?: string; logs?: any[]; code?: string }): void
  (e: 'logs', logs: any[]): void
}>()

const message = useMessage()

const activeAction = ref<RuleAction>('discovery')
const actionTabs = [
  { label: 'discovery', desc: '发现流', value: 'discovery' as RuleAction, icon: Compass },
  { label: 'search', desc: '搜索', value: 'search' as RuleAction, icon: Search },
  { label: 'detail', desc: '详情', value: 'detail' as RuleAction, icon: FileText },
  { label: 'parse', desc: '解析', value: 'parse' as RuleAction, icon: Terminal }
]

const paramsDiscovery = ref({ category: '', page: 1 })
const paramsSearch = ref({ keyword: '斗罗大陆', page: 1 })
const paramsDetail = ref({ key: '', item: null as any })
const paramsParse = ref({ key: '', groupName: '' })

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

// 智能归一化测试结果，自适应兼容各类数据结构
const parsedVisualData = computed(() => {
  if (!rawResult.value) return null
  const r = rawResult.value

  // 1. 列表类数据检测与标准化
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

  // 2. 视频/音频直链标准化
  let playUrl = ''
  if (typeof r === 'string' && (r.startsWith('http') || r.startsWith('//') || r.includes('.m3u8') || r.includes('.mp4'))) {
    playUrl = r
  } else if (r && typeof r === 'object') {
    const candidate = r.playUrl || r.url || r.videoUrl || r.link || r.src
    if (typeof candidate === 'string' && candidate.trim()) {
      playUrl = candidate.trim()
    }
  }

  // 3. 正文标准化 (小说/文章)
  let textContent = ''
  if (typeof r === 'string' && !playUrl) {
    textContent = r
  } else if (r && typeof r === 'object') {
    textContent = r.content || r.text || r.body || ''
  }

  // 4. 详情页标准化
  const isDetail = activeAction.value === 'detail' || (r && typeof r === 'object' && (r.title || r.groups || r.episodes || r.chapters))
  const title = r?.title || r?.name || ''
  const cover = r?.cover || r?.pic || r?.thumb || r?.image || r?.img || ''
  const desc = r?.desc || r?.description || r?.intro || r?.summary || ''
  const tags = Array.isArray(r?.tags) ? r.tags : Array.isArray(r?.categories) ? r.categories : []
  let groups: any[] = []
  if (Array.isArray(r?.groups)) {
    groups = r.groups
  } else if (Array.isArray(r?.episodes)) {
    groups = [{ name: '选集', items: r.episodes }]
  } else if (Array.isArray(r?.chapters)) {
    groups = [{ name: '章节', items: r.chapters }]
  }

  return {
    raw: r,
    items,
    isList: items !== null,
    itemCount: items ? items.length : 0,
    isDetail,
    title,
    cover,
    desc,
    tags,
    groups,
    playUrl,
    isPlayable: !!playUrl,
    textContent,
    hasTextContent: !!textContent
  }
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
  sandboxLogs.value = []

  const startTime = performance.now()

  let params: any = {}
  if (targetAction === 'discovery') {
    params = {
      category: paramsDiscovery.value.category || undefined,
      page: Number(paramsDiscovery.value.page) || 1
    }
  } else if (targetAction === 'search') {
    params = {
      keyword: paramsSearch.value.keyword || '',
      page: Number(paramsSearch.value.page) || 1
    }
  } else if (targetAction === 'detail') {
    params = {
      key: paramsDetail.value.key || '',
      url: paramsDetail.value.key || '',
      item: paramsDetail.value.item || undefined
    }
  } else if (targetAction === 'parse') {
    params = {
      key: paramsParse.value.key || '',
      url: paramsParse.value.key || '',
      groupName: paramsParse.value.groupName || undefined
    }
  }

  try {
    const res: any = await http.post('/rules/run', {
      code: props.code,
      action: targetAction,
      params,
      baseUrl: props.baseUrl
    })

    const duration = Math.round(performance.now() - startTime)
    executionTimeMs.value = duration

    if (Array.isArray(res?.logs)) {
      sandboxLogs.value = res.logs
      emit('logs', res.logs)
    }

    const targetResult = res?.result !== undefined ? res.result : res
    if (targetResult && !targetResult.message) {
      rawResult.value = targetResult
      statusCode.value = 200
      message.success(`${targetAction}() 执行成功 (${duration}ms)`)

      // 联动参数填充
      if (targetAction === 'discovery' || targetAction === 'search') {
        const items = targetResult.items || targetResult.list || (Array.isArray(targetResult) ? targetResult : null)
        if (Array.isArray(items) && items.length > 0 && !paramsDetail.value.key) {
          const first = items[0]
          paramsDetail.value.key = first.key || first.url || first.id || ''
          paramsDetail.value.item = first
        }
      } else if (targetAction === 'detail') {
        if (targetResult.groups?.length > 0 && targetResult.groups[0].items?.length > 0) {
          const firstGroup = targetResult.groups[0]
          const firstEp = firstGroup.items[0]
          paramsParse.value.key = firstEp.key || firstEp.url || ''
          paramsParse.value.groupName = firstGroup.name || ''
        }
      }
    } else {
      errorMessage.value = targetResult?.message || '沙箱执行未返回有效数据'
      statusCode.value = 500
      message.error(`${targetAction}() 执行异常`)
    }
  } catch (err: any) {
    executionTimeMs.value = Math.round(performance.now() - startTime)
    statusCode.value = err.response?.status || 500
    errorMessage.value = err.response?.data?.message || err.message || '运行请求失败'
    message.error(`沙箱执行失败: ${errorMessage.value}`)
  } finally {
    running.value = false
  }
}

// 串联运行所有生命周期动作
const runAllLifecycles = async () => {
  message.info('开始全流程生命周期串联测试...')
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
  message.success('串联测试流程完成')
}

const startDiagnosticFromTest = () => {
  emit('startDiagnostic', {
    error: errorMessage.value || (rawResult.value?.items?.length === 0 ? '返回列表条目为空 (items: 0)' : ''),
    logs: sandboxLogs.value,
    code: props.code
  })
}

defineExpose({
  executeAction,
  activeAction
})
</script>

<template>
  <div class="flex-1 flex flex-col min-h-0 h-full overflow-hidden gap-3">
    <!-- 顶部综合控制台 (Compact Test Controller) -->
    <div class="rounded-2xl border border-emerald-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] p-3 space-y-2.5 shadow-2xs shrink-0">
      <!-- 1. 动作方法选择器与操作按钮 -->
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center gap-1 p-0.5 bg-zinc-100 dark:bg-white/[0.06] rounded-xl border border-zinc-200/50 dark:border-white/5">
          <button
            v-for="tab in actionTabs"
            :key="tab.value"
            type="button"
            class="flex items-center gap-1 px-2.5 py-1 text-xs font-bold rounded-lg transition-all cursor-pointer"
            :class="activeAction === tab.value ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs border border-emerald-500/20' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
            @click="activeAction = tab.value"
          >
            <component :is="tab.icon" class="w-3 h-3" />
            <span>{{ tab.label }}</span>
          </button>
        </div>

        <div class="flex items-center gap-1.5 shrink-0">
          <n-button
            size="small"
            type="primary"
            class="!rounded-xl !font-bold shadow-md shadow-emerald-500/20 !bg-gradient-to-r !from-emerald-600 !via-teal-500 !to-cyan-500"
            :loading="running"
            @click="executeAction(activeAction)"
          >
            <template #icon>
              <Play class="w-3.5 h-3.5 fill-current" />
            </template>
            <span>运行 (Ctrl+R)</span>
          </n-button>

          <n-button
            size="small"
            secondary
            class="!rounded-xl text-xs font-semibold"
            :disabled="running"
            @click="runAllLifecycles"
            title="一键串联 (Discovery ➔ Detail ➔ Parse)"
          >
            <span>⚡ 串联</span>
          </n-button>
        </div>
      </div>

      <!-- 2. 精简动态参数栏 -->
      <div class="bg-zinc-50/80 dark:bg-white/[0.02] px-3 py-2 rounded-xl border border-emerald-100/50 dark:border-white/5 flex items-center gap-2">
        <!-- Discovery 参数 -->
        <template v-if="activeAction === 'discovery'">
          <div class="flex items-center gap-1 text-xs text-zinc-500 shrink-0 font-medium">
            <span>入参:</span>
          </div>
          <n-input
            v-model:value="paramsDiscovery.category"
            placeholder="分类 category (选填)"
            size="small"
            class="!rounded-lg text-xs flex-1"
          />
          <div class="w-24 shrink-0">
            <n-input-number
              v-model:value="paramsDiscovery.page"
              :min="1"
              size="small"
              placeholder="页码"
              class="!rounded-lg text-xs w-full"
            />
          </div>
        </template>

        <!-- Search 参数 -->
        <template v-else-if="activeAction === 'search'">
          <div class="flex items-center gap-1 text-xs text-zinc-500 shrink-0 font-medium">
            <span>关键词:</span>
          </div>
          <n-input
            v-model:value="paramsSearch.keyword"
            placeholder="输入搜索词..."
            size="small"
            class="!rounded-lg text-xs flex-1"
            @keyup.enter="executeAction('search')"
          />
          <div class="w-24 shrink-0">
            <n-input-number
              v-model:value="paramsSearch.page"
              :min="1"
              size="small"
              placeholder="页码"
              class="!rounded-lg text-xs w-full"
            />
          </div>
        </template>

        <!-- Detail 参数 -->
        <template v-else-if="activeAction === 'detail'">
          <div class="flex items-center gap-1 text-xs text-zinc-500 shrink-0 font-medium">
            <span>项目标识:</span>
          </div>
          <n-input
            v-model:value="paramsDetail.key"
            placeholder="/detail/123 或完整 URL 链接"
            size="small"
            class="!rounded-lg text-xs font-mono flex-1"
            @keyup.enter="executeAction('detail')"
          />
        </template>

        <!-- Parse 参数 -->
        <template v-else-if="activeAction === 'parse'">
          <div class="flex items-center gap-1 text-xs text-zinc-500 shrink-0 font-medium">
            <span>解析键:</span>
          </div>
          <n-input
            v-model:value="paramsParse.key"
            placeholder="分集 Key 或直链"
            size="small"
            class="!rounded-lg text-xs font-mono flex-1"
            @keyup.enter="executeAction('parse')"
          />
          <n-input
            v-model:value="paramsParse.groupName"
            placeholder="线路名 (可选)"
            size="small"
            class="!rounded-lg text-xs w-28 shrink-0"
          />
        </template>
      </div>
    </div>

    <!-- 下栏：多功能测试结果视口 (Results Viewport) -->
    <div class="flex-1 flex flex-col min-h-0 rounded-2xl overflow-hidden border border-emerald-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] shadow-2xs">
      <!-- 状态指标栏与视图切换 -->
      <div class="px-3.5 py-2 border-b border-emerald-100/50 dark:border-white/5 flex items-center justify-between gap-2 bg-zinc-50/80 dark:bg-white/[0.02] shrink-0">
        <!-- 运行指标 -->
        <div class="flex items-center gap-2 min-w-0">
          <span
            v-if="statusCode"
            class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full flex items-center gap-1"
            :class="statusCode === 200 ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 border border-emerald-500/30' : 'bg-rose-500/15 text-rose-600 border border-rose-500/30'"
          >
            <span class="w-1.5 h-1.5 rounded-full" :class="statusCode === 200 ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'"></span>
            <span>HTTP {{ statusCode }}</span>
          </span>

          <span v-if="executionTimeMs !== null" class="text-[11px] font-mono text-zinc-400 flex items-center gap-1">
            <Clock class="w-3 h-3 text-zinc-400" />
            <span>{{ executionTimeMs }}ms</span>
          </span>

          <span v-if="rawResult?.items" class="text-[11px] font-mono text-emerald-600 dark:text-emerald-400 font-bold truncate">
            ({{ rawResult.items.length }} 项)
          </span>
        </div>

        <!-- 视图切换与诊断入口 -->
        <div class="flex items-center gap-1.5 shrink-0">
          <n-button
            v-if="errorMessage || (rawResult && (!rawResult.items || rawResult.items.length === 0))"
            size="tiny"
            type="warning"
            secondary
            class="!rounded-lg !font-bold text-[10px]"
            @click="startDiagnosticFromTest"
          >
            <template #icon>
              <Sparkles class="w-3 h-3 text-amber-500" />
            </template>
            <span>AI 诊断</span>
          </n-button>

          <div class="flex items-center gap-0.5 p-0.5 bg-zinc-200/60 dark:bg-white/10 rounded-xl">
            <button
              type="button"
              class="px-2.5 py-1 text-xs rounded-lg transition-all cursor-pointer font-medium"
              :class="viewMode === 'visual' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
              @click="viewMode = 'visual'"
            >
              视觉
            </button>
            <button
              type="button"
              class="px-2.5 py-1 text-xs rounded-lg transition-all font-mono cursor-pointer font-medium"
              :class="viewMode === 'json' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
              @click="viewMode = 'json'"
            >
              JSON
            </button>
            <button
              type="button"
              class="px-2.5 py-1 text-xs rounded-lg transition-all font-mono flex items-center gap-1 cursor-pointer font-medium"
              :class="viewMode === 'logs' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs font-bold' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
              @click="viewMode = 'logs'"
            >
              <span>日志</span>
              <span v-if="sandboxLogs.length > 0" class="px-1 text-[9px] rounded-full bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 font-mono font-bold">
                {{ sandboxLogs.length }}
              </span>
            </button>
          </div>
        </div>
      </div>

      <!-- 渲染视口主体 -->
      <div class="flex-1 min-h-0 overflow-y-auto p-3.5 relative">
        <!-- 1. 控制台日志视图 -->
        <div v-if="viewMode === 'logs'" class="h-full flex flex-col p-3 bg-zinc-950 rounded-xl overflow-hidden font-mono text-xs text-zinc-100 border border-zinc-800">
          <div v-if="sandboxLogs.length === 0" class="flex-1 flex flex-col items-center justify-center text-zinc-400 gap-2">
            <Terminal class="w-8 h-8 text-emerald-500/40" />
            <p class="font-medium text-zinc-200">暂无沙箱控制台日志输出</p>
            <p class="text-[11px] text-zinc-400">在规则代码中写入 <code class="text-emerald-400 font-bold">console.log(...)</code>，运行后将在此高亮显示</p>
          </div>
          <div v-else class="flex-1 overflow-y-auto space-y-1.5 p-1 selection:bg-emerald-500/40">
            <div
              v-for="(log, idx) in sandboxLogs"
              :key="idx"
              class="flex items-start gap-2 py-1 border-b border-white/[0.06] last:border-0 hover:bg-white/[0.04] px-1.5 rounded transition-colors"
            >
              <span class="text-[11px] text-zinc-400 shrink-0 select-none">[{{ log.time }}]</span>
              <span
                class="text-[9px] px-1.5 py-0.2 rounded uppercase font-bold shrink-0 select-none border"
                :class="{
                  'bg-sky-500/20 text-sky-300 border-sky-500/30': log.level === 'log' || log.level === 'info',
                  'bg-amber-500/20 text-amber-300 border-amber-500/30': log.level === 'warn',
                  'bg-rose-500/20 text-rose-300 border-rose-500/30': log.level === 'error'
                }"
              >
                {{ log.level }}
              </span>
              <pre
                class="flex-1 whitespace-pre-wrap break-all text-xs font-mono"
                :class="{
                  'text-rose-300 font-bold': log.level === 'error',
                  'text-amber-200': log.level === 'warn',
                  'text-zinc-100': log.level !== 'error' && log.level !== 'warn'
                }"
              >{{ log.message }}</pre>
            </div>
          </div>
        </div>

        <!-- 2. 错误提示卡片 -->
        <div v-else-if="errorMessage" class="p-4 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-600 dark:text-rose-400 space-y-2">
          <div class="flex items-center gap-2 font-bold text-sm">
            <AlertCircle class="w-4 h-4 text-rose-500" />
            <span>沙箱执行报错</span>
          </div>
          <pre class="text-xs font-mono whitespace-pre-wrap leading-relaxed">{{ errorMessage }}</pre>
        </div>

        <!-- 3. JSON 代码视图 -->
        <div v-else-if="viewMode === 'json'" class="h-full rounded-xl overflow-hidden border border-zinc-200/50 dark:border-white/5">
          <code-editor
            :model-value="jsonOutput"
            model-id="sandbox_json_output"
            height="100%"
            readonly
            class="w-full h-full"
          />
        </div>

        <!-- 4. 视觉化媒体渲染视图 -->
        <div v-else-if="parsedVisualData" class="space-y-4">
          <!-- 4.1 列表视图 (discovery / search) -->
          <div v-if="parsedVisualData.isList" class="space-y-3">
            <!-- 分类标签 -->
            <div v-if="parsedVisualData.tags?.length > 0" class="flex flex-wrap gap-1.5 pb-2 border-b border-zinc-200/50 dark:border-white/5">
              <span
                v-for="cat in parsedVisualData.tags"
                :key="typeof cat === 'string' ? cat : cat?.title || cat?.name"
                class="px-2.5 py-0.5 text-xs rounded-lg bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 font-medium"
              >
                {{ typeof cat === 'string' ? cat : cat?.title || cat?.name }}
              </span>
            </div>

            <!-- 列表有项目 -->
            <div v-if="parsedVisualData.items && parsedVisualData.items.length > 0" class="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
              <div
                v-for="(item, idx) in parsedVisualData.items"
                :key="idx"
                class="p-2 rounded-xl border border-zinc-200/50 dark:border-white/5 bg-white/80 dark:bg-white/[0.03] space-y-1.5 group cursor-pointer hover:border-emerald-500/50 hover:shadow-md transition-all"
                @click="paramsDetail.key = item.key || item.url || item.id || ''; paramsDetail.item = item; activeAction = 'detail'"
                :title="`点击测试该项目的 detail() 详情`"
              >
                <div class="aspect-[3/4] rounded-lg bg-zinc-100 dark:bg-zinc-800 overflow-hidden relative shadow-2xs">
                  <img
                    v-if="item.cover || item.pic || item.thumb || item.url || item.image || item.img"
                    :src="item.cover || item.pic || item.thumb || item.url || item.image || item.img"
                    class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                    loading="lazy"
                    referrerpolicy="no-referrer"
                  />
                  <div v-else class="w-full h-full flex items-center justify-center text-zinc-400 text-xs">
                    暂无封面
                  </div>
                  <span v-if="item.badge || item.status" class="absolute top-1 right-1 px-1.5 py-0.5 text-[9px] font-bold rounded bg-black/70 text-white backdrop-blur-xs">
                    {{ item.badge || item.status }}
                  </span>
                </div>
                <div class="min-w-0">
                  <h4 class="text-xs font-bold text-zinc-900 dark:text-white truncate" :title="item.title || item.name">
                    {{ item.title || item.name || `项目 #${idx + 1}` }}
                  </h4>
                  <p v-if="item.desc || item.latest || item.author || item.subTitle" class="text-[10px] text-zinc-400 truncate">
                    {{ item.desc || item.latest || item.author || item.subTitle }}
                  </p>
                </div>
              </div>
            </div>

            <!-- 列表为空的友好提示 -->
            <div v-else class="p-6 rounded-2xl border border-amber-200/60 dark:border-amber-800/40 bg-amber-50/50 dark:bg-amber-950/20 text-center space-y-2">
              <AlertCircle class="w-8 h-8 text-amber-500 mx-auto" />
              <h4 class="text-xs font-bold text-amber-800 dark:text-amber-200">未解析到任何列表条目 (items: 0)</h4>
              <p class="text-[11px] text-zinc-500 dark:text-zinc-400 max-w-xs mx-auto leading-relaxed">
                规则代码已执行成功，但返回的 items 为空数组。请在中间编辑器检查选择器是否正确，或点击下方按钮排查。
              </p>
              <div class="flex items-center justify-center gap-2 pt-1">
                <n-button size="tiny" secondary @click="viewMode = 'json'">查看 JSON 原始返回</n-button>
                <n-button size="tiny" secondary @click="viewMode = 'logs'">查看控制台日志</n-button>
                <n-button size="tiny" type="warning" @click="startDiagnosticFromTest">🩺 发起 AI 诊断</n-button>
              </div>
            </div>
          </div>

          <!-- 4.2 详情页渲染 (detail) -->
          <div v-else-if="parsedVisualData.isDetail" class="space-y-4">
            <div class="flex gap-3 bg-white/60 dark:bg-white/[0.02] p-3 rounded-2xl border border-emerald-100/50 dark:border-white/5">
              <img
                v-if="parsedVisualData.cover"
                :src="parsedVisualData.cover"
                class="w-24 aspect-[3/4] rounded-xl object-cover shadow-sm shrink-0"
                referrerpolicy="no-referrer"
              />
              <div class="space-y-1.5 flex-1 min-w-0">
                <h2 class="text-sm font-black text-zinc-900 dark:text-white truncate">
                  {{ parsedVisualData.title || '无标题详情' }}
                </h2>
                <div v-if="parsedVisualData.tags?.length > 0" class="flex flex-wrap gap-1">
                  <span v-for="tag in parsedVisualData.tags" :key="tag" class="px-1.5 py-0.2 text-[10px] rounded-md bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 font-bold">
                    {{ typeof tag === 'string' ? tag : tag?.name }}
                  </span>
                </div>
                <p class="text-[11px] text-zinc-600 dark:text-zinc-400 leading-relaxed line-clamp-3">
                  {{ parsedVisualData.desc || '暂无简介' }}
                </p>
              </div>
            </div>

            <!-- 选集线路列表 -->
            <div v-if="parsedVisualData.groups?.length > 0" class="space-y-2.5 pt-2 border-t border-zinc-200/50 dark:border-white/5">
              <div v-for="(grp, gIdx) in parsedVisualData.groups" :key="gIdx" class="space-y-1.5">
                <h4 class="text-xs font-bold text-zinc-800 dark:text-zinc-200">
                  {{ grp.name || `线路 ${Number(gIdx) + 1}` }}
                </h4>
                <div class="flex flex-wrap gap-1.5 max-h-48 overflow-y-auto">
                  <button
                    v-for="(ep, eIdx) in grp.items"
                    :key="eIdx"
                    type="button"
                    class="px-2.5 py-1 text-xs rounded-lg border border-zinc-200/60 dark:border-white/5 bg-white/50 dark:bg-white/[0.02] hover:bg-emerald-500/15 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors cursor-pointer"
                    @click="paramsParse.key = ep.key || ep.url || ''; paramsParse.groupName = grp.name; activeAction = 'parse'"
                    :title="`点击测试该剧集的 parse() 解析`"
                  >
                    {{ ep.title || ep.name || `第 ${Number(eIdx) + 1} 集` }}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- 4.3 播放 / 正文解析页渲染 (parse) -->
          <div v-else-if="parsedVisualData.isPlayable || parsedVisualData.hasTextContent" class="space-y-3">
            <!-- 视频播放器 -->
            <div v-if="parsedVisualData.playUrl" class="space-y-2">
              <div class="flex items-center justify-between text-[11px] font-mono text-zinc-500">
                <span class="truncate max-w-xs">直链: {{ parsedVisualData.playUrl }}</span>
              </div>
              <div class="w-full aspect-video rounded-2xl overflow-hidden bg-black shadow-lg">
                <ArtPlayer :url="parsedVisualData.playUrl" />
              </div>
            </div>

            <!-- 小说正文 -->
            <div v-if="parsedVisualData.textContent" class="p-4 rounded-2xl bg-zinc-50 dark:bg-white/[0.02] border border-zinc-200/50 dark:border-white/5 leading-relaxed text-xs text-zinc-800 dark:text-zinc-200 whitespace-pre-wrap font-serif max-h-80 overflow-y-auto">
              {{ parsedVisualData.textContent }}
            </div>
          </div>

          <!-- 4.4 兜底：未能匹配标准结构的数据，展示格式化摘要 -->
          <div v-else class="p-4 rounded-2xl border border-zinc-200/50 dark:border-white/5 bg-zinc-50/50 dark:bg-white/[0.02] space-y-2 font-mono text-xs">
            <div class="flex items-center justify-between text-zinc-700 dark:text-zinc-200 font-bold">
              <span>返回值格式摘要</span>
              <button type="button" class="text-emerald-600 dark:text-emerald-400 hover:underline" @click="viewMode = 'json'">查看完整 JSON</button>
            </div>
            <pre class="text-zinc-700 dark:text-zinc-300 whitespace-pre-wrap max-h-60 overflow-y-auto">{{ JSON.stringify(parsedVisualData.raw, null, 2) }}</pre>
          </div>
        </div>

        <!-- 空白状态 (未执行测试) -->
        <div v-else class="h-full flex flex-col items-center justify-center text-center p-8 space-y-2 text-zinc-400">
          <Play class="w-8 h-8 opacity-40 text-emerald-500/50" />
          <span class="text-xs font-medium text-zinc-300">点击上方「运行」按钮启动沙箱测试</span>
          <span class="text-[11px] text-zinc-500">快捷键：<kbd class="px-1.5 py-0.5 bg-zinc-800 rounded-md border border-zinc-700 text-zinc-300 font-mono">Ctrl+R</kbd></span>
        </div>
      </div>
    </div>
  </div>
</template>
