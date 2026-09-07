import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../services/di.dart';

/// 应用全局设置与系统配置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _autoUpdateScript;

  @override
  void initState() {
    super.initState();
    _autoUpdateScript = appService.autoUpdateScript;
  }

  /// 获取当前主题模式的文本描述
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

  /// 弹出主题选择弹窗
  void _showThemeModeDialog(BuildContext context, bool isDark) {
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
                    _buildThemeRadioTile(
                      title: '跟随系统',
                      subtitle: '自动与手机系统的深色/浅色模式保持同步',
                      icon: LucideIcons.smartphone,
                      isSelected: currentMode == ThemeMode.system,
                      isDark: isDark,
                      onTap: () {
                        appService.updateThemeMode(ThemeMode.system);
                        Navigator.pop(ctx);
                      },
                    ),
                    _buildThemeRadioTile(
                      title: '纯净星暮白 (浅色模式)',
                      subtitle: '清爽通透的高雅浅色视觉风格',
                      icon: LucideIcons.sun,
                      isSelected: currentMode == ThemeMode.light,
                      isDark: isDark,
                      onTap: () {
                        appService.updateThemeMode(ThemeMode.light);
                        Navigator.pop(ctx);
                      },
                    ),
                    _buildThemeRadioTile(
                      title: '曜夜极光翡翠 (深色模式)',
                      subtitle: '沉浸舒适的极夜暗色与翡翠光辉',
                      icon: LucideIcons.moon,
                      isSelected: currentMode == ThemeMode.dark,
                      isDark: isDark,
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

  Widget _buildThemeRadioTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : (isDark ? AppColors.darkCard : AppColors.lightCard),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('系统设置'),
        centerTitle: false,
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 主题与视觉设置
          _buildThemeSection(isDark),
          const SizedBox(height: 16),

          // 规则沙箱与引擎设置
          _buildEngineSection(isDark),
          const SizedBox(height: 16),

          // 数据与日志设置
          _buildMaintenanceSection(isDark),
          const SizedBox(height: 24),

          // 底部版本标识
          Center(
            child: Text(
              '版本 ${appService.packageInfo?.version ?? "1.0.0"} (Build ${appService.packageInfo?.buildNumber ?? "1"})',
              style: TextStyle(
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 主题外观配置模块
  Widget _buildThemeSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appService.themeModeNotifier,
            builder: (context, currentMode, _) {
              return ListTile(
                leading: const Icon(LucideIcons.palette, color: AppColors.primary),
                title: const Text('系统界面主题', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  _getThemeModeLabel(currentMode, isDark),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => _showThemeModeDialog(context, isDark),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 规则沙箱与引擎更新配置
  Widget _buildEngineSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(LucideIcons.refreshCw, color: AppColors.accentTeal),
            title: const Text('启动时自动检查规则更新', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              '从云端规则市场自动同步最新的修复补丁与反爬适配',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            value: _autoUpdateScript,
            activeTrackColor: AppColors.primary,
            onChanged: (bool value) {
              setState(() {
                _autoUpdateScript = value;
                appService.autoUpdateScript = value;
              });
            },
          ),
        ],
      ),
    );
  }

  /// 缓存与维护模块
  Widget _buildMaintenanceSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(LucideIcons.trash2, color: Colors.amber),
            title: const Text('清理临时缓存', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              '清理网络图片缓存与搜索历史',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            trailing: const Icon(Icons.keyboard_arrow_right_rounded),
            onTap: () async {
              await AppStorage.remove('search_history');
              historyService.updateHistory([]);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已成功清除临时缓存')),
                );
              }
            },
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          ListTile(
            leading: const Icon(LucideIcons.fileText, color: Colors.blueAccent),
            title: const Text('沙箱运行日志', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              '查看 QuickJS 沙箱调用与解析异常记录',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            trailing: const Icon(Icons.keyboard_arrow_right_rounded),
            onTap: () => _showLogsDialog(context, isDark),
          ),
        ],
      ),
    );
  }

  /// 查看运行日志弹窗
  void _showLogsDialog(BuildContext context, bool isDark) {
    final logs = AppLogger.getLogs();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('沙箱日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: logs.isEmpty
              ? const Center(child: Text('当前无错误日志记录，系统运行良好'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${log.time.toIso8601String().substring(11, 19)} [${log.level}] ${log.message}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppLogger.clear();
              Navigator.pop(ctx);
            },
            child: const Text('清空日志'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
