<script setup lang="ts">
import { ref, computed, nextTick } from 'vue'
import type { RuleAction, MediaType } from '@/types/rule'
import {
  Sparkles,
  Play,
  Wrench,
  Maximize2,
  Minimize2,
  PanelLeftClose
} from '@lucide/vue'
import WorkbenchGenerator from './workbench/WorkbenchGenerator.vue'
import WorkbenchTester from './workbench/WorkbenchTester.vue'
import WorkbenchDebugger from './workbench/WorkbenchDebugger.vue'

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

const currentTab = ref<'ai' | 'test' | 'debug'>('ai')
const isFullscreen = ref(false)

const generatorRef = ref<InstanceType<typeof WorkbenchGenerator> | null>(null)
const testerRef = ref<InstanceType<typeof WorkbenchTester> | null>(null)
const debuggerRef = ref<InstanceType<typeof WorkbenchDebugger> | null>(null)
const lastDiagnosticInfo = ref<{ error?: string; logs?: any[]; code?: string } | null>(null)

// 从 Generator 采样数据中取出最相关的 HTML 传递给 Debugger
const debugTargetHtml = computed(() => {
  const gen = generatorRef.value
  if (!gen) return ''
  // 优先使用列表页 HTML（discovery 是最常见的诊断场景）
  return gen.listHtml || gen.detailHtml || gen.parseHtml || ''
})

const handleStartDiagnostic = async (info: { error?: string; logs?: any[]; code?: string }) => {
  lastDiagnosticInfo.value = info
  currentTab.value = 'debug'
  await nextTick()
  debuggerRef.value?.setDiagnosticContext(info)
}

// 暴露给父组件以支持全局快捷键联动 (Ctrl+R 运行当前动作)
defineExpose({
  executeAction: (action?: RuleAction) => testerRef.value?.executeAction(action),
  activeAction: computed(() => testerRef.value?.activeAction || 'discovery'),
  currentTab
})
</script>

<template>
  <div
    :class="[
      isFullscreen
        ? 'fixed inset-3 z-50 glass-panel rounded-3xl border border-emerald-200/80 dark:border-white/20 overflow-hidden shadow-2xl flex flex-col bg-white/95 dark:bg-zinc-900/95 backdrop-blur-xl'
        : 'w-full h-full glass-panel rounded-3xl !p-0 overflow-hidden shadow-xs border border-emerald-100/70 dark:border-white/10 flex flex-col bg-white/80 dark:bg-zinc-900/80 backdrop-blur-xl'
    ]"
  >
    <!-- 顶部工作台状态与 Tab 控制条 -->
    <div class="px-4 py-2.5 border-b border-emerald-100/60 dark:border-white/5 flex items-center justify-between bg-white/60 dark:bg-white/[0.02] shrink-0 gap-2">
      <!-- 标题与状态条 -->
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 text-white flex items-center justify-center shadow-md shadow-emerald-500/25 shrink-0">
          <Sparkles class="w-4 h-4" />
        </div>
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-xs sm:text-sm font-black tracking-tight text-zinc-900 dark:text-white truncate">
            AI 智能工作台
          </span>
        </div>
      </div>

      <!-- 工作台顶部三模态切换 Tab (保持用户喜爱的上版极简紧凑样式) -->
      <div class="flex items-center gap-1 p-0.5 bg-zinc-200/60 dark:bg-white/10 rounded-xl shrink-0">
        <button
          type="button"
          class="flex items-center gap-1 px-2.5 py-1 text-xs font-bold rounded-lg transition-all cursor-pointer"
          :class="currentTab === 'ai' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
          @click="currentTab = 'ai'"
        >
          <Sparkles class="w-3 h-3 text-emerald-500" />
          <span>生成</span>
        </button>

        <button
          type="button"
          class="flex items-center gap-1 px-2.5 py-1 text-xs font-bold rounded-lg transition-all cursor-pointer"
          :class="currentTab === 'test' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
          @click="currentTab = 'test'"
        >
          <Play class="w-3 h-3 fill-current text-emerald-500" />
          <span>测试</span>
        </button>

        <button
          type="button"
          class="flex items-center gap-1 px-2.5 py-1 text-xs font-bold rounded-lg transition-all cursor-pointer"
          :class="currentTab === 'debug' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
          @click="currentTab = 'debug'"
        >
          <Wrench class="w-3 h-3 text-amber-500" />
          <span>诊断</span>
        </button>
      </div>

      <!-- 窗口动作 -->
      <div class="flex items-center gap-1 shrink-0">
        <n-button
          quaternary
          circle
          size="small"
          class="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 !w-7 !h-7"
          :title="isFullscreen ? '还原至侧边栏' : '全屏展开'"
          @click="isFullscreen = !isFullscreen"
        >
          <template #icon>
            <Minimize2 v-if="isFullscreen" class="w-3.5 h-3.5" />
            <Maximize2 v-else class="w-3.5 h-3.5" />
          </template>
        </n-button>

        <n-button
          quaternary
          circle
          size="small"
          class="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 !w-7 !h-7"
          title="收起工作台"
          @click="emit('close')"
        >
          <template #icon>
            <PanelLeftClose class="w-3.5 h-3.5 rotate-180" />
          </template>
        </n-button>
      </div>
    </div>

    <!-- 工作台主体分栏内容 -->
    <div class="flex-1 flex flex-col min-h-0 h-full p-3.5 overflow-hidden">
      <!-- TAB 1: 🚀 AI 规则生成器 (v-show 保持组件存活，以便其他 Tab 读取采样数据) -->
      <WorkbenchGenerator
        v-show="currentTab === 'ai'"
        ref="generatorRef"
        :code="props.code"
        :base-url="props.baseUrl"
        :rule-type="props.ruleType"
        :rule-name="props.ruleName"
        :rule-description="props.ruleDescription"
        @update:code="(val) => emit('update:code', val)"
        @apply="(payload) => emit('apply', payload)"
        @switch-to-test="currentTab = 'test'"
      />

      <!-- TAB 2: ⚡ 沙箱测试与生命周期调试 -->
      <WorkbenchTester
        v-show="currentTab === 'test'"
        ref="testerRef"
        :code="props.code"
        :base-url="props.baseUrl"
        @logs="(logs) => emit('logs', logs)"
        @start-diagnostic="handleStartDiagnostic"
      />

      <!-- TAB 3: 🩺 AI 智能诊断与差量修复 -->
      <WorkbenchDebugger
        v-show="currentTab === 'debug'"
        ref="debuggerRef"
        :code="props.code"
        :base-url="props.baseUrl"
        :diagnostic-info="lastDiagnosticInfo"
        :target-html="debugTargetHtml"
        @update:code="(val) => emit('update:code', val)"
      />
    </div>
  </div>
</template>
