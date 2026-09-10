# FluxForge 移动端核心功能技术开发与落地规范 (APP_DEV_SPEC)

> 本文档为 FluxForge 移动客户端（Flutter）的一体化技术开发设计说明书。
> 所有后续 AI 编程助手或开发者在为移动端实现新功能、重构旧组件时，**必须严格遵循本文档所列出的技术选型、架构分层、接口定义与交互规范**，严禁擅自引入未批准的重量级依赖或偏离项目设计语言。

---

## 1. 全局工程底座与公共约束 (必读基础规范)

在开始任何模块的编码之前，必须遵守以下铁律：

### 1.1 依赖选型准则 (严禁滥用第三方库)
- **【明确弃用】Chewie**：严禁在任何新老代码中使用 `chewie`。其内部样式陈旧死板、手势拓展极其受限，已全面废弃；
- **【核心播放底座】video_player**：视频播放底层统一基于官方原生解码库 `video_player`（Android ExoPlayer / iOS AVPlayer），保证极致的稳定度与系统解码兼容性；
- **【触控与手势震动】系统内置**：长按震动反馈统一使用 Flutter 原生 `HapticFeedback.lightImpact()`（来自 `flutter/services.dart`），严禁引入额外震动库；
- **【状态管理策略】轻量与高内聚**：
  - 纯 UI 交互层（如播放器控制条显隐、手势微胶囊）优先使用 `StatefulWidget`、`ValueNotifier` 或 `flutter_hooks`，禁止将高频触控状态抛入全局 Store；
  - 全局持久化状态（如历史记录、规则库、收藏）统一使用项目既有的 Service 单例（通过 `di.dart` 的 GetIt 或全局常量注入）。

### 1.2 设计系统与色彩规范
- **色彩 Token**：严禁在业务代码中硬编码十六进制颜色！所有颜色统一从 `app/lib/core/theme/app_colors.dart` 引用（如 `AppColors.primary` 极光幽绿、`AppColors.darkBg` 曜夜深空黑、`AppColors.lightTextPrimary` 等）；
- **组件质感**：所有卡片、浮层、操作抽屉优先采用 `app/lib/widgets/app_card.dart`（统一 `borderRadius: 20`，自带 90ms 按压微缩弹性回弹，环境柔光冷调微阴影）；
- **微拟态与毛玻璃**：浮动控制器使用 `BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16))` 配合微透明底色打造 Apple 级透光质感。

### 1.3 内存泄漏与生命周期防线
- 所有创建的 `VideoPlayerController`、`AnimationController`、`TextEditingController`、`ScrollController`、`Timer` 必须在 State 的 `dispose()` 中严密销毁；
- 异步操作在 `setState` 前必须严格判定 `if (mounted)`。

---

## 2. 现代视频播放器 (AuraPlayer) 技术实现规格

### 2.1 模块定位与替换目标
- **目标路径**：`app/lib/widgets/player/aura_player.dart`（及 `app/lib/widgets/player/` 子目录辅助组件）；
- **替换目标**：彻底替换 `app/lib/views/detail/media_detail_page.dart` 中原有的 `Chewie` 逻辑，成为应用内唯一的全功能视频播放引擎。

### 2.2 组件接口定义 (API Contract)
```dart
class AuraPlayer extends StatefulWidget {
  const AuraPlayer({
    super.key,
    required this.playUrl,                   // 视频播放直链 (mp4, m3u8, flv 等)
    this.httpHeaders = const {},             // 防盗链请求头 (Referer, User-Agent 等)
    this.title = '',                         // 视频/剧集标题
    this.coverUrl,                           // 视频封面大图
    this.initialPosition = Duration.zero,    // 断点续播初始跳转位置
    this.onProgress,                         // 播放进度回调: void Function(Duration current, Duration total)
    this.onEnded,                            // 播放结束回调
    this.onBack,                             // 顶部返回按钮回调
    this.extraActions,                       // 顶部/底部右侧扩展操作插槽
  });

  final String playUrl;
  final Map<String, String> httpHeaders;
  final String title;
  final String? coverUrl;
  final Duration initialPosition;
  final void Function(Duration current, Duration total)? onProgress;
  final VoidCallback? onEnded;
  final VoidCallback? onBack;
  final List<Widget>? extraActions;
  
  @override
  State<AuraPlayer> createState() => _AuraPlayerState();
}
```

### 2.3 手势交互层详细逻辑 (Gesture Layer)
播放器画面上层覆盖一层全屏 `GestureDetector`，负责捕获四大手势：
1. **左侧 1/3 垂直滑动手势 (屏幕亮度调节)**：
   - 捕获垂直拖拽位移差，动态计算亮度增减（0.0 ~ 1.0）；
   - 屏幕左侧边缘弹出**垂直胶囊亮度条**，实时反映当前亮度百分比，手势松开 1 秒后自动淡出。
