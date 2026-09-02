<script setup lang="ts">
import { ref, watch } from 'vue'
import { useMessage } from 'naive-ui'
import { useAiSettingsStore } from '@/stores/aiSettings'
import CodeEditor from '@/components/CodeEditor/index.vue'
import {
  Wrench,
  Sparkles,
  Check,
  Copy,
  AlertCircle,
  FileCode,
  CheckCircle2,
  RefreshCw
} from '@lucide/vue'

const props = defineProps<{
  code: string
  baseUrl?: string
  diagnosticInfo?: { error?: string; logs?: any[]; code?: string } | null
}>()

const emit = defineEmits<{
  (e: 'update:code', val: string): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

const debugUserFeedback = ref('')
const quickProblemTags = [
  '返回列表为空 (items: 0)',
  '正文提取为空',
  '防盗链图片裂开',
  '选择器失效',
  '直链提取错误'
]

const debugging = ref(false)
const hasRunDiagnostic = ref(false)
const debugAnalysis = ref('')
const fixedCode = ref('')

const setDiagnosticContext = (info: { error?: string; logs?: any[]; code?: string }) => {
  if (info?.error) {
    debugUserFeedback.value = `测试异常: ${info.error}`
  }
}

watch(
  () => props.diagnosticInfo,
  (info) => {
    if (info?.error) {
      debugUserFeedback.value = `测试异常: ${info.error}`
    }
  },
  { immediate: true }
)

const handleStartDebugging = async () => {
  if (!aiStore.baseUrl || !aiStore.model) {
    message.error('请先前往系统设置配置 AI 模型提供商与 API Key')
    return
  }
  if (!props.code.trim()) {
    message.warning('当前规则代码为空，无法进行诊断')
    return
  }

  debugging.value = true
  hasRunDiagnostic.value = false
  debugAnalysis.value = ''
  fixedCode.value = ''

  try {
    const result = await aiStore.debugAndOptimizeRule({
      currentCode: props.code,
      action: 'discovery',
      actionParams: {},
      rawResult: {},
      errorMessage: debugUserFeedback.value || undefined,
      userFeedback: debugUserFeedback.value || '请全面检查代码中的选择器与异常处理，并提供修复方案'
    })

    debugAnalysis.value = result.analysis || '已完成规则代码的排查与优化分析。'
    if (result.fixedCode) {
      fixedCode.value = result.fixedCode
    }
    hasRunDiagnostic.value = true
    message.success('✨ AI 智能诊断完成！')
  } catch (err: any) {
    message.error(`诊断失败: ${err.message || '未知异常'}`)
  } finally {
    debugging.value = false
  }
}

const copyFixedCode = async () => {
  if (!fixedCode.value) return
  try {
    await navigator.clipboard.writeText(fixedCode.value)
    message.success('已复制修复后的代码')
  } catch {
    message.error('复制失败，请手动选择复制')
  }
}

const applyFixedCode = () => {
  if (!fixedCode.value) return
  emit('update:code', fixedCode.value)
  message.success('已将 AI 修复代码无缝应用到中栏编辑器')
}

defineExpose({
  setDiagnosticContext
})
</script>

<template>
  <div class="flex-1 flex flex-col min-h-0 h-full overflow-y-auto pr-1 gap-3.5">
    <!-- 1. 诊断输入控制卡片 -->
    <div class="rounded-2xl border border-amber-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] p-3.5 space-y-3 shadow-2xs shrink-0">
      <div class="flex items-center justify-between pb-1.5 border-b border-amber-100/40 dark:border-white/5">
        <div class="flex items-center gap-1.5 text-xs font-bold text-zinc-800 dark:text-zinc-200">
          <Wrench class="w-3.5 h-3.5 text-amber-500" />
          <span>AI 规则智能诊断与差量修复</span>
        </div>
        <span class="text-[10px] text-zinc-400">结合测试报错与执行日志</span>
      </div>

      <div class="space-y-1">
        <label class="text-xs text-zinc-600 dark:text-zinc-400">问题现象或异常描述</label>
        <n-input
          v-model:value="debugUserFeedback"
          type="textarea"
          :autosize="{ minRows: 2, maxRows: 3 }"
          placeholder="请描述遇到的问题，例如: 图片未补全协议、正文提取为空、选择器失效..."
          class="!rounded-xl text-xs"
        />
      </div>

      <!-- 快捷标签 -->
      <div class="space-y-1">
        <span class="text-[10px] text-zinc-400 font-medium">快捷问题标签:</span>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="tag in quickProblemTags"
            :key="tag"
            type="button"
            class="px-2.5 py-1 text-[10px] rounded-lg bg-amber-50/60 dark:bg-white/5 border border-amber-100/60 dark:border-white/5 text-amber-700 dark:text-amber-300 hover:bg-amber-500/15 transition-colors cursor-pointer"
            @click="debugUserFeedback = tag"
          >
            {{ tag }}
          </button>
        </div>
      </div>

      <!-- 诊断触发按钮 -->
      <div class="pt-1">
        <n-button
          type="primary"
          class="w-full !rounded-xl !font-bold !py-3.5 shadow-md shadow-amber-500/20 !bg-gradient-to-r !from-amber-500 !via-rose-500 !to-rose-600 text-white"
          :loading="debugging"
          @click="handleStartDebugging"
        >
          <template #icon>
            <Sparkles class="w-4 h-4 text-white animate-pulse" />
          </template>
          <span>🩺 开始 AI 诊断并推导修复代码</span>
        </n-button>
      </div>
    </div>

    <!-- 2. 诊断中加载状态 -->
    <div v-if="debugging" class="p-6 rounded-2xl border border-amber-200/60 dark:border-amber-800/40 bg-amber-50/50 dark:bg-amber-950/20 text-center space-y-2">
      <RefreshCw class="w-7 h-7 text-amber-500 animate-spin mx-auto" />
      <h4 class="text-xs font-bold text-amber-800 dark:text-amber-200">AI 正在全面推导诊断与修复方案...</h4>
      <p class="text-[11px] text-zinc-500 dark:text-zinc-400 max-w-xs mx-auto">
        正在结合规则代码、报错上下文与 DOM 选择器进行深度逻辑推导，请稍候
      </p>
    </div>

    <!-- 3. 诊断分析与修复结果展示面板 (确保 100% 可见) -->
    <div v-else-if="hasRunDiagnostic || debugAnalysis || fixedCode" class="space-y-3 shrink-0">
      <!-- 3.1 诊断排查结论 -->
      <div class="p-3.5 rounded-2xl bg-amber-50/80 dark:bg-amber-950/25 border border-amber-200/70 dark:border-amber-800/50 space-y-2 shadow-xs">
        <div class="flex items-center justify-between">
          <span class="text-xs font-bold text-amber-800 dark:text-amber-300 flex items-center gap-1.5">
            <CheckCircle2 class="w-4 h-4 text-amber-500" />
            <span>AI 诊断排查结论与优化建议</span>
          </span>
          <span class="text-[10px] font-mono px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-700 dark:text-amber-300 font-bold">
            Analysis
          </span>
        </div>

        <div class="text-xs text-amber-950 dark:text-amber-100 bg-white/90 dark:bg-zinc-900/90 p-3 rounded-xl border border-amber-100/50 dark:border-white/5 leading-relaxed whitespace-pre-wrap font-sans">
          {{ debugAnalysis || '诊断分析完成，已自动修正规则代码。' }}
        </div>
      </div>

      <!-- 3.2 修复后代码预览与应用 -->
      <div v-if="fixedCode" class="p-3.5 rounded-2xl bg-emerald-50/80 dark:bg-emerald-950/25 border border-emerald-200/70 dark:border-emerald-800/50 space-y-2.5 shadow-xs">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <FileCode class="w-4 h-4 text-emerald-500" />
            <span class="text-xs font-bold text-emerald-800 dark:text-emerald-300">修复后的完整规则代码</span>
          </div>
          <div class="flex items-center gap-1.5">
            <n-button
              size="tiny"
              secondary
              class="!rounded-lg text-xs"
              @click="copyFixedCode"
            >
              <template #icon>
                <Copy class="w-3 h-3" />
              </template>
              <span>复制</span>
            </n-button>
            <n-button
              size="tiny"
              type="primary"
              class="!rounded-lg !font-bold text-xs shadow-xs"
              @click="applyFixedCode"
            >
              <template #icon>
                <Check class="w-3 h-3" />
              </template>
              <span>应用到编辑器</span>
            </n-button>
          </div>
        </div>

        <div class="h-60 rounded-xl overflow-hidden border border-emerald-100/60 dark:border-white/5 shadow-2xs">
          <code-editor
            :model-value="fixedCode"
            model-id="workbench_fixed_code_preview"
            height="100%"
            readonly
            class="w-full h-full"
          />
        </div>
      </div>
    </div>
  </div>
</template>
