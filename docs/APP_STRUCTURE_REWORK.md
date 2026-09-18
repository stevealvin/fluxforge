# FluxForge 移动端架构约束与决策记录

> **文档定位**：本文档记录**仍然生效**的架构硬约束与设计决策（ADR）。
>
> 原《目录结构重构设计方案》中的「现状诊断 / 文件迁移映射 / 巨型文件拆分进度 / 迁移阶段表」
> 等**阶段性内容已随重构完成而删除** —— 执行过程见 [CHANGELOG.md](./CHANGELOG.md)，
> **尚未完成的收尾工作见 [APP_TODO.md](./APP_TODO.md) 第六节**。
>
> 实际目录结构以 `lib/` 为准，此处不再维护目录树快照（快照必然过期，是上一版文档失效的主因）。

---

## 一、分层与依赖方向（硬约束）

```
       ┌──────────────────────────────────────────────┐
       │  app/        装配层（入口、路由、DI、主题）      │
       └──────────────────────────────────────────────┘
                          │ 可依赖一切
       ┌──────────────────────────────────────────────┐
       │  features/   业务功能（页面 + 控制器 + 局部组件）│
       └──────────────────────────────────────────────┘
              │ 可依赖          │ 可依赖         │ 可依赖
       ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
       │  data/       │  │  shared/     │  │  core/       │
       │  数据访问     │  │  跨功能 UI    │  │  技术基建     │
       └──────────────┘  └──────────────┘  └──────────────┘
              │ 可依赖          │ 可依赖
       ┌──────────────────────────────────────────────┐
       │  domain/     领域模型（纯 Dart，零 Flutter 依赖）│
       └──────────────────────────────────────────────┘
```

**规则清单**：

1. `domain/` 只依赖 `dart:*` 与 `core/utils`，**不允许 import Flutter**；
2. `core/` 不依赖 `domain` / `data` / `features`；
3. `data/` 依赖 `domain` + `core`，**不依赖 `features`**；
4. `shared/` 依赖 `core` + `domain`，**不依赖任何 feature**；
5. `features/A` **不允许 import `features/B`**；跨功能协作只有两条路：
   - 跳转 → 通过 `app/router` 的路由名；
   - 数据 → 通过 `data/` 的 Repository；
6. `app/` 是唯一可以"认识所有人"的装配层。

> 建议在 CI 加一条自定义检查：扫描 `lib/` 的 import 语句校验上述方向 + 单文件行数上限（见 APP_TODO 第 18 条）。

---

## 二、feature 内部目录约定（ADR D2 落地）

| 目录 | 角色 | 示例 | 可测性 |
| :--- | :--- | :--- | :--- |
| `controllers/` | 有状态编排 | `chapter_cache.dart`、`chapter_content_pipeline.dart` | 需 mock 依赖 |
| `engines/` | **无状态算法 / 纯逻辑** | `pagination_engine.dart`、`vertical_flow_engine.dart`、`reader_progress.dart`、`catalog_navigator.dart` | **可纯 Dart 单测** |
| `models/` | 仅本 feature 使用的模型 | `reader_theme.dart`（含 `Color`，依赖 Flutter，故不能进 `domain/`） | — |
| `widgets/` | 仅本 feature 使用的 UI | `reader_catalog_drawer.dart` | Widget 测试 |
| `pages/` | 多个页面时才建 | `features/rules/pages/rules_page.dart` | 集成测试 |

**"能否单测"一眼可判**是这套划分的核心判据：`engines/` 必可纯 Dart 单测，
`controllers/` 需要替身 —— 阅读器的 4 个引擎因此全部配有独立单测。

---

## 三、明确不做的事（避免过度设计）

1. **不引入状态管理框架**（Riverpod / Bloc）：当前用 `ChangeNotifier` + `ValueNotifier` 足够，
   引框架会带来学习成本与迁移面，收益不匹配；
2. **不做多包拆分**（melos / 内部 package）：单端 App 规模尚不需要，
   等到需要复用到 Web / Desktop 时再抽 `packages/`；
3. **不引入代码生成**（freezed / json_serializable）：模型数量少且字段稳定，
   手写 `fromJson/toJson` 更直观，也避免 build_runner 拖慢迭代；
4. **不为目录整洁而重写逻辑**：搬运与逻辑变更必须分开提交 ——
   这条在阅读器 / 播放器重构中被反复验证：纯 UI 搬运的批次全部零回归，
   而同时夹带逻辑调整的批次都出现过编译或行为问题；
5. **不为了行数指标而外置 `setState` 编排**：紧耦合 `BuildContext` / `GlobalKey` 的页面状态机
   强行抽成 controller，只是把耦合搬了个位置，收益为负（见 APP_TODO 第 18 条）。

---

