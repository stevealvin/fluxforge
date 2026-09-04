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
  Layers,
  Sparkles
} from '@lucide/vue'

const props = defineProps<{
  code: string
  ruleType?: MediaType | string
  baseUrl?: string
}>()

const emit = defineEmits<{
  (e: 'logs', logs: any[]): void
  (e: 'fix-error', context: { action: RuleAction; actionParams: any; rawResult: any; errorMessage: string }): void
}>()

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

const paramsDiscovery = ref({ category: '', page: 1 })
const paramsSearch = ref({ keyword: '斗罗大陆', page: 1 })
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

  return {
    items,
    isDetail: activeAction.value === 'detail' || (r && typeof r === 'object' && (r.title || r.groups || r.playUrl)),
    isParse: activeAction.value === 'parse',
    categories: r && typeof r === 'object' && Array.isArray(r.categories) ? r.categories : [],
    raw: r
  }
})

// 执行沙箱动作
const executeAction = async (actionToRun?: RuleAction, overrideCode?: string) => {
  const targetAction = actionToRun || activeAction.value
  activeAction.value = targetAction

  const codeToRun = overrideCode || props.code
  if (!codeToRun || !codeToRun.trim()) {
    message.warning('请先输入或由 AI 生成规则脚本代码')
    return
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

defineExpose({
  executeAction,
  activeAction
})
</script>

<template>
  <div class="rounded-2xl border border-zinc-200/80 dark:border-white/5 bg-white/80 dark:bg-white/[0.02] p-3 space-y-3 shadow-xs flex-1 flex flex-col min-h-0">
    <!-- 测试控制栏与 Tab 切换 -->
    <div class="flex flex-wrap items-center justify-between gap-2 pb-2 border-b border-zinc-100 dark:border-white/5 shrink-0">
      <!-- 4 大动作 Tabs 切换 -->
      <div class="flex items-center p-0.5 rounded-xl bg-zinc-100/80 dark:bg-white/[0.04] border border-zinc-200/50 dark:border-white/5">
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
      </div>
    </div>

    <!-- 动态入参配置面板 -->
    <div class="p-2 rounded-xl bg-zinc-50/70 dark:bg-zinc-900/40 border border-zinc-200/40 dark:border-white/5 space-y-2 shrink-0">
      <!-- discovery 参数 -->
      <div v-if="activeAction === 'discovery'" class="grid grid-cols-2 gap-2">
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-12 shrink-0">category:</span>
          <n-input v-model:value="paramsDiscovery.category" placeholder="分类参数(可选)" size="tiny" class="!rounded-lg text-xs" />
        </div>
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-10 shrink-0">page:</span>
          <n-input-number v-model:value="paramsDiscovery.page" :min="1" size="tiny" class="!rounded-lg text-xs flex-1" />
        </div>
      </div>

      <!-- search 参数 -->
      <div v-else-if="activeAction === 'search'" class="grid grid-cols-2 gap-2">
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-12 shrink-0">keyword:</span>
          <n-input v-model:value="paramsSearch.keyword" placeholder="搜索关键词" size="tiny" class="!rounded-lg text-xs" />
        </div>
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-10 shrink-0">page:</span>
          <n-input-number v-model:value="paramsSearch.page" :min="1" size="tiny" class="!rounded-lg text-xs flex-1" />
        </div>
      </div>

      <!-- detail 参数 -->
      <div v-else-if="activeAction === 'detail'" class="space-y-1.5">
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-10 shrink-0">url:</span>
          <n-input v-model:value="paramsDetail.url" placeholder="详情页相对路径或完整 URL (如 /vod/detail-123.html)" size="tiny" class="!rounded-lg text-xs font-mono" />
        </div>
      </div>

      <!-- parse 参数 -->
      <div v-else-if="activeAction === 'parse'" class="grid grid-cols-2 gap-2">
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-10 shrink-0">url:</span>
          <n-input v-model:value="paramsParse.url" placeholder="选集相对路径或地址" size="tiny" class="!rounded-lg text-xs font-mono" />
        </div>
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-[11px] text-zinc-400 w-16 shrink-0">groupName:</span>
          <n-input v-model:value="paramsParse.groupName" placeholder="线路名 (如 默认线路)" size="tiny" class="!rounded-lg text-xs" />
        </div>
      </div>
    </div>

    <!-- 异常与报错横幅 + AI 诊断入口 -->
    <div
      v-if="errorMessage"
      class="p-2.5 rounded-xl bg-rose-50 dark:bg-rose-950/20 border border-rose-200 dark:border-rose-900/40 flex items-center justify-between gap-3 text-xs shrink-0 text-rose-700 dark:text-rose-300"
    >
      <div class="flex items-center gap-2 min-w-0">
        <AlertCircle class="w-4 h-4 shrink-0 text-rose-500" />
        <span class="font-mono truncate font-medium">{{ errorMessage }}</span>
      </div>
      <n-button
        type="error"
        size="tiny"
        secondary
        class="!rounded-lg shrink-0 font-bold"
        @click="triggerFixError"
      >
        <template #icon>
          <Sparkles class="w-3.5 h-3.5" />
        </template>
        <span>让 AI 修复此问题</span>
      </n-button>
    </div>

    <!-- 视图模式切换与展示控制栏 -->
    <div class="flex items-center justify-between pt-1 border-t border-zinc-100 dark:border-white/5 shrink-0">
      <div class="flex items-center gap-1">
        <span class="text-[11px] font-bold text-zinc-600 dark:text-zinc-400">输出模式:</span>
        <div class="flex items-center p-0.5 rounded-lg bg-zinc-100 dark:bg-white/[0.04]">
          <button
            type="button"
            class="px-2 py-0.5 text-[10px] font-medium rounded cursor-pointer"
            :class="viewMode === 'visual' ? 'bg-white dark:bg-zinc-800 text-emerald-600 font-bold shadow-2xs' : 'text-zinc-500'"
            @click="viewMode = 'visual'"
          >
            可视化
          </button>
          <button
            type="button"
            class="px-2 py-0.5 text-[10px] font-medium rounded cursor-pointer"
            :class="viewMode === 'json' ? 'bg-white dark:bg-zinc-800 text-emerald-600 font-bold shadow-2xs' : 'text-zinc-500'"
            @click="viewMode = 'json'"
          >
            JSON
          </button>
          <button
            type="button"
            class="px-2 py-0.5 text-[10px] font-medium rounded cursor-pointer"
            :class="viewMode === 'logs' ? 'bg-white dark:bg-zinc-800 text-emerald-600 font-bold shadow-2xs' : 'text-zinc-500'"
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
        <div v-else class="p-2 space-y-1.5 bg-zinc-950 rounded-xl font-mono text-xs overflow-y-auto h-full">
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
          <!-- 分类标签呈现 (若有) -->
          <div v-if="parsedVisualData.categories && parsedVisualData.categories.length > 0" class="flex flex-wrap gap-1.5 pb-1">
            <span
              v-for="(cat, idx) in parsedVisualData.categories"
              :key="idx"
              class="px-2 py-0.5 text-[10px] rounded-md bg-zinc-100 dark:bg-white/[0.06] text-zinc-600 dark:text-zinc-300"
            >
              {{ typeof cat === 'object' ? cat.title : cat }}
            </span>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
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
              <div class="p-2 space-y-1 flex-1 flex flex-col justify-between">
                <div class="text-xs font-bold text-zinc-800 dark:text-zinc-200 line-clamp-1" :title="item.title">
                  {{ item.title || '无标题' }}
                </div>
                <div v-if="item.desc" class="text-[10px] text-zinc-400 line-clamp-1">
                  {{ item.desc }}
                </div>

                <div class="pt-1.5 flex items-center justify-between border-t border-zinc-100 dark:border-white/5">
                  <span class="text-[9px] font-mono text-zinc-400 truncate max-w-[90px]" :title="item.url">
                    {{ item.url || '' }}
                  </span>
                  <button
                    type="button"
                    class="text-[10px] font-bold text-emerald-600 hover:text-emerald-700 dark:text-emerald-400 flex items-center gap-0.5 cursor-pointer"
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
</template>
