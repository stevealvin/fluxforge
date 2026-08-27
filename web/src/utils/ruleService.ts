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

export const ruleService = {
  /**
   * 从服务端获取全部规则列表
   */
  async getRules(): Promise<RuleSchema[]> {
    try {
      const res: any = await http.get('/rules')
      return res?.data || []
    } catch (e) {
      console.error('获取规则列表失败:', e)
      return []
    }
  },

  /**
   * 根据 ID 从服务端查询单条规则
   */
  async getRuleById(id: number | string): Promise<RuleSchema | null> {
    try {
      const res: any = await http.get(`/rules/${id}`)
      return res || null
    } catch (e) {
      console.error(`获取规则 [ID:${id}] 失败:`, e)
      return null
    }
  },

  /**
   * 根据媒体类型筛选启用的规则
   */
  async getEnabledRulesByType(type: MediaType | string): Promise<RuleSchema[]> {
    const rules = await this.getRules()
    return rules.filter((r) => {
      const matchType =
        r.type === type ||
        (type === '视频' && r.type === 'video') ||
        (type === '图片' && r.type === 'picture') ||
        (type === '小说' && r.type === 'novel')
      return matchType && Number(r.enabled) === 1
    })
  },

  /**
   * 保存规则 (新增 / 更新)
   */
  async saveRule(data: Partial<RuleSchema> & { id?: number | string }): Promise<RuleSchema> {
    const res: any = await http.post('/rules', data)
    return res
  },

  /**
   * 删除规则
   */
  async deleteRule(id: number | string): Promise<boolean> {
    const res: any = await http.delete(`/rules/${id}`)
    return Boolean(res?.success)
  },

  /**
   * 切换启用状态
   */
  async toggleRuleEnabled(id: number | string, enabled: boolean | number): Promise<boolean> {
    const res: any = await http.patch(`/rules/${id}/toggle`, {
      enabled: enabled ? 1 : 0
    })
    return Boolean(res?.success)
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
