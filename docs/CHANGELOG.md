# FluxForge 变更日志 (CHANGELOG)

本文档用于记录 FluxForge（包括 App 移动端、Server 服务端、Web 管理端）在开发过程中的重要功能迭代、UI 体验调优与架构重构日志。

## [2026-09-11]

### 🎨 App 图标透明化与白底剔除 (全套 Android 启动图标同步更新)
- **剔除原图白色背景 (`app/assets/icon/icon.png`)**：
  - **背景**：生图模型生成的 App Icon 概念图自带四角白色发光漫反射展示底板，直接打包会导致 Android 桌面图标与开屏页呈现白边与方形底色；
  - **优化**：通过高保真超椭圆圆角路径精确剥离四角全部白色渐变背景（Alpha 置为 0，100% 纯透明），完整保留黑曜石磨砂质感卡片、边缘微弧高光与中央 3D 翡翠莫比乌斯环发光流光 Logo；
  - 同步在 `app/assets/icon/logo_symbol_transparent.png` 提供无底座纯流光单体符号备选方案；
  - 重新执行 `dart run flutter_launcher_icons`，全套更新 Android `mipmap-*`（mdpi 至 xxxhdpi）启动图标。

### 📋 App 全链路日志系统与沙箱 Console 捕获实现
- **JavaScript 规则沙箱 Console.log 拦截 (`app/lib/services/rule_engine.dart`)**：
  - 注入全局增强版 `console` 代理对象，支持 `log/info/warn/error/debug` 多级别打印；
  - 跨桥消息支持多参数自动拼接与嵌套复杂对象 `JSON.stringify` 安全展开，杜绝 `[object Object]`；
  - 规则执行时自动关联当前规则名称（如 `[Rule: 樱花动漫]`），记录沙箱动作耗时（ms）与数据条数。
- **响应式日志核心记录器 (`app/lib/core/utils/app_logger.dart`)**：
  - 扩充 `LogEntry` 模型：支持 `tag` 来源标签、各级别专属主题色与语义化图标；
  - 引入 `ValueNotifier<List<LogEntry>> logsNotifier` 机制，提供 500 条先进先出环形队列，实现 UI 零开销响应式刷新；
  - 支持 `exportLogsAsText()` 纯文本全量导出以及清空内存/磁盘日志。
- **现代化全功能日志中心页面 (`app/lib/views/profile/logs_page.dart`)**：
  - 独立全屏日志诊断中心，适配极夜暗黑与纯净浅色双主题；
  - 支持快捷分类过滤 Chips（全部 / 规则沙箱 / ERROR / WARN / INFO / DEBUG / Network）；
  - 支持实时模糊搜索输入，毫秒级响应过滤；
  - 支持 Live 实时滚屏跟踪模式（Auto-scroll），边调试规则边观测输出；
  - 支持单条展开长文本/堆栈、长按复制单条、右上角一键全量导出（调用系统分享或剪贴板）与二次确认清空。
- **路由与设置入口无缝贯通 (`app/lib/router.dart`, `settings_page.dart`, `profile_page.dart`)**：
  - 注册 `/logs` 全局路由；设置页与个人中心“沙箱运行日志”入口升级为直达 `/logs` 页面，并动态显示日志总数与错误数徽标。
- **质量验证**：`flutter analyze` → **No issues found**（0 Error / 0 Warning，18.7s）。

### 🔍 修复 App 搜索点击后无反馈 & 沙箱初始化并发缺陷

