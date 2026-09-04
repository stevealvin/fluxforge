<script setup lang="ts">
import { ref } from 'vue'
import { useMessage } from 'naive-ui'
import http from '@/utils/http'
import CodeEditor from '@/components/CodeEditor/index.vue'
import type { MediaType } from '@/types/rule'
import {
  Globe,
  RefreshCw,
  Eye,
  CheckCircle2,
  ChevronDown,
  ChevronUp
} from '@lucide/vue'

const props = defineProps<{
  targetUrl: string
  mediaType?: MediaType | string
  detailUrl: string
  parseUrl: string
  listHtml: string
  detailHtml: string
  parseHtml: string
}>()

const emit = defineEmits<{
  (e: 'update:targetUrl', val: string): void
  (e: 'update:detailUrl', val: string): void
  (e: 'update:parseUrl', val: string): void
  (e: 'update:listHtml', val: string): void
  (e: 'update:detailHtml', val: string): void
  (e: 'update:parseHtml', val: string): void
}>()

const message = useMessage()

const showAdvancedSampling = ref(false)
const fetchingList = ref(false)
const fetchingDetail = ref(false)
const fetchingParse = ref(false)

// 源码查看弹窗
const showSourceModal = ref(false)
const sourceModalContent = ref('')
const sourceModalTitle = ref('')

const openSourceViewer = (content: string, title: string) => {
  sourceModalContent.value = content
  sourceModalTitle.value = title
  showSourceModal.value = true
}

const formatSize = (str: string): string => {
  if (!str) return '0 B'
  const bytes = new TextEncoder().encode(str).length
  return bytes >= 1024 ? (bytes / 1024).toFixed(1) + ' KB' : bytes + ' B'
}

const detectContentType = (str: string): string => {
  const trimmed = str.trim()
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try { JSON.parse(trimmed); return 'JSON' } catch {}
  }
  if (/<!DOCTYPE|<html|<head|<body/i.test(trimmed)) return 'HTML'
  return 'Text'
}

