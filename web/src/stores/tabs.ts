import { ref, computed } from 'vue'
import type { RouteLocationNormalized } from 'vue-router'

export interface TabItem {
  fullPath: string
  path: string
  title: string
  name: string
  closable: boolean
}

const tabs = ref<TabItem[]>([
  {
    fullPath: '/',
    path: '/',
    title: '首页探索',
    name: 'HomeView',
    closable: false,
  },
])

const activeFullPath = ref<string>('/')

const openFullPaths = computed(() => {
  return tabs.value.map((t) => t.fullPath)
})

const cachedTabNames = computed(() => {
  return Array.from(new Set(tabs.value.map((t) => t.name).filter(Boolean)))
})

// 中文路径与标题映射表
const pathTitleMap: Record<string, string> = {
  '/': '首页探索',
  '/search': '聚合搜索',
  '/video': '视频流',
  '/picture': '图集画廊',
  '/novel': '小说书库',
  '/rules': '规则管理',
  '/market': '规则集市',
  '/rules/market': '规则集市',
  '/rules/edit': '规则编辑',
  '/media/detail': '媒体详情',
  '/rules/detail': '媒体详情'
}

// 路径与组件 Name 映射表
const nameMap: Record<string, string> = {
  '/': 'HomeView',
  '/search': 'SearchView',
  '/video': 'MediaDiscoveryView',
  '/picture': 'MediaDiscoveryView',
  '/novel': 'MediaDiscoveryView',
  '/rules': 'RulesView',
  '/market': 'MarketView',
  '/rules/market': 'MarketView',
  '/rules/edit': 'EditView',
  '/media/detail': 'MediaDetailHub',
  '/rules/detail': 'MediaDetailHub'
}

function addTab(route: RouteLocationNormalized) {
  if (!route.path || route.path === '/:pathMatch(.*)*') return

  const fullPath = route.fullPath
  activeFullPath.value = fullPath

  // 格式化标签标题
  let title = (route.meta?.title as string) || ''
  title = title.replace(' - FluxForge', '').replace(' - FluxView', '').trim()

  if (route.query.q) {
    title = `搜索: ${route.query.q}`
  } else if (route.query.title) {
    title = `${route.query.title}`
  } else if (route.path === '/rules/edit') {
    title = route.query.id ? '编辑规则' : '新建规则'
  } else if (route.path === '/rules/discovery') {
    title = '规则发现'
  }

  if (!title) {
    title = pathTitleMap[route.path] || route.path.split('/').filter(Boolean).pop() || '新标签'
  }

  const compName = nameMap[route.path] || ''

  const existingIndex = tabs.value.findIndex((t) => t.fullPath === fullPath)
  if (existingIndex !== -1) {
    tabs.value[existingIndex].title = title
    return
  }

  tabs.value.push({
    fullPath,
    path: route.path,
    title,
    name: compName,
    closable: route.path !== '/',
  })
}

function closeTab(targetFullPath: string): string | null {
  const index = tabs.value.findIndex((t) => t.fullPath === targetFullPath)
  if (index === -1) return null

  const targetTab = tabs.value[index]
  if (!targetTab.closable) return null

  tabs.value.splice(index, 1)

  if (activeFullPath.value === targetFullPath) {
    const nextTab = tabs.value[index] || tabs.value[index - 1] || tabs.value[0]
    if (nextTab) {
      activeFullPath.value = nextTab.fullPath
      return nextTab.fullPath
    }
  }
  return null
}

function closeOtherTabs(targetFullPath: string) {
  tabs.value = tabs.value.filter((t) => !t.closable || t.fullPath === targetFullPath)
  activeFullPath.value = targetFullPath
}

function closeAllTabs(): string {
  tabs.value = tabs.value.filter((t) => !t.closable)
  activeFullPath.value = '/'
  return '/'
}

export function useTabsStore() {
  return {
    tabs,
    activeFullPath,
    openFullPaths,
    cachedTabNames,
    addTab,
    closeTab,
    closeOtherTabs,
    closeAllTabs,
  }
}
