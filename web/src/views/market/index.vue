<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useMessage } from 'naive-ui'

defineOptions({ name: 'MarketView' })
import {
  Store,
  ExternalLink,
  Copy,
  Plus,
  Search,
  Globe,
  Compass,
  Sparkles,
  Layers,
  Bookmark,
  Trash2,
  Tv,
  BookOpen,
  Video,
  Code
} from '@lucide/vue'

const message = useMessage()

interface SiteSource {
  id: string
  name: string
  url: string
  description: string
  category: '综合' | '影视' | '小说' | '漫画' | '社区'
  tags: string[]
  badge?: string
  isCustom?: boolean
}

// 预置的精选规则分享站点
const defaultSites: SiteSource[] = [
  {
    id: 'yckceo',
    name: '源仓库 (YCKCEO)',
    url: 'https://www.yckceo.com/',
    description: '全网知名海量多源聚合站，汇聚阅读3.0、海阔视界、影视视界、跨媒体沙箱及书源规则。',
    category: '综合',
    tags: ['综合大站', '阅读书源', '海阔规则', '持续更新'],
    badge: '官方推荐'
  },
  {
    id: 'yckceo-haikuo',
    name: '源小二 · 视界规则专区',
    url: 'https://www.yckceo.com/haikuo/',
    description: '专注于视界沙箱解析、短视频、影视播放插件及网页抓取 JS 脚本规则的开放分享中心。',
    category: '影视',
    tags: ['沙箱规则', '影视播放', 'JS解析'],
    badge: '精品专区'
  },
  {
    id: 'yckceo-yuedu',
    name: '源仓库 · 阅读3.0书源库',
    url: 'https://www.yckceo.com/yuedu/',
    description: '数万条小说书源在线分享，支持导入、一键校验，涵盖起点、纵横、晋江全网精品书源。',
    category: '小说',
    tags: ['小说网文', '书源3.0', '多源校验'],
    badge: '海量书库'
  },
  {
    id: 'tvbox-sources',
    name: 'TVBox 影视接口聚合',
    url: 'https://github.com/topics/tvbox',
    description: 'GitHub 上广受欢迎的跨端影视解析接口与规则集合，提供多仓配置与实时接口。',
    category: '影视',
    tags: ['开源接口', '多仓订阅', '影视流'],
    badge: 'GitHub'
  },
  {
    id: 'legado-forum',
    name: '开源阅读 Legado 社区',
    url: 'https://github.com/gedoor/legado',
    description: '开源规则与书源开发者论坛，分享各种复杂的正则解析、XPath 抽取及 JavaScript 沙箱脚本。',
    category: '社区',
    tags: ['开源开发者', '正则语法', '沙箱引擎'],
    badge: '开发者'
  }
]

const STORAGE_KEY = 'fluxforge-market-sites'
const LEGACY_STORAGE_KEY = 'flux-view-market-sites'

const sites = ref<SiteSource[]>([])
const searchQuery = ref('')
const selectedCategory = ref<string>('全部')
const showAddModal = ref(false)

const newSiteForm = ref({
  name: '',
  url: '',
  description: '',
  category: '综合' as '综合' | '影视' | '小说' | '漫画' | '社区',
  tagsString: ''
})

const categories = ['全部', '综合', '影视', '小说', '社区']

const loadSites = () => {
  const customJson = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY)
  if (customJson) {
    try {
      const customSites = JSON.parse(customJson)
      sites.value = [...defaultSites, ...customSites]
    } catch (e) {
      sites.value = [...defaultSites]
    }
  } else {
    sites.value = [...defaultSites]
  }
}

const filteredSites = computed(() => {
  return sites.value.filter((site) => {
    const matchCategory = selectedCategory.value === '全部' || site.category === selectedCategory.value
    const query = searchQuery.value.toLowerCase().trim()
    const matchSearch =
      !query ||
      site.name.toLowerCase().includes(query) ||
      site.description.toLowerCase().includes(query) ||
      site.url.toLowerCase().includes(query) ||
      site.tags.some((t) => t.toLowerCase().includes(query))
    return matchCategory && matchSearch
  })
})

