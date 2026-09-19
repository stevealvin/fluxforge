# FluxForge 变更日志 (CHANGELOG)

本文档用于记录 FluxForge（包括 App 移动端、Server 服务端、Web 管理端）在开发过程中的重要功能迭代、UI 体验调优与架构重构日志。

## [2026-09-19]

### 🧭 新增「站点」Tab：自定义网站入口 + 内置浏览器打开

**入口**：底部导航由「发现 / 规则 / 我的」扩为 **「发现 / 规则 / 站点 / 我的」**，
图标 `globeOutline`，与「发现」（规则源驱动的媒体内容浏览）职责明确区分。

**能力**：

- **添加站点**：名称（留空自动用域名兜底）+ 网址；地址自动补全 scheme
  （输入 `example.com` 即可），校验仅放行 http / https 且 host 非空；
- **打开站点**：点击卡片走现成的 `context.pushBrowser` 进入内置浏览器
  （自动广告拦截 + 视频手势嗅探 + 全屏播放能力全部继承）；
- **管理**：长按卡片弹出「编辑 / 删除」，同地址重复添加自动去重并置顶；
- **网格布局**：三列图标网格（图标 + 名称 + 域名），单屏可见条目更多；
- **空态引导**：说明用途并给出添加入口。

**实现**：

| 层 | 文件 | 职责 |
|---|---|---|
| data | `data/sites/site_store.dart` | `SiteEntry` 模型 + `SiteStore`（`ValueNotifier` + `AppStorage` JSON 持久化、URL 规范化与校验） |
| feature | `features/sites/sites_page.dart` | 站点列表 / 空态 / 打开动作 |
| feature | `features/sites/widgets/site_sheets.dart` | 新增编辑弹层、长按操作弹层 |

**顺带**：`sites_page` 初版 325 行被架构门禁拦下（>300 上限），按门禁要求拆出弹层组件 ——
门禁对新增代码同样生效，未走白名单豁免。

**验收**：新增 6 条单测（URL 规范化与校验、去重置顶、按 id 编辑删除、落盘往返读回）；
`flutter analyze` 0 问题；`flutter test` **235/235 通过**；架构门禁通过。

**测试基建修正**：`AppStorage` 的静态句柄会固定首次使用的 `SharedPreferencesAsyncPlatform`
实例，仅替换 `instance` 无法隔离测试数据（前序用例的持久化内容会泄漏），
现改为在 `setUp` 中显式 `AppStorage.clear()`。

### ✨ 进度条缓冲动效改版：Barber Pole 灰白斜条纹 + 缓冲前沿旋转弧

**旧动效**：未加载区域「白色流光单向扫掠 + 呼吸底色 + 缓冲端点横向光晕」——
单色白斑语义偏「数据流动」，且三个元素叠加偏碎。

**新动效**（统一灰白无彩色，避免与品牌翡翠轨争夺注意力）：

- **未加载区域 · Barber Pole 斜条纹滚动**：深浅两档灰白斜条纹（周期 14px）沿轨道方向
  循环平移，转筒式表达「后续内容正在滚动加载」；条纹用 `canvas.skew(-1, 0)` 做 45° 斜切，
  clip 严格限制在未加载区域与圆角轨道内。
  注：轨道仅 2.5~3.5px 高，斜切产生的斜边位移与轨道高度同量级，斜度弱于标准转筒，
  动感主要由相位滚动承担；
- **缓冲前沿 · 灰白旋转弧**：以缓冲端点为圆心的 `SweepGradient` 扫掠圆弧持续旋转
  （1.35π 留缺口、圆头描边），半径略大于轨道高度、水平位置 clamp 在轨道内；
- 移除原「端点横向光晕」（职责由旋转弧承担）。

**同步调整快捷胶囊视觉**（快进 / 快退 / 长按加速）：

- 图标与文字统一为**纯白**（原为方向色 / 品牌色），胶囊内不再出现彩色元素；
- 底色透明度下调（快进快退 0.45 → 0.35、长按加速 0.55 → 0.42），更通透。

动画仍复用 `_shimmerController`（已按缓冲状态启停），无新增动画器；
`flutter analyze` 0 问题，播放器测试通过。

### ⚡ 播放器性能：流光扫光动画改为按缓冲状态启停

**问题**：进度条扫光动画 `_shimmerController` 在 `initState` 里无条件 `..repeat()`，
但其视觉只在「未加载空白轨道」上可见（`AuraSliderTrackShape.paint` 内 `if (isBuffering)`）。
播放器常驻详情页时，即便视频暂停、控制栏隐藏，也会一直跑 60fps ticker 并持续重建进度条。

**修复**：新增 `_syncShimmerTicker()`，按综合缓冲状态（未初始化 / `isBuffering` / seek 后
缓冲指示）启停动画，并在状态变化点同步（帧监听、初始化成功与失败、手势 seek 与进度条拖动的
两端）。判定为「非缓冲」时 `stop()`，不影响任何视觉效果。

### 🖥️ 修复：全屏内修改播放设置需退出全屏才生效

**问题**：全屏是 `Navigator.push` 的独立路由，宿主的 `setState` 重建不到它；
而 `AuraPlayer` 内部无偏好副本、getter 直读 `widget.preferences`（创建时的快照）。
于是全屏内从右上角菜单改设置后，持久化与宿主回灌都成功，但**全屏实例仍用旧值**，
必须退出全屏（路由销毁、小屏实例重建）才生效。

**修复**：播放器内部持有偏好本地副本 `_preferences` ——

- 菜单改动：**先本地 `setState` 立即生效**，再上抛宿主持久化；
- 外部变更（设置页等）：`didUpdateWidget` 比对后回灌本地副本；
- 进入全屏时透传本地副本而非 widget 参数，宿主尚未回灌也不会带旧值。

现在小屏与全屏行为一致：改完立即生效，且同步持久化。

## [2026-09-19]

### 🔋 修复：小屏播放时屏幕常亮失效（多实例竞态）

**期望行为**：只要视频在播放（无论全屏还是小屏）就保持屏幕常亮（不锁屏），
暂停 / 播放结束 / 退出播放器时解除、恢复系统锁屏节奏。

**根因（多实例竞态）**：小屏与全屏是两个**共享控制器**的 `AuraPlayer` 实例，
而 `WakelockPlus` 是全局单例资源。原实现每个实例各自维护一份
`_isWakelockEnabled` 去重状态 —— 挂载 / 卸载时序稍错位（如新实例 initState
的 enable 先于旧实例 dispose 的 disable），旧实例的解除就会**关掉新实例刚开启
的常亮**，且随后被新实例自己的去重守卫拦截、无法恢复 → 常亮永久丢失。

**修复**：改为**全局引用计数**收敛 ——

- 静态计数 `_wakelockDemandCount`：>0 时保持常亮，归 0 才解除；
- 实例只登记 / 撤销自己的需求（`_wakelockDemanded` 防重复计数）；
- 旧实例 dispose 的解除最多把计数减 1，只要新实例仍在播放（计数 ≥1），
  常亮不会被误关 —— 时序错位不再可能造成常亮丢失；
- 暂停 / 结束 / 后台切前台等所有转换最终都经由 `_updateWakelock` 收敛，
  行为与「播放即常亮、不播即恢复锁屏」严格一致。

**验收**：`flutter analyze` **0 问题**；播放器测试全部通过。

## [2026-09-18]

### 📖 小说阅读器横向模式重构：跨章连续渲染（章节切换与章内翻页完全一致）

**旧机制**：`PageView` 只渲染单章 + 章首/章末「衔接提示页」，key 含章号 ——
翻到衔接页后必须整体重建 PageView 并 jump 定位，翻章永远伴随过渡页与跳变。

**新机制（滑窗式跨章连续渲染）**：

- `PageView` 渲染以当前章为中心的**滑窗**：`[上一章切片..., 当前章切片..., 下一章切片...]`
  扁平页序列；**key 不再含章号，组件全程不重建**；
- 章末继续向后翻，滑动动画**直接进入下一章第一页**，与章内翻页视觉完全一致；向前翻同理；
- 跨章瞬间：`onPageChanged` 把扁平页码反解为 (章, 章内页) → 更新当前章 → **窗口平移** +
  无动画 `jumpToPage`（jump 前后渲染同一页正文，仅索引变化，视觉零跳变）；
- 分片缓存 `Map<章号, 切片>`：正文已在内存的章节同步分片（`PaginationEngine` 纯函数直接复用）；
  相邻章内容预取完成后自动补片，翻章零等待；
- 正文未就绪的相邻章在窗口中占一页加载占位（复用 `ReaderChapterBridge`），就绪后自动顶替；
- 视口尺寸 / 字号 / 行距变化时全量失效重算（`invalidateAll`），单章内容更新只重算该章，
  相邻章分片得以复用；
- 章首/章末衔接页机制整体移除（`_autoAdvance*` / `_advanceToBridgeChapter` /
  `_prevBridgeCount` 等 ~80 行），三区点击翻页统一为滑窗内 `nextPage/previousPage` 动画。

**顺带修复**：小说详情页「进入阅读器查看全部 N 章节」使用固定 `AppColors.primary`，
暗色主题下应为更亮的 `primaryGlow`，改跟随 `colorScheme.primary` 自适应。

**验收**：阅读器 8/8 测试通过（无缝续读 / 无缝回退 / 进度条同步 / 目录 / 错误态全部保持）；
`flutter analyze` **0 问题**；`flutter test` **229/229 通过**；架构门禁通过。

### 🔁 视频下载新增「URL 过期刷新」机制（`onUrlExpired`）

**背景**：规则源的视频地址常带时效签名（`?sign=...&expire=...`）。源站以 401/403/410
拒绝请求时，此前该集只能标记失败，「重试失败」仍用同一条过期地址，永远 403。

**机制**（`DownloadService` 新增可空回调 `onUrlExpired`，未注册时行为与既往完全一致）：

- **触发判定**：`isAuthExpiredStatus` —— 仅 401 / 403 / 410 视为 URL 失效并尝试刷新；
  超时、断网、5xx 刷新 URL 无意义，照常按失败处理，杜绝死循环；
- **三个触发点**：HLS 清单请求、HLS 分片下载、直链 Range 续传；
- **编排**：触发后回调宿主重新解析播放页 → 新地址登记回 `targetUrls[index]`
  （后续「重试失败」也用它）→ 原路重试。**每集每轮至多刷新一次**；
- **进度保留**：分片与 `.part` 均与签名无关，重试原样续传；HLS 会作废含冻结签名的
  旧清单（`remote.m3u8`）重新拉取，但已落盘分片不重下；
- 与「再点一次下载按钮」的手动恢复路径互补：该路径刷新全部 URL 但救不了
  「分片签名冻结在已存盘清单里」的场景，本机制正好补上这一空档。

**验收**：新增 6 条测试（状态码判定边界 + 4 条直链端到端：刷新成功续传 / 回调返回
null 按普通失败 / 新地址再 403 不二次刷新 / 未注册回调行为与既往一致）；
`flutter analyze` **0 问题**；`flutter test` **229/229 通过**；架构门禁通过。

### ⏯️ 视频下载全类型断点续传

**上一版的局限**：中断后只有「整集级」续传（已完成集跳过），正在下载的那一集会从头重下 ——
因为 FFmpeg 把 HLS 合并成单个 MP4，半截文件既不可播也不可续。

**现在按地址形态分成两条续传通道**：

| 类型 | 续传粒度 | 机制 |
|---|---|---|
| m3u8（HLS） | **分片级** | 清单解析 → 逐分片落盘（跳过已有）→ 改写清单指向本地 → FFmpeg 合并 |
| mp4 / mkv 等直链 | **字节级** | dio `Range: bytes=<已有>-` → `.part` 追加 → 完成后原子改名 |

**HLS 分片续传的关键设计**：

- **解密不在 Dart 侧实现**：AES-128 的 key 也被下载到本地并改写进清单，
  合并时交给 FFmpeg 的 `crypto` 协议解密 —— 避免重复实现分片解密与 IV 推导；
- 清单**优先复用上次已存的原文**：源站临时不可达时也能续传；
- 分片写入「先 `.tmp` 再改名」：磁盘上存在的分片一定是完整的，中断不留脏文件；
- master 多码率清单取第一个码率子清单再解析一层；
- 每个分片之间检查任务存活性，暂停 / 删除后立即中止，不再消耗流量；
- 合并成功后整体删除分片目录，只保留最终 MP4（磁盘不双份占用）。

**直链续传**：服务器返回 206 时从断点追加；返回 200（不支持 Range）时自动退化为整文件重下；
`.part` 临时文件完成后**原子改名**，杜绝半截文件被当成品。

**配套改动**：

- `FfmpegCommandBuilder.buildLocalMerge()`：本地分片合并命令，协议白名单收窄为
  `file,crypto,data`（不再需要网络协议）；
- 新增 `HlsPlaylistParser`：master / media 识别、相对路径绝对化、
  `EXT-X-KEY / SESSION-KEY / MAP` 的 `URI` 提取、`data:` 内联资源跳过、清单本地化改写；
- `pause()` / `clearAll()` 同时打断两条通道（FFmpeg 会话 + dio CancelToken）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **223/223 通过**
（新增 HLS 解析 8 条 + 本地合并命令 1 条）；架构门禁通过。

**⚠️ 已知限制**：HLS 的 `#EXT-X-MEDIA`（独立音轨 / 字幕轨子清单）暂不支持；
真实解密与合并行为仍需 Android 真机验证。

### 📥 集成 FFmpeg 实现视频离线下载

**依赖与原生配置**：

- 新增 `ffmpeg_kit_flutter_new: ^4.6.2`（FFmpegKit 的社区维护分支，内核 FFmpeg v8.1.2，
  已适配 Android V2 embedding）；
- Android `minSdk` 显式抬到 **24**（该包原生库以此为基础，低于它会运行期加载 .so 失败）；
- 项目仅构建 Android（无 ios/ 目录），且 `abiFilters` 只保留 arm64-v8a，ffmpeg 原生库体积可控。

**核心设计**：

- **命令构造抽成纯逻辑** `data/download/ffmpeg_command_builder.dart`：
  FFmpeg 命令是纯字符串，参数顺序、引号转义、HTTP 头传递方式写错只会在真机上表现为
  「下载失败」或「视频无声」，抽成纯函数后用 **18 条单测**把所有转义分支固定下来；
  - `-protocol_whitelist` 含 `crypto`/`data`（AES-128 加密 m3u8 的硬需求）；
  - `-bsf:a aac_adtstoasc`（缺失会让产出的 MP4 在部分播放器上无声）；
  - `-movflags +faststart`（moov 前置，支持边下边播）；
  - `-user_agent` / `-referer` 走专用选项，Cookie 等其余头拼进 `-headers`（CRLF 分隔）；
  - 总时长从 FFmpeg 日志的 `Duration:` 行解析 —— **不走 FFprobe**：带防盗链头的源它也发不了请求。
- **DownloadService 扩展视频任务**：
  - `startVideoDownload()`：一部剧一个任务（与小说 / 漫画同一套任务记录与下载管理页），
    产物落 `videos/<bookId>/<索引>.mp4`；
  - `_downloadVideoEpisode()`：`executeAsync` + `Completer`，**暂停 / 删除 / 清空任务
    会 `FFmpegKit.cancel(sessionId)` 真正终止下载**（旧任务体系无此需求）；
    并防御了 `getSessionId()` 返回可空、以及「无效 sessionId 绝不能传给 cancel」
    —— 因为 `cancel(null)` 的语义是「取消全部会话」；
  - 进度：`Statistics.getTime()` 换算成**项内进度**（500ms 节流），
    `DownloadTask.progress` 计入项内进度 —— 长视频下载时进度条能持续前进，
    小说 / 漫画项内进度恒为 0，行为不变；重启后项内进度一律归零（瞬时状态）；
  - `localVideoPath()` / `isVideoEpisodeDownloaded()` 供播放与详情页查询。
- **播放器支持本地视频**：`AuraPlayer` 对非 http 地址改用
  `VideoPlayerController.contentUri`（Android ExoPlayer 原生支持 file:// URI），
  **不引入 `dart:io`**，保留 web 构建路径。
- **UI 接入**：视频详情选集栏新增「下载本部」按钮
  （三态：未下载 / 下载中→点击看进度 / 已完成），下载管理页类型徽标与单位扩展视频（视频 / 集）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **214/214 通过**（含 18 条新增命令构造单测）；
架构门禁通过。

**⚠️ 必须知晓的限制**：

1. **GPL v3.0**：主包标注 LGPL-3.0 但实际等效 GPL v3.0（含 x264/x265/vid.stab）。
   若本项目计划**闭源分发**，应改用 `ffmpeg_kit_flutter_new_https` 子包（无 GPL 组件）
   并同步调整 import；纯内部使用 / 开源则无碍。
2. **无法端到端验证**：FFmpeg 的实际执行依赖原生库，只能通过 Android 真机构建验证 ——
   首次构建会自动下载预编译库（约 30-50MB），建议先跑一次 `flutter build apk`
   确认链接成功，再用真实 m3u8 源实测「下载 → 断网播放」闭环。
3. **单集粒度下载暂不支持**：现按「整部剧」入队（与小说 / 漫画同一套任务模型），
   「只下载当前集」需要给任务模型增加选择性下载集合，如需要再单独做。

