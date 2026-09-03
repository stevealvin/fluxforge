<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useThemeStore } from '@/stores/theme'
import { useTabsStore } from '@/stores/tabs'
import {
  Sun,
  Moon,
  Home,
  Image,
  Search,
  FileBraces,
  ChevronsLeft,
  ChevronsRight,
  Video,
  BookOpen,
  Store,
  X,
  MoreHorizontal,
  Sparkles,
  Settings
} from '@lucide/vue'
import SettingsModal from '@/components/SettingsModal.vue'

const route = useRoute()
const router = useRouter()
const themeStore = useThemeStore()
const isCollapsed = ref(false)
const tabsStore = useTabsStore()
const showSettingsModal = ref(false)

const toggleCollapse = () => {
  isCollapsed.value = !isCollapsed.value
}

// 监听路由变化，自动新增或激活标签
watch(
  () => route.fullPath,
  () => {
    tabsStore.addTab(route)
  },
  { immediate: true }
)

const handleTabClick = (fullPath: string) => {
  if (route.fullPath !== fullPath) {
    router.push(fullPath)
  }
}

const handleCloseTab = (fullPath: string) => {
  const nextPath = tabsStore.closeTab(fullPath)
  if (nextPath) {
    router.push(nextPath)
  }
}

const handleSelectTabOption = (key: string) => {
  if (key === 'close-others') {
    tabsStore.closeOtherTabs(route.fullPath)
  } else if (key === 'close-all') {
    const nextPath = tabsStore.closeAllTabs()
    router.push(nextPath)
  }
}

// 分组导航项定义
const navMain = [
  { label: '首页', icon: Home, path: '/' },
  { label: '聚合搜索', icon: Search, path: '/search' },
]

const navMedia = [
  { label: '视频流', icon: Video, path: '/video' },
  { label: '图集画廊', icon: Image, path: '/picture' },
  { label: '小说阅读', icon: BookOpen, path: '/novel' },
]

const navRules = [
  { label: '规则管理', icon: FileBraces, path: '/rules' },
  { label: '规则集市', icon: Store, path: '/market' }
]
</script>

