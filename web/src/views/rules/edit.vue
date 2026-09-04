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
  CheckCircle2,
  Wrench
} from '@lucide/vue'
import CodeEditor from '@/components/CodeEditor/index.vue'
import RuleWorkbenchModal from './components/RuleWorkbenchModal.vue'

const route = useRoute()
const router = useRouter()
const message = useMessage()

// AI 工作台默认展开；左侧元数据配置默认收起以留出足够空间
const showWorkbench = ref(true)
const showMetaSidebar = ref(false)

// 标准 ESModule defineRule 模板代码
const RULE_TEMPLATE = `export default defineRule({
  // 1. 发现列表
  // 全局可用: baseUrl (站点根域名), axios (HTTP客户端), cheerio (HTML解析器), ua (User-Agent)
  async discovery({ category = '', page = 1 }) {
    // TODO: 请求并提取数据

    return {
      categories: [
        // { title: '分类标题', url: '/category-url' }
      ],
      items: [
        // { title: '标题', url: '/detail-url', cover: '', desc: '', badge: '' }
      ],
      hasMore: false
    }
  },

  // 2. 搜索列表
  async search({ keyword, page = 1 }) {
    // TODO: 请求并提取搜索结果

    return {
      items: [
        // { title: '标题', url: '/detail-url', cover: '', desc: '', badge: '' }
      ],
      hasMore: false
    }
  },

  // 3. 详情信息与选集
  async detail({ url, item }) {
    // TODO: 请求并提取详情数据与选集列表

    return {
      title: item?.title || '',
      cover: item?.cover || '',
      desc: '',
      tags: [],
      author: '',
      groups: [
        // { name: '默认线路', items: [{ title: '第01集', url: '/play-url' }] }
      ]
      // 其它类型直出字段（按需选择）:
      // playUrl: ''  // 视频播放直链
      // images: []   // 图集写真大图列表
      // content: ''  // 小说章节正文
    }
  },

  // 4. 直链解析或正文提取
  async parse({ url, groupName }) {
    // TODO: 提取分集最终播放直链或小说正文

    return {
      playUrl: url
    }
  }
})`

const formRef = useTemplateRef('formRef')
const form = ref<Partial<RuleSchema>>({
  name: '',
  description: '',
  type: 'video',
  author: '系统管理员',
  version: '1.0.0',
  baseUrl: '',
  code: '' // 默认不设置代码，保持纯净空白
})

const handleInsertTemplate = () => {
  if (form.value.code && form.value.code.trim()) {
    window.$dialog?.warning({
      title: '覆盖确认',
      content: '当前编辑器中已有规则代码，插入模板将覆盖现有内容，确定继续吗？',
      positiveText: '确定覆盖',
      negativeText: '取消',
      onPositiveClick: () => {
        form.value.code = RULE_TEMPLATE
        message.success('已插入标准规则模板代码')
      }
    })
  } else {
    form.value.code = RULE_TEMPLATE
    message.success('已插入标准规则模板代码')
  }
}

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
    code: ''
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

