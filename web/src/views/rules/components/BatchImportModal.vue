<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import { useAiSettingsStore } from '@/stores/aiSettings'
import { ruleService } from '@/utils/ruleService'
import http from '@/utils/http'
import {
  parseExternalSources,
  buildSingleRuleTranslatePrompt,
  type ParsedSourceItem
} from '@/utils/sourceParser'
import {
  Sparkles,
  Download,
  Upload,
  Play,
  Pause,
  RotateCcw,
  CheckCircle2,
  XCircle,
  Clock,
  Code,
  FileText,
  Globe,
  RefreshCw,
  AlertCircle,
  Layers,
  Copy,
  ChevronRight,
  ExternalLink
} from '@lucide/vue'

const props = defineProps<{
  show: boolean
}>()

const emit = defineEmits<{
  (e: 'update:show', val: boolean): void
  (e: 'saved'): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

// 输入方式与解析状态
const inputTab = ref<'url' | 'text'>('url')
const subscriptionUrl = ref('')
const rawText = ref('')
const fetchingUrl = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)

// 待处理列表
const sourceItems = ref<ParsedSourceItem[]>([])

// 并发与执行控制
const concurrency = ref(2)
const isTranslating = ref(false)
const isPaused = ref(false)
const queueRunningCount = ref(0)
const stopRequested = ref(false)

// 批量覆盖类型设置
const globalTypeOverride = ref<'keep' | 'video' | 'novel' | 'picture'>('keep')

// 抽屉代码预览
const showCodeDrawer = ref(false)
const activePreviewItem = ref<ParsedSourceItem | null>(null)

// 导入保存中状态
const savingRules = ref(false)

// 统计信息
const stats = computed(() => {
  const total = sourceItems.value.length
  const selected = sourceItems.value.filter((i) => i.selected).length
  const success = sourceItems.value.filter(
    (i) => i.selected && (i.status === 'success' || i.status === 'native_ready')
  ).length
  const failed = sourceItems.value.filter((i) => i.selected && i.status === 'failed').length
  const translating = sourceItems.value.filter((i) => i.status === 'translating').length
  const pending = sourceItems.value.filter((i) => i.selected && i.status === 'pending').length
  const progress = selected > 0 ? Math.round((success / selected) * 100) : 0

  return { total, selected, success, failed, translating, pending, progress }
})

// 全选/取消全选状态
const isAllSelected = computed({
  get: () =>
    sourceItems.value.length > 0 && sourceItems.value.every((i) => i.selected),
  set: (val: boolean) => {
    sourceItems.value.forEach((i) => (i.selected = val))
  }
})

// 从远程拉取订阅源
const handleFetchSubscription = async () => {
  const url = subscriptionUrl.value.trim()
  if (!url) {
    message.warning('请输入有效的订阅源链接')
    return
  }

  fetchingUrl.value = true
  try {
    const res: any = await http.post('/rules/fetch-page', { url })
    const content = res?.data || res?.content || (typeof res === 'string' ? res : JSON.stringify(res))

    if (!content) {
      throw new Error('未获取到有效内容')
    }

    processParsedContent(content)
    message.success(`成功获取并解析出 ${sourceItems.value.length} 个规则条目`)
  } catch (err: any) {
    console.error('拉取订阅失败:', err)
    message.error(`拉取订阅源失败: ${err.message || '网络连接超时或目标地址无效'}`)
  } finally {
    fetchingUrl.value = false
  }
}

// 解析文本框内容
const handleParseRawText = () => {
  if (!rawText.value.trim()) {
    message.warning('请先粘贴规则源数据')
    return
  }
  try {
    processParsedContent(rawText.value)
    message.success(`成功解析出 ${sourceItems.value.length} 个规则条目`)
  } catch (err: any) {
    message.error(err.message || '解析失败，请检查数据格式')
  }
}

