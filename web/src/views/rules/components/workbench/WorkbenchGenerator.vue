<script setup lang="ts">
import { ref, watch } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import { useAiSettingsStore, type GeneratedRuleResult } from '@/stores/aiSettings'
import type { MediaType } from '@/types/rule'
import {
  Sparkles,
  Play,
  Globe,
  Bot,
  Video,
  Image as ImageIcon,
  BookOpen,
  CheckCircle2
} from '@lucide/vue'

const props = defineProps<{
  code: string
  baseUrl?: string
  ruleType?: MediaType | string
  ruleName?: string
  ruleDescription?: string
}>()

const emit = defineEmits<{
  (e: 'update:code', val: string): void
  (e: 'apply', payload: { code: string; baseUrl: string; type: string; name?: string; description?: string }): void
  (e: 'switchToTest'): void
}>()

const message = useMessage()
const aiStore = useAiSettingsStore()

const aiTargetUrl = ref(props.baseUrl || '')
const aiDetailUrl = ref('')
const aiParseUrl = ref('')
const aiMediaType = ref<MediaType | string>(props.ruleType || 'video')
const aiRequirement = ref('')

const quickPromptChips = [
  '过滤广告干扰节点',
  '封面提取高清原图并补全域名',
  '选集按正序排列',
  '小说正文保留段落换行'
]

const listHtml = ref('')
const detailHtml = ref('')
const parseHtml = ref('')
const fetchingList = ref(false)
const fetchingDetail = ref(false)
const fetchingParse = ref(false)
const autoSniffed = ref(false)

const generating = ref(false)
const generatedResult = ref<GeneratedRuleResult | null>(null)

// 智能嗅探详情页链接
const sniffDetailUrl = (rawContent: string, base: string): string => {
  if (!rawContent || !base) return ''
  const trimmed = rawContent.trim()

  // JSON 嗅探
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
      // 忽略 JSON 解析错误
    }
  }

  // HTML 嗅探常见详情页路径
  try {
    const hrefMatches = rawContent.match(/href=["']([^"']*(?:detail|view|read|movie|book|post|show|subject|item|archives)[^"']*)["']/i)
    if (hrefMatches && hrefMatches[1]) {
      const matched = hrefMatches[1].trim()
      if (!matched.startsWith('javascript') && !matched.startsWith('#')) {
        return new URL(matched, base).href
      }
    }
  } catch {
    // 忽略正则/URL 错误
  }
  return ''
}

// 抓取并采样 URL 数据
const fetchUrlData = async (url: string, type: 'list' | 'detail' | 'parse') => {
  if (!url) {
    message.warning('请输入目标采样 URL')
    return
  }

  const loadingMap = { list: fetchingList, detail: fetchingDetail, parse: fetchingParse }
  loadingMap[type].value = true

  try {
    const res: any = await http.post('/rules/fetch-content', { url })
    const content = typeof res === 'string' ? res : res.content || JSON.stringify(res)

    if (type === 'list') {
      listHtml.value = content
      message.success('列表页采样成功')
      if (!aiDetailUrl.value) {
        const sniffed = sniffDetailUrl(content, url)
        if (sniffed) {
          aiDetailUrl.value = sniffed
          autoSniffed.value = true
          message.info('💡 已自动嗅探并填入详情页示例链接')
        }
      }
    } else if (type === 'detail') {
      detailHtml.value = content
      message.success('详情页采样成功')
    } else {
      parseHtml.value = content
      message.success('播放/正文页采样成功')
    }
  } catch (err: any) {
    message.error(`采样抓取失败: ${err.message || '网络或跨域异常'}`)
  } finally {
    loadingMap[type].value = false
  }
}

// 触发 AI 规则生成
const handleGenerateAiRule = async () => {
  if (!aiStore.baseUrl || !aiStore.model) {
    message.error('请先前往系统设置配置 AI 模型提供商与 API Key')
    return
  }
  if (!aiTargetUrl.value) {
    message.warning('请输入目标列表/发现页 URL')
    return
  }

  generating.value = true
  try {
    if (!listHtml.value) {
      await fetchUrlData(aiTargetUrl.value, 'list')
    }

    const payload = {
      targetUrl: aiTargetUrl.value,
      detailUrl: aiDetailUrl.value || undefined,
      parseUrl: aiParseUrl.value || undefined,
      mediaType: aiMediaType.value,
      userRequirement: aiRequirement.value || undefined,
      listHtml: listHtml.value,
      detailHtml: detailHtml.value || undefined,
      parseHtml: parseHtml.value || undefined
    }

    const result = await aiStore.generateRuleCode(payload)
    generatedResult.value = result

    if (result?.code) {
      emit('update:code', result.code)
      message.success('✨ 规则代码已由 AI 成功生成并同步至编辑器！')
    }
  } catch (err: any) {
    message.error(`AI 生成失败: ${err.message || '请检查模型状态'}`)
  } finally {
    generating.value = false
  }
}