### 🧭 「我的」页资产卡去重：搜索足迹 → 下载管理

- **移除「搜索足迹」资产卡**：该数据已完整收纳在历史中心页（观看历史 + 搜索足迹两个板块），
  在「我的」页再设一张卡等于同一份数据两个入口；
- **卡位改由「下载管理」承载**：主数值为离线任务数，副信息按优先级展示
  「正在下载 N 部 / N 部存在失败项 / 全部下载完成 / 暂无离线内容」，
  仅在存在失败项时亮提示点（进行中属正常状态，无需额外提示），点击直达下载管理页；
- **同步移除设置列表里的「离线下载」项** —— 资产卡承载该入口后，这一行会形成新的同屏重复，
  正是本次「消除重复入口」意图的一部分；
- 颜色沿用原卡位的 `accentAmber`，保持 2×2 四色互不重复。

**验收**：`flutter analyze` **0 问题**；`flutter test` **196/196 通过**；架构门禁通过。

### 🎛️ 视频详情：横向快速选集按钮收紧尺寸

- 剧集 chip 由「高 46 / 最小宽 54 / 水平内边距 14 / 字号 12.5 / 播放图标 10」
  收紧为「高 38 / 最小宽 46 / 水平内边距 12 / 字号 12 / 播放图标 9」，整体缩小约 17%；
- 附带收益：单屏可容纳的集数变多（4 字标题的按钮宽度由 78px 降至 72px）；
- 未改动「全部」抽屉按钮与底部全量剧集网格 —— 两者原本已是紧凑规格
  （字号 12、图标 13、网格格子高约 40px），无需再收。

**验收**：`flutter analyze` **0 问题**；`flutter test` **196/196 通过**；架构门禁通过。

### 🌊 修复纵向长卷向上加载章节时的顿挫（改用 center 锚点，彻底移除偏移补偿）

**问题**：上下滚动模式中，向上滚动加载前面的章节时会「顿一下」，不平滑。

**根因有两个，缺一不可**：

1. **前插导致坐标整体位移**：单条 `ListView` 的偏移原点在整条内容最顶部，向上前插一章会让
   所有已有章节的 index 位移，只能走「先布局 → 下一帧量高度 → `jumpTo` 补偿」。
   这必然漏出**一帧错位画面**；更糟的是新块高度测不到时
   `compensateOffsetAfterPrepend` 会直接返回 null 放弃补偿，位置就真的偏掉了。
2. **分隔线放在块首**：锚点块「上方是否有内容」在插入瞬间由 false 变 true，
   块内凭空多出 54px 的分隔线 → 锚点内容整体下移。

**修复**：

- `ReaderVerticalScrollView` 重构为 `CustomScrollView` + `center` 锚点：
  以「进入纵向模式时所在的章」为坐标原点，锚点之上的 sliver 坐标**独立于锚点**，
  向上插入内容天然不改变锚点及以下的布局 —— **无需任何补偿**，从机制上消除错位帧；
- 页面新增 `_verticalAnchorIndex` 与 `_verticalCenterKey`（跨帧稳定），
  并把「进入纵向模式 / 纵向内换章 / 冷启动恢复纵向模式」三条路径收敛到 `_resetVerticalFlow()`；
- 分隔线由**块首**移到**块尾**：尾部线只取决于「后面还有没有块」，
  前插不会改变任何已有块的布局（这一步是消除残余 54px 下移的关键）；
- 删除 `VerticalFlowEngine.compensateOffsetAfterPrepend` 及其 5 条单测（机制已被锚点取代）。

**顺带修复的既有 bug**：冷启动直接落到纵向模式时，长卷序列与锚点从未初始化
（此前只在「手动切换模式」时初始化）→ 上次退出时是纵向模式的用户再次进入会**整屏空白**。

**验收**：新增 4 条组件测试，核心断言是「向上前插后 `controller.offset` 仍为 0」
且「锚点章节标题的**屏幕坐标逐像素不变**」。`flutter analyze` **0 问题**；
`flutter test` **196/196 通过**；架构门禁通过。

**调试备忘**：`CustomScrollView.center` 之前的 sliver，其子项是「列表越靠前离锚点越远」，
因此向上序列必须**倒序取用**；另外 `SliverList` 懒加载是预期行为，
屏幕外的章节不会出现在 widget 树上，测试断言不能依赖它们。

### 🧩 统一「加载到即已下载」语义（取消独立的「会话级内存缓存」概念）

**背景（旧模型的错位）**：正文来源长期存在两套并存概念 ——
「会话级内存缓存（退出即失）」与「沙盒离线下载（持久化）」，
于是出现自相矛盾的行为：**读了的不存，没读的反而存了**。

| 入口 | 改造前 | 改造后 |
|---|---|---|
| 当前章联网抓取成功 | ❌ 只写内存，退出即失 | ✅ 内存镜像 + 落盘 |
| `prefetch` / `prefetchAdjacent` | ❌ 只写内存 | 已删除，统一为 `downloadOffline` / `downloadAdjacent` |
| 章节自带正文（无远程地址） | ❌ 只写内存 | ✅ 内存镜像 + 落盘 |
| `handleChapterJumped` | 分「具备 / 不具备离线条件」两条路 | ✅ 统一走 `downloadAdjacent` |

**改动**：

- 新增 `_mountLoadedContent()` 作为「加载到正文」之后唯一的收尾动作：写内存镜像 + `persistOffline`；
  落盘不可用时（未绑定书籍标识 / 解析规则）静默跳过，正文仍保留在内存镜像供本次阅读；
- **删除 `prefetch`** —— 它是「只进内存」这套旧概念的载体。`downloadOffline` 已完整覆盖其能力
  （内存镜像命中 → 复用落盘、零网络；沙盒命中 → 直接返回；都没有 → 一次抓取同时写内存与沙盒），
  且落盘失败时 `ensureContent` 已把正文写入内存镜像，**不丢失任何原有能力**；
- `prefetchAdjacent` → `downloadAdjacent`（名字如实反映行为），`handleChapterJumped` 委托给它，
  不再保留「内存专用分支」；
- 删除 `onPrefetched` 回调：内容就绪只剩 `onPersisted` 一个通知出口；
- `ChapterCache` 定位注释重写：从「会话级缓存」改为**已加载正文的阅读期内存镜像**，
  并明确「淘汰不会丢失内容 —— 只要该章已落盘，下次会被重新读回」，
  从根上消除「两套缓存」的理解歧义；
- 底部栏按钮在无离线条件时不再谎报「预取」，改为如实提示「未绑定书籍标识，无法离线留存」。

**验收**：管道单测增至 **13 条**，新增覆盖「内存镜像命中时零网络落盘」
「沙盒已命中则不重复 IO」「一次抓取同时写内存与沙盒」「相邻章下载跳过已落盘章节」
「`handleChapterJumped` 与 `downloadAdjacent` 行为一致」。
`flutter analyze` **0 问题**；`flutter test` **197/197 通过**；架构门禁通过。

**可见变化**：阅读过的章节会全部落盘（约 6 KB/章），底部「已下载」计数随阅读持续增长；
换来的是断网可读、退出重进不丢 —— 这正是「缓存即离线」的应有之义。

### 📥 阅读全链路离线优先（离线下载的章节不再联网读）

**背景**：`ChapterContentPipeline.ensureContent` 早已实现完整的三级正文来源
（内存会话缓存 → 沙盒离线文件 → 网络沙箱抓取），纵向续载与预取也确实走的是它；
但**当前章加载 `_loadChapterContent()` 自己重写了一套「缓存 → 网络」，把离线那一级整段丢了** ——
导致目录里显示「已下载」的章节，在线阅读时仍会联网抓取，断网时明明已落盘却读不到。

**改动**：

- `_loadChapterContent()` 在「内存缓存命中」之后、「网络抓取」之前插入沙盒离线读取：
  - 先用同步的 `isOfflineDownloaded()` 守卫，未下载时零开销、路径与原来完全一致；
  - **刻意不设置 `_isLoadingContent`** —— 本地文件 IO 耗时极短，否则会出现
    「明明已下载却仍闪一下加载态」；
  - 读盘期间用户可能已切走，故 `await` 之后校验 `_currentChapterIndex == index` 再挂载；
  - 离线文件读不到（损坏 / 被外部清理）时不报错，继续降级到自带正文 / 网络。
- `_isChapterContentAvailable()` 纳入 `isOfflineDownloaded()`：衔接页就绪判定与真实可用性一致，
  已离线章节滑到章末同样无缝切章（与上一批的体验修复形成闭环）。
- **口径统一（销账 APP_TODO 第 10 项）**：底部控制栏由「已缓存 N 章」（内存口径）改为
  「已下载 N 章」（沙盒口径），与目录抽屉顶部、下载管理页完全同源；
  该按钮此前图标是 `downloadOutline`、文案是「已缓存」、行为却只是内存预取，三者自相矛盾，
  现改为**真正下载下一章到沙盒**（`downloadOffline` 内部复用已抓取正文，零额外网络请求），
  未绑定书籍标识 / 解析规则时降级为会话内预取。

**顺带修复（写单测时查出的隐患）**：`readOffline()` 此前未包异常，沙盒文件损坏 / 被外部清理时
本地 IO 异常会直接冒泡 —— 而 `ensureContent` 的 try 只包住网络段、`_appendNextVerticalChapter`
更是裸调用，一次坏文件就能把整个纵向阅读流打断。现改为读取失败一律静默返回 null，
由调用方回退到下一级来源。

**验收**：新增 8 条管道单测（内存命中不碰离线也不碰网络 / 离线命中绝不发起网络请求 /
离线空串与抛异常时降级 / 未配置书籍标识时不触碰离线存取等），
用 `FileSystemException` 替身真实覆盖了坏文件路径。
`flutter analyze` **0 问题**；`flutter test` **192/192 通过**；架构门禁通过。

### 🔧 修复横向滑动翻章的 260ms 过渡页停留（就绪章节应与点击翻页一样无缝）

**问题**：横向模式下跨章有两条路径，行为不一致 ——

| 路径 | 实现 | 表现 |
|---|---|---|
| 点击左右区域 | `_goToNextPage` → `_switchChapter()` 直接切 | 无缝 ✓ |
| 滑到章末 / 章首衔接页 | `_autoAdvanceToNextChapter()` → `Future.delayed(260ms)` → 切章 | 衔接页停留 260ms，「正在进入下一章」可见 ✗ |

且原注释自称的「防抖」是**假的**：延迟回调里没有任何取消逻辑，用户滑回也拦不住切章，
它唯一实际效果就是把过渡页钉在屏幕上 260ms。

**修复**：

- 新增统一入口 `_advanceToBridgeChapter(index, {toLastPage})`：
  **正文已可渲染时立即 `_switchChapter`**（与点击翻页走完全同一条路径，零等待、不留过渡页）；
  仅当目标章正文确实还没到时才保留 260ms，让加载提示有机会被看到（此时等待是真实的）；
- 新增 `_isChapterContentAvailable(index)`：严格口径 —— 只有内存缓存命中或章节自带正文
  才算就绪；**正在预取（`_prefetching`）不算**（此时切过去只会看到整页加载态，
  不如留在衔接页展示「正在预取正文...」更诚实）；
- 新增 `_isChapterBridgeReady(index)` = 上述口径 + 预取中，供衔接页的图标与文案使用；
  衔接页原先各自复制一份的判定表达式已收敛到该方法（消除口径漂移）；
- 顺带修正判定口径：原写法只查 `_contentCache.containsKey`，漏掉「章节自带正文但尚未进缓存」
  的情况（详情页直传正文的单章书会误显示转圈）。

**验收**：新增 2 条组件测试（章末无缝续读 / 章首无缝回溯），断言以**页码归属**为准
而非章节标题 —— 衔接页的 `chapterTitle` 与目标章标题相同，只看标题会把
「停在衔接页」误判为「已切章」（该坑在调试中实际踩到过）。
`flutter analyze` **0 问题**；`flutter test` **184/184 通过**；架构门禁通过。

**调试备忘**：`PageController.jumpTo()` 的参数是**像素**而非页码，
传页码只会静默偏移几像素、`onPageChanged` 永不触发；驱动翻页必须用 `jumpToPage()`。
另：测试环境下三区点击热层会让 `PageView` 收不到拖拽手势，组件测试需直接驱动页码。

### 🐛 修复 `SearchSession` 三处状态位缺陷（独立逻辑修复，与上一批纯搬运分离）

**背景**：上一批为纯搬运，严格 1:1 保留原行为；本批在此基础上做逻辑审计，共查出三处缺陷。

**① `loadingMore` 跨轮次永久卡死（原代码遗留真 bug，影响可见）**

- **根因**：原分页收尾为 `if (mounted && _searchEpoch == thisEpoch) setState(() => _loadingMore = false)`——
  **轮次过期就跳过复位**；而 `search()` 开头从不重置 `_loadingMore`；
- **触发**：上滑触发分页 → 30ms 让出窗口内用户点「搜索」（手机高频操作）→ 旧分页被 epoch 守卫
  `return` 掉，`loadingMore` 永久为 `true`；
- **后果**：底部永久显示「加载更多中...」转圈，且 `_onScroll` 的 `!loadingMore` 守卫永久拦截
  → **上滑分页彻底失效**，直到下次清空 / 返回；
- **修复**：`search()` 开头复位 `loadingMore`；分页收尾改为**只在仍属于自己这一轮时**复位
  （避免旧轮次误关新轮次正在进行的分页）；`loadMore` 守卫补上 `loading`，
  使「首轮检索」与「分页」严格互斥；`cancel()` 追加防御性复位。

**② `clearResults()` 不中止在途检索**

- **问题**：只清 `allResults` 并复位两个 loading 标志，**不递增轮次 Epoch**，导致
  「返回 / 清空后后台仍跑完全部源（资源白烧）」+「在途回包写回已清空结果集（幽灵数据）」+
  「留下 `statusMap` / `rulePageMap` / `currentQuery` 三个字段不清（名实不符）」；
- **修复**：补齐 `_epoch++`（等价隐式取消）并同步清空各源状态、分页游标与关键词。

**③ `isSameRule(null, null)` 返回 `true` 的语义陷阱**

- **问题**：`return a == b` 让「两个空源」被判为同一个源，上层过滤逻辑一旦两侧同时为 null 就会静默走偏；
- **修复**：任一侧为 null 一律判定不同。当前无生产调用点命中（已逐个核对），属消除定时炸弹。

**顺带**：`_handleBack` / `_performSearch` 中对 `selectedRule` 的直接赋值改为 `selectRule()`，
确保该字段变更也触发重建（此前 `_handleBack` 的赋值静默不通知）。

**验收**：新增 4 条单测（清空彻底性、在途回包被轮次丢弃、分页被打断后标志不卡死、分页与检索互斥）；
`flutter analyze` **0 问题**；`flutter test` **182/182 通过**；架构门禁通过。

### 🧱 结构重构收尾（P2 末批：播放器 / 搜索 / 规则调试三大页面 + P4 测试对齐 + P5 CI 门禁）

**改动**：

**1. 播放器最后一块视图归位（`aura_player.dart` 1197 → 1150 行）**

- `player_overlays.dart` 追加 `PlayerLockButton`：全屏浮动锁屏键（垂直居中、左边缘与底栏进度条同轴、
  240ms 淡出 + 缩放、`Ctrl` 态图标切换）。`_buildLockButton`（53 行）整体删除，
  页面侧只留 **1 行显隐条件装配**（`_isFullScreen` 守卫上提到页面，组件不再感知"何时该渲染"）；
- 页面不再需要 `Ionicons.lock*`，锁图标依赖随组件迁移。

**2. `search_page.dart` 1656 → 328 行（-80.2%，拆分 11 个文件）**

| 层 | 文件 | 职责 |
|---|---|---|
| models | `search_result.dart` / `rule_search_status.dart` | 规范化结果条目（含 `displayTag` 兜底）、单源检索状态 |
| engines | `search_aggregator.dart` | 规则 Key 安全提取、`isSameRule` / `isVideoRule`、条目提取、`hasMore` 判定、按源过滤、完成度 |
| engines | `search_concurrency_pool.dart` | **受控并发池**：固定 Worker 数依次取任务，`shouldAbort` 在每个任务前校验 |
| controllers | `search_session.dart` | `ChangeNotifier` 承载结果集 / 各源状态 / 分页游标 / 轮次 Epoch |
| widgets | `search_app_bar` / `search_history_panel` / `search_source_filter_bar` | 顶部搜索栏、历史与探索面板、源筛选胶囊栏 |
| widgets | `search_list_card` / `search_grid_card` | 横版视频与竖版海报两套列表 / 网格卡片 |
| widgets | `search_results_view` / `search_result_list_view` / `search_result_grid_view` / `search_result_footer` / `search_placeholder_views` | 结果区三态分发 + 列表 / 网格 / 底部状态 / 等待与空态 |

- **轮次 Epoch 机制原样保留**：所有回包校验 epoch，杜绝上一轮迟到结果污染新一轮；
- 页面收敛为「输入交互 + 页面装配」，`SearchSession` 承担全部可变检索状态。

**3. `rule_tester_page.dart` 1181 → 272 行（-77.0%，拆分 9 个文件）**

