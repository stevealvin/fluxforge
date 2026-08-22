<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue'
import { useRouter } from 'vue-router'

defineOptions({ name: 'MediaDiscoveryView' })
import { ruleService, ruleHasDetail, type RuleSchema, type MediaItem } from '@/utils/ruleService'
import { useMediaContext } from '@/stores/mediaContext'
import {
  Compass,
  AlertCircle,
  RefreshCw,
  Search,
  BookOpen,
  Video,
  Image as ImageIcon,
  Play,
  Layers,
  ChevronRight,
  Download,
  Copy,
  ExternalLink
} from '@lucide/vue'
import { useMessage } from 'naive-ui'

const props = defineProps<{
  type: string
}>()

const router = useRouter()
const message = useMessage()
const mediaContext = useMediaContext()

const rules = ref<RuleSchema[]>([])
const activeRuleId = ref<number | null>(null)
const activeRule = ref<RuleSchema | null>(null)
const subCategories = ref<string[]>([])
const activeCategory = ref<string>('')
const items = ref<MediaItem[]>([])
const currentPage = ref(1)
const hasMore = ref(false)

const loading = ref(true)
const executing = ref(false)
const errorMsg = ref('')
const searchQuery = ref('')

// 壁纸类无详情大图原地预览状态
const previewModalVisible = ref(false)
const previewCurrentItem = ref<MediaItem | null>(null)

const activeIcon = computed(() => {
  if (props.type === '视频' || props.type === 'video') return Video
  if (props.type === '图片' || props.type === 'picture') return ImageIcon
  if (props.type === '小说' || props.type === 'novel') return BookOpen
  return Compass
})

const coverAspectClass = computed(() => {
  if (props.type === '视频' || props.type === 'video') {
    return 'aspect-[16/10]'
  }
  return 'aspect-[3/4]'
})

const loadRules = async () => {
  loading.value = true
  errorMsg.value = ''
  subCategories.value = []
  activeCategory.value = ''
  items.value = []
  searchQuery.value = ''
  currentPage.value = 1

  try {
    const matchedRules = ruleService.getEnabledRulesByType(props.type)
    rules.value = matchedRules

    if (rules.value.length > 0) {
      activeRuleId.value = rules.value[0].id
      activeRule.value = rules.value[0]
      await fetchDiscovery(1)
    } else {
      activeRuleId.value = null
      activeRule.value = null
    }
  } catch (error: any) {
    errorMsg.value = '获取规则失败: ' + (error.message || error)
  } finally {
    loading.value = false
  }
}

const handleRuleChange = async (id: number) => {
  const selected = rules.value.find((r) => r.id === id)
  if (selected) {
    activeRuleId.value = id
    activeRule.value = selected
    subCategories.value = []
    activeCategory.value = ''
    searchQuery.value = ''
    currentPage.value = 1
    await fetchDiscovery(1)
  }
}

const handleCategoryChange = async (cat: string) => {
  if (activeCategory.value === cat) return
  activeCategory.value = cat
  currentPage.value = 1
  await fetchDiscovery(1)
}

const fetchDiscovery = async (page = 1) => {
  if (!activeRule.value) return

  executing.value = true
  errorMsg.value = ''

  try {
    const res = await ruleService.runDiscovery(activeRule.value, {
      category: activeCategory.value,
      page
    })

    if (res.categories && res.categories.length > 0) {
      subCategories.value = res.categories
      if (!activeCategory.value && subCategories.value.length > 0) {
        activeCategory.value = subCategories.value[0]
      }
    }

    if (page === 1) {
      items.value = res.items || []
    } else {
      items.value = [...items.value, ...(res.items || [])]
    }

    currentPage.value = page
    hasMore.value = !!res.hasMore
  } catch (error: any) {
    errorMsg.value = '解析媒体发现流失败: ' + (error.message || error)
  } finally {
    executing.value = false
  }
}

const loadNextPage = () => {
  if (executing.value || !hasMore.value) return
  fetchDiscovery(currentPage.value + 1)
}

const filteredItems = computed(() => {
  if (!searchQuery.value.trim()) return items.value
  const query = searchQuery.value.toLowerCase().trim()
  return items.value.filter(
    (item) =>
      item.title?.toLowerCase().includes(query) ||
      item.desc?.toLowerCase().includes(query) ||
      item.badge?.toLowerCase().includes(query)
  )
})

