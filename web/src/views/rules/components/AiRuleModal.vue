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
  ArrowRight,
  Compass,
  FileText,
  Terminal,
  SearchCheck,
  CheckCircle2
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

// URL 多页面输入
const targetUrl = ref(props.defaultBaseUrl || '') // 发现/列表页 URL
const detailUrl = ref('')                        // 详情页示例 URL
const parseUrl = ref('')                         // 播放/解析页示例 URL
const mediaType = ref(props.defaultType || 'video')
const ruleName = ref('')
const requirement = ref('')

// 各页面数据源码片段 (直接存储返回的文本数据)
const listHtml = ref('')
const detailHtml = ref('')
const parseHtml = ref('')

// 抓取与生成状态
const fetchingList = ref(false)
const fetchingDetail = ref(false)
const fetchingParse = ref(false)
const autoSniffed = ref(false)
const generating = ref(false)
const generatedCode = ref('')
const activeHtmlTab = ref<'list' | 'detail' | 'parse'>('list')

const mediaTypeOptions = [
  { label: '视频规则 (video)', value: 'video' },
  { label: '图片规则 (picture)', value: 'picture' },
  { label: '小说规则 (novel)', value: 'novel' }
]

/**
 * 通用智能详情链接嗅探器 (支持从 HTML 或 JSON 文本中自动定位首条详情 URL)
 */
const sniffDetailUrl = (rawContent: string, base: string): string => {
  if (!rawContent || !base) return ''
  const trimmed = rawContent.trim()

  // 1. 如果是 JSON 数据
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const data = JSON.parse(trimmed)
      let items: any[] = []
      if (Array.isArray(data)) {
        items = data
      } else if (typeof data === 'object' && data !== null) {
        const candidates = ['list', 'data', 'items', 'results', 'vod_list', 'books', 'rows', 'data_list', 'posts']
        for (const key of candidates) {
          if (Array.isArray(data[key]) && data[key].length > 0) {
            items = data[key]
            break
          }
        }
        if (items.length === 0 && data.data && typeof data.data === 'object') {
          for (const key of candidates) {
            if (Array.isArray(data.data[key]) && data.data[key].length > 0) {
              items = data.data[key]
              break
            }
          }
        }
      }

      if (items.length > 0 && items[0] && typeof items[0] === 'object') {
        const first = items[0]
        const urlKeys = ['url', 'link', 'detail_url', 'detailUrl', 'href', 'page_url', 'view_url']
        for (const k of urlKeys) {
          if (typeof first[k] === 'string' && first[k].trim()) {
            return new URL(first[k].trim(), base).href
          }
        }
        const idKeys = ['id', 'vod_id', 'vodId', 'book_id', 'bookId', 'media_id', 'mediaId', 'code', 'key']
        for (const k of idKeys) {
          if (first[k] !== undefined && first[k] !== null && String(first[k]).trim()) {
            const idVal = String(first[k]).trim()
            if (base.includes('?ac=list') || base.includes('?ac=videolist')) {
              return base.replace(/\?ac=(list|videolist)/, `?ac=detail&ids=${idVal}`)
            }
            if (base.includes('/list')) {
              return base.replace(/\/list.*$/, `/detail/${idVal}`)
            }
            const u = new URL(base)
            return `${u.origin}${u.pathname.replace(/\/+$/, '')}/${idVal}`
          }
        }
      }
    } catch {
      // JSON 解析失败则转入 HTML 嗅探
    }
  }

  // 2. 如果是 HTML 数据
  try {
    const parser = new DOMParser()
    const doc = parser.parseFromString(rawContent, 'text/html')

    const ignoredSelectors = 'header, nav, footer, .menu, .navbar, .sidebar, #header, #footer, .header, .footer, .nav, .top-bar, .user-panel'
    doc.querySelectorAll(ignoredSelectors).forEach(el => el.remove())

    const links = Array.from(doc.querySelectorAll('a[href]'))
    const candidateLinks = links.filter(a => {
      const href = (a.getAttribute('href') || '').trim()
      if (!href || href === '#' || href === '/' || href.startsWith('javascript:') || href.startsWith('mailto:')) return false
      if (href.includes('login') || href.includes('register') || href.includes('about') || href.includes('contact') || href.includes('search')) return false
      return true
    })

    const imgLink = candidateLinks.find(a => {
      const hasImg = a.querySelector('img')
      const classStr = a.className.toLowerCase()
      const isCard = classStr.includes('pic') || classStr.includes('cover') || classStr.includes('poster') || classStr.includes('thumb') || classStr.includes('item')
      return hasImg || isCard
    })
    if (imgLink) {
      return new URL(imgLink.getAttribute('href')!, base).href
    }

    const patternLink = candidateLinks.find(a => {
      const href = a.getAttribute('href')!
      return /\/(detail|show|view|item|v|p|read|book|vod|drama|article|\d+)(\/|\.|$|\?)/i.test(href)
    })
    if (patternLink) {
      return new URL(patternLink.getAttribute('href')!, base).href
    }

    if (candidateLinks.length > 0) {
      return new URL(candidateLinks[0].getAttribute('href')!, base).href
    }
  } catch (e) {
    console.warn('智能探测详情链接失败:', e)
  }
  return ''
}