| 层 | 文件 | 职责 |
|---|---|---|
| models | `rule_test_step.dart` | 阶段枚举 + `RuleTestStep`（含 `reset()`） |
| engines | `rule_test_report.dart` | 默认关键词匹配、JSON 美化（循环引用降级）、阶段文案、Markdown 诊断报告 |
| engines | `rule_test_log_filter.dart` | 按规则标签 + 本轮起始时间过滤日志；报告行 / 控制台行格式化 |
| controllers | `rule_test_pipeline.dart` | 四阶段接力流水线（发现 → 搜索 → 详情 → 解析），阶段产物载体原样保留 |
| widgets | `rule_test_app_bar` / `rule_test_control_header` / `rule_test_step_card` / `rule_test_console` | 顶栏、关键词与开始/停止、阶段卡片、沙箱控制台 |

- `buildMarkdown` 的 `generatedAt` 改为**入参**而非内部 `DateTime.now()`，报告可被单测断言；
- 日志过滤逻辑此前只能手工点测，现已被 4 条单测覆盖。

**4. P4 · 测试目录全量镜像**

- 根目录 4 个散落测试按被测源路径归位（`unit/core/sandbox`、`unit/features/browser/engine`、
  `widget/features/rules/pages`）；
- 根目录 771 行的 `widget_test.dart` 拆分并删除，按被测源镜像为 12 个文件
  （`widget/shared/widgets/**`、`widget/features/{search,settings,media}/**`）；
- **测试隔离度提升的直接证据**：拆出后 `media_detail_page_test.dart` 暴露了两处隐性依赖 ——
  规则引擎 500ms 延迟初始化定时器未被排空（`Pending timers` 失败）、
  `RuleService` 依赖同文件内前序用例的 GetIt 注册。已通过显式 `pump(600ms)` 排空定时器
  与显式注册补齐，两处均已正交化。

**5. P5 · CI 门禁落地**

- 新增 `app/tool/guardrails/check_architecture.dart`（纯 `dart:io`，零第三方依赖）：
  1. `lib/domain/**` 出现 `flutter` / `material_ui` / `go_router` / `ionicons` / `dart:ui` → 失败；
  2. `lib/shared/**` 反向 import `package:fluxforge/features/` → 失败；
  3. `lib/` 下 UI 文件（含 Widget 定义或位于 `pages|widgets|views`）超过 **300 行** → 失败；
- 存量技术债登记在 `tool/guardrails/baseline.txt`（21 条），并提示"已销账待删除"的行，
  形成只减不增的收敛机制；
- 新增 `.github/workflows/app-quality.yml`：`flutter analyze` → 架构门禁 → `flutter test` 三道关卡。

**验收**：`flutter analyze` **0 问题**；`flutter test` **178/178 全部通过**（较上批 +41）；
架构门禁 `check_architecture` 通过。

### 🎥 P2 拆分巨型文件（第二十二批：视频画面层与断点续播提示）

**改动**：

- 新增 `shared/widgets/player/player_video_surface.dart`：`PlayerVideoSurface`
  - 承载三种画面比例（`contain` 用 `AspectRatio` 保持原始比例居中；`cover` / `fill` 用
    `SizedBox.expand + FittedBox` 撑满避免黑边）与水平镜像翻转；
  - 未就绪时退化为封面海报，封面也缺失时返回空容器由外层底色兜底 —— 这套降级链逐字保留；
  - 页面侧 `_buildVideoSurface` 由 63 行降为 **8 行装配**；
  - 组件依赖 `video_player`（播放控制器是渲染必需输入），但不依赖任何业务 service。
- `player_overlays.dart` 追加 `PlayerResumeTip`：断点续播气泡（「上次看到 X」+ 跳转继续 / 关闭），
  页面侧 `_buildResumeTip` 由 52 行降为 **14 行**，文案与两个动作均通过回调接入。

**顺带清理**：迁移后 `aura_player.dart` 的 `dart:math` / `dart:ui` 两个导入失效
（`math.pi` 镜像变换与 `ImageFilter` 毛玻璃随之移出），已一并删除；
`ImageFilter` 的依赖转入 `player_overlays.dart`。

**验收**：`flutter analyze` **0 问题**；`flutter test` **137/137 全部通过**。
`aura_player.dart` **2166 → 1069 行**（第十三～二十二批合计 **-1097，-50.6%**）。

### ⬆️ P2 拆分巨型文件（第二十一批：顶部控制条 `player_top_bar.dart`）

**改动**：新增 `shared/widgets/player/player_top_bar.dart`：

| 组件 | 说明 |
|---|---|
| `PlayerTopBar` | 顶部渐变条 + 返回键 + 标题 + 扩展操作区 + 更多设置；内边距由上层算好后整体传入（与 `PlayerControlBar` 同一约定） |
| `PlayerMoreSettingsButton` | 右上角「更多设置」；全屏下靠右固定尺寸容器（与进度条 / 全屏键右对齐），非全屏用 `IconButton` |

- 页面侧 `_buildTopBar` 由 54 行降为 **25 行装配**，`_buildMoreSettingsButton`（31 行）整体删除；
- 返回键显隐条件改为显式的 `showBackButton`（原为 `_isFullScreen || widget.onBack != null`），
  由上层判定后传入 —— 组件不再感知"什么时候该显示返回键"这条业务规则；
- 触感反馈内聚进按钮，与 `PlayerControlButtons` 保持一致；
- 顺带按 lint 建议把 `if (extraActions != null) ...extraActions!` 改为空感知展开 `...?extraActions`。

**验收**：`flutter analyze` **0 问题**；`flutter test` **137/137 全部通过**。
`aura_player.dart` **2166 → 1158 行**（第十三～二十一批合计 **-1008，-46.5%**）。

### 🪟 P2 拆分巨型文件（第二十批：控制浮层与微型进度条）

**改动**：向 `shared/widgets/player/player_overlays.dart` 追加三个浮层组件：

| 组件 | 说明 |
|---|---|
| `PlayerAnimatedBar` | 控制条显隐动画：微位移与淡出同步播放（顶栏上滑 / 底栏下滑），收起时不拦截点击 |
| `PlayerControlOverlays` | 顶 / 底两条控制栏的浮层容器；`topBar` 传 null 即表示本条不参与渲染 |
| `PlayerBottomMiniProgress` | 小屏常驻的 2px 微型进度条。`currentPosition` 用 `ValueGetter` 由上层注入，保证手势预览局部重建时拿到最新进度 |

- 页面侧 `_buildControlOverlays` 由 28 行降为 **13 行**、`_buildBottomMiniProgress` 由 39 行降为 **15 行**，
  `_buildAnimatedBar`（20 行）整体删除；
- **渲染守卫保留在页面侧**（全屏 / 未初始化 / 播放错误时不渲染微型进度条）——
  这是依赖播放状态的条件，属于页面职责；组件只负责视觉与动画。

**验收**：`flutter analyze` **0 问题**；`flutter test` **137/137 全部通过**。
`aura_player.dart` **2166 → 1214 行**（第十三～二十批合计 **-952，-44%**）。

### 🧷 P2 拆分巨型文件（第十九批：手势层外壳 `player_gesture_layer.dart`）

**背景**：第十八批已把分区判定与滑动算法抽成纯引擎，但页面里仍留着 `LayoutBuilder` +
`GestureDetector` 的接线代码，以及"把手势坐标换算成归一化比例"这一步 ——
前者是纯 UI 管道，后者是可在组件内统一处理的机械换算。

**改动**：新增 `shared/widgets/player/player_gesture_layer.dart`：

| 组件 | 说明 |
|---|---|
| `PlayerGestureLayer` | 未锁定态手势层：`LayoutBuilder` 取真实宽高 → 归一化 → 语义化回调；**分区判定在组件内统一调用一次**（原来分散在页面闭包里） |
| `PlayerLockedGestureLayer` | 锁定态极简层：仅捕获单击切换锁图标，完全拦截滑动/双击/长按 |

- 回调签名改为语义化：`onVerticalDragUpdate(zone, deltaRatio)` 与
  `onHorizontalDragUpdate(deltaRatio)`，页面侧不再出现 `primaryDelta / totalWidth` 这类换算；
- **除零保护**：`totalWidth <= 0` / `totalHeight <= 0` 时传 0，避免未完成布局时产生
  `NaN` 污染手势状态（原实现在未布局时可能写入 NaN）；
- 长按/双击等无参数手势用 `VoidCallback` 替代 `(_) {}`，签名更诚实；
- 组件不持有任何播放状态、不依赖 `video_player`，符合 ADR 对 `shared/widgets/` 的约束。

**验收**：`flutter analyze` **0 问题**；`flutter test` **137/137 全部通过**。
`aura_player.dart` **2166 → 1271 行**（第十三～十九批合计 **-895，-41%**）。

> 本批行数仅 -15：手势**逻辑**仍属页面状态机，抽走的只是接线管道与机械换算。
> 收益在结构（页面不再出现 `LayoutBuilder`/`GestureDetector`）与安全性（除零保护）。

### 🖐️ P2 拆分巨型文件（第十八批：手势引擎 `player_gesture_engine.dart`）

**背景**：手势层里最复杂、最容易出 bug 的两块计算埋在两段 `onXxxDragUpdate` 闭包中，只能靠真机拖动验证：

1. 垂直滑动的**分区判定**（左 35% 调亮度 / 右 35% 调音量 / 中间不响应）与量程换算；
2. 水平快进/快退的**浮点累积 + 毫秒精度 + 越界位移回写** —— 这正是此前"左右滑动不流畅"
   优化的核心算法，却没有任何测试保护。

**改动**：新增 `shared/widgets/player/player_gesture_engine.dart`（无状态纯函数）：

| API | 职责 |
|---|---|
| `zoneOf(localX, totalWidth)` | 手势分区；宽度为 0（尚未布局）时返回 `none`，避免除零误判 |
| `applyVerticalDrag(current, deltaRatio, min, max)` | 1.5 倍灵敏度量程换算 + 限幅（亮度下限 0.15 以免全黑） |
| `seekSecondsPerScreen(duration)` | 横滑档位分档：≤300 秒用 60 秒/屏，否则 120 秒/屏 |
| `resolveSeekTarget(...)` | 浮点累积求目标位置，并**回写越界位移** |
| `displayDeltaSeconds(accumulated)` | 浮层 `+15s / -8s` 的取整展示 |

- 页面侧两段手势闭包改为调用引擎：垂直滑动从 27 行降为 20 行且分区语义显式；
  水平滑动从 20 行降为 16 行，注释中的两条设计要点（浮点累积、越界回写）随实现迁入引擎文档。
- **新增 18 个单元测试**（`test/unit/shared/widgets/player/player_gesture_engine_test.dart`）：
  分区边界值（350 / 650 归入中间区）、宽度为 0、灵敏度换算与上下限、
  恰好 300 秒仍属短片档、**慢速滑动的浮点累积不丢精度**（每帧 0.24 秒累积三帧 = 0.72 秒，
  逐帧取整则会退化为 0）、**拖到片尾后越界回写使回滑立即响应**、时长未知时不产生非法 `Duration`。

**验收**：`flutter analyze` **0 问题**；`flutter test` **137/137 全部通过**（119 → 137）。

### 🎨 P2 拆分巨型文件（第十七批：进度条轨道绘制 `player_track_shape.dart`）

**背景**：`AuraSliderTrackShape` 是 160 行的自定义 `SliderTrackShape`，纯 Canvas 绘制逻辑
（消除原生 24px 内缩留白、统一三条轨道粗细、未加载区呼吸 + 流光扫光动效），
却与 1500 行的播放器页面挤在同一个文件里。

**改动**：整体迁至 `shared/widgets/player/player_track_shape.dart`。

- **类名不变**，因此 `_buildProgressSliderBody` 里的引用无需任何改动，只新增一条 import ——
  这是最安全的抽取形态：**零调用点改动、零行为变化**；
- 依赖收敛为 `dart:math` + `material_ui` + `AppColors`，与播放器内核、`video_player` 完全解耦；
- 文档注释中的三条设计目标（消除内缩边距 / 统一粗细 / 流光动效）随类一起迁移。

**验收**：`flutter analyze` **0 问题**；`flutter test` **119/119 全部通过**。
`aura_player.dart` **2166 → 1273 行**（第十三～十七批合计 **-893，-41%**）。

### 📊 P2 拆分巨型文件（第十六批：控制栏 `player_control_bar.dart` / `player_control_buttons.dart`）

**背景**：控制栏 7 个方法共 326 行内联在页面里 —— `_buildBottomBar` + 宽/窄两套布局 +
时间文本 + 三个按键，其中「全屏 / 非全屏」的分支散落在每个按键内部。

**改动**：

- 新增 `shared/widgets/player/player_control_bar.dart`：`PlayerControlBar`
  - 承载底部渐变遮罩、宽版布局（时间组合 + 全宽进度条 + 三键行）与小屏紧凑布局（单行居中）；
  - 两种布局**复用同一套控件**，差异仅在排布 —— 原来"全屏/非全屏"的分支在 5 处各写一遍；
  - 内边距由上层算好后整体传入（含全屏避让与底部安全区），组件不依赖 MediaQuery 细节；
  - **`currentPosition` 声明为 `ValueGetter<Duration>` 而非值** —— 时间文本要在
    手势预览的局部重建中拿到最新进度，传值会停留在建树那一刻（这一点写进了文档注释）。
- 新增 `shared/widgets/player/player_control_buttons.dart`：`PlayerPlayPauseButton` /
  `PlayerSpeedButton` / `PlayerFullscreenButton`
  - 触感反馈（`HapticFeedback.lightImpact()`）内聚到按键内部，调用方只表达"切换播放状态"；
  - 全屏下的贴边对齐（`Alignment.centerLeft` / `centerRight` + 固定 42/38 尺寸容器）
    与图标尺寸分档全部保留。
- **进度条刻意不抽**：`_buildProgressSlider` / `_buildProgressSliderBody` 需要缓冲比例、
  拖拽阻尼状态（`_isDraggingProgress` / `_dragProgressValue`）、seek 防抖定时器与
  `_shimmerController` 等播放器内部细节，抽出将被迫搬走一整套拖动状态机。
  改为通过 `PlayerProgressSliderBuilder` 由上层注入 —— 控制栏只负责它在两种布局中的位置。
- 页面侧 `_buildBottomBar` 由 25 行降为 **30 行装配**（含回调语义化），
  并删除 `_buildWideControlLayout` / `_buildCompactControlLayout` / `_buildTimeText` /
  `_buildPlayPauseButton` / `_buildSpeedButton` / `_buildFullscreenButton` 共 222 行。

**验收**：`flutter analyze` **0 问题**；`flutter test` **119/119 全部通过**。
`aura_player.dart` **2166 → 1415 行**（第十三～十六批合计 -751）。

### 🎛️ P2 拆分巨型文件（第十五批：播放设置抽屉 `player_settings_panel.dart`）

**背景**：`_showMoreSettingsDrawer` 178 行 + `_buildFitChip` 30 行 + `_buildSettingSwitchRow` 43 行
内联在页面里，且通过 `StatefulBuilder` 的 `setDrawerState` 从外部驱动抽屉局部刷新 ——
页面被迫持有并传递一个**纯 UI 刷新句柄**，`_buildSettingSwitchRow` / `_buildFitChip` /
`_buildSpeedChip` 三个辅助方法也都只为这一个抽屉服务。

**改动**：

- 新增 `shared/widgets/player/player_settings_panel.dart`：`PlayerMoreSettingsPanelBody`
  （`StatefulWidget`）
  - **`StateSetter` 彻底消失**：抽屉内容改为自身持有「展示副本」
    （`_isMirrored` / `_isLooping` / `_videoFit` / `_preferences`），
    改动后先 `setState` 立即回显、再上抛语义化回调；
  - 抽屉是模态的，页面状态不会被外部改动，因此无需双向同步 —— 这一点写进了文档注释；
  - `_applyPreferences(next)` 用 `copyWith` **只构造一次**新偏好值，避免先改本地、再重复构造上抛值；
  - 触感反馈（`HapticFeedback.lightImpact()`）从页面移到面板，与原「点击先震一下」的时序保持一致。
- `player_settings_sheets.dart` 追加 `showPlayerMoreSettingsDrawer(...)`：只负责弹出外壳
  （右滑入场动画 + 毛玻璃 + 遮罩），内容委托给面板；对外 9 个语义化参数，
  **不泄漏任何 UI 刷新细节**。
- `player_overlays.dart` 追加 `PlayerSettingSwitchRow` 与 `PlayerFitChip`
  （两者均返回 `Expanded`，需置于 `Row`，已写入文档注释）。
- 页面侧 `_showMoreSettingsDrawer` 由 178 行降为 **13 行**；删除
  `_buildFitChip` / `_buildSpeedChip` / `_buildSettingSwitchRow` 共 91 行。

**验收**：`flutter analyze` **0 问题**；`flutter test` **119/119 全部通过**。
`aura_player.dart` **2166 → 1615 行**（第十三～十五批合计 -551）。

### 🎚️ P2 拆分巨型文件（第十四批：倍速抽屉 + 播放器状态层 `player_settings_sheets` / `player_overlays`）

**改动**：

