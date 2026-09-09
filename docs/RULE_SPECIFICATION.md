# FluxForge 统一规则引擎与生命周期标准规范

> 版本：v2.0 (全链路去兼容化与契约收敛统一版)  
> 状态：现行强制标准  
> 适用端：Web 规则工作台 / Server 执行沙箱 / Flutter 移动客户端

---

## 目录
- [一、 规则核心哲学与单代码原则](#一-规则核心哲学与单代码原则)
- [二、 运行时沙箱环境与全局注入](#二-运行时沙箱环境与全局注入)
- [三、 规则结构定义 (`defineRule`)](#三-规则结构定义-definerule)
- [四、 四大生命周期契约详解](#四-四大生命周期契约详解)
  - [4.1 `discovery` (发现与页签列表)](#41-discovery-发现与页签列表)
  - [4.2 `search` (全局搜索检索)](#42-search-全局搜索检索)
  - [4.3 `detail` (媒体详情与子资源聚合)](#43-detail-媒体详情与子资源聚合)
  - [4.4 `parse` (直链嗅探与正文解析)](#44-parse-直链嗅探与正文解析)
- [五、 统一数据模型契约 (TypeScript Schemas)](#五-统一数据模型契约-typescript-schemas)
  - [5.1 `MediaItem` (基础媒体卡片条目)](#51-mediaitem-基础媒体卡片条目)
  - [5.2 `MediaEpisode` (子选集/章节条目)](#52-mediaepisode-子选集章节条目)
  - [5.3 `MediaGroup` (多线路/分卷分组)](#53-mediagroup-多线路分卷分组)
  - [5.4 `MediaDetail` (统一详情模型)](#54-mediadetail-统一详情模型)
  - [5.5 `ParseResult` (解析结果)](#55-parseresult-解析结果)
- [六、 核心字段收敛与设计原则](#六-核心字段收敛与设计原则)
  - [6.1 全类型大一统字段：`items`](#61-全类型大一统字段items)
  - [6.2 预览图流与推荐流解耦：`previews` & `related`](#62-预览图流与推荐流解耦previews--related)
  - [6.3 统一跳转标识：全网统一为 `url`](#63-统一跳转标识全网统一为-url)
- [七、 完整标准规则模板 (Reference Template)](#七-完整标准规则模板-reference-template)

---

## 一、 规则核心哲学与单代码原则

FluxForge 的规则系统致力于将互联网上异构的多媒体内容源（影视、相册/图集、小说/漫画）映射为统一的数据流。为了解决早期规则片段割裂、上下文难以复用、AI 生成出错率高的问题，系统确立了以下核心原则：

1. **单脚本原则 (Single Code Principle)**：
   - 每个站点源有且仅有一份完整的 JavaScript 核心代码。
   - 所有数据抓取、HTML 解析、加密解密工具函数均在同一上下文内定义，极大提升复用度。
2. **三位一体对称性 (Tri-Unity Symmetry)**：
   - 列表流 (`discovery.items`) $\rightarrow$ 搜索流 (`search.items`) $\rightarrow$ 详情子资源 (`detail.items`) 全部收敛于 `items` 概念。
3. **零冗余、去兼容化 (Zero Redundancy)**：
   - 剔除历史废弃字段（如 `list`、`images`、`photos`、`episodes`、`chapters`、`recommendations`）。
   - 杜绝多余别名（严禁使用 `src`、`href`、`key`、`path`，全局统一使用 `url`）。

---

## 二、 运行时沙箱环境与全局注入

无论脚本运行在服务端的 Node VM 沙箱，还是移动端基于 JavaScriptCore / QuickJS 的轻量沙箱，沙箱环境均预先注入以下全局变量与工具：

| 全局标识 | 类型 | 说明与典型用途 |
| :--- | :--- | :--- |
| **`baseUrl`** | `string` | 目标站点根域名（如 `https://example.com`），用于相对路径补全 |
| **`axios`** | `AxiosInstance` | 预置防爬请求头与 Cookie 容器的高性能 HTTP 客户端 |
| **`cheerio`** | `CheerioAPI` | 服务端轻量高性能 HTML DOM 解析器（语法同 jQuery） |
| **`ua`** | `string` | 标准 Modern Mobile / Desktop User-Agent 字符串 |
| **`defineRule`** | `Function` | 规则定义与类型辅助函数，用于包装导出规则对象 |

> 规则脚本内部**严禁编写任何 `import` 或 `require` 语句**，直接使用注入的全局对象即可。

---

## 三、 规则结构定义 (`defineRule`)

所有规则采用统一的标准 ESModule 导出范式：

```javascript
export default defineRule({
  async discovery({ tab = '', page = 1 }) {
    // 发现列表
  },
  async search({ keyword, page = 1 }) {
    // 搜索列表
  },
  async detail({ url, item }) {
    // 详情及选集/子资源
  },
  async parse({ url, groupName }) {
    // 直链/正文解析
  }
})
```

---

## 四、 四大生命周期契约详解

### 4.1 `discovery` (发现与页签列表)
- **触发时机**：进入分类浏览、首屏信息流、切换分类标签页或下拉加载更多时触发。
- **入参**：
  ```typescript
  {
    tab?: string;  // 当前选中的页签标识或分类相对 URL (默认为 '')
    page?: number; // 当前分页页码，从 1 开始计数 (默认为 1)
  }
  ```
- **返回值规范**：
  ```typescript
  interface DiscoveryResult {
    tabs?: Array<{ title: string; url?: string }> | string[]; // 分类页签列表
    items: MediaItem[]; // 当前分类/页码下的媒体卡片列表
    hasMore?: boolean;  // 是否有下一页
    page?: number;      // 当前返回的页码
  }
  ```

---

### 4.2 `search` (全局搜索检索)
- **触发时机**：用户在全局搜索框输入关键字并发起检索时触发。
- **入参**：
  ```typescript
  {
    keyword: string; // 用户检索词 (必填)
    page?: number;   // 分页页码 (默认为 1)
  }
  ```
- **返回值规范**：
  ```typescript
  interface SearchResult {
    items: MediaItem[]; // 搜索结果卡片列表 (与 discovery 卡片完全复用)
    hasMore?: boolean;  // 是否有下一页
    total?: number;     // 结果总数 (可选)
  }
  ```

---

### 4.3 `detail` (媒体详情与子资源聚合)
- **触发时机**：点击任意媒体卡片进入详情页时触发。
- **入参**：
  ```typescript
  {
    url: string;                  // 媒体详情页相对路径或完整 URL
    item?: Partial<MediaItem>;    // 从上一级卡片带来的预热上下文 (封面、标题等)
  }
  ```
- **返回值规范**：
  ```typescript
  interface MediaDetail {
    title: string;                 // 媒体主标题
    cover?: string;                // 高清封面大图
    desc?: string;                 // 详情剧情简介 / 正文描述 (支持换行)
    tags?: string[];               // 分类标签数组
    author?: string;               // 作者 / 演员 / 导演
    rating?: string | number;      // 评分 (如 "9.2")

    // 核心消费条目 (视频选集、小说章节、图集原图统一由此承载)
    items?: Array<MediaEpisode | string | { url: string; title?: string }>;
    
    // 多播放线路 / 分卷多线路 (可选)
    groups?: MediaGroup[];

    // 辅助视觉预览与关联推荐流
    previews?: string[];           // 剧照 / 截帧 / 插图预览大图数组
    related?: MediaItem[];         // 猜你喜欢 / 相似作品 / 关联条目列表

    // 直出内容 (若无需 parse 阶段时直接提供)
    playUrl?: string;              // 视频播放直链 (MP4 / M3U8)
    content?: string;              // 小说/文章单篇完整正文
    headers?: Record<string, string>; // 播放器或图片加载所需 Header (如 Referer)
    extra?: Record<string, any>;   // 扩展元数据
  }
  ```

---

### 4.4 `parse` (直链嗅探与正文解析)
- **触发时机**：点击视频选集按钮播放、或点击小说章节阅读时，如果条目的 `url` 为页面跳转链接而非视频直链/正文文本时触发。
- **入参**：
  ```typescript
  {
    url: string;        // 当前选中选集/章节的资源地址
    groupName?: string; // 选集所在线路/分组名称 (如 "4K极速线路")
  }
  ```
- **返回值规范**：
  ```typescript
  interface ParseResult {
    playUrl?: string;                 // 解析出的最终音视频播放直链 (mp4, m3u8 等)
    content?: string;                 // 解析出的小说/长文章纯正文内容
    headers?: Record<string, string>; // 专用的防盗链 Header
    format?: string;                  // 视频封装格式 (可选)
    extra?: Record<string, any>;      // 扩展数据
  }
  ```

---

## 五、 统一数据模型契约 (TypeScript Schemas)

```typescript
/**
 * 基础媒体简项 (用于发现网格、搜索列表、相关推荐)
 */
export interface MediaItem {
  url: string;                   // 详情页相对路径或完整 URL (核心跳转标识)
  title: string;                 // 主标题
  cover?: string;                // 封面海报图 URL
  badge?: string;                // 角标 (如 "4K超清", "完结", "第12集")
  desc?: string;                 // 副标题 / 简要描述 / 更新状态
  date?: string;                 // 上架时间 / 发布日期
  tags?: string[];               // 题材标签
  extra?: Record<string, any>;   // 附加元数据
}

/**
 * 选集/章节条目
 */
export interface MediaEpisode {
  url: string;                   // 目标播放页/章节阅读 URL
  title?: string;                // 标题 (如 "第01集", "第一章 破晓")
  desc?: string;                 // 选集简要介绍
  extra?: Record<string, any>;   // 附加上下文
}

/**
 * 选集/章节分组 (线路、分卷)
 */
export interface MediaGroup {
  name: string;                  // 分组/线路名称 (如 "极速播放源", "第一卷")
  items: MediaEpisode[];         // 分组包含的条目列表
}
```

---

## 六、 核心字段收敛与设计原则

### 6.1 全类型大一统字段：`items`
- **视频源**：`items` 为选集列表，每一项为 `{ title: '第01集', url: '/play-1' }`；
- **图集源**：`items` 为高清大图列表，每一项为 `{ url: 'https://.../1.jpg' }` 或纯链接字符串数组 `['https://.../1.jpg', ...]`；
- **小说源**：`items` 为章节目录，每一项为 `{ title: '第1章', url: '/chapter-1' }`。
> **去冗余原则**：在 `items` 中，严禁定义内嵌的 `cover`。对于图集类型，大图直接使用核心属性 `url` 表达，避免字段冗余。

### 6.2 预览图流与推荐流解耦：`previews` & `related`
- **`previews?: string[]`**：
  - **定位**：纯展示用途的视觉大图流（如影视的“剧照/截帧”、小说的“人物立绘/插画彩页”、App的“截屏”）。
  - **结构**：纯图片 URL 字符串数组，极简紧凑。
  - **交互**：客户端渲染为横向滑动视口，点击支持全屏 Lightbox 放大画廊浏览。
- **`related?: MediaItem[]`**：
  - **定位**：详情页底部的关联合集、同作者作品、同题材相似推荐。
  - **结构**：完全复用 `MediaItem`，与首页流保持 100% 一致。
  - **交互**：点击推荐卡片直接跳转进入下一个媒体详情页。

### 6.3 统一跳转标识：全网统一为 `url`
全局严禁出现 `path`、`href`、`src`、`key` 等任何形式的历史别名。所有能够代表跳转定位的属性全部统一命名为 **`url`**。

---

## 七、 完整标准规则模板 (Reference Template)

```javascript
export default defineRule({
  // 1. 发现列表
  async discovery({ tab = '', page = 1 }) {
    const targetUrl = tab ? `${baseUrl}${tab}?page=${page}` : `${baseUrl}/latest?page=${page}`;
    const res = await axios.get(targetUrl, { headers: { 'User-Agent': ua } });
    const $ = cheerio.load(res.data);

    const items = [];
    $('.media-card').each((_, el) => {
      items.push({
        title: $(el).find('.title').text().trim(),
        url: $(el).find('a').attr('href') || '',
        cover: $(el).find('img').attr('src') || '',
        badge: $(el).find('.badge').text().trim(),
        desc: $(el).find('.desc').text().trim()
      });
    });

    return {
      tabs: [
        { title: '热播榜', url: '/hot' },
        { title: '最新上架', url: '/latest' }
      ],
      items,
      hasMore: items.length >= 20
    };
  },

  // 2. 搜索列表
  async search({ keyword, page = 1 }) {
    const res = await axios.get(`${baseUrl}/search?wd=${encodeURIComponent(keyword)}&p=${page}`);
    const $ = cheerio.load(res.data);

    const items = [];
    $('.search-item').each((_, el) => {
      items.push({
        title: $(el).find('.name').text().trim(),
        url: $(el).find('a').attr('href') || '',
        cover: $(el).find('img').attr('src') || '',
        desc: $(el).find('.status').text().trim()
      });
    });

    return {
      items,
      hasMore: false
    };
  },

  // 3. 详情信息与子资源
  async detail({ url, item }) {
    const detailUrl = url.startsWith('http') ? url : `${baseUrl}${url}`;
    const res = await axios.get(detailUrl);
    const $ = cheerio.load(res.data);

    // 提取选集列表 (视频模式)
    const items = [];
    $('.episode-list a').each((i, el) => {
      items.push({
        title: $(el).text().trim() || `第 ${i + 1} 集`,
        url: $(el).attr('href') || ''
      });
    });

    // 提取剧照预览图
    const previews = [];
    $('.stills-gallery img').each((_, el) => {
      const src = $(el).attr('src');
      if (src) previews.push(src);
    });

    // 提取相关推荐作品
    const related = [];
    $('.recommend-list .item').each((_, el) => {
      related.push({
        title: $(el).find('.title').text().trim(),
        url: $(el).find('a').attr('href') || '',
        cover: $(el).find('img').attr('src') || ''
      });
    });

    return {
      title: $('.media-title').text().trim() || item?.title || '',
      cover: $('.media-poster img').attr('src') || item?.cover || '',
      desc: $('.media-summary').text().trim(),
      tags: $('.media-tags span').map((_, el) => $(el).text().trim()).get(),
      author: $('.director').text().trim(),
      rating: $('.score').text().trim(),
      items,
      previews,
      related
    };
  },

  // 4. 直链解析或正文提取
  async parse({ url, groupName }) {
    const playPageUrl = url.startsWith('http') ? url : `${baseUrl}${url}`;
    const res = await axios.get(playPageUrl);
    
    // 正则提取内嵌播放器直链
    const match = res.data.match(/var\s+player_data\s*=\s*\{.*?"url":"([^"]+)".*?\}/);
    const playUrl = match ? match[1] : playPageUrl;

    return {
      playUrl,
      headers: {
        'Referer': baseUrl,
        'User-Agent': ua
      }
    };
  }
});
```
