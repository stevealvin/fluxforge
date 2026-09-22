import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/settings/widgets/backup_sheet.dart';
import 'package:fluxforge/features/settings/widgets/custom_ua_sheet.dart';
import 'package:fluxforge/features/browser/engine/adblock_engine.dart';

/// 全局偏好与系统设置中心 (SettingsPage)
///
/// 定位为「参数配置 + 数据与诊断」的统一入口，涵盖播放视听偏好、阅读与图集偏好、
/// 规则沙箱网络、外观主题，以及数据备份还原、沙箱日志与「关于」信息共五大现代圆角卡片；
/// 「我的」页仅保留个人资产（收藏 / 历史 / 规则 / 缓存）与消费记录，避免职责重叠。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    AdBlockEngine.instance.initialize();
  }

  String _getThemeModeLabel(ThemeMode mode, bool isDark) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统 (${isDark ? "当前深色" : "当前浅色"})';
      case ThemeMode.dark:
        return '曜夜极光翡翠 (深色)';
      case ThemeMode.light:
        return '纯净星暮白 (浅色)';
    }
  }

  /// 弹出主题选择抽屉
  void _showThemeDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final currentMode = appService.settings.themeMode;
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
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                _buildThemeTile(
                  title: '跟随系统',
                  subtitle: '与手机系统的深浅模式自动同步',
                  icon: Ionicons.phonePortraitOutline,
                  isSelected: currentMode == ThemeMode.system,
                  isDark: isDark,
                  onTap: () {
                    appService.updateThemeMode(ThemeMode.system);
                    Navigator.pop(ctx);
                  },
                ),
                _buildThemeTile(
                  title: '纯净星暮白',
                  subtitle: '清爽通透的高雅浅色视觉风格',
                  icon: Ionicons.sunnyOutline,
                  isSelected: currentMode == ThemeMode.light,
                  isDark: isDark,
                  onTap: () {
                    appService.updateThemeMode(ThemeMode.light);
                    Navigator.pop(ctx);
                  },
                ),
                _buildThemeTile(
                  title: '曜夜极光翡翠',
                  subtitle: '沉浸舒适的极夜暗色与翡翠光辉',
                  icon: Ionicons.moonOutline,
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
  }

  Widget _buildThemeTile({
    required String title,
    required String subtitle,
    required dynamic icon,
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
              child: icon is IconData
                  ? Icon(
                      icon,
                      size: 20,
                      color: isSelected ? AppColors.primary : Colors.grey,
                    )
                  : Icon(
                      icon as IconData,
                      size: 20,
                      color: isSelected ? AppColors.primary : Colors.grey,
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
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  /// 自定义 User-Agent：底部弹出输入（与「备份恢复」同一交互形态）
  ///
  /// 换成面板而不是居中对话框的三个理由与备份恢复一致：输入框贴底不挡键盘、
  /// 顶部两角常驻 取消 / 确认、长串可整屏核对；另外 UA 串基本靠粘贴，
  /// 面板里直接给了「粘贴剪贴板」与「恢复默认」。
  Future<void> _showUASheet(BuildContext context) async {
    final saved = await showCustomUaSheet(
      context,
      initialValue: appService.settings.customUserAgent,
      onSave: (ua) => appService.updateSettings(
        appService.settings.copyWith(customUserAgent: ua),
      ),
    );
    // 取消返回 null；保存空串是合法值（表示恢复内置默认）
    if (saved == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved.isEmpty ? '已恢复内置 User-Agent' : '已保存自定义 User-Agent'),
      ),
    );
  }

  /// 触发广告拦截规则在线热更
  Future<void> _triggerAdBlockUpdate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在从高速镜像同步最新广告拦截规则...'),
        duration: Duration(seconds: 2),
      ),
    );

    final success = await AdBlockEngine.instance.updateRules();
    if (!mounted) return;

    if (success) {
      final count = AdBlockEngine.instance.totalRulesNotifier.value;
      messenger.showSnackBar(
        SnackBar(
          content: Text('规则库同步成功！当前已生效 $count 条拦截规则'),
          backgroundColor: AppColors.primary,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('部分规则镜像连接超时，已保留本地缓存与内置种子规则'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// 弹出「关于」信息面板（版本 / 构建号 / 平台 / 本地资产概览）
  ///
  /// 自「我的」页迁移至此，与数据备份、沙箱日志共同构成完整的数据与诊断入口。
  Future<void> _showAboutSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = appService.packageInfo;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryLight, AppColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Ionicons.compassOutline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FluxForge 流光视界',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '轻量级沙箱规则驱动的跨媒体聚合平台',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildAboutRow('版本号', 'v${info?.version ?? "1.0.0"}', isDark),
              _buildAboutRow('构建编号', info?.buildNumber ?? '1', isDark),
              // 使用 Theme.platform 等价于 defaultTargetPlatform，无需额外导入 foundation
              _buildAboutRow('运行平台', Theme.of(context).platform.name, isDark),
              _buildAboutRow('规则引擎', 'QuickJS-NG 极光微内核沙箱', isDark),
              _buildAboutRow('本地规则', '${ruleService.rules.length} 条', isDark),
              _buildAboutRow(
                '收藏条目',
                '${favoriteService.favorites.length} 部',
                isDark,
              ),
              _buildAboutRow(
                '消费记录',
                '${playHistoryService.records.length} 条',
                isDark,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '本地自治 · 数据全量留存于设备',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「关于」面板的信息行
  Widget _buildAboutRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text(
          '系统设置',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: ValueListenableBuilder<AppSettings>(
        valueListenable: appService.settingsNotifier,
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. 播放视听偏好卡片 (联动 AuraPlayer)
              _buildPlayerPrefCard(isDark, settings),
              const SizedBox(height: 16),

              // 2. 浏览与阅读偏好卡片 (联动 FluxReader & FluxGallery)
              _buildReaderPrefCard(isDark, settings),
              const SizedBox(height: 16),

              // 3. 规则沙箱与网络解析卡片
              _buildSandboxNetworkCard(isDark, settings),
              const SizedBox(height: 16),

              // 4. 外观与主题系统卡片
              _buildThemeCard(isDark, settings),
              const SizedBox(height: 16),

              // 5. 关于与系统诊断卡片
              _buildAboutDiagnosisCard(isDark),
              const SizedBox(height: 24),

              // 底部版本信息
              Center(
                child: Text(
                  'FluxForge v${appService.packageInfo?.version ?? "1.0.0"} (Build ${appService.packageInfo?.buildNumber ?? "1"}) · 极光轻量沙箱内核',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  /// 1. 播放与视听偏好卡片 (AuraPlayer)
  Widget _buildPlayerPrefCard(bool isDark, AppSettings settings) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '播放与视听偏好 (AuraPlayer)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(
              Ionicons.flashOutline,
              color: Colors.amber,
              size: 20,
            ),
            title: const Text(
              '长按瞬时加速与触觉震动',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '长按屏幕以 ${settings.longPressSpeed.toStringAsFixed(1)}x 加速播放，并触发原生轻微物理震动',
              style: const TextStyle(fontSize: 11),
            ),
            value: settings.enableLongPress2x,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              appService.updateSettings(
                settings.copyWith(enableLongPress2x: val),
              );
            },
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          // 长按加速倍率 (2.0x / 3.0x / 5.0x)
          ListTile(
            leading: const Icon(
              Ionicons.speedometerOutline,
              color: Colors.amber,
              size: 20,
            ),
            title: const Text(
              '长按加速倍率',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '长按屏幕时瞬时提升到的播放倍速',
              style: TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<double>(
              value: settings.longPressSpeed,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: 2.0,
                  child: Text('2.0x', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 3.0,
                  child: Text('3.0x', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 5.0,
                  child: Text('5.0x', style: TextStyle(fontSize: 12)),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(
                    settings.copyWith(longPressSpeed: val),
                  );
                }
              },
            ),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          ListTile(
            leading: const Icon(
              Ionicons.refreshOutline,
              color: AppColors.accentTeal,
              size: 20,
            ),
            title: const Text(
              '断点续播行为',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '当前策略：${settings.resumeBehavior.label}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<ResumeBehavior>(
              value: settings.resumeBehavior,
              underline: const SizedBox.shrink(),
              items: ResumeBehavior.values.map((r) {
                return DropdownMenuItem(
                  value: r,
                  child: Text(r.label, style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(
                    settings.copyWith(resumeBehavior: val),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 2. 浏览与阅读偏好卡片 (FluxReader & Gallery)
  Widget _buildReaderPrefCard(bool isDark, AppSettings settings) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '浏览与阅读偏好 (FluxReader & Gallery)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Ionicons.bookOutline,
              color: Color(0xFFF59E0B),
              size: 20,
            ),
            title: const Text(
              '小说默认翻页模式',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.novelPageMode == 'vertical' ? '上下连续长篇滚动' : '标准平滑横向翻页',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<String>(
              value: settings.novelPageMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: 'horizontal',
                  child: Text('平滑横翻', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'vertical',
                  child: Text('上下滚动', style: TextStyle(fontSize: 12)),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(
                    settings.copyWith(novelPageMode: val),
                  );
                }
              },
            ),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          ListTile(
            leading: const Icon(
              Ionicons.imageOutline,
              color: Color(0xFF8B5CF6),
              size: 20,
            ),
            title: const Text(
              '图集与画廊默认视图',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.galleryLayout == 'comicStrip' ? '垂直条漫连续拼接' : '瀑布流展厅网格',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<String>(
              value: settings.galleryLayout,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: 'grid',
                  child: Text('展厅网格', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 'comicStrip',
                  child: Text('垂直条漫', style: TextStyle(fontSize: 12)),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(
                    settings.copyWith(galleryLayout: val),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 3. 规则沙箱与网络解析卡片
  Widget _buildSandboxNetworkCard(bool isDark, AppSettings settings) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '规则沙箱与网络解析',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Ionicons.stopwatchOutline,
              color: AppColors.primary,
              size: 20,
            ),
            title: const Text(
              '沙箱请求超时时限',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '针对复杂网络源弹性宽容 (${settings.requestTimeoutSeconds}秒)',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: DropdownButton<int>(
              value: settings.requestTimeoutSeconds,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: 15,
                  child: Text('15 秒', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 30,
                  child: Text('30 秒 (推荐)', style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: 60,
                  child: Text('60 秒 (宽容)', style: TextStyle(fontSize: 12)),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(
                    settings.copyWith(requestTimeoutSeconds: val),
                  );
                }
              },
            ),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          ListTile(
            leading: const Icon(
              Ionicons.shieldCheckmarkOutline,
              color: Colors.green,
              size: 20,
            ),
            title: const Text(
              '内置网页广告拦截',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '智能阻断小说/影视网页弹窗、牛皮癣横幅与恶意外链',
              style: TextStyle(fontSize: 11),
            ),
            trailing: Switch(
              value: settings.enableAdBlock,
              activeTrackColor: AppColors.primary,
              onChanged: (val) {
                appService.updateSettings(
                  settings.copyWith(enableAdBlock: val),
                );
              },
            ),
          ),
          if (settings.enableAdBlock) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable:
                                AdBlockEngine.instance.totalRulesNotifier,
                            builder: (context, totalRules, _) {
                              return ValueListenableBuilder<DateTime?>(
                                valueListenable:
                                    AdBlockEngine.instance.lastUpdatedNotifier,
                                builder: (context, lastSync, _) {
                                  final syncText = lastSync != null
                                      ? '${lastSync.month}-${lastSync.day} ${lastSync.hour.toString().padLeft(2, "0")}:${lastSync.minute.toString().padLeft(2, "0")}'
                                      : '内置种子名单';
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '当前生效规则: $totalRules 条',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '上次更新: $syncText',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDark
                                              ? AppColors.darkTextMuted
                                              : AppColors.lightTextMuted,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              AdBlockEngine.instance.isUpdatingNotifier,
                          builder: (context, isUpdating, _) {
                            return FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: isUpdating
                                  ? null
                                  : () => _triggerAdBlockUpdate(context),
                              child: isUpdating
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      '立即同步',
                                      style: TextStyle(fontSize: 11),
                                    ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.pushAdblock(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '管理广告过滤规则与订阅源...',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          ListTile(
            leading: const Icon(
              Ionicons.globeOutline,
              color: Colors.blueAccent,
              size: 20,
            ),
            title: const Text(
              '自定义 User-Agent',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              settings.customUserAgent.isNotEmpty
                  ? settings.customUserAgent
                  : '使用内置移动端伪装标头',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showUASheet(context),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          SwitchListTile(
            secondary: const Icon(
              Ionicons.refreshOutline,
              color: AppColors.accentTeal,
              size: 20,
            ),
            title: const Text(
              '启动时自动同步规则',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '从规则市场同步已订阅源的最新解析补丁',
              style: TextStyle(fontSize: 11),
            ),
            value: settings.autoCheckRuleUpdates,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              appService.updateSettings(
                settings.copyWith(autoCheckRuleUpdates: val),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 4. 外观与主题系统卡片
  Widget _buildThemeCard(bool isDark, AppSettings settings) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '外观与主题系统',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Ionicons.colorPaletteOutline,
              color: AppColors.primary,
              size: 20,
            ),
            title: const Text(
              '界面风格主题',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _getThemeModeLabel(settings.themeMode, isDark),
              style: const TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showThemeDialog(context, isDark),
          ),
        ],
      ),
    );
  }

  /// 5. 数据备份、系统诊断与关于卡片
  Widget _buildAboutDiagnosisCard(bool isDark) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '数据备份、诊断与关于',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
          // 数据备份与还原（自「我的」页迁移，数据类操作统一收敛至设置页）
          ListTile(
            leading: const Icon(
              Ionicons.hardwareChipOutline,
              color: AppColors.accentPurple,
              size: 20,
            ),
            title: const Text(
              '数据备份与还原',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '规则库、收藏、搜索历史与观看进度单文件 JSON 导出/导入',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => showBackupSheet(context),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          ValueListenableBuilder<List<LogEntry>>(
            valueListenable: AppLogger.logsNotifier,
            builder: (context, logs, _) {
              final errorCount = logs.where((l) => l.level == 'ERROR').length;
              final subtitleText = logs.isEmpty
                  ? '查看 QuickJS 规则解析、console.log 与网络报错'
                  : '已记录 ${logs.length} 条日志${errorCount > 0 ? " (含 $errorCount 项异常)" : ""}';

              return ListTile(
                leading: const Icon(
                  Ionicons.documentOutline,
                  color: Colors.blueAccent,
                  size: 20,
                ),
                title: const Text(
                  '沙箱与系统日志中心',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  subtitleText,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errorCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$errorCount ERROR',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  ],
                ),
                onTap: () => context.pushLogs(),
              );
            },
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          // 关于信息面板（自「我的」页迁移）
          ListTile(
            leading: const Icon(
              Ionicons.informationCircleOutline,
              color: AppColors.accentAmber,
              size: 20,
            ),
            title: const Text(
              '关于 FluxForge',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '版本信息、运行底座与本地资产概览',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: _showAboutSheet,
          ),
        ],
      ),
    );
  }
}