// 处理上传文件
const triggerFileUpload = () => {
  fileInputRef.value?.click()
}

const handleFileSelected = (e: Event) => {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return

  const reader = new FileReader()
  reader.onload = (event) => {
    const text = event.target?.result as string
    if (text) {
      try {
        processParsedContent(text)
        message.success(`成功从文件加载并解析出 ${sourceItems.value.length} 个规则条目`)
      } catch (err: any) {
        message.error(`解析文件失败: ${err.message}`)
      }
    }
  }
  reader.readAsText(file)
  if (fileInputRef.value) fileInputRef.value.value = ''
}

// 统一解析并填充数据
const processParsedContent = (raw: string) => {
  const items = parseExternalSources(raw)
  if (items.length === 0) {
    throw new Error('未能在该数据中识别出任何有效的规则配置或书源条目')
  }
  sourceItems.value = items
}

// 批量修改分类
const handleApplyGlobalType = (typeVal: 'keep' | 'video' | 'novel' | 'picture') => {
  globalTypeOverride.value = typeVal
  if (typeVal === 'keep') return
  sourceItems.value.forEach((item) => {
    if (item.selected) {
      item.type = typeVal
      if (item.resultRule) {
        item.resultRule.type = typeVal
      }
    }
  })
  message.info(`已将选中项类型统一设为: ${typeVal === 'novel' ? '小说' : typeVal === 'video' ? '视频' : '图片'}`)
}

// 清空当前列表
const handleClearAll = () => {
  if (isTranslating.value) {
    message.warning('请先暂停或停止转译任务')
    return
  }
  sourceItems.value = []
}

// ==========================================
// 前端并发队列执行调度 (Worker Queue)
// ==========================================

const startTranslation = async () => {
  if (stats.value.selected === 0) {
    message.warning('请先勾选需要转译的规则条目')
    return
  }

  if (!aiStore.activeProfile?.baseUrl) {
    message.error('请先在系统设置中配置 AI 模型的 API 接口')
    return
  }

  isTranslating.value = true
  isPaused.value = false
  stopRequested.value = false

  // 将所有选中的待处理或失败项标为 pending
  sourceItems.value.forEach((item) => {
    if (item.selected && (item.status === 'idle' || item.status === 'failed')) {
      item.status = 'pending'
      item.error = undefined
    }
  })

  // 启动并发池工作流
  runConcurrentQueue()
}

const pauseTranslation = () => {
  isPaused.value = true
}

const resumeTranslation = () => {
  isPaused.value = false
  runConcurrentQueue()
}

const stopTranslation = () => {
  stopRequested.value = true
  isTranslating.value = false
  isPaused.value = false
  sourceItems.value.forEach((i) => {
    if (i.status === 'pending') i.status = 'idle'
  })
}

// 核心并发执行器
const runConcurrentQueue = () => {
  const maxWorkers = Math.max(1, Math.min(4, concurrency.value))

  const tryDispatchNext = () => {
    if (stopRequested.value || isPaused.value) return

    while (queueRunningCount.value < maxWorkers) {
      const nextItem = sourceItems.value.find(
        (i) => i.selected && i.status === 'pending'
      )
      if (!nextItem) {
        // 无待处理项，检查是否所有 worker 已退出
        if (queueRunningCount.value === 0) {
          isTranslating.value = false
          if (!stopRequested.value && !isPaused.value) {
            message.success(`转译执行完毕！成功 ${stats.value.success} 个，失败 ${stats.value.failed} 个`)
          }
        }
        break
      }

      // 派发任务
      queueRunningCount.value++
      executeSingleTranslation(nextItem).finally(() => {
        queueRunningCount.value--
        tryDispatchNext()
      })
    }
  }

  tryDispatchNext()
}