- **搜索点击"无反应"根因修复 (`app/lib/views/search/search_page.dart`)**：
  - **现象**：在搜索页输入关键词点击「搜索」按钮后界面毫无反馈，直到用户做其他操作（如删除输入框文字）才突然出现检索动画；
  - **根因**：`_performSearch()` 在 `setState(_loading = true)` 之后**未让出任何事件循环**，同一同步块内紧接着就串行进入 `RuleEngine.search()`；而 `RuleEngine` 通过 `dart:ffi` **同步**调用 QuickJS 的 `evaluate()`（每次都会把转译后的规则源码交给沙箱求值），同步调用期间主 isolate 无法绘制新的帧，导致 `setState` 调度的 loading 帧迟迟画不出来；
    > 注：`RuleEngine.init()` 已在 `main.dart` 启动阶段执行完成，`_initialized` 为 true，后续调用**不会**重复加载 axios / cheerio 运行库。
  - **修复**：`_performSearch()` 与 `_loadMoreResults()` 在 `setState` 之后统一插入 `await WidgetsBinding.instance.endOfFrame` 并补充 `mounted` 守卫，确保 loading 指示器先渲染出一帧，再进入可能阻塞的沙箱调度流程。
- **沙箱初始化并发缺陷修复 (`app/lib/services/rule_engine.dart`)**：
  - **重复初始化**：`init()` 此前仅用 `_initialized` 布尔量守卫，并发调用（如启动预热与首次搜索同时触发）会重复执行整套 `evaluate` 加载流程，造成双倍主线程阻塞；现改为 `_initFuture ??= _doInit()` 共享同一次初始化任务，失败时清空缓存允许重试；
  - **连续阻塞**：`url.polyfill.js`(16.2KB) / `axios.min.js`(31.2KB) / `cheerio.js`(380.4KB) 三库连续同步加载会长时间占用主线程，现于每个库之间插入 `await Future<void>.delayed(Duration.zero)` 主动让出事件循环；
  - `dispose()` 同步重置 `_initFuture`，确保销毁后仍可重新初始化。
- **质量验证**：`flutter analyze` → **No issues found**（0 Error / 0 Warning，18.1s）。

### 🎬 App 播放器快进/快退手势弹窗视觉精修 (双端体验对齐)
- **AuraPlayer 原生播放器 (`app/lib/widgets/player/aura_player.dart`)**：
  - `_buildSeekingCapsule()` 由原单行横向排布改为**双行紧凑布局**：上行「方向图标 + 快进/快退秒数」，下行「目标时间 / 视频总时长」，主次信息分层，解决单行内容过长导致的拥挤问题；
  - 圆角由 20px 收敛至 16px，内边距调整为 `18 × 9`；秒数字号 13 → 16，并提取 `accentColor` 统一配色变量（快进 = 翡翠绿 `#10B981`，快退 = 琥珀金 `#F59E0B`），与 WebView 端 HUD 配色完全一致。
- **WebView 网页视频手势 HUD (`app/lib/views/browser/web_video_gesture_engine.dart`)**：
  - **整体尺寸压缩**：容器 padding `16px 28px` → `10px 18px`、圆角 `20px` → `14px`、元素间距 `6px` → `3px`、投影收敛；主指示字号 `20px` → `17px`、副信息字号 `13px` → `11px`、进度条 `150×4` → `126×3`，视觉更轻巧、不遮挡画面；
  - **全面移除 emoji 图标**：快进/快退由 `⏩/⏪` 改为纯「`+15s` / `-15s`」数值（依靠绿/金配色区分方向），亮度提示由 `☀️ 亮度 XX%` 改为 `亮度 XX%`，音量提示由 `🔇/🔉/🔊 音量 XX%` 改为 `音量 XX%`，倍速提示由 `⚡ 2.0X 瞬时倍速中` 改为 `2.0X 瞬时倍速中`，规避跨平台 emoji 字体渲染差异；
  - 同步修订文件头部注释中的图标说明与 HUD 初始占位文案。
- **质量验证**：对上述两个修改文件运行 `flutter analyze`，结果 **No issues found**（0 Error / 0 Warning）。

### 🪟 WebView 视频 HUD 半透明化与快进退进度条精简
- **快进/快退 HUD 移除底部进度条 (`app/lib/views/browser/web_video_gesture_engine.dart`)**：
  - 新增 `setProgressTrackVisible(visible)` 统一管理进度刻度条的显隐；`showSeekHud` 中隐藏进度条，仅保留「±Xs」与「时间 / 总时长」两行核心信息，弹窗更轻巧；
  - 亮度、音量、长按倍速三类 HUD 保持进度刻度条可见（百分比与全速状态仍需可视化刻度），切换到对应手势时自动恢复显示，互不干扰。
