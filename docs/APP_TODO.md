# FluxForge 移动端待优化与已知问题清单 (APP_TODO)

> **文档定位**：汇总**已确认存在、但尚未处理**的技术问题与优化项，按「收益 / 风险」分级并给出候选方案。
> 已完成的迭代请查阅 [CHANGELOG.md](./CHANGELOG.md)；移动端功能清单与实现路径请查阅 [app/README.md](../app/README.md)；
> 依赖方向与 UI 文件行数等硬约束由 `app/tool/guardrails/check_architecture.dart` 强制校验。
>
> 维护约定：事项处理后请从本文档移除，并在 `CHANGELOG.md` 记录结论。
> 条目编号与章节编号均仅作**稳定标识**使用，删除后**不顺延**（避免破坏文内交叉引用），
> 因此编号可能不连续：某一节的条目全部处理完毕后会整节移除，出现章节号跳跃属正常。

---

## 一、小说阅读器（NovelReaderPage）

### 5. 章节加载失败熔断后用户无感知 【收益中 / 风险低】

- **现状**：纵向续载失败会写入 `_verticalFailed` 并停止重试，用户只看到内容不再继续，无任何提示。
- **方案**：在长卷顶部 / 底部显示「上一章 / 下一章加载失败，点击重试」，并解除对应熔断标记。

---

## 五、其它

### 14. 段落自然吸附可能使单页高度多出一行 【收益低 / 风险中】

- **现状**：分页引擎的「段落自然吸附」在断点恰好是换行符时，会在换行符之后多带 1 个字符，
  使该页高度可能超出可用高度至多一行（表现为极少数页面略微拥挤）。
- **发现方式**：抽出 `PaginationEngine` 后新增的单测
  （`每页高度不超过可用高度（段落吸附最多容忍一行误差）`）暴露了该边界。
- **方案**：吸附后重新用 `TextPainter` 校验高度，若溢出则回退到未吸附的切分点。
- **注意**：会改变既有分页结果，进而影响阅读位置还原（`_restoreReadingPosition`）；
  建议与「分页结果缓存」一并评估后再改。

---

## 六、结构重构剩余工作

> 原《目录结构重构设计方案》的阶段执行表已随重构完成而删除，**未完成部分统一收敛到本节**；
> 硬约束（分层依赖方向、UI 文件行数上限）由 `app/tool/guardrails/check_architecture.dart` 强制校验。

### 16. 存量超长 UI 文件仍有 21 个 【收益低 / 风险中】

- **现状**：`app/tool/guardrails/baseline.txt` 白名单中仍有 **21 个** UI 文件超过 300 行，
  最大四个为 `novel_reader_page.dart`（1626）、`aura_player.dart`（1276）、
  `video_detail_view.dart`（1095）、`rule_catalog_page.dart`（1093）。
- **行数口径**：一律按门禁算法统计（`check_architecture.dart` 的
  `LineSplitter().convert(source).length`，**含空行**），与 300 行阈值同源。
  误用「非空行」口径会低估 20~40 行、结论可能反过来 ——
  例如 `search_page.dart` 总行 322（超标），而非空行仅 286（会被误判为"合规"）。
- **说明**：白名单是**待销账清单**而非豁免金牌 —— 门禁只拦新增，存量需逐个拆分后手动删行；
  文件降到 300 行内时，门禁会自动打印「已销账，建议移除」提示。当前 21 个**无一**达线。
- **销账顺序**：先挑**超限幅度最小**的，性价比最高 —— `search_page`（322 / +22）、
  `media_meta_header`（336 / +36）、`market_page`（347 / +47）；
  大文件留作后续批次（`rules_page` / `rule_catalog_page` 均为纯列表页，拆分路径与
  `search_page` 一致：`engines/` → `widgets/` → 页面收口）。
