<script setup lang="ts">
import { ref, useTemplateRef, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'

defineOptions({ name: 'EditView' })
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import { ruleService, type RuleSchema, type MediaType } from '@/utils/ruleService'
import {
  RefreshCcw,
  Save,
  ArrowLeft,
  Copy,
  Download,
  Play,
  Code,
  Sparkles,
  Bot,
  Terminal,
  Layers,
  Globe,
  FileCode,
  Sliders,
  PanelLeftClose,
  PanelLeftOpen,
  Info,
  CheckCircle2
} from '@lucide/vue'
import CodeEditor from '@/components/CodeEditor/index.vue'
import AiRuleModal from './components/AiRuleModal.vue'
import RuleTestWorkbench from './components/RuleTestWorkbench.vue'

const route = useRoute()
const router = useRouter()
const message = useMessage()

const showAiModal = ref(false)
const showTestWorkbench = ref(false)
const showMetaSidebar = ref(true)

const formRef = useTemplateRef('formRef')
const form = ref<Partial<RuleSchema>>({
  name: '',
  description: '',
  type: 'video',
  author: '系统管理员',
  version: '1.0.0',
  baseUrl: '',
  code: `import axios from 'axios'
import * as cheerio from 'cheerio'

export default {
  // 1. 发现流
  async discovery({ category, page = 1 }) {
    return {
      categories: ['最新', '热门'],
      items: [
        {
          key: 'item_1',
          title: '示例项目',
          cover: 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=500',
          badge: '高清',
          desc: '示例描述'
        }
      ],
      hasMore: false
    }
  },

  // 2. 搜索
  async search({ keyword, page = 1 }) {
    return {
      items: [],
      hasMore: false
    }
  },

  // 3. 详情
  async detail({ key, item }) {
    return {
      title: item?.title || '详情标题',
      cover: item?.cover,
      desc: '正文介绍',
      tags: ['精选'],
      playUrl: ''
    }
  },

  // 4. 解析
  async parse({ key }) {
    return {
      playUrl: key
    }
  }
}`
})

const submitLoading = ref(false)

const loadData = async () => {
  const id = route.query.id
  if (!id) return
  const result = await ruleService.getRuleById(id as string)
  if (result) {
    form.value = { ...result }
  }
}

const onReset = () => {
  form.value = {
    name: '',
    description: '',
    type: 'video',
    author: '系统管理员',
    version: '1.0.0',
    baseUrl: '',
    code: `export default {\n  async discovery({ category, page = 1 }) {\n    return { items: [] }\n  }\n}`
  }
}

const onSubmit = async () => {
  let { warnings } = await formRef.value?.validate()
  if (warnings) return

  submitLoading.value = true
  try {
    const saved = await ruleService.saveRule(form.value)
    message.success('保存规则成功')
    if (!route.query.id && saved?.id) {
      router.replace(`/rules/edit?id=${saved.id}`)
    } else {
      await loadData()
    }
  } catch (error: any) {
    message.error('保存失败: ' + error.message)
  } finally {
    submitLoading.value = false
  }
}

const openTestWorkbench = () => {
  showTestWorkbench.value = true
}

const copyRule = async () => {
  try {
    const { id, created_at, updated_at, ...rest } = form.value
    const jsonStr = JSON.stringify(rest, null, 2)
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(jsonStr)
      message.success('已复制当前规则配置到剪贴板')
    }
  } catch (error: any) {
    message.error('复制失败: ' + error.message)
  }
}