// 应用生成的规则
const applyGeneratedRule = (andTest = false) => {
  if (!generatedResult.value) return
  emit('apply', {
    code: generatedResult.value.code,
    baseUrl: aiTargetUrl.value,
    type: generatedResult.value.mediaType,
    name: generatedResult.value.name,
    description: generatedResult.value.description
  })
  if (andTest) {
    emit('switchToTest')
  }
}

watch(
  () => props.baseUrl,
  (val) => {
    if (val && !aiTargetUrl.value) aiTargetUrl.value = val
  }
)
watch(
  () => props.ruleType,
  (val) => {
    if (val) aiMediaType.value = val
  }
)
</script>

<template>
  <div class="flex-1 flex flex-col gap-3.5 min-h-0 h-full overflow-y-auto pr-1">
    <!-- 1. URL 抓取采样区域 -->
    <div class="rounded-2xl border border-emerald-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] p-3.5 space-y-3 shadow-2xs">
      <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/40 dark:border-white/5">
        <div class="flex items-center gap-1.5 text-xs font-bold text-zinc-800 dark:text-zinc-200">
          <Globe class="w-3.5 h-3.5 text-emerald-500" />
          <span>多级源站采样 URL</span>
        </div>
        <span class="text-[10px] text-zinc-400">支持 HTML 与 JSON</span>
      </div>

      <!-- 1. 发现/列表页 URL -->
      <div class="space-y-1">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-1.5">
            <span class="w-4 h-4 rounded-full bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 flex items-center justify-center text-[10px] font-bold font-mono">1</span>
            <span class="font-bold text-zinc-700 dark:text-zinc-300">列表 / 发现页 (discovery)</span>
          </div>
          <span class="text-[10px] text-rose-500 font-mono font-bold">* 必填</span>
        </div>
        <div class="flex gap-1.5">
          <n-input
            v-model:value="aiTargetUrl"
            placeholder="https://example.com/vod/list 或 JSON API"
            clearable
            class="!rounded-xl text-xs font-mono flex-1"
            @keyup.enter="fetchUrlData(aiTargetUrl, 'list')"
          />
          <n-button
            size="small"
            type="primary"
            secondary
            class="!rounded-xl !font-bold shrink-0 shadow-xs"
            :loading="fetchingList"
            @click="fetchUrlData(aiTargetUrl, 'list')"
          >
            抓取采样
          </n-button>
        </div>
      </div>

      <!-- 2. 详情/选集页 URL -->
      <div class="space-y-1">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-1.5">
            <span class="w-4 h-4 rounded-full bg-teal-500/15 text-teal-600 dark:text-teal-400 flex items-center justify-center text-[10px] font-bold font-mono">2</span>
            <span class="font-bold text-zinc-700 dark:text-zinc-300">详情 / 选集页 (detail)</span>
            <span v-if="autoSniffed" class="px-1.5 py-0.2 text-[9px] rounded-full bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 border border-emerald-500/30 font-bold animate-pulse">
              已嗅探
            </span>
          </div>
          <span class="text-[10px] text-zinc-400 font-mono">选填</span>
        </div>
        <div class="flex gap-1.5">
          <n-input
            v-model:value="aiDetailUrl"
            placeholder="https://example.com/detail/123"
            clearable
            class="!rounded-xl text-xs font-mono flex-1"
            @keyup.enter="fetchUrlData(aiDetailUrl, 'detail')"
          />
          <n-button
            size="small"
            secondary
            class="!rounded-xl shrink-0"
            :loading="fetchingDetail"
            @click="fetchUrlData(aiDetailUrl, 'detail')"
          >
            采样
          </n-button>
        </div>
      </div>

      <!-- 3. 播放/正文页 URL -->
      <div class="space-y-1">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-1.5">
            <span class="w-4 h-4 rounded-full bg-cyan-500/15 text-cyan-600 dark:text-cyan-400 flex items-center justify-center text-[10px] font-bold font-mono">3</span>
            <span class="font-bold text-zinc-700 dark:text-zinc-300">播放 / 正文页 (parse)</span>
          </div>
          <span class="text-[10px] text-zinc-400 font-mono">选填</span>
        </div>
        <div class="flex gap-1.5">
          <n-input
            v-model:value="aiParseUrl"
            placeholder="https://example.com/play/123"
            clearable
            class="!rounded-xl text-xs font-mono flex-1"
            @keyup.enter="fetchUrlData(aiParseUrl, 'parse')"
          />
          <n-button
            size="small"
            secondary
            class="!rounded-xl shrink-0"
            :loading="fetchingParse"
            @click="fetchUrlData(aiParseUrl, 'parse')"
          >
            采样
          </n-button>
        </div>
      </div>
    </div>

    <!-- 2. 媒体类型视觉卡片选择 -->
    <div class="rounded-2xl border border-emerald-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] p-3.5 space-y-3 shadow-2xs">
      <div class="flex items-center justify-between pb-1 border-b border-emerald-100/40 dark:border-white/5">
        <label class="text-xs font-bold text-zinc-800 dark:text-zinc-200">目标媒体类型</label>
        <span class="text-[10px] text-zinc-400">选择适用场景</span>
      </div>

      <div class="grid grid-cols-3 gap-2">
        <button
          type="button"
          class="flex flex-col items-center justify-center p-2.5 rounded-xl border text-xs transition-all gap-1 cursor-pointer"
          :class="aiMediaType === 'video' ? 'bg-rose-50/80 dark:bg-rose-950/30 border-rose-400 dark:border-rose-500 text-rose-600 dark:text-rose-400 font-bold shadow-xs scale-[1.02]' : 'border-zinc-200/60 dark:border-white/5 text-zinc-500 hover:bg-zinc-100 dark:hover:bg-white/5'"
          @click="aiMediaType = 'video'"
        >
          <Video class="w-4 h-4" />
          <span>视频 (Video)</span>
        </button>

        <button
          type="button"
          class="flex flex-col items-center justify-center p-2.5 rounded-xl border text-xs transition-all gap-1 cursor-pointer"
          :class="aiMediaType === 'picture' ? 'bg-amber-50/80 dark:bg-amber-950/30 border-amber-400 dark:border-amber-500 text-amber-600 dark:text-amber-400 font-bold shadow-xs scale-[1.02]' : 'border-zinc-200/60 dark:border-white/5 text-zinc-500 hover:bg-zinc-100 dark:hover:bg-white/5'"
          @click="aiMediaType = 'picture'"
        >
          <ImageIcon class="w-4 h-4" />
          <span>图片 (Picture)</span>
        </button>

        <button
          type="button"
          class="flex flex-col items-center justify-center p-2.5 rounded-xl border text-xs transition-all gap-1 cursor-pointer"
          :class="aiMediaType === 'novel' ? 'bg-cyan-50/80 dark:bg-cyan-950/30 border-cyan-400 dark:border-cyan-500 text-cyan-600 dark:text-cyan-400 font-bold shadow-xs scale-[1.02]' : 'border-zinc-200/60 dark:border-white/5 text-zinc-500 hover:bg-zinc-100 dark:hover:bg-white/5'"
          @click="aiMediaType = 'novel'"
        >
          <BookOpen class="w-4 h-4" />
          <span>小说 (Novel)</span>
        </button>
      </div>

      <!-- 提示词增强与快捷标签 -->
      <div class="space-y-1.5 pt-1">
        <div class="flex items-center justify-between">
          <label class="text-[11px] font-bold text-zinc-700 dark:text-zinc-300">个性化定制提取要求</label>
          <span class="text-[10px] text-zinc-400 font-mono">Prompt 增强</span>
        </div>

        <!-- 快捷标签 -->
        <div class="flex flex-wrap gap-1.5 pb-1">
          <button
            v-for="chip in quickPromptChips"
            :key="chip"
            type="button"
            class="px-2 py-0.5 text-[10px] rounded-lg bg-emerald-50/70 dark:bg-white/5 border border-emerald-100 dark:border-white/5 text-emerald-700 dark:text-emerald-300 hover:bg-emerald-500/15 transition-colors cursor-pointer"
            @click="aiRequirement = aiRequirement ? `${aiRequirement}，${chip}` : chip"
          >
            + {{ chip }}
          </button>
        </div>

        <n-input
          v-model:value="aiRequirement"
          type="textarea"
          :rows="2"
          placeholder="例如: 过滤广告干扰节点、封面补全域名、支持倒序选集..."
          class="!rounded-xl text-xs"
        />
      </div>

      <!-- 生成主按钮 -->
      <div class="pt-1.5">
        <n-button
          type="primary"
          class="w-full !rounded-xl !font-bold !py-3.5 shadow-lg shadow-emerald-500/25 !bg-gradient-to-r !from-emerald-600 !via-teal-500 !to-cyan-500 hover:!opacity-95 text-white"
          :loading="generating"
          @click="handleGenerateAiRule"
        >
          <template #icon>
            <Sparkles class="w-4 h-4 text-white animate-pulse" />
          </template>
          <span>🚀 一键 AI 分析网页并生成规则代码</span>
        </n-button>
      </div>
    </div>

    <!-- 3. AI 生成成功庆祝卡片 -->
    <div v-if="generatedResult?.code" class="p-3.5 rounded-2xl bg-gradient-to-br from-emerald-500/10 via-teal-500/5 to-emerald-500/15 border border-emerald-500/30 space-y-2.5 shadow-xs shrink-0">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-1.5 text-xs font-bold text-emerald-600 dark:text-emerald-400">
          <CheckCircle2 class="w-4 h-4 text-emerald-500" />
          <span>新规则已成功生成并同步至编辑器！</span>
        </div>
        <span class="text-[10px] font-mono px-1.5 py-0.2 rounded-full bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 font-bold">
          Ready
        </span>
      </div>

      <div class="text-xs bg-white/80 dark:bg-zinc-900/80 p-3 rounded-xl space-y-1.5 border border-emerald-100/60 dark:border-white/5 backdrop-blur-xs">
        <div class="flex items-center gap-2">
          <span class="font-bold text-zinc-800 dark:text-zinc-200">提取名称:</span>
          <span class="text-emerald-600 dark:text-emerald-400 font-mono font-black">{{ generatedResult.name || '默认规则' }}</span>
          <span class="px-1.5 py-0.2 text-[10px] font-bold rounded-md bg-emerald-100/80 dark:bg-white/10 text-emerald-700 dark:text-emerald-300">
            {{ generatedResult.mediaType }}
          </span>
        </div>
        <p class="text-[11px] text-zinc-500 dark:text-zinc-400 line-clamp-2">
          {{ generatedResult.description || '暂无描述' }}
        </p>
      </div>

      <div class="flex gap-2 pt-0.5">
        <n-button
          size="small"
          secondary
          class="flex-1 !rounded-xl text-xs font-bold"
          @click="applyGeneratedRule(false)"
        >
          更新元数据到表单
        </n-button>
        <n-button
          size="small"
          type="primary"
          class="flex-1 !rounded-xl text-xs font-bold shadow-md shadow-emerald-500/20"
          @click="applyGeneratedRule(true)"
        >
          <template #icon>
            <Play class="w-3 h-3 fill-current" />
          </template>
          <span>立即沙箱测试 ➔</span>
        </n-button>
      </div>
    </div>

    <!-- AI 规则工坊区域 (已移动至最下方) -->
    <div class="p-3 rounded-2xl bg-gradient-to-r from-emerald-500/10 via-teal-500/5 to-cyan-500/10 border border-emerald-500/15 flex items-center justify-between gap-2 shrink-0 mt-auto">
      <div class="flex items-center gap-2">
        <div class="w-6 h-6 rounded-lg bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 flex items-center justify-center">
          <Bot class="w-3.5 h-3.5" />
        </div>
        <div>
          <h3 class="text-xs font-black text-zinc-900 dark:text-white">AI 规则工坊</h3>
          <p class="text-[10px] text-zinc-500 dark:text-zinc-400">自动抓取样本 · 智能嗅探解析 · 一键生成规则</p>
        </div>
      </div>
      <span class="text-[10px] font-mono text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded-full font-bold">
        v2.0
      </span>
    </div>
  </div>
</template>
