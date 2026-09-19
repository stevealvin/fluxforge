# FluxForge 移动端待优化与已知问题清单 (APP_TODO)

> **文档定位**：汇总**已确认存在、但尚未处理**的技术问题与优化项，按「收益 / 风险」分级并给出候选方案。
> 已完成的迭代请查阅 [CHANGELOG.md](./CHANGELOG.md)；产品定位、技术规范与已完成能力请查阅 [APP_DEV_SPEC.md](./APP_DEV_SPEC.md)。
>
> 维护约定：事项处理后请从本文档移除，并在 `CHANGELOG.md` 记录结论。
> （第 2 项以 `✅ 已完成` 保留，作为"处理结论"的备查范例。）

---

## 〇、全量复核结论（2026-09-18）

> 阅读器 / 播放器结构重构完成后，对全部 14 项逐条对照代码复核：**除第 2 项外均仍未完成**。
> 但重构改变了其中若干项的**前置条件与改动面**，实施前请先看下面两列。

| 项 | 复核结论（代码依据） | 重构带来的变化 |
| :--- | :--- | :--- |
| 1 纵向长卷内存无上限 | 仍存在：`_verticalSequence` 只增不减 | `ChapterCache` 的 LRU 已落地，但其保护集合**显式包含 `_verticalSequence`** —— 说明"回收能力已具备，长卷章节是被**刻意保护**的"。因此修复重点不再是"加淘汰"，而是**如何在不破坏滚动位置的前提下释放远端章节**（即方案 B 的近似补偿问题） |
| 2 `_contentCache` 无淘汰 | ✅ 已完成 | 见下文本项 |
| 3 纵向滚动每帧测量 | 仍存在 | 几何测量已隔离在 `_verticalChapterMetrics()`，降频改动面变小 |
| 4 长卷无 `itemExtent` | 仍存在，维持"暂不建议" | 无关 |
| 5 熔断后用户无感知 | 仍存在：`_verticalFailed` 无任何 UI 出口 | 可复用已抽出的 `ReaderErrorView`「重试加载」范式 |
| 6 目录排序不持久化 | 仍存在：`_isCatalogReversed` 仅 `setState`，无写入 | `ReaderPreferences` 已就位（键名 / 取值集中定义），落地只需加一个键 |
| 7 播放期每帧全树重建 | 仍存在：`_onControllerUpdate` 仅 `if (_isSeeking) return` 跳过，播放期仍每帧 `setState` | **改动面显著缩小**：控制栏 / 迷你进度条已抽为独立组件，且控制栏的 `currentPosition` 已是 `ValueGetter`、迷你进度条已订阅 `ValueListenable` —— 只差把播放帧回调改为递增 tick notifier |
| 8 寻道期间仍解码 | 仍存在 | 无关 |
| 9 长按与横拖手势冲突 | 仍存在（两者仍注册在同一 `GestureDetector` 上，竞技场行为未变） | 手势层已独立为 `PlayerGestureLayer`，加短路条件更简单 |
| 10 「已缓存」/「已下载」口径不一致 | ✅ 已完成 | 见下文本项 |
| 11 横向仍用 `SelectableText` | 仍存在 | 横向视图已抽为 `ReaderHorizontalPageView`（162 行），改动面从 1500 行页面缩到单个组件 |
| 12 内存压力主动释放 | 仍存在：全项目无 `didHaveMemoryPressure` | 无关 |
| 13 `enablePlayerGestures` 未生效 | 仍存在：`PlayerPreferences` 中无 `gesturesEnabled` 字段 | 手势层已独立，加字段后只需在组件层短路判断 |
| 14 段落吸附多出一行 | 仍存在（暴露该边界的单测仍为"容忍一行误差"） | 无关 |

---

## 一、小说阅读器（NovelReaderPage）

### 1. 纵向长卷内存无上限 【收益中 / 风险中】

- **现状**：`_verticalSequence` 只增不减（向下追加 + 向上前插），读过的章节正文全部常驻内存。
  正文存于 `_contentCache` 与 `_chapters[i].content` 两处，但**指向同一个不可变 String，不是双份**。
- **量级**：单章 3000 中文字 ≈ 6 KB（Dart String 为 UTF-16）→ 1000 章 ≈ 6 MB。**量级可控，无淘汰策略是隐患**。
- **方案 A（安全）**：仅卸载「当前章**下方**远端」章节 —— 不影响滚动位置，无需补偿偏移。
- **方案 B（完整）**：窗口化（保留当前章前后各 N 章）。卸载**上方**章节会让内容整体上移，
  必须补偿偏移；而视口外章节测不到真实高度，只能用「字数 × 平均字高」**近似补偿**，可能引入小幅跳动。