- **HUD 窗口改为半透明毛玻璃**：
  - 容器背景由 `rgba(15, 23, 42, 0.90)` 降至 `rgba(15, 23, 42, 0.55)`，模糊半径由 `blur(24px)` 提升至 `blur(28px)`，边框提亮至 `0.24` 透明度，使底部视频画面自然透出；
  - 为 `.__ff_hud_delta` 补充 `text-shadow`，保证半透明底色上彩色文字的对比度与可读性。
- **质量验证**：`flutter analyze` → **No issues found**（0 Error / 0 Warning）。

### 🎞️ AuraPlayer 控制栏显隐动画与小屏底部栏单行布局
- **顶部/底部控制栏显隐接入丝滑动画 (`app/lib/widgets/player/aura_player.dart`)**：
  - 原实现为直接条件渲染（`if (_showControls && _isInitialized)`），控制栏消失是"硬闪"、无任何过渡；
  - 改为**常驻渲染 + 动画驱动**：新增通用方法 `_buildAnimatedBar({slideOffset, child})`，内部以 `AnimatedSlide`（250ms / `easeOutCubic`）配合 `AnimatedOpacity`（200ms / `easeOut`）驱动，并用 `IgnorePointer` 在隐藏态屏蔽指针事件，避免点击到已透明但仍在树中的控件；
  - 顶部栏向上滑出 `Offset(0, -1)`、底部栏向下滑出 `Offset(0, 1)`，滑出方向各自契合所在屏幕边缘；
  - 锁屏原先由 `if (_isLocked) return SizedBox.shrink()` 移除节点导致硬切，现统一交由 `_showControls` 驱动（上锁必将其置为 false），锁屏/解锁同样具备过渡动画。
- **小屏底部控制栏合并为单行条线**：
  - 全屏（大屏）保持双行布局——上行「时间 + 进度条 + 时长」、下行「播放 … 倍速 全屏」，操作区舒展、命中率高；
  - 非全屏（小屏）改为**进度条与播放/时间/倍速/全屏全部对齐在同一条水平线上**，起止时间合并为「当前/总长」单段文本，底部内边距由 `bottom:24 / top:16` 压缩至 `bottom:8 / top:4`，显著降低控制条对低矮画面的遮挡；
  - 为支撑双布局并消除重复代码，将底部栏拆分为可复用零件：`_buildProgressSlider` / `_buildPlayPauseButton` / `_buildSpeedPill` / `_buildFullscreenButton` / `_buildTimeText`，并新增 `_currentPosition` getter 统一"拖拽中优先取拖拽值"的取位逻辑；
  - 紧凑态按钮通过 `padding: EdgeInsets.zero` + `constraints: BoxConstraints.tightFor(36×36)` 收紧点击区，避免默认 48×48 挤压进度条可用宽度。
- **质量验证**：`flutter analyze` → **No issues found**（0 Error / 0 Warning）。

### ⚡ 长按瞬时加速倍率可配置 (2x / 3x / 5x) 并打通全局设置链路
- **排查中发现既有问题：播放偏好多项在 UI 上完全失效**
  - 经全局检索确认，`enablePlayerGestures` / `enableLongPress2x` / `resumeBehavior` / `defaultPlaybackSpeed` 四个字段此前仅在 `app_service.dart` 与 `settings_page.dart` 之间流转，`AuraPlayer` 从未读取过它们——设置页里的开关与下拉改了不产生任何实际效果；
  - 本次将长按相关的 `enableLongPress2x` 与新增的倍率一并打通到播放器，其余三项仍待接线。