// 抓取列表/发现页数据
const handleFetchListHtml = async () => {
  if (!targetUrl.value.trim() || !targetUrl.value.startsWith('http')) {
    message.warning('请先输入有效的列表/发现页 URL')
    return
  }

  fetchingList.value = true
  autoSniffed.value = false
  try {
    const res: any = await http.post('/rules/fetch-page', {
      url: targetUrl.value.trim()
    })
    const data = res?.data || ''
    if (data) {
      listHtml.value = data.slice(0, 30000)
      message.success(`列表数据抓取成功 (${(data.length / 1024).toFixed(1)} KB)`)

      // 自动嗅探首条详情链接
      const detected = sniffDetailUrl(data, targetUrl.value.trim())
      if (detected) {
        detailUrl.value = detected
        autoSniffed.value = true
        message.info(`已自动嗅探到首条详情链接: ${detected}`)
        handleFetchDetailHtml()
      }
    } else {
      message.warning('抓取到的列表数据为空')
    }
  } catch (err: any) {
    message.error(err.response?.data?.message || err.message || '抓取列表数据失败')
  } finally {
    fetchingList.value = false
  }
}

// 抓取详情页/接口数据
const handleFetchDetailHtml = async () => {
  if (!detailUrl.value.trim() || !detailUrl.value.startsWith('http')) {
    message.warning('请先输入有效的详情页/接口示例 URL')
    return
  }

  fetchingDetail.value = true
  try {
    const res: any = await http.post('/rules/fetch-page', {
      url: detailUrl.value.trim()
    })
    const data = res?.data || ''
    if (data) {
      detailHtml.value = data.slice(0, 30000)
      message.success(`详情数据抓取成功 (${(data.length / 1024).toFixed(1)} KB)`)
    } else {
      message.warning('抓取到的详情数据为空')
    }
  } catch (err: any) {
    message.error(err.response?.data?.message || err.message || '抓取详情数据失败')
  } finally {
    fetchingDetail.value = false
  }
}

// 抓取播放/解析接口数据
const handleFetchParseHtml = async () => {
  if (!parseUrl.value.trim() || !parseUrl.value.startsWith('http')) {
    message.warning('请先输入有效的播放/解析接口示例 URL')
    return
  }

  fetchingParse.value = true
  try {
    const res: any = await http.post('/rules/fetch-page', {
      url: parseUrl.value.trim()
    })
    const data = res?.data || ''
    if (data) {
      parseHtml.value = data.slice(0, 25000)
      message.success(`播放解析数据抓取成功 (${(data.length / 1024).toFixed(1)} KB)`)
    } else {
      message.warning('抓取到的播放解析数据为空')
    }
  } catch (err: any) {
    message.error(err.response?.data?.message || err.message || '抓取播放解析数据失败')
  } finally {
    fetchingParse.value = false
  }
}

