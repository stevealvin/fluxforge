<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import { useAiSettingsStore } from '@/stores/aiSettings'
import CodeEditor from '@/components/CodeEditor/index.vue'
import type { MediaType } from '@/types/rule'
import {
  Sparkles,
  CheckCircle2,
  Copy,
  Check,
  Code,
  CheckCheck,
  ChevronDown,
  ChevronUp
} from '@lucide/vue'

export interface AiGenerationResult {
  code: string
  name?: string
  description?: string
  mediaType?: string
  analysis?: string
  isFix?: boolean
}

const props = defineProps<{
  code: string
  targetUrl: string
  detailUrl?: string
  parseUrl?: string
  mediaType: MediaType | string
  listHtml: string
  detailHtml?: string
  parseHtml?: string
  ruleName?: string
  ruleDescription?: string
}>()

const emit = defineEmits<{
  (e: 'code-ready', result: AiGenerationResult): void
  (e: 'apply', payload: { code: string; baseUrl: string; type: string; name?: string; description?: string }): void
  (e: 'auto-test', action: string, code: string): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

const userPrompt = ref('')
const aiLoading = ref(false)
const autoTestAfterAi = ref(true)
const currentAiResult = ref<AiGenerationResult | null>(null)
const showCodePreview = ref(false)
const showAnalysis = ref(false)

// 判断是否全新冷启动
const isFreshStart = computed(() => {
  if (!props.code || !props.code.trim()) return true
  const trimmed = props.code.trim()
  if (trimmed.includes('示例描述') || trimmed.includes('item_1') || trimmed.length < 220) {
    return true
  }
  return false
})

const quickPromptChips = [
  '全新生成完整规则',
  '过滤广告干扰节点',
  '封面提取高清原图并补全',
  '选集按正序排列',
  '小说正文保留段落换行',
  '修复列表数据为空',
  '修复翻页失效'
]

const handleApplyPromptChip = (chip: string) => {
  if (userPrompt.value) {
    userPrompt.value += `，${chip}`
  } else {
    userPrompt.value = chip
  }
}

// 核心 AI 统一调用入口 (全新生成 / 需求变更 / 测试排错统一流转，解绑网页强依赖)
const handleRunAi = async (options?: {
  overridePrompt?: string
  forceDiagnostic?: boolean
  action?: string
  actionParams?: any
  rawResult?: any
  errorMessage?: string
}) => {
  if (!aiStore.baseUrl || !aiStore.model) {
    message.error('请先在「系统设置」中配置 AI API Key 与模型提供商')
    return
  }

  const promptText = options?.overridePrompt || userPrompt.value
  const hasError = Boolean(options?.errorMessage)
  const isFix = !isFreshStart.value || options?.forceDiagnostic || hasError

  aiLoading.value = true
  try {
    const result = await aiStore.processRuleCode({
      code: isFreshStart.value ? '' : (currentAiResult.value?.code || props.code),
      targetUrl: props.targetUrl || undefined,
      mediaType: props.mediaType,
      prompt: promptText || undefined,
      action: options?.action,
      actionParams: options?.actionParams,
      rawResult: options?.rawResult,
      errorMessage: options?.errorMessage,
      listHtml: props.listHtml || undefined,
      detailHtml: props.detailHtml || undefined,
      parseHtml: props.parseHtml || undefined
    })

    if (result?.code) {
      currentAiResult.value = {
        code: result.code,
        name: result.name || props.ruleName,
        description: result.description || props.ruleDescription,
        mediaType: result.mediaType || props.mediaType,
        analysis: result.analysis || (isFix ? 'AI 已完成代码针对性优化与排错。' : 'AI 已根据需求生成完整规则脚本。'),
        isFix
      }
      showCodePreview.value = false
      message.success(isFix ? '✨ AI 已完成针对性优化修复！' : '✨ 规则生成成功！')
      emit('code-ready', currentAiResult.value)

      if (autoTestAfterAi.value) {
        emit('auto-test', options?.action || 'discovery', result.code)
      }
    }
  } catch (err: any) {
    message.error(`AI 执行失败: ${err.message || '请检查模型连接'}`)
  } finally {
    aiLoading.value = false
  }
}

// 复制当前 AI 代码
const copyAiCode = async () => {
  const code = currentAiResult.value?.code
  if (!code) return
  try {
    await navigator.clipboard.writeText(code)
    message.success('已复制 AI 代码到剪贴板')
  } catch {
    message.error('复制失败')
  }
}

// 一键应用到主编辑器
const applyToMainEditor = () => {
  const codeToApply = currentAiResult.value?.code
  if (!codeToApply) return

  emit('apply', {
    code: codeToApply,
    baseUrl: props.targetUrl || '',
    type: currentAiResult.value?.mediaType || String(props.mediaType),
    name: currentAiResult.value?.name || props.ruleName,
    description: currentAiResult.value?.description || props.ruleDescription
  })
  message.success('✅ 已将代码与配置无缝同步至主编辑器')
}

defineExpose({
  handleRunAi,
  currentAiResult
})
</script>

<template>
  <div class="space-y-2.5 shrink-0">
    <!-- 自然语言提词与快捷指令控制卡片 -->
    <div class="rounded-2xl border border-emerald-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] p-3 space-y-2.5 shadow-2xs">
      <!-- 需求与指令输入框 -->
      <div class="space-y-1.5">
        <div class="flex items-center justify-between text-xs">
          <span class="font-bold text-zinc-800 dark:text-zinc-200 flex items-center gap-1.5">
            <Sparkles class="w-3.5 h-3.5 text-emerald-500" />
            <span>AI 规则需求与调整指令:</span>
          </span>
          <span class="text-[10px] text-zinc-400">支持 Ctrl+Enter 快捷发送</span>
        </div>

        <n-input
          v-model:value="userPrompt"
          type="textarea"
          :rows="2"
          :placeholder="isFreshStart ? '请输入生成需求（如：提取列表标题、封面高清原图、过滤广告节点等）...' : '输入优化需求或问题（如：选集正序排列、正文保留段落、翻页失效等）...'"
          class="!rounded-xl text-xs"
          @keydown.ctrl.enter="handleRunAi()"
        />
      </div>

      <!-- 快捷指令标签胶囊 -->
      <div class="flex flex-wrap gap-1.5 items-center">
        <span class="text-[10px] text-zinc-400">快捷预设:</span>
        <button
          v-for="chip in quickPromptChips"
          :key="chip"
          type="button"
          class="px-2 py-0.5 text-[10px] rounded-lg bg-violet-50/70 dark:bg-violet-950/20 border border-violet-200/50 dark:border-violet-800/30 text-violet-700 dark:text-violet-300 hover:bg-violet-500/15 transition-colors cursor-pointer"
          @click="handleApplyPromptChip(chip)"
        >
          {{ chip }}
        </button>
      </div>

      <!-- 触发按钮与选项 -->
      <div class="flex items-center gap-2 pt-1">
        <n-button
          type="primary"
          class="flex-1 !rounded-xl !font-bold !py-3 shadow-md shadow-emerald-500/20 !bg-gradient-to-r !from-emerald-600 !via-teal-500 !to-cyan-500 text-white"
          :loading="aiLoading"
          @click="handleRunAi()"
        >
          <template #icon>
            <Sparkles class="w-4 h-4 text-white animate-pulse" />
          </template>
          <span>
            {{ isFreshStart ? '🚀 一键 AI 分析并生成规则代码' : '✨ 让 AI 推导优化并更新规则' }}
          </span>
        </n-button>
      </div>
    </div>

    <!-- AI 产出卡片 (代码更新与分析简述) -->
    <div
      v-if="currentAiResult?.code"
      class="rounded-2xl border border-emerald-200/80 dark:border-emerald-800/40 bg-emerald-50/30 dark:bg-emerald-950/15 p-3 space-y-2.5 shadow-2xs"
    >
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-1.5">
          <CheckCircle2 class="w-4 h-4 text-emerald-500" />
          <span class="text-xs font-bold text-zinc-900 dark:text-zinc-100">
            {{ currentAiResult.isFix ? 'AI 诊断修复完成' : 'AI 规则生成完成' }}
          </span>
          <span v-if="currentAiResult.name" class="px-1.5 py-0.2 text-[10px] rounded bg-emerald-500/20 text-emerald-700 dark:text-emerald-300 font-bold">
            {{ currentAiResult.name }}
          </span>
        </div>

        <div class="flex items-center gap-1.5">
          <n-button
            v-if="currentAiResult.analysis"
            size="tiny"
            quaternary
            class="!rounded-lg text-[10px]"
            @click="showAnalysis = !showAnalysis"
          >
            {{ showAnalysis ? '收起分析' : '分析报告' }}
          </n-button>
          <n-button
            size="tiny"
            quaternary
            class="!rounded-lg text-[10px]"
            @click="showCodePreview = !showCodePreview"
          >
            <template #icon>
              <Code class="w-3 h-3" />
            </template>
            <span>{{ showCodePreview ? '收起预览' : '查看代码' }}</span>
          </n-button>
          <n-button
            size="tiny"
            secondary
            class="!rounded-lg text-[10px]"
            @click="copyAiCode"
          >
            <template #icon>
              <Copy class="w-3 h-3" />
            </template>
            <span>复制</span>
          </n-button>
          <n-button
            size="tiny"
            type="primary"
            class="!rounded-lg !font-bold text-[10px] shadow-xs"
            @click="applyToMainEditor"
          >
            <template #icon>
              <CheckCheck class="w-3 h-3" />
            </template>
            <span>同步主编辑器</span>
          </n-button>
        </div>
      </div>

      <!-- 分析报告展开 -->
      <div
        v-if="showAnalysis && currentAiResult.analysis"
        class="text-xs p-2.5 rounded-xl bg-white/80 dark:bg-black/20 border border-emerald-100 dark:border-white/5 text-zinc-600 dark:text-zinc-300 whitespace-pre-wrap leading-relaxed"
      >
        {{ currentAiResult.analysis }}
      </div>

      <!-- 代码预览抽屉/容器 -->
      <div v-if="showCodePreview" class="h-64 rounded-xl overflow-hidden border border-zinc-200/80 dark:border-white/10">
        <code-editor
          :model-value="currentAiResult.code"
          model-id="ai_code_preview"
          height="100%"
          class="w-full h-full"
          :options="{ readOnly: true, lineNumbers: 'on', minimap: { enabled: false } }"
        />
      </div>
    </div>
  </div>
</template>