<template>
  <div class="h-screen w-screen overflow-hidden transition-colors duration-300 flex font-sans selection:bg-emerald-600 selection:text-white relative">
    <!-- 极光光斑动效背景 (Aurora Ambient Glow) -->
    <!-- Desktop Left Sidebar (微拟态侧边栏) -->
    <aside
      class="hidden lg:flex flex-col shrink-0 sticky top-0 h-screen p-2.5 justify-between transition-all duration-300 ease-in-out overflow-hidden"
      :class="[
        isCollapsed ? 'w-16' : 'w-50',
        themeStore.isDark
          ? 'bg-[#0a1814]/90 border-white/6 backdrop-blur-xl'
          : 'bg-white/85 border-emerald-100/60 backdrop-blur-xl'
      ]"
    >
      <div class="space-y-5">
        <!-- 品牌 Logo 头部 (固定几何插槽，零位移) -->
        <div class="flex items-center h-11 overflow-hidden">
          <n-tooltip :disabled="!isCollapsed" trigger="hover" placement="right">
            <template #trigger>
              <router-link
                to="/"
                class="flex items-center group w-full h-full min-w-0 overflow-hidden select-none"
              >
                <div class="w-11 h-11 shrink-0 flex items-center justify-center">
                  <div class="w-9 h-9 rounded-xl bg-linear-to-tr from-emerald-600 via-teal-500 to-cyan-500 flex items-center justify-center shadow-lg shadow-emerald-500/25 group-hover:scale-105 transition-transform shrink-0">
                    <Sparkles class="w-5 h-5 text-white animate-pulse" />
                  </div>
                </div>
                <span
                  class="text-lg font-black tracking-tight gradient-flux font-['Plus_Jakarta_Sans','Outfit'] whitespace-nowrap overflow-hidden transition-all duration-300"
                  :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-1.5'"
                >
                  FluxForge
                </span>
              </router-link>
            </template>
            FluxForge 首页
          </n-tooltip>
        </div>

        <!-- 导航组 1：发现检索 -->
        <div class="space-y-1">
          <div
            class="px-3 text-[10px] font-bold uppercase tracking-wider text-zinc-400 dark:text-zinc-500 whitespace-nowrap overflow-hidden transition-all duration-300"
            :class="isCollapsed ? 'max-h-0 opacity-0 mb-0' : 'max-h-6 opacity-100 mb-1'"
          >
            发现检索
          </div>
          <n-tooltip v-for="item in navMain" :key="item.path" :disabled="!isCollapsed" placement="right">
            <template #trigger>
              <router-link
                :to="item.path"
                class="flex items-center w-full h-10 rounded-xl text-xs font-semibold transition-colors relative group overflow-hidden select-none"
                :class="[
                  $route.path === item.path
                    ? (themeStore.isDark ? 'bg-emerald-500/20 text-emerald-300 shadow-xs border border-emerald-500/30' : 'bg-emerald-600 text-white shadow-md shadow-emerald-500/25')
                    : (themeStore.isDark ? 'text-zinc-400 hover:text-white hover:bg-white/6' : 'text-zinc-600 hover:text-zinc-900 hover:bg-emerald-50/60')
                ]"
              >
                <div class="w-11 h-10 shrink-0 flex items-center justify-center">
                  <component :is="item.icon" class="w-4 h-4" />
                </div>
                <span
                  class="whitespace-nowrap overflow-hidden transition-all duration-300 text-xs font-semibold"
                  :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-0.5'"
                >
                  {{ item.label }}
                </span>
                <span
                  v-if="$route.path === item.path"
                  class="absolute left-0 top-2 bottom-2 w-1 rounded-r bg-emerald-500"
                ></span>
              </router-link>
            </template>
            {{ item.label }}
          </n-tooltip>
        </div>

        <!-- 导航组 2：媒体分类 -->
        <div class="space-y-1">
          <div
            class="px-3 text-[10px] font-bold uppercase tracking-wider text-zinc-400 dark:text-zinc-500 whitespace-nowrap overflow-hidden transition-all duration-300"
            :class="isCollapsed ? 'max-h-0 opacity-0 mb-0' : 'max-h-6 opacity-100 mb-1'"
          >
            媒体流
          </div>
          <n-tooltip v-for="item in navMedia" :key="item.path" :disabled="!isCollapsed" placement="right">
            <template #trigger>
              <router-link
                :to="item.path"
                class="flex items-center w-full h-10 rounded-xl text-xs font-semibold transition-colors relative group overflow-hidden select-none"
                :class="[
                  $route.path === item.path
                    ? (themeStore.isDark ? 'bg-emerald-500/20 text-emerald-300 shadow-xs border border-emerald-500/30' : 'bg-emerald-600 text-white shadow-md shadow-emerald-500/25')
                    : (themeStore.isDark ? 'text-zinc-400 hover:text-white hover:bg-white/6' : 'text-zinc-600 hover:text-zinc-900 hover:bg-emerald-50/60')
                ]"
              >
                <div class="w-11 h-10 shrink-0 flex items-center justify-center">
                  <component :is="item.icon" class="w-4 h-4" />
                </div>
                <span
                  class="whitespace-nowrap overflow-hidden transition-all duration-300 text-xs font-semibold"
                  :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-0.5'"
                >
                  {{ item.label }}
                </span>
                <span
                  v-if="$route.path === item.path"
                  class="absolute left-0 top-2 bottom-2 w-1 rounded-r bg-emerald-500"
                ></span>
              </router-link>
            </template>
            {{ item.label }}
          </n-tooltip>
        </div>

        <!-- 导航组 3：规则引擎 -->
        <div class="space-y-1">
          <div
            class="px-3 text-[10px] font-bold uppercase tracking-wider text-zinc-400 dark:text-zinc-500 whitespace-nowrap overflow-hidden transition-all duration-300"
            :class="isCollapsed ? 'max-h-0 opacity-0 mb-0' : 'max-h-6 opacity-100 mb-1'"
          >
            规则引擎
          </div>
          <n-tooltip v-for="item in navRules" :key="item.path" :disabled="!isCollapsed" placement="right">
            <template #trigger>
              <router-link
                :to="item.path"
                class="flex items-center w-full h-10 rounded-xl text-xs font-semibold transition-colors relative group overflow-hidden select-none"
                :class="[
                  (item.path === '/rules' ? ($route.path === '/rules' || $route.path.startsWith('/rules/edit') || $route.path.startsWith('/rules/discovery') || $route.path.startsWith('/rules/detail')) : $route.path === item.path)
                    ? (themeStore.isDark ? 'bg-emerald-500/20 text-emerald-300 shadow-xs border border-emerald-500/30' : 'bg-emerald-600 text-white shadow-md shadow-emerald-500/25')
                    : (themeStore.isDark ? 'text-zinc-400 hover:text-white hover:bg-white/6' : 'text-zinc-600 hover:text-zinc-900 hover:bg-emerald-50/60')
                ]"
              >
                <div class="w-11 h-10 shrink-0 flex items-center justify-center">
                  <component :is="item.icon" class="w-4 h-4" />
                </div>
                <span
                  class="whitespace-nowrap overflow-hidden transition-all duration-300 text-xs font-semibold"
                  :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-0.5'"
                >
                  {{ item.label }}
                </span>
                <span
                  v-if="(item.path === '/rules' ? ($route.path === '/rules' || $route.path.startsWith('/rules/edit') || $route.path.startsWith('/rules/discovery') || $route.path.startsWith('/rules/detail')) : $route.path === item.path)"
                  class="absolute left-0 top-2 bottom-2 w-1 rounded-r bg-emerald-500"
                ></span>
              </router-link>
            </template>
            {{ item.label }}
          </n-tooltip>
        </div>
      </div>

      <!-- 底部控制区（设置、主题切换 & 折叠控制） -->
      <div class="space-y-1 pt-2 border-t border-emerald-100/60 dark:border-white/6">
        <!-- 系统设置 -->
        <n-tooltip :disabled="!isCollapsed" trigger="hover" placement="right">
          <template #trigger>
            <div
              @click="showSettingsModal = true"
              class="flex items-center w-full h-10 rounded-xl text-xs font-semibold cursor-pointer overflow-hidden transition-colors select-none text-zinc-600 dark:text-zinc-300 hover:text-zinc-900 dark:hover:text-white hover:bg-emerald-50/80 dark:hover:bg-white/6"
            >
              <div class="w-11 h-10 shrink-0 flex items-center justify-center">
                <Settings class="w-4 h-4 text-cyan-500" />
              </div>
              <span
                class="whitespace-nowrap overflow-hidden transition-all duration-300 text-xs font-semibold"
                :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-0.5'"
              >
                系统设置
              </span>
            </div>
          </template>
          系统设置 (AI 模型与偏好)
        </n-tooltip>

        <!-- 主题切换行 -->
        <n-tooltip :disabled="!isCollapsed" trigger="hover" placement="right">
          <template #trigger>
            <div
              @click="themeStore.toggleTheme()"
              class="flex items-center w-full h-10 rounded-xl text-xs font-semibold cursor-pointer overflow-hidden transition-colors select-none text-zinc-600 dark:text-zinc-300 hover:text-zinc-900 dark:hover:text-white hover:bg-emerald-50/80 dark:hover:bg-white/[0.06]"
            >
              <div class="w-11 h-10 shrink-0 flex items-center justify-center">
                <Sun v-if="themeStore.isDark" class="w-4 h-4 text-amber-400" />
                <Moon v-else class="w-4 h-4 text-emerald-600" />
              </div>
              <span
                class="whitespace-nowrap overflow-hidden transition-all duration-300 text-xs font-semibold"
                :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-0.5'"
              >
                {{ themeStore.isDark ? '浅色模式' : '深色模式' }}
              </span>
            </div>
          </template>
          切换为{{ themeStore.isDark ? '翠影极光浅色' : '幻夜极光深色' }}主题
        </n-tooltip>

        <!-- 折叠/展开侧边栏 -->
        <n-tooltip :disabled="!isCollapsed" trigger="hover" placement="right">
          <template #trigger>
            <div
              @click="toggleCollapse"
              class="flex items-center w-full h-10 rounded-xl text-xs font-semibold cursor-pointer overflow-hidden transition-colors select-none text-zinc-600 dark:text-zinc-300 hover:text-zinc-900 dark:hover:text-white hover:bg-emerald-50/80 dark:hover:bg-white/[0.06]"
            >
              <div class="w-11 h-10 shrink-0 flex items-center justify-center">
                <ChevronsRight v-if="isCollapsed" class="w-4 h-4" />
                <ChevronsLeft v-else class="w-4 h-4" />
              </div>
              <span
                class="whitespace-nowrap overflow-hidden transition-all duration-300 text-xs font-semibold"
                :class="isCollapsed ? 'opacity-0 max-w-0 pointer-events-none' : 'opacity-100 max-w-xs ml-0.5'"
              >
                {{ isCollapsed ? '展开侧边栏' : '收起侧边栏' }}
              </span>
            </div>
          </template>
          {{ isCollapsed ? '展开侧边栏' : '收起侧边栏' }}
        </n-tooltip>
      </div>
    </aside>

    <!-- Right Main Container -->
    <div class="flex-1 flex flex-col min-w-0 h-full overflow-hidden relative">
      <!-- 顶部固定 Header (Apple Segmented Glass Tab 多标签栏) -->
      <header
        class="sticky top-0 z-20 h-10 sm:h-11 border-b px-2 sm:px-4 flex items-center justify-between min-w-0 select-none backdrop-blur-xl transition-colors duration-200"
        :class="themeStore.isDark ? 'bg-[#0a1814]/80 border-white/6' : 'bg-white/80 border-emerald-100/60'"
      >
        <!-- 移动端 Logo / 站点标识 -->
        <div class="flex items-center gap-1.5 lg:hidden shrink-0 mr-1.5">
          <router-link to="/" class="flex items-center space-x-1.5">
            <div class="w-6 h-6 rounded-lg bg-linear-to-tr from-emerald-600 to-teal-500 flex items-center justify-center shadow-xs">
              <Sparkles class="w-3.5 h-3.5 text-white" />
            </div>
            <span class="text-xs font-black tracking-tight gradient-flux font-['Plus_Jakarta_Sans']">FluxForge</span>
          </router-link>
        </div>

        <!-- 中间可滑动多标签栏 (Segmented Glass Tab 风格) -->
        <div class="flex-1 flex items-center gap-1.5 overflow-x-auto no-scrollbar py-0.5 px-0.5 min-w-0">
          <div
            v-for="tab in tabsStore.tabs.value"
            :key="tab.fullPath"
            @click="handleTabClick(tab.fullPath)"
            class="group relative flex items-center gap-1.5 h-7 px-2.5 rounded-lg text-[11px] font-medium shrink-0 cursor-pointer transition-all duration-150 select-none border"
            :class="tab.fullPath === tabsStore.activeFullPath.value
              ? (themeStore.isDark
                  ? 'bg-emerald-500/25 text-emerald-300 border-emerald-500/40 shadow-xs font-bold'
                  : 'bg-emerald-600 text-white border-emerald-600 shadow-xs font-bold')
              : (themeStore.isDark
                  ? 'bg-white/3 hover:bg-white/8 text-zinc-400 hover:text-zinc-200 border-white/5'
                  : 'bg-emerald-50/60 hover:bg-emerald-100/70 text-zinc-600 hover:text-zinc-900 border-emerald-200/40')"
          >
            <!-- 激活指示微型高亮圆点 -->
            <span v-if="tab.fullPath === tabsStore.activeFullPath.value" class="w-1.5 h-1.5 rounded-full bg-emerald-400 dark:bg-emerald-300 flex-shrink-0 animate-pulse"></span>

            <span class="truncate max-w-[110px] sm:max-w-[150px] inline-block leading-none">
              {{ tab.title }}
            </span>

            <!-- 可关闭 Close 图标按键 -->
            <n-button
              v-if="tab.closable"
              text
              size="tiny"
              @click.stop="handleCloseTab(tab.fullPath)"
              class="rounded p-0.5 text-zinc-400 hover:text-white opacity-60 hover:opacity-100 cursor-pointer"
              title="关闭当前标签"
            >
              <X class="w-2.5 h-2.5" />
            </n-button>
          </div>
        </div>

        <!-- 右侧动作快捷区 (多标签下拉、快捷搜索、主题切换) -->
        <div class="flex items-center gap-1.5 flex-shrink-0 ml-1.5">
          <!-- 标签页操作下拉菜单 -->
          <n-dropdown
            trigger="click"
            :options="[
              { label: '关闭其他标签页', key: 'close-others' },
              { label: '关闭全部标签页', key: 'close-all' }
            ]"
            @select="handleSelectTabOption"
          >
            <n-button
              quaternary
              size="small"
              class="!p-1.5 !rounded-lg text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white"
              title="标签页更多选项"
            >
              <template #icon>
                <MoreHorizontal class="w-3.5 h-3.5" />
              </template>
            </n-button>
          </n-dropdown>

          <!-- 快捷搜索框/按钮 -->
          <router-link
            to="/search"
            class="flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[11px] font-medium bg-emerald-50/80 dark:bg-white/[0.05] text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white border border-emerald-200/50 dark:border-white/[0.06] transition-all shadow-2xs hover:scale-102 active:scale-98"
          >
            <Search class="w-3 h-3 text-emerald-500" />
            <span class="hidden md:inline">全网搜索</span>
          </router-link>

          <!-- 移动端主题切换 -->
          <n-button
            quaternary
            size="small"
            @click="themeStore.toggleTheme()"
            class="lg:hidden !p-1.5 !rounded-lg text-zinc-600 dark:text-zinc-300"
            title="切换主题"
          >
            <template #icon>
              <Sun v-if="themeStore.isDark" class="w-3.5 h-3.5 text-amber-400" />
              <Moon v-else class="w-3.5 h-3.5 text-emerald-600" />
            </template>
          </n-button>
        </div>
      </header>

      <!-- 主视图渲染区 (KeepAlive 缓存容器，全局弹性自适应) -->
      <main class="flex-1 flex flex-col min-h-0 min-w-0 overflow-y-auto p-4 sm:p-5 relative">
        <router-view v-slot="{ Component, route }">
          <transition name="fade-slide" mode="out-in">
            <keep-alive :include="tabsStore.cachedTabNames.value">
              <component
                :is="Component"
                :key="tabsStore.openFullPaths.value.includes(route.fullPath) ? route.fullPath : route.fullPath + '_fresh'"
                class="w-full flex-1 flex flex-col min-h-0"
              />
            </keep-alive>
          </transition>
        </router-view>
      </main>

      <!-- 移动端底部 Tabbar (小屏手机适配) -->
      <nav
        class="lg:hidden sticky bottom-0 z-20 h-14 border-t px-2 flex items-center justify-around select-none backdrop-blur-xl"
        :class="themeStore.isDark ? 'bg-[#08100d]/90 border-white/[0.06]' : 'bg-white/90 border-emerald-100/60'"
      >
        <router-link
          v-for="item in [...navMain, ...navMedia.slice(0, 2), ...navRules]"
          :key="item.path"
          :to="item.path"
          class="flex flex-col items-center justify-center gap-0.5 px-3 py-1 rounded-lg text-[10px] font-semibold transition-all"
          :class="[
            $route.path === item.path
              ? 'text-emerald-600 dark:text-emerald-400 font-bold'
              : 'text-zinc-500 dark:text-zinc-400'
          ]"
        >
          <component :is="item.icon" class="w-4 h-4" />
          <span>{{ item.label }}</span>
        </router-link>
      </nav>
    </div>

    <!-- 全局系统设置模态弹窗 -->
    <SettingsModal v-model:show="showSettingsModal" />
  </div>
</template>

<style scoped>
/* 页面过渡效果 */
.fade-slide-enter-active,
.fade-slide-leave-active {
  transition: all 0.22s cubic-bezier(0.4, 0, 0.2, 1);
}

.fade-slide-enter-from {
  opacity: 0;
  transform: translateY(6px);
}

.fade-slide-leave-to {
  opacity: 0;
  transform: translateY(-6px);
}
</style>