import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../services/app_service.dart';
import '../../services/di.dart';
import '../../widgets/app_card.dart';
import '../browser/adblock_engine.dart';

/// 全局偏好与系统设置中心 (SettingsPage)
/// 
/// 涵盖播放视听偏好、阅读与图集偏好、规则沙箱网络、数据备份与深度维护、
/// 主题系统及关于诊断共六大现代圆角卡片
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _cacheSizeMB = 0.0;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _fetchCacheSize();
    AdBlockEngine.instance.initialize();
  }

  Future<void> _fetchCacheSize() async {
    final size = await appService.getCacheSizeInMB();
    if (mounted) {
      setState(() => _cacheSizeMB = size);
    }
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
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                _buildThemeTile(
                  title: '跟随系统',
                  subtitle: '与手机系统的深浅模式自动同步',
                  icon: LucideIcons.smartphone,
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
                  icon: LucideIcons.sun,
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
  }

  Widget _buildThemeTile({
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
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

  /// 弹出自定义 User-Agent 设置对话框
  void _showUADialog(BuildContext context, bool isDark) {
    final controller = TextEditingController(text: appService.settings.customUserAgent);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义 User-Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '留空则默认使用内置高拟真 Chrome/Safari 移动端防爬伪装标头。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '输入自定义 UA 请求标头...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final newSettings = appService.settings.copyWith(customUserAgent: controller.text.trim());
              appService.updateSettings(newSettings);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已保存自定义 User-Agent')),
              );
            },
            child: const Text('保存'),
          ),
        ],
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

  /// 弹出广告规则订阅源管理面板
  void _showAdBlockSourcesSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sources = AdBlockEngine.instance.sources;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '广告规则订阅源管理',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('添加订阅', style: TextStyle(fontSize: 12)),
                        onPressed: () => _showAddCustomSourceDialog(context, () {
                          setSheetState(() {});
                        }),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 12),
                    child: Text(
                      '支持内置精选国内规则源与用户自定义订阅源，支持多镜像容灾',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 12,
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      ),
                      itemBuilder: (context, index) {
                        final s = sources[index];
                        return CheckboxListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: Text(
                            s.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            s.description,
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                          ),
                          value: s.isEnabled,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                s.isEnabled = val;
                              });
                              setState(() {});
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('保存并立即拉取更新'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _triggerAdBlockUpdate(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 弹出添加自定义订阅源对话框
  void _showAddCustomSourceDialog(BuildContext context, VoidCallback onAdded) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('添加自定义规则订阅源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '订阅源名称',
                hintText: '如：我的去广告规则',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '订阅直链 (URL)',
                hintText: 'https://.../rules.txt',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isNotEmpty && url.startsWith('http')) {
                AdBlockEngine.instance.addCustomSource(name, url);
                onAdded();
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已添加自定义源 [$name]')),
                );
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 弹出数据备份导出与导入操作面板
  void _showBackupSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  '数据全量备份与还原',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileUp, color: AppColors.primary),
                title: const Text('一键导出备份数据包'),
                subtitle: const Text('将规则库、收藏与搜索历史打包为 JSON 并分享/保存至本地', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await backupService.exportBackup();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('导出备份失败: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileDown, color: Colors.amber),
                title: const Text('从 JSON 文本/剪贴板恢复'),
                subtitle: const Text('解析备份 JSON，支持「合并追加」或「全量覆盖」', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImportRestoreDialog(context, isDark);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出输入/粘贴 JSON 恢复弹窗
  void _showImportRestoreDialog(BuildContext context, bool isDark) {
    final controller = TextEditingController();
    bool mergeMode = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('恢复备份数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请粘贴导出的 FluxForge 备份 JSON 文本内容：',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 4,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '{\n  "app": "FluxForge",\n  "data": { ... }\n}',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.clipboard, size: 16),
                    tooltip: '粘贴剪贴板',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        setDialogState(() {
                          controller.text = data!.text!;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: mergeMode,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      setDialogState(() {
                        mergeMode = val ?? true;
                      });
                    },
                  ),
                  GestureDetector(
                    onTap: () => setDialogState(() => mergeMode = !mergeMode),
                    child: Text(
                      mergeMode ? '合并导入 (保留现有，追加新增)' : '完全覆盖 (清空现有，以备份为准)',
                      style: TextStyle(
                        fontSize: 12,
                        color: mergeMode ? AppColors.primary : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final jsonStr = controller.text.trim();
                if (jsonStr.isEmpty) return;

                final result = await backupService.restoreBackup(
                  jsonStr: jsonStr,
                  merge: mergeMode,
                );

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result.success
                            ? '${result.message}：规则+${result.rulesImported}，收藏+${result.favoritesImported}'
                            : result.message,
                      ),
                    ),
                  );
                }
              },
              child: const Text('执行恢复'),
            ),
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
        title: const Text('系统设置', style: TextStyle(fontWeight: FontWeight.bold)),
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

              // 4. 数据存储与备份还原卡片 (联动 BackupService)
              _buildStorageMaintenanceCard(isDark),
              const SizedBox(height: 16),

              // 5. 外观与主题系统卡片
              _buildThemeCard(isDark, settings),
              const SizedBox(height: 16),

              // 6. 关于与系统诊断卡片
              _buildAboutDiagnosisCard(isDark),
              const SizedBox(height: 24),

              // 底部版本信息
              Center(
                child: Text(
                  'FluxForge v${appService.packageInfo?.version ?? "1.0.0"} (Build ${appService.packageInfo?.buildNumber ?? "1"}) · 极光轻量沙箱内核',
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
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
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(LucideIcons.sliders, color: AppColors.primary, size: 20),
            title: const Text('屏幕滑动手势调节', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('左侧滑动调节亮度、右侧应用内免权限音量调节', style: TextStyle(fontSize: 11)),
            value: settings.enablePlayerGestures,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              appService.updateSettings(settings.copyWith(enablePlayerGestures: val));
            },
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          SwitchListTile(
            secondary: const Icon(LucideIcons.zap, color: Colors.amber, size: 20),
            title: const Text('长按 2.0X 倍速与触觉震动', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('长按屏幕瞬时倍速并触发原生轻微物理震动', style: TextStyle(fontSize: 11)),
            value: settings.enableLongPress2x,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              appService.updateSettings(settings.copyWith(enableLongPress2x: val));
            },
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ListTile(
            leading: const Icon(LucideIcons.history, color: AppColors.accentTeal, size: 20),
            title: const Text('断点续播行为', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('当前策略：${settings.resumeBehavior.label}', style: const TextStyle(fontSize: 11)),
            trailing: DropdownButton<ResumeBehavior>(
              value: settings.resumeBehavior,
              underline: const SizedBox.shrink(),
              items: ResumeBehavior.values.map((r) {
                return DropdownMenuItem(value: r, child: Text(r.label, style: const TextStyle(fontSize: 12)));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(settings.copyWith(resumeBehavior: val));
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
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(LucideIcons.bookOpen, color: Color(0xFFF59E0B), size: 20),
            title: const Text('小说默认翻页模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(settings.novelPageMode == 'vertical' ? '上下连续长篇滚动' : '标准平滑横向翻页', style: const TextStyle(fontSize: 11)),
            trailing: DropdownButton<String>(
              value: settings.novelPageMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'horizontal', child: Text('平滑横翻', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'vertical', child: Text('上下滚动', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(settings.copyWith(novelPageMode: val));
                }
              },
            ),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ListTile(
            leading: const Icon(LucideIcons.image, color: Color(0xFF8B5CF6), size: 20),
            title: const Text('图集与画廊默认视图', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(settings.galleryLayout == 'comicStrip' ? '垂直条漫连续拼接' : '瀑布流展厅网格', style: const TextStyle(fontSize: 11)),
            trailing: DropdownButton<String>(
              value: settings.galleryLayout,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'grid', child: Text('展厅网格', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'comicStrip', child: Text('垂直条漫', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(settings.copyWith(galleryLayout: val));
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
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(LucideIcons.timer, color: AppColors.primary, size: 20),
            title: const Text('沙箱请求超时时限', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('针对复杂网络源弹性宽容 (${settings.requestTimeoutSeconds}秒)', style: const TextStyle(fontSize: 11)),
            trailing: DropdownButton<int>(
              value: settings.requestTimeoutSeconds,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 秒', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 30, child: Text('30 秒 (推荐)', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 60, child: Text('60 秒 (宽容)', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) {
                  appService.updateSettings(settings.copyWith(requestTimeoutSeconds: val));
                }
              },
            ),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ListTile(
            leading: const Icon(LucideIcons.shieldCheck, color: Colors.green, size: 20),
            title: const Text('内置网页广告拦截', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('智能阻断小说/影视网页弹窗、牛皮癣横幅与恶意外链', style: TextStyle(fontSize: 11)),
            trailing: Switch(
              value: settings.enableAdBlock,
              activeTrackColor: AppColors.primary,
              onChanged: (val) {
                appService.updateSettings(settings.copyWith(enableAdBlock: val));
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
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
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
                                valueListenable: AdBlockEngine.instance.lastUpdatedNotifier,
                                builder: (context, lastSync, _) {
                                  final syncText = lastSync != null
                                      ? '${lastSync.month}-${lastSync.day} ${lastSync.hour.toString().padLeft(2, "0")}:${lastSync.minute.toString().padLeft(2, "0")}'
                                      : '内置种子名单';
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '当前生效规则: $totalRules 条',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '上次更新: $syncText',
                                        style: TextStyle(fontSize: 10, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: isUpdating ? null : () => _triggerAdBlockUpdate(context),
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
                      onTap: () => _showAdBlockSourcesSheet(context, isDark),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '管理订阅源与自定义规则...',
                              style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ListTile(
            leading: const Icon(LucideIcons.globe, color: Colors.blueAccent, size: 20),
            title: const Text('自定义 User-Agent', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              settings.customUserAgent.isNotEmpty ? settings.customUserAgent : '使用内置移动端伪装标头',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showUADialog(context, isDark),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          SwitchListTile(
            secondary: const Icon(LucideIcons.refreshCw, color: AppColors.accentTeal, size: 20),
            title: const Text('启动时自动同步规则', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('从规则市场同步已订阅源的最新解析补丁', style: TextStyle(fontSize: 11)),
            value: settings.autoCheckRuleUpdates,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              appService.updateSettings(settings.copyWith(autoCheckRuleUpdates: val));
            },
          ),
        ],
      ),
    );
  }

  /// 4. 数据存储与精准深度清理卡片
  Widget _buildStorageMaintenanceCard(bool isDark) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '数据存储与深度维护',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(LucideIcons.hardDrive, color: Colors.purpleAccent, size: 20),
            title: const Text('数据全量备份与还原', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '规则库 (${ruleService.rules.length}条) · 收藏 (${favoriteService.favorites.length}项)',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showBackupSheet(context, isDark),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ListTile(
            leading: const Icon(LucideIcons.trash2, color: Colors.amber, size: 20),
            title: const Text('清理临时与网络图片缓存', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '占用空间：${_cacheSizeMB.toStringAsFixed(1)} MB',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: _isCleaning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () async {
                      setState(() => _isCleaning = true);
                      await appService.clearCache();
                      await _fetchCacheSize();
                      if (!mounted) return;
                      setState(() => _isCleaning = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已清理临时文件缓存')),
                      );
                    },
                    child: const Text('清理', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  ),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ListTile(
            leading: const Icon(LucideIcons.history, color: Colors.grey, size: 20),
            title: const Text('清空搜索历史记录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('共 ${historyService.searchHistory.length} 条记录', style: const TextStyle(fontSize: 11)),
            trailing: TextButton(
              onPressed: () async {
                await historyService.clearHistory();
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空搜索历史')),
                );
              },
              child: const Text('清空', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
  }

  /// 5. 主题与外观风格卡片
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
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(LucideIcons.palette, color: AppColors.primary, size: 20),
            title: const Text('界面风格主题', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(_getThemeModeLabel(settings.themeMode, isDark), style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showThemeDialog(context, isDark),
          ),
        ],
      ),
    );
  }

  /// 6. 关于与系统诊断卡片
  Widget _buildAboutDiagnosisCard(bool isDark) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '关于与系统诊断',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(LucideIcons.fileText, color: Colors.blueAccent, size: 20),
            title: const Text('沙箱运行日志', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('查看 QuickJS 规则解析与网络请求报错堆栈', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showLogsDialog(context, isDark),
          ),
        ],
      ),
    );
  }

  /// 查看沙箱日志弹窗
  void _showLogsDialog(BuildContext context, bool isDark) {
    final logs = AppLogger.getLogs();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('沙箱运行日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
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