- 新增 `shared/widgets/player/player_settings_sheets.dart`：`showPlayerSpeedDrawer`
  - 把 135 行的 `showGeneralDialog` 内联块收成一个命令式函数，页面侧 `_showPlaybackSpeedDialog`
    从 135 行降为 **13 行**，只保留「取当前倍速 → 回调里写控制器与偏好」；
  - 档位常量 `kPlayerSpeedOptions` 提到模块级，避免每次弹窗重复构造列表；
  - 选项行拆为 `PlayerSpeedOptionTile`，选中态样式与 `HapticFeedback` 反馈内聚在组件内；
  - 页面回调仍负责 `setState` 与 `_startControlsTimer()`，抽屉不感知播放器状态。
- 新增 `shared/widgets/player/player_overlays.dart`：
  - `PlayerSpeedChip`：长按加速倍率胶囊（返回 `Expanded`，需置于 `Row`，已写入文档注释）；
  - `PlayerStateOverlay`：加载中 / 失败重试两层状态合一，页面侧 `_buildStateOverlay()`
    从 39 行降为 **5 行**；
  - 顺带清理迁移后失效的 `app_loading.dart` 导入。

**验收**：`flutter analyze` **0 问题**；`flutter test` **119/119 全部通过**。
`aura_player.dart` **2166 → 1858 行**（第十三 + 十四批合计 -308）。

### 🎬 P2 拆分巨型文件（第十三批：播放器手势浮层胶囊 `player_capsules.dart`）

**背景**：`aura_player.dart`（2166 行）的视图层此前未拆，四个手势浮层各自内联了
完整的毛玻璃容器结构 —— 亮度与音量两个胶囊**代码几乎逐行重复**，仅「图标 / 贴边方向 / 偏移」不同。

**改动**：抽出 `shared/widgets/player/player_capsules.dart`：

| 组件 | 说明 |
|---|---|
| `PlayerVerticalIndicatorCapsule` + `PlayerCapsuleSide` | 亮度 / 音量合并为一个组件，靠 `side` 决定贴左还是贴右、`icon` / `value` 由调用方传入 |
| `PlayerSeekingCapsule` | 居中快进 / 快退胶囊，入参为 `deltaSeconds` 与已格式化的 `targetLabel` |
| `PlayerFastForwardCapsule` | 长按加速顶部微胶囊（无状态、无参数） |

- **消除重复**：亮度与音量两份 48 行的容器结构合并为一份，页面侧只剩两个 6 行装配；
- **保留视觉细节**：毛玻璃模糊半径、`RotatedBox(quarterTurns: -1)` 竖条、
  快进翡翠绿 `#10B981` / 快退琥珀金 `#F59E0B`、百分比文案字号等全部逐字保留；
- **顺带修掉一处死代码**：亮度胶囊原图标为 `_brightness > 0.5 ? sunnyOutline : sunnyOutline`
  （三元两支相同），现直接传 `Ionicons.sunnyOutline`，行为等价；
- **职责边界**：组件不感知业务规则（如「音量为 0 用静音图标」由页面算好后传入），
  符合 ADR 对 `shared/widgets/`「不得依赖业务 service」的约束。

**验收**：`flutter analyze` **0 问题**；`flutter test` **119/119 全部通过**。
`aura_player.dart` **2166 → 2025 行**（-141）。

### 🧩 P2 拆分巨型文件（第九～十二批：状态视图 / 进度引擎 / 内容管道 / 目录导航 / 偏好持久化）

本轮把 `novel_reader_page.dart` 从 **1443 行压到 1191 行**，并新增 5 个模块与 42 个单测。

**第九批 · 状态视图（`widgets/reader_status_views.dart`，134 行）**
- 抽出 `ReaderEmptyScaffold`（无章节空态）、`ReaderLoadingView`（抓取中等待态）、
  `ReaderErrorView`（抓取失败 + 重试入口）；
- 主页面留下三个状态分流分支，`_buildEmptyScaffold` 整体删除（101 行）；
- 顺带清理因迁移而失效的 `ionicons` / `app_colors` 两个导入。

**第十批 · 进度换算引擎（`engines/reader_progress.dart`，70 行 + 28 单测）**
- 抽出的纯计算：`charOffsetFromPage`、`pageIndexFromCharOffset`、`horizontalProgress`、
  `pageIndexFromRatio`、`verticalProgress`、`verticalOffsetFromRatio`、`ratioFromCharOffset`
  与两个进度文案函数；
- 明确了三条此前只存在于代码里的边界语义并写进文档注释：
  **偏移恰好落在页边界归入下一页**、**偏移超出正文归入末页**、**章块不足一屏视为读完**；
- `_currentCharOffset` / `_restoreReadingPosition` / `_chapterProgress` / `_chapterProgressLabel` /
  `_seekChapterProgress` 全部收敛为引擎调用。

**第十一批 · 内容管道（`controllers/chapter_content_pipeline.dart`，218 行）**
- 把三级正文来源（内存缓存 → 沙盒离线 → 网络沙箱）与两种后台策略（预取 / 落盘）收敛为一个组件；
- **新增可替换的 `OfflineChapterStore` 接口**：生产环境走 `GlobalOfflineChapterStore`（接全局
  `downloadService`），使沙盒依赖变成可注入的窄接口，而非散落的全局函数调用；
- `RuleEngine.parse` 亦通过 `parseRule` 函数注入，默认真实实现 —— 管道因此可完全脱离沙盒与网络测试；
- 页面删除 9 个方法（`_ensureChapterContent` / `_readOfflineChapter` / `_prefetchChapter` /
  `_downloadChapterOffline` / `_persistChapterOffline` / `_canDownloadOffline` /
  `_isOfflineDownloaded` / `_handleChapterJumped` / `_maybePrefetchAdjacent`，共 190 行）；
- 页面状态（`setState`）、纵向失败熔断解除、缓存容量回收均通过回调留在页面，管道不触碰 UI。

**第十二批 · 目录导航（`engines/catalog_navigator.dart`，26 行 + 8 单测）+ 偏好持久化（`controllers/reader_preferences.dart`，74 行 + 6 单测）**
- 目录的「显示行号镜像映射」与「停靠偏移（上方保留 2 行上下文）」抽为纯计算，
  固定行高常量一并归位；页面里的 `_catalogItemHeight` 字段删除；
- 偏好读写收敛到 `ReaderPreferences`：四个键名与取值集中定义，类型化写入，
  移除页面 `_savePreference(key, dynamic)` 这类靠关键字字符串 + 动态类型的分发；
- **读取语义更严谨**：`load()` 返回的字段可空，**未持久化过的项保持 null**，
  页面据此逐项覆盖 —— 避免把「未设置」误当作「设置为默认值」；
  脏数据（未知配色名 / 未知模式标识）分别回落 `parchment` 与横向。

**验收**：`flutter analyze` **0 问题**；`flutter test` **119/119 全部通过**。

### 🎛️ P2 拆分巨型文件（第八批：排版设置面板 `ReaderSettingsPanel`）

**背景**：`_buildSettingsDrawer()` 199 行内联在 `State` 中，把「护眼底色 / 翻页模式 / 字号 / 行距」
四组控件的布局与页面状态（含偏好持久化）耦合在一起。

**改动**：

- 新增 `widgets/reader_settings_panel.dart`：`ReaderSettingsPanel`
  - **纯展示 + 回调上抛**：组件不持有状态、不接触 `_savePreference`，偏好写入全部由上层在回调里完成；
  - 11 个属性拆出语义边界清晰的行为：`onThemeSelected` / `onPageModeSelected` /
    `onDecreaseFont` / `onIncreaseFont` / `onLineHeightChangeStart` / `onLineHeightChanged` /
    `onLineHeightChangeEnd`；
  - **边界判断（字号 12~32、`onChangeStart` 锚点、`onChangeEnd` 还原）留在上层** ——
    这些规则与「阅读位置保持」逻辑同属页面职责，不适合下沉到 UI 组件；
  - 组件返回 [Positioned]（`bottom: 96` 等定位常量由组件持有），文档标注需置于 `Stack` 内使用；
  - 「点击当前已选中的翻页 Chip 不触发切换」的防抖判定保留在组件内，因为它是纯交互语义
    （`ChoiceChip` 点击时回调参数为 `!selected`，组件据此拦截）。
- 主页面 `_buildSettingsDrawer()` 收敛为 **38 行薄封装**（原 199 行）。

**新增 5 个组件测试**（`test/widget/.../widgets/reader_settings_panel_test.dart`）：
字号 / 行距回显、A+ / A- 分别上抛、选择其它配色回传对应主题、
**点击已选中翻页模式不触发切换**、点击未选中翻页模式触发切换。

**踩坑记录（值得复用的约定）**：本仓库使用 **vendored `material_ui`**（包内自带一份 material 源码副本），
因此测试**必须** `import 'package:material_ui/material_ui.dart'` 而不是 `flutter/material.dart` ——
两者是**不同的 `Material` 类**，混用会让 `debugCheckHasMaterial` 找不到祖先，
报 `No Material widget found`（最初 5 个用例全红即此原因）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **77/77 全部通过**（含新增 5 个组件测试）。
主文件 **1597 → 1443 行**（-154）。

### 🖼️ P2 拆分巨型文件（第七批：纵向长卷视图 + 横向翻页视图）

**背景**：主页面里剩下的最大两块 UI 代码 —— `_buildHorizontalPageView`（151 行）与
`_buildVerticalScrollView`（77 行）—— 直接内联在 `State` 中，与分页状态、缓存、手势回调耦合。

**改动**：

- 新增 `widgets/reader_horizontal_page_view.dart`：`ReaderHorizontalPageView`
  - 承载页眉（章节名 / 书名）、`LayoutBuilder` 翻页主体、`PageView.builder` 与底部页码指示器；
  - **分页计算上抛**：`LayoutBuilder` 只把实测宽高通过 `onViewportResolved(w, h)` 交回上层，
    视图本身不感知 `TextPainter` 排版细节；
  - **语义判定上抛**：`onPageChanged` 只转发 `PageView` 原始页码，
    「滑入衔接页 → 自动切章 / 滑入正文页 → 同步页码 + 双向预取」留在上层 `_onHorizontalPageChanged`；
  - 衔接页改为直接传入 `previousBridge` / `nextBridge`（为 null 即不存在相邻章节），
    视图据 `!= null` 自算总页数，因此主页面里仅供其使用的 `_nextBridgeCount` / `_totalPageCount`
    两个 getter 一并删除；
  - `pageController` 保持可空，与重构前「为空时由 PageView 自建控制器」的行为一致。
- 新增 `widgets/reader_vertical_scroll_view.dart`：`ReaderVerticalScrollView`
  - 承载长卷 `ListView`（含末尾续载占位、章节分隔与标题、全书末尾提示）与外层 `SelectionArea`；
  - 正文取值通过 `contentOf(index)` 回调上抛，组件不依赖 `ChapterCache`，
    保持「纯展示」定位；`hasMore` 由上层用 `VerticalFlowEngine.hasMoreBelow` 算好后传入；
  - 主页面保留 `_buildVerticalScrollView()` 作为薄封装，继续承担「序列兜底至少含当前章 /
    确保当前章有 blockKey」这两个状态职责。
- 抽出的两个方法均为**纯 UI 搬运**：样式取值、`clamp` 区间、`ValueKey` 组成方式、
  空正文占位与末页提示文案全部逐字保留。

**验收**：`flutter analyze` **0 问题**；`flutter test` **72/72 全部通过**
（两个新组件由既有 6 个 `NovelReaderPage` widget 测试间接覆盖，本轮未新增用例）。
主文件 **1749 → 1597 行**（-152）。

### 🧵 P2 拆分巨型文件（第六批：纵向长卷流程引擎 `VerticalFlowEngine`）

**背景**：纵向连续滚屏的续载判定散落在 `_onVerticalScroll` 与两个 async 续载方法里，
边界分支（首章 / 末章 / 加载中 / 失败熔断）埋在 `setState` 之间，只能靠手工滚动验证。

**改动**：抽出 `reader/engines/vertical_flow_engine.dart`，5 个无状态纯函数 + 1 个意图枚举：

| API | 职责 |
|---|---|
| `resolveIntent(pixels, maxScrollExtent, threshold)` | 滚动位置 → `none / appendNext / prependPrev / both`，阈值默认 480px；内容不足一屏时返回 `both` |
| `nextAppendTarget(sequence, appending, failed, chapterCount)` | 向下续载目标，null 表示末章 / 加载中 / 已失败熔断 |
| `prevPrependTarget(sequence, appending, failed)` | 向上前插目标，null 表示首章 / 加载中 / 已失败熔断 |
| `hasMoreBelow(sequence, failed, chapterCount)` | 底部是否仍显示加载占位（决定「全书完」提示时机） |
| `compensateOffsetAfterPrepend(beforeOffset, insertedHeight, maxScrollExtent)` | 前插后的偏移补偿；**高度未知时返回 null 表示不跳转**，避免画面跳变 |

- 调用点收敛：`_onVerticalScroll` 的两条 `if`（原硬编码 `480`）改为消费意图枚举；
  `_appendNextVerticalChapter` / `_prependPrevVerticalChapter` 的 3 行前置守卫各自收敛为一次引擎调用；
  `_buildVerticalScrollView` 的 `hasMore` 表达式改为引擎调用；
  前插补偿的 `clamp` 内联表达式改为引擎调用。
- **新增 24 个单元测试**（`test/unit/.../engines/vertical_flow_engine_test.dart`）：
  意图四态 + 阈值边界（**恰好等于阈值不触发**）+ 自定义阈值；续载目标的正常 / 空序列 /
  末章 / 首章 / 加载中 / 失败熔断；`hasMoreBelow` 四态；偏移补偿的正常相加、clamp 到
  `maxScrollExtent`、负偏移 clamp 到 0、高度为 0 与负高度返回 null。

**验收**：`flutter analyze` **0 问题**；`flutter test` **72/72 全部通过**（含新增 24 个引擎单测）。

### 🗃️ P2 拆分巨型文件（第五批：会话缓存 `ChapterCache` + LRU 淘汰）

**背景**：`novel_reader_page.dart` 里 `final Map<int, String> _contentCache = {}` 是一张**无上限**的裸 Map，
被 18 处直接操作；它既是「切章零等待」的性能层，又承担「章节是否已就绪」的判定职责，
却没有任何淘汰策略（APP_TODO 第 2 项）。

**改动**：

- 抽出 `reader/controllers/chapter_cache.dart`：`ChapterCache` 类封装这张表
  - 内部用 Dart Map 的**插入顺序**实现访问序 LRU（读取即重插 → 置为最近使用），零额外数据结构开销；
  - 提供 `containsKey` / `[]` / `[]=`（运算符重载让 **18 处调用点几乎零改动**）/ `nonEmptyCount` /
    `seedFromChapters` / `evictOverflow(protect:)`；
  - `capacity` 默认 200 章（按单章约 6 KB 估算 ≈ 1.2 MB），`<= 0` 表示不限制。
- 阅读器侧新增两个收口方法，替换原先散落的 5 处裸写入：
  - `_cacheChapterContent(index, content)`：写入缓存 + 触发回收；
  - `_evictChapterCacheIfNeeded()`：按容量上限回收，并**同步清空 `_chapters[i].content`**
    （否则 String 仍被章节模型持有，内存不会真正释放）。
- **保护集合**是安全性的关键，淘汰时以下章节永不回收：
  - `_verticalSequence`（纵向长卷正在渲染的章节，淘汰会出现空白块）；
  - 当前章、`_prefetching`、`_downloadingChapters`；
  - **没有远程地址的章节**（如详情页直传的单章正文）—— 一旦淘汰将永久无法重新获取。
  - 若保护集合本身已超容，宁可暂时超出也不淘汰正在阅读的内容。
- `_cachedChapterCount` 由 `entries.where(...)` 改为 `nonEmptyCount`。
- **新增 10 个单元测试**（`test/unit/.../controllers/chapter_cache_test.dart`）：基本读写、重复写入不产生重复条目、
  `seedFromChapters` 跳过空正文、未超容不淘汰、超容淘汰最久未使用者、**读取刷新 LRU 顺序**、
  `protect` 内永不淘汰、全保护时宁可持续超容、`capacity <= 0` 不限制。

**验收**：`flutter analyze` **0 问题**；`flutter test` **48/48 全部通过**（含新增 10 个缓存单测）。

### ✂️ P2 拆分巨型文件（第四批：分页引擎 + 首批逻辑单测）

- 抽出 `reader/engines/pagination_engine.dart`：把原先内嵌在 State 中的 `_computeTextPages()`（64 行）
  提炼为**纯函数引擎** `PaginationEngine.sliceIntoPages()` —— 无状态、不依赖任何页面状态；
- 页面侧 `_recalculatePages()` 改为调用引擎，只保留视口尺寸缓存与页码修正等状态写入；
- **新增首批逻辑单元测试**（`test/unit/features/media/novel/reader/engines/pagination_engine_test.dart`，5 个用例）：
  1. 空文本返回单页空串；
  2. 尺寸非法时原样返回全文，交由调用方兜底；
  3. 长文本切分为多页且**拼接可还原全文**（不丢字符）；
  4. 可用高度越小，分页数越多（单调性）；
  5. 每页高度不超过可用高度（段落吸附最多容忍一行误差）。
- **测试暴露的既有边界**：段落自然吸附在「断点恰好是换行符」时会在其后多带 1 个字符，
  使该页高度可能超出可用高度至多一行。因属既有行为、且改动会影响分页结果与阅读位置还原，
  本次**未改算法**，仅在测试中显式记录容忍度，并记入 APP_TODO 第 14 项供后续评估。