const openSite = (url: string) => {
  window.open(url, '_blank', 'noopener,noreferrer')
}

const copyUrl = async (url: string, name: string) => {
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(url)
    } else {
      const textarea = document.createElement('textarea')
      textarea.value = url
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand('copy')
      document.body.removeChild(textarea)
    }
    message.success(`已复制「${name}」链接到剪贴板`)
  } catch (e: any) {
    message.error('复制链接失败: ' + e.message)
  }
}

const handleAddSite = () => {
  if (!newSiteForm.value.name.trim() || !newSiteForm.value.url.trim()) {
    message.warning('请填写网站名称和有效网址')
    return
  }

  let formattedUrl = newSiteForm.value.url.trim()
  if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
    formattedUrl = 'https://' + formattedUrl
  }

  const tags = newSiteForm.value.tagsString
    ? newSiteForm.value.tagsString.split(/[,，\s]+/).filter(Boolean)
    : ['自定义收藏']

  const newSite: SiteSource = {
    id: 'custom_' + Date.now(),
    name: newSiteForm.value.name.trim(),
    url: formattedUrl,
    description: newSiteForm.value.description.trim() || '用户自定义添加的规则分享站点',
    category: newSiteForm.value.category,
    tags,
    badge: '自定义',
    isCustom: true
  }

  const customJson = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY)
  const currentCustom: SiteSource[] = customJson ? JSON.parse(customJson) : []
  currentCustom.push(newSite)
  localStorage.setItem(STORAGE_KEY, JSON.stringify(currentCustom))

  message.success(`成功添加站点「${newSite.name}」`)
  showAddModal.value = false
  newSiteForm.value = {
    name: '',
    url: '',
    description: '',
    category: '综合',
    tagsString: ''
  }
  loadSites()
}

const removeCustomSite = (id: string, name: string) => {
  const customJson = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY)
  if (!customJson) return
  try {
    let currentCustom: SiteSource[] = JSON.parse(customJson)
    currentCustom = currentCustom.filter((s) => s.id !== id)
    localStorage.setItem(STORAGE_KEY, JSON.stringify(currentCustom))
    message.success(`已删除自定义站点「${name}」`)
    loadSites()
  } catch (e) {}
}

const getCategoryIcon = (category: string) => {
  switch (category) {
    case '影视':
      return Video
    case '小说':
      return BookOpen
    case '社区':
      return Code
    default:
      return Globe
  }
}

onMounted(() => {
  loadSites()
})
</script>

