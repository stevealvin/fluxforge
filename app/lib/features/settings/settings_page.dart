import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/features/browser/engine/adblock_engine.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_reader_preferences.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/reader_preferences.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/settings/widgets/backup_sheet.dart';
import 'package:fluxforge/features/settings/widgets/custom_ua_sheet.dart';
import 'package:fluxforge/shared/widgets/app_confirm_dialog.dart';
import 'package:fluxforge/shared/widgets/setting_tile.dart';

/// 全局系统偏好与沙箱控制台 (SettingsPage - 方案一：现代仪表盘 + 核心场景专区)
///
/// 架构设计遵循「方案一」现代化仪表盘美学：
/// 1. **Hero Dashboard（运行态健康与存储仪表盘）**：
///    - 顶部微内核状态指示灯（QuickJS-NG 沙箱 · 活跃正常）
///    - 本地缓存动态容量条与「一键瘦身」快速清理
///    - 核心资产三联统计磁贴（已装载规则数、媒体消费资产数、沙箱自愈健康状态，**彻底去掉延迟显示**）
/// 2. **核心场景专区磁贴（2x2 场景卡片）**：
///    - 🎬 影音与播放：长按瞬时加速、倍率选择、断点续播
///    - 📖 阅读与排版：小说翻页方式、漫画长条连读
///    - 🎨 外观与风格：曜夜极光深色、纯净星暮浅色、跟随系统
///    - 🛡️ 网络与安全：沙箱请求超时、内置广告拦截、自定义 UA、启动规则同步
/// 3. **高级与系统工具箱**：
///    - 📦 数据备份与迁移（单文件 JSON 导入导出）
///    - 💻 沙箱与系统日志中心（实时错误徽标与控制台日志）
///    - ℹ️ 关于 FluxForge（版本、内核说明与本地资产统计）
///    - 🔄 恢复默认偏好（危险动作，二次确认出厂重置）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 阅读偏好独立于 [AppSettings]，归各自阅读器引擎管辖，此处持久化同步
  PageTurnMode _novelPageMode = PageTurnMode.horizontal;
  bool _comicContinuous = false;

  /// 本地临时与网络缓存占用大小（MB），null 表示仍在统计中
  double? _cacheSizeMb;

  /// 是否正在执行一键清理缓存
  bool _isCleaningCache = false;

  @override
  void initState() {
    super.initState();
    AdBlockEngine.instance.initialize();
    _loadReaderPreferences();
    _loadCacheSize();
  }

  /// 异步读取小说与漫画阅读器的偏好持久化值
  Future<void> _loadReaderPreferences() async {
    final novel = await ReaderPreferences.load();
    final comicContinuous = await ComicReaderPreferences.loadContinuousMode();
    if (!mounted) return;
    setState(() {
      _novelPageMode = novel.pageMode ?? PageTurnMode.horizontal;
      _comicContinuous = comicContinuous ?? false;
    });
  }

  /// 异步统计当前设备的临时与图片缓存大小
  Future<void> _loadCacheSize() async {
    final size = await appService.getCacheSizeInMB();
    if (!mounted) return;
    setState(() {
      _cacheSizeMb = size;
    });
  }

  /// 执行一键瘦身：清除网络与临时缓存，并平滑刷新仪表盘
  Future<void> _handleCleanCache(BuildContext context) async {
    if (_isCleaningCache) return;
    setState(() => _isCleaningCache = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await appService.clearCache();
      if (!mounted) return;
      setState(() {
        _cacheSizeMb = 0.0;
        _isCleaningCache = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('临时缓存已全部清空，存储空间已释放'),
          backgroundColor: AppColors.primary,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCleaningCache = false);
    }
  }

  /// 主题模式文本标签
  String _getThemeModeLabel(ThemeMode mode, bool isDark) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统 (${isDark ? "深色" : "浅色"})';
      case ThemeMode.dark:
        return '曜夜极光翡翠';
      case ThemeMode.light:
        return '纯净星暮白';
    }
  }

  /// 弹出外观与风格选择抽屉
  void _showThemeDialog(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
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
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
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
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return SettingRow(
      icon: icon,
      color: AppColors.primary,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: isSelected
          ? const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primary,
              size: 20,
            )
          : const SizedBox.shrink(),
    );
  }

  /// 弹出自定义 User-Agent 面板
  Future<void> _showUASheet(BuildContext context) async {
    final saved = await showCustomUaSheet(
      context,
      initialValue: appService.settings.customUserAgent,
      onSave: (ua) => appService.updateSettings(
        appService.settings.copyWith(customUserAgent: ua),
      ),
    );
    if (saved == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved.isEmpty ? '已恢复内置 User-Agent' : '已保存自定义 User-Agent'),
      ),
    );
  }

  /// 触发广告拦截规则在线热更新
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

  /// 恢复默认偏好（带二次确认弹窗）
  Future<void> _resetPreferences(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: '恢复默认偏好？',
      message:
          '将把本页所有开关与选项（主题、播放、阅读、网络）恢复为出厂值。\n'
          '收藏、历史记录、离线下载与规则库不受影响。',
      confirmText: '恢复默认',
    );
    if (!confirmed) return;

    await appService.resetToDefaults();
    await ReaderPreferences.savePageMode(PageTurnMode.horizontal);
    await ComicReaderPreferences.saveContinuousMode(false);
    if (!mounted) return;

    setState(() {
      _novelPageMode = PageTurnMode.horizontal;
      _comicContinuous = false;
    });
    messenger.showSnackBar(const SnackBar(content: Text('已恢复默认偏好')));
  }

  /// 弹出「关于 FluxForge」应用总览与沙箱架构说明
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
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
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

  // ==========================================
  // 核心场景专区抽屉：影音、阅读、网络与安全
  // ==========================================

  /// 🎬 影音与播放配置抽屉
  void _showMediaSettingsSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: ValueListenableBuilder<AppSettings>(
              valueListenable: appService.settingsNotifier,
              builder: (context, settings, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '影音与播放偏好',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '视频手势加速、起播倍率与记忆断点',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingSection(
                      children: [
                        SettingRow(
                          icon: Ionicons.flashOutline,
                          color: AppColors.accentAmber,
                          title: '长按瞬时加速',
                          subtitle: '长按播放画面瞬时提速，松手即恢复',
                          onTap: () => appService.updateSettings(
                            settings.copyWith(
                              enableLongPress2x: !settings.enableLongPress2x,
                            ),
                          ),
                          trailing: Switch(
                            value: settings.enableLongPress2x,
                            activeTrackColor: AppColors.primary,
                            onChanged: (val) {
                              appService.updateSettings(
                                settings.copyWith(enableLongPress2x: val),
                              );
                            },
                          ),
                        ),
                        SettingRow(
                          icon: Ionicons.speedometerOutline,
                          color: AppColors.accentAmber,
                          title: '长按加速倍率',
                          subtitle: '长按期间提升到的播放倍速',
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
                        SettingRow(
                          icon: Ionicons.refreshOutline,
                          color: AppColors.accentTeal,
                          title: '断点续播',
                          subtitle: '再次打开同一部时的起播位置',
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
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 📖 阅读与排版配置抽屉
  void _showReadingSettingsSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '阅读与排版偏好',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '小说与漫画的默认打开方式（字号排版在阅读器内调节）',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingSection(
                      children: [
                        SettingRow(
                          icon: Ionicons.bookOutline,
                          color: AppColors.accentAmber,
                          title: '小说翻页方式',
                          subtitle: '打开小说时的默认翻页方式',
                          trailing: DropdownButton<PageTurnMode>(
                            value: _novelPageMode,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: PageTurnMode.horizontal,
                                child: Text('平滑横翻', style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: PageTurnMode.verticalScroll,
                                child: Text('上下滚动', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() => _novelPageMode = val);
                              setModalState(() => _novelPageMode = val);
                              ReaderPreferences.savePageMode(val);
                            },
                          ),
                        ),
                        SettingRow(
                          icon: Ionicons.imageOutline,
                          color: AppColors.accentPurple,
                          title: '漫画阅读方式',
                          subtitle: '打开图集与漫画时的默认浏览方式',
                          trailing: DropdownButton<bool>(
                            value: _comicContinuous,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: false,
                                child: Text('左右翻页', style: TextStyle(fontSize: 12)),
                              ),
                              DropdownMenuItem(
                                value: true,
                                child: Text('长条连读', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() => _comicContinuous = val);
                              setModalState(() => _comicContinuous = val);
                              ComicReaderPreferences.saveContinuousMode(val);
                            },
                          ),
                        ),
                      ],
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

  /// 🛡️ 网络与安全配置抽屉
  void _showNetworkSettingsSheet(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: ValueListenableBuilder<AppSettings>(
              valueListenable: appService.settingsNotifier,
              builder: (context, settings, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '网络与沙箱安全',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '沙箱请求超时时限、广告拦截与伪装标头',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingSection(
                      children: [
                        SettingRow(
                          icon: Ionicons.stopwatchOutline,
                          color: AppColors.primary,
                          title: '沙箱请求超时',
                          subtitle: '复杂网络源等待上限，超时即中断解析',
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
                        SettingRow(
                          icon: Ionicons.shieldCheckmarkOutline,
                          color: AppColors.success,
                          title: '网页广告拦截',
                          subtitle: '拦截小说与影视页面的弹窗和横幅广告',
                          onTap: () => appService.updateSettings(
                            settings.copyWith(
                              enableAdBlock: !settings.enableAdBlock,
                            ),
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
                        if (settings.enableAdBlock)
                          _buildAdBlockStatusPanel(sheetContext, isDark),
                        SettingRow(
                          icon: Ionicons.globeOutline,
                          color: AppColors.accentBlue,
                          title: '自定义 User-Agent',
                          subtitle: settings.customUserAgent.isNotEmpty
                              ? settings.customUserAgent
                              : '当前使用内置移动端伪装标头',
                          onTap: () => _showUASheet(context),
                        ),
                        SettingRow(
                          icon: Ionicons.cloudDownloadOutline,
                          color: AppColors.accentTeal,
                          title: '启动时同步规则',
                          subtitle: '启动时检查已订阅源的最新解析规则',
                          onTap: () => appService.updateSettings(
                            settings.copyWith(
                              autoCheckRuleUpdates: !settings.autoCheckRuleUpdates,
                            ),
                          ),
                          trailing: Switch(
                            value: settings.autoCheckRuleUpdates,
                            activeTrackColor: AppColors.primary,
                            onChanged: (val) {
                              appService.updateSettings(
                                settings.copyWith(autoCheckRuleUpdates: val),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 广告拦截状态面板组件
  Widget _buildAdBlockStatusPanel(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: AdBlockEngine.instance.totalRulesNotifier,
                    builder: (context, totalRules, _) {
                      return ValueListenableBuilder<DateTime?>(
                        valueListenable:
                            AdBlockEngine.instance.lastUpdatedNotifier,
                        builder: (context, lastSync, _) {
                          final syncText = lastSync != null
                              ? '${lastSync.month}-${lastSync.day} ${lastSync.hour.toString().padLeft(2, "0")}:${lastSync.minute.toString().padLeft(2, "0")}'
                              : '内置种子名单';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                  valueListenable: AdBlockEngine.instance.isUpdatingNotifier,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('立即同步', style: TextStyle(fontSize: 11)),
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
    );
  }

  // ==========================================
  // 主页面布局与方案一组件构建
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('系统偏好', style: TextStyle(fontWeight: FontWeight.bold)),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // 1. 运行态健康与存储仪表盘 (Hero Dashboard - 无延迟显示)
              _buildHeroDashboard(context, isDark, settings),
              const SizedBox(height: 24),

              // 2. 核心场景专区磁贴 (2x2 场景卡片)
              const SettingSectionTitle(
                title: '核心场景专区',
                subtitle: '影音、阅读、外观与网络安全独立配置',
              ),
              _buildSceneZonesGrid(context, isDark, settings),
              const SizedBox(height: 24),

              // 3. 高级与系统工具 (数据备份、沙箱日志、关于、恢复默认)
              const SettingSectionTitle(
                title: '高级与系统工具',
                subtitle: '备份迁移、沙箱诊断与出厂偏好重置',
              ),
              _buildToolboxSection(context, isDark),
              const SizedBox(height: 24),

              // 底部版本落款
              Center(
                child: Text(
                  'FluxForge v${appService.packageInfo?.version ?? "1.0.0"} '
                  '(Build ${appService.packageInfo?.buildNumber ?? "1"}) · QuickJS-NG 极光微内核沙箱',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  /// 1. 现代运行态健康与存储仪表盘 (Hero Dashboard)
  ///
  /// 严格遵照要求：完全剔除任何延时显示，聚焦于微内核运行态、存储容量与核心自治资产
  Widget _buildHeroDashboard(
    BuildContext context,
    bool isDark,
    AppSettings settings,
  ) {
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : AppColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态胶囊 + 一键瘦身
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '沙箱微内核 · 活跃就绪',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isCleaningCache ? null : () => _handleCleanCache(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : AppColors.lightBorder,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isCleaningCache)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          )
                        else
                          Icon(
                            Ionicons.sparklesOutline,
                            size: 13,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          '一键瘦身',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 存储容量条
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '本地临时与媒体缓存占用',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
                Text(
                  _cacheSizeMb != null
                      ? '${_cacheSizeMb!.toStringAsFixed(1)} MB'
                      : '计算中...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 6,
                width: double.infinity,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ((_cacheSizeMb ?? 10.0) / 120.0).clamp(0.08, 0.95),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.accentTeal],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 核心资产三联统计磁贴（已装载规则、媒体资产、沙箱自愈诊断 - 坚决无延迟显示）
            ValueListenableBuilder<List<LogEntry>>(
              valueListenable: AppLogger.logsNotifier,
              builder: (context, logs, _) {
                final errorCount = logs.where((l) => l.level == 'ERROR').length;
                return Container(
                  padding: const EdgeInsets.only(top: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : AppColors.lightBorder,
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildMetricBadge(
                        title: '${ruleService.rules.length}',
                        label: '已启用规则',
                        isDark: isDark,
                      ),
                      _buildMetricBadge(
                        title:
                            '${favoriteService.favorites.length + playHistoryService.records.length}',
                        label: '媒体消费资产',
                        isDark: isDark,
                      ),
                      _buildMetricBadge(
                        title: errorCount == 0 ? '零异常' : '$errorCount 项待检',
                        label: '沙箱自愈诊断',
                        titleColor: errorCount == 0
                            ? (isDark ? AppColors.primaryLight : AppColors.primary)
                            : AppColors.danger,
                        isDark: isDark,
                        onTap: () => context.pushLogs(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 仪表盘单个指标徽标
  Widget _buildMetricBadge({
    required String title,
    required String label,
    required bool isDark,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    Widget content = Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: titleColor ??
                (isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: isDark
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
          ),
        ),
      ],
    );

    if (onTap != null) {
      content = InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: content,
        ),
      );
    }
    return Expanded(child: content);
  }

  /// 2. 核心场景专区 2x2 磁贴卡片
  Widget _buildSceneZonesGrid(
    BuildContext context,
    bool isDark,
    AppSettings settings,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 560;

        final cardMedia = _buildSceneCard(
          title: '影音与播放',
          subtitle:
              '长按 ${settings.longPressSpeed}x · ${settings.enableLongPress2x ? "已开启加速" : "标准播放"} · ${settings.resumeBehavior.label}',
          tag: '配置 3 项 ›',
          icon: Ionicons.playCircleOutline,
          color: AppColors.accentAmber,
          isDark: isDark,
          onTap: () => _showMediaSettingsSheet(context),
        );

        final cardReading = _buildSceneCard(
          title: '阅读与排版',
          subtitle:
              '小说${_novelPageMode == PageTurnMode.horizontal ? "平滑横翻" : "上下滚动"} · 漫画${_comicContinuous ? "长漫连读" : "左右翻页"}',
          tag: '配置 2 项 ›',
          icon: Ionicons.bookOutline,
          color: AppColors.accentPurple,
          isDark: isDark,
          onTap: () => _showReadingSettingsSheet(context),
        );

        final cardAppearance = _buildSceneCard(
          title: '外观与风格',
          subtitle: _getThemeModeLabel(settings.themeMode, isDark),
          tag: '切换主题 ›',
          icon: Ionicons.colorPaletteOutline,
          color: AppColors.primary,
          isDark: isDark,
          onTap: () => _showThemeDialog(context, isDark),
        );

        final cardNetwork = _buildSceneCard(
          title: '网络与安全',
          subtitle:
              '沙箱超时 ${settings.requestTimeoutSeconds}s · 拦截${settings.enableAdBlock ? "开启" : "关闭"}',
          tag: '配置 4 项 ›',
          icon: Ionicons.shieldCheckmarkOutline,
          color: AppColors.accentBlue,
          isDark: isDark,
          onTap: () => _showNetworkSettingsSheet(context, isDark),
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: cardMedia),
              const SizedBox(width: 12),
              Expanded(child: cardReading),
              const SizedBox(width: 12),
              Expanded(child: cardAppearance),
              const SizedBox(width: 12),
              Expanded(child: cardNetwork),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cardMedia),
                const SizedBox(width: 12),
                Expanded(child: cardReading),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: cardAppearance),
                const SizedBox(width: 12),
                Expanded(child: cardNetwork),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 场景专区单张磁贴卡片
  Widget _buildSceneCard({
    required String title,
    required String subtitle,
    required String tag,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : AppColors.lightBorder,
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: color),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  /// 3. 高级与系统工具列表 (收纳备份、系统日志、关于与出厂重置)
  Widget _buildToolboxSection(BuildContext context, bool isDark) {
    return SettingSection(
      children: [
        SettingRow(
          icon: Ionicons.hardwareChipOutline,
          color: AppColors.accentPurple,
          title: '数据备份与还原',
          subtitle: '规则库、收藏与历史单文件 JSON 导出/恢复',
          onTap: () => showBackupSheet(context),
        ),
        ValueListenableBuilder<List<LogEntry>>(
          valueListenable: AppLogger.logsNotifier,
          builder: (context, logs, _) {
            final errorCount = logs.where((l) => l.level == 'ERROR').length;
            final subtitleText = logs.isEmpty
                ? '查看 QuickJS 规则解析、console.log 与网络报错'
                : '已记录 ${logs.length} 条日志${errorCount > 0 ? " (含 $errorCount 项异常)" : ""}';

            return SettingRow(
              icon: Ionicons.documentOutline,
              color: AppColors.info,
              title: '沙箱与系统日志中心',
              subtitle: subtitleText,
              onTap: () => context.pushLogs(),
              trailing: errorCount > 0
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$errorCount ERROR',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SettingRowChevron(),
                      ],
                    )
                  : null,
            );
          },
        ),
        SettingRow(
          icon: Ionicons.informationCircleOutline,
          color: AppColors.primary,
          title: '关于 FluxForge',
          subtitle: '微内核沙箱架构、版本号与本地自治协议',
          onTap: _showAboutSheet,
        ),
        SettingRow(
          icon: Ionicons.refreshOutline,
          color: AppColors.danger,
          title: '恢复默认偏好',
          subtitle: '仅重置本页偏好配置；收藏、历史与下载不受影响',
          onTap: () => _resetPreferences(context),
        ),
      ],
    );
  }
}