- **累计进度**：`novel_reader_page.dart` **2193 → 1705 行**（-488 行，-22%）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **38/38 全部通过**（含 5 个新增逻辑单测）。

### ✂️ P2 拆分巨型文件（第三批：顶栏 + 底栏，阅读器降至 1757 行）

- 抽出 `reader/widgets/reader_top_bar.dart`：顶部控制栏（返回 / 书名 / 刷新章节 / 章节目录），约 **75 行**；
- 抽出 `reader/widgets/reader_bottom_bar.dart`：底部控制面板（章内进度条 + 上一章 / 下一章 + 进度文案 +
  四个功能按钮），并把原先的私有 `_buildActionButton` 提升为可复用的 `ReaderBarActionButton`，约 **180 行**；
- 页面侧 `_buildTopBar()` / `_buildBottomControls()` 分别收缩为 7 行 / 18 行的参数装配，
  `_buildActionButton()`（24 行）整体移除；
- **累计进度**：`novel_reader_page.dart` **2193 → 1757 行**（-436 行，-20%），
  已抽出 4 个模型文件 + 5 个 widget（三区热层 / 衔接页 / 目录抽屉 / 顶栏 / 底栏）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**。

### ✂️ P2 拆分巨型文件（第二批：目录抽屉，阅读器降至 1905 行）

- 抽出 `reader/widgets/reader_catalog_drawer.dart`：章节目录抽屉
  （顶部信息栏「书名 + 已下载进度」+ 正序/倒序切换 + 关闭按钮 + 固定行高章节列表 + 三态下载图标），约 **130 行**；
- 组件设计为**纯展示**：章节数据、当前章索引、单章下载状态判定全部由宿主传入，
  选择章节 / 单章下载 / 切换排序 / 关闭等行为通过回调上抛 —— 它不依赖任何仓储或页面状态，可独立进行 Widget 测试；
- 页面侧 `_buildCatalogDrawer()` 收缩为 18 行参数装配，`_buildCatalogItem()` 整体移除；
- **累计进度**：`novel_reader_page.dart` **2193 → 1905 行**（-288 行），已抽出 4 个模型文件 + 3 个 widget。

**验收**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**。

### 🎬 AuraPlayer 完成业务解耦并归位 `shared/`（ADR D1 落地）

**目标**：让播放器成为真正可复用的通用组件。它此前直接读写全局设置仓储（`appService.settings`），
因此按依赖规则只能留在 feature 内。

**改动**：

- 新增 `shared/widgets/player/player_preferences.dart`：纯值对象 `PlayerPreferences`
  （长按加速开关 + 倍率，含 `copyWith` / `==` / `hashCode`），零业务依赖；
- `AuraPlayer` 新增两个注入点：
  - `preferences` —— 偏好由宿主传入（默认 `const PlayerPreferences()`，既有调用方零改动）；
  - `onPreferencesChanged` —— 用户在播放器设置抽屉内调整偏好时，回调宿主持久化；
- 内部 **7 处 `appService` 引用全部替换**：长按开关 / 倍率的两个 getter、设置抽屉的开关值、
  开关写入、倍率条件渲染、倍率选中判断、倍率写入；全屏路由内的自引用一并透传两个新参数；
- **移除 `app/di/di.dart` 导入** —— 播放器不再认识依赖容器；
- **归位**：`features/media/video/player/aura_player.dart` → `shared/widgets/player/aura_player.dart`，
  满足「`shared/` 不得依赖 `data/` 与 `app/di`」的硬约束（ADR D1 的落地判据）；
- 业务侧 `video_detail_view.dart` 承担注入与持久化职责：监听 `appService.settingsNotifier`，
  设置变化时重新注入偏好；`onPreferencesChanged` 中写回全局设置。

**验证**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**；
`grep` 确认播放器文件内已无 `appService` 与 `app/di` 引用。

**顺带发现（已记入 APP_TODO 第 13 项）**：设置项 `enablePlayerGestures`（播放手势开关）
在播放器内**从未被读取**，即该开关当前不生效。因属行为变更，未在本次一并接入。

### ✂️ P2 拆分巨型文件（第一批：小说阅读器 2193 → 2034 行）

**目标**：`novel_reader_page.dart` 原本 2193 行，承担分页算法、纵向长卷、目录抽屉、排版设置、
进度换算、预取调度等十余项职责，按设计文档拆为 15 个文件。

**本批完成**：

| 抽出内容 | 新文件 | 性质 |
| :--- | :--- | :--- |
| 护眼配色 `ReaderTheme` | `reader/models/reader_theme.dart` | UI 模型（含 `Color`，按 ADR D3 留在 feature 内） |
| 翻页模式 `PageTurnMode` | `reader/models/page_turn_mode.dart` | 模型 |
| 章节模型 `NovelChapter` | `reader/models/novel_chapter.dart` | 模型（纯 Dart） |
| 章块几何 `_ChapterMetrics` → `ChapterMetrics` | `reader/models/chapter_metrics.dart` | 模型（跨文件使用，去掉私有前缀） |
| 三区点击热层 | `reader/widgets/reader_tap_zones.dart` | 无状态 Widget（三回调注入） |
| 章首 / 章末衔接页（合一） | `reader/widgets/reader_chapter_bridge.dart` | 无状态 Widget（文案参数化，两个方向共用） |

**顺带收益**：

- `NovelChapter` 与 `ChapterMetrics` 成为**纯 Dart 类型**，可脱离 Widget 单测（为 P4 铺路）；
- 衔接页两个方向原本是约 90 行近乎重复的实现，现合并为一个参数化组件，杜绝"只改一边"的不一致；
- `reader_tap_zones` 注释更正为与现状一致（正文已由 `SelectableText` 改为 `SelectionArea` + `Text`）。

**过程中的失误与修正**：一次批量替换把模型提取块的 `new_str` 误填为 import 语句，导致重复导入 + 注释粘连；
通过读取实际文件状态定位并修复（`analyze` 0 问题、测试全绿）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**。

**后续批次**：目录抽屉（约 250 行）→ 顶栏/底栏（约 400 行）→ 横向/纵向视图 → 排版设置面板 →
最后提取 `controllers/`（状态编排、章节缓存）与 `engines/`（分页算法、长卷引擎）。

### 🧭 P1 路由参数类型化：以强类型 Args 取代 extra 魔法字典

**背景**：此前所有跳转都以 `extra: <String, dynamic>{'title': ..., 'url': ...}` 传参 ——
键名写错不会有编译期提示，只能在运行时表现为"参数丢了"；且路径字符串在注册端与跳转端各写一遍。

**新增（`app/router/`）**：

| 文件 | 职责 |
| :--- | :--- |
| `app_routes.dart` | 路由路径常量。同时提供「跳转用绝对路径」与「注册用相对段」—— GoRouter 子路由 `path` 必须为相对段 |
| `route_args.dart` | 4 个参数模型：`SearchArgs` / `RuleArgs` / `RuleDetailArgs` / `MediaDetailArgs`，各带 `tryParse` 集中解析与容错（兼容「参数类对象 / 裸 `Rule` / 旧字典」三种形态） |
| `app_navigator.dart` | `BuildContext` 扩展：`pushRuleDetail()` / `pushSearch()` / `pushMarket()` 等 15 个类型化导航方法，并 `export route_args.dart`，调用方只需一个 import |

**改造范围**：

- **注册端**：5 个含参路由改为 `XxxArgs.tryParse(state.extra)`，原先散在 `app_router.dart` 里的内联 Map 解析（约 70 行）全部移除；
- **跳转端**：**12 处**带参跳转改为类型化方法（覆盖 discover / search / rules / rule_catalog / history 五个功能），**9 处**无参跳转改为扩展方法；
- **顺带修复**：`main.dart` 中 `router.go('/home')` 指向了**不存在的路由**（实际路径为 `/`），会导致兜底跳转失败，已改用 `AppRoutes.home`；
- **顺带简化**：`rules_page` 中手工 `Uri.encodeComponent` 拼接的 `/web?url=...&title=...` 改为 `pushBrowser()`（内部用 `Uri` 构造，自动编码，杜绝截断）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**；全项目已无 `context.push('/xxx')` 与 `extra: {` 形式的残留（仅剩说明性注释）。

### 🧱 P0 目录结构重构落地：feature-first 六层骨架 + 全量绝对 import

**背景**：`lib/` 原本按技术类型横向切分（`views` / `widgets` / `services` / `models` / `engines` / `core`），
单个功能的代码散落在 4~6 个目录，功能边界不可见。方案见 [`APP_STRUCTURE_REWORK.md`](./APP_STRUCTURE_REWORK.md)。

**步骤 1 · 相对 import 全量统一为绝对 import**

- 把 `lib/` 与 `test/` 中的 **196 处** `../` / `./` 相对 import 与 **49 处**无前缀同级相对 import
  （如 `import 'router.dart';`）全部改写为 `package:fluxforge/...`；
- 收益：此后移动文件不再需要重算相对路径（亦为 Flutter 官方推荐写法）。

**步骤 2 · 目录搬迁（纯移动，业务逻辑零改动）**

- **55 个文件**迁入新的六层结构：

| 顶层 | 职责 | 内容 |
| :--- | :--- | :--- |
| `app/` | 装配层 | `di`（原 `services/di.dart`）、`router`（原 `lib/router.dart`）、`theme`（原 `core/theme/`） |
| `core/` | 技术基建 | `logging`（原 `core/utils/app_logger.dart`）、`sandbox`（原 `services/rule_engine.dart`）、`network` / `storage` / `utils` |
| `domain/` | 领域模型 | `media` / `rule`（原 `models/`）、`text`（原 `core/utils/novel_text.dart`） |
| `data/` | 数据访问 | `backup` / `download` / `library` / `rule` / `settings`（原 `services/` 下 8 个服务） |
| `shared/` | 跨功能组件 | `widgets/`（原 `widgets/` 下 6 个通用组件） |
| `features/` | 业务功能 | `shell` / `splash` / `discover` / `search` / `rules` / `profile` / `settings` / `browser` / `library`（favorites·history·downloads）/ `media`（shared·video·novel·comic） |

- `features/browser/engine/` 收纳原 `engines/`（广告拦截、网页视频手势引擎）；
- `widgets/player/aura_player.dart` 暂归 `features/media/video/player/` —— 待 P2 完成播放偏好解耦后
  再下沉至 `shared/widgets/player/`（见设计文档 ADR D1）；
- **删除死代码** `views/dev/card_gallery_page.dart`（824 行，路由入口此前已移除）。

**验收**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**；无任何业务逻辑改动。

**下一步**：P1 路由参数类型化 → P2 拆分 6 个千行文件 → P3 抽 `controllers/` 状态层 → P4 测试目录对齐 → P5 CI 门禁。

### 🧱 新增《移动端目录结构重构设计方案》

- 新增 [`docs/APP_STRUCTURE_REWORK.md`](./APP_STRUCTURE_REWORK.md)：基于当前 `lib/` 61 个文件、约 2.5 万行的实测数据，给出结构重构蓝图：
  - **诊断**：根源不在命名，而在"按技术类型横向切分"——单个功能的代码散落在 4~6 个目录；6 个文件超 1000 行、2 个超 2000 行；`services/` 与 `widgets/` 职责混装；路由以 `extra: Map<String, dynamic>` 魔法字典传参；缺少状态管理层；
  - **目标**：`app`（装配）/ `core`（技术基建）/ `domain`（纯 Dart 模型）/ `data`（Repository）/ `shared`（跨功能 UI）/ `features`（按功能垂直切分）六层，并给出 5 条依赖方向硬约束（如 feature 之间禁止互相 import）；
  - **交付物**：完整目标目录树、**61 个文件的迁移映射表**、`novel_reader_page.dart`（2193 行 → 15 文件）与 `aura_player.dart`（2154 行 → 12 文件）的拆分清单、配套的路由类型化与测试目录对齐方案、P0~P5 分阶段迁移路径与验收标准、以及"明确不做的事"（不引状态框架 / 不拆多包 / 不引代码生成）。
- 同步更新 `docs/README.md` 文档索引。

### 🗂️ 文档体系整理：新增待优化清单，清除过时文档

- **新增 [`docs/APP_TODO.md`](./APP_TODO.md)**：汇总已确认存在但尚未处理的技术问题与优化项共 12 项，按「收益 / 风险」分级：
  - **阅读器**：纵向长卷内存无上限、`_contentCache` 无淘汰策略、滚动同步每帧测量、加载失败熔断无提示、目录排序不持久化；
  - **播放器**：**播放期每帧 `setState` 全树重建（收益最高的一项）**、寻道期间仍在解码、长按与拖动的手势竞争；
  - **全局**：「已缓存」与「已下载」口径不一致、横向模式仍用 `SelectableText`、内存压力主动释放未实现；
  - 并附「已确认无需处理」结论（正文非双份存储、纵向下两个横向专用变量恒为 false 等），避免后续重复排查。
- **清除过时文档**：
  - 删除 `docs/APP_ROADMAP.md` —— 其 P0/P1/P2 规划项（断点续播、小说阅读器、漫画查看器、收藏追更、备份还原、离线下载、规则测速）**均已落地**，内容严重滞后；
  - 删除根目录 `CONVERSATION_SUMMARY.md` —— 旧项目名（FluxView）时代的会话归档，已完全过时。
- **同步修复失效引用**：`docs/README.md` 文档索引、根 `README.md`、`app/README.md` 中对 `APP_ROADMAP.md` 的链接与描述已更新为 `APP_TODO.md`（`CHANGELOG.md` 内的历史引用按惯例保留）。

### ⚡ 纵向长卷渲染优化：单个 SelectionArea 替代逐块 SelectableText

- **内存与卡顿排查结论**：
  - 正文常驻内存的来源是**纵向长卷**：`_verticalSequence` 只增不减，读过的章节正文全部留在 `_contentCache` 与 `_chapters[i].content` 中（二者指向同一 String 引用，并非双份存储），且没有淘汰策略；
  - 单章 3000 中文字 ≈ 6 KB（Dart String 为 UTF-16），1000 章 ≈ 6 MB，**内存量级本身可控**；
  - **真正的卡顿源是渲染而非内存**：长卷中每个章节块都是一个 `SelectableText`，每个实例都会建立独立的 `EditableText` 与选择容器，多章并存时布局与绘制开销显著。
- **本次优化**：长卷改为「外层单个 `SelectionArea` + 内部纯 `Text`」—— 选择容器只建立一次，长按划词与跨章复制能力完整保留，渲染成本大幅下降。
- **未改动**：横向分页模式仍使用 `SelectableText`（每页独立、视口内通常仅 1~3 页，成本可控）。
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**。

### ⬇️ 阅读临时缓存与离线下载职责分离（跳章时前后各下载一章）

**最终形态：两类机制各司其职**

| 机制 | 触发场景 | 是否落盘 | 生命周期 |
|---|---|---|---|
| **临时缓存** | 翻页 / 纵向续载的邻近预取（`_prefetchChapter`） | ❌ 仅内存 | 本次会话，退出阅读器即释放 |
| **离线下载** | 跳章（前后各一章）、目录手动单章、详情页全本下载 | ✅ 沙盒 | 持久化，断网可读 |

**演变说明**：上一版曾把「预取」也一并落盘，使得「这次看完下次还在」，抹掉了原有临时缓存的语义；本版按职责重新拆分。

**关键改动**

- `_prefetchChapter` 恢复为**纯内存临时缓存**（不再落盘）：保留「这次可以直接看、下一次就没了」的原有体验，阅读过程不静默占用磁盘；
- 新增 `_handleChapterJumped()`：跳章后把**前后相邻章节各下载一章**到沙盒；正文若已在内存缓存中则**复用落盘、零额外网络请求**，否则才调度一次抓取；不具备离线条件时退化为纯内存预取；
- 新增 `_downloadChapterOffline()` / `_persistChapterOffline()` / `_canDownloadOffline`，目录手动下载改为复用同一路径（已缓存章节不再二次抓取）；
- `DownloadService` 收敛为单一落盘入口 `saveNovelChapterContent()`（正文由调用方提供），删除刚引入却已无调用者的 `downloadNovelChapter()` 及中转方法 `_markNovelChapterCompleted()`，避免两套单章下载逻辑并存。

**质量验证**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**。

### 📖 小说阅读器：统一缓存与下载、修复翻章加载动画、修复纵向长卷滚动与进度

**① 阅读缓存与离线下载统一为一套**

- 新增 `DownloadService.downloadNovelChapter()` 单章离线下载 API，与全本下载**共用同一套沙盒目录**（`<bookDir>/<index>.txt`）与**同一份任务记录**（`completed` 集合）：单章下载过的章节全本下载自动跳过，反之亦然。
- 新增 `_ensureNovelTask()`：单章下载时若本书尚无任务，按 `paused` 创建记录 —— 既不自动开跑全本，又保证阅读器目录与下载管理页读到一致状态。
- 目录「云端图标」由**只写内存缓存**改为**真正落盘下载**，成功后回填内存缓存；目录顶部文案改为「已下载 N 章」，状态图标统一为「已下载 / 下载中 / 未下载」三态（移除原先易误解的「已缓存」对勾态）。
- 内存缓存 `_contentCache` 退居阅读期加速层，读取优先级仍为「内存 → 沙盒 → 网络」。