2. **右侧 1/3 垂直滑动手势 (应用内音量调节 - 免权限方案)**：
   - 直接调用 `_controller.setVolume(newVolume)`（0.0 ~ 1.0）；
   - **技术亮点**：避免调用危险的系统音量 API，不弹出系统原生粗大音量框，静默在屏幕右侧边缘渲染**垂直胶囊音量条**。
3. **屏幕中央水平滑动手势 (精细快进/快退)**：
   - 水平拖拽时计算目标时间差值（`deltaSeconds`）；
   - 屏幕正中央弹出**微拟态毛玻璃悬浮胶囊**，内部展示：
     - 快进/快退图标（`LucideIcons.fastForward` / `rewind`）；
     - 时间差值高亮（如 `+00:15` 或 `-00:30`）；
     - 目标进度与总时长（如 `12:45 / 45:00`）；
   - 手指抬起时一次性触发 `_controller.seekTo(targetPosition)`。
4. **屏幕任意位置长按手势 (2.0X 瞬时倍速)**：
   - `onLongPressStart`：触发一次轻微物理震动 `HapticFeedback.lightImpact()`，记录当前播放速率，并将倍速临时提升至 `2.0`；
   - 画面顶部中央弹出呼吸微胶囊：`▶▶ 2.0X 快速播放中`；
   - `onLongPressEnd`：恢复长按前的原始倍速，微胶囊淡出。
5. **单击与双击交互**：
   - 单击屏幕：切换控制条显隐状态，显示状态下开启 3.5 秒无操作自动淡出计时器；
   - 双击屏幕中央：切换播放/暂停，伴随中央微拟态播放图标缩放动画。

### 2.4 UI 控制层视觉元素与交互细节 (UI Overlay)
- **顶部栏 (Top Bar)**：
  - 背景：从纯黑 70% 透明度渐变到完全透明的暗影遮罩；
  - 内容：左侧返回箭头（`arrow_back_ios_new`）+ 剧集标题（单行省略）+ 右侧画中画 PiP 按钮（`LucideIcons.pictureInPicture2`）；
- **底部栏 (Bottom Bar)**：
  - 背景：底部暗影遮罩与微模糊；
  - 核心控件：
    - 播放/暂停大图标；
    - 当前播放进度与总时间（采用 `w600` 微等宽字体）；
    - **极光流光进度条**：
      - 未缓冲轨道：白微透 20%；
      - 缓冲轨道：白微透 45%；
      - 播放进度轨道：`AppColors.primary` (翡翠幽绿)；
      - 拖拽手柄：拖拽时从 6px 平滑放大至 12px 翡翠光晕圆点；
    - 倍速药丸按钮：点击弹出底部轻量 BottomSheet，支持 `0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 2.0x`；
    - 锁定按钮 (Lock)：屏幕左下角浮动小锁图标，锁定后隐藏并冻结一切手势交互，防看剧误触；
    - 全屏切换按钮：联动 `SystemChrome.setPreferredOrientations` 切换横竖屏。
- **辅助浮层**：
  - **断点续播提示**：进入时检测到已有进度（> 5秒且未播完），在右下角弹出轻胶囊「上次看到 12:45 [点击继续]」，5 秒后自动淡出。

---

## 3. 规则健康巡检与毫秒级测速实现规格

### 3.1 模块定位与涉及文件
- **目标路径**：扩展 `app/lib/views/rules/rules_page.dart` 及 `app/lib/services/rule_service.dart`。

### 3.2 测速探测与三色判定算法
- **触发入口**：在 `RulesPage` 的 AppBar 右侧或顶部增加「一键测速」图标按钮；
- **探测逻辑**：
  - 遍历所有已启用的规则，通过 `dio` 或 `http` 并发发起轻量 `HEAD` 请求（若源站不支持 HEAD 则降级为超时 3 秒的 `GET` 请求）；
  - 统计请求开始至响应首字节到达的耗时（`ms`）；
- **三色状态指示器**：
  - 🟢 **畅通 (< 500ms)**：极光绿微圆点 + 延迟数值（如 `128ms`）；
  - 🟡 **较慢 (500ms ~ 1500ms)**：琥珀黄微圆点 + 延迟数值；
  - 🔴 **失效/超时 (> 1500ms 或抛出 SocketException/404/500)**：红色感叹圆点 + `超时`；
- **批量清理操作**：
  - 测速完成后，如果存在红色失效源，在顶部弹出轻提示条：「检测到 N 个失效规则，[一键禁用] 或 [一键清理]」。

---