## 附录 A：架构决策记录（ADR）

> 其中 **D1、D2 修正了原方案第三节的部分安排，以本节结论为准**。

### D1 · `AuraPlayer` 归属：通用播放器下沉 `shared/`，业务适配留在 feature

**决策**：把播放器**拆成两层**放置，而不是整体放进 `features/media/video/`。

| 层 | 位置 | 内容 | 依赖约束 |
| :--- | :--- | :--- | :--- |
| **通用播放器** | `shared/widgets/player/` | `aura_player.dart`（装配）、`player_gesture_engine.dart`、`player_gesture_layer.dart`、`player_control_bar.dart`、`player_control_buttons.dart`、`player_track_shape.dart`、`player_capsules.dart`、`player_overlays.dart`、`player_top_bar.dart`、`player_video_surface.dart`、`player_settings_sheets.dart`、`player_settings_panel.dart` | **禁止 import `data/`、`app/di` 与任何业务 service**；偏好一律通过构造参数注入 |
| **业务适配** | `features/media/video/` | 读取播放偏好、绑定播放历史与断点续播、注入业务动作 | 可依赖 data / domain / shared |

**判据**：只有当通用层**不再 import 任何 `data/` 或 `app/di`** 时，才算真正通用。

**落地状态**：✅ 已完成 —— `aura_player.dart` 已无 `appService` 与 `app/di` 引用，
偏好经 `PlayerPreferences` 注入、变更经回调写出。

### D2 · feature 内部目录：用 `controllers/`，不用 `services/`

**决策**：`services/` 这个名称**全项目不再使用**。

理由：

- `controllers/` 语义明确 —— **有状态、面向 UI、生命周期与页面绑定**的编排单元
  （`ChangeNotifier` / `ValueNotifier`），一眼能看出"这是驱动页面的状态机"；
- `services/` 在社区语境里通常指**无状态、跨功能**的业务能力，容易与 `data/` 层的 Repository
  混淆，最终变成另一个杂物间（重构前的 `services/` 就是这么退化的）；
- 需要"服务"语义时归属本就明确：**跨功能业务能力 → `data/` 的 Repository**；
  **纯业务规则 → `domain/`**。

### D3 · `domain/` 不是 `models/`：它是"业务概念的建模层"

**决策**：保留 `domain/` 命名，不使用 `models/`。

| 维度 | `models/` | `domain/` |
| :--- | :--- | :--- |
| 视角 | 技术（"数据长什么样"） | 业务（"业务里有哪些概念"） |
| 准入 | 模糊 → 易变杂物间 | 明确 → 必须是业务概念 |
| 依赖 | 无约束 | **硬约束：零 Flutter 依赖，只依赖 `dart:*`** |
| 价值 | 仅组织代码 | 保证"业务内核可单测、可跨端复用" |

**准入标准**：

- ✅ 业务实体：`MediaItem`、`Rule`、`PlayRecord`、`FavoriteItem`
- ✅ 值对象 / 枚举：`MediaEpisode`、`MediaGroup`、`MediaType`、`ReadingProgress`、`DownloadStatus`
- ✅ 贴在值对象上的业务规则：如"剩余不足 10 秒视为已看完"的续播判定
- ❌ 网络 DTO / JSON 包装 → `data/`
- ❌ UI 状态（选中项、loading 标记）→ `controllers/`
- ❌ **任何依赖 Flutter 的类型** → 对应 feature 的 `models/`（如含 `Color` 的 `ReaderTheme`）

### D4 · 模型归属：按"被谁引用"决定，宁晚不早

**决策**：模型不预先集中管理，**先放 feature 内，被第二个 feature 用到时再提升**。

| 情况 | 归属 | 本项目示例 |
| :--- | :--- | :--- |
| 仅 1 个 feature 使用 | `features/<name>/models/` | `ReaderTheme`；`NovelChapter`（detail 与 reader 同属 `features/media/novel/`） |
| **2 个及以上 feature 使用**，或需被 `data/` 持久化 | **`domain/<area>/`** | `MediaItem` / `MediaEpisode` / `MediaGroup`；`Rule`；`PlayRecord`；`FavoriteItem` |
| 仅用于传输 / 持久化的结构 | `data/<area>/` | 备份文件结构、规则市场响应包装 |
| 既是业务概念又带状态机 | `domain/<area>/` | `DownloadTask` |

**为什么"宁晚不早"**：过早提升到 `domain/` 会造出一个"谁都不负责"的公共层，
模型频繁变动时影响面反而扩大；等第二个使用者出现再提升，代价只是一次移动。

**提升检查清单**：移动后该类型**不得**引入 Flutter 依赖；若不可避免地需要 `Color` / `Widget`，
说明它是"UI 模型"，应留在 feature 内。
