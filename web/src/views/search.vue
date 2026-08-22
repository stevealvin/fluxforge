<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'

defineOptions({ name: 'SearchView' })
import { ruleService, ruleHasDetail, type RuleSchema, type MediaItem } from '@/utils/ruleService'
import { useMediaContext } from '@/stores/mediaContext'
import {
  ArrowLeft,
  Search,
  Compass,
  AlertCircle,
  Sparkles,
  Layers,
  Play,
  Video,
  Image as ImageIcon,
  BookOpen,
  Copy,
  Download
} from '@lucide/vue'
import { useMessage } from 'naive-ui'

const route = useRoute()
const router = useRouter()
const message = useMessage()
const mediaContext = useMediaContext()

const searchKeyword = ref('')
const searchResults = ref<(MediaItem & { ruleId: number; ruleName: string; ruleType: string })[]>([])
const loading = ref(false)
const searched = ref(false)
const errorMsg = ref('')
const activeRuleRequests = ref(0)
const totalRuleRequests = ref(0)

// 原地大图预览状态
const previewModalVisible = ref(false)
const previewCurrentItem = ref<MediaItem | null>(null)

let lastSearchedQuery = ''

const initSearch = () => {
  const query = route.query.q as string
  if (query) {
    searchKeyword.value = query
    performSearch(query)
  } else {
    searchResults.value = []
    searched.value = false
    lastSearchedQuery = ''
  }
}

const performSearch = async (query: string) => {
  if (!query.trim()) return
  if (query === lastSearchedQuery && searchResults.value.length > 0) return

  lastSearchedQuery = query
  loading.value = true
  searched.value = true
  errorMsg.value = ''
  searchResults.value = []

  try {
    const allRules = ruleService.getRules()
    const enabledRules = allRules.filter((r) => r.enabled === 1 || (r.enabled as any) === true)

    if (enabledRules.length === 0) {
      errorMsg.value = '没有启用的规则源，请先前往「规则管理」启用规则。'
      loading.value = false
      return
    }

    totalRuleRequests.value = enabledRules.length
    activeRuleRequests.value = enabledRules.length

    let completedCount = 0

    enabledRules.forEach(async (rule: RuleSchema) => {
      try {
        const searchRes = await ruleService.runSearch(rule, { keyword: query })

        if (searchRes.items && searchRes.items.length > 0) {
          const mapped = searchRes.items.map((item) => ({
            ...item,
            ruleId: rule.id,
            ruleName: rule.name,
            ruleType: rule.type
          }))
          searchResults.value.push(...mapped)
        }
      } catch (err) {
        console.warn(`Search failed on rule "${rule.name}":`, err)
      } finally {
        completedCount++
        activeRuleRequests.value = totalRuleRequests.value - completedCount
        if (completedCount >= enabledRules.length) {
          loading.value = false
        }
      }
    })
  } catch (err: any) {
    errorMsg.value = '发起聚合搜索失败: ' + err.message
    loading.value = false
  }
}

const handleSearchSubmit = () => {
  if (!searchKeyword.value.trim()) return
  router.push({
    path: '/search',
    query: { q: searchKeyword.value.trim() }
  })
}

const handleCardClick = (item: MediaItem & { ruleId: number; ruleName: string; ruleType: string }) => {
  const rule = ruleService.getRuleById(item.ruleId)

  // 1. 若规则没有 detail 方法 (如壁纸) -> 原地全屏预览
  if (rule && !ruleHasDetail(rule)) {
    previewCurrentItem.value = item
    previewModalVisible.value = true
    return
  }

  // 2. 注入上下文并路由跳转
  mediaContext.setContext(item.ruleId, item.key, item)
  router.push({
    path: '/media/detail',
    query: {
      ruleId: item.ruleId,
      key: item.key
    }
  })
}

const copyImageUrl = (url?: string) => {
  if (!url) return
  if (navigator.clipboard) {
    navigator.clipboard.writeText(url)
    message.success('已复制图片直链至剪贴板')
  }
}

const downloadImage = (url?: string, title?: string) => {
  if (!url) return
  const a = document.createElement('a')
  a.href = url
  a.download = `${title || 'image'}.jpg`
  a.target = '_blank'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  message.success('已启动原图下载')
}

const getItemIcon = (ruleType: string) => {
  if (ruleType === 'video' || ruleType === '视频') return Video
  if (ruleType === 'picture' || ruleType === '图片') return ImageIcon
  if (ruleType === 'novel' || ruleType === '小说') return BookOpen
  return Compass
}