- **新增可配置项 (`app/lib/services/app_service.dart`)**：
  - `AppSettings` 新增 `longPressSpeed` 字段，默认 `3.0`，可选 `2.0 / 3.0 / 5.0`；
  - 同步接入持久化：`pref_long_press_speed` 的读写（`_loadSettings` / `updateSettings`），并补齐 `copyWith` 参数与构造默认值。
- **AuraPlayer 生效 (`app/lib/widgets/player/aura_player.dart`)**：
  - 新增 `_longPressEnabled` / `_longPressSpeed` 两个 getter，每次长按实时读取全局偏好，设置改动无需重启播放器即生效；
  - `onLongPressStart` 在开关关闭时直接返回；`onLongPressEnd` 增加 `_isFastForwarding` 守卫，避免未真正进入加速态却去恢复原速；
  - 顶部加速胶囊文案由硬编码 `2.0X 快速播放中` 改为按实际倍率渲染。
- **WebView 端同步 (`app/lib/views/browser/web_video_gesture_engine.dart` + `browser_page.dart`)**：
  - `buildVideoGestureScript()` 增加 `longPressSpeed` 与 `longPressEnabled` 两个具名参数；脚本内以 `__FF_LONG_PRESS_SPEED__` / `__FF_LONG_PRESS_ENABLED__` 占位，返回前用 `replaceAll` 注入真实值（脚本为 Dart raw string，无法直接使用插值）；
  - 开关判断放在定时器回调**内部**而非函数提前 `return`——否则会跳过上方的 `initialVolume` / `initialBrightness` 初始化，破坏左右滑动调节亮度与音量的手势。
- **设置页 UI (`app/lib/views/profile/settings_page.dart`)**：
  - 原「长按 2.0X 倍速与触觉震动」更名为「长按瞬时加速与触觉震动」，副标题动态显示当前倍率；
  - 新增「长按加速倍率」下拉项（`LucideIcons.gauge`），可选 2.0x / 3.0x / 5.0x。
- **质量验证**：全项目 `flutter analyze` → **No issues found**（0 Error / 0 Warning）。

## [2026-09-10]

### 🛡️ App 移动端 AdBlock 广告拦截体系轻量化与云端热更改造
- **包体积深度瘦身（直降 11.4 MB）**：
  - 彻底清理 `app/assets/filters/` 目录下全部 5 个臃肿的静态规则文本文件（`adguard_english.txt` 6.4MB、`adguard_base.txt` 2.2MB、`easylist.txt` 2.0MB 等）；
  - 从 `pubspec.yaml` 的 `flutter.assets` 资源打包清单中剔除 `assets/filters/`，极大减少打包构建体积与解压消耗。
- **内置极简种子名单保底（开箱即用 · 零等待）**：
  - 在代码中内置仅 3KB 的核心高频广告联盟黑名单（百度联盟、腾讯广点通、阿里妈妈、字节穿山甲、Google AdSense、暗刷与统计域名等）；
  - 内置小说与影视站常见牛皮癣、悬浮挂件与全屏弹窗的通用隐藏选择器（Seed Selectors），保障新安装及离线状态下 100% 具备拦截能力。
- **云端多镜像异步热更与本地沙箱持久化 (`app/lib/views/browser/adblock_engine.dart`)**：
  - 重构 `AdBlockEngine`：优先读取应用沙箱目录缓存（`<documents>/fluxforge_filters/`），无缓存自动回退种子名单；
  - 内置 4 套权威预设规则源（AdGuard 中文规则优化版、CJX 烦人弹窗规则、EasyList China、EasyList 全球通用基础规则），支持国内官方高速 CDN 与 jsDelivr 加速节点自动容灾重试；
  - 针对海外/英文网页浏览需求，预设 EasyList 全球基础库（默认关闭，按需一键启用）；
  - 支持用户自定义输入订阅链接，支持动态勾选切换；
  - 提取 `##` 元素隐藏规则并生成动态 CSS 与防恶意弹窗 Scriptlet 脚本。
