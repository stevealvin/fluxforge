<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'

defineOptions({ name: 'HomeView' })
import { ruleService } from '@/utils/ruleService'
import {
  Search,
  Compass,
  ArrowRight,
  ShieldAlert,
  Video,
  Image as ImageIcon,
  BookOpen,
  Sparkles,
  SlidersHorizontal
} from '@lucide/vue'

const router = useRouter()
const searchKeyword = ref('')
const rules = ref<any[]>([])
const loading = ref(true)

const loadRules = async () => {
  loading.value = true
  try {
    const allRules = ruleService.getRules()
    rules.value = allRules.filter((r: any) => r.enabled === 1 || r.enabled === true)
  } catch (error) {
    console.error('Failed to load rules:', error)
  } finally {
    loading.value = false
  }
}

const handleSearch = () => {
  if (searchKeyword.value.trim()) {
    router.push({ path: '/search', query: { q: searchKeyword.value.trim() } })
  }
}

const goToSource = (rule: any) => {
  if (rule.type === 'video' || rule.type === '视频') {
    router.push('/video')
  } else if (rule.type === 'picture' || rule.type === '图片') {
    router.push('/picture')
  } else if (rule.type === 'novel' || rule.type === '小说') {
    router.push('/novel')
  } else {
    router.push('/rules')
  }
}

const getTypeIcon = (type: string) => {
  switch (type) {
    case 'video':
    case '视频': return Video
    case 'picture':
    case '图片': return ImageIcon
    case 'novel':
    case '小说': return BookOpen
    default: return Compass
  }
}

const getTypeBadgeColor = (type: string) => {
  switch (type) {
    case 'video':
    case '视频': return 'bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 border-indigo-500/20'
    case 'picture':
    case '图片': return 'bg-pink-500/10 text-pink-600 dark:text-pink-400 border-pink-500/20'
    case 'novel':
    case '小说': return 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20'
    default: return 'bg-sky-500/10 text-sky-600 dark:text-sky-400 border-sky-500/20'
  }
}

onMounted(() => {
  loadRules()
})
</script>

