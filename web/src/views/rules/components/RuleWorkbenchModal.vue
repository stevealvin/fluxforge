<script setup lang="ts">
import { ref } from 'vue'
import type { MediaType } from '@/types/rule'
import WorkbenchSampling from './workbench/WorkbenchSampling.vue'
import WorkbenchPrompt, { type AiGenerationResult } from './workbench/WorkbenchPrompt.vue'
import WorkbenchSandbox from './workbench/WorkbenchSandbox.vue'
import {
  Sparkles,
  Maximize2,
  Minimize2,
  PanelLeftClose
} from '@lucide/vue'

const props = withDefaults(
  defineProps<{
    show?: boolean
    embedded?: boolean
    code: string
    baseUrl?: string
    ruleType?: MediaType | string
    ruleName?: string
    ruleDescription?: string
  }>(),
  {
    show: true,
    embedded: false
  }
)

const emit = defineEmits<{
  (e: 'update:show', val: boolean): void
  (e: 'update:code', val: string): void
  (e: 'apply', payload: { code: string; baseUrl: string; type: string; name?: string; description?: string }): void
  (e: 'logs', logs: any[]): void
  (e: 'close'): void
}>()

// 全屏状态
const isFullscreen = ref(false)

// 模块子引用
const samplingRef = useTemplateRef<any>('samplingRef')
const promptRef = useTemplateRef<any>('promptRef')
const sandboxRef = useTemplateRef<any>('sandboxRef')

// 共享采样状态
const targetUrl = ref(props.baseUrl || '')
const detailUrl = ref('')
const parseUrl = ref('')
const selectedMediaType = ref<MediaType | string>(props.ruleType || 'video')
const listHtml = ref('')
const detailHtml = ref('')
const parseHtml = ref('')

// AI 产出代码（优先使用，否则使用外部传入的当前代码）
const latestAiResult = ref<AiGenerationResult | null>(null)

// 响应 AI 产出最新代码
const handleCodeReady = (result: AiGenerationResult) => {
  latestAiResult.value = result
}

// 自动测试调度
const handleAutoTest = (action: string, code: string) => {
  sandboxRef.value?.executeAction(action, code)
}

// 响应沙箱异常 -> 联动 AI 智能诊断修复
const handleFixError = (context: {
  action: string
  actionParams: any
  rawResult: any
  errorMessage: string
}) => {
  promptRef.value?.handleRunAi({
    overridePrompt: `测试动作 [${context.action}] 异常: ${context.errorMessage}`,
    forceDiagnostic: true,
    action: context.action,
    actionParams: context.actionParams,
    rawResult: context.rawResult,
    errorMessage: context.errorMessage
  })
}

// 转发同步主编辑器
const handleApply = (payload: { code: string; baseUrl: string; type: string; name?: string; description?: string }) => {
  emit('update:code', payload.code)
  emit('apply', payload)
}

// 暴露给外层调用 (如 Ctrl+R 快捷键测试)
const executeAction = (action?: any, overrideCode?: string) => {
  sandboxRef.value?.executeAction(action, overrideCode || latestAiResult.value?.code || props.code)
}

defineExpose({
  executeAction
})
</script>

<template>
  <div
    class="glass-panel flex flex-col overflow-hidden transition-all duration-300 border border-emerald-100/60 dark:border-white/5"
    :class="[
      embedded
        ? 'w-full h-full rounded-2xl shadow-xs bg-white/70 dark:bg-zinc-950/70 backdrop-blur-md'
        : isFullscreen
          ? 'fixed inset-0 z-50 rounded-none bg-zinc-900/95 text-zinc-100 backdrop-blur-xl'
          : 'relative w-full h-full rounded-2xl shadow-2xl bg-white/95 dark:bg-zinc-900/95 text-zinc-800 dark:text-zinc-100 backdrop-blur-xl'
    ]"
  >
    <!-- 1. 顶栏导航 (Header) -->
    <div class="px-4 py-2.5 border-b border-zinc-100 dark:border-white/5 flex items-center justify-between bg-emerald-500/[0.03] shrink-0 select-none">
      <div class="flex items-center gap-2">
        <div class="p-1 rounded-lg bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
          <Sparkles class="w-4 h-4 animate-pulse" />
        </div>
        <span class="text-xs sm:text-sm font-black text-zinc-900 dark:text-white tracking-tight">AI 智能与调试工作台</span>
      </div>

      <div class="flex items-center gap-1">
        <n-button
          v-if="!embedded"
          quaternary
          size="tiny"
          class="!p-1.5 !rounded-lg"
          @click="isFullscreen = !isFullscreen"
        >
          <template #icon>
            <component :is="isFullscreen ? Minimize2 : Maximize2" class="w-3.5 h-3.5" />
          </template>
        </n-button>

        <n-button
          quaternary
          size="tiny"
          class="!p-1.5 !rounded-lg text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
          title="收起工作台 (Ctrl+Enter)"
          @click="emit('close')"
        >
          <template #icon>
            <PanelLeftClose class="w-4 h-4" />
          </template>
        </n-button>
      </div>
    </div>

    <!-- 2. 工作台主滚动区域 (三模块闭环流水线) -->
    <div class="flex-1 flex flex-col gap-3 p-3 overflow-y-auto min-h-0">
      <!-- 模块 1: 目标采样管理 -->
      <WorkbenchSampling
        ref="samplingRef"
        v-model:target-url="targetUrl"
        v-model:detail-url="detailUrl"
        v-model:parse-url="parseUrl"
        v-model:list-html="listHtml"
        v-model:detail-html="detailHtml"
        v-model:parse-html="parseHtml"
      />

      <!-- 模块 2: AI 提示词与智能推导 -->
      <WorkbenchPrompt
        ref="promptRef"
        :code="props.code"
        :target-url="targetUrl"
        :detail-url="detailUrl"
        :parse-url="parseUrl"
        :media-type="selectedMediaType"
        :list-html="listHtml"
        :detail-html="detailHtml"
        :parse-html="parseHtml"
        :rule-name="props.ruleName"
        :rule-description="props.ruleDescription"
        @code-ready="handleCodeReady"
        @auto-test="handleAutoTest"
        @apply="handleApply"
      />

      <!-- 模块 3: 沙箱测试与结果呈现 -->
      <WorkbenchSandbox
        ref="sandboxRef"
        :code="latestAiResult?.code || props.code"
        :rule-type="selectedMediaType"
        :base-url="targetUrl"
        @logs="(logs) => emit('logs', logs)"
        @fix-error="handleFixError"
      />
    </div>
  </div>
</template>
