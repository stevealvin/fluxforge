<script setup lang="ts">
import { ref } from 'vue'
import { BookOpen, ChevronLeft, ChevronRight, Sparkles } from '@lucide/vue'
import type { MediaDetail, MediaEpisode, RuleSchema } from '@/types/rule'
import { ruleService } from '@/utils/ruleService'

const props = defineProps<{
  detail: MediaDetail
  rule?: RuleSchema
}>()

const activeChapterUrl = ref<string>('')
const activeChapterTitle = ref<string>('')
const chapterContent = ref<string>(props.detail.content || '')
const readingFontSize = ref<'small' | 'medium' | 'large'>('medium')
const readingTheme = ref<'default' | 'sepia' | 'dark'>('default')
const parsing = ref(false)
const errorMsg = ref('')

const allChapters = ref<MediaEpisode[]>([])
if (props.detail.groups && props.detail.groups.length > 0) {
  allChapters.value = props.detail.groups.flatMap((g) => g.items || [])
}

const selectChapter = async (ch: MediaEpisode, autoScroll = true) => {
  activeChapterUrl.value = ch.url
  activeChapterTitle.value = ch.title
  errorMsg.value = ''

  if (props.rule) {
    parsing.value = true
    try {
      const res = await ruleService.runParse(props.rule, { url: ch.url })
      if (res.content) {
        chapterContent.value = res.content
        if (autoScroll) {
          window.scrollTo({ top: 0, behavior: 'smooth' })
        }
      } else {
        errorMsg.value = '未能解析到该章节的正文内容'
      }
    } catch (e: any) {
      errorMsg.value = '解析章节失败: ' + e.message
    } finally {
      parsing.value = false
    }
  }
}

// 翻页上一章 / 下一章
const currentIndex = () => allChapters.value.findIndex((c) => c.url === activeChapterUrl.value)

const prevChapter = () => {
  const idx = currentIndex()
  if (idx > 0) {
    selectChapter(allChapters.value[idx - 1])
  }
}

const nextChapter = () => {
  const idx = currentIndex()
  if (idx !== -1 && idx < allChapters.value.length - 1) {
    selectChapter(allChapters.value[idx + 1])
  }
}
</script>

