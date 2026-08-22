<script setup lang="ts">
import { ref } from 'vue'
import { Play, Layers, Compass, ListVideo, Sparkles } from '@lucide/vue'
import ArtPlayer from '@/components/ArtPlayer.vue'
import type { MediaDetail, MediaEpisode, MediaItem, RuleSchema } from '@/types/rule'
import { ruleService } from '@/utils/ruleService'

const props = defineProps<{
  detail: MediaDetail
  rule?: RuleSchema
}>()

const emit = defineEmits<{
  (e: 'select', item: MediaItem): void
}>()

const activeEpisodeKey = ref<string>('')
const currentVideoUrl = ref<string>(props.detail.playUrl || '')
const parsing = ref(false)
const parseError = ref('')

// 若有选集分组，默认高亮第一集
if (props.detail.groups && props.detail.groups.length > 0 && props.detail.groups[0].items.length > 0) {
  activeEpisodeKey.value = props.detail.groups[0].items[0].key
}

const handleEpisodeClick = async (ep: MediaEpisode, groupName: string) => {
  activeEpisodeKey.value = ep.key
  parseError.value = ''

  // 如果 ep.key 本身就是直链或包含 .m3u8 / .mp4
  if (ep.key.startsWith('http') && (ep.key.includes('.m3u8') || ep.key.includes('.mp4'))) {
    currentVideoUrl.value = ep.key
    return
  }

  // 否则尝试调用规则的 parse 钩子
  if (props.rule) {
    parsing.value = true
    try {
      const res = await ruleService.runParse(props.rule, {
        key: ep.key,
        groupName
      })
      if (res.playUrl) {
        currentVideoUrl.value = res.playUrl
      } else {
        parseError.value = '未能解析到播放地址'
      }
    } catch (e: any) {
      parseError.value = '解析分集失败: ' + e.message
    } finally {
      parsing.value = false
    }
  }
}
</script>

