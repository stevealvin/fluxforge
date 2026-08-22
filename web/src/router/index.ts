import { createRouter, createWebHistory } from 'vue-router'
import type { RouteRecordRaw } from 'vue-router'

const routes: RouteRecordRaw[] = [
  // 1. 首页 / 仪表盘
  {
    path: '/',
    component: () => import('../views/home.vue')
  },
  {
    path: '/gallery',
    component: () => import('../views/gallery.vue')
  },

  // 2. 规则管理与开发中心 (Rules Hub)
  {
    path: '/rules',
    component: () => import('../views/rules/index.vue')
  },
  {
    path: '/rules/edit',
    component: () => import('../views/rules/edit.vue')
  },

  // 3. 规则生态集市 (Market Hub)
  {
    path: '/market',
    component: () => import('../views/market/index.vue')
  },
  {
    path: '/rules/market',
    redirect: '/market'
  },

  // 4. 多媒体消费流中心 (Media Hub)
  {
    path: '/video',
    component: () => import('../views/media/index.vue'),
    props: { type: '视频' }
  },
  {
    path: '/picture',
    component: () => import('../views/media/index.vue'),
    props: { type: '图片' }
  },
  {
    path: '/novel',
    component: () => import('../views/media/index.vue'),
    props: { type: '小说' }
  },
  {
    path: '/media/detail',
    component: () => import('../views/media/detail.vue')
  },
  {
    path: '/rules/detail',
    redirect: (to) => ({ path: '/media/detail', query: to.query })
  },

  // 5. 全网聚合搜索
  {
    path: '/search',
    component: () => import('../views/search.vue')
  }
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes
})

export default router
