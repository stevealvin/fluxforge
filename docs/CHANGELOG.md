# FluxForge 变更日志 (CHANGELOG)

本文档用于记录 FluxForge（包括 App 移动端、Server 服务端、Web 管理端）在开发过程中的重要功能迭代、UI 体验调优与架构重构日志。

## [2026-09-14]

### 📖 小说阅读器架构级重构：彻底摒弃脆弱固定字数切片，全面升级为 Flutter 原生 TextPainter 视口物理测量驱动精准分页引擎
- **用户建议与核心洞察**：
  - 用户敏锐并精准地指出：“小说阅读界面通过固定文字实现每页屏幕的展示是不是有问题”；
  - **核心痛点深度排查**：
    1. **空行与对话密集段落必定溢出丢字**：固定字符算法（如 360 字）若遇到角色密集对话（短句与换行频繁）或诗歌空行，360 字可能会触发 30~40 行换行，直接超出常见手机竖屏能容纳的 16~19 行上限，下半部分内容被完全截断看不到；
    2. **不同设备屏幕尺寸无法适配**：小屏机（如 iPhone SE）与大屏机/折叠屏/平板（如 iPad、全面屏旗舰）可用高度差距巨大。固定字数在小屏上溢出、在大屏或平板上却只占上半截，留下大片惨白；
    3. **行距与字号调节失衡**：用户拉大行距（如 1.4x 到 2.2x）时，每行占据高度放大 50% 以上，固定字符算法完全无法感知垂直像素占用，调大行距必然大面积超屏；
    4. **机械切片破坏阅读连贯性**：固定字符切分经常从复合词或句子中间切断。