watch(
  () => route.query.q,
  () => {
    initSearch()
  }
)

onMounted(() => {
  initSearch()
})
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12">
    <!-- 顶部聚合搜索条 (mori-box 风格) -->
    <div class="glass-panel rounded-2xl p-5 sm:p-6 space-y-4 shadow-sm">
      <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
        <div class="flex items-center gap-3 w-full sm:w-auto">
          <n-button
            quaternary
            size="small"
            class="!p-2 !rounded-xl"
            @click="router.back()"
            title="返回"
          >
            <template #icon>
              <ArrowLeft class="w-4 h-4" />
            </template>
          </n-button>
          <div>
            <h1 class="text-base sm:text-lg font-black tracking-tight text-zinc-900 dark:text-white flex items-center gap-2">
              <span>全网聚合搜索</span>
              <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50/80 dark:bg-emerald-950/30 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50 dark:border-emerald-800/30">
                MULTI-SOURCE SEARCH
              </span>
            </h1>
            <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
              一键并发检索所有已启用的影视、画廊与小说规则源
            </p>
          </div>
        </div>

        <!-- 搜索输入框 -->
        <div class="w-full sm:w-80 relative flex items-center gap-2">
          <div class="relative flex-1">
            <input
              v-model="searchKeyword"
              type="text"
              placeholder="输入搜索关键词，回车检索..."
              @keyup.enter="handleSearchSubmit"
              class="w-full pl-9 pr-3 py-2 bg-zinc-100/70 dark:bg-white/[0.04] hover:bg-zinc-200/50 dark:hover:bg-white/[0.07] focus:bg-white dark:focus:bg-zinc-900 border border-zinc-200/60 dark:border-white/10 rounded-xl text-xs outline-none text-zinc-800 dark:text-zinc-100 placeholder-zinc-400 transition-all shadow-inner"
            />
            <Search class="absolute left-3 top-2.5 w-4 h-4 text-zinc-400" />
          </div>
          <n-button
            type="primary"
            size="small"
            class="!rounded-xl"
            @click="handleSearchSubmit"
          >
            搜索
          </n-button>
        </div>
      </div>

      <!-- 搜索进度条 -->
      <div v-if="loading && totalRuleRequests > 0" class="pt-2">
        <div class="flex items-center justify-between text-[11px] text-zinc-500 dark:text-zinc-400 mb-1.5">
          <span>正在并发检索各大规则源...</span>
          <span class="font-mono">{{ totalRuleRequests - activeRuleRequests }} / {{ totalRuleRequests }} 个源完成</span>
        </div>
        <div class="w-full bg-zinc-100 dark:bg-white/5 h-1.5 rounded-full overflow-hidden">
          <div
            class="bg-gradient-to-r from-emerald-500 to-teal-400 h-full transition-all duration-300 rounded-full"
            :style="{ width: `${((totalRuleRequests - activeRuleRequests) / totalRuleRequests) * 100}%` }"
          />
        </div>
      </div>
    </div>

    <!-- 结果主体展示区 -->
    <div>
      <!-- 异常状态 -->
      <div
        v-if="errorMsg"
        class="glass-panel rounded-2xl p-8 max-w-md mx-auto my-12 text-center flex flex-col items-center justify-center space-y-3 border-rose-500/30 bg-rose-500/5"
      >
        <AlertCircle class="w-10 h-10 text-rose-500" />
        <h3 class="text-sm font-bold text-rose-600 dark:text-rose-400">检索失败</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">{{ errorMsg }}</p>
      </div>

      <!-- 未搜索状态 -->
      <div
        v-else-if="!searched"
        class="glass-panel rounded-2xl p-16 text-center max-w-md mx-auto my-12 flex flex-col items-center justify-center space-y-3"
      >
        <Sparkles class="w-10 h-10 text-emerald-500" />
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-200">开始探索全网内容</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">在上方输入框中输入关键字，即可同时聚合多源检索结果。</p>
      </div>

      <!-- 搜索空状态 -->
      <div
        v-else-if="!loading && searchResults.length === 0"
        class="glass-panel rounded-2xl p-16 text-center max-w-md mx-auto my-12 flex flex-col items-center justify-center space-y-3"
      >
        <Compass class="w-10 h-10 text-zinc-400" />
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-200">未找到相关媒体内容</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">换个关键词试试，或前往「规则管理」检查相关规则源是否启用。</p>
      </div>

      <!-- 结果卡片网格 -->
      <div v-else class="space-y-4">
        <div class="flex items-center justify-between px-1 text-xs text-zinc-500 dark:text-zinc-400">
          <span>共找到 <strong class="text-emerald-600 dark:text-emerald-400">{{ searchResults.length }}</strong> 条多媒体聚合结果</span>
        </div>

        <div class="grid gap-3 sm:gap-4.5 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
          <div
            v-for="(item, idx) in searchResults"
            :key="item.key || idx"
            class="group relative flex flex-col rounded-2xl overflow-hidden bg-white/70 dark:bg-white/[0.03] backdrop-blur-md border border-zinc-200/60 dark:border-white/5 hover:-translate-y-1.5 transition-all duration-300 cursor-pointer shadow-2xs hover:shadow-xl hover:shadow-emerald-500/10 active:scale-98"
            @click="handleCardClick(item)"
          >
            <!-- 封面图容器 -->
            <div
              class="w-full relative overflow-hidden bg-zinc-200 dark:bg-zinc-900"
              :class="item.ruleType === 'video' || item.ruleType === '视频' ? 'aspect-[16/10]' : 'aspect-[3/4]'"
            >
              <img
                v-if="item.cover"
                :src="item.cover"
                referrerpolicy="no-referrer"
                :alt="item.title"
                class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
                loading="lazy"
              />
              <div v-else class="w-full h-full flex items-center justify-center text-zinc-400">
                <component :is="getItemIcon(item.ruleType)" class="w-8 h-8" />
              </div>

              <!-- 悬浮蒙层 -->
              <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-end p-2.5">
                <span class="text-white text-[11px] font-bold line-clamp-1">点击查看</span>
              </div>

              <!-- 规则来源 Badge -->
              <span class="absolute top-2 left-2 px-2 py-0.5 rounded-lg text-[9px] font-bold bg-emerald-600/85 backdrop-blur-md text-white border border-white/10 shadow-xs">
                {{ item.ruleName }}
              </span>

              <!-- 角标 Tag -->
              <span
                v-if="item.badge"
                class="absolute top-2 right-2 px-2 py-0.5 rounded-lg text-[9px] font-bold bg-black/60 backdrop-blur-md text-white border border-white/10"
              >
                {{ item.badge }}
              </span>
            </div>

            <!-- 卡片文本信息 -->
            <div class="p-2.5 sm:p-3 flex flex-col justify-between flex-1 space-y-1">
              <h3 class="text-xs font-bold text-zinc-900 dark:text-white line-clamp-1 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors leading-snug">
                {{ item.title }}
              </h3>
              <p v-if="item.desc" class="text-[11px] text-zinc-500 dark:text-zinc-400 line-clamp-1">
                {{ item.desc }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 壁纸类无详情全屏大图预览弹窗 -->
    <n-modal
      v-model:show="previewModalVisible"
      preset="card"
      class="max-w-4xl !rounded-2xl overflow-hidden"
      :title="previewCurrentItem?.title || '全屏大图预览'"
    >
      <div class="space-y-4">
        <div class="w-full max-h-[75vh] flex items-center justify-center bg-black/5 dark:bg-black/30 rounded-xl overflow-hidden">
          <img
            :src="previewCurrentItem?.cover || previewCurrentItem?.key"
            referrerpolicy="no-referrer"
            class="max-w-full max-h-[75vh] object-contain rounded-xl shadow-lg"
          />
        </div>

        <div class="flex items-center justify-between pt-2 border-t border-zinc-200/50 dark:border-white/10">
          <span class="text-xs text-zinc-500 dark:text-zinc-400 truncate max-w-[60%]">
            {{ previewCurrentItem?.desc || previewCurrentItem?.title }}
          </span>

          <div class="flex items-center gap-2">
            <n-button
              secondary
              size="small"
              class="!rounded-xl"
              @click="copyImageUrl(previewCurrentItem?.cover || previewCurrentItem?.key)"
            >
              <template #icon><Copy class="w-3.5 h-3.5" /></template>
              <span>复制直链</span>
            </n-button>

            <n-button
              type="primary"
              size="small"
              class="!rounded-xl"
              @click="downloadImage(previewCurrentItem?.cover || previewCurrentItem?.key, previewCurrentItem?.title)"
            >
              <template #icon><Download class="w-3.5 h-3.5" /></template>
              <span>下载原图</span>
            </n-button>
          </div>
        </div>
      </div>
    </n-modal>
  </div>
</template>

<style scoped>
</style>