**② 修复已缓存章节翻章仍出现加载动画**

- 根因：章首 / 章末衔接页**无条件渲染 `CircularProgressIndicator`**，即使 `isReady`（正文已就绪 / 已下载）也照样转圈，造成「明明已缓存却仍在加载」的错觉。
- 修复：`isReady` 时改为展示对勾就绪图标，仅未就绪才显示转圈。

**③ 修复纵向长卷中段无法向上滚动**

- 根因：只有 `_appendNextVerticalChapter()` 向下追加逻辑，**完全没有向上前插**，长卷滚到顶部后就再也无法回溯前文。
- 修复：新增 `_prependPrevVerticalChapter()`，在「距顶不足 480px」时静默前插上一章；因前插会把既有内容整体下移，采用**下一帧实测新块高度后补偿滚动偏移**，保证画面不跳变；并继续向上预取再上一章。

**④ 修复纵向模式加载多章后进度条不准**

- 根因：`_chapterProgress` 纵向分支以**整条长卷的 `maxScrollExtent`** 作分母，而长卷每追加一章分母就变大 → 同一物理偏移对应的比例自行回退，加载章节越多偏差越大；文案却标注为「本章 X%」。
- 修复：新增 `_verticalChapterMetrics()`，借助 `RenderAbstractViewport.getOffsetToReveal` 实测当前章块顶部偏移与高度，进度改为**章块内滚动比例**（0% = 章首对齐，100% = 章末读尽，章块不足一屏视为已读完）；同步修正 `_seekChapterProgress`（拖动改为章内定位）、`_currentCharOffset` 与 `_restoreReadingPosition`（切模式 / 改排版后的位置还原），四处共用同一套度量。
- 新增 `_ChapterMetrics` 数据类与 `package:flutter/rendering.dart` 导入。

**质量验证**：`flutter analyze` **0 问题**；`flutter test` **33/33 全部通过**（同步把目录图标断言更新为新语义）。

### 📚 小说阅读器章节目录支持正序 / 倒序切换

- **新增排序切换按钮**（`novel_reader_page.dart` 目录抽屉顶部信息栏）：一键在「正序（第 1 章在前）」与「倒序（最新章节在前）」之间切换，按钮文案与高亮色实时反映当前状态，便于追更时快速定位最新章。
- **实现要点**：
  - 新增 `_isCatalogReversed` 状态与 `_catalogDisplayIndex` 行号映射，`ListView.builder` 按显示行号镜像回真实章节索引；
  - 抽出 `_catalogOffsetForCurrentChapter()`，「打开目录」与「切换排序」共用同一套「当前章上方保留 2 行」的定位算法，两种排序下都能自动停靠到正在阅读的章节；
  - 目录展开状态下**不重建** `ScrollController`（旧控制器仍被列表占用，dispose 后会抛异常），改为在列表重建后的下一帧 `jumpTo` 并 clamp 到 `maxScrollExtent`。
- **顺带修正文案缺陷**：目录内「一键缓存」此前提示「已缓存，可离线续读」，但该操作实际只写入**内存会话缓存**（`_contentCache`），退出阅读器即失效，并不具备离线能力；现更正为「已缓存，本次阅读内可瞬时切换」，并在方法注释中明确其与沙盒离线下载的区别。
- **回归保护**：新增测试 `NovelReaderPage catalog order toggle flips chapter list order`，断言切换后第 3 章升至第 1 章上方且按钮文案变为「倒序」。
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **全部通过**。

### 🎞️ AuraPlayer 左右滑动快进快退流畅度优化

**问题定位（`widgets/player/aura_player.dart`）**：滑动寻道存在「掉帧 + 顿挫」两类问题，根因有三：

1. **每帧两次全树重建**：手势 `onHorizontalDragUpdate` 每帧 `setState`，叠加 `_onControllerUpdate` 里播放期每帧的 `setState(() {})`，导致 13 层 `Stack`（视频层 / 控制栏 / 各类浮层）每帧被重建两次 → 滑动明显掉帧。
2. **逐帧取整累积造成顿挫**：原实现 `(deltaX * scale).round()` 后再累加，慢速滑动时单帧增量常不足 0.5 秒而被截断为 0，形成「一顿一停、偶尔跳 1 秒」的不跟手手感。
3. **触顶后越界位移未回写**：拖到片头 / 片尾后继续滑动会持续累积无效位移，回滑时出现一段「不响应」的空窗期。

**优化实现**：

- **浮点累积 + 毫秒精度**：新增 `_seekDeltaRawSeconds` 做浮点累加，仅在渲染时 `round()`；目标位置按毫秒精度计算，彻底消除秒级顿挫。
- **越界回写**：将 clamp 后的实际位移回写至累积值，片头片尾回滑即时响应，无空窗期。
- **零整树重建**：新增 `ValueNotifier<int> _seekPreviewTick`，手势拖动期间只递增该 notifier；中央快进胶囊、进度条、时间文本、迷你进度条四处改为 `ValueListenableBuilder` 订阅局部重建。
- **播放帧回调短路**：`_onControllerUpdate` 在寻道进行中直接跳过 `setState`，避免「播放帧回调 + 手势回调」双重重建。
- **进度条主体拆分**：`_buildProgressSlider` 拆出 `_buildProgressSliderBody`，使订阅层与渲染主体解耦。
- 手势结束仍保留一次性 `setState`，播放意图记忆（`_effectiveIsPlaying`）与 350ms 防抖逻辑不变。

**质量验证**：`flutter analyze` **0 问题**；`flutter test` **32/32 全部通过**。

### 🧭 「我的」页入口收敛：移除广告拦截，备份 / 日志 / 关于迁入「设置」

- **「我的」页移除三项、迁移两项**：
  - 「广告拦截规则」—— **移除**：设置页「规则沙箱与网络解析」卡片已具备开关、实时规则数 / 同步时间、一键热更与 `/adblock` 跳转，属完全重复入口；
  - 「数据备份与还原」—— **迁入**设置页；
  - 「沙箱与系统日志」—— **移除**：设置页对应入口已附带等效且更完整的日志统计与 ERROR 徽标；
  - 「关于 FluxForge」—— **迁入**设置页。
- **设置页（`settings_page.dart`）**：第 5 张卡片由「关于与系统诊断」升级为「数据备份、诊断与关于」，依次为「数据备份与还原 → `showBackupSheet`」「沙箱与系统日志中心 → `/logs`」「关于 FluxForge → `_showAboutSheet`」，以分隔线分组；`_showAboutSheet` / `_buildAboutRow` 自「我的」页整体迁移，其中运行平台取值由 `defaultTargetPlatform` 调整为等价的 `Theme.of(context).platform`，省去 `foundation.dart` 依赖。
- **「我的」页连带收敛**：原「系统与关于」整区移除 —— 该区仅剩的「系统偏好设置」与 Hero 卡右上角齿轮完全重复，而齿轮本就是设置唯一入口。页面现由「身份 Hero → 继续观看 → 资产网格 → 数据与同步（规则市场 / 离线下载 / 缓存）」构成，「我的」彻底回归资产仪表盘定位。
- **清理**：`profile_page.dart` 移除 `foundation.dart`、`app_logger.dart`、`backup_sheet.dart` 三个不再使用的导入，并删除 `_showAboutSheet` / `_buildAboutRow` 共 105 行。
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **32/32 全部通过**。

### 📳 阅读界面取消点击触感反馈

- **变更动机**：小说 / 漫画阅读属于高频、长时沉浸场景，单击翻页与呼出菜单的震动反馈带来不必要的感官干扰，统一改为纯视觉反馈。
- **小说阅读器（`novel_reader_page.dart`）移除 6 处触感**：
  - 左 / 右三区点击翻页（`_goToPreviousPage` / `_goToNextPage`）原 `selectionClick`；
  - 翻页模式切换（`_togglePageMode`）原 `selectionClick`；
  - 章节预取（`_prefetchNextChapter`）、打开章节目录（`_showCatalogDrawer`）、目录内一键缓存（`_downloadChapterFromCatalog`）原 `lightImpact`。
- **漫画阅读器（`comic_reader_page.dart`）移除 1 处**：阅读模式切换（`_toggleReadingMode`）原 `lightImpact`。
- **配套清理**：两个文件的 `import 'package:flutter/services.dart'` 仅服务于 `HapticFeedback`，移除后已无用，一并删除（静态分析此前报 `unnecessary_import`）。
- **未改动范围**：影视 / 小说 / 漫画**详情页**与视频播放器的触感反馈保持原状，本次仅收敛「阅读界面」。
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **32/32 全部通过**。

### 🖱️ 修复阅读器错误页「重试加载」按钮被三区点击热层遮挡

- **问题现象**：章节正文加载失败时，错误页的「重试加载」按钮点不到，点击反而会呼出控制栏（命中了三区热层的中间区域）。
- **根因**：三区点击热层是 `Positioned.fill` 全屏覆盖，且层级位于 `_buildReaderBody` **之上**；错误页属于正文分支的一部分，其按钮手势被热层抢走。
- **修复（`novel_reader_page.dart`）**：
  1. 新增 `_isContentErrorState` getter，统一判定「正文加载失败且无可用内容」；
  2. build 中热层改为条件渲染：错误态下**撤除热层**，让点击直达「重试加载」按钮；
  3. `_buildReaderBody` 的状态 B 分支复用同一 getter，避免两处判定逻辑漂移。
- **设计取舍**：**保留**重试按钮而非删除 —— 该状态下重试入口即按钮本身，无需再靠点击呼出控制栏；且修复只需一个判断，不存在「判断过多不优雅」的问题。
- **回归保护**：新增测试用例 `NovelReaderPage error state keeps retry button clickable without tap-zone interception`，断言错误态出现「重试加载」，且点击后不会呼出控制栏。
- **质量验证**：`flutter analyze` **0 问题**；`test/widget_test.dart` **22/22 全部通过**。

### 🔧 修复小说阅读器「回退到上一章」定位失效

- **问题现象**：在中间章节的第一页点击左侧区域（或向右滑入章首衔接页）回退时，无法正确定位到上一章最后一页，而是停在被 clamp 过的错误页码。
- **根因定位（三层叠加）**：
  1. `PageView` 的 key 包含当前章节索引（`ValueKey('novel_pageview_${_currentChapterIndex}_$totalCount')`），切章时**必然触发重建**；
  2. `_syncPageController()` 在 `setState` 之后**同步**调用 —— 此时旧 PageView 尚未销毁（build 未执行），`jumpToPage` 作用在即将被丢弃的实例上；
  3. build 完成后新 PageView 挂载，`PageController` 重新 attach 并回退到**创建时**的陈旧 `initialPage`，最终停在被 `clamp` 过的错误页码；
  4. 由于「下一页」的目标页为第 0 页（数值小），偏差不易察觉；而「上一页」目标为末页（数值大），问题立即暴露 —— 这正是只在「回退」时被发现的根本原因。
- **修复方案（`novel_reader_page.dart` → `_syncPageController`）**：
  - 统一延迟到**下一帧**（`addPostFrameCallback`：build 已完成、新 PageView 已挂载）再执行定位；
  - 若延迟执行时控制器仍未挂载，则以正确目标页码**重建** `PageController`，杜绝沿用陈旧 `initialPage`；
  - 补充成因注释，防止后续被改回同步调用而再次踩坑。
- **质量验证**：`flutter analyze` **0 问题**；`test/widget_test.dart` **21/21 全部通过**（含「衔接页与 seek 同步不应误触发章节回退」用例）。

### 📖 小说阅读器向前翻页、对称桥接页与 PageView 真实页码偏移加固

- **背景与代码审查**：
  - 用户提交了 `2c9f8ff`，实现了横向翻页模式下向左倒序翻页功能：
    1. 在 `_hasPrevChapter` 时于 PageView 首位增加「上一章桥接页」(`_buildPreviousChapterBridge`)，滑入第 0 页后通过 `_autoAdvanceToPreviousChapter` 自动倒序回退到上一章最后一页；
    2. 新增 `_openAtLastPage` 标记与 `toLastPage` 参数，使 `_switchChapter` 支持自动定位到目标章最后一页，实现了正序读与倒序翻的完整闭环；
    3. 点击热区左侧 1/3 区域支持在第 1 页时直接触发倒序回退到上一章最后一页；
    4. 引入 `_maybePrefetchAdjacent` 实现双向静默预取，前后相邻章节均提前缓存；
    5. 新增 `_syncPageController` 统一按真实页面索引（考虑桥接页偏移 `_prevBridgeCount`）进行 `jumpToPage`。
- **审查发现的严重边界隐患**：
  1. **排版变更/模式切换后阅读位置恢复偏移**：
     `_restoreReadingPosition` 原代码直接使用切片索引 `target` 执行 `controller.jumpToPage(target)`。
     当用户在非第 1 章的第 1 页正文处（`target = 0`）调整字号、行距或从纵向切回横向时，会直接跳到 PageView 的 index 0（**上一章桥接页**），导致误触发 `_autoAdvanceToPreviousChapter()` 强行倒退回上一章！在第 2 页以上时也会因少算 1 个桥接页偏移而导致显示的切片倒退 1 页。
  2. **底栏章内进度条拖动偏移**：
     `_seekChapterProgress` 原代码直接使用 `target` 执行 `_pageController?.jumpToPage(target)`。
     拖动进度条到最左侧（0%）时会跳到 index 0 触发误退回上一章；拖到最右侧（100%）时因少加 `_prevBridgeCount` 无法跳转到最后一页。
- **加固方案与重构**：
  - 将 `_restoreReadingPosition` 与 `_seekChapterProgress` 中直接调用 `jumpToPage(target)` 的地方全面替换为统一的 `_syncPageController()`；
  - 彻底复用 `_syncPageController()` 内对 `_prevBridgeCount` 偏移、切片索引 clamp 以及控制器生命周期状态的防御逻辑；
  - 在 `app/test/widget_test.dart` 中新增针对性测试 `NovelReaderPage horizontal bridge and seek synchronization does not accidentally trigger chapter retreat`，全量覆盖进度条拖拽与桥接页安全隔离。
- **质量验证**：
  - `flutter analyze` **0 错误、0 警告 (No issues found!)**；
  - `flutter test` **31/31 测试全部通过 (All tests passed!)**。

## [2026-09-18]

### 📥 离线下载功能上线：小说全本与漫画整部下载至 App 沙盒

- **用户诉求**：增加下载功能；经确认范围为 **小说 + 漫画**、存储于 **App 沙盒内**、**纯手动下载**（不做自动下载与视频下载）。
- **新增服务 [`DownloadService`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/services/download_service.dart)**：
  1. **任务模型 `DownloadTask`**：记录书籍标识、标题封面、媒体类型、绑定规则、待下载目标列表（小说=章节 URL / 漫画=图片 URL）、已完成与失败下标集合、状态与时间戳；
  2. **调度策略**：
     - 任务级并发上限 2、任务内严格串行：既能并行推进多本，又避免单站点被高频请求打爆触发风控；
     - **断点续传**：已完成下标落盘持久化，重启 App 自动跳过已下载项继续；
     - **失败熔断**：单项失败记入 `failed` 且不自动重试，由用户手动「重试失败项」，杜绝死循环；
     - **节流持久化**：下载过程中进度变更按 3 秒节流写盘（复用 PlayHistoryService 的节流范式）；
  3. **沙盒存储布局**：`AppDocuments/fluxforge_offline/`
     - 小说正文：`novels/<书籍安全名>/<章节索引>.txt`
     - 漫画图片：`comics/<书籍安全名>/<URL 稳定哈希>.<扩展名>`
     - 书籍目录名采用「可读前缀 + 确定性哈希」杜绝碰撞；图片以 URL 哈希命名，与阅读顺序解耦；
  4. **公开 API**：`startNovelDownload` / `startComicDownload` / `pause` / `resume` / `retryFailed` / `remove` / `clearAll` / `readNovelChapter` / `localComicImagePath` / `totalBytes`；