const handleCardClick = (item: MediaItem) => {
  if (!activeRule.value) return

  // 1. 如果该规则没有 detail 解析方法 (如壁纸类) -> 原地唤起全屏高清大图预览
  if (!ruleHasDetail(activeRule.value)) {
    previewCurrentItem.value = item
    previewModalVisible.value = true
    return
  }

  // 2. 如果具备 detail 方法 (如写真套图、影视、小说) -> 注入预热上下文并路由跳转
  mediaContext.setContext(activeRule.value.id, item.key, item)
  router.push({
    path: '/media/detail',
    query: {
      ruleId: activeRule.value.id,
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
  a.download = `${title || 'wallpaper'}.jpg`
  a.target = '_blank'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  message.success('已启动原图下载')
}

watch(
  () => props.type,
  () => {
    loadRules()
  }
)

onMounted(() => {
  loadRules()
})
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12">
    <!-- 顶部控制台 (mori-box 风格) -->
    <div class="glass-panel rounded-2xl p-5 space-y-4 shadow-sm">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <!-- 页面标题与图标 -->
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-2xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 text-white flex items-center justify-center shadow-md shadow-emerald-500/25 flex-shrink-0">
            <component :is="activeIcon" class="w-5 h-5" />
          </div>
          <div>
            <h1 class="text-base sm:text-lg font-black tracking-tight text-zinc-900 dark:text-white flex items-center gap-2">
              <span>{{ props.type }}发现</span>
              <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50/80 dark:bg-emerald-950/30 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50 dark:border-emerald-800/30">
                DISCOVERY
              </span>
            </h1>
            <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
              当前共接入 {{ rules.length }} 个已启用{{ props.type }}规则源
            </p>
          </div>
        </div>

        <!-- 页面内即时检索框与刷新 -->
        <div class="flex items-center gap-2 w-full sm:w-auto">
          <div class="relative flex-1 sm:w-60">
            <input
              v-model="searchQuery"
              type="text"
              placeholder="在当前列表中快速过滤..."
              class="w-full pl-8 pr-3 py-1.5 bg-zinc-100/70 dark:bg-white/[0.04] hover:bg-zinc-200/50 dark:hover:bg-white/[0.07] focus:bg-white dark:focus:bg-zinc-900 border border-zinc-200/60 dark:border-white/10 rounded-xl text-xs outline-none text-zinc-800 dark:text-zinc-100 placeholder-zinc-400 transition-all"
            />
            <Search class="absolute left-2.5 top-2 w-3.5 h-3.5 text-zinc-400" />
          </div>

          <n-button
            secondary
            size="small"
            class="!rounded-xl"
            :loading="executing"
            @click="fetchDiscovery(1)"
            title="重新解析流"
          >
            <template #icon>
              <RefreshCw class="w-3.5 h-3.5" :class="{ 'animate-spin': executing }" />
            </template>
          </n-button>
        </div>
      </div>

      <!-- 第一排：规则源选择切换器 Pills -->
      <div v-if="rules.length > 0" class="pt-2 border-t border-zinc-200/50 dark:border-white/5 space-y-3">
        <div class="flex items-center gap-2 overflow-x-auto no-scrollbar py-0.5">
          <span class="text-xs font-bold text-zinc-400 whitespace-nowrap mr-1 flex items-center gap-1">
            <Layers class="w-3.5 h-3.5" />
            <span>规则源:</span>
          </span>
          <button
            v-for="rule in rules"
            :key="rule.id"
            @click="handleRuleChange(rule.id)"
            class="px-3 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition-all duration-200 cursor-pointer border flex-shrink-0"
            :class="
              activeRuleId === rule.id
                ? 'bg-emerald-600 text-white border-emerald-500 shadow-md shadow-emerald-600/25'
                : 'bg-zinc-100 dark:bg-white/[0.04] text-zinc-600 dark:text-zinc-300 hover:bg-zinc-200 dark:hover:bg-white/[0.08] border-zinc-200/60 dark:border-white/5'
            "
          >
            {{ rule.name }}
          </button>
        </div>

        <!-- 第二排：子分类选择标签 (如有) -->
        <div v-if="subCategories.length > 0" class="flex items-center gap-1.5 overflow-x-auto no-scrollbar pt-1">
          <span class="text-[11px] text-zinc-400 whitespace-nowrap mr-1">分类:</span>
          <button
            v-for="cat in subCategories"
            :key="cat"
            @click="handleCategoryChange(cat)"
            class="px-2.5 py-1 rounded-lg text-[11px] font-medium whitespace-nowrap transition-all duration-200 cursor-pointer"
            :class="
              activeCategory === cat
                ? 'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-300 font-bold border border-emerald-200/50 dark:border-emerald-800/40'
                : 'text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white hover:bg-zinc-100 dark:hover:bg-white/5'
            "
          >
            {{ cat }}
          </button>
        </div>
      </div>
    </div>

    <!-- 主展示区 -->
    <div>
      <!-- 异常状态 -->
      <div
        v-if="errorMsg"
        class="glass-panel rounded-2xl p-8 max-w-md mx-auto my-12 text-center flex flex-col items-center justify-center space-y-3 border-rose-500/30 bg-rose-500/5"
      >
        <AlertCircle class="w-10 h-10 text-rose-500" />
        <h3 class="text-sm font-bold text-rose-600 dark:text-rose-400">解析异常</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">{{ errorMsg }}</p>
        <n-button
          type="error"
          size="small"
          class="!rounded-xl mt-2"
          @click="fetchDiscovery(1)"
        >
          重新尝试
        </n-button>
      </div>

      <!-- 空规则源提示 -->
      <div
        v-else-if="rules.length === 0 && !loading"
        class="glass-panel rounded-2xl p-16 text-center max-w-md mx-auto my-12 flex flex-col items-center justify-center space-y-3"
      >
        <Compass class="w-10 h-10 text-zinc-400" />
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-200">未找到启用的{{ props.type }}规则</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">请前往「规则管理」启用或新建对应的{{ props.type }}规则源。</p>
        <n-button
          type="primary"
          size="small"
          class="!rounded-xl mt-2"
          @click="router.push('/rules')"
        >
          前往规则管理
        </n-button>
      </div>

      <!-- 卡片网格展示流 -->
      <div v-else class="space-y-6">
        <div
          class="grid gap-3 sm:gap-4.5"
          :class="
            props.type === '视频' || props.type === 'video'
              ? 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5'
              : 'grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6'
          "
        >
          <div
            v-for="(item, idx) in filteredItems"
            :key="item.key || idx"
            class="group relative flex flex-col rounded-2xl overflow-hidden bg-white/70 dark:bg-white/[0.03] backdrop-blur-md border border-zinc-200/60 dark:border-white/5 hover:-translate-y-1.5 transition-all duration-300 cursor-pointer shadow-2xs hover:shadow-xl hover:shadow-emerald-500/10 active:scale-98"
            @click="handleCardClick(item)"
          >
            <!-- 封面图容器 -->
            <div class="w-full relative overflow-hidden bg-zinc-200 dark:bg-zinc-900" :class="coverAspectClass">
              <img
                v-if="item.cover"
                :src="item.cover"
                referrerpolicy="no-referrer"
                :alt="item.title"
                class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
                loading="lazy"
              />
              <div v-else class="w-full h-full flex items-center justify-center text-zinc-400">
                <component :is="activeIcon" class="w-8 h-8" />
              </div>

              <!-- 悬浮蒙层 -->
              <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-end p-2.5">
                <span class="text-white text-[11px] font-bold line-clamp-1">
                  {{ !ruleHasDetail(activeRule) ? '点击全屏预览大图' : '点击查看详情' }}
                </span>
              </div>

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

        <!-- 加载更多按钮 -->
        <div v-if="hasMore" class="flex justify-center pt-4">
          <n-button
            secondary
            class="!rounded-xl !px-6"
            :loading="executing"
            @click="loadNextPage"
          >
            <span>{{ executing ? '正在加载下一页...' : '加载更多内容' }}</span>
          </n-button>
        </div>
      </div>
    </div>

    <!-- 壁纸类无详情全屏大图预览弹窗 (Modal Lightbox) -->
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