<template>
  <div class="space-y-8 max-w-6xl mx-auto pb-10">
    <!-- 顶部 Hero 区域 -->
    <div class="text-center pt-8 sm:pt-14 space-y-4">
      <div class="inline-flex items-center gap-2 px-3.5 py-1 rounded-full text-xs font-semibold bg-emerald-50/80 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-300 border border-emerald-200/50 dark:border-emerald-800/40 shadow-2xs">
        <Sparkles class="w-3.5 h-3.5 text-emerald-500 animate-spin" style="animation-duration: 8s" />
        <span>沙箱规则驱动 · 全网多媒体聚合</span>
      </div>

      <h1 class="text-3xl sm:text-5xl font-black tracking-tight text-zinc-900 dark:text-white">
        流光视界 · <span class="gradient-flux font-['Plus_Jakarta_Sans','Outfit']">FluxForge</span>
      </h1>

      <p class="text-sm sm:text-base text-zinc-600 dark:text-zinc-400 max-w-xl mx-auto font-normal">
        轻量高效的多源聚合浏览空间，将跨站视频、图集画廊与小说源集中呈现在纯净视界。
      </p>

      <!-- 聚合全局搜索框 -->
      <div class="max-w-2xl w-full mx-auto pt-4">
        <div class="glass-panel rounded-2xl p-2 shadow-xl shadow-emerald-600/5 focus-within:shadow-emerald-600/15 focus-within:border-emerald-500/50 transition-all border border-emerald-100/60 dark:border-white/[0.08]">
          <div class="flex items-center gap-2">
            <Search class="w-5 h-5 text-zinc-400 dark:text-zinc-500 ml-2.5 flex-shrink-0" />
            <input
              v-model="searchKeyword"
              type="text"
              placeholder="搜索全网视频、图片、小说资源..."
              class="w-full bg-transparent border-none outline-none text-zinc-800 dark:text-zinc-100 placeholder-zinc-400 text-sm py-2 px-1"
              @keyup.enter="handleSearch"
            />
            <n-button
              type="primary"
              class="!rounded-xl !font-bold flex-shrink-0"
              @click="handleSearch"
            >
              聚合搜索
            </n-button>
          </div>
        </div>
      </div>
    </div>

    <!-- 数据源与规则轨卡片区 -->
    <div class="space-y-4 pt-4">
      <!-- 栏目标题区 -->
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center gap-2.5">
          <div class="w-1.5 h-5 rounded-full bg-gradient-to-b from-emerald-500 via-teal-500 to-cyan-500 flex-shrink-0"></div>
          <h2 class="text-base sm:text-lg font-black tracking-tight text-zinc-800 dark:text-zinc-100 flex items-center gap-2">
            <span>已启用的数据源</span>
            <span class="hidden sm:inline text-xs font-normal text-zinc-400 dark:text-zinc-500 uppercase tracking-wider font-mono">ACTIVE SOURCES</span>
          </h2>
        </div>

        <div class="flex items-center gap-3">
          <div class="flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-emerald-50/80 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400 border border-emerald-100/50 dark:border-emerald-900/30 shadow-2xs">
            <span class="relative flex h-1.5 w-1.5">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-500"></span>
            </span>
            <span>已接入 <strong class="font-bold font-mono">{{ rules.length }}</strong> 个规则源</span>
          </div>

          <n-button
            size="small"
            secondary
            class="!rounded-xl !font-bold"
            @click="router.push('/rules')"
          >
            <template #icon>
              <SlidersHorizontal class="w-3.5 h-3.5" />
            </template>
            规则管理
          </n-button>
        </div>
      </div>

      <!-- 加载中骨架 -->
      <div v-if="loading" class="grid gap-4 grid-cols-1 sm:grid-cols-2 md:grid-cols-3">
        <div v-for="n in 6" :key="n" class="glass-panel rounded-2xl p-5 space-y-3">
          <div class="h-5 w-24 bg-emerald-100/60 dark:bg-zinc-800/40 rounded-lg animate-pulse"></div>
          <div class="h-4 w-full bg-emerald-100/40 dark:bg-zinc-800/20 rounded-md animate-pulse"></div>
          <div class="h-4 w-2/3 bg-emerald-100/40 dark:bg-zinc-800/20 rounded-md animate-pulse"></div>
        </div>
      </div>

      <!-- 空白无数据源提示 -->
      <div
        v-else-if="rules.length === 0"
        class="glass-panel rounded-2xl p-12 text-center flex flex-col items-center justify-center space-y-3 border border-emerald-100/60 dark:border-white/[0.08]"
      >
        <div class="w-12 h-12 rounded-2xl bg-amber-500/10 text-amber-500 flex items-center justify-center border border-amber-500/20">
          <ShieldAlert class="w-6 h-6" />
        </div>
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-100">暂无启用的规则源</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400 max-w-sm">
          尚未启用任何规则。请前往规则管理中心导入或开启解析规则。
        </p>
        <n-button
          type="primary"
          class="!rounded-xl !font-bold mt-2"
          @click="router.push('/rules')"
        >
          前往配置规则
        </n-button>
      </div>

      <!-- 数据源卡片网格 (微拟态悬浮卡片) -->
      <div v-else class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="rule in rules"
          :key="rule.id"
          @click="goToSource(rule)"
          class="glass-card rounded-2xl p-5 flex flex-col justify-between cursor-pointer group"
        >
          <div class="space-y-3">
            <!-- 卡片顶部：图标、规则名与分类 Tag -->
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-emerald-500/10 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 flex items-center justify-center border border-emerald-500/20 group-hover:scale-105 transition-transform">
                  <component :is="getTypeIcon(rule.type)" class="w-5 h-5" />
                </div>
                <div>
                  <h3 class="text-sm font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                    {{ rule.name || rule.title || '自定义规则' }}
                  </h3>
                  <p class="text-[11px] font-mono text-zinc-400 dark:text-zinc-500">v{{ rule.version || '1.0.0' }}</p>
                </div>
              </div>

              <!-- 类型角标 -->
              <span
                class="px-2.5 py-0.5 text-[10px] font-bold rounded-full border"
                :class="getTypeBadgeColor(rule.type)"
              >
                {{ rule.type === 'video' ? '视频' : rule.type === 'picture' ? '图集' : rule.type === 'novel' ? '小说' : rule.type }}
              </span>
            </div>

            <!-- 规则描述 -->
            <p class="text-xs text-zinc-600 dark:text-zinc-300 line-clamp-2 leading-relaxed">
              {{ rule.description || '高效沙箱解析规则，支持多维分类发现与详情检索。' }}
            </p>
          </div>

          <!-- 卡片底部作者与动作进入按键 -->
          <div class="pt-4 mt-4 border-t border-emerald-100/50 dark:border-white/5 flex items-center justify-between text-xs">
            <span class="text-zinc-400 dark:text-zinc-500 text-[11px] font-medium">
              作者: {{ rule.author || '官方预置' }}
            </span>
            <div class="flex items-center gap-1 font-bold text-emerald-600 dark:text-emerald-400 group-hover:translate-x-1 transition-transform">
              <span>探索发现</span>
              <ArrowRight class="w-3.5 h-3.5" />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
</style>