- **建议**：先观察真机表现；确有卡顿上方案 A，极端场景再考虑方案 B。
- **备注（2026-09-18 更新）**：正文来源已统一为「加载到即已下载」，
  `ChapterCache` 降级为**阅读期内存镜像** —— 淘汰条目不再等于永久丢失，
  只要该章已落盘就能重新读回。这使得方案 A / B 的实现风险进一步降低。
  同时 `content` 双写点已收敛：`_chapters[i].content` 与镜像同步维护的约束依然要遵守。
- **重要更新（同日前一结论已过时）**：长卷已改为 `CustomScrollView.center` 锚点结构
  （见 `CHANGELOG.md`「修复纵向长卷向上加载章节时的顿挫」），
  这使得本项原先的判断需要改写 ——
  1. **方案 B 不再需要「近似补偿」**：锚点之上（向上方向）的布局坐标独立于锚点，
     卸载上方章节**不会**移动当前内容，因此不存在「视口外章节测不到真实高度、
     只能用字数估算补偿」的难题，该方案由「有损近似」变为**无损可行**；
  2. 方案 A / B 的真正收益因此从「阅读位置不跳动」回归到「内存上限」本身，
     实施优先级可维持「先观察真机表现」。

### 2. ~~`_contentCache` 无淘汰策略~~ ✅ 已完成

- 已抽出 `ChapterCache`（访问序 LRU + 保护集合），容量默认 200 章，`<= 0` 表示不限制；
- 淘汰时同步清空 `_chapters[i].content` 以真正释放内存；
- 保护集合覆盖纵向长卷正在渲染的章节、当前章、预取 / 下载中章节，以及**无远程地址的章节**；
- 详见 `CHANGELOG.md`「P2 拆分巨型文件（第五批：会话缓存 ChapterCache + LRU 淘汰）」。

### 3. 纵向滚动同步每帧测量 【收益低 / 风险低】

- **现状**：`_onVerticalScroll` 每帧调用 `_syncVerticalCurrentChapter()`，内部用 `findRenderObject`
  做屏幕中线判定与当前章回写。
- **方案**：降频到每 3~4 帧一次，或改为滚动停止（`ScrollEndNotification`）时精确同步。

### 4. 长卷 `ListView` 无 `itemExtent` 【收益低 / 风险低】

- **现状**：章节高度不一，总高度依赖已布局项估算，序列很长时滚动估算成本上升。
- **说明**：`itemExtent` 不适用（章节高度不同）；彻底解决需自研虚拟滚动，**收益不匹配成本，暂不建议**。

### 5. 章节加载失败熔断后用户无感知 【收益中 / 风险低】

- **现状**：纵向续载失败会写入 `_verticalFailed` 并停止重试，用户只看到内容不再继续，无任何提示。
- **方案**：在长卷顶部 / 底部显示「上一章 / 下一章加载失败，点击重试」，并解除对应熔断标记。

### 6. 目录排序状态不持久化 【收益低 / 风险低】

- **现状**：`_isCatalogReversed` 退出阅读器即恢复正序。
- **方案**：写入 `AppStorage`（与字号 / 行距 / 主题偏好一致的体系）。

---

## 二、视频播放器（AuraPlayer）

### 7. 播放期每帧 `setState` 全树重建 【收益高 / 风险中】★ 最值得做

- **现状**：`_onControllerUpdate` 目前仅在手势寻道（`_isSeeking`）时跳过刷新，
  **正常播放时每帧仍会 `setState(() {})` 重建整棵播放器树**（13 层 Stack）。
- **方案**：
  1. 把「随时间刷新的 UI」（进度条、时间文本、迷你进度条）抽为 `ValueListenableBuilder` 订阅；
  2. 播放回调改为仅递增一个 tick notifier；
  3. 播放 / 暂停 / 缓冲等**状态变化**才触发全树 `setState`；
  4. 进度条 `Slider` 拖动期间同样是每帧 `setState` 整树重建（未复用 seek 手势的
     `_seekPreviewTick` 局部刷新），可在同一轮统一。
- **收益**：播放期重建次数由 ~60 次/秒 降至 0。

### 8. 拖动寻道期间视频仍在解码 【收益中 / 风险中】

- **现状**：左右滑动寻道时视频继续播放与解码，与手势渲染叠加。
- **方案**：寻道期间临时暂停（`_wasPlayingBeforeDrag` 已有记忆，松手自动恢复）。
- **注意**：会改变观感（画面停住），需确认后再做。