## 4. 纯净小说阅读引擎 (FluxReader) 实现规格

### 4.1 模块定位与新建文件
- **目标路径**：`app/lib/views/reader/novel_reader_page.dart`（及关联排版计算辅助类）。

### 4.2 核心排版引擎与翻页机制
- **排版计算器**：
  - 依据当前屏幕视口尺寸、字体大小（14~28px）、行高倍率（1.4~2.2）、段落间距，进行分页字符截断切片；
- **三大阅读翻页模式**：
  1. **仿真覆盖/左右平滑翻页**：标准横向 PageView 翻页；
  2. **上下连续长篇滚动**：网文读者最喜爱的无缝长下拉流；
- **护眼质感底色预设 (Reading Palettes)**：
  - **羊皮复古**：底色 `#F6F1E7`，字体 `#3B2F1D`；
  - **豆沙护眼**：底色 `#E4EDE1`，字体 `#1D2E1A`；
  - **极夜深邃**：底色 `#0F141C`，字体 `#A0ABC0`；
  - **纯净白瓷**：底色 `#FFFFFF`，字体 `#1A202C`。
- **进度与预加载**：
  - 退出时自动保存章节索引与阅读进度百分比；
  - 阅读至当前章节最后 20% 进度时，静默调用 `RuleEngine` 解析下一章节正文并写入内存缓存。

---

## 5. 漫画与图集查看器 (FluxGallery) 实现规格

### 5.1 模块定位与新建文件
- **目标路径**：`app/lib/views/gallery/gallery_viewer_page.dart`。

### 5.2 查看模式与双指交互
- **双阅读模式**：
  - **瀑布流大图展厅**：2列或3列网格卡片，点击单图进入沉浸全屏；
  - **垂直条漫阅读器**：漫画专用，从上往下垂直连续无缝拼图下拉；
- **手势缩放与拖拽**：
  - 基于 `InteractiveViewer` 实现 1.0x ~ 4.0x 双指无级平滑缩放，双击屏幕快速复位或放大；
- **快捷动作抽屉**：
  - 长按图片底部弹出极简面板：支持「保存高清原图到系统相册」、「复制图片直链」、「分享图片」。

---

## 6. 本地全量数据一键备份与恢复实现规格

### 6.1 模块定位与服务新建
- **目标路径**：`app/lib/services/backup_service.dart`，入口嵌入设置页 `app/lib/views/profile/settings_page.dart`。

### 6.2 JSON 数据包结构契约 (Backup Schema)
导出的单文件命名为 `fluxforge_backup_YYYYMMDD_HHmm.json`（或 `.flux`），结构严格如下：
```json
{
  "app": "FluxForge",
  "version": 1,
  "exportedAt": "2026-09-10T15:00:00.000Z",
  "data": {
    "rules": [ ... ],       // 当前存储的全部规则数组
    "favorites": [ ... ],   // 用户的收藏夹列表
    "history": [ ... ]      // 观看/阅读历史记录
  }
}
```

### 6.3 导出与导入交互流
- **导出流程**：
  - 组装 JSON 字符串，保存至 App 临时目录；
  - 调用 `share_plus` 插件弹出原生系统分享弹窗，用户可直接保存到手机本地文件管理器、或发送至微信/QQ/电脑；
- **导入流程**：
  - 使用文件选择器（`file_picker`）选取本地 JSON 文件；
  - 校验 `app == "FluxForge"` 与数据结构完整性；
  - 弹出确认对话框让用户选择：
    - 「合并导入」（保留现有数据，仅追加去重新增项）；
    - 「完全覆盖」（清空当前库，以备份文件为准）。

---

## 7. 统一收藏与智能追更提醒实现规格

### 7.1 模块定位与数据模型
- **目标路径**：`app/lib/services/favorite_service.dart`，在「我的」/收藏列表呈现。

### 7.2 数据结构契约
```dart
class FavoriteItem {
  final String id;           // 媒体唯一标识 (通常为 url 或 uuid)
  final String title;        // 媒体名称
  final String cover;        // 封面图
  final String mediaType;    // video / novel / picture
  final String ruleId;       // 绑定的解析规则 ID
  final String lastEpisode;  // 上次看到/更新的章节名 (如 "第12集")
  final String latestEpisode;// 探测到的源站最新章节名 (如 "第13集")
  final bool hasUpdate;      // 是否有新更新未看
  final DateTime updatedAt;
}
```

### 7.3 追更探测机制
- 用户进入收藏页面或执行下拉刷新时：
  - 取出所有未完结的收藏条目，并发调用对应规则的 `detail` 动作；
  - 比对返回的最新章节名与本地记录的 `lastEpisode`；
  - 若发现新章节，更新 `hasUpdate = true`，并在收藏卡片右上角亮起**极光翡翠「NEW · 第13集」微胶囊角标**，点击后直达最新剧集。