<template>
  <div class="flex flex-col gap-8 w-full">
    <!-- 上半部分：左播放器，右侧视频详情与选集 -->
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 w-full items-start">
      <!-- 左侧：播放器主体 -->
      <div class="lg:col-span-8 xl:col-span-9 flex flex-col gap-4">
        <div class="aspect-video w-full rounded-2xl overflow-hidden bg-black shadow-2xl relative border border-slate-200/60 dark:border-white/10">
          <div v-if="parsing" class="w-full h-full flex flex-col items-center justify-center text-slate-300 gap-3">
            <n-spin size="large" />
            <span class="text-xs">正在解析分集播放直链...</span>
          </div>
          <ArtPlayer
            v-else-if="currentVideoUrl"
            :url="currentVideoUrl"
            :title="detail.title"
          />
          <div v-else class="w-full h-full flex flex-col items-center justify-center text-slate-400 gap-2 min-h-[300px]">
            <Play class="w-12 h-12 text-slate-500" />
            <span class="text-xs">{{ parseError || '未能获取有效的视频播放地址' }}</span>
          </div>
        </div>
      </div>

      <!-- 右侧：视频信息与选集分组 -->
      <div class="lg:col-span-4 xl:col-span-3 flex flex-col gap-4">
        <!-- 视频标题、标签与简介面板 -->
        <div class="glass-panel rounded-2xl p-5 space-y-3 shadow-sm">
          <h2 class="text-base sm:text-lg font-black text-slate-900 dark:text-white leading-snug">
            {{ detail.title }}
          </h2>

          <!-- 标签 Tags -->
          <div v-if="detail.tags && detail.tags.length > 0" class="flex flex-wrap gap-1.5">
            <span
              v-for="t in detail.tags"
              :key="t"
              class="px-2 py-0.5 text-[10px] font-bold rounded-md bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-200/40 dark:border-emerald-800/30"
            >
              {{ t }}
            </span>
          </div>

          <!-- 详情介绍 (支持换行符显示) -->
          <div
            v-if="detail.desc"
            class="text-xs text-zinc-600 dark:text-zinc-300 leading-relaxed pt-1 max-h-48 overflow-y-auto whitespace-pre-line break-words"
            v-html="detail.desc"
          />
        </div>

        <!-- 选集 / 分集列表 (置于播放器右侧) -->
        <div v-if="detail.groups && detail.groups.length > 0" class="glass-panel rounded-2xl p-5 space-y-4 shadow-sm">
          <div v-for="group in detail.groups" :key="group.name" class="space-y-2.5">
            <div class="flex items-center gap-2 pb-1 border-b border-emerald-100/50 dark:border-white/5">
              <div class="w-1.5 h-4 rounded-full bg-gradient-to-b from-emerald-500 via-teal-500 to-cyan-500"></div>
              <h3 class="text-xs font-bold text-zinc-800 dark:text-zinc-100">{{ group.name }}</h3>
            </div>
            <div class="flex flex-wrap gap-2 max-h-60 overflow-y-auto pr-1">
              <n-button
                v-for="ep in group.items"
                :key="ep.key"
                size="small"
                :type="activeEpisodeKey === ep.key ? 'primary' : 'default'"
                :secondary="activeEpisodeKey !== ep.key"
                class="!rounded-xl !font-semibold"
                @click="handleEpisodeClick(ep, group.name)"
              >
                {{ ep.title }}
              </n-button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 下半部分：剧照预览与相关推荐 (平铺于播放器下方) -->
    <div class="space-y-8 w-full">
      <!-- 剧照 / 预览图片流 (如有) -->
      <div v-if="detail.images && detail.images.length > 0" class="space-y-3">
        <div class="flex items-center gap-2 pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
          <div class="w-1.5 h-4.5 rounded-full bg-gradient-to-b from-emerald-500 via-teal-500 to-cyan-500"></div>
          <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-100">剧照与画廊预览</h3>
        </div>
        <n-image-group>
          <div class="grid gap-3 sm:gap-4 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
            <div
              v-for="(img, idx) in detail.images"
              :key="idx"
              class="group rounded-2xl overflow-hidden bg-zinc-200 dark:bg-zinc-900 border border-emerald-100/60 dark:border-white/5 aspect-[16/10] cursor-pointer relative"
            >
              <n-image
                :src="img"
                referrerpolicy="no-referrer"
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                lazy
              />
            </div>
          </div>
        </n-image-group>
      </div>

      <!-- 相关推荐列表 (置于下方宽幅网格) -->
      <div v-if="detail.recommendations && detail.recommendations.length > 0" class="space-y-3">
        <div class="flex items-center gap-2 pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
          <div class="w-1.5 h-4.5 rounded-full bg-gradient-to-b from-emerald-500 via-teal-500 to-cyan-500"></div>
          <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-100">相关推荐</h3>
        </div>
        <div class="grid gap-3 sm:gap-4.5 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
          <div
            v-for="(item, idx) in detail.recommendations"
            :key="item.key || idx"
            class="group relative flex flex-col rounded-2xl overflow-hidden bg-white/70 dark:bg-white/[0.03] backdrop-blur-md border border-emerald-100/60 dark:border-white/5 hover:-translate-y-1.5 transition-all duration-300 cursor-pointer shadow-2xs hover:shadow-xl hover:shadow-emerald-500/10 active:scale-98"
            @click="emit('select', item)"
          >
            <div class="aspect-[16/10] overflow-hidden relative bg-zinc-200 dark:bg-zinc-900">
              <img
                v-if="item.cover"
                :src="item.cover"
                referrerpolicy="no-referrer"
                :alt="item.title"
                class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
                loading="lazy"
              />
              <div v-else class="w-full h-full flex items-center justify-center text-zinc-400">
                <Play class="w-6 h-6" />
              </div>
            </div>
            <div class="p-2.5 flex flex-col justify-between flex-1">
              <h4 class="text-xs font-bold text-zinc-800 dark:text-zinc-200 line-clamp-1 leading-snug group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                {{ item.title }}
              </h4>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>
