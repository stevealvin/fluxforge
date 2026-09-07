<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import { useAiSettingsStore } from '@/stores/aiSettings'
import type { MediaType } from '@/types/rule'
import {
  Sparkles,
  Loader2,
  FileText,
  Copy,
  CheckCheck,
  Bot
} from '@lucide/vue'

export interface AiGenerationResult {
  code: string
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

// 快速切换 Profile 下拉菜单选项
const profileQuickOptions = computed(() => {
  return aiStore.profiles.map((p) => ({
    label: `${p.name} (${p.model})`,
    value: p.id
  }))
})

// 处理工作台直接快速切换 AI 节点
const handleQuickSwitchProfile = (id: string) => {
  aiStore.setActiveProfile(id)
  message.success(`已切换生效 AI 配置: ${aiStore.activeProfile.name}`)
}

const userPrompt = ref('')
const aiLoading = ref(false)
const autoTestAfterAi = ref(true)
const currentAiResult = ref<AiGenerationResult | null>(null)

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
  if (aiLoading.value) return

  if (!aiStore.activeProfile?.baseUrl || !aiStore.activeProfile?.model) {
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
        analysis: result.analysis || (isFix ? 'AI 已完成代码针对性优化与排错。' : 'AI 已根据需求生成完整规则脚本。'),
        isFix
      }

      // 方案A：生成成功后，直接自动同步至主编辑器 (保持全局单一代码源)
      emit('apply', {
        code: result.code,
        baseUrl: props.targetUrl || '',
        type: String(props.mediaType),
        name: props.ruleName,
        description: props.ruleDescription
      })

      message.success(isFix ? '✨ AI 已完成针对性优化修复并同步至主编辑器！' : '✨ 规则生成成功并已同步至主编辑器！')
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

// 复制 AI 分析报告
const copyAnalysis = async () => {
  const analysis = currentAiResult.value?.analysis
  if (!analysis) return
  try {
    await navigator.clipboard.writeText(analysis)
    message.success('已复制分析报告到剪贴板')
  } catch {
    message.error('复制失败')
  }
}

// 再次同步到主编辑器
const applyToMainEditor = () => {
  const codeToApply = currentAiResult.value?.code
  if (!codeToApply) return

  emit('apply', {
    code: codeToApply,
    baseUrl: props.targetUrl || '',
    type: String(props.mediaType),
    name: props.ruleName,
    description: props.ruleDescription
  })
  message.success('✅ 已将代码重新同步至主编辑器')
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

          <div class="flex items-center gap-2">
            <!-- 快捷切换生效配置 -->
            <n-popselect
              v-if="aiStore.profiles.length > 0"
              :value="aiStore.activeProfileId"
              :options="profileQuickOptions"
              size="small"
              @update:value="handleQuickSwitchProfile"
            >
              <button
                type="button"
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 hover:bg-emerald-500/15 text-[10px] font-bold transition-colors cursor-pointer border border-emerald-500/20"
                :title="`当前生效配置: ${aiStore.activeProfile.name} (${aiStore.activeProfile.model})，点击可切换`"
              >
                <Bot class="w-3 h-3 text-emerald-500" />
                <span class="max-w-[100px] truncate">{{ aiStore.activeProfile.name }}</span>
                <span class="text-[9px] opacity-75 font-mono">({{ aiStore.activeProfile.model }})</span>
              </button>
            </n-popselect>
            <span class="text-[10px] text-zinc-400 hidden sm:inline">按 Enter 发送</span>
          </div>
        </div>

        <n-input
          v-model:value="userPrompt"
          type="textarea"
          :rows="4"
          :disabled="aiLoading"
          :placeholder="isFreshStart ? '请输入生成需求，或直接粘贴外部规则配置、爬虫脚本、接口定义与数据样本，AI 将自动分析转译...' : '请输入优化调整需求、待转译规则或问题排查说明（按 Enter 发送）...'"
          class="rounded-xl! text-xs"
          @keydown.enter.exact.prevent="!$event.isComposing && handleRunAi()"
        />
      </div>

      <!-- 快捷指令标签胶囊 -->
      <div class="flex flex-wrap gap-1.5 items-center">
        <span class="text-[10px] text-zinc-400">快捷预设:</span>
        <button
          v-for="chip in quickPromptChips"
          :key="chip"
          type="button"
          :disabled="aiLoading"
          class="px-2 py-0.5 text-[10px] rounded-lg bg-violet-50/70 dark:bg-violet-950/20 border border-violet-200/50 dark:border-violet-800/30 text-violet-700 dark:text-violet-300 hover:bg-violet-500/15 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
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
          :disabled="aiLoading"
          @click="handleRunAi()"
        >
          <template #icon>
            <Loader2 v-if="aiLoading" class="w-4 h-4 text-white animate-spin" />
            <Sparkles v-else class="w-4 h-4 text-white animate-pulse" />
          </template>
          <span>
            {{ aiLoading
                ? (isFreshStart ? '🚀 正在智能分析并生成代码...' : '✨ 正在排查推导并优化代码...')
                : (isFreshStart ? '🚀 一键 AI 分析并生成规则代码' : '✨ 让 AI 推导优化并更新规则')
            }}
          </span>
        </n-button>
      </div>
    </div>

    <!-- AI 分析报告卡片 (直接常驻展示，无代码预览，不可折叠) -->
    <div
      v-if="currentAiResult?.analysis"
      class="rounded-2xl border border-emerald-200/80 dark:border-emerald-800/40 bg-emerald-50/40 dark:bg-emerald-950/20 p-3.5 space-y-2.5 shadow-2xs"
    >
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-1.5">
          <FileText class="w-4 h-4 text-emerald-500" />
          <span class="text-xs font-bold text-zinc-900 dark:text-zinc-100">
            {{ currentAiResult.isFix ? 'AI 诊断优化报告' : 'AI 规则分析报告' }}
          </span>
        </div>

        <div class="flex items-center gap-1.5">
          <n-button
            size="tiny"
            quaternary
            class="!rounded-lg text-[10px]"
            title="复制分析报告"
            @click="copyAnalysis"
          >
            <template #icon>
              <Copy class="w-3 h-3" />
            </template>
            <span>复制报告</span>
          </n-button>
          <n-button
            size="tiny"
            secondary
            class="!rounded-lg text-[10px]"
            title="代码已自动同步至主编辑器，点击可再次强制同步"
            @click="applyToMainEditor"
          >
            <template #icon>
              <CheckCheck class="w-3 h-3 text-emerald-500" />
            </template>
            <span>已同步主编辑器</span>
          </n-button>
        </div>
      </div>

      <!-- 分析报告正文 (常驻直接展示，不可收起) -->
      <div
        class="text-xs p-3 rounded-xl bg-white/80 dark:bg-black/20 border border-emerald-100 dark:border-white/5 text-zinc-700 dark:text-zinc-200 whitespace-pre-wrap leading-relaxed select-text shadow-2xs font-normal"
      >
        {{ currentAiResult.analysis }}
      </div>
    </div>
  </div>
</template>