---

## 8. 全局偏好与系统设置 (AppSettings) 实现规格

### 8.1 模块定位与涉及文件
- **目标路径**：`app/lib/views/profile/settings_page.dart` 及 `app/lib/services/app_service.dart`（全局偏好状态持久化）。

### 8.2 核心偏好模型契约 (Settings Model)
```dart
enum ResumeBehavior { auto, prompt, disabled }

class AppSettings {
  // 1. 播放视听偏好 (AuraPlayer)
  final bool enablePlayerGestures;     // 允许滑动手势调节亮度与音量 (默认 true)
  final bool enableLongPress2x;        // 允许长按 2.0x 瞬时倍速与轻震动 (默认 true)
  final double defaultPlaybackSpeed;   // 默认起播倍速 (0.5 ~ 2.0，默认 1.0)
  final ResumeBehavior resumeBehavior; // 续播行为 (auto 直接跳 / prompt 提示询问 / disabled 从头播)
  final bool cellularDataWarning;      // 非 Wi-Fi 播放流量保护提醒 (默认 false)

  // 2. 浏览与阅读偏好 (FluxReader & Gallery)
  final String novelPageMode;          // 小说翻页模式 (slide 平滑翻页 / scroll 垂直滚动 / cover 仿真)
  final double novelFontSize;          // 小说基准字号 (默认 18.0)
  final double novelLineHeight;        // 小说行高倍率 (默认 1.6)
  final String galleryLayout;          // 图集画廊展示模式 (waterfall 瀑布流 / strip 垂直条漫长图)

  // 3. 规则沙箱与网络偏好
  final int requestTimeoutSeconds;     // 规则沙箱全局请求超时时限 (15s / 30s / 60s，默认 30s)
  final String customUserAgent;        // 自定义全局 User-Agent (留空使用内置移动端/桌面 UA)
  final bool enableAdBlock;            // 内置浏览器广告拦截引擎开关 (默认 true)
  final bool autoCheckRuleUpdates;     // 启动时自动检查规则更新 (默认 true)

  // 4. 外观与主题系统
  final ThemeMode themeMode;           // 主题模式 (system 跟随 / light 纯白 / dark 极夜)
  final DynamicSchemeVariant dynamicVariant; // M3 色彩算法变体 (expressive / vibrant / tonalSpot)
  
  // 5. 隐私与安全
  final bool incognitoMode;            // 无痕消费模式 (开启后暂不写入播放与阅读历史，默认 false)
}
```

### 8.3 界面布局与卡片分组设计
设置页采用大一统的分组 `AppCard` 现代工业级圆角卡片列表展示：
1. **播放与视听偏好卡片 (与 AuraPlayer 联动)**：
   - 屏幕滑动手势调节开关 (亮度/音量)；
   - 长按 2.0x 瞬时倍速与触觉微震动开关；
   - 默认起播倍速与断点续播行为 (直接跳转 / 浮层提示 / 从头播) 切换选择；
   - 移动网络播放流量提示保护开关；
2. **浏览与阅读偏好卡片 (与 FluxReader / FluxGallery 联动)**：
   - 小说默认翻页方式 (左右平滑 / 垂直长篇连续滚动 / 仿真)；
   - 小说基准字号与行距调节滑块；
   - 图集默认展厅列数与长图条漫模式偏好；
3. **规则沙箱与网络解析卡片**：
   - **沙箱请求超时时限下拉菜单** (提供 `15s` / `30s (推荐)` / `60s`，针对不同网络源站弹性宽容)；
   - 自定义全局 User-Agent 输入弹窗；
   - 内置浏览器广告拦截增强开关 (AdBlockEngine)；
   - 启动时自动同步规则更新开关；
4. **数据存储与精准深度清理卡片**：
   - 细分显示占用容量：网络图片缓存容量 (如 `36.8 MB`)、搜索历史条数、播放进度条目；
   - 支持单项精准「清理」与全量一键复位；
   - 本地数据全量一键导出与导入还原入口 (无缝联动第 6 章模块)；
5. **主题与外观风格卡片**：
   - 系统主题选择 (跟随系统 / 纯净星暮白 / 曜夜极光翡翠)；
   - Material 3 动态色彩风格切换 (表现力 Expressive / 鲜艳 Vibrant / 柔和 TonalSpot)；
6. **关于与系统诊断卡片**：
   - App 版本号、构建编号及 Flutter 运行底座信息；
   - QuickJS 沙箱实时运行日志抽屉 (支持一键复制/清空报错堆栈)；
   - 跨端规则契约白皮书与开源许可证入口。