const sniffDetailUrl = (rawContent: string, base: string): string => {
  if (!rawContent || !base) return ''
  const trimmed = rawContent.trim()
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const data = JSON.parse(trimmed)
      let items: any[] = []
      if (Array.isArray(data)) items = data
      else if (typeof data === 'object' && data !== null) {
        const candidates = ['list', 'data', 'items', 'results', 'vod_list', 'books', 'rows', 'data_list', 'posts']
        for (const k of candidates) {
          if (Array.isArray(data[k]) && data[k].length > 0) {
            items = data[k]
            break
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
      }
    } catch {}
  }

  try {
    const hrefMatches = rawContent.match(/href=["']([^"']*(?:detail|view|read|movie|book|post|show|subject|item|archives)[^"']*)["']/i)
    if (hrefMatches && hrefMatches[1]) {
      const matched = hrefMatches[1].trim()
      if (!matched.startsWith('javascript') && !matched.startsWith('#')) {
        return new URL(matched, base).href
      }
    }
  } catch {}
  return ''
}

const fetchUrlData = async (url: string, type: 'list' | 'detail' | 'parse') => {
  if (!url) {
    message.warning('请输入要采样的目标网址')
    return
  }

  const loadingMap = { list: fetchingList, detail: fetchingDetail, parse: fetchingParse }
  loadingMap[type].value = true

  try {
    const { data } = await http.post('/rules/fetch-page', { url })
    const content = data || ''

    if (type === 'list') {
      emit('update:listHtml', content)
      message.success(`列表页已采样 (${formatSize(content)})`)
      if (!props.detailUrl) {
        const sniffed = sniffDetailUrl(content, url)
        if (sniffed) {
          emit('update:detailUrl', sniffed)
          showAdvancedSampling.value = true
          message.info('💡 已自动嗅探到详情页链接并填入高级采样')
        }
      }
    } else if (type === 'detail') {
      emit('update:detailHtml', content)
      message.success(`详情页已采样 (${formatSize(content)})`)
    } else {
      emit('update:parseHtml', content)
      message.success(`解析页已采样 (${formatSize(content)})`)
    }
  } catch (err: any) {
    message.error(err.response?.data?.message || err.message || '采样抓取失败')
  } finally {
    loadingMap[type].value = false
  }
}

defineExpose({
  fetchUrlData
})
</script>

<template>
  <div class="rounded-2xl border border-emerald-100/70 dark:border-white/5 bg-white/70 dark:bg-white/[0.02] p-3.5 space-y-3 shadow-2xs shrink-0">
    <!-- 1. 目标源站 URL 输入与采样 (宽裕独立行) -->
    <div class="space-y-1.5">
      <div class="flex items-center justify-between text-xs font-bold text-zinc-700 dark:text-zinc-300">
        <div class="flex items-center gap-1.5">
          <Globe class="w-3.5 h-3.5 text-emerald-500" />
          <span>目标源站 URL (可选采样)</span>
        </div>
        <button
          type="button"
          class="flex items-center gap-1 text-[11px] font-normal text-zinc-400 hover:text-emerald-600 dark:hover:text-emerald-400 cursor-pointer transition-colors"
          @click="showAdvancedSampling = !showAdvancedSampling"
        >
          <span>多级采样</span>
          <component :is="showAdvancedSampling ? ChevronUp : ChevronDown" class="w-3 h-3" />
        </button>
      </div>

      <div class="flex gap-2">
        <n-input
          :value="targetUrl"
          placeholder="https://example.com/vod 或 JSON API (可选采样)"
          clearable
          class="!rounded-xl text-xs font-mono flex-1"
          @update:value="emit('update:targetUrl', $event)"
          @keyup.enter="fetchUrlData(targetUrl, 'list')"
        >
          <template #prefix>
            <Globe class="w-3.5 h-3.5 text-zinc-400" />
          </template>
        </n-input>

        <n-button
          secondary
          type="primary"
          size="small"
          class="!rounded-xl !font-bold shrink-0 shadow-xs"
          :loading="fetchingList"
          @click="fetchUrlData(targetUrl, 'list')"
        >
          <template #icon>
            <RefreshCw class="w-3.5 h-3.5" :class="{ 'animate-spin': fetchingList }" />
          </template>
          <span>{{ listHtml ? '重新采样' : '采样' }}</span>
        </n-button>
      </div>

      <!-- 采样状态指示胶囊 -->
      <div v-if="listHtml" class="flex items-center justify-between text-[11px] px-2.5 py-1.5 rounded-xl bg-emerald-50/60 dark:bg-emerald-950/20 border border-emerald-200/50 dark:border-emerald-800/30 mt-1">
        <div class="flex items-center gap-1.5 text-emerald-700 dark:text-emerald-300 font-medium truncate mr-2">
          <CheckCircle2 class="w-3.5 h-3.5 text-emerald-500 shrink-0" />
          <span class="truncate">已采样列表数据 ({{ formatSize(listHtml) }} · {{ detectContentType(listHtml) }})</span>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button
            type="button"
            class="text-emerald-600 hover:text-emerald-800 dark:hover:text-emerald-200 font-bold cursor-pointer"
            @click="openSourceViewer(listHtml, '列表页采样数据')"
          >
            查看源码
          </button>
          <span class="text-zinc-300 dark:text-zinc-700">|</span>
          <button
            type="button"
            class="text-zinc-400 hover:text-rose-500 transition-colors cursor-pointer"
            @click="emit('update:listHtml', '')"
          >
            清空
          </button>
        </div>
      </div>
    </div>

    <!-- 展开高级多级采样 (详情页 / 解析页) -->
      <div v-if="showAdvancedSampling" class="pt-2 border-t border-zinc-100 dark:border-white/5 space-y-2">
        <!-- 详情页采样 -->
        <div class="flex items-center gap-2 min-w-0 w-full">
          <span class="text-[11px] text-zinc-400 w-12 shrink-0">详情页:</span>
          <n-input
            :value="detailUrl"
            placeholder="详情页示例 URL (已嗅探或手动输入)"
            clearable
            class="!rounded-xl text-xs font-mono flex-1 min-w-0"
            @update:value="emit('update:detailUrl', $event)"
          />
          <n-button
            secondary
            size="tiny"
            class="!rounded-lg shrink-0"
            :loading="fetchingDetail"
            @click="fetchUrlData(detailUrl, 'detail')"
          >
            {{ detailHtml ? '重新采样' : '采样' }}
          </n-button>
        </div>
        <div v-if="detailHtml" class="flex items-center justify-between text-[10px] px-2 py-1 rounded-lg bg-zinc-50 dark:bg-white/[0.02] text-zinc-500">
          <span class="truncate mr-2">已采样详情页 ({{ formatSize(detailHtml) }})</span>
          <button type="button" class="text-emerald-500 font-bold shrink-0 cursor-pointer" @click="openSourceViewer(detailHtml, '详情页采样数据')">查看</button>
        </div>

        <!-- 解析/正文采样 -->
        <div class="flex items-center gap-2 min-w-0 w-full">
          <span class="text-[11px] text-zinc-400 w-12 shrink-0">解析页:</span>
          <n-input
            :value="parseUrl"
            placeholder="播放器/正文解析 URL (可选)"
            clearable
            class="!rounded-xl text-xs font-mono flex-1 min-w-0"
            @update:value="emit('update:parseUrl', $event)"
          />
          <n-button
            secondary
            size="tiny"
            class="!rounded-lg shrink-0"
            :loading="fetchingParse"
            @click="fetchUrlData(parseUrl, 'parse')"
          >
            {{ parseHtml ? '重新采样' : '采样' }}
          </n-button>
        </div>
        <div v-if="parseHtml" class="flex items-center justify-between text-[10px] px-2 py-1 rounded-lg bg-zinc-50 dark:bg-white/[0.02] text-zinc-500">
          <span>已采样解析页 ({{ formatSize(parseHtml) }})</span>
          <button type="button" class="text-emerald-500 font-bold cursor-pointer" @click="openSourceViewer(parseHtml, '解析页采样数据')">查看</button>
        </div>
      </div>

    <!-- 源码预览 Modal -->
    <n-modal
      v-model:show="showSourceModal"
      preset="card"
      class="max-w-4xl !rounded-2xl overflow-hidden"
      :title="sourceModalTitle"
    >
      <div class="h-[60vh] w-full flex flex-col gap-2">
        <div class="flex items-center justify-between text-xs text-zinc-400 pb-1 border-b border-zinc-100 dark:border-white/5">
          <span>{{ detectContentType(sourceModalContent) }} · {{ formatSize(sourceModalContent) }}</span>
          <span class="font-mono text-[10px]">只读展示</span>
        </div>
        <div class="flex-1 w-full relative min-h-0">
          <code-editor
            :model-value="sourceModalContent"
            model-id="sample_source_viewer"
            height="100%"
            class="w-full h-full"
            :options="{ readOnly: true, lineNumbers: 'on', minimap: { enabled: false } }"
          />
        </div>
      </div>
    </n-modal>
  </div>
</template>