// 执行单条源转译
const executeSingleTranslation = async (item: ParsedSourceItem) => {
  // 原生规则直接就绪，无需调用大模型
  if (item.format === 'native' && item.resultRule) {
    item.status = 'native_ready'
    return
  }

  item.status = 'translating'
  item.error = undefined

  try {
    const { systemPrompt, userPrompt } = buildSingleRuleTranslatePrompt(item)
    const rawOutput = await aiStore.callLlm({
      systemPrompt,
      userPrompt,
      jsonMode: true
    })

    // 清洗并提取 JSON
    let jsonStr = rawOutput.trim()
    const jsonMatch = jsonStr.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)
    if (jsonMatch && jsonMatch[1]) {
      jsonStr = jsonMatch[1].trim()
    }

    const resObj = JSON.parse(jsonStr)
    if (!resObj.code || typeof resObj.code !== 'string') {
      throw new Error('AI 未能生成有效的代码内容 (缺少 code 字段)')
    }

    // 简单校验 defineRule
    if (!resObj.code.includes('defineRule')) {
      throw new Error('生成的代码不符合 FluxForge 规范 (未找到 defineRule 导出)')
    }

    item.resultRule = {
      name: resObj.name || item.name,
      baseUrl: resObj.baseUrl || item.baseUrl,
      type: (resObj.type as any) || item.type,
      code: resObj.code,
      description: resObj.description || `转译自 ${item.formatLabel}`
    }
    item.status = 'success'
  } catch (err: any) {
    console.error(`转译 [${item.name}] 失败:`, err)
    item.status = 'failed'
    item.error = err.message || '转译异常'
  }
}

// 单独重试某一项
const handleRetrySingle = (item: ParsedSourceItem) => {
  item.status = 'pending'
  item.error = undefined
  if (!isTranslating.value) {
    isTranslating.value = true
    isPaused.value = false
    stopRequested.value = false
    runConcurrentQueue()
  }
}

// 预览代码
const handlePreviewCode = (item: ParsedSourceItem) => {
  activePreviewItem.value = item
  showCodeDrawer.value = true
}

const copyPreviewCode = () => {
  if (!activePreviewItem.value?.resultRule?.code) return
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(activePreviewItem.value.resultRule.code)
    message.success('规则代码已复制到剪贴板')
  }
}

// 批量保存入库
const handleBatchSave = async () => {
  const readyItems = sourceItems.value.filter(
    (i) => i.selected && (i.status === 'success' || i.status === 'native_ready') && i.resultRule
  )

  if (readyItems.length === 0) {
    message.warning('当前没有转译成功的规则可供入库')
    return
  }

  savingRules.value = true
  let savedCount = 0

  try {
    for (const item of readyItems) {
      if (!item.resultRule) continue
      await ruleService.saveRule({
        name: item.resultRule.name,
        baseUrl: item.resultRule.baseUrl,
        type: item.resultRule.type,
        code: item.resultRule.code,
        description: item.resultRule.description,
        enabled: 1
      })
      savedCount++
    }

    message.success(`成功入库 ${savedCount} 条新规则！`)
    emit('saved')
    emit('update:show', false)
  } catch (err: any) {
    console.error('批量入库失败:', err)
    message.error(`入库过程中发生错误: ${err.message}`)
  } finally {
    savingRules.value = false
  }
}
</script>