- **共享正文清洗工具 [`novel_text.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/core/utils/novel_text.dart)**：
  - 把阅读器私有的正文清洗逻辑上提为公共函数，**在线阅读与离线下载复用同一套实现**，保证两处排版完全一致；
- **共享组件 [`DownloadBar`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/widgets/download_bar.dart)**：
  - 小说与漫画详情页共用的五态下载条（未下载 / 下载中可暂停 / 已暂停可继续 / 部分失败可重试 / 已完成）含实时进度条，避免两处重复实现；
- **接入落地**：
  1. **小说**：详情页「开始阅读」下方新增下载条；阅读器新增 `offlineBookId` 参数，`_ensureChapterContent` 改为 **磁盘 → 内存 → 网络** 三级优先；目录抽屉图标升级为四态（已离线 / 仅内存缓存 / 预取中 / 未缓存）；
  2. **漫画**：详情页头部新增下载条（图集 + 各分组章节全量收集）；打开阅读器前把已下载图片替换为本地路径；阅读器新增 `_buildComicImage` 统一构建，**本地文件优先、网络回退**（连续长卷与分页双模式均已接入）；
  3. **管理页 [`DownloadManagerPage`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/downloads/download_manager_page.dart)**：占用空间概览 + 任务列表（类型 / 状态 / 进度 / 失败数）+ 暂停继续重试删除 + 一键清空（均二次确认），入口挂在「我的 → 数据与同步 → 离线下载」；
- **修复**：抽取漫画图片构建方法时，`loadStateChanged` 闭包返回类型需为 `Widget? Function(...)`（否则 `return null` 触发 `return_of_invalid_type_from_closure`）；
- **本轮明确不做（边界）**：自动下载新章节、视频 / m3u8 离线、导出到系统相册或外部存储（纯沙盒，卸载即清除）。
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **31/31 全部通过**。

## [2026-09-17]

### 📊 阅读器底栏进度条改为「章内页数」语义

- **用户诉求**：弹出菜单的进度条改为当前章节的页数。
- **改造前问题**：底栏 Slider 为**章级**进度（`当前章索引 / 总章数`），拖动即直接跳章，用户无法在**本章内部**定位，也无法感知本章还剩多少页。
- **改造后**：
  1. 新增章内进度计算 `_chapterProgress`：横向翻页模式按「当前页码 / 本章总页数」，纵向长卷模式按「滚动偏移 / 最大滚动距离」；
  2. 新增拖动跳转 `_seekChapterProgress`：横向按比例换算目标页码后 `jumpToPage`（无动画，保证拖动跟手），纵向按比例换算滚动距离后 `jumpTo`；
  3. 进度条下方新增章内进度文案 `_chapterProgressLabel`：横向显示「本章 第 X / Y 页」，纵向显示「本章 N%」；
  4. 章级切换职责继续由两侧「上一章 / 下一章」按钮承担，职责边界更清晰；
  5. 纵向模式新增 `_lastVerticalProgress` 节流刷新（进度变化超过 0.5% 才触发 setState），避免滚动过程中每帧重建。
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **30/30 全部通过**。

### 👆 小说阅读器三区点击交互：左右区域翻页、中间区域呼出菜单

- **用户诉求**：阅读界面点击左边和右边区域为前后翻页，中间区域弹出菜单。
- **技术难点与方案选型**：
  - 正文采用 `SelectableText`（长按划词必需），其内部注册了 tap 识别器，**外层 `GestureDetector.onTap` 会被其赢走**
    （这正是此前只能把 onTap 直接挂在 `SelectableText` 上的原因）；
  - 而直接挂在 `SelectableText` 上的 onTap 拿不到点击坐标，无法区分左 / 中 / 右区域；
  - **最终方案**：在 `Stack` 正文之上叠加 `Positioned.fill` 的**三区透明热层**（`Row` 33/34/33 + `GestureDetector`，`HitTestBehavior.translucent`）：
    热层位于更上层因而优先被命中，可稳定赢得单击手势竞技场；且**仅注册 onTap**，长按划词、拖动选择与滑动翻页手势均不受影响；
- **交互落地**：
  1. **左 1/3**：上一页。横向模式为 `previousPage` 动画翻页；已是本章第一页时进入上一章并直接定位到其最后一页（`_switchChapterToLastPage`）；纵向长卷按屏上滚；
  2. **中 1/3**：呼出 / 收起控制栏（`_toggleControls`）；
  3. **右 1/3**：下一页。横向模式为 `nextPage` 动画翻页；已是本章最后一页时无缝续读下一章；纵向长卷按屏下滚并触发触底续载；
  4. 全书首尾给出轻提示（「已是全书第一页 / 已是最后一章」），避免反复点击却无反馈；
  5. 同步移除正文 `SelectableText` 上原有的 `onTap: _toggleControls`，单击分发统一收口到热层，杜绝双重响应；
- **回归保护**：新增测试用例 `NovelReaderPage tap zones turn pages on sides and toggle menu in center`，
  以坐标点击（右侧 `700,300` / 中间 `400,300`）验证翻页与菜单呼出；
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **30/30 全部通过**。

### 🧹 小说阅读器清除示例假章节：无章节时改渲染空态引导

- **用户疑问**：「阅读界面内有一些默认文本和章节是干嘛的」——经排查为 `novel_reader_page.dart` 中的开发期打样数据：
  - `_sampleChapterContent` 常量（《三体》风格伪造正文）与 `_setupChapters()` 中硬编码的两章示例（「第一章 科学边界」「第二章 台球与物理规律」），
    当外部未传入 `chapters` 时被注入，用于早期在没有规则数据时预览排版效果；
- **问题定位**：
  1. 与已清理的「收藏示例数据」「模拟测试日志」性质相同，均属会误导用户的假数据；
  2. 调用链核查：`NovelDetailView._openReader` 始终会传入至少一章（含本地正文兜底），**该假数据分支在生产路径根本不可达**，只会在异常/空数据场景被渲染出来；
  3. 伪造的是知名版权作品正文，用户无从分辨真假，存在明确的误导风险；
- **清理与替代方案**：
  1. 删除 `_sampleChapterContent` 常量及 `_setupChapters()` 中的示例章节注入，无章节时以空数组承载；
  2. 新增 `_buildEmptyScaffold()` 空态页（图标 + 「暂无章节内容」+「该作品尚未解析出章节目录，请返回详情页刷新后重试」+ 返回按钮）；
  3. 补齐空数据防御：`build` 空态提前返回，`_recalculatePages()` 与 `_currentCharOffset` 增加空章节保护，杜绝越界崩溃；
  4. 同步修正类文档注释（移除已废弃的「一键整章复制」描述）；
- **回归保护**：新增测试用例 `NovelReaderPage renders empty state instead of sample chapters when no chapters provided`，
  断言空章节时必须渲染空态、且不得出现任何示例正文；
- **质量验证**：`flutter analyze` **0 问题**；`flutter test` **29/29 全部通过**。

### 📚 小说目录抽屉化改造：左侧滑出、打开即定位当前章、缓存状态标识与取消整章复制

- **用户诉求**：
  1. 目录列表改为新页面或左侧弹出；
  2. 每个元素后面未下载的章节增加图标显示；
  3. 每次打开目录时定位到当前章节；
  4. 取消复制章节功能。
- **落地成果（`app/lib/views/media/novel/reader/novel_reader_page.dart`）**：
  1. **目录改为左侧滑出抽屉**：
     - 由 `showModalBottomSheet` 底部弹层改为 `Scaffold.drawer`（宽度为屏宽 76%），阅读上下文不再被完全遮挡；
     - 设置 `drawerEnableOpenDragGesture: false`，避免边缘滑动与横向翻页 / 左滑手势冲突，统一由顶栏目录按钮唤醒；
  2. **打开即定位当前章节**：
     - 每次打开前重建 `ScrollController`，以固定行高（`_catalogItemHeight = 56`）配合 `initialScrollOffset = (当前章索引 - 2) × 行高` 预置偏移，实现「打开即定位」且上方保留 2 行上下文；
     - 列表采用 `ListView.builder + itemExtent` 固定行高，保证定位精确；
  3. **章节缓存状态图标**：
     - 已缓存 → 绿色对勾图标；预取中 → 环形进度指示器；未缓存 → 云下载图标（点击即一键缓存该章，成功后自动解除纵向续载的失败熔断标记并提示）；
     - 抽屉顶部实时展示「共 N 章 · 已缓存 M 章」；当前章节以左侧高亮竖条 + 主色加粗标题标识；
  4. **取消复制章节功能**：
     - 移除顶栏「复制本章正文」按钮与 `_copyCurrentChapter()` 方法（正文本身已支持 `SelectableText` 长按划词复制，整章复制属冗余入口）；
     - 顶栏收敛为：返回 / 书名 / 刷新 / 目录；
- **测试同步**：`NovelReaderPage` 用例由「验证复制按钮与复制 SnackBar」改造为「验证目录抽屉打开、章节列表渲染与已缓存对勾图标」，用例名同步更名；
- **质量验证**：
  - `flutter analyze`：**No issues found (0 warnings, 0 errors)**；
  - `flutter test`：**全套 28 项自动化测试 100% 通过**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

### 📖 小说阅读器四项体验升级：后台预取、跨章连续翻页、阅读位置保持与控制栏优化

- **用户诉求**：
  1. 阅读时自动缓存后面的章节；
  2. 章节阅读完成后连续翻页到下一章节；
  3. 切换翻页类型时会从头开始，需要解决；
  4. 阅读界面控件优化。
- **落地成果（`app/lib/views/media/novel/reader/novel_reader_page.dart`）**：
  1. **后台静默预取（自动缓存后续章节）**：
     - 新增纯数据获取方法 `_ensureChapterContent`（不触碰当前 UI 状态，可安全用于后台预取），并封装出 `_prefetchChapter` 静默预取；
     - 触发时机：当前章加载完成即预取下一章、横向翻页推进到倒数第 2 页再次触发、纵向续载成功后继续向后预取；
     - 预取仅写入 `_contentCache` 以实现切章秒开，并通过 `_prefetching` 集合防止同一章重复请求；
     - 底栏新增「已缓存 N 章」状态键，支持一键手动预取并给出明确反馈；
  2. **跨章连续阅读**：
     - **横向**：章末追加一页「下一章衔接页」（展示下一章标题与就绪状态），滑入后约 260ms 自动续读下一章（`_advancingChapter` 防抖），配合预取实现无感切换；
     - **纵向**：滚动距离底部不足 480px 时静默加载下一章并**追加到同一 `ListView`**，形成真正的无缝长卷；依据屏幕中线（仅检查相邻 3 个章节块）自动同步当前章节，保证进度记录与目录高亮准确；
     - **失败熔断**：续载失败的章节写入 `_verticalFailed`，杜绝滚动过程中对同一章节反复发起无效请求；
  3. **阅读位置保持（彻底消除「切换后从头开始」）**：
     - 新增统一锚点 `_currentCharOffset`（横向按页累加字符、纵向按滚动比例换算）与 `_restoreReadingPosition`（下一帧布局完成后精确还原）；
     - 翻页模式切换统一收口到 `_togglePageMode`，切换前后自动保持阅读位置，纵向模式会以目标章重建连续阅读序列；
     - 字号增减经 `_applyTypographyChange` 保持位置；行距拖动采用 `onChangeStart` 锚定 + `onChangeEnd` 还原，避免连续拖动时页面抖动；
  4. **控制栏优化**：
     - 顶/底控制栏由不透明色块升级为**纵向渐变遮罩**，与正文过渡更自然；
     - 移除底栏与顶栏重复的「复制本章」入口（统一保留顶栏）；
     - 底栏四键调整为 `目录` / `已缓存 N 章` / `翻页模式` / `排版`；
     - 排版抽屉新增「翻页模式」选择（与底栏快捷切换共享同一套位置保持逻辑）；
     - 横向模式读到全书最后一页时提示「已是最后一章」，避免用户反复滑动却无反馈；
     - 修复 `_buildActionButton` 的 `dynamic icon` 类型与「两分支代码完全相同」的冗余三元判断；
- **质量验证**：
  - `flutter analyze`：**No issues found (0 warnings, 0 errors)**；
  - `flutter test`：**全套 28 项自动化测试 100% 通过**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

## [2026-09-16]

### 🧭 规则生成契约引导强化：items 默认出口与 groups 多线路判别铁律

- **问题根源定位**：
  - AI 生成的详情规则普遍把子资源无脑包裹成 `groups: [{ name: '默认', items: [...] }]`，导致单一选集列表 / 单一清晰度变体场景也凭空多出一层无意义结构；
  - 而 `groups` 在契约中本为「多播放线路 / 分卷多线路」的可选升级位，`items` 才是大一统默认出口（`RULE_SPECIFICATION.md` 6.1）；
  - 根因并非结构设计，而是 AI 提示词的两处表述冲突：字段清单遗漏了 `groups` 说明，而「映射到 detail」一条却把 `groups` 写成了默认产出结构；
- **提示词修正（`web/src/stores/aiSettings.ts`）**：
  1. 「核心返回值契约」补齐 `groups` 字段定义，并新增**【items 与 groups 的选择铁律（严禁无脑包裹）】**：
     - 默认一律使用扁平 `items`：单一选集列表、单一章节目录、以及同一线路下的多清晰度/多版本变体（720p、1080p、高清、标清）全部平铺，版本名写入条目 `title`；
     - 严禁虚构单分组包裹，`groups: [{ name: '默认', items: [...] }]` 判定为错误写法，必须降级为扁平 `items`；
     - 仅当同一作品存在**多套互斥资源列表**时才使用 `groups`（多播放线路、小说多卷、漫画单行本与番外篇），且分组数必须大于 1；
  2. `detail` 方法契约补注 items/groups 选择约束；
  3. 「映射到 detail」由「输出分组结构 groups」改为「子资源默认平铺输出到 items」；
  4. 「契约优先与彻底去兼容化」原则新增「结构层次必须如实映射」条款；
- **编辑器引导同步（`web/src/views/rules/edit.vue`）**：标准模板的 `groups` 示例由单条「默认线路」改为「线路一 / 线路二」两条互斥线路，并注明单清晰度变体严禁包裹；
- **编辑器类型提示同步（`web/src/components/CodeEditor/util.ts`）**：`DetailResult.items` / `groups` 的 JSDoc 补充默认出口与多线路判别说明；
- **质量验证**：`npx vue-tsc --noEmit` 通过（0 类型错误）；App 端现有 `groups` ↔ `items` 双兼容解析逻辑无需改动，存量规则完全向后兼容。

### 🔐 规则沙箱内置 CryptoJS 加密全家桶、Node.js 原生 crypto 兼容垫片与离线集成
- **用户需求与痛点**：
  - 用户询问：“app内怎么装载 nodejs crypto 模块，有可以下载的 cdn 链接吗”，并要求“帮我一步到位”集成。
- **底层架构原理与技术落地**：
  1. **离线内置全功能 `crypto-js`**：
     - 下载高可用完整打包的 `crypto-js.min.js` (60KB) 放置于 [`app/assets/js/crypto-js.min.js`](file:///c:/zz/z-custom/projects/fluxforge/app/assets/js/crypto-js.min.js)，利用 Flutter assets 机制实现离线随包分发，零网络依赖；
     - 在 [`RuleEngine._doInit()`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/services/rule_engine.dart) 中完成加载，提升至全局单例 `globalThis.CryptoJS`，并严格防范 UMD 模块覆盖；
  2. **内置 Node.js 原生 `crypto` API 轻量级桥接垫片 (Polyfill)**：
     - 提供 Node.js 风格的 `crypto.createHash(algo)`（支持 md5, sha1, sha256, sha512, sha3, ripemd160 等及 hex/base64 digest）；
     - 提供 `crypto.createHmac(algo, key)`（支持 sha256, md5, sha1 等）；
     - 提供 `crypto.randomBytes(size)`（支持 hex/base64 输出）；
  3. **极致开发亲和与全语法兼容**：
     - 规则内写 `import crypto from 'crypto'` 或 `import CryptoJS from 'crypto-js'` 时，转译器自动安全剥离并链接至沙箱单例；
     - 执行闭包头部自动注入 `var crypto = globalThis.crypto; var CryptoJS = globalThis.CryptoJS;`；
     - 注入微型 `require` 拦截器：当规则编写 CommonJS `const crypto = require('crypto')` 或 `require('crypto-js')` 时自动拦截并返回对应单例，无需修改规则即可直接跨端跑通；
     - 包含 AES, DES, TripleDES, RC4, Base64 等高级对称加解密算法全面支持；
  4. **超时容灾防御机制**：
     - 在 `_doInit()` 中为 `getApplicationDocumentsDirectory()` 增加 500ms 超时限制，防止在无原生平台通道的单元测试或特殊嵌入环境下卡死挂起。
- **质量验证**：
  - `flutter analyze`：0 warnings, 0 errors；
  - `flutter test`：全套 28 项自动化测试 100% 全部通过 (28/28 Passed)；
  - 经纯 JS 环境与 Node.js 真实沙箱双向校验，MD5、SHA256、AES 加解密结果 100% 精确匹配。

### 🎛️ App「我的」页资产仪表盘重构、跨媒体消费历史与断点续播全链路落地

- **用户诉求与设计共识**：
  - 用户希望先分析 App 端整体功能，再对「我的」页面进行重新设计与重构；
  - 经全量代码调研（`views/` / `services/` / `widgets/` + `APP_DEV_SPEC` / `APP_ROADMAP`）后达成共识：把「我的」从**功能入口集合**升级为**个人资产仪表盘**，设置页则收敛为**纯参数配置中心**；
- **现状诊断（重构前问题定位）**：
  1. **定位重叠**：`ProfilePage` 与 `SettingsPage` 同时提供备份还原、清缓存、日志入口，数据资产职责边界模糊；
  2. **结构平铺**：页面为「头卡 → 4 指标条 → 追更卡 → 4 菜单 → 页脚」单一平铺，无分组语义，设置入口重复 2 次、收藏入口 4 次；
  3. **文案与语义缺陷**：`'追更追更状态'` 重复错字；「搜索足迹」跳转搜索页而非历史管理；「已载规则」跳转规则市场而非规则页；「临时缓存」指标点击会**静默连带清空搜索历史**；
  4. **数据失真**：`AppService.getCacheSizeInMB` 异常时兜底返回硬编码假值 `12.8`，误导用户；
  5. **代码重复**：「我的」页与设置页的备份面板 + 导入对话框约 150 行逐行重复；
  6. **能力缺失（最关键）**：App 端仅有搜索历史，**不存在观看/阅读历史服务**；`ResumeBehavior` 设置项形同虚设（播放器从未接入 `initialPosition` / `onProgress`），P0 断点续播实际未落地；
- **架构级落地与重构成果**：
  1. **新增统一消费历史服务 [`PlayHistoryService`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/services/play_history_service.dart)**：
     - 定义跨媒体 `PlayRecord` 数据契约（媒体类型 / 集数章节 / 播放秒数 / 总时长 / 综合进度百分比）；
     - **高频写入节流**：播放器 `onProgress` 约每 500ms 回调一次，内存即时更新、磁盘按 5 秒节流落盘，避免 IO 抖动与 UI 狂刷；
     - 支持去重置顶、200 条容量上限、单条删除、一键清空与备份导入导出；
  2. **断点续播全链路打通**：
     - `AuraPlayer` 新增 `autoResume` 参数，完整落地 `ResumeBehavior` 的「直接跳转 / 提示询问 / 从头播放」三种策略；
     - 视频详情页接入 `initialPosition` + `onProgress`，并在进入时自动恢复到上次观看的集数；
     - 小说阅读器新增 `onChapterChanged` 回调，小说/漫画详情页接入章节级阅读进度记录，实现「继续阅读」精确续读；
  3. **「我的」页按五大语义区重新设计**（`profile_page.dart` 编排 + 3 个子组件）：
     - ① 身份 Hero（可编辑昵称、沙箱状态、主题三态 SegmentedButton、设置唯一入口）；
     - ② 继续观看（跨媒体横滑卡片流，封面叠加进度条，一键续播）；
     - ③ 我的资产（2×2 资产卡网格：追更收藏 / 观看历史 / 我的规则 / 搜索足迹，各卡独立监听服务并展示动态副信息）；
     - ④ 数据与同步（备份还原 / 规则市场 / 缓存治理）；⑤ 系统与关于（偏好设置 / 沙箱日志 ERROR 徽标 / 广告拦截 / 关于面板）；
     - 新增下拉刷新一体化动作（追更检测 + 缓存重算）；
  4. **新增历史管理中心页 [`HistoryCenterPage`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/history/history_center_page.dart)**：统一收纳观看/阅读历史（类型过滤、进度条、相对时间、单条删除、点击直达续播）与搜索足迹（标签流、单条删除、一键清空），并导出可复用的 `openPlayRecord` 跳转函数；
  5. **公共组件抽取与去重**：
     - 新增 [`backup_sheet.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/widgets/backup_sheet.dart)，消除两页约 150 行重复实现；
     - 新增 [`setting_tile.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/widgets/setting_tile.dart)（SettingTile / SettingSectionTitle / SettingSection），统一菜单行与分组容器；
     - 新增 [`media_utils.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/core/utils/media_utils.dart)，统一媒体类型图标与中文标签映射；
  6. **职责边界收敛**：设置页移除「数据存储与深度维护」卡片，定位为纯参数配置中心；备份数据包结构扩展 `playHistory` 字段（向后兼容旧备份文件）；