- **内置浏览器与系统设置全链路打通**：
  - **`BrowserPage` 深度注入**：在网页加载前（`onPageStarted`）及加载完成时（`onPageFinished`）自动注入通用隐藏 CSS 与防弹窗脚本，配合 `onNavigationRequest` 形成立体拦截；
  - **`SettingsPage` 交互升级**：在「规则沙箱与网络」中展示已生效规则总数与上次更新时间，提供「立即同步」按钮与规则订阅源管理底栏抽屉。
- **代码规范与质量验证**：
  - 针对修改的关键 Dart 文件运行精准 `flutter analyze`，静态类型分析 0 Error、0 Warning。

### 🎨 App 移动端「我的」界面重构精简 (去除无用、多余与重复功能)
- **剔除无用与静态文本假功能**：
  - 彻底删除原页面中仅弹出纯静态长文本对话框的「QuickJS 沙箱运行环境」、「网络策略与防盗链代理」、「规则生命周期契约指南」等静态自嗨项；
  - 彻底删除研发调试用的「卡片设计体系展廊 (CardGalleryPage)」入口；
- **消灭重复入口与职责错位**：
  - 移除与底部 Tab「规则」100% 重复的本地规则列表堆叠；
  - 移除与系统设置 `SettingsPage` 100% 重复的深层主题设置与重复清理入口；
- **全新极光个人资产中心架构 (`app/lib/views/profile/profile_page.dart`)**：
  - **顶部身份与状态区**：极光渐变品牌头像、探索者设备标识、本地沙箱离线状态绿灯、轻巧的深浅色即时切换与系统设置齿轮；
  - **核心资产指标看板**：追更收藏（支持翡翠呼吸红点）、搜索足迹、已载规则、临时缓存（支持轻触一键快速释放），4 大高频指标一览无余；
  - **正在追更状态微缩卡片**：检测到更新时首屏高亮显示「《作品名》· 最新章节」，点击直达开播/阅读；
  - **四大实用功能收敛卡片**：
    1. **我的收藏与追更** (NEW 微胶囊红点，直达追更列表)；
    2. **数据备份与还原** (单文件 JSON 导出分享与合并/覆盖还原)；
    3. **规则订阅市场** (发现并订阅云端跨媒体解析源)；
    4. **系统偏好设置** (手势偏好、沙箱超时时限、网页广告拦截等全量设置)；
  - **代码量大幅精简**：从原先臃肿冗余的 1087 行深度收敛至 490 行，结构清晰内聚，视觉通透自然。


### 📱 App 移动端核心功能全量落地 (按照 APP_DEV_SPEC.md 规范完成交付)
- **现代自研视频播放器 (AuraPlayer) 落地 (`app/lib/widgets/player/aura_player.dart`)**：
  - **彻底告别 Chewie**：底层完全基于官方原生 `video_player` 驱动硬解，解耦第三方笨重控制层；
  - **全套触控手势体系**：
    - **亮度调节**：左侧 1/3 区域垂直滑动无侵入式调节屏幕明暗度，左侧边缘弹出垂直微胶囊；
    - **免权限音量调节**：右侧 1/3 区域垂直滑动调用应用内音量调节，彻底规避系统敏感权限申请与系统粗大音量条遮挡；
    - **精细快进/快退**：屏幕中央水平滑动手势，居中弹出毛玻璃微胶囊（时间差值与当前/总时长）；
    - **长按 2.0X 瞬时倍速**：长按触发原生触觉轻震动 `HapticFeedback.lightImpact()`，顶部中央弹出呼吸指示徽标；
    - **轻量控制**：双击快速暂停/播放、左下角安全防误触锁屏、0.5x~2.0x 倍速抽屉、横竖屏旋转全屏切换；
    - **极光流光翡翠进度条**：支持缓冲进度、动态拖拽手柄平滑放大；
    - **断点续播智能提醒**：记忆观看进度，自动弹出「上次看到 xx:xx [点击继续]」气泡；
  - **全量换装**：彻底重构 `VideoPlayerPage` 与 `MediaDetailPage`，支持选集联动切换与防盗链 headers 透传。