### 9. 长按加速与水平拖动的手势冲突 【收益低 / 风险低】

- **现状**：长按加速（500ms）与水平拖动寻道同时注册在同一手势层，长按后若水平移动可能同时响应。
- **方案**：确认手势竞技场优先级，必要时在长按期间屏蔽水平拖动。

---

## 三、全局与体验一致性

### 10. 全屏播放时小屏 AuraPlayer 实例未卸载 【收益中 / 风险低】

- **现状**：全屏是 `Navigator.push` 的独立路由，宿主 `video_detail_view` 未监听
  `onFullScreenChanged`；进入全屏后小屏播放器实例仍留在 widget 树中，且持续监听同一个
  controller —— 每次播放状态变化双份 `setState` + 双份 build（Flutter 只对被遮挡路由
  禁用 ticker，**不**禁用跨路由的 controller 监听回调）。
- **方案**：宿主监听 `onFullScreenChanged`，全屏期间以小占位（封面 / 黑底）替换小屏播放器。
  控制器由宿主托管（`AuraPlayer.controller` 为外部传入），实例 dispose 不会销毁它，
  全屏播放不受影响；退出全屏后重建小屏实例即可（`initState` 会重新接管已就绪的控制器）。
- **注意**：重建后会话级状态（应用内亮度遮罩）与视效选项（fit / 镜像 / 循环）回默认值，
  与「全屏、小屏本就是两个实例」的现状一致，不构成新增回退。

### 11. ~~「已缓存」与「已下载」口径不一致~~ ✅ 已完成

- 已按「缓存即离线」统一为沙盒口径：底部控制栏改名为 `downloadedChapterCount`、
  取值 `pipeline.downloadedCount`、文案「已下载 N 章」，与目录抽屉顶部、下载管理页完全同源；
- 顺带修掉该按钮的三处自相矛盾：图标是 `downloadOutline`、文案却是「已缓存」、
  行为只是内存预取 —— 现在行为改为**真正下载下一章到沙盒**
  （`downloadOffline` 会复用已抓取正文，零额外网络请求），无离线条件时降级为会话内预取；
- 详见 `CHANGELOG.md`「阅读全链路离线优先」。

### 12. 横向分页模式仍使用 `SelectableText` 【收益低 / 风险低】

- **现状**：纵向长卷已改为「外层 `SelectionArea` + 内部 `Text`」，横向每页仍为独立 `SelectableText`。
- **说明**：横向视口内通常仅 1~3 页，成本可控；若需统一，可用 `SelectionArea` 包裹 `PageView`。

### 13. 内存压力主动释放（未实现） 【收益中 / 风险低】

- **方案**：实现 `WidgetsBindingObserver.didHaveMemoryPressure()`，收到系统内存警告时主动清理
  非当前章的内存缓存与预取结果，降低被系统杀进程的概率。

---

## 四、已确认无需处理（避免重复排查）

- **正文不存在双份存储**：`_contentCache[i]` 与 `_chapters[i].content` 指向同一个不可变 String 引用。
- **纵向模式下 `_openAtLastPage` / `_advancingChapter` 恒为 `false`**：二者均为横向分页 / 桥接页专用，无需清理。
- **`SelectionArea` 包裹长卷不影响三区点击热层**：它只注册长按与拖动手势，不拦截单击。
- **`DownloadService.downloadNovelChapter` 已移除**：阅读器统一走「抓取 → `saveNovelChapterContent` 落盘」，
  避免两套单章下载逻辑并存。
- **阅读临时缓存与离线下载职责已分离**：预取只写内存（会话级），跳章 / 手动才落盘，不存在"偷偷变成下载"。
- **`AuraPlayer` 已完成业务解耦**：偏好经 `PlayerPreferences` 注入、变更经回调写出，文件内已无 `appService` 与 `app/di` 引用（ADR D1 落地）。

---

## 五、其它

### 13. 播放手势开关 `enablePlayerGestures` 实际未生效 【收益中 / 风险低】

- **现状**：设置页提供「屏幕滑动手势调节」开关，但 `AuraPlayer` 的手势层
  （垂直调光 / 调音、水平寻道）**从未读取该设置**，关闭后手势依然生效。
- **前置条件已就绪**：播放器现已改为偏好注入（`PlayerPreferences`）。
- **方案**：在 `PlayerPreferences` 增加 `gesturesEnabled` 字段，在 `video_detail_view` 注入时带上该值，
  并在手势层做短路判断。