// 调用 AI 大模型生成多页面协同规则代码
const handleGenerate = async () => {
  if (!listHtml.value.trim() && !detailHtml.value.trim()) {
    message.warning('请至少抓取或提供列表页或详情页的数据样本 (HTML/JSON)')
    return
  }

  if (!aiStore.baseUrl) {
    message.error('尚未配置 AI 模型 API 地址，请在左侧侧边栏底部「系统设置」中配置')
    return
  }

  generating.value = true
  try {
    const result = await aiStore.generateRuleCode({
      targetUrl: targetUrl.value.trim(),
      mediaType: mediaType.value,
      listHtml: listHtml.value.trim(),
      detailUrl: detailUrl.value.trim(),
      detailHtml: detailHtml.value.trim(),
      parseUrl: parseUrl.value.trim(),
      parseHtml: parseHtml.value.trim(),
      requirement: requirement.value.trim()
    })

    if (result?.code) {
      generatedCode.value = result.code
      if (result.name && !ruleName.value) ruleName.value = result.name
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
    title="AI 智能规则编写助手 (多源协同通用版)"
    class="!rounded-3xl max-w-6xl shadow-2xl w-full"
    :segmented="{ content: 'soft', footer: 'soft' }"
  >
    <template #header>
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center shadow-md shadow-emerald-500/20 text-white">
          <Sparkles class="w-4 h-4 animate-pulse" />
        </div>
        <div>
          <h2 class="text-base font-black text-zinc-900 dark:text-white flex items-center gap-2">
            <span>AI 多源全链路规则生成器</span>
            <span class="px-2 py-0.5 text-[10px] font-mono rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50">
              {{ aiStore.model || '未配置' }}
            </span>
          </h2>
          <p class="text-[11px] text-zinc-400">通用支持网页 HTML 与 REST JSON API 多源采样与智能嗅探，AI 同步生成 discovery / search / detail / parse 全套解析规则</p>
        </div>
      </div>
    </template>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-5 h-[68vh]">
      <!-- 左侧：输入与抓取参数栏 (lg:col-span-5) -->
      <div class="lg:col-span-5 flex flex-col gap-3 h-full overflow-y-auto pr-1">
        <!-- 1. 列表页/发现页 URL (必填) -->
        <div class="space-y-1">
          <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
            <span class="flex items-center gap-1.5">
              <Compass class="w-3.5 h-3.5 text-emerald-500" />
              <span>1. 发现/列表页 URL (HTML 或 JSON API)</span>
            </span>
            <n-button
              size="tiny"
              secondary
              type="primary"
              :loading="fetchingList"
              @click="handleFetchListHtml"
              class="!rounded-lg !font-bold"
            >
              <template #icon>
                <DownloadCloud class="w-3 h-3" />
              </template>
              抓取列表
            </n-button>
          </div>
          <n-input
            v-model:value="targetUrl"
            placeholder="例如: https://site.com/movie/list 或 /api/vod"
            class="!rounded-xl font-mono text-xs"
          />
        </div>

        <!-- 2. 详情页示例 URL (可选 / 自动嗅探) -->
        <div class="space-y-1">
          <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
            <span class="flex items-center gap-1.5">
              <FileText class="w-3.5 h-3.5 text-teal-500" />
              <span>2. 详情页/接口示例 URL (选集/正文)</span>
              <span v-if="autoSniffed" class="px-1.5 py-0.2 text-[9px] font-bold rounded bg-emerald-100 dark:bg-emerald-950/60 text-emerald-600 dark:text-emerald-400">
                ⚡ 自动嗅探
              </span>
            </span>
            <n-button
              size="tiny"
              secondary
              type="primary"
              :loading="fetchingDetail"
              @click="handleFetchDetailHtml"
              class="!rounded-lg !font-bold"
            >
              <template #icon>
                <DownloadCloud class="w-3 h-3" />
              </template>
              抓取详情
            </n-button>
          </div>
          <n-input
            v-model:value="detailUrl"
            placeholder="例如: https://site.com/detail/10086.html (留空由系统自动嗅探)"
            class="!rounded-xl font-mono text-xs"
          />
        </div>

        <!-- 3. 播放/解析页示例 URL (可选) -->
        <div class="space-y-1">
          <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
            <span class="flex items-center gap-1.5">
              <Terminal class="w-3.5 h-3.5 text-cyan-500" />
              <span>3. 播放/解析接口示例 URL (可选)</span>
            </span>
            <n-button
              size="tiny"
              secondary
              type="primary"
              :loading="fetchingParse"
              @click="handleFetchParseHtml"
              class="!rounded-lg !font-bold"
            >
              <template #icon>
                <DownloadCloud class="w-3 h-3" />
              </template>
              抓取解析
            </n-button>
          </div>
          <n-input
            v-model:value="parseUrl"
            placeholder="例如: https://site.com/play/10086-1-1.html"
            class="!rounded-xl font-mono text-xs"
          />
        </div>

        <!-- 规则分类与名称 -->
        <div class="grid grid-cols-2 gap-2 pt-1">
          <div class="space-y-1">
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

          <div class="space-y-1">
            <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1">
              <FileCode2 class="w-3.5 h-3.5 text-cyan-500" />
              <span>规则名称 (可选)</span>
            </label>
            <n-input
              v-model:value="ruleName"
              placeholder="例如: 极光影视源"
              class="!rounded-xl text-xs"
            />
          </div>
        </div>

        <!-- 源码片段多标签查看器 -->
        <div class="space-y-1.5 flex-1 flex flex-col min-h-[140px] pt-1">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-1 p-0.5 bg-zinc-100 dark:bg-white/[0.04] rounded-xl text-[11px] font-bold">
              <button
                type="button"
                @click="activeHtmlTab = 'list'"
                class="px-2.5 py-1 rounded-lg transition-all cursor-pointer flex items-center gap-1.5"
                :class="activeHtmlTab === 'list' ? 'bg-white dark:bg-zinc-800 text-emerald-600 dark:text-emerald-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
              >
                <span>列表数据</span>
                <span v-if="listHtml" class="text-[10px] font-mono font-normal opacity-70">
                  {{ (listHtml.length / 1024).toFixed(1) }}k
                </span>
              </button>
              <button
                type="button"
                @click="activeHtmlTab = 'detail'"
                class="px-2.5 py-1 rounded-lg transition-all cursor-pointer flex items-center gap-1.5"
                :class="activeHtmlTab === 'detail' ? 'bg-white dark:bg-zinc-800 text-teal-600 dark:text-teal-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
              >
                <span>详情数据</span>
                <span v-if="detailHtml" class="text-[10px] font-mono font-normal opacity-70">
                  {{ (detailHtml.length / 1024).toFixed(1) }}k
                </span>
              </button>
              <button
                type="button"
                @click="activeHtmlTab = 'parse'"
                class="px-2.5 py-1 rounded-lg transition-all cursor-pointer flex items-center gap-1.5"
                :class="activeHtmlTab === 'parse' ? 'bg-white dark:bg-zinc-800 text-cyan-600 dark:text-cyan-400 shadow-xs' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'"
              >
                <span>播放数据</span>
                <span v-if="parseHtml" class="text-[10px] font-mono font-normal opacity-70">
                  {{ (parseHtml.length / 1024).toFixed(1) }}k
                </span>
              </button>
            </div>
          </div>

          <n-input
            v-if="activeHtmlTab === 'list'"
            v-model:value="listHtml"
            type="textarea"
            placeholder="列表/发现数据样本 (HTML 源码或 JSON 响应)..."
            class="!rounded-xl font-mono text-xs flex-1"
            :autosize="{ minRows: 4, maxRows: 8 }"
          />
          <n-input
            v-else-if="activeHtmlTab === 'detail'"
            v-model:value="detailHtml"
            type="textarea"
            placeholder="详情数据样本 (HTML 选集/正文或 JSON 响应)..."
            class="!rounded-xl font-mono text-xs flex-1"
            :autosize="{ minRows: 4, maxRows: 8 }"
          />
          <n-input
            v-else
            v-model:value="parseHtml"
            type="textarea"
            placeholder="播放解析数据样本 (HTML 源码或 JSON 直链响应)..."
            class="!rounded-xl font-mono text-xs flex-1"
            :autosize="{ minRows: 4, maxRows: 8 }"
          />
        </div>

        <!-- 补充需求 -->
        <div class="space-y-1">
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
            <SlidersHorizontal class="w-3.5 h-3.5 text-violet-500" />
            <span>补充解析诉求 / 字段提示 (可选)</span>
          </label>
          <n-input
            v-model:value="requirement"
            placeholder="例如: 接口返回的是 JSON，直接从 data.list 遍历，直链在 data.play_url"
            class="!rounded-xl text-xs"
          />
        </div>

        <!-- 生成按键 -->
        <n-button
          type="primary"
          block
          :loading="generating"
          @click="handleGenerate"
          class="!rounded-xl !font-bold !py-3.5 shadow-lg shadow-emerald-500/20 mt-1 shrink-0"
        >
          <template #icon>
            <Bot class="w-4 h-4" />
          </template>
          <span>{{ generating ? 'AI 大模型正在多源深度协同解析中...' : '开始生成全链路规则代码' }}</span>
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
            <span class="text-xs font-bold">AI 正在根据多页面 DOM 树组织 Standard Rules...</span>
          </div>
          <CodeEditor
            v-else-if="generatedCode"
            v-model="generatedCode"
            language="javascript"
          />
          <div v-else class="w-full h-full flex flex-col items-center justify-center text-zinc-400 gap-2 p-6 text-center">
            <Bot class="w-12 h-12 text-zinc-300 dark:text-zinc-700" />
            <span class="text-xs text-zinc-500">在左侧输入列表页 URL 后，系统将自动嗅探详情页并多源采样，点击「开始生成」即可在此实时预览并应用规则。</span>
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
