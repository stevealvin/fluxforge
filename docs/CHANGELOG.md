# FluxForge 变更日志 (CHANGELOG)

本文档用于记录 FluxForge（包括 App 移动端、Server 服务端、Web 管理端）在开发过程中的重要功能迭代、UI 体验调优与架构重构日志。

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
