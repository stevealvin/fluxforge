<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

defineOptions({ name: 'MediaDetailHub' })
import { ruleService, type RuleSchema, type MediaDetail, type MediaItem } from '@/utils/ruleService'
import { useMediaContext } from '@/stores/mediaContext'
import { ArrowLeft, AlertCircle, RefreshCw } from '@lucide/vue'
import VideoPlayer from './components/VideoPlayer.vue'
import ImageGallery from './components/ImageGallery.vue'
import NovelReader from './components/NovelReader.vue'

const route = useRoute()
const router = useRouter()
const mediaContext = useMediaContext()

const rule = ref<RuleSchema | null>(null)
const detail = ref<MediaDetail | null>(null)
const loading = ref(true)
const executing = ref(false)
const errorMsg = ref('')

const loadDetail = async () => {
  errorMsg.value = ''

  const ruleId = Number(route.query.ruleId)
  const url = (route.query.url || route.query.key) as string

  if (!ruleId || !url) {
    errorMsg.value = '缺少必要的请求参数 (ruleId 或 url)'
    loading.value = false
    executing.value = false
    return
  }

  // 获取预热数据
  const preheat = mediaContext.getContext(ruleId, url)
  if (preheat && !detail.value) {
    detail.value = {
      title: preheat.title || '',
      cover: preheat.cover || '',
      desc: preheat.desc || '',
      tags: preheat.tags || []
    }
  }

  if (!detail.value) {
    loading.value = true
  }
  executing.value = true

  try {
    const ruleRes = await ruleService.getRuleById(ruleId)
    rule.value = ruleRes

    if (!rule.value) {
      errorMsg.value = `规则 [ID:${ruleId}] 不存在`
      loading.value = false
      executing.value = false
      return
    }

    const res = await ruleService.runDetail(rule.value, {
      url,
      item: preheat
    })

    detail.value = res
  } catch (error: any) {
    errorMsg.value = error.message || String(error)
  } finally {
    loading.value = false
    executing.value = false
  }
}

const goToRelated = (item: MediaItem) => {
  const ruleId = Number(route.query.ruleId)
  if (ruleId && item.url) {
    mediaContext.setContext(ruleId, item.url, item)
    router.push({
      path: '/media/detail',
      query: {
        ruleId,
        url: item.url
      }
    })
  }
}

watch([() => route.query.url, () => route.query.key, () => route.query.ruleId], () => {
  loadDetail()
})

onMounted(() => {
  loadDetail()
})
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12">
    <!-- 顶部操作栏 -->
    <div class="glass-panel rounded-2xl p-4 sm:p-5 flex items-center justify-between shadow-sm">
      <div class="flex items-center gap-3 min-w-0">
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
        <div class="min-w-0">
          <h1 class="text-base sm:text-lg font-black tracking-tight text-zinc-900 dark:text-white truncate">
            {{ detail?.title || '详情' }}
          </h1>
          <p class="text-xs text-zinc-500 dark:text-zinc-400" v-if="rule">
            来源: {{ rule.name }}
          </p>
        </div>
      </div>

      <!-- 刷新按钮 -->
      <n-button
        size="small"
        secondary
        class="!rounded-xl"
        :loading="executing"
        @click="loadDetail"
        title="重新解析"
      >
        <template #icon>
          <RefreshCw class="w-3.5 h-3.5" :class="{ 'animate-spin': executing }" />
        </template>
        <span>刷新</span>
      </n-button>
    </div>

    <!-- 主展示面板 -->
    <div>
      <div v-if="loading && !detail" class="flex flex-col items-center justify-center py-28 gap-3">
        <n-spin size="large" />
        <span class="text-zinc-400 text-sm">正在加载媒体数据...</span>
      </div>

      <div
        v-else-if="errorMsg && !detail"
        class="glass-panel rounded-2xl p-8 max-w-md mx-auto my-12 text-center flex flex-col items-center justify-center space-y-3 border-rose-500/30 bg-rose-500/5"
      >
        <AlertCircle class="w-10 h-10 text-rose-500" />
        <h3 class="text-sm font-bold text-rose-600 dark:text-rose-400">解析异常</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">{{ errorMsg }}</p>
        <n-button
          type="error"
          size="small"
          class="!rounded-xl mt-2"
          @click="loadDetail"
        >
          重新尝试
        </n-button>
      </div>

      <div v-else-if="detail" class="w-full">
        <!-- 1. 视频播放器与选集 -->
        <VideoPlayer
          v-if="rule?.type === 'video'"
          :detail="detail"
          :rule="rule || undefined"
          @select="goToRelated"
        />

        <!-- 2. 图集画廊 -->
        <ImageGallery
          v-else-if="rule?.type === 'picture'"
          :images="detail.images || []"
          :title="detail.title"
          :desc="detail.desc"
        />

        <!-- 3. 小说阅读器与章节 -->
        <NovelReader
          v-else-if="rule?.type === 'novel'"
          :detail="detail"
          :rule="rule || undefined"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>