<template>
  <div class="space-y-6 max-w-4xl mx-auto pb-16">
    <!-- 小说头部元信息卡片 -->
    <div class="glass-panel rounded-2xl p-5 sm:p-6 space-y-4 shadow-sm">
      <div class="flex flex-col sm:flex-row items-start sm:items-center gap-4">
        <img
          v-if="detail.cover"
          :src="detail.cover"
          referrerpolicy="no-referrer"
          :alt="detail.title"
          class="w-24 h-32 rounded-xl object-cover shadow-md border border-slate-200/60 dark:border-white/10 flex-shrink-0"
        />
        <div class="space-y-2 flex-1 min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h1 class="text-lg sm:text-xl font-black text-zinc-900 dark:text-white">
              {{ detail.title }}
            </h1>
            <span v-if="detail.author" class="text-xs px-2.5 py-0.5 rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 font-bold border border-emerald-200/40 dark:border-emerald-800/30">
              作者: {{ detail.author }}
            </span>
          </div>
          <p v-if="detail.desc" class="text-xs text-slate-600 dark:text-slate-300 leading-relaxed whitespace-pre-line break-words">
            {{ detail.desc }}
          </p>
        </div>
      </div>
    </div>

    <!-- 正文沉浸式阅读器 -->
    <div
      v-if="chapterContent || parsing"
      class="glass-panel rounded-2xl p-6 sm:p-12 space-y-6 shadow-sm transition-all duration-300 border"
      :class="{
        'bg-amber-50/70 dark:bg-amber-950/20 text-amber-950 dark:text-amber-100': readingTheme === 'sepia',
        'bg-slate-900 text-slate-100': readingTheme === 'dark'
      }"
    >
      <!-- 阅读器顶部工具栏 -->
      <div class="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-slate-200/50 dark:border-white/10">
        <span class="text-xs font-bold text-slate-400">
          {{ activeChapterTitle || '正文阅读' }}
        </span>

        <div class="flex items-center gap-3 text-xs">
          <!-- 背景主题 -->
          <div class="flex items-center gap-1 bg-emerald-50/60 dark:bg-white/[0.04] p-1 rounded-xl border border-emerald-100/60 dark:border-white/5">
            <n-button
              size="tiny"
              :type="readingTheme === 'default' ? 'primary' : 'default'"
              :secondary="readingTheme !== 'default'"
              class="!rounded-lg"
              @click="readingTheme = 'default'"
            >
              默认
            </n-button>
            <n-button
              size="tiny"
              :type="readingTheme === 'sepia' ? 'warning' : 'default'"
              :secondary="readingTheme !== 'sepia'"
              class="!rounded-lg"
              @click="readingTheme = 'sepia'"
            >
              羊皮纸
            </n-button>
            <n-button
              size="tiny"
              :type="readingTheme === 'dark' ? 'primary' : 'default'"
              :secondary="readingTheme !== 'dark'"
              class="!rounded-lg"
              @click="readingTheme = 'dark'"
            >
              夜间
            </n-button>
          </div>

          <!-- 字号控制 -->
          <div class="flex items-center gap-1 bg-emerald-50/60 dark:bg-white/[0.04] p-1 rounded-xl border border-emerald-100/60 dark:border-white/5">
            <n-button
              size="tiny"
              :type="readingFontSize === 'small' ? 'primary' : 'default'"
              :secondary="readingFontSize !== 'small'"
              class="!rounded-lg"
              @click="readingFontSize = 'small'"
            >
              小
            </n-button>
            <n-button
              size="tiny"
              :type="readingFontSize === 'medium' ? 'primary' : 'default'"
              :secondary="readingFontSize !== 'medium'"
              class="!rounded-lg"
              @click="readingFontSize = 'medium'"
            >
              中
            </n-button>
            <n-button
              size="tiny"
              :type="readingFontSize === 'large' ? 'primary' : 'default'"
              :secondary="readingFontSize !== 'large'"
              class="!rounded-lg"
              @click="readingFontSize = 'large'"
            >
              大
            </n-button>
          </div>
        </div>
      </div>

      <!-- 解析加载动画 -->
      <div v-if="parsing" class="py-20 flex flex-col items-center justify-center gap-3">
        <n-spin size="large" />
        <span class="text-xs text-zinc-400">正在抓取并清洗章节正文...</span>
      </div>

      <!-- 错误提示 -->
      <div v-else-if="errorMsg" class="py-12 text-center text-rose-500 text-xs font-bold">
        {{ errorMsg }}
      </div>

      <!-- 正文内容 -->
      <div
        v-else
        class="leading-loose whitespace-pre-wrap font-sans transition-all duration-300 select-text"
        :class="{
          'text-xs sm:text-sm': readingFontSize === 'small',
          'text-sm sm:text-base': readingFontSize === 'medium',
          'text-base sm:text-lg': readingFontSize === 'large'
        }"
      >
        {{ chapterContent }}
      </div>

      <!-- 翻章操作栏 -->
      <div v-if="allChapters.length > 0" class="pt-6 border-t border-emerald-100/50 dark:border-white/10 flex items-center justify-between">
        <n-button
          size="small"
          secondary
          class="!rounded-xl !font-bold"
          :disabled="currentIndex() <= 0"
          @click="prevChapter"
        >
          <template #icon>
            <ChevronLeft class="w-4 h-4" />
          </template>
          <span>上一章</span>
        </n-button>

        <span class="text-xs font-mono text-zinc-400">
          {{ currentIndex() + 1 }} / {{ allChapters.length }}
        </span>

        <n-button
          size="small"
          secondary
          class="!rounded-xl !font-bold"
          :disabled="currentIndex() >= allChapters.length - 1"
          @click="nextChapter"
        >
          <span>下一章</span>
          <template #icon>
            <ChevronRight class="w-4 h-4" />
          </template>
        </n-button>
      </div>
    </div>

    <!-- 章节目录网格 -->
    <div v-if="detail.groups && detail.groups.length > 0" class="space-y-4">
      <div v-for="group in detail.groups" :key="group.name" class="space-y-3">
        <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
          <div class="flex items-center gap-2">
            <div class="w-1.5 h-4.5 rounded-full bg-gradient-to-b from-emerald-500 via-teal-500 to-cyan-500"></div>
            <h2 class="text-sm font-bold text-zinc-800 dark:text-zinc-100">
              {{ group.name }} (共 {{ group.items.length }} 章)
            </h2>
          </div>
        </div>

        <div class="grid gap-2 grid-cols-1 sm:grid-cols-2 md:grid-cols-3">
          <div
            v-for="item in group.items"
            :key="item.url"
            class="glass-panel glass-panel-hover rounded-xl p-3 cursor-pointer transition-all border"
            :class="
              activeChapterUrl === item.url
                ? 'bg-emerald-600 text-white border-emerald-500 shadow-md shadow-emerald-600/30'
                : 'text-zinc-700 dark:text-zinc-200'
            "
            @click="selectChapter(item)"
          >
            <span class="text-xs font-semibold line-clamp-1">
              {{ item.title }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>
