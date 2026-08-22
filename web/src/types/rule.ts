/**
 * FluxForge 标准媒体与规则契约模型
 */

export type MediaType = 'video' | 'picture' | 'novel'

export type RuleAction = 'discovery' | 'search' | 'detail' | 'parse'

/**
 * 规则完整配置实体
 */
export interface RuleSchema {
  id: number
  name: string                  // 规则名称 (如: "全面屏超清壁纸", "JAVMENU")
  type: MediaType               // 媒体大类
  version: string               // 语义化版本号
  author: string                // 作者
  description?: string          // 描述
  icon?: string                 // 规则图标/Logo
  baseUrl: string               // 目标站根域名
  enabled: number               // 启用状态 (1 启用, 0 禁用)
  headers?: Record<string, string> // 默认公共请求头
  code: string                  // 规则 ESModule 核心脚本代码
  created_at?: string
  updated_at?: string
}

/**
 * 列表中的基础媒体简项 (用于发现页网格、搜索结果列表、相关推荐等)
 */
export interface MediaItem {
  key: string                   // 媒体唯一标识 / 相对路径 / 详情 URL
  title: string                 // 主标题
  cover?: string                // 封面海报图 URL
  badge?: string                // 标签角标 (如 "4K超清", "完结", "第12集")
  desc?: string                 // 副标题 / 简介 / 更新时间
  date?: string                 // 发布日期 / 上架时间
  tags?: string[]               // 标签分类
  extra?: Record<string, any>   // 附加元数据
}

/**
 * 选集/章节/分集条目
 */
export interface MediaEpisode {
  key: string                   // 选集/章节唯一标识或直链 URL
  title: string                 // 选集/章节标题 (如 "第 01 集", "第 1 章 开篇")
  cover?: string                // 选集封面图 (可选)
  desc?: string                 // 选集简介 (可选)
  extra?: Record<string, any>   // 附加上下文
}

/**
 * 选集/章节分组 (例如: "正片", "预告", "VIP线路1", "卷一")
 */
export interface MediaGroup {
  name: string                  // 分组名称
  items: MediaEpisode[]         // 分组包含的剧集/章节列表
}

/**
 * 通用媒体详情结构 (detail 方法返回的扁平化标准)
 */
export interface MediaDetail {
  title: string                 // 主标题
  cover?: string                // 封面大图
  desc?: string                 // 完整正文剧情介绍/详情描述 (支持换行)
  tags?: string[]               // 分类标签
  author?: string               // 作者 / 演员 / 导演
  rating?: string | number      // 评分

  // 扁平化媒体内容 (直接挂载在顶层)
  playUrl?: string              // 视频播放直链 / M3U8 / MP4
  images?: string[]             // 图集画廊包含的完整大图 URL 列表 / 剧照
  content?: string              // 小说/长文本正文内容
  headers?: Record<string, string> // 播放器/图片需要的请求头 (如 Referer)

  groups?: MediaGroup[]         // 选集 / 章节分组
  recommendations?: MediaItem[] // 相关相似推荐列表
  extra?: Record<string, any>   // 扩展数据
}

/**
 * 发现页返回结果 (discovery 方法返回的数据标准)
 */
export interface DiscoveryResult {
  categories?: string[]         // 支持的子分类/标签选项 (如 ['最新', '热门', '推荐'])
  items: MediaItem[]            // 当前分类下的媒体卡片列表
  hasMore?: boolean             // 是否有下一页
  page?: number                 // 当前页码
}

/**
 * 搜索页返回结果 (search 方法返回的数据标准)
 */
export interface SearchResult {
  items: MediaItem[]            // 搜索结果卡片列表
  hasMore?: boolean             // 是否有更多分页
  total?: number                // 结果总数 (可选)
}

/**
 * 动态分集/直链解析结果 (parse 方法返回的数据标准)
 */
export interface ParseResult {
  playUrl?: string              // 最终解析出的视频/音频播放直链
  type?: MediaType              // 解析内容类型
  content?: string              // 小说章节纯文本正文
  headers?: Record<string, string> // 自定义防盗链请求头
}