<template>
  <div class="space-y-6 max-w-7xl mx-auto pb-12">
    <!-- 顶部 Banner 与控制台 (mori-box 风格) -->
    <div class="glass-panel rounded-2xl p-5 sm:p-6 space-y-4 shadow-sm">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <!-- 页面标题与理念介绍 -->
        <div class="flex items-center gap-3.5">
          <div class="w-11 h-11 rounded-2xl bg-gradient-to-tr from-emerald-600 via-teal-500 to-cyan-500 text-white flex items-center justify-center shadow-md shadow-emerald-500/25 flex-shrink-0">
            <Store class="w-5 h-5" />
          </div>
          <div>
            <h1 class="text-base sm:text-xl font-black tracking-tight text-zinc-900 dark:text-white flex items-center gap-2">
              <span>规则集市 · 源生态</span>
              <span class="px-2 py-0.5 text-[10px] font-mono font-bold rounded-full bg-emerald-50/80 dark:bg-emerald-950/30 text-emerald-600 dark:text-emerald-400 border border-emerald-200/50 dark:border-emerald-800/30">
                RULE MARKET
              </span>
            </h1>
            <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
              精选全网优质规则分享站点与社区，发现更多影视视界、小说书源及媒体沙箱规则。
            </p>
          </div>
        </div>

        <!-- 自定义添加站点按钮 -->
        <n-button
          type="primary"
          size="small"
          class="!rounded-xl !font-bold"
          @click="showAddModal = true"
        >
          <template #icon>
            <Plus class="w-4 h-4" />
          </template>
          <span>添加收藏站点</span>
        </n-button>
      </div>

      <!-- 分类标签与搜索筛选条 -->
      <div class="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-emerald-100/50 dark:border-white/5">
        <!-- 分类切换胶囊按钮 (Segmented Pills) -->
        <div class="flex items-center gap-1.5 overflow-x-auto no-scrollbar py-0.5">
          <n-button
            v-for="cat in categories"
            :key="cat"
            size="small"
            :type="selectedCategory === cat ? 'primary' : 'default'"
            :secondary="selectedCategory !== cat"
            class="!rounded-xl !font-bold flex-shrink-0"
            @click="selectedCategory = cat"
          >
            {{ cat }}
          </n-button>
        </div>

        <!-- 搜索输入框 -->
        <div class="relative w-full sm:w-64">
          <Search class="absolute left-3 top-2.5 w-3.5 h-3.5 text-zinc-400" />
          <input
            v-model="searchQuery"
            type="text"
            placeholder="搜索源站名称、标签或网址..."
            class="w-full pl-8 pr-3 py-1.5 bg-emerald-50/60 dark:bg-white/[0.04] hover:bg-emerald-100/50 dark:hover:bg-white/[0.07] focus:bg-white dark:focus:bg-zinc-900 border border-emerald-200/60 dark:border-white/10 rounded-xl text-xs outline-none text-zinc-800 dark:text-zinc-100 placeholder-zinc-400 transition-all"
          />
        </div>
      </div>
    </div>

    <!-- 站点卡片网格列表 (mori-box 风格) -->
    <div class="space-y-4">
      <div v-if="filteredSites.length === 0" class="glass-panel rounded-2xl p-16 text-center max-w-md mx-auto my-12 flex flex-col items-center justify-center space-y-3">
        <Compass class="w-10 h-10 text-zinc-400" />
        <h3 class="text-sm font-bold text-zinc-800 dark:text-zinc-200">没有找到匹配的规则站点</h3>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">尝试更换搜索关键字，或点击上方“添加收藏站点”。</p>
      </div>

      <div v-else class="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="site in filteredSites"
          :key="site.id"
          class="glass-panel glass-panel-hover rounded-2xl p-5 flex flex-col justify-between h-full group relative border border-emerald-100/60 dark:border-white/5"
        >
          <!-- 上半部：站点头部与描述 -->
          <div class="space-y-3">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3 min-w-0">
                <div class="w-10 h-10 rounded-xl bg-emerald-500/10 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 flex items-center justify-center border border-emerald-500/20 flex-shrink-0 group-hover:scale-105 transition-transform">
                  <component :is="getCategoryIcon(site.category)" class="w-5 h-5" />
                </div>
                <div class="min-w-0">
                  <h3 class="text-sm font-bold text-zinc-900 dark:text-white truncate group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                    {{ site.name }}
                  </h3>
                  <div class="flex items-center gap-2 mt-0.5">
                    <span class="text-[10px] font-mono text-zinc-400 dark:text-zinc-500 truncate max-w-[170px]">
                      {{ site.url.replace(/^https?:\/\//, '').replace(/\/$/, '') }}
                    </span>
                  </div>
                </div>
              </div>

              <!-- 徽章 Tag -->
              <span
                v-if="site.badge"
                class="px-2 py-0.5 text-[9px] font-black rounded-full border flex-shrink-0"
                :class="
                  site.isCustom
                    ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20'
                    : 'bg-emerald-600/10 text-emerald-600 dark:text-emerald-400 border-emerald-600/20'
                "
              >
                {{ site.badge }}
              </span>
            </div>

            <!-- 站点介绍 -->
            <p class="text-xs text-zinc-600 dark:text-zinc-300 line-clamp-3 leading-relaxed">
              {{ site.description }}
            </p>

            <!-- 标签列表 -->
            <div class="flex flex-wrap gap-1.5 pt-1">
              <span
                v-for="tag in site.tags"
                :key="tag"
                class="px-2 py-0.5 text-[10px] font-medium rounded-lg bg-emerald-50/60 dark:bg-white/[0.04] text-zinc-600 dark:text-zinc-400 border border-emerald-100/50 dark:border-white/5"
              >
                {{ tag }}
              </span>
            </div>
          </div>

          <!-- 下半部：动作栏 (直达访问 & 复制链接 & 删除) -->
          <div class="pt-4 mt-4 border-t border-emerald-100/50 dark:border-white/5 flex items-center justify-between text-xs">
            <div class="flex items-center gap-1.5">
              <n-button
                size="tiny"
                quaternary
                class="!rounded-lg text-zinc-600 dark:text-zinc-300"
                @click="copyUrl(site.url, site.name)"
                title="复制站点地址"
              >
                <template #icon>
                  <Copy class="w-3 h-3" />
                </template>
                <span>复制链接</span>
              </n-button>

              <n-button
                v-if="site.isCustom"
                size="tiny"
                quaternary
                circle
                class="text-zinc-400 hover:text-rose-500"
                @click="removeCustomSite(site.id, site.name)"
                title="删除自定义站点"
              >
                <template #icon>
                  <Trash2 class="w-3 h-3" />
                </template>
              </n-button>
            </div>

            <!-- 直达访问主按钮 -->
            <n-button
              size="small"
              type="primary"
              class="!rounded-xl !font-bold"
              @click="openSite(site.url)"
            >
              <span>立即直达</span>
              <template #icon>
                <ExternalLink class="w-3.5 h-3.5" />
              </template>
            </n-button>
          </div>
        </div>
      </div>
    </div>

    <!-- 添加自定义站点弹窗 Modal -->
    <n-modal v-model:show="showAddModal" preset="card" title="添加规则分享站点" class="max-w-lg">
      <div class="space-y-4">
        <div>
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 block mb-1.5">站点名称 *</label>
          <n-input v-model:value="newSiteForm.name" placeholder="如: 某某开源源站 / 影视规则库" clearable />
        </div>

        <div>
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 block mb-1.5">站点网址 URL *</label>
          <n-input v-model:value="newSiteForm.url" placeholder="如: https://www.yckceo.com/" clearable />
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 block mb-1.5">主要分类</label>
            <n-select
              v-model:value="newSiteForm.category"
              :options="[
                { label: '综合', value: '综合' },
                { label: '影视', value: '影视' },
                { label: '小说', value: '小说' },
                { label: '漫画', value: '漫画' },
                { label: '社区', value: '社区' }
              ]"
            />
          </div>
          <div>
            <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 block mb-1.5">标签 (空格或逗号分隔)</label>
            <n-input v-model:value="newSiteForm.tagsString" placeholder="书源 影视 精品" clearable />
          </div>
        </div>

        <div>
          <label class="text-xs font-bold text-zinc-700 dark:text-zinc-300 block mb-1.5">站点特色说明</label>
          <n-input v-model:value="newSiteForm.description" type="textarea" placeholder="简要描述站点的核心规则类型与特色..." :rows="3" />
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <n-button
            size="small"
            quaternary
            class="!rounded-xl !font-bold"
            @click="showAddModal = false"
          >
            取消
          </n-button>
          <n-button
            size="small"
            type="primary"
            class="!rounded-xl !font-bold"
            @click="handleAddSite"
          >
            确认添加
          </n-button>
        </div>
      </div>
    </n-modal>
  </div>
</template>

<style scoped>
.no-scrollbar::-webkit-scrollbar {
  display: none;
}
.no-scrollbar {
  -ms-overflow-style: none;
  scrollbar-width: none;
}
</style>