- **顺带修复清单**：
  - 修复 `'追更追更状态'` 文案错字；
  - `getCacheSizeInMB` 返回 `double?`，不可用时展示「正在统计...」而非伪造 `12.8M`；
  - 「清理缓存」与「清空搜索历史」彻底解耦并增加二次确认弹窗；
  - 「我的规则」资产卡点击改为切换至规则 Tab（新增 `onSwitchTab` 回调），修复原先误跳规则市场的语义错误；
  - 移除无入口的 `/card_gallery` 死路由（组件文件保留供开发调试）；
  - `EmptyState.icon` 由 `dynamic` 规范为 `IconData?`，移除重复的类型判断分支；
  - 头像渐变与图标色统一改用 `AppColors` 令牌，消除硬编码十六进制色值；
  - **彻底移除收藏页假数据**：删除 `FavoritesPage._seedSampleIfEmpty()` 预置的示例条目（`sample_video_1` / `sample_novel_1`），
    收藏列表不再向用户资产中注入任何演示数据；
  - 修正 `FavoriteService.checkUpdates` 的误导性注释（原「模拟或真实执行」易被误解为模拟数据，实际为真实的集数比对逻辑）；
  - **移除日志页「写入模拟测试日志」调试入口**：删除 `LogsPage._injectDemoLogs()` 方法与空态按钮，
    杜绝伪造日志混入真实日志流、抬高 ERROR 计数徽标，以及被 `AppLogger` 真实追加写入磁盘 `.logs` 文件。
- **质量验证**：
  - `flutter analyze`：**No issues found (0 warnings, 0 errors)**；
  - `flutter test`：**全套 27 项自动化测试 100% 通过 (27/27 Passed)**（同步补充了消费历史服务的测试容器注册）；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

### 🛡️ 全局分页 hasMore: false 拦截保护机制、上滑加载熔断与通栏居中 Footer 体验升级
- **用户关切与需求**：
  - 用户询问：“列表有分页的地方hasMore：false有设置不能继续上滑加载吗”。
- **全项目代码排查与缺陷定位**：
  1. **搜索页 (`SearchPage`) 严重缺失 `hasMore` 管理与上滑截断**：
     - 此前 `SearchPage` 完全未持久化各规则源的 `hasMore` 返回值；
     - 当规则源在 `search` 动作中返回 `{ items: [...], hasMore: false }` 时，系统直接丢弃了 `hasMore`；
     - 导致只要用户滑到底部，`_onScroll` 无脑触发 `_loadMoreResults()`，页码无休止递增发起无效网络请求，浪费流量与沙箱算力；
     - 且无任何“已加载全部”提示。
  2. **规则发现目录页 (`RuleCatalogPage`) Footer 渲染逻辑错乱**：
     - 代码虽在 `_onScroll` 中检测了 `_hasMore`，但在 UI 层面，`itemCount` 错误地判断了 `_loadingMore || _hasMore ? 1 : 0`；
     - 导致当 `_hasMore: false`（真正无更多）时，底部的“没有更多内容了”文本**永远无法渲染**；反而当 `_hasMore: true` 且尚未触发加载时，提前给用户展示了“没有更多内容了”；
     - 在 GridView 网格视图下，Footer 作为普通卡片被挤在左侧单列半宽（仅占 50%），UI 不居中。
- **架构级修复与优化落地**：
  1. **`SearchPage` 引入全生命周期 `hasMore` 状态熔断机制**：
     - 在 `_RuleSearchStatus` 中新增 `bool hasMore = true;`；
     - 在 `runRuleSearch` 与 `_loadMoreResults` 中严格解析沙箱返回的 `hasMore`，智能兼容显式指定与条目兜底；网络异常时直接熔断该源后续分页；
     - 新增计算属性 `_hasMoreCurrent`：单源筛选模式下检测对应源状态，全源聚合模式下检测是否存在任意有效源拥有更多数据；
     - 在 `_onScroll` 中加入 `&& _hasMoreCurrent` 硬性截断守卫，无更多时**彻底禁止触发任何上滑加载**；
     - 在 `_loadMoreResults` 中仅对尚有更多数据的规则源发起下一页请求，跳过已结束的规则源。
  2. **列表与网格视图通栏居中 Footer 体验升级**：
     - `SearchPage` 与 `RuleCatalogPage` 网格视图全面升级为 `CustomScrollView` + `SliverGrid` + `SliverToBoxAdapter`，Footer 彻底横贯整行、优雅居中显示；
     - 加载中显示平滑菊花与状态文本，全部加载完毕后清晰通栏展示“— 已加载全部搜索结果 —” / “— 没有更多内容了 —”；
     - 修复 `RuleCatalogPage` 中 `_loadMore` 的前置守卫（`if (!_hasMore || _loadingMore || _loading) return;`）。
  3. **Web 端 (`web/src/views/media/index.vue`) 对齐体验**：
     - 在 `hasMore == false` 且数据非空时追加优雅的弱化居中提示“— 已加载全部内容 —”，实现多端行为高度一致。
- **质量验证**：
  - `flutter analyze`：0 warnings, 0 errors；
  - `flutter test`：全套 27 项自动化测试全部通过 (27/27 Passed)。

### ⚡ 规则沙箱轻量闭包瘦身、转译语法安全防护、错误切片高亮与局部 defineRule 隔离
- **用户更新与技术演进**：
  1. **转译器语法安全性加固（修复非 export default 规则 SyntaxError 缺陷）**：
     - 在 [`RuleEngine.transformToRunnableJs`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/services/rule_engine.dart) 中，彻底摒弃旧版无脑在非导出代码前硬拼 `module.exports = ` 的做法；
     - 限制仅对纯对象字面量（以 `{` 开头并以 `}` 结尾）包裹 `module.exports = (...)`，杜绝在 `const`、`let`、`// 注释` 等语句前强行拼接导致的 `SyntaxError: unexpected token const`；
  2. **沙箱闭包精简 50+ 行冗余脚手架代码**：
     - 移除执行闭包中重复声明的 `console` 代理与参数序列化函数（复用 `_doInit` 全局单例通道），大幅精简闭包体积，使堆栈报错行号贴近规则源码；
  3. **沙箱语法错误智能切片与真实行号映射**：
     - 增加正则捕获 `<eval>:(\d+):(\d+)`，精准提取出错行号与列号，并在控制台/日志中生成代码切片与 `^` 定位符；
     - 智能推导并展示 `-> 约规则源码第 X 行`，极大提升开发者调试体验；
- **排查与深度优化**：
  - **局部 `defineRule` 严格隔离与空对象判空**：
    - 识别出若将 `defineRule` 挂载于 `globalThis` 并依赖 `module.exports || exports || ...` 会因为 `{}` 在 JS 中为 truthy 发生逻辑短路、且存在跨规则全局污染隐患；
    - 在闭包内局部定义 `defineRule` 直接赋值给当前闭包私有的 `module.exports`，并使用 `Object.keys(module.exports).length > 0` 精确判空，兼顾纯 `defineRule`、`export default`、`module.exports` 三种写法的同时杜绝实例污染；
  - **精简内置代码与消灭 `SyntaxError: expecting ';'` 语法陷阱**：
    - **消灭闭包作用域冲突**：此前闭包内使用 `var baseUrl = ...`，若规则作者自身在顶部写了 `const baseUrl = ...`，JS 引擎会因同一 Lexical 作用域内重复声明抛出 `SyntaxError`。现改为在全局执行前动态挂载 `globalThis.baseUrl`，彻底允许规则自由遮蔽或直接引用，零冲突；
    - **自动闭合分号防护**：在 `transformToRunnableJs` 中自动确保非大括号结尾的规则末尾补充分号，彻底杜绝转译代码与后续闭包逻辑粘连导致的 `expecting ';'`；
    - **沙箱闭包极限瘦身至 28 行**：彻底移除闭包内长达 40+ 行脆弱且容易引发字符转义冲突的内联 catch 字符串拼接逻辑，错误捕获全部交给 Dart 层，闭包顶部脚手架缩短至仅 8 行；
    - **精简 `url.polyfill.js` 非必要代码**：移除末尾 50+ 行未被使用的 `btoa` / `atob` 代码，使 Polyfill 更纯粹轻量。
- **测试与代码质量验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 27 项自动化测试用例 100% 全部通过 (27/27 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

## [2026-09-15]

### 🌐 规则沙箱 POST 302 重定向智能跟随、QuickJS 错误堆栈反吞噬与 URLSearchParams 契约补齐
- **用户问题与异常现象**：
  - 用户在规则中编写表单 POST 搜索代码：
    ```javascript
    const searchUrl = `${baseUrl}/search.html`;
    const params = new URLSearchParams();
    params.append('searchtype', 'all');
    params.append('searchkey', keyword);
    let headers = { 'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'path=/' };
    let res = await axios.post(searchUrl, params.toString(), { headers });
    ```
  - App 端执行搜索动作时抛出异常：`搜索动作执行异常：Exception： at <anonymous> (<eval>:27:70) at <eval> (<eval>:1:11)`，用户询问 Dio 能否正确请求以及具体成因。
- **底层根因深度剖析**：
  1. **QuickJS 堆栈吞噬错误信息（报错不可读核心根因）**：
     - 在沙箱执行生命周期的 catch 块中，此前逻辑为 `var errMessage = (err && (err.stack || err.message)) ? String(err.stack || err.message) : String(err);`；
     - 在 Node.js/V8 中 `err.stack` 会自动包含 `err.message`，但在 **QuickJS-NG** 引擎中，`err.stack` 仅包含纯调用栈文本（即 `at <anonymous> (<eval>:27:70)...`）；
     - 由于逻辑优先取了 `err.stack`，导致真实的异常原因（如 Axios 的 HTTP 302/403 状态码或网络错误）被完全丢弃，对外仅能看到两行无意义堆栈；
  2. **Dart HttpClient 默认拒绝 POST 重定向导致 302 抛错**：
     - 小说站（如杰奇CMS、帝国CMS）在收到 POST `/search.html` 请求后，标准行为是返回 **HTTP 302 Found** 并通过 `Location` 重定向至搜索结果页；
     - 浏览器和 Node.js Axios 会自动将 POST 302 转为 GET 请求跳转至结果页；而 Dart `HttpClient`（Dio 底层）默认不对 POST 进行重定向跟随，直接返回 302；
     - JS 端沙箱适配器默认 `validateStatus` 判定 302 为非 2xx 异常，立即触发 `reject(new Error('Request failed with status code 302'))`，引发搜索异常中断；
  3. **URLSearchParams 原型 Symbol.toStringTag 缺失**：
     - 内置 `url.polyfill.js` 未定义 `Symbol.toStringTag = 'URLSearchParams'` 与 `toJSON`，若用户直接写 `axios.post(url, params)`，Axios 会误判其为普通对象并序列化为空 JSON `"{}"`。
- **架构升级与优化落地**：
  1. **原生请求层智能跟随 HTTP 重定向（RFC 7231 / 浏览器行为对齐）**：
     - 在 [`RuleEngine._handleHttpRequest`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/services/rule_engine.dart) 中增加循环重定向处理器，默认最多跟随 5 次（若规则显式配置 `maxRedirects: 0` 则原样透传）；
     - 当收到 301/302/303 状态码且带 `Location` 头时，自动将请求方法转为 GET、清理多余表单请求头，并使用 `Uri.resolve` 解析相对路径，与浏览器和 Node.js 行为 100% 对齐；
  2. **沙箱错误捕获与日志诊断增强及 Dart 多行字符串转义缺陷修复**：
     - 重构 JS 沙箱 catch 块：全面提取 `err.message`、Axios 状态码（`HTTP 302 / 403`）、请求目标 URL，并与 QuickJS `err.stack` 进行清晰拼接；
     - **排查修复 Dart 编译期换行转义导致 JS SyntaxError 缺陷**：在 Dart 的非 raw 多行字符串中，`'\n'` 会在 Dart 编译期被直接求值为物理换行符 `\x0A`，导致生成的 JS 脚本中单引号字符串未闭合而跨行，引发 `SyntaxError: unexpected end of string at <eval>:155:27`。通过改用 `String.fromCharCode(10)` 生成换行，彻底根除跨平台语言字符串模板的转义陷阱；
  3. **完善 URLSearchParamsPolyfill 规范**：
     - 在 [`url.polyfill.js`](file:///c:/zz/z-custom/projects/fluxforge/app/assets/js/url.polyfill.js) 原型上注入 `[Symbol.toStringTag] = 'URLSearchParams'` 和 `toJSON`，使规则中直接传 `params` 即可被 Axios 原生自动转换为 `application/x-www-form-urlencoded`。
- **测试与代码质量验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 26 项自动化测试用例 100% 全部通过 (26/26 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。
- **用户更新与技术演进**：
  1. **网络层深度集成 CookieJar 与 DioCookieManager**：
     - 在 [`RuleEngine`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/services/rule_engine.dart) 中接入 `cookie_jar: ^4.0.9` 与 `dio_cookie_manager: ^3.5.0`，在 `_initInternal()` 时自动将 Cookie 持久化到 App 文档目录下的 `.cookies`；
     - 原生沙箱 Dio 请求统一挂载 `CookieManager` 拦截器，解决规则爬虫跨请求会话维持、反爬校验与登录态丢失难题；在非原生环境或无权限环境优雅降级为内存 `CookieJar`；
     - 导出 `cookieJar` getter 与 `clearCookies()` 静态接口，并在 [`test/rule_engine_timeout_test.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/test/rule_engine_timeout_test.dart) 中完成生命周期与存取清理单测覆盖；
  2. **搜索历史标签体验重构**：
     - 在 [`search_page.dart`](file:///c:/zz/z-custom/projects/fluxforge/app/lib/views/search/search_page.dart) 中彻底摒弃原 `InputChip`，改用更轻量灵活的 `Material + InkWell + Container` 自定义圆角胶囊（圆角 14px）；
     - 引入 `ConstrainedBox(maxWidth: 160)` 与 `TextOverflow.ellipsis`，对超长搜索历史词进行优雅的单行省略截断，杜绝单标签撑满全行破坏网格排版；
     - 删除小叉采用 `GestureDetector(behavior: HitTestBehavior.opaque)` 严密阻断冒泡，杜绝误触搜索。
- **全量测试与代码静态审查验证**：
  - `flutter analyze` 运行验证：**No issues found (0 warnings, 0 errors)**；
  - `flutter test` 运行验证：**全套 26 项自动化测试用例 100% 全部通过 (26/26 Passed)**；
  - 严格遵守最高指令要求，未向远程仓库提交或推送 Git。

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
