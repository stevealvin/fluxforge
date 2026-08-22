<script setup lang="ts">
import { ref, computed } from 'vue'
import { useMessage } from 'naive-ui'
import { useAiSettingsStore } from '@/stores/aiSettings'
import http from '@/utils/http'
import CodeEditor from '@/components/CodeEditor/index.vue'
import {
  Sparkles,
  Bot,
  Globe,
  Code2,
  DownloadCloud,
  FileCode2,
  Check,
  RotateCcw,
  SlidersHorizontal,
  Layers,
  ArrowRight
} from '@lucide/vue'

const props = defineProps<{
  show: boolean
  defaultBaseUrl?: string
  defaultType?: string
}>()

const emit = defineEmits<{
  (e: 'update:show', val: boolean): void
  (e: 'apply', payload: { code: string; baseUrl: string; type: string; name?: string }): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

const targetUrl = ref(props.defaultBaseUrl || '')
const mediaType = ref(props.defaultType || 'video')
const htmlSnippet = ref('')
const requirement = ref('')

const fetchingHtml = ref(false)
const generating = ref(false)
const generatedCode = ref('')
const ruleName = ref('')

const mediaTypeOptions = [
  { label: '视频规则 (video)', value: 'video' },
  { label: '图片规则 (picture)', value: 'picture' },
  { label: '小说规则 (novel)', value: 'novel' }
]

// 一键从目标 URL 抓取 HTML 源码
const handleFetchHtml = async () => {
  if (!targetUrl.value.trim() || !targetUrl.value.startsWith('http')) {
    message.warning('请先输入有效的 HTTP/HTTPS 目标站点网址')
    return
  }

  fetchingHtml.value = true
  try {
    const res: any = await http.post('/rules/fetch-html', {
      url: targetUrl.value.trim()
    })
    if (res?.html) {
      htmlSnippet.value = res.html.slice(0, 30000)
      message.success(`已成功抓取网页源码 (${(res.html.length / 1024).toFixed(1)} KB)`)
    } else {
      message.warning('抓取到的网页内容为空')
    }
  } catch (err: any) {
    message.error(err.response?.data?.message || err.message || '抓取网页源码失败')
  } finally {
    fetchingHtml.value = false
  }
}

// 调用 AI 大模型生成规则代码
const handleGenerate = async () => {
  if (!htmlSnippet.value.trim()) {
    message.warning('请先输入或抓取目标网页的 HTML 片段')
    return
  }

  if (!aiStore.baseUrl) {
    message.error('尚未配置 AI 模型 API 地址，请在左侧侧边栏底部「系统设置」中配置')
    return
  }

  generating.value = true
  try {
    const code = await aiStore.generateRuleCode({
      targetUrl: targetUrl.value.trim(),
      mediaType: mediaType.value,
      htmlSnippet: htmlSnippet.value.trim(),
      requirement: requirement.value.trim()
    })

    if (code) {
      generatedCode.value = code
      message.success('AI 解析规则生成完成！')
    } else {
      message.error('AI 未能生成有效的代码')
    }
  } catch (err: any) {
    message.error('生成失败: ' + err.message)
  } finally {
    generating.value = false
  }
}

// 应用到规则编辑器
const handleApply = () => {
  if (!generatedCode.value.trim()) {
    message.warning('暂无生成的代码可应用')
    return
  }

  emit('apply', {
    code: generatedCode.value.trim(),
    baseUrl: targetUrl.value.trim(),
    type: mediaType.value,
    name: ruleName.value.trim()
  })

  message.success('已成功应用 AI 生成的规则代码到编辑器')
  emit('update:show', false)
}
</script>

<template>
  <n-modal
    :show="show"
    @update:show="(val) => emit('update:show', val)"
    preset="card"
    title="AI 智能规则编写助手"
    class="!rounded-3xl max-w-5xl shadow-2xl w-full"
    :segmented="{ content: 'soft', footer: 'soft' }"
  >
    <template #header>
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center shadow-md shadow-emerald-500/20 text-white">
          <Sparkles class="w-4 h-4 animate-pulse" />
        </div>
        <div>
          <h2 class="text-base font-black text-zinc-900 dark:text-white flex items-center gap-2">
            <span>AI 智能生成解析规则</span>
            <span class="px-2 py-0.5 text-[10px] font-mono rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50">
              {{ aiStore.model || '未配置' }}
            </span>
          </h2>
          <p class="text-[11px] text-zinc-400">提供目标站点网址与网页 HTML 源码，AI 大模型自动为您分析 DOM 结构并编写符合 FluxForge 规范的完整规则代码</p>
        </div>
      </div>
    </template>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-5 h-[65vh]">
      <!-- 左侧：输入与抓取参数栏 (lg:col-span-5) -->
      <div class="lg:col-span-5 flex flex-col gap-3.5 h-full overflow-y-auto pr-1">
        <!-- 目标网址与一键抓取 -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center justify-between">
            <span class="flex items-center gap-1.5">
              <Globe class="w-3.5 h-3.5 text-teal-500" />
              <span>目标源站 URL (Base URL)</span>
            </span>
            <n-button
              size="tiny"
              secondary
              type="primary"
              :loading="fetchingHtml"
              @click="handleFetchHtml"
              class="!rounded-lg !font-bold"
            >
              <template #icon>
                <DownloadCloud class="w-3 h-3" />
              </template>
              抓取源码
            </n-button>
          </label>
          <n-input
            v-model:value="targetUrl"
            placeholder="例如: https://bizhi.wpcoder.cn"
            class="!rounded-xl font-mono text-xs"
          />
        </div>

        <!-- 规则类型与可选名称 -->
        <div class="grid grid-cols-2 gap-2">
          <div class="space-y-1.5">
            <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1">
              <Layers class="w-3.5 h-3.5 text-emerald-500" />
              <span>媒体大类</span>
            </label>
            <n-select
              v-model:value="mediaType"
              :options="mediaTypeOptions"
              class="!rounded-xl"
            />
          </div>

          <div class="space-y-1.5">
            <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1">
              <FileCode2 class="w-3.5 h-3.5 text-cyan-500" />
              <span>规则名称 (可选)</span>
            </label>
            <n-input
              v-model:value="ruleName"
              placeholder="例如: 壁纸精选"
              class="!rounded-xl text-xs"
            />
          </div>
        </div>

        <!-- 网页 HTML 片段输入区 -->
        <div class="space-y-1.5 flex-1 flex flex-col min-h-[160px]">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center justify-between">
            <span class="flex items-center gap-1.5">
              <Code2 class="w-3.5 h-3.5 text-amber-500" />
              <span>目标页面 HTML 片段 / DOM 结构</span>
            </span>
            <span class="text-[10px] font-mono text-zinc-400">
              {{ htmlSnippet.length }} 字符
            </span>
          </label>
          <n-input
            v-model:value="htmlSnippet"
            type="textarea"
            placeholder="请在此粘贴目标网站的 HTML 源码片段（例如 <ul> 列表、详情页区域 DOM 等）..."
            class="!rounded-xl font-mono text-xs flex-1"
            :autosize="{ minRows: 6, maxRows: 12 }"
          />
        </div>

        <!-- 补充需求 -->
        <div class="space-y-1.5">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
            <SlidersHorizontal class="w-3.5 h-3.5 text-violet-500" />
            <span>补充需求 / 特殊解析提示 (可选)</span>
          </label>
          <n-input
            v-model:value="requirement"
            placeholder="例如: 列表在 .list-box li 中，视频直链需要提取 script 内的 mp4 变量"
            class="!rounded-xl text-xs"
          />
        </div>

        <!-- 生成按键 -->
        <n-button
          type="primary"
          block
          :loading="generating"
          @click="handleGenerate"
          class="!rounded-xl !font-bold !py-4 shadow-lg shadow-emerald-500/20 mt-1"
        >
          <template #icon>
            <Bot class="w-4 h-4" />
          </template>
          <span>{{ generating ? 'AI 大模型正在分析编写规则中...' : '开始生成解析规则' }}</span>
        </n-button>
      </div>

      <!-- 右侧：生成结果与代码预览 (lg:col-span-7) -->
      <div class="lg:col-span-7 flex flex-col gap-2 h-full border border-emerald-100/50 dark:border-white/5 rounded-2xl p-3 bg-zinc-50/50 dark:bg-black/20">
        <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
          <div class="flex items-center gap-2">
            <div class="w-1.5 h-4 rounded-full bg-gradient-to-b from-emerald-500 to-cyan-500"></div>
            <span class="text-xs font-bold text-zinc-800 dark:text-zinc-200">生成代码预览 (JavaScript ESModule)</span>
          </div>
          <span v-if="generatedCode" class="text-[10px] font-mono text-emerald-600 dark:text-emerald-400">已就绪</span>
        </div>

        <!-- Monaco 代码编辑器预览 -->
        <div class="flex-1 w-full rounded-xl overflow-hidden border border-zinc-200/60 dark:border-white/5 relative">
          <div v-if="generating" class="w-full h-full flex flex-col items-center justify-center text-zinc-400 gap-3 bg-white/60 dark:bg-zinc-900/60 backdrop-blur-xs">
            <n-spin size="large" />
            <span class="text-xs font-bold">AI 正在深度解析 DOM 并组织 Standard Rules...</span>
          </div>
          <CodeEditor
            v-else-if="generatedCode"
            v-model="generatedCode"
            language="javascript"
          />
          <div v-else class="w-full h-full flex flex-col items-center justify-center text-zinc-400 gap-2 p-6 text-center">
            <Bot class="w-12 h-12 text-zinc-300 dark:text-zinc-700" />
            <span class="text-xs text-zinc-500">在左侧填入网址与 HTML 源码后，点击「开始生成」即可在此实时预览并应用规则。</span>
          </div>
        </div>
      </div>
    </div>

    <!-- 底部按钮 -->
    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <div class="text-[11px] text-zinc-400 flex items-center gap-1">
          <Sparkles class="w-3.5 h-3.5 text-emerald-500" />
          <span>生成的代码符合 FluxForge ESModule 标准，支持 discovery / search / detail / parse</span>
        </div>

        <div class="flex items-center gap-2">
          <n-button size="small" class="!rounded-xl" @click="emit('update:show', false)">
            取消
          </n-button>
          <n-button
            type="primary"
            size="small"
            :disabled="!generatedCode"
            class="!rounded-xl !font-bold"
            @click="handleApply"
          >
            <template #icon>
              <Check class="w-3.5 h-3.5" />
            </template>
            应用到当前规则
          </n-button>
        </div>
      </div>
    </template>
  </n-modal>
</template>

<style scoped>
</style>