const openWorkbench = () => {
  showWorkbench.value = true
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

// 接收来自工作台的智能回填数据 (代码、名称、描述、类型、BaseURL)
const handleApplyWorkbench = (payload: {
  code: string
  baseUrl: string
  type: string
  name?: string
  description?: string
}) => {
  form.value.code = payload.code
  if (payload.baseUrl) form.value.baseUrl = payload.baseUrl
  if (payload.type) form.value.type = payload.type as any
  if (payload.name) form.value.name = payload.name
  if (payload.description) form.value.description = payload.description
}

const showTerminal = ref(true)
const consoleLogs = ref<Array<{ level: string; time: string; message: string }>>([])
const workbenchRef = useTemplateRef<any>('workbenchRef')

const handleReceiveLogs = (logs: any[]) => {
  consoleLogs.value = logs || []
  if (logs && logs.length > 0) {
    showTerminal.value = true
  }
}

const runWorkbenchAction = () => {
  if (!showWorkbench.value) showWorkbench.value = true
  setTimeout(() => {
    workbenchRef.value?.executeAction?.()
  }, 50)
}

const handleKeydown = (e: KeyboardEvent) => {
  if ((e.ctrlKey || e.metaKey) && (e.key === 'r' || e.key === 'R')) {
    e.preventDefault()
    runWorkbenchAction()
  } else if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
    e.preventDefault()
    onSubmit()
  } else if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    e.preventDefault()
    showWorkbench.value = !showWorkbench.value
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
  <div class="w-full h-full flex flex-col gap-2.5 overflow-hidden">
    <!-- 1. 顶部操作工具栏 (IDE Header) -->
    <div class="glass-panel rounded-2xl px-4 py-2 sm:px-5 sm:py-2.5 flex flex-wrap items-center justify-between gap-3 shadow-xs shrink-0 border border-emerald-100/60 dark:border-white/5">
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
        <!-- 切换配置侧边栏 -->
        <n-button
          size="small"
          quaternary
          class="!rounded-xl !px-2.5 text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200"
          :type="showMetaSidebar ? 'primary' : 'default'"
          @click="showMetaSidebar = !showMetaSidebar"
          :title="showMetaSidebar ? '收起配置侧栏' : '展开规则基础配置侧栏'"
        >
          <template #icon>
            <Sliders class="w-3.5 h-3.5" />
          </template>
          <span>{{ showMetaSidebar ? '收起配置' : '配置' }}</span>
        </n-button>

        <!-- 切换底部控制台 -->
        <n-button
          size="small"
          quaternary
          class="!rounded-xl !px-2.5 text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200"
          :type="showTerminal ? 'primary' : 'default'"
          @click="showTerminal = !showTerminal"
          title="切换沙箱控制台 (Console Logs)"
        >
          <template #icon>
            <Terminal class="w-3.5 h-3.5" />
          </template>
          <span>控制台 {{ consoleLogs.length > 0 ? `(${consoleLogs.length})` : '' }}</span>
        </n-button>

        <!-- 快捷运行测试按钮 (Ctrl+R) -->
        <n-button
          size="small"
          secondary
          type="primary"
          class="!rounded-xl !font-bold !px-3 shadow-xs"
          @click="runWorkbenchAction"
          title="运行当前沙箱测试 (Ctrl+R)"
        >
          <template #icon>
            <Play class="w-3.5 h-3.5 fill-current" />
          </template>
          <span>运行测试 (Ctrl+R)</span>
        </n-button>

        <!-- 🚀 一体化规则调试工作台切换 -->
        <n-button
          size="small"
          type="primary"
          class="!rounded-xl !font-bold !px-3 !bg-gradient-to-r !from-emerald-600 !via-teal-500 !to-cyan-500 hover:!opacity-95 shadow-md shadow-emerald-500/25"
          @click="showWorkbench = !showWorkbench"
          title="展开/收起 AI 智能与调试工作台 (Ctrl+Enter)"
        >
          <template #icon>
            <Sparkles class="w-3.5 h-3.5 text-white animate-pulse" />
          </template>
          <span>{{ showWorkbench ? '收起工作台' : 'AI 智能工作台' }}</span>
        </n-button>

        <!-- 辅助按键 -->
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

        <!-- 保存按钮 (Ctrl+S) -->
        <n-button
          size="small"
          type="primary"
          class="!rounded-xl !font-bold !px-3.5 shadow-md shadow-emerald-500/20"
          :loading="submitLoading"
          @click="onSubmit"
          title="保存当前规则 (Ctrl+S)"
        >
          <template #icon>
            <Save class="w-3.5 h-3.5" />
          </template>
          <span>保存</span>
        </n-button>
      </div>
    </div>

    <!-- 2. 主体三栏沉浸式工作台 (Left: Metadata | Center: Monaco + Terminal | Right: Studio Panel) -->
    <div class="flex-1 flex gap-2.5 min-h-0 overflow-hidden">
      <!-- 左栏：规则配置侧边栏 (Metadata) -->
      <div
        class="shrink-0 transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)] overflow-hidden flex flex-col h-full"
        :class="showMetaSidebar ? 'w-80 xl:w-88 opacity-100' : 'w-0 opacity-0 pointer-events-none -mr-2.5'"
      >
        <div class="glass-panel rounded-2xl p-4 sm:p-5 flex-1 flex flex-col gap-3.5 shadow-xs border border-emerald-100/60 dark:border-white/5 overflow-y-auto h-full w-80 xl:w-88">
          <div class="flex items-center justify-between pb-2 border-b border-emerald-100/50 dark:border-white/5 shrink-0">
            <div class="flex items-center gap-2 text-xs font-bold text-zinc-800 dark:text-zinc-200">
              <Sliders class="w-3.5 h-3.5 text-emerald-500" />
              <span>规则元数据与配置</span>
            </div>
            <span class="text-[10px] text-zinc-400">基本信息</span>
          </div>

          <n-form ref="formRef" :model="form" class="space-y-3 shrink-0">
            <n-form-item label="规则标识名称" path="name" :rule="{ required: true, message: '请输入规则名称' }">
              <n-input v-model:value="form.name" clearable placeholder="如: 全面屏超清壁纸, 极光影视" class="!rounded-xl text-xs" />
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
              <n-input v-model:value="form.description" type="textarea" :rows="3" clearable placeholder="规则的详细说明及特性..." class="!rounded-xl text-xs" />
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
              <li>内置全局变量: <code class="text-emerald-600 font-mono">baseUrl</code>, <code class="text-emerald-600 font-mono">ua</code></li>
              <li>四大标准生命周期: <code class="text-emerald-600 font-mono">discovery, search, detail, parse</code></li>
              <li>快捷调试: <kbd class="px-1 py-0.5 bg-white dark:bg-zinc-800 rounded border border-zinc-200 dark:border-zinc-700">Ctrl+R</kbd> 运行测试</li>
            </ul>
          </div>
        </div>
      </div>

      <!-- 中栏：Monaco 代码编辑器 (代码永远可见、随改随测) + 底部沙箱控制台 Terminal -->
      <div class="flex-1 flex flex-col min-w-0 h-full gap-2.5 transition-all duration-300">
        <!-- Monaco 代码编辑器主体 -->
        <div class="flex-1 min-h-0 glass-panel rounded-2xl overflow-hidden shadow-xs border border-emerald-100/60 dark:border-white/5 flex flex-col">
          <!-- 编辑器顶部状态条 -->
          <div class="px-4 py-2 border-b border-emerald-100/50 dark:border-white/5 flex items-center justify-between bg-zinc-50/70 dark:bg-white/[0.02] shrink-0">
            <div class="flex items-center gap-2">
              <div class="w-1.5 h-4 rounded-full bg-gradient-to-b from-emerald-500 to-teal-500"></div>
              <span class="text-xs font-bold text-zinc-800 dark:text-zinc-200">
                ESModule 沙箱规则脚本 (内置 Axios, Cheerio, defineRule)
              </span>
            </div>

            <div class="flex items-center gap-2.5">
              <span class="font-mono text-[11px] text-zinc-400">JavaScript</span>
              <n-button
                size="tiny"
                secondary
                type="primary"
                class="!rounded-lg !font-bold !px-2.5 shadow-2xs"
                @click="handleInsertTemplate"
                title="向当前编辑器插入标准规则模板代码"
              >
                <template #icon>
                  <FileCode class="w-3.5 h-3.5" />
                </template>
                <span>插入模板</span>
              </n-button>
            </div>
          </div>

          <!-- Monaco 代码编辑器主体 -->
          <div class="flex-1 w-full relative min-h-0 overflow-hidden">
            <code-editor
              v-model="form.code"
              model-id="rule_main_editor"
              height="100%"
              class="w-full h-full"
            />
          </div>
        </div>

        <!-- 底部：沙箱控制台 Terminal (Console Logs) -->
        <div
          v-if="showTerminal"
          class="h-44 shrink-0 rounded-2xl overflow-hidden shadow-lg border border-zinc-700/60 dark:border-white/10 flex flex-col bg-zinc-950 text-zinc-100 transition-all"
        >
          <!-- Terminal 顶栏 (高对比度深色面板顶条) -->
          <div class="px-3.5 py-1.5 border-b border-zinc-800 flex items-center justify-between bg-zinc-900/90 shrink-0 select-none">
            <div class="flex items-center gap-2">
              <Terminal class="w-3.5 h-3.5 text-emerald-400" />
              <span class="text-xs font-mono font-bold text-white tracking-wide">沙箱运行控制台 (Console Terminal)</span>
              <span v-if="consoleLogs.length > 0" class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                {{ consoleLogs.length }} 条输出
              </span>
            </div>

            <div class="flex items-center gap-3">
              <button
                v-if="consoleLogs.length > 0"
                type="button"
                class="text-xs font-mono text-zinc-300 hover:text-white transition-colors cursor-pointer"
                @click="consoleLogs = []"
                title="清空控制台日志"
              >
                清空
              </button>
              <button
                type="button"
                class="text-xs font-mono text-zinc-300 hover:text-white transition-colors cursor-pointer"
                @click="showTerminal = false"
                title="收起控制台"
              >
                收起
              </button>
            </div>
          </div>

          <!-- Terminal 日志列表 -->
          <div class="flex-1 min-h-0 overflow-y-auto p-3 font-mono text-xs space-y-1.5 selection:bg-emerald-500/40">
            <div v-if="consoleLogs.length === 0" class="h-full flex flex-col items-center justify-center text-zinc-400 space-y-1.5">
              <Terminal class="w-6 h-6 text-emerald-500/40" />
              <p class="text-xs font-medium text-zinc-200">暂无沙箱控制台输出</p>
              <p class="text-[11px] text-zinc-400">在规则代码中写入 <code class="text-emerald-400 font-bold">console.log(...)</code>，运行测试后将在此高亮显示</p>
            </div>
            <div
              v-for="(log, idx) in consoleLogs"
              :key="idx"
              class="flex items-start gap-2.5 py-1 leading-relaxed hover:bg-white/[0.05] px-2 rounded transition-colors"
            >
              <span class="text-[11px] text-zinc-400 font-mono shrink-0 select-none">[{{ log.time }}]</span>
              <span
                class="text-[10px] px-1.5 py-0.2 rounded font-bold uppercase select-none shrink-0 border"
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
      </div>

      <!-- 右栏：一体化智能工作台 (AI 智能生成 + 沙箱测试 + AI 诊断修复) -->
      <div
        class="shrink-0 transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)] overflow-hidden flex flex-col h-full"
        :class="showWorkbench ? 'w-[540px] xl:w-[600px] 2xl:w-[660px] opacity-100' : 'w-0 opacity-0 pointer-events-none -mr-2.5'"
      >
        <RuleWorkbenchModal
          ref="workbenchRef"
          embedded
          :code="form.code || ''"
          :base-url="form.baseUrl"
          :rule-type="form.type"
          :rule-name="form.name"
          :rule-description="form.description"
          @update:code="(val) => (form.code = val)"
          @apply="handleApplyWorkbench"
          @logs="handleReceiveLogs"
          @close="showWorkbench = false"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>