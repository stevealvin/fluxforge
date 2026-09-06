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
  AlertCircle,
  Eye,
  History,
  RotateCcw,
  Wrench
} from '@lucide/vue'
import CodeEditor from '@/components/CodeEditor/index.vue'
import RuleWorkbenchModal from './components/RuleWorkbenchModal.vue'
import WorkbenchSandbox from './components/workbench/WorkbenchSandbox.vue'
import { useAiSettingsStore } from '@/stores/aiSettings'

const route = useRoute()
const router = useRouter()
const message = useMessage()
const aiStore = useAiSettingsStore()

// AI 工作台与左侧元数据配置默认展开
const showWorkbench = ref(true)
const showMetaSidebar = ref(true)
const sandboxCollapsed = ref(false)

const sandboxRef = useTemplateRef<any>('sandboxRef')
const workbenchRef = useTemplateRef<any>('workbenchRef')

// 标准 ESModule defineRule 模板代码
const RULE_TEMPLATE = `export default defineRule({
  // 1. 发现列表
  // 全局可用: baseUrl (站点根域名), axios (HTTP客户端), cheerio (HTML解析器), ua (User-Agent)
  async discovery({ tab = '', page = 1 }) {
    // TODO: 请求并提取数据

    return {
      tabs: [
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

// 数据库已保存代码快照 (进入页面时从数据库读取的原始代码)
const originalCode = ref('')
const showSavedCodeModal = ref(false)

// 判断当前编辑器代码是否相对数据库已保存版本发生改动
const hasCodeChangedFromSaved = computed(() => {
  if (!route.query.id && !originalCode.value) return false
  return (form.value.code || '').trim() !== (originalCode.value || '').trim()
})

// 复制数据库已保存的代码
const copySavedCode = async () => {
  if (!originalCode.value) return
  try {
    await navigator.clipboard.writeText(originalCode.value)
    message.success('已复制已保存代码到剪贴板')
  } catch {
    message.error('复制失败')
  }
}

// 还原为数据库已保存代码
const restoreOriginalCode = () => {
  if (!originalCode.value) return
  window.$dialog?.warning({
    title: '还原确认',
    content: '确定要将当前编辑器的代码还原为数据库已保存的版本吗？当前未保存的修改将被覆盖。',
    positiveText: '确认还原',
    negativeText: '取消',
    onPositiveClick: () => {
      form.value.code = originalCode.value
      showSavedCodeModal.value = false
      message.success('已成功还原为数据库已保存代码')
    }
  })
}

const submitLoading = ref(false)
const pageLoading = ref(Boolean(route.query.id))
const loadError = ref('')

const loadData = async () => {
  const id = route.query.id
  if (!id) {
    pageLoading.value = false
    return
  }

  pageLoading.value = true
  loadError.value = ''
  try {
    const result = await ruleService.getRuleById(id as string)
    if (result) {
      form.value = { ...result }
      originalCode.value = result.code || ''
    } else {
      loadError.value = '未找到对应的规则数据，可能已被删除'
    }
  } catch (err: any) {
    loadError.value = err.message || '加载规则数据失败，请检查网络或服务端连接'
  } finally {
    pageLoading.value = false
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
    originalCode.value = form.value.code || ''
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

// 智能识别站点元数据 (基于站点首页 HTML 与域名提炼站点名称与描述)
const identifyingSite = ref(false)
const handleIdentifySite = async () => {
  const targetUrl = form.value.baseUrl?.trim()
  if (!targetUrl || !targetUrl.startsWith('http')) {
    message.warning('请先输入有效的站点根域名 (如 https://example.com)')
    return
  }

  identifyingSite.value = true
  try {
    let html = ''
    try {
      const res: any = await http.post('/rules/fetch-page', { url: targetUrl })
      html = res?.data || ''
    } catch (e: any) {
      console.warn('抓取站点首页失败，将仅基于 URL 域名进行智能识别:', e.message)
    }

    const meta = await aiStore.extractSiteMetadata({
      url: targetUrl,
      htmlContent: html,
      useAi: true
    })

    if (meta.name) {
      form.value.name = meta.name
    }
    if (meta.description) {
      form.value.description = meta.description
    }

    message.success(`✨ 已成功识别站点信息: ${meta.name}`)
  } catch (err: any) {
    message.error(`识别站点信息失败: ${err.message || '网络或模型异常'}`)
  } finally {
    identifyingSite.value = false
  }
}

// 接收来自工作台的代码同步
const handleApplyWorkbench = (payload: {
  code: string
  baseUrl: string
  type: string
  name?: string
  description?: string
}) => {
  form.value.code = payload.code
  if (payload.baseUrl && !form.value.baseUrl) form.value.baseUrl = payload.baseUrl
  if (payload.type && !form.value.type) form.value.type = payload.type as any
  if (payload.name && !form.value.name) form.value.name = payload.name
  if (payload.description && !form.value.description) form.value.description = payload.description
}

// 响应沙箱异常 -> 自动展开右侧 AI 助手并注入诊断信息
const handleFixErrorFromSandbox = (context: any) => {
  if (!showWorkbench.value) showWorkbench.value = true
  setTimeout(() => {
    workbenchRef.value?.handleFixError?.(context)
  }, 100)
}

// 响应 AI 生成完毕后的自动测试 -> 驱动中下方的沙箱
const handleAutoTestFromAi = ({ action, code }: { action: string; code: string }) => {
  sandboxCollapsed.value = false
  setTimeout(() => {
    sandboxRef.value?.executeAction?.(action, code)
  }, 50)
}



const runWorkbenchAction = () => {
  sandboxCollapsed.value = false
  setTimeout(() => {
    sandboxRef.value?.executeAction?.()
  }, 50)
}

const handleKeydown = (e: KeyboardEvent) => {
  if ((e.ctrlKey || e.metaKey) && (e.key === 'r' || e.key === 'R')) {
    e.preventDefault()
    runWorkbenchAction()
  } else if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
    e.preventDefault()
    onSubmit()
  } else if (e.altKey && (e.key === 'w' || e.key === 'W')) {
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

        <!-- 切换底部沙箱面板 -->
        <n-button
          size="small"
          quaternary
          class="!rounded-xl !px-2.5 text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200"
          :type="!sandboxCollapsed ? 'primary' : 'default'"
          @click="sandboxCollapsed = !sandboxCollapsed"
          title="切换沙箱调试与结果面板"
        >
          <template #icon>
            <Terminal class="w-3.5 h-3.5" />
          </template>
          <span>调试面板</span>
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
          title="展开/收起 AI 智能与调试工作台 (Alt+W)"
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

    <!-- 2. 主体工作台状态分发 -->
    <!-- 2.1 加载失败错误态 -->
    <div
      v-if="loadError"
      class="flex-1 flex flex-col items-center justify-center p-8 text-center glass-panel rounded-2xl border border-rose-500/20 bg-rose-500/[0.03] shadow-xs"
    >
      <AlertCircle class="w-12 h-12 text-rose-500 mb-3" />
      <h3 class="text-sm font-bold text-rose-600 dark:text-rose-400 mb-1">规则加载失败</h3>
      <p class="text-xs text-zinc-500 dark:text-zinc-400 mb-4">{{ loadError }}</p>
      <div class="flex items-center gap-2">
        <n-button size="small" secondary class="!rounded-xl" @click="loadData">
          <template #icon><RefreshCcw class="w-3.5 h-3.5" /></template>
          <span>重新尝试</span>
        </n-button>
        <n-button size="small" type="primary" class="!rounded-xl" @click="router.back()">
          <span>返回规则列表</span>
        </n-button>
      </div>
    </div>

    <!-- 2.2 正在加载页面数据 (毛玻璃优雅微光态) -->
    <div
      v-else-if="pageLoading"
      class="flex-1 flex flex-col items-center justify-center glass-panel rounded-2xl border border-emerald-100/60 dark:border-white/5 space-y-3.5 shadow-xs"
    >
      <div class="relative flex items-center justify-center">
        <div class="w-12 h-12 rounded-full border-2 border-emerald-500/20 border-t-emerald-500 animate-spin"></div>
        <Sparkles class="w-5 h-5 text-emerald-500 absolute animate-pulse" />
      </div>
      <div class="text-center space-y-1">
        <span class="text-xs font-bold text-zinc-700 dark:text-zinc-200">正在载入规则脚本与配置...</span>
        <p class="text-[11px] text-zinc-400">读取远端数据库与代码沙箱环境</p>
      </div>
    </div>

    <!-- 2.3 主体三栏沉浸式工作台 (Left: Metadata | Center: Monaco + Terminal | Right: Studio Panel) -->
    <div v-else class="flex-1 flex gap-2.5 min-h-0 overflow-hidden">
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
            <!-- 1. 站点地址 (Base URL) [必填] -->
            <n-form-item
              label="站点根域名 (Base URL)"
              path="baseUrl"
              :rule="[
                { required: true, message: '请输入站点根域名 (如 https://example.com)', trigger: ['blur', 'input'] },
                {
                  validator: (_rule, value) => {
                    if (!value) return true
                    return /^https?:\/\//i.test(value.trim()) || new Error('站点根域名必须以 http:// 或 https:// 开头')
                  },
                  trigger: 'blur'
                }
              ]"
            >
              <div class="space-y-1.5 w-full">
                <n-input
                  v-model:value="form.baseUrl"
                  clearable
                  placeholder="https://example.com"
                  class="!rounded-xl font-mono text-xs w-full"
                  @keydown.enter.prevent="handleIdentifySite"
                />
                <n-button
                  size="small"
                  secondary
                  type="primary"
                  class="w-full !rounded-xl !font-bold text-xs"
                  :loading="identifyingSite"
                  @click="handleIdentifySite"
                  title="自动抓取首页并提炼网站名称与简介"
                >
                  <template #icon>
                    <Sparkles class="w-3.5 h-3.5" />
                  </template>
                  <span>智能识别填充站点信息</span>
                </n-button>
              </div>
            </n-form-item>

            <!-- 2. 媒体类型 [必填] -->
            <n-form-item label="媒体类型" path="type" :rule="{ required: true, message: '请选择媒体类型' }">
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

            <!-- 3. 网站名称 [必填] -->
            <n-form-item label="网站名称" path="name" :rule="{ required: true, message: '请输入网站名称' }">
              <n-input v-model:value="form.name" clearable placeholder="如: 全面屏超清壁纸, 极光影视" class="!rounded-xl text-xs" />
            </n-form-item>

            <n-form-item label="网站描述信息">
              <n-input v-model:value="form.description" type="textarea" :rows="3" clearable placeholder="网站的详细说明及主营资源特色介绍..." class="!rounded-xl text-xs" />
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

            <div class="flex items-center gap-2">
              <span class="font-mono text-[11px] text-zinc-400">JavaScript</span>

              <!-- 📜 查看已保存代码 (仅在编辑已有规则或有已保存代码时展示) -->
              <n-button
                v-if="route.query.id || originalCode"
                size="tiny"
                quaternary
                class="!rounded-lg text-xs transition-all"
                :class="hasCodeChangedFromSaved ? 'text-amber-600 dark:text-amber-400 font-bold bg-amber-500/10 hover:bg-amber-500/20' : 'text-zinc-600 dark:text-zinc-300'"
                @click="showSavedCodeModal = true"
                title="查看进入页面时从数据库读取的已保存代码版本"
              >
                <template #icon>
                  <History class="w-3.5 h-3.5" />
                </template>
                <span>已保存代码</span>
                <span
                  v-if="hasCodeChangedFromSaved"
                  class="w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse ml-0.5"
                  title="当前编辑器代码相比已保存版本有新改动"
                ></span>
              </n-button>

              <!-- 📥 插入模板 -->
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

        <!-- 底部：一体化沙箱调试工作台 (可视化预览 + JSON + 控制台终端) -->
        <WorkbenchSandbox
          ref="sandboxRef"
          :code="form.code || ''"
          :rule-type="form.type"
          :base-url="form.baseUrl || workbenchRef?.targetUrl"
          v-model:collapsed="sandboxCollapsed"
          @fix-error="handleFixErrorFromSandbox"
        />
      </div>

      <!-- 右栏：一体化智能工作台 (AI 目标采样管理 + AI 规则生成与诊断) -->
      <div
        class="shrink-0 transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)] overflow-hidden flex flex-col h-full"
        :class="showWorkbench ? 'w-[440px] xl:w-[480px] 2xl:w-[520px] opacity-100' : 'w-0 opacity-0 pointer-events-none -mr-2.5'"
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
          @auto-test="handleAutoTestFromAi"
          @close="showWorkbench = false"
        />
      </div>
    </div>

    <!-- 数据库已保存代码只读与还原弹窗 -->
    <n-modal
      v-model:show="showSavedCodeModal"
      preset="card"
      title="📜 数据库已保存规则代码 (初始加载版本)"
      class="!max-w-3xl !w-[92vw] !rounded-2xl shadow-2xl"
      :segmented="{ content: true, action: true }"
    >
      <div class="space-y-2.5">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-1.5 text-zinc-500 dark:text-zinc-400">
            <Info class="w-3.5 h-3.5 text-emerald-500" />
            <span>进入编辑时从数据库加载的已存代码。若当前代码被 AI 修改覆盖，可在此随时查看或一键还原。</span>
          </div>
          <span
            class="font-mono text-[11px] px-2 py-0.5 rounded-md font-bold shrink-0"
            :class="hasCodeChangedFromSaved ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400' : 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'"
          >
            {{ hasCodeChangedFromSaved ? '当前有未保存改动' : '与当前代码一致' }}
          </span>
        </div>

        <div class="h-[460px] rounded-xl overflow-hidden border border-zinc-200/80 dark:border-white/10 shadow-inner">
          <code-editor
            :model-value="originalCode"
            model-id="rule_saved_code_preview_modal"
            height="100%"
            class="w-full h-full"
            :options="{ readOnly: true, lineNumbers: 'on', minimap: { enabled: false } }"
          />
        </div>
      </div>
      <template #action>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="text-xs text-zinc-400">若对 AI 修改或当前代码不满意，可点击右侧按钮直接还原回数据库版本</span>
          <div class="flex items-center gap-2">
            <n-button size="small" secondary class="!rounded-xl" @click="copySavedCode">
              <template #icon><Copy class="w-3.5 h-3.5" /></template>
              <span>复制代码</span>
            </n-button>
            <n-button
              size="small"
              type="warning"
              secondary
              class="!rounded-xl !font-bold"
              :disabled="!hasCodeChangedFromSaved"
              @click="restoreOriginalCode"
            >
              <template #icon><RotateCcw class="w-3.5 h-3.5" /></template>
              <span>还原为已保存版本</span>
            </n-button>
          </div>
        </div>
      </template>
    </n-modal>
  </div>
</template>

<style scoped>
</style>