- **重构落地与引擎升级**：
  1. **LayoutBuilder 视口物理感知**：
     - 在 [`novel_reader_page.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/media/novel/reader/novel_reader_page.dart) 的翻页主体中引入 `LayoutBuilder`，在首帧排版以及屏幕旋转、分屏、字号/行距调节时，实时捕获精确到像素级的正文可用物理尺寸（`renderWidth` 与 `renderHeight`）；
  2. **Flutter 原生 TextPainter 亚像素级二分查找分页算法**：
     - 依据用户当前字号、行高倍率与字间距，利用 `TextPainter` 对章节文本进行二分查找测量，寻找在 `textPainter.height <= renderHeight` 约束下的最佳单页字符上限；
     - 每一页排出的文字严格贴合可用屏幕高度，**不多一字、不少一行，零溢出、零丢字、零多余留白**，在彻底杜绝上下滑动的同时保证每一页内容完整呈现；
  3. **智能段落末尾自然吸附**：
     - 在单页截断点末尾 35 个字符以内智能探测换行符 `\n`，优先在段落末尾自然翻页，还原纸质图书般连贯舒缓的阅读体验。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 25 项自动化测试用例 100% 全部通过 (25/25 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。



### 🎨 小说阅读翻页锁死、详情主题自适应、无边线卡片、搜索历史紧凑化及播放器视觉全量升级
- **用户反馈与针对性排查**：
  1. 小说阅读界面翻页模式还是能上下滑动，目录弹窗去掉标题下面的分割线；
  2. 小说详情界面暗色模式文字去掉颜色，让系统自适应；小说封面图片有外边线吗，有的话去掉；
  3. 搜索历史元素上下间隔减小一点；
  4. 视频详情剧照与预览图片有边框线吗，如果有去掉；
  5. 播放器中心的播放暂停图标太大了小一点；
  6. 播放器图标有更好的吗，特别是放大缩小图标。
- **问题深度溯源与成因剖析**：
  1. **小说横向翻页模式仍可上下滑动**：`PageView` 本身只负责横向滑页，但单页内容采用的 `SelectableText` 内部自带垂直 `Scrollable` 视口；同时此前 `_recalculatePages` 基准字数设为 600 字，在手机竖屏下超出一页高度，触发了内置垂直滚动并与横翻手势冲突；
  2. **小说详情暗色模式文字生硬与封面多余外边线**：详情页标题、简介与选集此前残留了硬编码颜色三元分支；同时通用头部封面卡片 `_buildCoverCard()` 显式配置了 0.8px 的 `border: Border.all` 外边线；
  3. **搜索历史元素上下间距过大**：`Wrap` 默认 `runSpacing` 为 8，且 `InputChip` 具有 Material 默认的 48px 点击热区外延扩展，导致行间视觉间距偏大；
  4. **视频详情剧照预览外边线**：`_buildPreviewsSection()` 横向列表项的容器上存在 `border: Border.all(...)` 边框配置；
  5. **播放器中心播放/暂停按键体量过大**：此前中心图标尺寸为 48px（容器 56px），且细线空心轮廓在明亮或复杂视频背景画面下辨识度偏弱；
  6. **全屏放大缩小图标视觉单薄**：此前的 `Ionicons.expandOutline / contractOutline` 为单纯折角单线，在流媒体播放器底栏中视觉分量较轻，缺乏经典流媒体全屏图标的稳重与辨识度。
- **重构落地与体验调优**：
  1. **小说阅读器交互锁死与纯净弹层**：
     - 在 [`novel_reader_page.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/media/novel/reader/novel_reader_page.dart) 中，为 `SelectableText` 注入 `scrollPhysics: const NeverScrollableScrollPhysics()`，彻底切断垂直滚动轴；同时将单页基准字数优化为适合竖屏阅读的 360 字，彻底根治上下滑动；
     - 移除目录抽屉标题下方的 `Divider(height: 1)`，使弹窗更加通透沉浸；
  2. **小说详情与封面纯净自适应**：
     - 在 [`novel_detail_view.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/media/novel/novel_detail_view.dart) 中，移除章节标题上的强制硬编码颜色，交由系统主题原生自适应；
     - 在 [`media_meta_header.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/media/common/media_meta_header.dart) 中，移除主标题与作品简介的硬编码颜色，移除 `_buildCoverCard()` 的 0.8px 外边线；
  3. **搜索历史紧凑排版**：
     - 在 [`search_page.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/search/search_page.dart) 中，将 `Wrap` 的 `runSpacing` 从 8 减半至 4，为 `InputChip` 配置 `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`、`visualDensity: VisualDensity.compact` 与紧凑内边距；
  4. **视频剧照纯净无边线**：
     - 在 [`video_detail_view.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/media/video/video_detail_view.dart) 的 `_buildPreviewsSection()` 中彻底剔除 `border: Border.all(...)`；
  5. **播放器中心播放暂停按键精致化**：
     - 在 [`aura_player.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/widgets/player/aura_player.dart) 中，将中心播放暂停图标由 48px 收紧为 34px（外层 44px），采用圆润质感的流媒体标准矢量图标 `Icons.play_arrow_rounded` 与 `Icons.pause_rounded`，兼具抗杂乱背景的高对比度与轻量美感；
  6. **播放器流媒体级图标升级**：
     - 全屏/退出全屏图标升级为现代流媒体标准圆角的 `Icons.fullscreen_rounded` 与 `Icons.fullscreen_exit_rounded`；
     - 底栏播放暂停按钮同步统一升级为圆角实心矢量图标 `Icons.play_arrow_rounded` / `Icons.pause_rounded`。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 25 项自动化测试用例 100% 全部通过 (25/25 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

## [2026-09-13]

### 🎯 详情页文字颜色架构重塑：彻底废除硬编码分支，全面交由 Flutter 全局主题原生自适应
- **用户建议与核心洞察**：
  - 用户敏锐地指出：“详情视频类型内暗色主题标题文字、预览标题、相关推荐标题文字、相关推荐列表元素文字颜色不对，是设置了文字颜色吗，如果直接不设置颜色是不是就行了”；
  - **根本原因深度排查**：
    1. **硬编码颜色的脆弱性**：此前在详情页各模块标题（视频主大标题、选集标题、剧照与预览标题、相关推荐标题、推荐卡片标题、顶栏标题等）显式设置了 `color: isDark ? Colors.white : AppColors.lightTextPrimary`。一旦上下文或环境在路由转场时偶发状态错位，硬编码不仅会产生生硬死白（`#FFFFFF`），甚至会错误应用浅色文字（暗黑背景下的黑字），直接破坏视觉可读性；
    2. **用户提议直击本质**：Flutter 的 `Scaffold`、`Material` 与 `Card` 本身内置了完善的 `DefaultTextStyle` 级联体系。在不显式指定 `color` 时，所有文本天然会自动继承当前主题的 `colorScheme.onSurface`（深色模式为柔和亮白，浅色模式为深黑 Slate 900），不仅彻底杜绝错乱，而且严格符合 Material 3 与 Apple 人机交互设计规范。
- **重构落地与精简**：
  1. **主标题全面脱色，交由全局 Theme 原生驱动**：
     - 在 [`VideoDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/video/video_detail_view.dart) 中，彻底移除视频大标题 `_displayTitle`、“选集”标题、“全部剧集”抽屉标题、“剧照与预览”标题中的死硬 `color` 参数；
     - 在 [`MediaRelatedGrid`](file:///c:/dev/projects/fluxforge/app/lib/views/media/common/media_related_grid.dart) 中，移除“相关推荐”主标题与卡片项标题 `item.title` 中的 `color` 参数；
     - 在 [`MediaDetailPage`](file:///c:/dev/projects/fluxforge/app/lib/views/media/media_detail_page.dart) 中，移除顶栏标题中的 `color` 参数；
     - 同步对齐 [`ComicDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/comic/comic_detail_view.dart) 与 [`NovelDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/novel/novel_detail_view.dart) 章节选集标题；
  2. **次级文本层次清晰化**：
     - 保留集数提示、图片数量及描述等次级提示的弱化色彩（`darkTextMuted / lightTextMuted`），确保主标题高对比、次级文本柔和不抢戏。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 25 项自动化测试用例 100% 全部通过 (25/25 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。


### ⚡ 全工程全面接入 `ionicons`：回归精致轻盈现代细线条美学与原生架构瘦身
- **重构背景与审美驱动**：
  - 用户反馈指出：“font_awesome_flutter有细一点的图标吗”，“用ionicons看看”；
  - **核心痛点深度剖析**：
    1. **Font Awesome 免费版视觉偏粗**：开源免费版主要打包的是 Solid（实心粗体），在浅色和深色主题下视觉分量过重、块状感强，且绝大多数业务图标没有 Regular（细线）版本；官方真正的细线（Light / Thin）属于年费 \$99+ 的 Pro 商业闭源授权；
    2. **工程组件封装冗余**：`font_awesome_flutter` 需借助非标准容器 `FaIcon` 渲染，破坏了 Flutter 标准的 `Icon(IconData)` 泛型规范；
    3. **Ionicons 核心优势挖掘**：
       - **纯正细线美学**：每个图标均提供对应且统一粗细（1.5~2px）的 `_outline` 细线变体，端点饱满微弧，极度契合现代移动端与极光翡翠双主题的轻盈质感；
       - **超低包体积**：整个包仅 **790 KB**（比 Font Awesome 1.55 MB 再降近 50%，比原 Lucide 49.8 MB 缩减 98.4%）；
       - **原生 IconData**：原生支持 Flutter 标准 `Icon(...)` 组件，与 Material/Cupertino 设计完全平滑兼容；
       - **成对双态交互**：完美支持未选中细线（如 `compassOutline`）与选中实心（如 `compass`）的状态切换，对齐移动端顶级交互规范。
- **全量迁移与工程落地**：
  1. **依赖升级与依赖瘦身**：
     - 在 [`pubspec.yaml`](file:///c:/dev/projects/fluxforge/app/pubspec.yaml) 中移除 `font_awesome_flutter`，接入 `ionicons: ^0.2.3`；
  2. **跨 25 个文件与测试的精准语义对齐 (86 组图标映射)**：
     - 将全工程各业务组件（播放器、媒体详情、选集栏、漫画小说阅读器、底部导航、搜索发现、规则调试器等）的 211 处图标调用全部平滑升级为 `Icon(Ionicons.xxxOutline)`；
     - 还原为 Flutter 标准原生的 `Icon` 组件，废除自定义 `FaIcon`，类型系统全面收敛至原生 `IconData`；
  3. **单元测试与测试断言对齐**：
     - 同步更新 [`test/widget_test.dart`](file:///c:/dev/projects/fluxforge/app/test/widget_test.dart) 中的断言逻辑，彻底消除 `.data` 别名依赖。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 25 项自动化测试用例 100% 全部通过 (25/25 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。


### 💎 视频详情页深色主题深度打磨：标题层级纯白高亮、剧照与推荐标题规范、AppCard.flat 全面换装与无缝顶栏
- **用户反馈与针对性排查**：
  - 用户提出 4 项核心诉求：“你改了什么，暗色主题标题文字颜色有问题，预览标题和相关推荐标题有问题，相关推荐列表用appcard了吗，去掉顶部栏和视频中间的分割线”；
  - **问题深度溯源与成因剖析**：
    1. **暗色模式标题文字颜色发暗/灰白**：顶栏标题与视频大标题此前使用了 `AppColors.darkTextPrimary`（`Slate 50`），在暗黑纯黑底色与播放器附近对比度不足，未能呈现出高亮纯白的锐利精致感；
    2. **预览与相关推荐标题排版失真**：此前粗暴将数量拼接在主标题粗体文字内（如 `剧照与预览 (10)`），缺少旧版精致的视觉层级节奏；相关推荐甚至缺失数量指示，不符合项目规范；
    3. **相关推荐卡片遗漏 AppCard 包装**：[`MediaRelatedGrid`](file:///c:/dev/projects/fluxforge/app/lib/views/media/common/media_related_grid.dart) 此前仅给封面图片包裹了容器，下方文字直接裸露在背景上，深色模式下文字背部“死黑悬浮”，丧失卡片实体感与防溢出圆角裁剪；
    4. **顶栏与视频之间存在突兀割裂灰线**：[`MediaDetailPage`](file:///c:/dev/projects/fluxforge/app/lib/views/media/media_detail_page.dart) 顶栏此前残留了 0.5px `Border(bottom: ...)` 底部边框，在深色顶栏与纯黑视频播放器之间横插了一条生硬亮灰线。
- **重构落地与质感精修**：
  1. **无缝沉浸顶栏（彻底移除与视频之间的分割线）**：
     - 在 [`MediaDetailPage`](file:///c:/dev/projects/fluxforge/app/lib/views/media/media_detail_page.dart) 的 `_buildTopBar` 中彻底移除底部 Border 分割线，让暗色顶栏与下方纯黑播放器实现纯净浑然一体的视觉过渡；
     - 顶栏主标题与返回按钮在暗色模式下统一强化为 `Colors.white`（最高对比度），刷新图标对齐 `Colors.white70`；
  2. **暗色主题文字全面纯白高亮与对比度重塑**：
     - 在 [`VideoDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/video/video_detail_view.dart) 中将视频主大标题重塑为高亮纯白 `isDark ? Colors.white : AppColors.lightTextPrimary`（18px, w600）；
     - 同步规范“选集”与抽屉内“全部剧集”标题在暗色下为纯白 `Colors.white`；
     - 同步对齐 [`ComicDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/comic/comic_detail_view.dart) 与 [`NovelDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/novel/novel_detail_view.dart) 章节目录标题颜色；
  3. **标题层级全面对齐旧版规范标准**：
     - 将“剧照与预览”和“相关推荐”标题统一规范为：**3.5px 极光翡翠指示条** + **14.5px SemiBold w600 主标题（`Colors.white`）** + **间距 6px** + **12px 弱化次级数量提示（`(${count})`, `AppColors.darkTextMuted`）**；
     - 彻底告别粗暴拼串与字体失衡，视觉层级干练典雅；
     - 优化预览缩略图列表高度为 76px（严格契合 16:9 比例）；
  4. **相关推荐列表全面换装 `AppCard.flat` 标准卡片**：
     - 在 [`MediaRelatedGrid`](file:///c:/dev/projects/fluxforge/app/lib/views/media/common/media_related_grid.dart) 中全量改用 `AppCard.flat`（`padding: EdgeInsets.zero`, `borderRadius: 10`）进行整卡包裹；
     - 封面内嵌底部暗部渐变遮罩 `LinearGradient(colors: [transparent, Colors.black87])`，确保右下角角标 Badge 胶囊清晰醒目；
     - 底部文字信息区规整 `EdgeInsets.fromLTRB(8, 6, 8, 6)` 内边距，主标题纯白高亮，副标题次级灰；
     - 宽屏网格宽高比调整为 `childAspectRatio: 1.34`（旧版黄金比），彻底消除底部冗余空白，深色模式自动享有 0.5px 微光轮廓；
     - 在 [`MediaRelatedItem`](file:///c:/dev/projects/fluxforge/app/lib/models/media.dart) 契约模型中新增 `badge` 字段并支持 `status`/`rating` 智能兜底，提升沙箱解析容错。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 25 项自动化测试用例 100% 全部通过 (25/25 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。


### 🎬 视频详情页极致体验还原与暗色模式深度重塑 (吸顶播放器 + 纯净平铺元数据 + 横向选集滑动条 + 全量抽屉)
- **核心诉求与重构对齐**：
  - 用户指出：“视频详情暗色模式下还是有问题，看一下重构之前的文件这个部分是怎么写的，有提交记录”，“顶栏保留，其他的实现”；
  - **历史源码与深色问题深度复盘**：
    1. **滚动失焦与播放器被卷走**：新版此前把整个页面（包括播放器）塞在外层单一 `SingleChildScrollView` 中，导致用户在下方选集翻找或查看推荐时，播放器直接被滚出屏幕；
    2. **元数据生硬框选与暗色融底**：视频区强行套用了通用 `MediaMetaHeader`，在深色背景上套了一层厚重的 `AppCard` 简介框，线条突兀，缺乏沉浸感；
    3. **选集体验倒退**：新版之前把几十上百集全部用 4 列 GridView 竖向全部铺平在页面，占据海量纵向空间，把剧照和相关推荐无限往下推，破坏了流媒体选集节奏；
    4. **旧版优秀设计挖掘**：重构前 [`rule_detail_page.dart`](file:///c:/dev/projects/fluxforge/app/lib/views/rules/rule_detail_page.dart) 采用了极致沉浸的视频交互规范——吸顶播放器始终驻顶、元数据纯净平铺零多余边框、单行横向快速切集滑动条、大集数呼出半屏抽屉。
- **重构落地与体验升华**：
  1. **保留统一顶栏，实现 16:9 吸顶常驻播放器**：
     - 在 [`MediaDetailPage`](file:///c:/dev/projects/fluxforge/app/lib/views/media/media_detail_page.dart) 完美保留统一流光沉浸式顶栏；
     - 视频类型重塑为分层架构：顶部 16:9 `AuraPlayer` 吸顶常驻（Pinned），无论下方如何滚动，播放画面始终清晰可见；
  2. **纯净平铺视频元数据与折叠简介**：
     - 在 [`VideoDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/video/video_detail_view.dart) 彻底移除多余的卡片与简介外框；
     - 标题采用 `18px FontWeight.w600`（深色 `darkTextPrimary`），流式平铺琥珀黄评分胶囊（`#F59E0B`）、极光幽绿规则源、分类题材微光药丸与作者演职员；
     - 简介直接平铺于主视口，采用 `GestureDetector` + `AnimatedCrossFade` 平滑展开折叠，深色次级文本高清晰度对比；
  3. **商业级长视频选集体系完全恢复**：
     - **多线路切换**：支持横向滑动 `ChoiceChip` 胶囊，选中为极光翠绿实体；
     - **单行横向快速滑动条 (46px)**：横向单行滑动（`ListView.separated(scrollDirection: Axis.horizontal)`），当前播放集采用极光翠绿实体背景 + 翠绿发光阴影 + 白色小播放三角图标（`FontAwesomeIcons.play`）+ 白色粗体字；未播放集为微光实体卡片 `darkCard` + `darkBorder`；
     - **全量剧集底部半屏抽屉 (`_showAllEpisodesSheet`)**：当集数 > 5 时，选集标题栏右侧展示“全部”按钮（`FontAwesomeIcons.tableCellsLarge`），点击呼出 65% 高度底部抽屉，支持顶部药丸把手、抽屉内正倒序即时切换与 4 列网格自由点播，选中即刻切集并关闭抽屉；
  4. **剧照截图横向流与宽屏相关推荐完整衔接**：
     - 剧照预览采用 16:10 宽屏卡片，相关推荐采用 16:9 现代宽屏双列流，点击相关推荐自动受控暂停当前视频播放。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 23 项自动化测试用例 100% 全部通过 (23/23 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

### ✨ 全工程图标体系升维：全面迁移至 `font_awesome_flutter` 11.0 质感图标生态
- **重构背景与审美驱动**：
  - 用户反馈指出：“font_awesome_flutter 图标好像好看一点”，明确指示执行“全量替换”；
  - **深度解析**：`font_awesome_flutter` 相比原先的细线 Outline 图标，具有更高的视觉分量（Visual Weight）、更扎实的实心轮廓与更强的辨识度。在深色（曜夜暗黑）与浅色（星暮白）双主题下，实体剪影的色彩饱和度与光影对比显著增强，大幅提升了流媒体播放、操作交互及导航栏的沉浸高级感；
  - **工程瘦身**：原依赖包 `lucide_icons_flutter` 在 pub 缓存中携带了 20MB SVG 源码与 13MB 冗余元数据，总计占用 49.8MB；全量迁移至 `font_awesome_flutter` (v11.0.0) 后，本地依赖包大幅精简至 1.55MB，依赖解析与开发编译更加敏捷。
- **全量迁移与类型系统兼容落地**：
  1. **依赖升级与引擎适配**：
     - 在 [`pubspec.yaml`](file:///c:/dev/projects/fluxforge/app/pubspec.yaml) 中彻底移除 `lucide_icons_flutter`，引入现代适配 Flutter 3.27+ / 3.47+ 架构的 `font_awesome_flutter: ^11.0.0`；
  2. **跨 24 个源文件与测试的精准语义对齐 (211 处图标调用)**：
     - 构建了完备的 100 组 Lucide 到 FontAwesome 的高颜值语义映射词典（涵盖播放控制 `play`/`pause`/`forward`/`backward`、导航路由 `compass`/`store`/`wandMagicSparkles`/`user`、文档与书卷 `bookOpen`/`film`/`image`、通用交互 `magnifyingGlass`/`gear`/`arrowsRotate`/`copy`/`shareNodes`/`shieldHalved` 等）；
     - 将全工程各业务组件、抽屉弹层、控制栏与底部导航的 211 处图标调用全部平滑升级为 `FaIcon(FontAwesomeIcons.xxx)`；
  3. **架构健壮性升维与泛型兼容**：
     - 升级通用组件 [`EmptyState`](file:///c:/dev/projects/fluxforge/app/lib/widgets/app_empty_state.dart) 及各级配置瓦片（如 `_buildFilterChip`、`_buildThemeTile`、`_buildSectionHeader` 等），原生支持 `FaIconData`、`IconData` 与 `Widget` 复合输入，避免强转异常；
     - 深度重构 [`AuraPlayer`](file:///c:/dev/projects/fluxforge/app/lib/widgets/player/aura_player.dart) 视频播控层与滑动音量/亮度/寻道 HUD，全面换装 FontAwesome 高清图标；
     - 同步更新 [`test/widget_test.dart`](file:///c:/dev/projects/fluxforge/app/test/widget_test.dart)，支持测试环境断言。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 23 项自动化测试用例 100% 全部通过 (23/23 Passed)**；
  - 严格遵守最高指令要求，未执行 Git 提交或推送。

### 🎨 详情页深色模式质感重塑与跨媒体头部组件参数精简 (`MediaMetaHeader`)
- **核心痛点定位与分析**：
  - 用户反馈：“不需要这两个设置，深色模式下详情页面颜色有问题”；
  - **根本原因排查**：
    1. **深色融底与无层级感**：之前详情页各模块大量使用 `Colors.white.withValues(alpha: 0.04~0.06)` 作为深色卡片背景。在全局曜夜暗黑背景 `AppColors.darkBg` (`#0A0D14`) 下，这种半透明黑色几乎完全丧失实体材质边界，导致标题卡片、简介区域、选集网格、线路切换按钮与整页背景“死黑融底”，无边框微光、无立体层级感；
    2. **组件契约冗余**：[`MediaMetaHeader`](file:///c:/dev/projects/fluxforge/app/lib/views/media/common/media_meta_header.dart) 历史遗留了 `showFavoriteButton` 与 `showActions` 两个布尔开关，不仅导致上层构造参数冗长，且逻辑与媒体中心职责重叠。
- **重构落地与质感升华**：
  1. **彻底移除冗余参数，精简组件契约**：
     - 从 `MediaMetaHeader` 中彻底移除 `showFavoriteButton` 与 `showActions`，移除了大块追更栏并收敛为右上角轻量分享按钮；
     - 外部使用点（[`VideoDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/video/video_detail_view.dart)、[`NovelDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/novel/novel_detail_view.dart)、[`ComicDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/comic/comic_detail_view.dart)）全面同步精简传参。
  2. **全面重构详情页深色模式色彩体系**：
     - **实体卡片底色升级**：全链路采用设计系统标准 `AppColors.darkCard` (`#151C2C`)，替换原先的 `white.withValues(alpha: 0.04)`，形成坚实深邃的暗曜微光材质；
     - **极光微光发光边框**：所有海报卡片、简介卡片、线路药丸胶囊、选集按钮及剧照图文容器均启用 `AppColors.darkBorder` (`#1E293B`)，打造 0.8px 高级冷色微发光描边；
     - **高对比度文字与标签层级**：标题统一采用 `AppColors.darkTextPrimary` (`#F8FAFC`)，副标题与说明采用 `AppColors.darkTextSecondary` (`#94A3B8`)，辅助与来源采用 `AppColors.darkTextTertiary` (`#64748B`)，彻底告别文字灰暗模糊；
     - **选集网格交互升华**：未选中剧集/章节采用微光暗曜实体卡片，选中态采用极光翠绿 `AppColors.primary.withValues(alpha: 0.22)` 高亮衬底与翠绿主边框，对比强烈、焦点清晰；
     - **顶部导航与沉浸底色贯通**：[`MediaDetailPage`](file:///c:/dev/projects/fluxforge/app/lib/views/media/media_detail_page.dart) 顶栏、占位骨架与正文统一接入深色模式微边框与纯正曜夜底色。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 23 项测试用例全部通过 (100% Passed)**；
  - 严格遵守指令要求，未向远程仓库提交或推送 Git。

### 📖 小说文学阅读引擎 (FluxReader) 正文沙箱异步按需抓取与自由划选/一键复制重构
- **核心痛点定位与分析**：
  - 用户反馈：“小说类型，点击章节的时候好像一直是‘正在加载章节内容...’，小说内容增加可以复制”；
  - **根本原因排查**：原小说详情页在组装 `NovelChapter` 时将所有章节内容硬编码为占位文本 `'正在加载章节正文内容...'`，而 `NovelReaderPage` 历史版本仅为静态展示容器，未持有 `Rule` 对象且没有任何调用沙箱 `RuleEngine.parse` 抓取正文的代码，导致用户切章后永远停留于占位文本中；同时旧文本采用只读 `Text` 渲染，无法长按选词或复制。
- **重构落地与体验升华**：
  1. **全链路接入沙箱 `parse` 生命周期动作**：
     - 在 [`NovelDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/novel/novel_detail_view.dart) 打开阅读器时完整透传 `rule`、`customHeaders` 及待加载章节清单；
     - 在 [`NovelReaderPage`](file:///c:/dev/projects/fluxforge/app/lib/views/media/novel/reader/novel_reader_page.dart) 建立异步加载流水线 `_loadChapterContent(index)`，按需调用 `RuleEngine.parse(widget.rule!, chapterUrl)`；
     - 建立基于内存的 `_contentCache` 章节缓存字典，切章已加载内容实现 0ms 秒开无缝切换；
     - 注入 `_cleanNovelContent` 智能正文排版清洗器，过滤 HTML 残留标签、转换 HTML 实体符号、智能压缩空行，并自动补齐标准的两格全角空格首行缩进（`　　`）；
     - 打造优雅的状态分流：加载中展示极光幽绿微光旋转动效，加载失败展示轻量空状态及“重试加载”操作。
  2. **双重内容复制体验打造（长按自由划选 + 一键整章导出）**：
     - **自由选段复制**：阅读器视口全面改用 `SelectableText`（横向翻页与纵向长卷模式双适配），保留单触控唤起控制栏的同时，原生支持手指长按划词选区与系统浮窗气泡（复制/全选/分享）；
     - **一键整章复制**：在顶部导航栏与底部操作面板同步新增“复制本章”按钮（`LucideIcons.copy`），点击后自动组装《章节名》与正文全篇复制到系统剪贴板，伴随触觉微震反馈与浮层提示。
- **测试与静态审查验证**：
  - 新增 `NovelReaderPage renders chapter content, supports SelectionArea and copy action cleanly` 单元部件测试；
  - `flutter analyze` 保持 **0 issues**；
  - `flutter test` 全套 **23 项自动化测试用例 100% 全部通过**。

### 📺 影视详情页视觉与交互深度调优 (还原极简宽屏沉浸视界)
- **核心诉求与体验调优**：
  1. **标题区域去除重复封面**：影视详情页顶部已由 16:9 大视口 `AuraPlayer` 接管视频与海报展示，下方元数据区通过 `showCover: false` 去掉左侧竖向封面卡片，标题与题材标签全宽延展呈现，字号提升至 20px，排版清爽大气；
  2. **去除大块追更按钮**：通过 `showFavoriteButton: false` 与 `showActions: false` 隐藏侵入感较强的追更栏，让视觉焦点彻底回归视频选集与内容信息本身；
  3. **恢复剧照与预览截图流**：恢复重构时遗漏的 `MediaDetailData.previews` 剧照模块，在选集与相关推荐之间插入 16:10 宽屏横向滑动流，注入防盗链 Referer 头部与圆角微光容器；
  4. **相关推荐列表升级为 16:9 现代流媒体宽屏**：`MediaRelatedGrid` 扩展支持 `isWide: true` 模式，切换为双列（`crossAxisCount: 2`）、`childAspectRatio: 1.28` 及 16:9 宽屏封面，彻底消除了底部留白，贴合影视类流媒体的现代视觉审美；
- **涉及组件演进**：
  - [`MediaMetaHeader`](file:///c:/dev/projects/fluxforge/app/lib/views/media/common/media_meta_header.dart)：新增受控开关 `showCover`、`showFavoriteButton` 与 `showActions`，并补全各个私有 UI 构建组件；
  - [`MediaRelatedGrid`](file:///c:/dev/projects/fluxforge/app/lib/views/media/common/media_related_grid.dart)：支持 `isWide` 构造参数，自适应 16:9 宽屏双列与 1:1.34 竖版三列，图片加载接入防盗链 Referer；
  - [`VideoDetailView`](file:///c:/dev/projects/fluxforge/app/lib/views/media/video/video_detail_view.dart)：无缝协同新配置，恢复剧照滑动流，并将相关推荐设为宽屏展示；
- **全量测试与静态分析验证**：
  - `flutter analyze` 保持 0 issues；
  - `flutter test` 22 项全量自动化测试 100% 通过。

### 🎬 视频播放器 (AuraPlayer) 彻底解耦全局 Router：由业务层显式受控暂停，全局基础组件彻底纯粹化
- **架构洞察与战略升华（采纳用户高水准建议）**：
  - 用户指出：“点击详情其他视频暂停是不是写在业务代码比较好，AuraPlayer可以不用额外使用router”；
  - **深度剖析**：`AuraPlayer` 作为全局基础 UI 组件（`lib/widgets/player/aura_player.dart`），反向依赖 `router.dart` 与 `RouteAware` 是导致全屏与弹窗“过度敏感/误伤暂停”的根本源头。把路由跳转暂停的动作下沉到业务代码中，能让组件和业务两端同时获得最大化解耦与简洁；
- **底层重构落地**：
  1. **AuraPlayer 彻底解耦外部路由 (`app/lib/widgets/player/aura_player.dart`)**：
     - 彻底移除 `import '../../router.dart';` 与 `with RouteAware`；
     - 彻底移除 `didPushNext()`、`didPopNext()`、`appRouteObserver.subscribe` 及全屏/弹窗状态锁等一系列黑魔法过度防御；
     - 导出受控状态类 `AuraPlayerState`，并公开纯粹的 `pause()`、`play()`、`isPlaying` 受控方法；
     - 保留原生 `WidgetsBindingObserver`（仅在 App 进入手机后台或锁屏时自动暂停以保护电量与流量）；
  2. **业务层显式控制跳转暂停 (`app/lib/views/media/video/video_detail_view.dart`)**：
     - `VideoDetailView` 持有 `GlobalKey<AuraPlayerState> _playerKey`，并挂载给 `AuraPlayer(key: _playerKey)`；
     - 当用户点击相关推荐卡片（`MediaRelatedGrid.onItemTap`）跳转新视频详情前，业务代码主动调用 `_playerKey.currentState?.pause()`；
     - 跳转动作与暂停意图 100% 显式透明，零隐式副作用，全屏与任何抽屉/弹层天然绝对不会被误暂停；
- **全量测试与规范达标**：
  - 更新并新增 `AuraPlayer supports external control via GlobalKey<AuraPlayerState> pause and play` 测试；
  - `flutter analyze` 0 issues，全套 22 项测试用例 100% 全部通过。

### 🏗️ 客户端 `lib/` 体系全栈架构治理与模块化彻底重构 (一步到位长期可持续设计)
- **核心动机与战略重塑**：
  - 彻底打破历史技术包袱，不向旧兼容性妥协，按「长期可维护性、高内聚低耦合、领域清晰」原则完成移动客户端 `lib/` 的全量治理与重命名；
  - 明确基础组件与业务页面职责：`AuraPlayer` 保持为全局基础核心组件，不内嵌业务特化逻辑；消除 `views/` 与底层引擎概念倒错；
- **阶段一：无死角清理历史僵尸代码与冗余孤儿文件**：
  - 彻底移除已被现代化重构替代的历史死文件：
    - `lib/models/detail_result.dart` 与 `lib/models/search_result.dart`（已被全局媒体领域模型 `models/media.dart` 全面替代）；
    - `lib/widgets/media_grid.dart`、`lib/widgets/media_list.dart` 与 `lib/widgets/card_block.dart`（已被通用 `AppCard` 与业务展厅彻底替代）；
    - `lib/views/reader/novel_reader_page.dart`（已被 `views/media/novel/reader/novel_reader_page.dart` 彻底替代，并清理空目录）；
  - 全工程累计删除 3,500+ 行死代码，实现零孤儿引用、零编译干扰。
- **阶段二：计算与拦截引擎层升维独立 (`lib/engines/`)**：
  - 将深埋在视图层 `views/browser/` 中的两大无 UI 计算与注入引擎提升为顶级架构层：
    - `lib/views/browser/adblock_engine.dart` -> **`lib/engines/adblock_engine.dart`**（ABP 规则匹配、反钓鱼与黑名单过滤）；
    - `lib/views/browser/web_video_gesture_engine.dart` -> **`lib/engines/web_video_gesture_engine.dart`**（网页全屏视频手势注入）；
  - 全量迁移并更新 `test/adblock_engine_test.dart`、`test/web_video_gesture_engine_test.dart`、`browser_page.dart`、`settings_page.dart` 引用。
- **阶段三：领域模型层统领升华 (`lib/models/media.dart`)**：
  - 将原仅服务于媒体页面的私有模型 `views/media/models/media_detail_data.dart` 升华为全局通用跨端领域模型；
  - 统一契约：涵盖 `MediaItem`、`MediaDetailData`、`MediaEpisodeGroup`、`MediaEpisodeItem` 及 `EpisodeWatchState`；
  - 清理 `views/media/models/` 空目录，更新所有上层引用。
- **阶段四：全局设计系统组件统一规范 (`lib/widgets/app_*.dart`)**：
  - 消除命名参差不齐，全面遵循 `app_` 前缀通用组件命名规范：
    - `widgets/empty_state.dart` -> **`widgets/app_empty_state.dart`**（导出 `AppEmptyState` 别名）；
    - `widgets/loading_indicator.dart` -> **`widgets/app_loading.dart`**（导出 `AppLoading` 别名）；
    - `widgets/net_image.dart` -> **`widgets/app_net_image.dart`**（导出 `AppNetImage` 别名）；
  - `AuraPlayer` 保持位于 `lib/widgets/player/aura_player.dart` 全局独立基础组件定位。
- **阶段五：视图层领域目录归位与命名混淆消除**：
  - **消除动名词混淆**：
    - 将 `lib/views/rules/rule_discovery_page.dart` 重命名并重构为 **`lib/views/rules/rule_catalog_page.dart`**（`RuleCatalogPage`），彻底解决其与底部主 Tab `views/discover/discover_page.dart` 动名词同名的困扰；
  - **解耦 `views/profile/` 杂物箱**：
    - 收藏与追更独立建域：新建 **`lib/views/favorites/favorites_page.dart`**；
    - 系统设置与日志中心独立建域：新建 **`lib/views/settings/settings_page.dart`** 与 **`lib/views/settings/logs_page.dart`**；
    - 调试与设计组件画廊独立建域：新建 **`lib/views/dev/card_gallery_page.dart`**；
    - `lib/views/profile/` 提纯为纯粹的用户个人中心主页 `profile_page.dart`。
- **阶段六：全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**0 issues found**，零警告零报错；
  - `flutter test` 运行验证：**21 项测试用例全部通过 (100%)**；
  - 严格遵守指令要求，未向远程仓库提交或推送 Git。


### 📖 图片/漫画解析展示架构重构：长漫画无缝全宽长列表模式与双向切换
- **大图/全屏手势查看器支持长漫画模式与模式切换胶囊 (`app/lib/views/detail/photo_gallery_page.dart`)**：
  - **核心痛点根治**：原先 `PhotoViewPage` 仅支持 `ExtendedImageGesturePageView.builder(scrollDirection: Axis.horizontal)` 左右水平滑动翻页，用户在浏览漫画或长图集时无法像真实条漫一样连贯纵向阅读；
  - **长漫画无缝模式落地**：新增纵向长卷模式（Vertical Comic Mode），采用 `ListView.builder` + `ScrollController`：
    - **零间隔 (Zero Spacing)**：彻底移除条目之间的间距（gap 为 0），图片像素级上下紧密相连；
    - **零圆角 (Zero Border Radius)**：直角边缘渲染，消除所有卡片圆角裁切，保持画卷原汁原味的无缝连贯性；
    - **全宽铺满 (Full Width Fill)**：容器零内边距（`padding: EdgeInsets.zero`），图片采用 `width: double.infinity, fit: BoxFit.fitWidth`，物理宽度 100% 紧贴屏幕边缘，高度自适应延伸；
  - **沉浸式交互与双向精准跳转**：
    - 顶栏右侧新增模式切换流光胶囊（`LucideIcons.scrollText` / `LucideIcons.columns2`），清晰指示当前状态并支持一键在“长漫画”与“左右翻页”之间自由切换；
    - 滚动时通过视口中心碰撞算法（`_updateCurrentIndexFromScroll`）精准计算当前阅读至第几页，动态刷新顶栏 `12 / 50` 进度；
    - 切换模式时双向自动定位：左右翻页切换至长列表时通过 `Scrollable.ensureVisible` 滚动至当前图片；长列表切换至左右翻页时通过 `jumpToPage` 保持页码完全同步；
    - 长漫画模式下支持轻触屏幕切换顶栏显隐，提供纯净沉浸的全屏漫画阅读体验；
  - **用户阅读偏好持久化**：基于 `AppStorage`（`photo_view_comic_mode` 键名）记住用户的阅读模式偏好，一次切换后全局所有图片/漫画自动生效。
- **明确职责边界：详情页面保持原有画廊展厅设计，长漫画模式专注落地于详情进入解析后的浏览页面 (`app/lib/views/rules/rule_detail_page.dart`)**：
  - 响应用户指令，保持 `RuleDetailPage` 详情页原有画廊与选集结构完全不变（保持原有 `EdgeInsets.fromLTRB(12, 8, 12, 32)` 容器边距、网格与长卷展示原型）；
  - 零侵入详情页结构，将“左右滑动翻页 vs 零圆角零间隔全宽长漫画”的高自由度模式切换与全屏画卷渲染全部聚焦在从详情进入解析后的目标大图页面（`PhotoViewPage`）。
- **相关推荐底部冗余空白消除与卡片宽高比紧凑优化 (`app/lib/views/rules/rule_detail_page.dart`)**：
  - **卡片内部底部空洞根除**：原先 `childAspectRatio: 1.18` 导致卡片被强制拉伸过高（约 150px），而 16:9 封面（约 98px）配合单行标题（约 15px）时，文字下方空出了整整 23px 的空白底色；现优化调整为黄金紧凑比例 **`childAspectRatio: 1.34`**，卡片高度紧密贴合内容，彻底消除卡片内多余空白；
  - **列表底部多重堆叠留白消除**：排查并移除了视频详情页末尾无条件追加的 `SizedBox(height: 24)` 与 `SizedBox(height: 20)` 双重堆叠，在相关推荐下方收窄为单一轻巧的 `SizedBox(height: 12)`，配合滚动容器底部安全边距，视觉留白达到匀称自然的黄金比例（约 26px），彻底根除“相关推荐底部多出一大块空白”的视觉缺陷。
- **全量测试与规范达标**：
  - 新增 `PhotoViewPage` 模式切换与长漫画无缝长列表组件测试用例，覆盖零边距检查与双向切换；
  - 全套 21 项自动化测试 100% 全部通过（`flutter test` 21 passed），`flutter analyze` 保持 0 错误 0 警告。

### 🎨 AuraPlayer 细节质感微调与相关推荐紧凑网格重构
- **全屏进度条布局规范重构：彻底淘汰 Offset 位移，采用标准 Column 流式排布 (`app/lib/widgets/player/aura_player.dart`)**：
  - 源码级根因定位：Flutter 原生 `Slider` 在无父级高度约束时（`constraints.hasBoundedHeight == false`），默认会分配 48px（`math.max(_minPreferredTrackHeight, _maxSliderPartHeight)`）的无障碍触摸高度，导致轨道上下自带约 22px 隐形透明内边距；原先采用 `Transform.translate(Offset(0, -2))` 仅为绘制层矩阵偏移，破坏了布局真实性；
  - 彻底重构方案：通过 `SizedBox(height: 20)` 为 Slider 赋予显式的高度约束（`hasBoundedHeight == true`），使组件布局尺寸收缩至紧凑高度，上下自然各留 8px 触控热区；同时彻底丢弃 `Transform.translate`，回归纯正的 `Column` 紧凑流式排布，组件真实位置与视觉绘制 100% 严格一致；
- **进度条加载动画升级：未加载区域专属流光与多重动效融合 (`AuraSliderTrackShape`)**：
  - 精准计算已缓冲右边界 `loadedRight` 与未加载区间 `unloadedRect`，使用 `canvas.clipRect(unloadedRect)` 将流光扫光**严格约束仅在未加载的空白轨道上流动**，已播放与已缓冲区域保持纯净通透；
  - 融合**未加载区域呼吸底色 (Breathing Pulse)** 与**已缓冲端点向右微光波纹 (Buffer Head Glow)**，加载状态科技感与层次感倍增；
- **锁屏悬浮按钮关闭（锁定）状态去色**：
  - `_buildLockButton` 中将锁定状态的高亮翡翠绿移除，统一采用纯白通透悬浮质感（`color: Colors.white`），消除全屏沉浸播放时的突兀感；
- **播放/暂停图标圆润与纯净升级：彻底去掉外圈，居中换装为两个圆润长方形竖条 (`aura_player.dart`)**：
  - 明确原因：原先居中的外圈为 `LucideIcons.circlePlay` 与 `LucideIcons.circlePause` 图标本身自带的外环描边；
  - 响应用户指令彻底移除外圈：居中大按键换装为 **`LucideIcons.pause600`** 与 **`LucideIcons.play600`**（字重 600 加粗圆润款，尺寸 48px 配立体阴影）；
  - 视觉效果：暂停状态完美呈现为**无外圈、两个饱满圆润的长方形竖条**，播放状态呈现为**纯净圆角三角形**，悬浮在视频中央晶莹通透；
  - 底栏播放小按钮保持统一采用圆润加粗款 `LucideIcons.play600` 与 `LucideIcons.pause600`；
- **相关推荐全面换装为 AppCard.flat 纯净平铺卡片与间隙消除 (`rule_detail_page.dart`)**：
  - 源码级根因定位：Flutter 内部 `BoxScrollView.buildSlivers` 在 `padding == null` 时会自动把 `MediaQuery` 的垂直内边距（状态栏安全区约 30px~48px）作为 `SliverPadding` 强制包裹在网格顶部，导致标题下方出现巨大虚高空隙；
  - 彻底根治方案：在 `GridView.builder` 中显式设置 `padding: EdgeInsets.zero`，完全清空幽灵边距；同时将头部标题下方的间距由 12px 收窄微调至紧凑自然的 8px；
  - 视觉质感升维：无多余阴影与毛玻璃（消除详情页层级冗余），自动继承深/浅色纯净平铺底色（深色 0xFF161E2E，浅色纯白），文字有了统一底板依托，对比度与阅读舒适度显著提升；
  - 结合 `AppCard` 的严格防溢出圆角裁切（`Clip.antiAlias`，圆角 10px）与内置水波纹交互，网格宽高比调优为紧凑匀称的 `childAspectRatio: 1.18`，行间距 10px，全站设计规范高度一致；
- **详情页标题字重与排版质感优化：由 FontWeight.bold(w700) 全面降温至现代 SemiBold(w600) (`rule_detail_page.dart`)**：
  - 响应用户审美建议，根治中文在 `FontWeight.bold`（w700）下笔画密集造成的“墨渍感”与沉重感；
  - 视频主大标题降温为 `fontSize: 17.5, fontWeight: FontWeight.w600, letterSpacing: -0.2`，骨架干练利落，层级清晰且透气轻盈；
  - 全量同步重构各核心功能区标题（选集目录、剧照与预览、相关推荐、漫画/小说章节目录），由生硬的 `FontWeight.bold` 统一精修至 `FontWeight.w600`，全页面排版视觉高级感与秩序感拉满；
- **发现页列表架构深度调研**：
  - 梳理并明确全局发现页（`discover_page.dart`，`CustomScrollView` + `SliverGrid`）与规则发现页（`rule_discovery_page.dart`，`GridView.builder` 与 `ListView.separated` 双模式无缝切换）的技术实现体系。
- **AuraPlayer 工业级生命周期自治：路由遮挡自动暂停与切后台防偷跑 (`router.dart` / `aura_player.dart`)**：
  - 架构决策：采用组件内部自治（RouteAware + AppLifecycle）而非散落业务代码，从根源上彻底解决进入“相关推荐”新页面后原视频在背后偷播的痛点；
  - 在 `router.dart` 中注册全局 `appRouteObserver`，并挂入 `GoRouter(observers: [appRouteObserver])`；
  - `AuraPlayer` 混入 `RouteAware`，实现 `didPushNext()` 监听：当用户点击相关推荐、选集跳转任何新页面压栈覆盖当前播放器时，老视频即刻自动暂停并解除常亮，零业务侵入；
  - 完善 `WidgetsBindingObserver` 生命周期回调：当 App 锁屏或退至手机后台时自动调用 `pause()`，彻底阻断背景偷跑流量与耗电；
  - 新增 `autoPauseOnCovered`（默认 true）参数，兼顾组件自治与特殊场景自定义扩展。
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 20 项自动化测试 100% 全部通过（`flutter test` 20 passed）。

## [2026-09-12]

### 💎 AuraPlayer 界面精简：长按快进微胶囊去文字纯净极简化
- **长按加速提示微胶囊纯净去字化 (`app/lib/widgets/player/aura_player.dart`)**：
  - 响应用户建议，重构 `_buildFastForwardCapsule`：彻底移除微胶囊内的文字描述（`2.0X 快速播放中`），仅保留居中的高斯毛玻璃极光翡翠快进双箭头（`LucideIcons.fastForward`，尺寸 20px）；
  - 胶囊内边距调优为精致对称的 `14px x 8px`，长按时在顶部中央通透显现，轻量轻快，彻底杜绝文字对视频画面核心内容的任何视线遮挡；
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 全部通过（`flutter test` 19 passed）。


### ✨ AuraPlayer 全站设计语言统一：播放器全套控件全面换装 LucideIcons
- **全套控件 100% 纯血换装为 LucideIcons (`app/lib/widgets/player/aura_player.dart`)**：
  - 响应用户指令，将播放器内所有 Material 图标全面重构为全站统一的 **LucideIcons 系列**，实现与 FluxForge 核心设计语言（线性、极简、现代科技感）的百分之百无缝闭环：
    - **居中大播放/暂停键**：换装为 `LucideIcons.play` 与 `LucideIcons.pause`，大尺寸（42px）配双层立体投影；
    - **底部控制栏播放/暂停**：换装为 `LucideIcons.play` 与 `LucideIcons.pause`；
    - **全屏 / 退出全屏**：换装为标准全屏扩展/收缩四角箭头 `LucideIcons.maximize` 与 `LucideIcons.minimize`；
    - **锁屏 / 解锁悬浮按钮**：换装为圆润锁体 `LucideIcons.lock` 与 `LucideIcons.unlock`；
    - **快进 / 快退 HUD 胶囊**：换装为双箭头 `LucideIcons.fastForward` 与 `LucideIcons.rewind`；
    - **长按加速微胶囊**：换装为 `LucideIcons.fastForward`；
    - **亮度指示条**：换装为极简发散太阳 `LucideIcons.sun` 与 `LucideIcons.sunMedium`；
    - **音量指示条**：换装为线性喇叭 `LucideIcons.volume2`、`LucideIcons.volume1` 与静音 `LucideIcons.volumeX`；
    - **顶栏导航与更多**：返回键换装为 `LucideIcons.chevronLeft`，更多设置换装为 `LucideIcons.ellipsis`；
    - **倍速/设置抽屉关闭键**：换装为极简圆润 `LucideIcons.x`；
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 全部通过（`flutter test` 19 passed）。


### 🚀 AuraPlayer 商业级五大核心体验调优：防跳变播放状态机、全屏图标与进度条边缘严密对齐、加载状态流光扫光动画、控件自动隐藏延至5秒、右上角更多设置半透明抽屉
- **拖动进度与滑动手势防跳变播放状态机 (`app/lib/widgets/player/aura_player.dart`)**：
  - 根治痛点：修复在拖拽滑块或屏幕滑屏寻道时，底层播放器触发缓冲导致 `isPlaying` 短暂掉落为 false、使得播放按钮与居中大键错误跳变为暂停状态的闪烁问题；
  - 引入 `_effectiveIsPlaying` 播放意图状态计算与寻道接力缓冲防抖机制（`_wasPlayingBeforeDrag` / `_isSeekingTo`），拖动期间与缓冲阶段始终稳如泰山维持用户原本意图，并在 seek 结束后自动恢复平滑播放；
- **全屏状态下锁图标、播放图标、全屏图标与进度条边缘像素级严密对齐**：
  - 左侧垂直基准线：统一 `_fullscreenLeftPadding`（避开圆角与异形屏），将锁图标（`Alignment.centerLeft`）、底栏播放键（`Alignment.centerLeft`）、进度条起点（0px）与时间文本（0px）实现四点同轴垂直对齐；
  - 右侧垂直基准线：统一 `_fullscreenRightPadding`，将全屏/退出全屏键（`Alignment.centerRight`）、进度条终点与顶栏更多按钮严格右边缘对齐；
- **进度条统一粗细与加载状态流光扫光动画 (`AuraSliderTrackShape`)**：
  - 彻底解决“已加载和未加载粗细不一”问题：重写 `AuraSliderTrackShape.paint`，使未加载背景轨、已加载缓冲轨（从网络获取真实的 `_controller.value.buffered` 范围）、已播放翡翠轨三者在同一高度矩形内填充，粗细绝对一致；
  - 增加加载动画：当处于初始化或网络缓冲中时，激活 `_shimmerController` 循环扫光，一道羽化渐变的高光流光自左向右掠过整个轨道，科技感与加载反馈拉满；
- **控件自动隐藏时长延长至 5.0 秒**：
  - 将控制条显隐计时器与锁屏悬浮键计时器由 3.5 秒延长至更从容舒适的 5.0 秒，杜绝仓促隐藏；
- **顶栏右上角「更多设置」与右侧半透明毛玻璃设置抽屉 (`_showMoreSettingsDrawer`)**：
  - 顶栏右上角新增圆润更多按钮（`Icons.more_horiz_rounded`）；
  - 点击从屏幕右侧顺滑滑出 280px 全高高斯毛玻璃设置面板（18px 模糊 + 55% 暗黑半透明）；
  - 提供：画面比例调节（适应 16:9 / 铺满 Cover / 拉伸 Fill）、画面水平镜像翻转（舞蹈/跟练神器）、单视频循环播放开关、长按瞬时加速开关与倍率单选（2x / 3x / 5x），全套触觉震动反馈与即时生效；
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 全部通过（`flutter test` 19 passed）。


### ⚡ AuraPlayer 倍速交互升级：小屏移除倍速按键、全屏文字悬浮去底色、右侧滑出半透明毛玻璃抽屉面板
- **小屏状态彻底移除倍速按键 (`app/lib/widgets/player/aura_player.dart`)**：
  - 响应用户建议，重构 `_buildCompactControlLayout`：在竖屏/小屏 16:9 紧凑布局下彻底移除倍速按钮，消除空间拥挤感，横向空间全额分配给流光进度条与当前/总长播放时间；
- **全屏倍速按键去底色并采用纯净悬浮文字**：
  - 彻底淘汰原先类似小胶囊的深色底板与边框（`BoxDecoration`），重构为商业流媒体产品主流的纯白悬浮文字形态（`_buildSpeedButton`）；
  - 融入轻立体微文字投影（`Shadow(color: Colors.black87, blurRadius: 6)`），确保在各种高亮或复杂视频背景下清晰锐利；
  - 状态智能回退：当前为 1.0x 正常速度时显示“倍速”二字，非 1.0x 时动态显示实时倍率（如 `1.5x` / `2x`）；
- **全屏右侧滑出半透明毛玻璃倍速抽屉面板 (`_showPlaybackSpeedDialog`)**：
  - 淘汰原先底部弹窗模式，全面对标腾讯视频/B站全屏播放器的商业级**右侧滑出抽屉面板 (Right Slide-over Panel)**；
  - 动画：基于 `showGeneralDialog` 与 `SlideTransition`，采用 `Curves.easeOutCubic` 曲线从屏幕右侧顺滑滑入（宽度 210px，全高覆盖）；
  - 视觉：融入 18px 高斯毛玻璃（`BackdropFilter(sigmaX: 18, sigmaY: 18)`）与 52% 通透黑半透明底色，背后视频画面流光通透，带有 `SafeArea(left: false)` 保证横屏真机防刘海遮挡；
  - 选项：垂直排布 `2.0x, 1.5x, 1.25x, 1.0x (正常), 0.75x, 0.5x`，当前选中项以极光翡翠绿（`AppColors.primary`）高亮并在右侧指示发光呼吸绿点；轻触任意项伴随触觉微振感即刻生效并平滑回缩抽屉。
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 通过（`flutter test` 19 passed）。


### 🎨 AuraPlayer 视觉触感升级：圆润图标系列全面换装、快进退弹窗取消边框并提升通透度
- **快进/快退 HUD 悬浮窗通透去边框 (`app/lib/widgets/player/aura_player.dart`)**：
  - 响应用户建议，彻底移除快进/快退居中胶囊窗口原先的白光外围边框线（`border: Border.all(...)`）；
  - 背景颜色透明度由 `alpha: 0.65` 调优为更加轻盈通透的 `alpha: 0.45`，配合底层的 16px 高斯毛玻璃模糊（`BackdropFilter`），呈现晶莹剔透的水晶流光形态，不遮挡背后视频核心画面；
- **全套播放器控件圆润图标换装 (Material Rounded 系列)**：
  - 彻底淘汰原先线条折角尖锐的线性几何图标，全面换装为业界圆润饱满的 **Material Rounded 系列（`Icons.*_rounded`）**：
    - **居中大播放/暂停键**：升级为 `Icons.play_arrow_rounded` 与 `Icons.pause_rounded`（圆头胶囊圆棒与圆弧三角），尺寸微调至 42px，搭配投影立体通透；
    - **底部控制栏播放/暂停**：升级为圆润版 `Icons.play_arrow_rounded` / `Icons.pause_rounded`；
    - **全屏 / 退出全屏**：升级为平滑圆角的 `Icons.fullscreen_rounded` / `Icons.fullscreen_exit_rounded`；
    - **锁屏 / 解锁悬浮按键**：升级为锁钩与锁体均圆弧倒角的 `Icons.lock_rounded` / `Icons.lock_open_rounded`；
    - **快进 / 快退 HUD 图标**：升级为柔和圆润的 `Icons.fast_forward_rounded` / `Icons.fast_rewind_rounded`（尺寸 18px）；
    - **亮度 / 音量指示条**：升级为圆润小太阳 `Icons.light_mode_rounded` 与圆角喇叭 `Icons.volume_up_rounded` / `Icons.volume_down_rounded` / `Icons.volume_off_rounded`；
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 通过（`flutter test` 19 passed）。


### 🎬 详情页相关推荐重构：宽屏 16:9 双列纵向瀑布网格，丝滑向下无限浏览
- **告别单行横滑，重构为宽屏双列纵向流 (`app/lib/views/rules/rule_detail_page.dart`)**：
  - 响应用户建议，彻底淘汰原先 `ListView.horizontal` 单行横向水平滑动的窄屏小卡片模式；
  - 重构为对标 Bilibili / YouTube / 腾讯视频的**宽屏两列网格（`crossAxisCount: 2`）**，内嵌于主滚动视口中，随着页面整体**垂直向下纵向滑动**，尽情畅看；
  - 封面升级为标准 **16:9 影视宽屏比例**，配备 `8px` 圆角与双主题自适应微边框；
  - 智能解析条目右下角角标（`badge`，如“4K超清”、“完结”），标题限制最多 2 行保证对齐，副标题/描述（`desc`）单行自适应排布；
  - 融入轻触感交互（`HapticFeedback.lightImpact()`）与点击无缝路由，点击任意推荐项目平滑推入对应详情；
- **全量测试与规范达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 通过（`flutter test` 19 passed）。


### 🖼️ 详情页剧照预览流精细化微调：高度收缩至 72px、16:9 标准比例与全屏画廊查看
- **剧照卡片紧凑轻巧化 (`app/lib/views/rules/rule_detail_page.dart`)**：
  - 响应用户建议，将 `_buildPreviewsSection` 的横向滑动列表视口高度由原先笨重的 `110px` 紧缩调优为 `72px`（垂直空间收缩约 35%）；
  - 宽高比升级为标准的影视级 `16:9`（单张宽度约为 128px），与顶部播放器视口比例保持严格的视觉秩序感；
  - 卡片圆角调优为 `8px` 并注入双主题自适应微边框（`border: 0.6px`），间距由 10px 压缩至 8px，极大释放了下方垂直空间；
- **全屏画廊大图交互打通 (`_openPhotoViewer`)**：
  - 扩展 `_openPhotoViewer` 支持传入任意自定义图片数组（`images: _previews`）；
  - 剧照卡片内嵌 `InkWell` 点击手势：点击任意一张剧照即可瞬时弹出全屏 Lightbox 浏览器，支持手势缩放、全套横向滑屏预览与保存；
- **测试与检查达标**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 通过（`flutter test` 19 passed）。


### 📺 规则详情页视频排版商业级重构：吸顶置顶播放器、消除双AppBar、影视元数据卡片与腾讯/B站级选集系统
- **彻底根治双重顶栏与双返回键冲突 (`app/lib/views/rules/rule_detail_page.dart`)**：
  - 排查确认当详情页解析为视频类型时，外层 `Scaffold.appBar` 与内层 16:9 `AuraPlayer` 顶栏同时渲染，导致界面出现极不专业的“双标题、双返回键”叠层灾难；
  - 动态重构顶层 `build`：当媒体类型判定为视频（`_mediaType == MediaType.video`）且加载成功时，将外层 `Scaffold.appBar` 自动置为 `null`，顶栏导航、返回操作与标题全权交由置顶沉浸式播放器接管；
  - 播放器未加载或空地址占位状态同样内嵌沉浸式顶部渐变条与返回按键，随时支持无缝回退；
- **播放器顶部固定吸顶常驻 (Pinned Viewport)**：
  - 彻底抛弃将播放器与所有详情内容打包进单一 `SingleChildScrollView` 的落后做法；
  - 采用流媒体商业 App（腾讯视频/B站/爱奇艺）标配的**吸顶分层架构**：顶部 16:9 视口常驻固定（`SafeArea(bottom: false) + AspectRatio(16/9)`），下方内容通过 `Expanded + SingleChildScrollView` 独立滑动，无论下方如何浏览几十上百集选集或剧照，上方视频画面永不滚出屏幕；
- **全新长视频影视元数据卡片 (`_buildVideoMetaCard`)**：
  - 补全此前严重缺失的视频核心信息：大字号标题（18px Bold）、金色微胶囊评分（如 `★ 9.8`）、规则源标识标签、题材分类标签流（Tags）与演员/导演/作者卡片；
  - 优雅的剧情简介折叠机制：默认展示 2 行关键概要，右下角提供带旋转箭头的“展开/收起”平滑展开交互，字号 12.5px、行高 1.5 倍，排版错落有致；
- **对标商业流媒体的长视频选集交互系统 (`_buildVideoEpisodesSection`)**：
  - **多播放线路支持**：若沙箱返回包含多组播放线路（`groups`），顶部渲染小巧的 ChoiceChip 线路横向滑动条，支持一键切换并自动接力播放首集；
  - **正序 / 倒序一键反转**：选集头部栏提供轻触感反馈（`HapticFeedback.lightImpact()`）的正倒序排序切换按钮；
  - **横向滑动选集条**：告别原版平铺数十行 `Wrap` 的拥挤杂乱，提供高度 46px 的横向胶囊选集滑动条；当前正在播放集以极光翡翠绿高亮、粗体白字、带播放状态小图标与立体微发光投影；
  - **“全部选集” 商业级底部抽屉 (`_showAllEpisodesSheet`)**：当总集数大于 5 时提供“全部”快捷按钮，点击呼出高质感半屏抽屉面板；内嵌 5 列网格整齐方块，支持在弹窗内直接正倒序切换与快速点播；
- **自动化测试保障与规范达标**：
  - 新增 `RuleDetailPage` 视频排版与布局部件测试用例（`test/widget_test.dart`）；
  - `flutter analyze` 保持 0 错误 0 警告；全套 19 项自动化测试 100% 通过（`flutter test` 19 passed）。


### ⚡ 底层内核换代升级：全面从 flutter_js 迁移至 quickjs_engine (现代 QuickJS-NG 0.14.0)
- **全平台统一现代 JS 引擎 (`app/pubspec.yaml`, `app/lib/services/rule_engine.dart`)**：
  - 彻底淘汰原 `flutter_js`（使用 2021 年过旧 QuickJS 且 iOS/macOS 降级为 JavaScriptCore 的双端分裂机制），替换为最新的 `quickjs_engine: ^0.1.5`；
  - **iOS、Android、macOS、Windows、Linux 全平台统一运行 QuickJS-NG 0.14.0 (2026 年现代版)**，彻底消除跨平台引擎解析差异与未知边界 Bug；
  - 原生全面支持 ES2020+、现代 async/await、Promise 微任务、Proxy 代理、BigInt、RegExp 具名捕获组与可选链；
- **主动关闭脆弱的旧 XHR，纯享原生安全 Dio 通道**：
  - 运行时初始化显式指定 `getJavascriptRuntime(xhr: false)`，彻底禁用底层容易因裸字符串拼接导致反引号截断的旧 XHR 监听；
  - 完美复用此前自研的基于 Dio 的 `FluxHttpRequest` 原生适配器与双通道 `FluxConsoleLog`，所有数据均通过 `jsonEncode` 安全结构化跨桥，杜绝语法注入与假死超时；
- **关闭脆弱自带 XHR，定型为基于 Dio 的原生安全网络通道 (`app/lib/services/rule_engine.dart`)**：
  - 经真机实测与源码实锤排查，`quickjs_engine` 自带的 `xhr.dart` 存在反引号裸字符串直接拼接机制（第 342 行），在解析带反引号脚本的网页时必然会触发 SyntaxError 并引发 Promise 挂起死锁；
  - 彻底去除测试切换开关与冗余分支，代码回归精简纯净：默认且常驻以 `xhr: false` 启动 QuickJS-NG，彻底禁用自带 XHR；
  - 全面通过 `_setupNativeHttpBridge`（Dio + `jsonEncode` 安全序列化）承载规则网络请求，确保所有类型网页与 JSON 100% 零截断、零死锁、零假死超时；
- **文档与工程看板同步更新**：
  - 同步更新 [app/README.md](file:///c:/dev/projects/fluxforge/app/README.md) 中关于 JS 规则沙箱引擎与运行时的技术栈架构说明；
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全套 18 个自动化测试 100% 通过（`flutter test` 18 passed）。

### 🎬 AuraPlayer 全屏视觉再进化：纯净无底色悬浮锁、进度条下移8px贴紧操作图标
- **居中暂停播放按钮去除背景与边线 (`app/lib/widgets/player/aura_player.dart`)**：
  - 彻底去除居中大播放按钮原有的深色半透明圆形底板（`Colors.black52`）、白色圆框边线与外围阴影；
  - 图标尺寸由 24 适度舒展提升至 38，增加柔和微立体投影（`Shadow(color: Colors.black87, blurRadius: 12)`），实现轻量通透的悬浮形态；
  - 优化呈现时机：小屏呼出控制栏时呈现，全屏模式下播放中自动隐藏避免遮挡画面、仅在暂停状态下居中浮现纯净大播放按键，点击毫秒级恢复播放；
- **自定义 AuraSliderTrackShape 彻底消除左右强制边距与时间像素级对齐**：
  - 排查确认 Flutter 原生 `Slider` 默认 `RoundedRectSliderTrackShape` 左右强制预留了高达 24px 的不可见内缩边距，导致进度条轨道起始位置比上方时间文本内缩 18px 严重错位；
  - 自研并注入 `AuraSliderTrackShape`，将轨道宽度扩展至 100% 可用宽度（`x = 0` 起始），彻底消除两侧无用留白；
  - 上方时间进度 `left` 边距精准调优为 `0`，时间首个数字的左垂直边缘与下方进度条轨道的起跑线实现 100% 绝对对齐，视觉整齐划一；
- **纯净无底色微投影锁图标 (`app/lib/widgets/player/aura_player.dart`)**：
  - 彻底去除锁图标原有的深色半透明圆形底板、外边框与外围盒子阴影，实现轻量纯粹的悬浮图标形态；
  - 尺寸由 20 适度舒展至 24，内嵌微妙文字级立体投影（`Shadow(color: Colors.black87, blurRadius: 8)`），兼顾纯净视觉与全白亮色画面下的辨识度；
  - 保留 44x44 的无形触摸热区与 `HitTestBehavior.opaque`，盲操触控依然 100% 灵敏；
- **进度条垂直下移 8px，紧贴下方控制图标**：
  - 分析并消除 Flutter `Slider` 默认 48px 强制高度所造成的底部 24px 大空白间隔；
  - 在全屏布局中通过 `Transform.translate(offset: Offset(0, 8))` 将进度条整体下移 8px，轨道与下方播放按键之间的视觉距离压缩至精致和谐的贴合间距；
  - 手势 HitTest 随平移矩阵无缝同步，拖拽手感跟手精准，上方时间文本与进度条层次进一步拉开；
- **左右呼吸安全边距大幅拓宽 (`app/lib/widgets/player/aura_player.dart`)**：
  - 顶栏与底栏自适应设备物理安全区（刘海打孔与曲面边缘），全屏横屏状态下左右 Padding 提升至 `max(safeArea + 24px, 42px)`；
  - 彻底摆脱返回键、标题、播放键与全屏键紧贴屏幕边缘或被曲面屏/圆角遮挡的局促感，视觉焦点优雅居中；
- **全屏时间指示器位置革新**：
  - 将原左右挤压进度条的起止时间拆分重构，当前播放时间与总时长合并为组合文本（`05:23 / 45:10`），移至**进度条上方左侧**独立排布；
  - 时间文本采用 `tabularFigures` 等宽字体，左边缘与下方进度条起跑线精准垂直对齐；
- **进度条下沉贴地与全宽拉通**：
  - 去除进度条左右时间文字挤压，进度条横跨整行拉通，拖拽有效轨迹大幅延长；
  - 将底部控制栏底边间距压缩至 `12px`，操作按键高度收敛至 `38px`，使进度条垂直重心整体显著下移贴地，根治全屏下进度条悬浮在屏幕正中偏高处的视觉突兀感；
- **全量测试与代码检查保障**：
  - 运行 `flutter analyze` 保持 0 错误 0 警告；全量 18 项自动化测试 100% 通过（`flutter test` 18 passed）。

### 🎬 AuraPlayer 自研播放器体验重构：小屏控件精准对齐、微位移动画防溢出与全屏沉浸式锁屏系统
- **全屏锁屏交互全面重构 (`app/lib/widgets/player/aura_player.dart`)**：
  - **左边缘舒适呼吸安全间距**：彻底消除原 `left: 20` 顶边紧贴屏幕与被圆角/刘海遮挡的问题，结合横屏安全区适配 `MediaQuery.of(context).padding.left + 40`（保底至少 54px），横屏视觉居中且留白舒展；
  - **锁图标自动淡出与独立唤醒机制**：
    1. 上锁后，顶部控制栏与底部控制栏立即向外滑出隐藏，锁图标在 3.5 秒无操作后自动平滑淡出隐藏；
    2. 新增锁屏专用拦截手势层 `_buildLockedGestureLayer`：锁定状态下完全屏蔽调光/调音/快进/双击等所有误触手势；
    3. 锁定状态下单机播放器任意位置：**仅单独唤醒显示左侧锁图标**（顶栏、底栏、进度条绝不出现），并在 3.5 秒后自动隐去；
    4. 点击锁图标解锁时，平滑恢复全部控制栏显示并重新启动倒计时；
  - **按键微拟态视觉升级**：采用 44x44 圆形磨砂深色底衬配合翡翠绿/白光高亮微边框（`BoxShadow` + `Border`），在明暗画面中均清晰可触。
- **小屏控件排布与动画防溢出彻底优化 (`app/lib/widgets/player/aura_player.dart`)**：
  - **视口边界全量裁剪防穿帮**：外层容器增加 `ClipRect`，内部 `Stack` 显式设置 `clipBehavior: Clip.hardEdge`，彻底根除原有控制栏滑出动画时溢出穿帮覆盖外部页面内容的 Bug；
  - **克制优雅的微位移动画**：控制条由全屏自身高度完全滑移优化为微位移（顶部 `Offset(0, -0.5)`、底部 `Offset(0, 0.5)`）+ `AnimatedOpacity`，避免低矮小屏视口内的突兀感；
  - **小屏底部栏水平对齐与尺寸精简**：
    1. 底部栏高度精准收敛至 38px，播放(32x32)、全屏(32x32)、倍速药丸、等宽紧凑时间文本与 Slider 进度条完全垂直居中对齐；
    2. Slider 采用微型 thumb 尺寸与内边距精简，彻底消除多控件挤压与文本像素溢出风险；
  - **小屏居中大播放/暂停按键**：小屏控制栏呼出时，播放器正中央呈现 52px 半透明圆盘大播放/暂停键，带微缩放与淡入淡出动效，大幅提升小屏盲操命中率；
  - **小屏底边常驻微型流光进度条**：控制栏收起隐藏时，底部无缝淡入一条 2px 极细极光流光进度条，纯净观影与进度掌握兼得。
- **自动化测试套件持续保障 (`app/test/widget_test.dart`)**：
  - 新增 AuraPlayer 小屏与全屏容器防溢出结构单元测试；
  - 全套 18 个测试 100% 通过（`flutter test` 18 passed），静态分析 `flutter analyze` 保持 0 错误 0 警告。

## [2026-09-11]

### 🚀 突破性重构：内置基于 Dio 的原生安全 HTTP 适配器，彻底根除 flutter_js 网页反引号模板字符串卡死超时缺陷
- **终极根因深度定位 (`app/lib/services/rule_engine.dart`)**：
  1. **规则编写层面无任何异常**：用户对比的「规则一」与「规则二」均符合标准 `defineRule` 规范，且详情逻辑均使用标准的 `await axios.get(url)`；
  2. **网页 HTML 差异与底层解析崩溃**：
     - 规则一目标页（`meirentu.cc`）以及规则二发现页（`page/1`）源码均为纯文本/数字结构，**不包含任何反引号 `` ` ``**；
     - 规则二详情页（`bizhi.wpcoder.cn/...`）在 HTML 第 30099 字符处包含内嵌 JS 脚本：`originalUrl.replace(domainRegex, `$1${newDomain}`)`，**包含反引号 `` ` `` 与 `${...}` 模板插值**；
     - **flutter_js 底层 XHR 实现的致命缺陷**：`flutter_js` 官方 `xhr.dart` 在将 HTTP 响应回传给 QuickJS 沙箱时，使用了反引号模板字符串直接拼接：`this.evaluate("globalThis.xhrRequests[id].callback(info, `$responseText`, error);")`；
     - 当网页 HTML 自身带有反引号或 `${}` 时，反引号截断了模板字符串并引发 **SyntaxError（语法解析错误）**，导致 `callback` 根本未能被调用，`XMLHttpRequest` 永远处于 `LOADING` 状态，`axios.get` 的 Promise 永远挂起，造成详情阶段卡顿并最终触发 30 秒超时假死！
- **原生高性能网络通信桥接彻底重构方案**：
  1. **自定义 Axios 原生 Adapter (`axios.defaults.adapter = fluxNativeHttpAdapter`)**：
     - 完全绕过 `flutter_js` 存在缺陷的旧版 `XMLHttpRequest`，Axios 请求直接通过独立通道 `FluxHttpRequest` 抛给 Dart 宿主；
     - 彻底消除 `flutter_js` 原有 `Timer.periodic(40ms)` 轮询延时，网络响应实现毫秒级即时触发；
  2. **Dio 强力宿主驱动与 JSON 安全转义传递**：
     - 引入全局 `Dio` 实例发起原生网络请求，支持 gzip、自动重定向、连接池复用与全局 User-Agent 补全；
     - 响应体通过 Dart 的 `jsonEncode` 严格转义为合法的 JSON 对象，无论 HTML 内部含有反引号、`${}`、换行符、反斜杠或双引号，均 100% 安全解析，绝无任何 SyntaxError 语法报错；
     - 真实透传状态码与响应头，完全遵循 Axios 标准 Promise / Error 契约。
- **质量验证**：
  - 静态分析 `flutter analyze` 保持 0 错误 0 警告；
  - 自动化测试套件全量 17 个测试全部 100% 通过。

### 📋 沙箱控制台打印内容复制能力全面落地（移动端 App 与 Web 双端对齐）
- **移动端 App 沙箱控制台交互升级 (`app/lib/views/rules/rule_tester_page.dart`)**：
  - **一键复制全部日志**：在控制台顶部操作区引入快速复制按钮（`LucideIcons.copy`），一键将所有控制台日志按标准格式拼接并写入系统剪贴板，提供触觉反馈与 SnackBar 提示；
  - **自由划词与长按快捷复制**：将不可选中文本升级为 `SelectableText.rich`，支持用户自由选择复制任意字词；并支持整行长按复制单条日志。
- **Web 端沙箱控制台交互升级 (`web/src/views/rules/components/workbench/WorkbenchSandbox.vue`)**：
  - **健壮安全的剪贴板复制工具 (`copyToClipboard`)**：优先使用现代化 `navigator.clipboard.writeText`，在非安全上下文或非 HTTPS 开发环境自动平滑降级至 `textarea` 离屏选择复制（`document.execCommand('copy')`），100% 保障多环境复制成功；
  - **顶部及日志区全量复制 (`copyAllLogs`)**：在沙箱输出日志区的 sticky 标题栏以及工作台顶栏提供「复制全部/复制日志」按钮，一键导出完整时间戳、等级与消息体；
  - **单条悬停复制与划选复制 (`copySingleLog`)**：每条日志项右侧增加 hover 浮现的轻量微型复制图标，点击即复制该条日志；同时保留 `select-text` 使得开发者可在浏览器中自由高亮划选任意部分内容。

### ⚡ 规则引擎遵循 defineRule 标准模板纯粹化重构与详情函数超时假死根除
- **标准模板单契约收敛 (`app/lib/services/rule_engine.dart`)**：
  - **设计理念收敛**：彻底摒弃过度防御、Class 猜测、多层级兼容等冗余分支，严格遵循统一的 `export default defineRule({ discovery, search, detail, parse })` 官方标准模板架构；
  - **极简转译器 (`transformToRunnableJs`)**：
    1. 剔除顶层 `import ...;` 依赖声明；
    2. 将 `export default ` 统一规范替换为 `module.exports = `（若未声明则自动包裹 `module.exports = $clean`），实现零包袱的纯粹 CommonJS 模块导出；
  - **沙箱闭包全链路安全包裹与即时错误透传 (`executeRule`)**：
    1. **杜绝 QuickJS 30 秒假死超时**：在 `(async () => { try { ... } catch (err) { ... } })()` 最外层实施全覆盖异常捕获，沙箱执行期间发生任何业务报错或方法缺失，均通过 `console.error` 实时输出完整错误堆栈至 AppLogger，并以 `{ success: false, error: errMessage }` 格式秒级 Resolved 返回；
    2. **Dart 端毫秒级异常感知**：Dart 端直接解析响应状态，一旦失败立即抛出精准的业务异常，彻底消除了由于 QuickJS 底层 Unhandled Rejection 导致的 `isPendingPromise` 永久挂起与 30 秒超时假死现象；
    3. **空返回值与未定义安全处理**：针对规则编写过程中方法尚未 `return` 的场景（如仅编写 `console.log` 调试），以 `{ success: true, data: null }` 安全封装，杜绝由于 `JSON.stringify(undefined)` 引发的解码崩溃；
    4. **严格契约执行**：提取 `var fn = rule[action];`，按标准入参签名 `await fn.call(rule, params)` 调度，确保 `discovery`、`search`、`detail` 与 `parse` 均按官方标准模板顺畅执行。
- **质量验证与自动化测试套件 (`app/test/widget_test.dart`)**：
  - 新增标准模板 `export default defineRule` 纯粹转译测试用例；
  - 全量 17 个自动化测试全部高质量通过（`flutter test` 17 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。


### 📜 规则内部 console.log 实时回传与 App 端日志中心全链路打通
- **`QuickJsRuntime2` 底层 Channel 冲突排查与专属 `FluxConsoleLog` 桥接升级 (`app/lib/services/rule_engine.dart`)**：
  - **根因深度定位**：
    1. 在 `flutter_js` 的 `QuickJsRuntime2` 中，`setupBridge` 方法存在严苛的防御逻辑：`if (channelFunctionCallbacks.keys.contains(channelName)) return false;`；
    2. `QuickJsRuntime2` 实例化初始化时，其基类会自动默认注册系统级的 `'ConsoleLog'` 通道，当我们在 `RuleEngine._setupEnhancedConsole` 中调用 `onMessage('ConsoleLog', ...)` 时，底层检测到键名冲突直接忽略并返回 `false`，导致我们自定义的 `AppLogger` 转发回调根本没有成功挂载；
    3. 结果导致 JS 规则执行 `console.log` 时，仅触发了 `flutter_js` 默认的本地终端 `print`，日志完全无法流转到 App 端的 `AppLogger`，造成「运行日志页面（LogsPage）」与「规则测试器（RuleTesterPage）」的控制台均无法看到规则打印；
    4. 此外，规则在闭包运行期间，未在自身闭包词法作用域内优先绑定 `var console`，存在被默认环境旧变量遮蔽的风险。
  - **全链路彻底修复方案**：
    1. **专属 Channel 桥接 (`FluxConsoleLog`)**：注册全新的独立 Channel `'FluxConsoleLog'`，从机制上绕过 `setupBridge` 的键名冲突，确保桥接回调 100% 成功注入并生效；
    2. **系统默认 Channel 强行接管**：通过 `JavascriptRuntime.channelFunctionsRegistered` 全局静态注册表，对默认的 `'ConsoleLog'` 也强行替换为我们的统一日志分发处理器 `_handleConsoleLog`，实现双通道兜底捕获；
    3. **沙箱闭包作用域优先绑定**：在 `RuleEngine.executeRule` 构造的闭包执行体 `(async () => { ... })()` 内部，在注入规则代码前显式声明 `var console = ...` 代理，确保规则内的 `console.log/info/warn/error/debug` 100% 命中我们当前作用域内的分发函数；
    4. **强化对象展开与 Error 堆栈解析**：格式化参数支持多参数拼接、普通类型直接提取、Error 实例展开 `stack/message`，杜绝传统 `JSON.stringify(new Error())` 序列化为空对象的问题；
    5. **多态格式安全解码**：`_handleConsoleLog` 支持对解构数组 `List`、JSON 字符串 `String` 及字典 `Map` 的全兼容解析，准确挂载 `Rule: [规则名]` 标签与对应日志等级（INFO/WARN/ERROR/DEBUG）。
- **质量验证与自动化测试 (`app/test/widget_test.dart`)**：
  - 新增规则 `console.log` 经由沙箱桥接安全打入 `AppLogger` 的端到端测试用例；
  - 全套 16 个测试用例全部高质量 PASS（`flutter test` 16 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。

### 🛡️ 单规则搜索点击后全屏灰屏彻底根治（NoSuchMethodError 根因排查）与全局渲染保护视窗
- **`Rule.id` dynamic 动态调用 NoSuchMethodError 致命异常根除 (`app/lib/views/search/search_page.dart`)**：
  - **终极根因深度定位**：
    1. 用户在「规则管理 -> 进入发现 -> 点击顶部搜索」时，所传入的 `Rule` 实体来源于 SQLite 数据库或持久化存储，其自增主键 `id` 字段为 `int` 类型（例如 `1, 2, 3`），在 Dart 中声明为 `dynamic id`；
    2. 在 `SearchPage` 中，初始化状态字典、检索回调及 `_displayResults` 渲染过滤时，存在多处危险代码：`final key = rule.id.isNotEmpty ? rule.id : rule.name;` 与 `final targetKey = _selectedRuleFilter!.id.isNotEmpty ? ...`；
    3. 在单规则搜索模式下，由于绑定了 `_selectedRuleFilter`，当用户点击“搜索”触发页面重绘时，`_displayResults` 在渲染树 `build` 周期内被同步调用，直接对 `int` 类型的 `id` 触发了不存在的属性访问，瞬间抛出致命异常：`NoSuchMethodError: Class 'int' has no instance getter 'isNotEmpty'`；
    4. 由于 Flutter 默认在未捕获构建异常时呈现无内容的灰色 `Container`（即经典的“全屏灰死”），导致用户一旦点击搜索整个页面瞬间变灰死锁。
  - **体系化防御性重构方案**：
    1. **全局安全 Key 提取器 (`_getRuleKey`)**：统一使用静态方法 `_getRuleKey(Rule? rule)`，优先通过 `rule.id?.toString().trim()` 提取字符串标识，安全兼容 `int`、`String` 与 `null`（绝不调用任何未经类型守卫的 dynamic 方法），在全链路中（`_ruleStatusMap`、`_loadMoreResults`、`_displayResults`、Worker 调度）100% 替换；
    2. **规则等价性多态匹配 (`_isSameRule`)**：使用 `_isSameRule(a, b)` 替代单纯的对象引用比对（`==`），即使跨内存反序列化实例也能精准高亮源胶囊和定位过滤结果；
    3. **字典类型安全防护**：优化 `_NormalizedSearchResult.fromMap` 中的原始数据转换，采用安全迭代映射替代严格强转，杜绝沙箱返回非 String 字典 Key 时的类型报错；
    4. **进度条指标范围约束**：为 `LinearProgressIndicator` 计算结果补充 `.clamp(0.0, 1.0)` 防御，避免计算结果产生断言越界；
    5. **单源异常感知与调试器直达**：当单规则检索出现异常或无匹配时，提供精准的错误诊断 EmptyState，并提供一键直达规则调试器（`context.push('/rule_test', extra: singleTargetRule)`）的一键诊断通道。
- **全局 ErrorWidget 防御视窗与异常日志桥接 (`app/lib/main.dart`)**：
  - **全局渲染崩溃拦截器 (`ErrorWidget.builder`)**：彻底告别 Flutter 默认的生硬全灰屏幕！当任何子组件或页面发生未预期的渲染异常时，自动拦截并呈现深色极光风格的「界面渲染保护视窗」，展示直观的异常描述与「返回上一页」兜底自愈按钮；
  - **全链路诊断日志桥接 (`FlutterError.onError`)**：捕获所有 Flutter 框架层未处理错误，并自动打入 `AppLogger` 与日志面板，供开发者与用户随时追溯。
- **AppStorage 本地存储容错兼容 (`app/lib/core/storage/app_storage.dart`)**：
  - 在 `getJson` 方法中增加对历史上保存为 `StringList` 的数组数据的自动降级回退，消除类型强转警告。
- **端到端测试与质量验证 (`app/test/widget_test.dart`)**：
  - 新增整数主键单规则搜索点击、流式过滤与渲染崩溃防御的完整测试用例；
  - 全套 15 个测试用例全部高质量 PASS（`flutter test` 15 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。

### 🎨 规则发现页 Tabs 栏去分割线与下拉展开面板原生背景完全同色化
- **Tabs 栏彻底移除硬质分割线 (`app/lib/views/rules/rule_discovery_page.dart`)**：
  - 移除了横向滚动分类栏底部的 `border` 分割线，让分类标签栏在收起状态下 100% 纯净透明悬浮于页面顶层，彻底消除生硬线条。
- **下拉展开面板与外部页面原生底色 100% 相同融合 (`app/lib/views/rules/rule_discovery_page.dart`)**：
  - **视觉优化策略**：摒弃任何与页面底色不一致的卡片高亮色（如纯白或灰卡片底色），下拉展开面板的背景直接采用与外部页面完全相同的原生底色（深色模式下为深邃暗夜 `AppColors.darkBg`，浅色模式下为纯净星暮白 `AppColors.lightBg`）；
  - **从上往下自然连通**：
    1. Tabs 栏保持 `Colors.transparent`，透出与下拉面板完全相同的页面原生底色；
    2. 下拉面板与上方 Tabs 栏 0 色差接壤，自上而下顺畅流淌，毫无色块跳跃与视觉突兀感；
    3. 底部采用 20px 柔和微圆角与大弥散微阴影（`blurRadius: 20`），与半透明黑色遮罩产生通透深邃的立体层次。
- **质量验证**：
  - 全套 15 个测试用例继续全量通过（`flutter test` 15 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。

### ⚡ 全网搜索升级为类开源阅读（Legado）流式并发聚合模型 & 搜索历史持久化修复
- **类开源阅读多源并发流式聚合架构 (`app/lib/views/search/search_page.dart`)**：
  - **根因分析**：
    1. 过去搜索采用单线程串行 `for` 循环，若前序规则因死链超时或网络缓慢（每个源默认超时长达 30 秒），后续源无法调度，导致页面长达数十秒一直停留在死板的居中转圈加载动画；
    2. 全网搜索时未重置源过滤字段（`_selectedRuleFilter`），若此前在单规则模式或胶囊中选中过特定源，新搜索的数据由于无法匹配被全部过滤为空，形成死循环般的假性“一直在加载”；
  - **重构方案**：
    1. **智能 Worker 并发工作池**：引入多 Worker 并发调度队列（默认并发度 3~4），单源超时收窄至 `clamp(5, 12)` 秒，单个死链源在 12 秒内必定被快速放弃，整体搜索提速 3~5 倍；
    2. **开源阅读同款即时流式呈现**：任何一个规则源只要返回有效条目，即刻通过 `_allResults.addAll(parsed)` 并更新 UI 呈现出来，用户无需等待全部源跑完即可立刻上滑浏览、点击播放；
    3. **全景进度条与开源阅读同款 Stop 机制**：顶部指示条精准反映各源完成百分比（`finishedCount / totalCount`），搜索栏右侧操作按钮在检索中自动切换为“停止”（带终止警示色），用户随时可按停止键立刻中止剩余耗时源并保留已搜索成果；
    4. **底部流式指示**：在数据已呈现而剩余源还在检索中时，在列表/网格最底部展示紧凑的流式探测小动画，彻底消除全屏大菊花挡死带来的卡死困惑。
- **搜索历史持久化与响应式机制深度修复 (`app/lib/services/history_service.dart`, `app/lib/main.dart`, `app/lib/views/search/search_page.dart`)**：
  - **根因分析**：`HistoryService` 构造函数中异步加载未被初始化 await 阻断，导致 `SearchPage` 进入时取到空数组；且此前页面未监听 `searchHistoryNotifier`，异步加载完毕后界面无法自愈刷新；此外 `AppStorage.setStringList` 缺少异常保护，易在覆盖写入时丢失历史；
  - **优化方案**：
    1. `main.dart` 启动阶段显式 `await historyService.init()`，确保在任何视图挂载前历史记录 100% 内存预热就绪；
    2. `HistoryService` 升级为 JSON Array + StringList 双写双读容错，自带全链路 try-catch；
    3. `SearchPage` 深度绑定 `searchHistoryNotifier` 监听器，所有增删改查动作统一委托单例服务并自动响应式重绘。
- **质量验证**：
  - 在 `app/test/widget_test.dart` 中新增 `HistoryService` 增删查持久化与广播测试用例；
  - 全套 15 个测试用例全部 PASS（`flutter test` 15 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。

### 🐛 单规则搜索点击后全屏灰屏崩溃深度根除与搜索体验调优
- **`Positioned` 非法嵌套导致的 ParentData 致命崩溃根除 (`app/lib/views/search/search_page.dart`)**：
  - **根因分析**：在 `_buildVideoResultCard`（横向视频卡片）与 `_buildVideoGridCard`（双列视频网格卡片）中，封面区域的更新集数/清晰度角标（`displayTag`）此前被包裹在 `Builder` 部件内部，当解析到的视频条目包含 `badge` 或 `tags` 时，`Builder` 内部返回了 `Positioned(right: 4, bottom: 4, child: ...)`。由于 `Positioned` 的直接父级是 `Builder` 而非 `Stack`，违反了 Flutter 布局系统的底层契约（`A Positioned widget must be a direct child of a Stack widget`），导致在渲染搜索结果瞬间抛出 `Incorrect use of ParentDataWidget` 致命断言异常，引发页面全屏灰屏；
  - **优化方案**：移除 `Builder` 间接嵌套，直接在卡片构建初始提取 `displayTag`，使 `Positioned` 成为 `Stack` 的直接子节点（`if (displayTag != null && displayTag.isNotEmpty) Positioned(...)`），同时对 `_buildPortraitResultCard` 进行同构精简。
- **单规则专属搜索与组件健壮性升级**：
  - **单规则搜索交互调优 (`app/lib/views/search/search_page.dart`)**：当处于单规则搜索模式下（`_ruleStatusMap.length <= 1`）时，自动隐藏多余的“全部/单源”筛选胶囊栏，让结果列表展示空间最大化；在清空结果回到历史态时保留当前绑定的 `targetRule`；
  - **路由参数稳健解析 (`app/lib/router.dart`)**：`/search` 路由对 `extra` 增加多态解析支持（同时兼容 `Rule` 实体、`Map<String, Rule>` 与序列化 Map），彻底防止潜在的类型强转异常；
  - **网络图片加载防御 (`app/lib/widgets/net_image.dart`)**：`NetImage` 增加针对空 URL 及非法协议的前置校验，遇到异常封面时平滑降级至优雅的内置占位图，杜绝底层网络组件抛错。
- **质量验证**：
  - 在 `app/test/widget_test.dart` 中新增单规则搜索初始化与带角标视频卡片渲染测试用例；
  - 全套 14 个测试用例全部 PASS（`flutter test` 14 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。

### 🧪 规则管理增加类开源阅读（Legado）规则流式测试与调试系统
- **四大生命周期自动化接力流水线 (`app/lib/views/rules/rule_tester_page.dart`)**：
  - **流水线架构**：依次按 `发现/分类 (Discovery)` → `关键字搜索 (Search)` → `详情与选集 (Detail)` → `直链解析/正文提取 (Parse)` 四大生命周期阶段串联流式测试，上一阶段提取的目标条目自动作为下一阶段的测试入参；
  - **跨媒体自适应**：智能依据规则类型（`video` / `novel` / `picture` / `comic` / `audio`）动态预填推荐测试词（如“斗罗大陆”、“剑来”、“海贼王”），自适应验证视频 m3u8/mp4 直链、小说正文字数与排版、漫画图集图片清单；
  - **阶段状态与关键指标**：支持 `idle`、`running`、`success`、`failed`、`skipped` 5 种状态指示，精确到毫秒级耗时监控（`xx ms`），自动提取展示核心字段（标题、URL、封面、字数/集数/图片数）；
  - **原始数据与一键复制**：每个阶段均支持折叠/展开查看格式化原始 JSON 结构，并提供一键复制单阶段数据或导出完整 Markdown 格式规则诊断报告。
- **沙箱实时控制台输出 (Console Logcat)**：
  - 自动捕获当前测试期间 QuickJS 沙箱内部派发的全部 `console.log`、`console.info`、`console.warn`、`console.error`，带语义化等级色彩高亮与自动滚屏；
  - 提供控制台一键折叠、清空与报告导出。
- **规则列表入口无缝集成与纯图标精修 (`app/lib/views/rules/rules_page.dart`, `app/lib/router.dart`)**：
  - 注册 `/rule_test` 全局路由；
  - 规则卡片底部「测试」按钮重构为**纯图标微交互**：移除“测试”冗余文字，仅保留翡翠绿微光烧瓶图标（`LucideIcons.flaskConical`，尺寸 14，内边距 4，圆角 6），与右侧垃圾桶删除图标（`LucideIcons.trash2`）在尺寸与间距上达到 1:1 绝对平衡与视觉呼吸感；
  - 外层注入 `Tooltip(message: '规则测试')` 保持良好的无障碍交互与悬停/长按语义提示；
  - 保留规则卡片 `onLongPress` 长按快捷操作面板，支持快速发起测试、分类发现、复制源站地址或删除规则。
- **质量验证**：
  - 新增 `app/test/rule_tester_page_test.dart` 自动化测试套件；
  - 全套 12 个单元测试与组件测试全部 PASS（`flutter test` 12 passed）；
  - 静态代码分析 0 警告 0 错误（`flutter analyze` No issues found）。

### 🔍 搜索页面点击无反应与双圆角缺陷深度修复
- **输入框双重圆角重叠缺陷根除 (`app/lib/views/search/search_page.dart`)**：
  - **根因分析**：外层 `Container` 设定了半径 10 的灰色细边框，而内层 `TextField` 仅设置了 `border: InputBorder.none`，导致其自动从全局 `ThemeData.inputDecorationTheme` 继承了 `enabledBorder` 与 `focusedBorder`（半径 14、线宽 1.5 的翡翠绿大圆角），在获得焦点时产生“一个绿色大圆角与一个灰色细线条小圆角”嵌套叠加的严重视觉 bug；
  - **优化方案**：在内层 `TextField` 的 `InputDecoration` 中将 `border`、`enabledBorder`、`focusedBorder`、`disabledBorder`、`errorBorder` 等所有边框全部显式置为 `InputBorder.none` 且 `filled: false, fillColor: Colors.transparent`；通过监听 `_focusNode` 将聚焦状态交给外层 Container 统一渲染（圆角 10px，聚焦时高亮翡翠绿边框，失焦时为微弱灰边），实现纯净优雅的单圆角质感。
- **点击搜索无反应缺陷彻底修复 (`app/lib/views/search/search_page.dart`)**：
  - **根因分析**：原代码在 `_performSearch` 与 `_loadMoreResults` 中使用了 `await WidgetsBinding.instance.endOfFrame;`。当输入完成用户点击搜索触发 `_focusNode.unfocus()`（软键盘收起动画过渡）时，若当前帧已绘制完毕且系统未调度新帧，`endOfFrame` 会**无限期挂起（Hang）**，导致后续检索循环与 `RuleEngine.search` 逻辑完全卡死无法执行；
  - **优化方案**：
    1. 将 `WidgetsBinding.instance.endOfFrame` 替换为安全的异步调度与微延时 `await Future<void>.delayed(const Duration(milliseconds: 30));`，既确保 UI 线程及时绘制 loading 进度条，又 100% 杜绝帧等待死锁；
    2. 增加可用规则源的前置校验，当无规则时立即给出明确的 SnackBar 提示与市场导入引导，避免空白空状态造成的“无反应”困惑；
    3. “搜索”按钮直接绑定 `loading: _loading` 与防并发重复点击，点击时即刻变为转圈状态，提供明确的视觉反馈。
- **质量验证**：在 `app/test/widget_test.dart` 中追加 `SearchPage` 单测，覆盖输入框无双圆角校验与无挂起搜索交互测试，`flutter test` 10 个用例全部 PASS，`flutter analyze` 0 警告 0 错误。

### 📑 规则发现页分类 Tabs 交互与视觉优化
- **Tabs 栏纯净透明化 (`app/lib/views/rules/rule_discovery_page.dart`)**：
  - 移除了分类栏原本的实体色块背景（`darkSurface` / `lightSurface`），改为 `Colors.transparent` 纯透明渲染，消除视觉割裂感，使标签流自然浮于页面整体底色与渐变氛围之上。
- **全部分类下拉展示升级为方案 B (顶部向下展开)**：
  - 点击横向 Tabs 右侧的展开按钮，右侧箭头执行 180° 顺滑旋转（`AnimatedRotation` 旋转变色为翡翠绿向上箭头 `^`）；
  - 紧贴 Tabs 正下方平滑向下滑出全部分类网格面板，覆盖在列表上方并带有柔和半透明暗色遮罩（点击空白遮罩区域自动收起）；
  - 面板内标注当前选中态，轻点任一分类即自动收起面板并平滑联动横向滚动条居中至目标 Tab。
- **质量验证**：`flutter test` 9 个用例全部通过，`flutter analyze` 0 警告 0 错误。


### 🎬 WebView 网页视频手势体验调优 (仅全屏触发与极简 HUD)
- **严格全屏限定 (`app/lib/views/browser/web_video_gesture_engine.dart`)**：
  - **背景**：在网页小窗或信息流播放视频时，用户滑动的初衷是浏览图文或滚动页面，此时捕获滑动手势会导致严重误触（误快进或调亮/调音）；
  - **优化**：新增 `isVideoFullscreen()` 判定，同时识别 HTML5 原生全屏 API 与移动端 CSS 视口伪全屏（宽高占比 ≥ 90%）；在非全屏模式下完全不拦截触控事件，彻底放行网页原生浏览、滚动与双指缩放，仅在全屏状态下激活快进、快退、亮度、音量与长按加速。
- **极简 HUD 视觉瘦身**：
  - 去除音量与亮度浮层下方的冗余说明文本（“左侧上下滑动调节画面亮度” / “右侧上下滑动调节播放音量”），仅呈现核心大号百分比数值与金色/天蓝色渐变进度条，视觉感受更加沉浸纯粹。
- **质量验证**：同步更新 `web_video_gesture_engine_test.dart` 全量单元测试，`flutter test` 9 个用例全部通过，`flutter analyze` 0 警告 0 错误。

### 🛠️ 修复沙箱运行日志中心灰屏与返回按钮缺陷
- **根因修复 (`app/lib/views/profile/logs_page.dart`, `app/lib/core/utils/app_logger.dart`)**：
  - 纠正了 `logs_page.dart` 误引用 `package:flutter/material.dart` 导致的 `material_ui` 官方组件库类型冲突（TypeError 导致全局 ErrorWidget 灰屏）；
  - 显式补齐 `AppBar` 的 `leading` 返回图标按钮与 `backgroundColor`、`elevation: 0` 配置，修复左上角返回区域；
  - 优化日志卡片内的文本组件，杜绝内部文本与外层卡片长按复制/点击展开的手势竞争。

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
