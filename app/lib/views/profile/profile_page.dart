import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../widgets/app_card.dart';
import '../../widgets/loading_indicator.dart';

/// 个人中心与应用总览页面（我的）
/// 
/// 承载 FluxForge 核心引擎状态、实时数据看板、高频快捷动作与系统配置
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: appService.themeModeNotifier,
        builder: (context, currentThemeMode, _) {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. 顶部 Sliver 标题栏 (含快速主题切换与设置入口)
              _buildHeader(context, isDark, currentThemeMode),

              // 2. 核心引擎 Hero 概览卡片
              SliverToBoxAdapter(child: _buildEngineHeroCard(isDark)),

              // 3. 实时数据指标看板 (规则 / 搜索 / 市场 / 版本)
              SliverToBoxAdapter(child: _buildMetricsStrip(context, isDark)),

              // 4. 核心快捷操作矩阵 (市场 / 导入 / 历史 / 清理)
              SliverToBoxAdapter(child: _buildQuickActions(context, isDark)),

              // 5. 规则沙箱与源站中枢分组
              SliverToBoxAdapter(
                child: _buildSectionGroup(
                  title: '规则沙箱与源站中枢',
                  icon: LucideIcons.cpu,
                  isDark: isDark,
                  children: [
                    ValueListenableBuilder<List<Rule>>(
                      valueListenable: ruleService.rulesNotifier,
                      builder: (context, rules, _) {
                        return _buildListTile(
                          icon: LucideIcons.codeXml,
                          iconColor: AppColors.primary,
                          title: '本地规则管理',
                          subtitle: '已收录 ${rules.length} 条规则，其中 ${rules.where((r) => r.enabled).length} 条已启用',
                          isDark: isDark,
                          onTap: () {
                            // 可跳转市场或引导切换规则 Tab
                            context.push('/market');
                          },
                        );
                      },
                    ),
                    _buildDivider(isDark),
                    _buildListTile(
                      icon: LucideIcons.shieldCheck,
                      iconColor: Colors.teal,
                      title: 'QuickJS 沙箱运行环境',
                      subtitle: '全隔离沙箱运行 · WHATWG URL 与 Base64 Polyfill 就绪',
                      isDark: isDark,
                      onTap: () => _showSandboxInfoDialog(context),
                    ),
                    _buildDivider(isDark),
                    _buildListTile(
                      icon: LucideIcons.globe,
                      iconColor: AppColors.accentBlue,
                      title: '网络策略与防盗链代理',
                      subtitle: '自动注入 Referer 防盗链请求头与专属 User-Agent',
                      isDark: isDark,
                      onTap: () => _showSandboxInfoDialog(context),
                    ),
                  ],
                ),
              ),

              // 6. 系统偏好与存储配置分组
              SliverToBoxAdapter(
                child: _buildSectionGroup(
                  title: '系统偏好与存储管理',
                  icon: LucideIcons.sliders,
                  isDark: isDark,
                  children: [
                    _buildListTile(
                      icon: LucideIcons.palette,
                      iconColor: AppColors.accentPurple,
                      title: '界面外观与主题模式',
                      subtitle: _getThemeModeLabel(currentThemeMode, isDark),
                      isDark: isDark,
                      onTap: () => _showThemePickerModal(context, isDark),
                    ),
                    _buildDivider(isDark),
                    ValueListenableBuilder<List<String>>(
                      valueListenable: historyService.searchHistoryNotifier,
                      builder: (context, history, _) {
                        return _buildListTile(
                          icon: LucideIcons.history,
                          iconColor: Colors.indigo,
                          title: '搜索历史记录',
                          subtitle: '本地保存了 ${history.length} 条搜索足迹',
                          isDark: isDark,
                          onTap: () => context.push('/search'),
                        );
                      },
                    ),
                    _buildDivider(isDark),
                    _buildListTile(
                      icon: LucideIcons.trash2,
                      iconColor: Colors.orange,
                      title: '清理应用缓存',
                      subtitle: '释放本地图片缓存与历史临时索引',
                      isDark: isDark,
                      onTap: () => _confirmClearCache(context),
                    ),
                  ],
                ),
              ),

              // 7. 关于与极客生态分组
              SliverToBoxAdapter(
                child: _buildSectionGroup(
                  title: '关于与开发生态',
                  icon: LucideIcons.info,
                  isDark: isDark,
                  children: [
                    _buildListTile(
                      icon: LucideIcons.layers,
                      iconColor: AppColors.primary,
                      title: '卡片组件设计体系 (AppCard)',
                      subtitle: '预览 Standard、Flat、Outlined、Gradient 与弹性微缩',
                      isDark: isDark,
                      onTap: () => context.push('/card_gallery'),
                    ),
                    _buildDivider(isDark),
                    _buildListTile(
                      icon: LucideIcons.bookOpen,
                      iconColor: AppColors.accentBlue,
                      title: '规则生命周期契约指南',
                      subtitle: '了解 discovery、search、detail、parse 规范契约',
                      isDark: isDark,
                      onTap: () => _showRuleContractDialog(context),
                    ),
                    _buildDivider(isDark),
                    _buildListTile(
                      icon: LucideIcons.refreshCw,
                      iconColor: AppColors.primary,
                      title: '检查版本更新',
                      subtitle: '当前版本 v${appService.packageInfo?.version ?? "1.0.0"} (已是最新版)',
                      isDark: isDark,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('当前已是最新版本 v1.0.0'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    _buildDivider(isDark),
                    _buildListTile(
                      icon: LucideIcons.info,
                      iconColor: Colors.teal,
                      title: '关于 FluxForge',
                      subtitle: '开源协议、设计规范与免责声明',
                      isDark: isDark,
                      onTap: () => _showAboutDialog(context),
                    ),
                  ],
                ),
              ),

              // 8. 底部版本号与安全避让
              SliverToBoxAdapter(child: _buildFooter(isDark)),
            ],
          );
        },
      ),
    );
  }

  /// 1. 页面顶部标题栏
  Widget _buildHeader(BuildContext context, bool isDark, ThemeMode themeMode) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      elevation: 0,
      title: Text(
        '我的',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
      ),
      actions: [
        // 快速主题切换按钮
        IconButton(
          icon: Icon(
            themeMode == ThemeMode.dark
                ? LucideIcons.moon
                : (themeMode == ThemeMode.light ? LucideIcons.sun : LucideIcons.smartphone),
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            size: 20,
          ),
          tooltip: '切换外观主题',
          onPressed: () => _showThemePickerModal(context, isDark),
        ),
        // 设置入口
        IconButton(
          icon: Icon(
            LucideIcons.settings,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            size: 20,
          ),
          tooltip: '系统设置',
          onPressed: () => context.push('/settings'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// 2. 核心引擎 Hero 概览卡片
  Widget _buildEngineHeroCard(bool isDark) {
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      borderRadius: 18,
      child: Column(
        children: [
          Row(
            children: [
              // 品牌 Logo / 头像
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accentTeal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.zap,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              // 信息区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'FluxForge 探索者',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 运行状态指示胶囊
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 0.6,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 3,
                                backgroundColor: AppColors.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '就绪',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'QuickJS 规则沙箱 · 全生命周期隔离引擎',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 3. 实时数据指标看板 (响应式)
  Widget _buildMetricsStrip(BuildContext context, bool isDark) {
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: ValueListenableBuilder<List<Rule>>(
        valueListenable: ruleService.rulesNotifier,
        builder: (context, allRules, _) {
          final enabledCount = allRules.where((r) => r.enabled).length;

          return ValueListenableBuilder<List<String>>(
            valueListenable: historyService.searchHistoryNotifier,
            builder: (context, history, _) {
              return Row(
                children: [
                  _buildMetricItem(
                    label: '启用规则',
                    value: '$enabledCount/${allRules.length}',
                    isDark: isDark,
                    onTap: () => context.push('/market'),
                  ),
                  _buildMetricDivider(isDark),
                  _buildMetricItem(
                    label: '搜索足迹',
                    value: '${history.length} 条',
                    isDark: isDark,
                    onTap: () => context.push('/search'),
                  ),
                  _buildMetricDivider(isDark),
                  _buildMetricItem(
                    label: '云端规则库',
                    value: '公共市场',
                    isDark: isDark,
                    onTap: () => context.push('/market'),
                  ),
                  _buildMetricDivider(isDark),
                  _buildMetricItem(
                    label: '应用版本',
                    value: 'v${appService.packageInfo?.version ?? "1.0"}',
                    isDark: isDark,
                    onTap: () => _showAboutDialog(context),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricDivider(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
    );
  }

  /// 4. 核心快捷操作矩阵 (4 列圆角轻卡片)
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    final actions = [
      {
        'title': '规则市场',
        'icon': LucideIcons.store,
        'color': const Color(0xFF10B981),
        'onTap': () => context.push('/market'),
      },
      {
        'title': '导入规则',
        'icon': LucideIcons.downloadCloud,
        'color': const Color(0xFF0EA5E9),
        'onTap': () => _showImportDialog(context),
      },
      {
        'title': '搜索历史',
        'icon': LucideIcons.history,
        'color': const Color(0xFF8B5CF6),
        'onTap': () => context.push('/search'),
      },
      {
        'title': '清理缓存',
        'icon': LucideIcons.trash2,
        'color': const Color(0xFFF59E0B),
        'onTap': () => _confirmClearCache(context),
      },
    ];

    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((item) {
          final color = item['color'] as Color;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: item['onTap'] as VoidCallback?,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item['icon'] as IconData,
                      size: 22,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['title'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 5. 通用功能分组容器
  Widget _buildSectionGroup({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(icon, size: 15, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 13,
        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
      ),
      onTap: onTap,
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 56,
      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
    );
  }

  /// 8. 底部版本号与协议说明
  Widget _buildFooter(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.zap, size: 14, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
              const SizedBox(width: 6),
              Text(
                'FluxForge 跨端沙箱引擎 v${appService.packageInfo?.version ?? "1.0.0"}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '曜夜极光翡翠 · 纯净星暮白沉浸式视界',
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppColors.darkTextMuted.withValues(alpha: 0.7)
                  : AppColors.lightTextMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 80), // 避让底部毛玻璃 NavigationBar
        ],
      ),
    );
  }

  /// 主题模式标签辅助
  String _getThemeModeLabel(ThemeMode mode, bool isDark) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统 (${isDark ? "当前为深色" : "当前为浅色"})';
      case ThemeMode.dark:
        return '曜夜极光翡翠 (强制深色)';
      case ThemeMode.light:
        return '纯净星暮白 (强制浅色)';
    }
  }

  /// 弹出快速主题外观选择器
  void _showThemePickerModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appService.themeModeNotifier,
          builder: (context, currentMode, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 12),
                      child: Text(
                        '选择系统主题外观',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('跟随系统'),
                      subtitle: const Text('自动与移动设备系统的深色/浅色模式保持同步'),
                      leading: const Icon(LucideIcons.smartphone),
                      trailing: currentMode == ThemeMode.system
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () {
                        appService.updateThemeMode(ThemeMode.system);
                        Navigator.pop(ctx);
                      },
                    ),
                    ListTile(
                      title: const Text('纯净星暮白 (浅色模式)'),
                      subtitle: const Text('清爽通透的高雅浅色视觉风格'),
                      leading: const Icon(LucideIcons.sun),
                      trailing: currentMode == ThemeMode.light
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () {
                        appService.updateThemeMode(ThemeMode.light);
                        Navigator.pop(ctx);
                      },
                    ),
                    ListTile(
                      title: const Text('曜夜极光翡翠 (深色模式)'),
                      subtitle: const Text('沉浸舒适的极夜暗色与翡翠光辉'),
                      leading: const Icon(LucideIcons.moon),
                      trailing: currentMode == ThemeMode.dark
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () {
                        appService.updateThemeMode(ThemeMode.dark);
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 弹出添加/导入规则对话框
  void _showImportDialog(BuildContext context) {
    int activeTab = 0;
    final urlController = TextEditingController();
    final jsonController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131D19) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '导入规则',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            context.push('/market');
                          },
                          icon: const Icon(LucideIcons.store, size: 16),
                          label: const Text('规则市场', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('网络导入'),
                          icon: Icon(LucideIcons.link, size: 16),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('粘贴 JSON'),
                          icon: Icon(LucideIcons.clipboard, size: 16),
                        ),
                      ],
                      selected: {activeTab},
                      onSelectionChanged: (set) {
                        setModalState(() {
                          activeTab = set.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (activeTab == 0) ...[
                      TextField(
                        controller: urlController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '请输入规则订阅或 JSON 地址 (https://...)',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.withValues(alpha: 0.8)),
                          prefixIcon: const Icon(LucideIcons.globe, size: 18),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E2D27) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: jsonController,
                        maxLines: 5,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '请粘贴规则 JSON 或规则数组配置...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.withValues(alpha: 0.8)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E2D27) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() {
                                isSubmitting = true;
                              });
                              try {
                                int count = 0;
                                if (activeTab == 0) {
                                  final url = urlController.text.trim();
                                  if (url.isEmpty) throw Exception('请输入有效的网络订阅 URL');
                                  count = await ruleService.importFromUrl(url);
                                } else {
                                  final jsonStr = jsonController.text.trim();
                                  if (jsonStr.isEmpty) throw Exception('请粘贴规则 JSON 内容');
                                  count = await ruleService.importFromJson(jsonStr);
                                }
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('成功导入 $count 条规则！'),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                }
                              } catch (err) {
                                setModalState(() {
                                  isSubmitting = false;
                                });
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    SnackBar(content: Text('导入失败: $err'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            },
                      child: isSubmitting
                          ? const LoadingIndicator.compact(size: 18, color: Colors.white)
                          : const Text('确认导入', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 清除缓存确认对话框
  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('确定要清空本地搜索历史与临时图片缓存吗？（已导入的规则不会被删除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              historyService.clearHistory();
              await AppStorage.remove('search_history');
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('已完成缓存清理')),
                );
              }
            },
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
  }

  /// 沙箱隔离与安全信息弹窗
  void _showSandboxInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.shieldCheck, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('沙箱与安全机制'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• QuickJS 独立隔离引擎：所有外部规则在隔离沙箱闭包中解析运行，无权接触设备底层隐私。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            SizedBox(height: 8),
            Text(
              '• WHATWG URL 标准注入：已内置 URL、URLSearchParams 及 Base64 Polyfill，保障现代 JS 规则 100% 兼容。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            SizedBox(height: 8),
            Text(
              '• 防盗链网络代理策略：媒体请求与图片加载自动注入目标规则 BaseUrl 的 Referer 与标准移动端 User-Agent，规避 403 访问限制。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('已知悉'),
          ),
        ],
      ),
    );
  }

  /// 规则生命周期契约说明弹窗
  void _showRuleContractDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.codeXml, color: AppColors.accentBlue, size: 22),
            SizedBox(width: 8),
            Text('规则生命周期契约'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FluxForge 规则引擎基于 ESModule 标准 export default defineRule({...}) 定义，核心包含四大标准生命周期函数：',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              SizedBox(height: 8),
              Text(
                '1. discovery({ tab, page = 1 })\n返回: { tabs?: [...], items: MediaItem[], hasMore?: boolean }',
                style: TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace'),
              ),
              SizedBox(height: 6),
              Text(
                '2. search({ keyword, page = 1 })\n返回: { items: MediaItem[], hasMore?: boolean }',
                style: TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace'),
              ),
              SizedBox(height: 6),
              Text(
                '3. detail({ url, item })\n返回: { title, cover, playUrl?, images?, content?, groups? }',
                style: TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace'),
              ),
              SizedBox(height: 6),
              Text(
                '4. parse({ url, groupName })\n返回: { playUrl?, content? }',
                style: TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 关于对话框
  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'FluxForge',
      applicationVersion: 'v${appService.packageInfo?.version ?? "1.0.0"}',
      applicationLegalese: '© 2026 FluxForge Team. All rights reserved.',
      children: const [
        SizedBox(height: 12),
        Text('轻量级、沙箱规则驱动的跨媒体聚合浏览与多功能播放平台。'),
      ],
    );
  }
}