- **规则健康巡检与毫秒级测速 (`RuleService` & `RulesPage`)**：
  - **并发轻量探测**：在 `RuleService` 中实现并发 HEAD 连通性探测（超时 3 秒并支持 405 时降级 GET 流探测）；
  - **三色微胶囊指示器**：畅通（🟢 <500ms 极光绿）、较慢（🟡 500~1500ms 琥珀黄）、失效（🔴 超时/错误 红色）；
  - **失效源批量治理**：在规则页搜索栏下方增设失效提示横幅，支持「一键禁用」或「一键清理」失效规则。
- **纯净小说阅读引擎 (FluxReader) 落地 (`app/lib/views/reader/novel_reader_page.dart`)**：
  - **动态视口切片排版**：按屏幕视口高度与字号自适应切片分页；
  - **双阅读翻页模式**：支持左右平滑横向翻页与上下连续无缝长篇滚动；
  - **四大护眼底色方案**：羊皮复古 (`#F6F1E7`)、豆沙护眼 (`#E4EDE1`)、极夜深邃 (`#0F141C`)、纯净白瓷 (`#FFFFFF`)；
  - **交互体验**：字号无级增减、行间距微调、目录抽屉切章与阅读偏好本地持久化。
- **漫画与图集查看器 (FluxGallery) 落地 (`app/lib/views/gallery/gallery_viewer_page.dart`)**：
  - **双展示模式自由切换**：2列瀑布流大图展厅 vs 垂直无缝长图条漫（漫画专用连续拼图下拉）；
  - **手势无级平滑缩放**：基于 `ExtendedImageGesturePageView` 实现 1.0x ~ 4.0x 双指缩放与双击复位；
  - **快捷操作面板**：长按图片弹出直链复制、系统分享与浏览器直达抽屉；
  - **聚合分发**：在 `MediaDetailPage` 中打通漫画、图集与小说精准分发。
- **本地全量数据一键备份与还原 (BackupService) 落地 (`app/lib/services/backup_service.dart`)**：
  - **标准化数据契约**：单文件打包命名为 `fluxforge_backup_YYYYMMDD_HHmm.json`，包内容涵盖 rules、favorites、history；
  - **系统分享导出**：写入本地临时目录并通过 `share_plus` 一键唤起原生分享面板保存或外发；
  - **安全还原机制**：支持校验合法性，提供「合并追加」与「完全覆盖」双重导入模式。
- **统一多媒体收藏与智能追更提醒 (`FavoriteService` & `FavoritesPage`)**：
  - **跨媒体收藏库**：统一收纳影视、小说、漫画，支持本地持久化；
  - **智能追更机制**：支持并发追更比对，检测到新集数/章节时点亮极光翡翠「NEW · 第xx集」角标；
  - **页面与入口**：新建 `FavoritesPage`，在 `ProfilePage` 指标看板与快捷操作中接入「我的追更」与动态呼吸红点。
- **全局偏好与系统设置中心全面升级 (`SettingsPage` & `AppService`)**：
  - **完备 AppSettings 模型**：涵盖播放手势偏好、长按倍速、沙箱 15s/30s/60s 超时阈值、广告拦截、自定义 UA、主题及无痕消费；
  - **现代六大圆角卡片布局**：
    1. 播放与视听偏好 (AuraPlayer 深度联动)；
    2. 浏览与阅读偏好 (FluxReader & Gallery 偏好联动)；
    3. 规则沙箱与网络解析；
    4. 数据存储与精准深度维护 (备份导出/导入入口、网络缓存精准计算与清理、搜索历史清空)；
    5. 外观与主题系统 (跟随系统/极夜/纯白)；
    6. 关于与系统诊断 (沙箱运行日志一键查看与清空)。