<template>
  <n-modal
    :show="props.show"
    preset="card"
    class="max-w-4xl w-[94vw] !rounded-3xl shadow-2xl border border-zinc-200/80 dark:border-zinc-800/80 backdrop-blur-xl"
    :segmented="{ content: 'soft', footer: 'soft' }"
    @update:show="(val: boolean) => emit('update:show', val)"
  >
    <template #header>
      <div class="flex items-center gap-3">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-amber-500 via-orange-500 to-rose-500 text-white flex items-center justify-center shadow-md shadow-amber-500/20">
          <Sparkles class="w-4 h-4" />
        </div>
        <div>
          <div class="text-sm font-black tracking-tight text-zinc-900 dark:text-white flex items-center gap-2">
            <span>AI 批量转译与规则导入</span>
            <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
              SMART INGEST
            </span>
          </div>
          <p class="text-[11px] text-zinc-500 dark:text-zinc-400 mt-0.5">
            输入阅读 3.0 书源、TVBox 影视配置或订阅链接，自动解构并发转译为标准规则
          </p>
        </div>
      </div>
    </template>

    <div class="space-y-4">
      <!-- 步骤一：数据输入区 (若已有解析数据则支持折叠/清空) -->
      <div v-if="sourceItems.length === 0" class="space-y-3">
        <n-tabs v-model:value="inputTab" type="segment" animated size="small" class="w-full">
          <n-tab-pane name="url" tab="方式一：规则订阅链接 (HTTP URL)">
            <div class="space-y-2 pt-2">
              <div class="flex gap-2">
                <n-input
                  v-model:value="subscriptionUrl"
                  placeholder="输入公开规则订阅链接，如: https://example.com/legado_sources.json"
                  class="!rounded-xl"
                  :disabled="fetchingUrl"
                  @keydown.enter="handleFetchSubscription"
                >
                  <template #prefix>
                    <Globe class="w-4 h-4 text-zinc-400 mr-1" />
                  </template>
                </n-input>
                <n-button
                  type="primary"
                  class="!rounded-xl !font-bold px-4 shrink-0"
                  :loading="fetchingUrl"
                  @click="handleFetchSubscription"
                >
                  <template #icon>
                    <Download class="w-4 h-4" />
                  </template>
                  <span>拉取并解析</span>
                </n-button>
              </div>
              <p class="text-[11px] text-zinc-400 flex items-center gap-1">
                <AlertCircle class="w-3.5 h-3.5 text-zinc-400 shrink-0" />
                <span>由服务端代理抓取，自动穿透浏览器 CORS 限制并支持 Base64 与 GBK/UTF-8 自动转码</span>
              </p>
            </div>
          </n-tab-pane>

          <n-tab-pane name="text" tab="方式二：粘贴 JSON 文本或上传文件">
            <div class="space-y-2 pt-2">
              <n-input
                v-model:value="rawText"
                type="textarea"
                placeholder="在此粘贴阅读 3.0 书源数组、TVBox sites 配置或通用规则 JSON..."
                :rows="6"
                class="!rounded-xl font-mono text-xs"
              />
              <div class="flex items-center justify-between gap-2">
                <input
                  type="file"
                  ref="fileInputRef"
                  accept=".json,.txt"
                  class="hidden"
                  @change="handleFileSelected"
                />
                <n-button
                  dashed
                  size="small"
                  class="!rounded-xl !text-xs text-zinc-500"
                  @click="triggerFileUpload"
                >
                  <template #icon>
                    <Upload class="w-3.5 h-3.5" />
                  </template>
                  <span>选择本地 .json / .txt 文件</span>
                </n-button>

                <n-button
                  type="primary"
                  size="small"
                  class="!rounded-xl !font-bold px-4"
                  @click="handleParseRawText"
                >
                  <span>解析数据源</span>
                </n-button>
              </div>
            </div>
          </n-tab-pane>
        </n-tabs>
      </div>

      <!-- 步骤二：解析结果表格与任务队列控制区 -->
      <div v-else class="space-y-3">
        <!-- 顶部工具条：统计、操作与并发配置 -->
        <div class="flex flex-wrap items-center justify-between gap-3 p-3 rounded-2xl bg-zinc-50 dark:bg-zinc-900/60 border border-zinc-200/60 dark:border-zinc-800/60">
          <!-- 统计指示 -->
          <div class="flex items-center gap-3">
            <n-checkbox v-model:checked="isAllSelected" :disabled="isTranslating">
              <span class="text-xs font-bold text-zinc-700 dark:text-zinc-200">
                已选 {{ stats.selected }} / {{ stats.total }} 项
              </span>
            </n-checkbox>

            <div class="flex items-center gap-1 text-[11px] font-medium">
              <span v-if="stats.success > 0" class="text-emerald-600 dark:text-emerald-400 flex items-center gap-0.5">
                <CheckCircle2 class="w-3 h-3" /> {{ stats.success }} 成功
              </span>
              <span v-if="stats.failed > 0" class="text-rose-500 dark:text-rose-400 flex items-center gap-0.5 ml-1">
                <XCircle class="w-3 h-3" /> {{ stats.failed }} 失败
              </span>
              <span v-if="stats.translating > 0" class="text-amber-500 dark:text-amber-400 flex items-center gap-0.5 ml-1">
                <RefreshCw class="w-3 h-3 animate-spin" /> {{ stats.translating }} 转译中
              </span>
            </div>
          </div>

          <!-- 控制动作组 -->
          <div class="flex items-center gap-2.5 shrink-0 flex-nowrap">
            <!-- 统一修改分类下拉 (严禁换行) -->
            <div class="flex items-center gap-1.5 shrink-0 whitespace-nowrap text-xs">
              <span class="text-zinc-500 dark:text-zinc-400 text-[11px] font-medium shrink-0 whitespace-nowrap">目标类型:</span>
              <n-select
                v-model:value="globalTypeOverride"
                size="tiny"
                class="w-24 shrink-0"
                :options="[
                  { label: '智能推断', value: 'keep' },
                  { label: '全部小说', value: 'novel' },
                  { label: '全部视频', value: 'video' },
                  { label: '全部图片', value: 'picture' }
                ]"
                @update:value="handleApplyGlobalType"
              />
            </div>

            <!-- 并发限制标签 (严禁换行) -->
            <div class="flex items-center gap-1 text-xs px-2 py-1 rounded-lg bg-zinc-200/60 dark:bg-zinc-800/60 shrink-0 whitespace-nowrap">
              <span class="text-[11px] text-zinc-500 dark:text-zinc-400 whitespace-nowrap">并发: {{ concurrency }}</span>
            </div>

            <!-- 清空重置 -->
            <n-button
              size="tiny"
              quaternary
              class="!rounded-lg text-zinc-400 hover:text-rose-500 shrink-0 whitespace-nowrap"
              :disabled="isTranslating"
              @click="handleClearAll"
            >
              重新输入
            </n-button>
          </div>
        </div>

        <!-- 队列整体进度条 -->
        <div v-if="isTranslating || stats.success > 0 || stats.failed > 0" class="space-y-1 px-1">
          <div class="flex justify-between text-[11px] text-zinc-500 font-mono">
            <span>总进度: {{ stats.success + stats.failed }} / {{ stats.selected }}</span>
            <span>{{ stats.progress }}%</span>
          </div>
          <n-progress
            type="line"
            :percentage="stats.progress"
            :status="stats.failed > 0 && stats.success === 0 ? 'error' : 'success'"
            :show-indicator="false"
            processing
          />
        </div>

        <!-- 规则条目滚动表格 -->
        <div class="rounded-2xl border border-zinc-200/80 dark:border-zinc-800/80 overflow-hidden bg-white dark:bg-zinc-950/40">
          <n-scrollbar style="max-height: 380px;">
            <div class="divide-y divide-zinc-100 dark:divide-zinc-800/60">
              <div
                v-for="item in sourceItems"
                :key="item.id"
                class="flex items-center justify-between p-3 gap-3 hover:bg-zinc-50/80 dark:hover:bg-zinc-900/40 transition-colors"
                :class="{ 'opacity-50': !item.selected }"
              >
                <!-- 左侧勾选与信息 -->
                <div class="flex items-center gap-2.5 min-w-0 flex-1">
                  <n-checkbox v-model:checked="item.selected" :disabled="isTranslating" />
                  
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                      <span class="font-bold text-xs text-zinc-800 dark:text-zinc-200 truncate">
                        {{ item.name }}
                      </span>
                      <n-tag size="tiny" :bordered="false" class="!text-[10px]">
                        {{ item.formatLabel }}
                      </n-tag>
                      <n-popselect
                        v-model:value="item.type"
                        size="small"
                        :options="[
                          { label: '小说 (Novel)', value: 'novel' },
                          { label: '视频 (Video)', value: 'video' },
                          { label: '图片 (Picture)', value: 'picture' }
                        ]"
                      >
                        <n-tag
                          size="tiny"
                          :type="item.type === 'novel' ? 'info' : item.type === 'video' ? 'error' : 'warning'"
                          class="!text-[10px] cursor-pointer hover:opacity-80 transition-opacity"
                        >
                          {{ item.type === 'novel' ? '小说' : item.type === 'video' ? '视频' : '图片' }} ▾
                        </n-tag>
                      </n-popselect>
                    </div>
                    <p class="text-[11px] text-zinc-400 font-mono truncate mt-0.5">
                      {{ item.baseUrl || '无指定 BaseURL' }}
                    </p>
                  </div>
                </div>

                <!-- 状态徽章与操作 -->
                <div class="flex items-center gap-2 shrink-0">
                  <!-- 状态标识 -->
                  <div class="text-right">
                    <span
                      v-if="item.status === 'idle'"
                      class="text-[11px] text-zinc-400 flex items-center gap-1"
                    >
                      <Clock class="w-3 h-3" /> 等待转译
                    </span>
                    <span
                      v-else-if="item.status === 'pending'"
                      class="text-[11px] text-amber-500 flex items-center gap-1"
                    >
                      <Clock class="w-3 h-3" /> 排队中
                    </span>
                    <span
                      v-else-if="item.status === 'translating'"
                      class="text-[11px] text-sky-500 font-bold flex items-center gap-1 animate-pulse"
                    >
                      <RefreshCw class="w-3 h-3 animate-spin" /> AI 转译中...
                    </span>
                    <span
                      v-else-if="item.status === 'success'"
                      class="text-[11px] text-emerald-600 dark:text-emerald-400 font-bold flex items-center gap-1"
                    >
                      <CheckCircle2 class="w-3 h-3" /> 转译完成
                    </span>
                    <span
                      v-else-if="item.status === 'native_ready'"
                      class="text-[11px] text-teal-600 dark:text-teal-400 font-bold flex items-center gap-1"
                    >
                      <CheckCircle2 class="w-3 h-3" /> 原生规则直通
                    </span>
                    <span
                      v-else-if="item.status === 'failed'"
                      class="text-[11px] text-rose-500 font-bold flex items-center gap-1"
                      :title="item.error"
                    >
                      <XCircle class="w-3 h-3" /> 失败: {{ item.error?.slice(0, 15) }}...
                    </span>
                  </div>

                  <!-- 单项操作按钮 -->
                  <div class="flex items-center gap-1">
                    <n-button
                      v-if="item.status === 'success' || item.status === 'native_ready'"
                      size="tiny"
                      secondary
                      type="primary"
                      class="!rounded-lg text-[11px]"
                      @click="handlePreviewCode(item)"
                    >
                      <template #icon>
                        <Code class="w-3 h-3" />
                      </template>
                      <span>预览代码</span>
                    </n-button>

                    <n-button
                      v-if="item.status === 'failed'"
                      size="tiny"
                      secondary
                      type="error"
                      class="!rounded-lg text-[11px]"
                      @click="handleRetrySingle(item)"
                    >
                      <template #icon>
                        <RotateCcw class="w-3 h-3" />
                      </template>
                      <span>重试</span>
                    </n-button>
                  </div>
                </div>
              </div>
            </div>
          </n-scrollbar>
        </div>
      </div>
    </div>

    <!-- 底部操作栏 -->
    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <!-- 左侧模型提示 -->
        <div class="text-[11px] text-zinc-500 flex items-center gap-1.5 truncate">
          <span class="w-2 h-2 rounded-full bg-emerald-500 shrink-0"></span>
          <span class="truncate">当前模型: <strong>{{ aiStore.activeProfile?.name }} ({{ aiStore.activeProfile?.model }})</strong></span>
        </div>

        <!-- 右侧按钮组 -->
        <div class="flex items-center gap-2">
          <n-button
            size="small"
            quaternary
            class="!rounded-xl font-bold"
            @click="emit('update:show', false)"
          >
            关闭
          </n-button>

          <!-- 开始 / 暂停 / 继续转译按钮 -->
          <template v-if="sourceItems.length > 0">
            <n-button
              v-if="!isTranslating"
              size="small"
              type="primary"
              secondary
              class="!rounded-xl font-bold"
              :disabled="stats.selected === 0"
              @click="startTranslation"
            >
              <template #icon>
                <Play class="w-3.5 h-3.5" />
              </template>
              <span>开始转译 ({{ stats.selected }})</span>
            </n-button>

            <template v-else>
              <n-button
                v-if="!isPaused"
                size="small"
                type="warning"
                secondary
                class="!rounded-xl font-bold"
                @click="pauseTranslation"
              >
                <template #icon>
                  <Pause class="w-3.5 h-3.5" />
                </template>
                <span>暂停</span>
              </n-button>

              <n-button
                v-else
                size="small"
                type="primary"
                secondary
                class="!rounded-xl font-bold"
                @click="resumeTranslation"
              >
                <template #icon>
                  <Play class="w-3.5 h-3.5" />
                </template>
                <span>继续</span>
              </n-button>

              <n-button
                size="small"
                quaternary
                type="error"
                class="!rounded-xl font-bold"
                @click="stopTranslation"
              >
                <span>停止</span>
              </n-button>
            </template>

            <!-- 批量入库按钮 -->
            <n-button
              size="small"
              type="primary"
              class="!rounded-xl font-bold !bg-emerald-600 hover:!bg-emerald-500"
              :loading="savingRules"
              :disabled="stats.success === 0"
              @click="handleBatchSave"
            >
              <template #icon>
                <Download class="w-3.5 h-3.5" />
              </template>
              <span>导入已成功项 ({{ stats.success }})</span>
            </n-button>
          </template>
        </div>
      </div>
    </template>
  </n-modal>

  <!-- 代码预览抽屉 / 模态 -->
  <n-drawer
    v-model:show="showCodeDrawer"
    :width="600"
    placement="right"
    class="!bg-zinc-950 text-zinc-100"
  >
    <n-drawer-content :title="`代码预览: ${activePreviewItem?.name || ''}`" closable>
      <div class="space-y-3 h-full flex flex-col">
        <div class="flex items-center justify-between">
          <div class="text-xs text-zinc-400">
            <span>分类: </span>
            <span class="font-bold text-white uppercase">{{ activePreviewItem?.resultRule?.type }}</span>
            <span class="ml-3">BaseURL: </span>
            <span class="font-mono text-zinc-300">{{ activePreviewItem?.resultRule?.baseUrl }}</span>
          </div>
          <n-button size="tiny" secondary class="!rounded-lg" @click="copyPreviewCode">
            <template #icon>
              <Copy class="w-3 h-3" />
            </template>
            <span>复制代码</span>
          </n-button>
        </div>

        <div class="flex-1 rounded-xl bg-zinc-900/90 border border-zinc-800 p-3 font-mono text-xs overflow-auto select-text leading-relaxed">
          <pre class="text-emerald-400"><code>{{ activePreviewItem?.resultRule?.code }}</code></pre>
        </div>
      </div>
    </n-drawer-content>
  </n-drawer>
</template>

<style scoped>
</style>