- **覆盖面盲区（待决策）**：行数上限只作用于「**UI 文件**」—— `_isUiFile` 的判据是
  「路径含 `pages/` `widgets/` `views/`，或源码定义了 `Widget`」，因此
  `engines/` / `controllers/` / `data/` / `core/` 下的文件**完全不受行数约束**。
  实测 `lib/` 下 >300 行却不在白名单的还有 **6 个**：
  `data/download/download_service.dart`（**1354**，全仓第二大文件，已超过 `aura_player`）、
  `core/sandbox/rule_engine.dart`（1001）、`features/browser/engine/adblock_engine.dart`（949）、
  `features/browser/engine/web_video_gesture_engine.dart`（587）、
  `data/library/play_history_service.dart`（322）、
  `features/rules/controllers/rule_test_pipeline.dart`（318）。
  **二选一**：① 把上限扩展到引擎 / 服务层（会一次性新增 6 条违规，需登记白名单后排队拆分）；
  ② 把「非 UI 文件不限行数」写进架构约定（现状是隐式边界，非明示决策）。

### 17. 依赖方向门禁只覆盖了 `shared → features` 【收益低 / 风险低】

- **现状**：`tool/guardrails/check_architecture.dart` 已校验
  `domain/` 零 Flutter 依赖、`shared/` 不反向依赖 `features/`、UI 文件行数上限；
  但 **`features/A` 不 import `features/B`** 尚未纳入（需要先定义"允许的横向依赖白名单"，
  例如 `media/*` 之间共享 `media/shared`、`search` 依赖 `media` 等既有事实）。
- **建议**：先跑一次全量 import 关系导出，确认合法横向依赖清单后再加规则，
  否则会误伤现存的 `features/search → features/media` 这类合理引用。

### 18. 规则调试器的日志过滤与中断粒度偏粗 【收益低 / 风险低】

- **日志过滤**：`RuleTestConsolePanel` 的 `logs` 由页面每次 `build` 调 `_getFilteredLogs()` 现算，
  内部要全量遍历 `AppLogger.getLogs()`。日志量大时每次重建都是 O(n) 扫描（原实现即如此）。
  **建议**：把过滤结果缓存到 State，仅在 `logsNotifier` 触发时重算。
- **流水线中断粒度**：`RuleTestPipeline.cancel()` 只在**阶段边界**检查 `_isCancelled`，
  阶段内部的 `await RuleEngine.xxx()` 无法打断。页面 `dispose()` 后当前阶段仍会跑完
  （数据写入已卸载 State 的 `_steps`，不会崩溃，但会白跑一次沙箱）。
  **建议**：若要严格可中断，需把 `RuleEngine` 的调用改为可取消（如传入 `Completer` / 轮次校验）。
- **完成度的两套等价表达**：顶部 `LinearProgressIndicator` 用 `SearchAggregator.finishedRatio`，
  而 `SearchPendingView` 用 `length - searchingCount` 自算。两者分子相同、结果一致，
  但重复表达了同一概念，**建议**统一走 `finishedRatio`。

### 19. 结构重构的后续阶段（P3 决策记录）

- **P3 · 状态层 —— 经评估后决定不做（部分）**：阅读器剩余的状态编排（分页状态机、切章导航、
  纵向滚动几何测量）紧耦合 `setState` / `BuildContext` / `GlobalKey`，
  强行抽成 `reader_controller` 只会把这两者一起搬走，**收益为负**，故保留为页面职责。
  播放器侧的对应问题（每帧全树重建）**已实现**，见 [CHANGELOG.md](./CHANGELOG.md)
  的「AuraPlayer 播放期消除每帧整树重建」。
- **注**：`search_page` 的检索状态（结果集 / 各源状态 / 分页游标）**不在此列** ——
  它不含 `BuildContext` / `GlobalKey` 耦合，已顺利下沉为 `SearchSession extends ChangeNotifier`，
  可作为"什么该抽、什么不该抽"的对照范例。


