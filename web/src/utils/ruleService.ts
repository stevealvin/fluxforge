import seedRules from './rules_seed.json'
import http from './http'
import type {
  RuleSchema,
  DiscoveryResult,
  SearchResult,
  MediaDetail,
  ParseResult,
  MediaItem,
  MediaType
} from '@/types/rule'

export type { RuleSchema, DiscoveryResult, SearchResult, MediaDetail, ParseResult, MediaItem, MediaType }
export type Rule = RuleSchema

/**
 * 判断规则是否包含 detail 详情解析生命周期方法
 */
export const ruleHasDetail = (rule?: RuleSchema | null): boolean => {
  if (!rule || !rule.code) return false
  return /\bdetail\s*[\(:]/.test(rule.code)
}

const STORAGE_KEY = 'fluxforge-rules'

export const ruleService = {
  /**
   * 初始化规则库
   */
  initRules(): void {
    if (!localStorage.getItem(STORAGE_KEY)) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(seedRules))
    }
  },

  /**
   * 从后端同步最新规则列表
   */
  async syncRemoteRules(): Promise<RuleSchema[]> {
    try {
      const res: any = await http.get('/rules')
      const remoteList = res?.data || []
      if (Array.isArray(remoteList) && remoteList.length > 0) {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(remoteList))
        return remoteList
      }
    } catch (e) {
      console.warn('同步远程规则失败:', e)
    }
    return this.getRules()
  },

  /**
   * 获取所有规则
   */
  getRules(): RuleSchema[] {
    this.initRules()
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    try {
      return JSON.parse(raw) as RuleSchema[]
    } catch {
      return []
    }
  },

  /**
   * 根据 ID 查询单条规则
   */
  getRuleById(id: number | string): RuleSchema | null {
    const rules = this.getRules()
    return rules.find((r) => String(r.id) === String(id)) || null
  },

  /**
   * 根据类型筛选启用的规则
   */
  getEnabledRulesByType(type: MediaType | string): RuleSchema[] {
    const rules = this.getRules()
    return rules.filter((r) => {
      const matchType =
        r.type === type ||
        (type === '视频' && r.type === 'video') ||
        (type === '图片' && r.type === 'picture') ||
        (type === '小说' && r.type === 'novel')
      return matchType && r.enabled === 1
    })
  },

  /**
   * 保存规则 (新增 / 更新)
   */
  saveRule(data: Partial<RuleSchema> & { id?: number | string }): RuleSchema {
    const rules = this.getRules()
    const now = new Date().toISOString()

    let savedRule: RuleSchema

    if (data.id) {
      const idToFind = String(data.id)
      const index = rules.findIndex((r) => String(r.id) === idToFind)

      if (index !== -1) {
        savedRule = {
          ...rules[index],
          ...data,
          id: Number(data.id),
          enabled: data.enabled ? 1 : 0,
          updated_at: now
        }
        rules[index] = savedRule
        localStorage.setItem(STORAGE_KEY, JSON.stringify(rules))
      } else {
        throw new Error(`Rule [ID:${data.id}] not found`)
      }
    } else {
      const nextId = rules.length > 0 ? Math.max(...rules.map((r) => Number(r.id) || 0)) + 1 : 1
      savedRule = {
        id: nextId,
        name: data.name || '',
        type: data.type || 'video',
        version: data.version || '1.0.0',
        author: data.author || '管理员',
        description: data.description || '',
        baseUrl: data.baseUrl || '',
        enabled: data.enabled ? 1 : 0,
        code: data.code || '',
        created_at: now,
        updated_at: now
      }
      rules.push(savedRule)
      localStorage.setItem(STORAGE_KEY, JSON.stringify(rules))
    }

    // 后台同步写入后端
    http.post('/rules', savedRule).catch((err) => {
      console.warn('同步规则至后端失败:', err)
    })

    return savedRule
  },

  /**
   * 删除规则
   */
  deleteRule(id: number | string): boolean {
    const rules = this.getRules()
    const idToFind = String(id)
    const filtered = rules.filter((r) => String(r.id) !== idToFind)

    if (filtered.length < rules.length) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(filtered))
      http.delete(`/rules/${id}`).catch((err) => {
        console.warn('后端删除规则失败:', err)
      })
      return true
    }
    return false
  },

  /**
   * 切换启用状态
   */
  toggleRuleEnabled(id: number | string, enabled: boolean | number): RuleSchema | null {
    const rules = this.getRules()
    const idToFind = String(id)
    const rule = rules.find((r) => String(r.id) === idToFind)

    if (rule) {
      rule.enabled = enabled ? 1 : 0
      rule.updated_at = new Date().toISOString()
      localStorage.setItem(STORAGE_KEY, JSON.stringify(rules))

      http.patch(`/rules/${id}/toggle`, { enabled: rule.enabled }).catch((err) => {
        console.warn('后端更新状态失败:', err)
      })
      return rule
    }
    return null
  },

  /**
   * 重置回官方默认预置规则
   */
  resetToSeedRules(): RuleSchema[] {
    const list: RuleSchema[] = seedRules as RuleSchema[]
    localStorage.setItem(STORAGE_KEY, JSON.stringify(list))

    Promise.all(list.map((r) => http.post('/rules', r))).catch((err) => {
      console.warn('重置预置规则失败:', err)
    })

    return list
  },

  // ==========================================
  // 规则标准沙箱代理执行接口
  // ==========================================

  /**
   * 执行 discovery (发现/分类列表)
   */
  async runDiscovery(rule: RuleSchema, params: { category?: string; page?: number } = {}): Promise<DiscoveryResult> {
    const res: any = await http.post('/rules/execute', {
      ruleId: rule.id,
      code: rule.code,
      action: 'discovery',
      params: {
        category: params.category || '',
        page: params.page || 1,
        baseUrl: rule.baseUrl
      }
    })

    return {
      categories: res?.categories || [],
      items: res?.items || [],
      hasMore: Boolean(res?.hasMore)
    }
  },

  /**
   * 执行 search (搜索)
   */
  async runSearch(rule: RuleSchema, params: { keyword: string; page?: number } = { keyword: '' }): Promise<SearchResult> {
    const res: any = await http.post('/rules/execute', {
      ruleId: rule.id,
      code: rule.code,
      action: 'search',
      params: {
        keyword: params.keyword,
        page: params.page || 1,
        baseUrl: rule.baseUrl
      }
    })

    return {
      items: res?.items || [],
      hasMore: Boolean(res?.hasMore)
    }
  },

  /**
   * 执行 detail (获取媒体详情)
   */
  async runDetail(rule: RuleSchema, params: { key: string; item?: Partial<MediaItem> }): Promise<MediaDetail> {
    const res: any = await http.post('/rules/execute', {
      ruleId: rule.id,
      code: rule.code,
      action: 'detail',
      params: {
        key: params.key,
        item: params.item,
        baseUrl: rule.baseUrl
      }
    })

    return {
      title: res.title,
      cover: res.cover,
      desc: res.desc,
      tags: res.tags || [],
      author: res.author,
      playUrl: res.playUrl,
      images: res.images || [],
      content: res.content,
      headers: res.headers,
      groups: res.groups || [],
      recommendations: res.recommendations || []
    }
  },

  /**
   * 执行 parse (动态解析分集播放直链或小说正文)
   */
  async runParse(rule: RuleSchema, params: { key: string; groupName?: string }): Promise<ParseResult> {
    const res: any = await http.post('/rules/execute', {
      ruleId: rule.id,
      code: rule.code,
      action: 'parse',
      params: {
        key: params.key,
        groupName: params.groupName || '',
        baseUrl: rule.baseUrl
      }
    })

    if (typeof res === 'string') {
      return res.startsWith('http') ? { playUrl: res } : { content: res }
    }

    return {
      playUrl: res?.playUrl || '',
      type: res?.type || rule.type,
      content: res?.content || '',
      headers: res?.headers || {}
    }
  }
}
