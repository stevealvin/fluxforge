import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/rule.dart';
import '../../../services/di.dart';
import '../../../widgets/app_card.dart';

/// 「我的」页顶部身份 Hero 卡 (ProfileHero)
///
/// 承载个人身份（可编辑昵称）、沙箱运行状态、主题三态快捷切换与设置唯一入口，
/// 替代旧版页面中重复出现的设置按钮与静态假数据。
class ProfileHero extends StatefulWidget {
  const ProfileHero({super.key});

  @override
  State<ProfileHero> createState() => _ProfileHeroState();
}

class _ProfileHeroState extends State<ProfileHero> {
  /// 昵称本地持久化键
  static const String _nicknameKey = 'profile_nickname';

  String _nickname = 'FluxForge 探索者';

  @override
  void initState() {
    super.initState();
    _loadNickname();
  }

  /// 加载本地昵称
  Future<void> _loadNickname() async {
    final saved = await AppStorage.getString(_nicknameKey);
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      setState(() => _nickname = saved.trim());
    }
  }

  /// 弹出昵称编辑对话框
  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(
            hintText: '请输入昵称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _nickname = result);
    await AppStorage.setString(_nicknameKey, result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('昵称已更新')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<List<Rule>>(
      valueListenable: ruleService.rulesNotifier,
      builder: (context, rules, _) {
        final enabledCount = rules.where((r) => r.enabled).length;

        return AppCard(
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          gradient: LinearGradient(
            colors: [
              AppColors.primaryLight.withValues(alpha: isDark ? 0.20 : 0.14),
              isDark ? AppColors.darkCard : AppColors.lightCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 极光渐变品牌头像（点击可修改昵称）
                  GestureDetector(
                    onTap: _editNickname,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.primaryLight, AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryLight.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Ionicons.compassOutline, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 昵称与沙箱运行状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: _editNickname,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Ionicons.createOutline,
                                size: 13,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '沙箱就绪 · $enabledCount 条规则启用 · v${appService.packageInfo?.version ?? "1.0.0"}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 设置唯一入口
                  IconButton(
                    tooltip: '系统偏好设置',
                    icon: Icon(
                      Ionicons.settingsOutline,
                      size: 20,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 主题三态快捷切换（跟随系统 / 纯净星暮白 / 曜夜极光翡翠）
              ValueListenableBuilder<ThemeMode>(
                valueListenable: appService.themeModeNotifier,
                builder: (context, mode, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Ionicons.phonePortraitOutline, size: 13),
                          label: Text('跟随系统', style: TextStyle(fontSize: 11.5)),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Ionicons.sunnyOutline, size: 13),
                          label: Text('浅色', style: TextStyle(fontSize: 11.5)),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Ionicons.moonOutline, size: 13),
                          label: Text('深色', style: TextStyle(fontSize: 11.5)),
                        ),
                      ],
                      selected: <ThemeMode>{mode},
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.primary.withValues(alpha: 0.16);
                          }
                          return Colors.transparent;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.primary;
                          }
                          return isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
                        }),
                        side: WidgetStatePropertyAll(
                          BorderSide(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            width: 0.8,
                          ),
                        ),
                      ),
                      onSelectionChanged: (selection) {
                        appService.updateThemeMode(selection.first);
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
