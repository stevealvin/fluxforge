import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/shared/widgets/setting_tile.dart';
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

  /// 主题选择面板的单个选项（复用统一行组件，避免第二套行样式）
  ///
  /// 选中态**只留尾部一个勾**：模式名本身已写明是哪种，再给标题染色 / 加粗是对
  /// 同一信息的重复强调（理由同「首页规则卡」那次收敛）。
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
      // 未选中用零尺寸占位：尾部非 null 即不画箭头，同时不占横向空间
      trailing: isSelected
          ? const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primary,
              size: 20,
            )
          : const SizedBox.shrink(),
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
          // 分组标题在卡片**外**（[SettingSectionTitle]），卡内不再自绘小标题 ——
          // 与「我的」页同构，同一套视觉语言只有一处实现。
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. 播放与视听偏好（联动 AuraPlayer）
              const SettingSectionTitle(title: '播放与视听'),
              _buildPlayerPrefSection(isDark, settings),
              const SizedBox(height: 24),

              // 2. 浏览与阅读偏好（联动 FluxReader & FluxGallery）
              const SettingSectionTitle(title: '浏览与阅读'),
              _buildReaderPrefSection(isDark, settings),
              const SizedBox(height: 24),

              // 3. 规则沙箱与网络解析
              const SettingSectionTitle(title: '规则沙箱与网络'),
              _buildSandboxNetworkSection(isDark, settings),
              const SizedBox(height: 24),

              // 4. 外观与主题系统
              const SettingSectionTitle(title: '外观与主题'),
              _buildThemeSection(isDark, settings),
              const SizedBox(height: 24),

              // 5. 数据备份、系统诊断与关于
              const SettingSectionTitle(title: '数据、诊断与关于'),
              _buildAboutDiagnosisSection(isDark),
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

  /// 1. 播放与视听偏好（AuraPlayer）
  Widget _buildPlayerPrefSection(bool isDark, AppSettings settings) {
    return SettingSection(
      children: [
        SettingRow(
          icon: Ionicons.flashOutline,
          color: AppColors.accentAmber,
          title: '长按瞬时加速与触觉震动',
          subtitle: '长按屏幕瞬时加速播放，并触发原生轻微物理震动',
          // 整行可点：点行内任意处即可切换，不必精准点中开关
          onTap: () => appService.updateSettings(
            settings.copyWith(enableLongPress2x: !settings.enableLongPress2x),
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
        // 长按加速倍率 (2.0x / 3.0x / 5.0x)
        SettingRow(
          icon: Ionicons.speedometerOutline,
          color: AppColors.accentAmber,
          title: '长按加速倍率',
          subtitle: '长按屏幕时瞬时提升到的播放倍速',
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
          title: '断点续播行为',
          // 当前值已由尾部下拉表达，说明改为写「这行是干什么的」
          subtitle: '再次打开时从哪里开始播放',
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
    );
  }

  /// 2. 浏览与阅读偏好（FluxReader & Gallery）
  Widget _buildReaderPrefSection(bool isDark, AppSettings settings) {
    return SettingSection(
      children: [
        SettingRow(
          icon: Ionicons.bookOutline,
          color: AppColors.accentAmber,
          title: '小说默认翻页模式',
          subtitle: '小说阅读器默认使用的翻页方式',
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
        SettingRow(
          icon: Ionicons.imageOutline,
          color: AppColors.accentPurple,
          title: '图集与画廊默认视图',
          subtitle: '图集默认使用的浏览布局',
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
    );
  }

  /// 3. 规则沙箱与网络解析
  Widget _buildSandboxNetworkSection(bool isDark, AppSettings settings) {
    return SettingSection(
      children: [
        SettingRow(
          icon: Ionicons.stopwatchOutline,
          color: AppColors.primary,
          title: '沙箱请求超时时限',
          subtitle: '复杂网络源的等待上限，超时即中断本次解析',
          // 当前值由尾部下拉表达，故说明不必再写一遍「(30秒)」
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
          title: '内置网页广告拦截',
          subtitle: '智能阻断小说/影视网页弹窗、牛皮癣横幅与恶意外链',
          onTap: () => appService.updateSettings(
            settings.copyWith(enableAdBlock: !settings.enableAdBlock),
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
        if (settings.enableAdBlock) _buildAdBlockStatusPanel(isDark),
        SettingRow(
          icon: Ionicons.globeOutline,
          color: AppColors.accentBlue,
          title: '自定义 User-Agent',
          subtitle: settings.customUserAgent.isNotEmpty
              ? settings.customUserAgent
              : '使用内置移动端伪装标头',
          onTap: () => _showUASheet(context),
        ),
        SettingRow(
          icon: Ionicons.refreshOutline,
          color: AppColors.accentTeal,
          title: '启动时自动同步规则',
          subtitle: '从规则市场同步已订阅源的最新解析补丁',
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
    );
  }

  /// 广告拦截开启后的状态块（随「内置网页广告拦截」开关展开）
  ///
  /// 底色取「比卡片深 / 亮一档」的内嵌块色而非卡片同色：同一层色块叠在卡片上
  /// 等于没有边界，而加边框又会与分组的容器边框重复 —— 用底色分档最干净。
  Widget _buildAdBlockStatusPanel(bool isDark) {
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
    );
  }

  /// 4. 外观与主题系统
  Widget _buildThemeSection(bool isDark, AppSettings settings) {
    return SettingSection(
      children: [
        SettingRow(
          icon: Ionicons.colorPaletteOutline,
          color: AppColors.primary,
          title: '界面风格主题',
          // 尾部只有箭头（无文字），故当前值仍需留在说明里
          subtitle: _getThemeModeLabel(settings.themeMode, isDark),
          onTap: () => _showThemeDialog(context, isDark),
        ),
      ],
    );
  }

  /// 5. 数据备份、系统诊断与关于
  Widget _buildAboutDiagnosisSection(bool isDark) {
    return SettingSection(
      children: [
        // 数据备份与还原（自「我的」页迁移，数据类操作统一收敛至设置页）
        SettingRow(
          icon: Ionicons.hardwareChipOutline,
          color: AppColors.accentPurple,
          title: '数据备份与还原',
          subtitle: '规则库、收藏、搜索历史与观看进度单文件 JSON 导出/导入',
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
              // 异常徽标是自绘尾部，箭头要显式补上（复用同源组件，避免尺寸分叉）
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
        // 关于信息面板（自「我的」页迁移）
        SettingRow(
          icon: Ionicons.informationCircleOutline,
          color: AppColors.accentAmber,
          title: '关于 FluxForge',
          subtitle: '版本信息、运行底座与本地资产概览',
          onTap: _showAboutSheet,
        ),
      ],
    );
  }
}
