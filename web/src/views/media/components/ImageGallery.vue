<script setup lang="ts">
import { Image as ImageIcon } from '@lucide/vue'

type Props = {
  images: any[]
  title?: string
  desc?: string
}

withDefaults(defineProps<Props>(), {
  images: () => [],
  title: '',
  desc: ''
})

const getImageUrl = (img: any): string => {
  if (typeof img === 'string') return img
  return img?.url || img?.src || img?.cover || ''
}
</script>

<template>
  <div class="space-y-5 max-w-7xl mx-auto pb-12">
    <!-- 图集介绍面板 (如有) -->
    <div v-if="title || desc" class="glass-panel rounded-2xl p-5 space-y-2 shadow-sm">
      <h2 v-if="title" class="text-base sm:text-lg font-black text-slate-900 dark:text-white">
        {{ title }}
      </h2>
      <p v-if="desc" class="text-xs text-slate-500 dark:text-slate-400 leading-relaxed whitespace-pre-line break-words">
        {{ desc }}
      </p>
    </div>

    <!-- 顶部状态栏 -->
    <div class="flex items-center justify-between pb-1.5 border-b border-emerald-100/50 dark:border-white/5">
      <div class="flex items-center gap-2">
        <div class="w-1.5 h-4.5 rounded-full bg-gradient-to-b from-emerald-500 via-teal-500 to-cyan-500"></div>
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-100">
          图集画廊
        </h3>
      </div>
      <span class="px-2.5 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50/80 dark:bg-emerald-950/30 text-emerald-600 dark:text-emerald-400 border border-emerald-200/40 dark:border-emerald-800/30">
        共 {{ images.length }} 张（点击开启全屏预览）
      </span>
    </div>

    <!-- 图片瀑布流网格 -->
    <n-image-group>
      <div class="grid gap-4 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
        <div
          v-for="(img, index) in images"
          :key="index"
          class="overflow-hidden rounded-2xl border border-emerald-100/60 dark:border-white/5 bg-zinc-100 dark:bg-zinc-900 shadow-2xs hover:shadow-lg transition-all duration-300 relative group aspect-[3/4] cursor-pointer"
        >
          <n-image
            :src="getImageUrl(img)"
            referrerpolicy="no-referrer"
            class="w-full h-full object-cover rounded-2xl overflow-hidden"
            lazy
            show-toolbar-tooltip
          />
        </div>
      </div>
    </n-image-group>
  </div>
</template>

<style scoped>
:deep(.n-image) {
  width: 100%;
  height: 100%;
}
:deep(.n-image img) {
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: transform 0.4s ease;
}
:deep(.n-image:hover img) {
  transform: scale(1.05);
}
</style>
