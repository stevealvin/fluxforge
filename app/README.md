# 📱 FluxForge Mobile (移动客户端)

> **基于轻量级 JS 沙箱驱动的现代化、高质感跨媒体聚合浏览与播放客户端**  
> 采用 Flutter 3.24+ 构建，深度融合 **Material 3 Expressive** 动态表现力设计与 **Apple 级磨砂微拟态** 美学。

---

## 📖 移动端架构概述

FluxForge 移动端不仅是一个内容浏览器，更是一个**独立的客户端本地爬虫与解码沙箱**：
- **本地独立运行**：基于 `flutter_js` (QuickJS 引擎)，在本地直接加载内置的 `axios.min.js` 与 `cheerio.js`，直接在手机端执行规则爬取与数据清洗，不强依赖后端代理服务；
- **单代码统一契约**：严格遵循 `docs/RULE_SPECIFICATION.md` 规范，以单一 `defineRule` 脚本对接影视、小说、图集、音频等多媒体源；
- **流光设计系统**：全局定制 `AppCard`（20px 黄金圆角、90ms 物理下沉弹性回弹、冷调发散微阴影），内置曜夜深空黑与纯净白双主题（支持 `DynamicSchemeVariant.expressive` 动态色彩算法）。

---

## 📊 移动端功能完成度与开发看板 (Feature Status)

| 功能模块 | 详细特性描述 | 状态 | 规范与指引 |
| :--- | :--- | :---: | :--- |
| **本地 JS 规则引擎** | 基于 QuickJS 沙箱，支持 ES Module 转译、60秒防挂起超时、详细异常捕获 | ✅ 已完成 | `lib/services/rule_engine.dart` |
| **规则生命周期调度** | 完整调度 `discovery` (发现流)、`search` (全局搜索)、`detail` (详情)、`parse` (解析) | ✅ 已完成 | `lib/services/rule_service.dart` |
| **规则管理与导入** | 规则启停 Switch、网络订阅 URL 导入、JSON 粘贴导入、按名称/地址即时检索 | ✅ 已完成 | `lib/views/rules/rules_page.dart` |
| **主框架宿主** | 沉浸式 `ShellPage`，三大核心 Tab（发现/规则/我的），毛玻璃防重叠导航栏 | ✅ 已完成 | `lib/views/shell/shell_page.dart` |
| **全局跨源检索** | 多规则并发检索、源筛选胶囊栏、即时搜索与历史词记录 | ✅ 已完成 | `lib/views/search/search_page.dart` |
| **内置聚合浏览器** | 带广告拦截引擎 (`AdBlockEngine`)、全屏媒体播放适配、响应式手势防误退 | ✅ 已完成 | `lib/views/browser/browser_page.dart` |
| **自研现代播放器 (`AuraPlayer`)** | **【核心进行中】** 彻底弃用 Chewie，基于原生 `video_player`，支持手势调光/音量/快进微胶囊、长按 2.0x 震动倍速、防盗链 Headers、毫秒级断点续播 | ⏳ 正在落地 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#2-现代视频播放器-auraplayer-技术实现规格) |
| **规则连通性测速** | 规则列表一键并发探测，三色延迟指示灯 (🟢 <500ms, 🟡 1s+, 🔴 超时)，一键清理失效源 | ⏳ 规划中 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#3-规则健康巡检与毫秒级测速实现规格) |
| **纯净小说阅读引擎** | 仿真/平滑滑动/上下滚动三大模式，字号排版色盘、章节跳转与静默预加载 | ⏳ 规划中 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#4-纯净小说阅读引擎-fluxreader-实现规格) |
| **漫画与图集查看器** | 瀑布流大图展厅 + 垂直长图条漫阅读模式，双指平滑无级缩放，长按保存相册 | ⏳ 规划中 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#5-漫画与图集查看器-fluxgallery-实现规格) |
| **本地数据备份与还原** | 单文件 JSON/Flux 全量导出分享（规则+收藏+历史），换机即导即用，无需网盘 | ⏳ 规划中 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#6-本地全量数据一键备份与恢复实现规格) |
| **统一多媒体追更收藏** | 追剧/书架统一，源站新剧集/章节轻量探测，卡片角标亮起「NEW · 第13集」红点 | ⏳ 规划中 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#7-统一收藏与智能追更提醒实现规格) |
| **全局偏好与系统设置** | 播放手势/倍速偏好、阅读排版、沙箱请求超时时限 (15s/30s/60s)、精准深度清理 | ⏳ 规划中 | [详细规格见 APP_DEV_SPEC.md](../docs/APP_DEV_SPEC.md#8-全局偏好与系统设置-appsettings-实现规格) |

---

## 🛠️ 核心开发文档与规范指引

**任何参与移动端开发的工程师或 AI 编程助手，必须严格阅读以下技术规范**：

1. 🛠️ [**移动端技术开发与落地规范 (APP_DEV_SPEC.md)**](../docs/APP_DEV_SPEC.md)：
   - **必读铁律**：严禁私自引入未经批准的重型依赖；彻底弃用 Chewie；组件统一基于 `AppCard`；
   - 包含自研播放器 `AuraPlayer`、小说阅读器、测速、备份等全套接口与交互设计。
2. 🚀 [**移动端产品规划与演进路线图 (APP_ROADMAP.md)**](../docs/APP_ROADMAP.md)：
   - 功能优先级划分矩阵 (P0 / P1 / P2)。
3. 📖 [**规则引擎与生命周期契约白皮书 (RULE_SPECIFICATION.md)**](../docs/RULE_SPECIFICATION.md)：
   - 移动端数据解析与 `RuleEngine` 契约依据。

---

## 🚀 本地开发与调试运行

### 1. 环境要求
- **Flutter SDK** >= 3.24.0 (Dart >= 3.5.0)
- **Android Studio / VS Code** (配置 Flutter & Dart 插件)
- **Android SDK** API Level >= 21 (推荐 API 34+)

### 2. 依赖安装与启动
```bash
# 切换至 app 目录
cd app

# 获取依赖
flutter pub get

# 启动调试运行 (连接真机或模拟器)
flutter run
```

---

## 📦 Android 签名配置与打包发布

为保证团队多环境打包签名一致，Android 签名证书已统一固化在工程内部：

- **证书路径**：`android/app/key.jks`（严禁删除或加入 gitignore）；
- **签名配置**：`android/keystore.properties`
  ```properties
  storeFile=key.jks
  keyAlias=naile
  storePassword=***
  keyPassword=***
  ```
- **打包 Release APK 命令**：
  ```bash
  flutter build apk --release
  ```
  编译产物生成于：`app/build/app/outputs/flutter-apk/app-release.apk`。
