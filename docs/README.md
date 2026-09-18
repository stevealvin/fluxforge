# FluxForge 架构设计与规则契约文档中心

欢迎查阅 FluxForge 跨端生态（Web 工作台、Hono 微服务、Flutter 移动客户端）官方文档库。

---

## 核心文档导引

| 文档名称 | 内容描述 | 适用人群 |
| :--- | :--- | :--- |
| 📖 [**RULE_SPECIFICATION.md**](./RULE_SPECIFICATION.md) | **规则引擎与生命周期契约白皮书**<br>详细说明单代码 `defineRule` 规范、四大生命周期（`discovery`, `search`, `detail`, `parse`）输入输出、`items` 大一统模型、`previews` 与 `related` 设计。 | 规则编写者、AI 规则提示词工程师、前端开发 |
| 🏗️ [**SYSTEM_ARCHITECTURE.md**](./SYSTEM_ARCHITECTURE.md) | **跨端系统架构与多端设计规范**<br>系统工程拓扑架构、多端数据流、Flutter 客户端 `AppCard` 质感设计哲学、主题色彩系统、移动端本地 JS 沙箱运行机制与 API 规范。 | 客户端开发、服务端架构师、全栈工程师 |
| 🚀 [**APP_TODO.md**](./APP_TODO.md) | **移动端待优化与已知问题清单**<br>汇总已确认存在但尚未处理的技术问题与优化项（阅读器长卷内存、播放器帧重建、口径一致性等），按收益/风险分级并给出候选方案与已确认无需处理的结论；**第六节为结构重构的剩余工作**（`aura_player` 收尾、`search_page` / `rule_tester_page` 拆分、P4 测试对齐、P5 CI 门禁）。 | 移动端开发、产品设计 |
| 🧱 [**APP_STRUCTURE_REWORK.md**](./APP_STRUCTURE_REWORK.md) | **移动端架构约束与决策记录**<br>仍然生效的分层依赖方向硬约束、feature 内部目录约定、明确不做的事，以及 4 项架构决策记录（ADR D1–D4）。原重构方案的阶段性内容（诊断、迁移映射、拆分进度）已随执行完成删除，未完成工作见 `APP_TODO` 第六节。 | 移动端开发、架构设计 |
| 🛠️ [**APP_DEV_SPEC.md**](./APP_DEV_SPEC.md) | **移动端核心功能技术开发与落地规范 (一体化说明书)**<br>采用 1234 扁平大一统架构，定死依赖底座（弃用 Chewie，基于原生 video_player）、自研 FluxPlayer 全功能规格、阅读器、测速、备份等技术接口与交互细节。 | 移动端开发、AI 编程助手 |
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