### 📚 规范与产品规划 (Docs)
- **重构根目录与移动端 README 建设全景看板**：
  - **根目录 [`README.md`](../README.md)**：新增《全栈功能矩阵与研发进展看板 (Feature Status)》与《官方文档中心导引》，全景呈现全端（Web、Server、App）与规则引擎已完成（✅）与规划中（⏳）特性；
  - **移动端 [`app/README.md`](../app/README.md)**：将原空白模板重构为移动端专属技术说明书，涵盖本地沙箱架构、核心功能完成度详表、`APP_DEV_SPEC.md` 开发规范直链、运行与 Android 证书签名打包指南。
- **发布《移动端核心功能技术开发与落地规范》([`docs/APP_DEV_SPEC.md`](./APP_DEV_SPEC.md))**：
  - **扁平 1234 一体化结构**：不碎片化建档，在单一文档内收敛 7 大章节，为后续 AI 自动编码与组件落地提供 100% 严密的输入约束；
  - **自研播放器 (AuraPlayer) 独立定名与规格定死**：弃用与主项目强绑定的临时名，正式定名为兼具现代美学与独立开源沉淀潜力的 `AuraPlayer`；明确彻底废弃 Chewie，底层锁定官方原生 `video_player`；详述四大手势系统（左亮度、右免权限应用音量、中进度微胶囊、长按 2.0x 震动倍速）、极光流光进度条与历史断点秒级续播；
  - **小说阅读/图集/测速/备份/设置规范入库**：完整提供排版色盘、双指手势缩放、规则 HEAD 测速、本地单文件备份 Schema，并在第 8 章正式整合《全局偏好与系统设置 (AppSettings)》规格（覆盖播放手势开关/默认倍速、沙箱 15s/30s/60s 超时下拉阈值、存储深度细分清理等）。
- **落地《移动端产品规划与演进路线图》([`docs/APP_ROADMAP.md`](./APP_ROADMAP.md))**：
  - **边界收敛与减负**：明确砍去沉重的跨端联动、WebDAV及多端适配，将后台 WebView 嗅探降为最低优先级，全力聚焦纯粹手机端体验；
  - **核心消费体验闭环 (P0~P1)**：规划视频播放器深度手势与断点续播、纯净小说阅读引擎、瀑布流与条漫图集查看器；
  - **轻量规则生态与资产安全 (P0~P2)**：规划规则健康巡检与毫秒级测速指示灯、规则分组管理、多媒体统一收藏与追更红点提醒、纯本地单文件全量备份还原等核心演进路径；
  - **文档中心对齐**：在 [`docs/README.md`](./README.md) 中更新了路线图的全局导航索引。

---

## [2026-09-09]

### 📱 App 移动端 (Flutter)
- **主题系统升级 Material 3 Expressive 动态色彩变体**：
  - 在 AppTheme (pp/lib/core/theme/app_theme.dart) 的浅色与深色 ColorScheme.fromSeed 中全面注入 dynamicSchemeVariant: DynamicSchemeVariant.expressive 属性；
  - 激活 Google Material 3 进阶算法：赋予各层级组件（surfaceContainer、	ertiary、各组件状态高光等）更高彩度与动态色相跳跃，全面提升微拟态与卡片分层的通透感。
- **内置浏览器 (BrowserPage) 手势返回与 PopScope 深度修复**：
  - **动态 canPop 接管原生返回手势**：将写死的 canPop: false 重构为动态响应式的 canPop: !_canGoBack，消除滑动返回退出 App 的 Bug；
  - **防重入与多重 Pop 防护**：在 onPopInvokedWithResult 中增加 if (didPop) return; 阻断；
  - **生命周期状态对齐**：在 onPageFinished 阶段同步触发 _controller.canGoBack()。
- **规则管理页 UI 极致精简与修复**：
  - **导入 AppColors 修复编译**：在 RulesPage 顶部补齐 ../../core/theme/app_colors.dart 引用；
  - **移除统计大横幅**：彻底移除 RulesPage 顶部的大色块统计卡片及重复的「规则市场」按钮；
  - **首屏空间优化**：搜索栏与规则卡片列表无缝直连；
  - **清理冗余变量**：同步剔除无引用的 enabledCount 计算逻辑。
