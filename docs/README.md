# FluxForge 架构设计与规则契约文档中心

欢迎查阅 FluxForge 跨端生态（Web 工作台、Hono 微服务、Flutter 移动客户端）官方文档库。

---

## 核心文档导引

| 文档名称 | 内容描述 | 适用人群 |
| :--- | :--- | :--- |
| 📖 [**RULE_SPECIFICATION.md**](./RULE_SPECIFICATION.md) | **规则引擎与生命周期契约白皮书**<br>详细说明单代码 `defineRule` 规范、四大生命周期（`discovery`, `search`, `detail`, `parse`）输入输出、`items` 大一统模型、`previews` 与 `related` 设计。 | 规则编写者、AI 规则提示词工程师、前端开发 |
| 🚀 [**APP_TODO.md**](./APP_TODO.md) | **移动端待优化与已知问题清单**<br>汇总已确认存在但尚未处理的技术问题与优化项（阅读器续载熔断提示、规则调试器中断粒度、存量超长文件收敛等），按收益/风险分级并给出候选方案；**结构重构的后续项**（存量超长文件收敛、依赖门禁覆盖面等）亦收敛于其中。 | 移动端开发、产品设计 |
| 📝 [**CHANGELOG.md**](./CHANGELOG.md) | **系统版本更新与演进日志**<br>记录全链路契约收敛、去兼容化改造、重要特性更新与修复明细。 | 全体协作者 |

---

## 核心契约速查

```typescript
// 1. 发现页
async discovery({ tab = '', page = 1 }): Promise<{ tabs?, items: MediaItem[], hasMore? }>

// 2. 搜索页
async search({ keyword, page = 1 }): Promise<{ items: MediaItem[], hasMore? }>

// 3. 详情页 (items 统管剧集/章节/图集)
async detail({ url, item }): Promise<{
  title: string,
  cover?: string,
  desc?: string,
  items?: Array<MediaEpisode | string | { url: string; title?: string }>,
  groups?: MediaGroup[],
  previews?: string[],   // 剧照/截图预览大图
  related?: MediaItem[], // 猜你喜欢/相关推荐
  playUrl?: string,
  content?: string
}>

// 4. 解析器
async parse({ url, groupName }): Promise<{ playUrl?: string, content?: string, headers? }>
```