- **注意**：属**行为变更**（关闭过该开关的用户会立刻感受到差异），需确认后再实施。

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
> 仍然生效的依赖硬约束与 ADR（D1–D4）见 [APP_STRUCTURE_REWORK.md](./APP_STRUCTURE_REWORK.md)。

### 15. `search_page.dart`（328 行）剩余可拆项 【收益低 / 风险低】

- **现状**：已由 **1656 → 328 行**（-80.2%），超出 300 行门禁阈值 **28 行**，暂登记在
  `app/tool/guardrails/baseline.txt` 白名单中。
- **可拆项**：
  1. `build()` 向 `SearchResultsView` 传了 15 个参数，可改为直接注入 `SearchSession`（视图读会话），
     预计再省 8~10 行；
  2. `_hotSuggestions` 常量更适合内聚在 `SearchHistoryPanel`；
  3. `SearchAppBar` 的 11 个入参可合并为少量配置对象。
- **建议**：与第 16 条一并处理，销账后从白名单删除。

### 16. 存量超长 UI 文件仍有 21 个 【收益低 / 风险中】

- **现状**：`app/tool/guardrails/baseline.txt` 白名单中仍有 21 个 UI 文件超过 300 行，
  其中 `novel_reader_page.dart`（1191）、`rules_page.dart`（1046）、`rule_catalog_page.dart`（1031）、
  `aura_player.dart`（1150）为四大头号目标。
- **说明**：白名单是**待销账清单**而非豁免金牌 —— 门禁只拦新增，存量需逐个拆分后手动删行。
- **建议顺序**：`rules_page` → `rule_catalog_page`（两者均为纯列表页，拆分路径与
  `search_page` 完全一致：`engines/` → `widgets/` → 页面收口）。

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
  播放器侧的对应问题（每帧全树重建）见本文件第 7 条。
- **注**：`search_page` 的检索状态（结果集 / 各源状态 / 分页游标）**不在此列** ——
  它不含 `BuildContext` / `GlobalKey` 耦合，已顺利下沉为 `SearchSession extends ChangeNotifier`，
  可作为"什么该抽、什么不该抽"的对照范例。

### 20. 结构重构已完成部分（备查）

- **P0** 六层骨架（`app` / `core` / `domain` / `data` / `shared` / `features`）+ 全量绝对 import ✅
- **P1** 路由参数类型化（`extra` 字典 → 参数类）✅
- **P2** `novel_reader_page.dart` **2193 → 1191 行**（21 个文件）✅；
  `aura_player.dart` **1197 → 1150 行**（13 个视图模块，`_buildLockButton` 已抽出）✅；
  `search_page.dart` **1656 → 328 行**（拆分 11 个文件）✅；
  `rule_tester_page.dart` **1181 → 272 行**（拆分 9 个文件）✅
- **P4** 测试目录按 `test/{unit,widget}/<lib 路径>` 全量镜像，根目录大泥球 `widget_test.dart`
  拆为 12 个文件 ✅
- **P5** CI 门禁落地（`.github/workflows/app-quality.yml` + `tool/guardrails/check_architecture.dart`）✅
- **逻辑审计**：搬运完成后逐项对照 `git HEAD` 核实「逐字一致」，确认无搬运走样
  （`RuleTestStep.reset` / `formatJson` / 日志过滤 / 结果模型 / `_hasMoreCurrent` / `_onScroll` 全部一致）；
  并顺带查出 3 处状态位缺陷（分页标志跨轮次卡死、在途检索未中止、空源判定陷阱），已修复并补测。
- 累计单测：**223 个全部通过**，全程 `flutter analyze` 零问题。
- **视频离线下载**：集成 `ffmpeg_kit_flutter_new`，命令构造抽为纯逻辑可单测，
  Android `minSdk` 抬到 24；**全类型断点续传**（HLS 分片级 / 直链字节级），
  详见 `CHANGELOG.md`（含 GPL 许可证与真机验证提醒）。
- **离线优先闭环**：阅读全链路（当前章加载 / 横向衔接页 / 纵向续载 / 相邻章提前准备 / 手动下载）
  统一为「内存镜像 → 沙盒离线 → 网络」同一优先级，详见 `CHANGELOG.md`。
  该策略落地过程中查出的第 10 项口径不一致已一并销账。
- **「加载到即已下载」语义统一**：取消独立的「会话级内存缓存」概念，
  删除只写内存的 `prefetch`，`ChapterCache` 明确定位为阅读期内存镜像 ——
  只要加载到正文就落盘，退出重进不丢、断网可读。