const exportRule = () => {
  try {
    const { id, created_at, updated_at, ...rest } = form.value
    const jsonStr = JSON.stringify(rest, null, 2)
    const blob = new Blob([jsonStr], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${form.value.name || 'rule'}.json`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    message.success('已导出规则文件')
  } catch (error: any) {
    message.error('导出失败: ' + error.message)
  }
}

const handleApplyAiRule = (payload: { code: string; baseUrl: string; type: string; name?: string }) => {
  form.value.code = payload.code
  if (payload.baseUrl) form.value.baseUrl = payload.baseUrl
  if (payload.type) form.value.type = payload.type as any
  if (payload.name && !form.value.name) form.value.name = payload.name
}

const handleKeydown = (e: KeyboardEvent) => {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    e.preventDefault()
    openTestWorkbench()
  }
}

onMounted(() => {
  loadData()
  window.addEventListener('keydown', handleKeydown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeydown)
})
</script>

<template>
  <div class="w-full h-full flex flex-col gap-3 overflow-hidden">
    <!-- 1. 顶部操作工具栏 (IDE Header) -->
    <div class="glass-panel rounded-2xl px-4 py-2.5 sm:px-5 sm:py-3 flex flex-wrap items-center justify-between gap-3 shadow-xs shrink-0 border border-emerald-100/60 dark:border-white/5">
      <!-- 左侧：返回、标题与状态标签 -->
      <div class="flex items-center gap-3 min-w-0">
        <n-button
          quaternary
          size="small"
          class="!p-2 !rounded-xl"
          @click="router.back()"
          title="返回规则列表"
        >
          <template #icon>
            <ArrowLeft class="w-4 h-4" />
          </template>
        </n-button>

        <div class="flex items-center gap-2.5 min-w-0">
          <h1 class="text-sm sm:text-base font-black tracking-tight text-zinc-900 dark:text-white truncate max-w-[200px] sm:max-w-[320px]">
            {{ form.name || (route.query.id ? '编辑规则' : '新建规则') }}
          </h1>

          <div class="flex items-center gap-1.5 shrink-0">
            <span
              v-if="form.type"
              class="px-2 py-0.5 text-[10px] font-bold rounded-md uppercase"
              :class="{
                'bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 border border-rose-200/40': form.type === 'video',
                'bg-amber-50 dark:bg-amber-950/40 text-amber-600 dark:text-amber-400 border border-amber-200/40': form.type === 'picture',
                'bg-cyan-50 dark:bg-cyan-950/40 text-cyan-600 dark:text-cyan-400 border border-cyan-200/40': form.type === 'novel'
              }"
            >
              {{ form.type === 'video' ? '视频' : form.type === 'picture' ? '图片' : '小说' }}
            </span>
            <span class="px-2 py-0.5 text-[10px] font-mono rounded-md bg-zinc-100 dark:bg-white/[0.06] text-zinc-500 border border-zinc-200/50 dark:border-white/5">
              v{{ form.version || '1.0.0' }}
            </span>
          </div>
        </div>
      </div>

      <!-- 右侧：核心功能与操作按钮组 -->
      <div class="flex items-center gap-2 flex-wrap">
        <!-- 切换侧边栏展开/收起 -->
        <n-button
          size="small"
          quaternary
          class="!rounded-xl !p-2 text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200"
          @click="showMetaSidebar = !showMetaSidebar"
          :title="showMetaSidebar ? '收起配置侧边栏 (代码全屏)' : '展开配置侧边栏'"
        >
          <template #icon>
            <PanelLeftClose v-if="showMetaSidebar" class="w-4 h-4" />
            <PanelLeftOpen v-else class="w-4 h-4" />
          </template>
        </n-button>

        <!-- AI 智能生成规则 -->
        <n-button
          size="small"
          type="primary"
          class="!rounded-xl !font-bold !bg-gradient-to-r !from-emerald-600 !to-teal-500 hover:!opacity-95 shadow-md shadow-emerald-500/20"
          @click="showAiModal = true"
        >
          <template #icon>
            <Sparkles class="w-3.5 h-3.5 text-white animate-pulse" />
          </template>
          <span>AI 智能生成</span>
        </n-button>

        <!-- 打开测试工作台 -->
        <n-button
          size="small"
          type="primary"
          secondary
          class="!rounded-xl !font-bold"
          @click="openTestWorkbench"
          title="运行沙箱测试 (Ctrl+Enter)"
        >
          <template #icon>
            <Play class="w-3.5 h-3.5 fill-current text-emerald-600 dark:text-emerald-400" />
          </template>
          <span>测试运行 (Ctrl+Enter)</span>
        </n-button>

        <!-- 辅助功能下拉/按键 -->
        <n-button
          v-if="route.query.id"
          size="small"
          secondary
          class="!rounded-xl"
          @click="copyRule"
          title="复制当前规则 JSON"
        >
          <template #icon>
            <Copy class="w-3.5 h-3.5" />
          </template>
        </n-button>

        <n-button
          v-if="route.query.id"
          size="small"
          secondary
          class="!rounded-xl"
          @click="exportRule"
          title="导出规则文件"
        >
          <template #icon>
            <Download class="w-3.5 h-3.5" />
          </template>
        </n-button>

        <!-- 重置 -->
        <n-button
          size="small"
          secondary
          class="!rounded-xl"
          @click="onReset"
          title="重置代码与表单"
        >
          <template #icon>
            <RefreshCcw class="w-3.5 h-3.5" />
          </template>
        </n-button>

        <!-- 保存按钮 -->
        <n-button
          size="small"
          type="primary"
          class="!rounded-xl !font-bold !px-4 shadow-md shadow-emerald-500/20"
          :loading="submitLoading"
          @click="onSubmit"
        >
          <template #icon>
            <Save class="w-3.5 h-3.5" />
          </template>
          <span>保存规则</span>
        </n-button>
      </div>
    </div>

    <!-- 2. 主体分栏工作台 (Left: Metadata Form | Right: 100% Fluid Monaco Editor) -->
    <div class="flex-1 flex gap-3 min-h-0 overflow-hidden">
      <!-- 左侧：规则配置侧边栏 (Metadata) -->
      <div
        class="shrink-0 transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)] overflow-hidden flex flex-col h-full"
        :class="showMetaSidebar ? 'w-80 xl:w-96 opacity-100' : 'w-0 opacity-0 pointer-events-none -mr-3'"
      >
        <div class="glass-panel rounded-2xl p-4 sm:p-5 flex-1 flex flex-col gap-3.5 shadow-xs border border-emerald-100/60 dark:border-white/5 overflow-y-auto h-full w-80 xl:w-96">
          <div class="flex items-center justify-between pb-2 border-b border-emerald-100/50 dark:border-white/5 shrink-0">
            <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
              <Sliders class="w-3.5 h-3.5 text-emerald-500" />
              <span>规则元数据与配置</span>
            </div>
            <span class="text-[10px] text-zinc-400">基本信息</span>
          </div>

          <n-form ref="formRef" :model="form" class="space-y-3 shrink-0">
            <n-form-item label="规则标识名称" path="name" :rule="{ required: true, message: '请输入规则名称' }">
              <n-input v-model:value="form.name" clearable placeholder="如: 全面屏超清壁纸, JAVMENU" class="!rounded-xl text-xs" />
            </n-form-item>

            <n-form-item label="媒体类型" path="type" :rule="{ required: true, message: '请选择规则媒体类型' }">
              <n-select
                v-model:value="form.type"
                :options="[
                  { label: '视频 (Video)', value: 'video' },
                  { label: '图片 (Picture)', value: 'picture' },
                  { label: '小说 (Novel)', value: 'novel' }
                ]"
                class="!rounded-xl"
              />
            </n-form-item>

            <n-form-item label="目标站点根域名 (Base URL)" path="baseUrl">
              <n-input v-model:value="form.baseUrl" clearable placeholder="https://example.com" class="!rounded-xl font-mono text-xs" />
            </n-form-item>

            <n-form-item label="规则描述">
              <n-input v-model:value="form.description" type="textarea" :autosize="{ minRows: 2, maxRows: 3 }" clearable placeholder="规则的详细说明及特性..." class="!rounded-xl text-xs" />
            </n-form-item>

            <div class="grid grid-cols-2 gap-2">
              <n-form-item label="作者" path="author">
                <n-input v-model:value="form.author" clearable class="!rounded-xl text-xs" />
              </n-form-item>
              <n-form-item label="版本号" path="version">
                <n-input v-model:value="form.version" clearable placeholder="1.0.0" class="!rounded-xl font-mono text-xs" />
              </n-form-item>
            </div>
          </n-form>

          <!-- 底部小规范贴士 -->
          <div class="mt-auto p-3 rounded-xl bg-emerald-50/60 dark:bg-white/[0.02] border border-emerald-200/40 dark:border-white/5 space-y-1.5 text-[11px] text-zinc-500 dark:text-zinc-400 shrink-0">
            <div class="flex items-center gap-1 font-bold text-emerald-700 dark:text-emerald-300">
              <Info class="w-3.5 h-3.5" />
              <span>沙箱环境规范提示</span>
            </div>
            <ul class="list-disc pl-3.5 space-y-0.5 text-[10px]">
              <li>全局预置: <code class="text-emerald-600 font-mono">ua</code> (浏览器 User-Agent)</li>
              <li>四大方法: <code class="text-emerald-600 font-mono">discovery, search, detail, parse</code></li>
              <li>视频直链必须挂载在 <code class="text-emerald-600 font-mono">playUrl</code> 字段</li>
            </ul>
          </div>
        </div>
      </div>

      <!-- 右侧：100% 全宽沉浸式 Monaco 代码编辑器 -->
      <div class="flex-1 flex flex-col min-w-0 glass-panel rounded-2xl overflow-hidden shadow-xs border border-emerald-100/60 dark:border-white/5 transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)] h-full">
        <!-- 编辑器顶部状态条 -->
        <div class="px-4 py-2 border-b border-emerald-100/50 dark:border-white/5 flex items-center justify-between bg-zinc-50/70 dark:bg-white/[0.02] shrink-0">
          <div class="flex items-center gap-2">
            <div class="w-1.5 h-4 rounded-full bg-gradient-to-b from-emerald-500 to-teal-500"></div>
            <span class="text-xs font-bold text-zinc-800 dark:text-zinc-200">
              ESModule 沙箱规则脚本 (内置 Axios & Cheerio)
            </span>
          </div>

          <div class="flex items-center gap-2 text-xs text-zinc-400">
            <span class="font-mono text-[11px]">JavaScript</span>
          </div>
        </div>

        <!-- Monaco 代码编辑器主体 (100% 自适应撑满容器，无滚动条溢出) -->
        <div class="flex-1 w-full relative min-h-0 h-full overflow-hidden">
          <code-editor
            v-model="form.code"
            model-id="rule_main_editor"
            height="100%"
            class="w-full h-full"
          />
        </div>
      </div>
    </div>

    <!-- AI 规则智能生成弹窗 -->
    <AiRuleModal
      v-model:show="showAiModal"
      :default-base-url="form.baseUrl"
      :default-type="form.type"
      @apply="handleApplyAiRule"
    />

    <!-- 专业级沙箱测试工作台 (内置 AI 智能诊断与修复) -->
    <RuleTestWorkbench
      v-model:show="showTestWorkbench"
      :code="form.code || ''"
      :base-url="form.baseUrl"
      :rule-type="form.type"
      :rule-name="form.name"
      @update:code="(val) => (form.code = val)"
    />
  </div>
</template>

<style scoped>
</style>