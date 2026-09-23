import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 「我的」页顶部身份 Hero 卡 (ProfileHero)
///
/// 承载身份标题、沙箱运行状态、主题三态快捷切换与设置唯一入口，
/// 替代旧版页面中重复出现的设置按钮与静态假数据。
///
/// 说明：原「点击修改昵称」功能已移除 —— 昵称的读取与持久化落在组件内属于越界
/// （组件直接读写 `AppStorage`），且该页与设置页将重新设计。因此本卡不再持有任何本地状态。
class ProfileHero extends StatelessWidget {
  const ProfileHero({super.key});

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
                  // 极光渐变品牌头像
                  Container(
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
                      child: Icon(
                        Ionicons.compassOutline,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 身份标题与沙箱运行状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 身份标题（原「点击修改昵称」已移除，该页将重新设计）
                        Text(
                          'FluxForge 探索者',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
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
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary,
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
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                    onPressed: () => context.pushSettings(),
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
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.primary.withValues(alpha: 0.16);
                          }
                          return Colors.transparent;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.primary;
                          }
                          return isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary;
                        }),
                        side: WidgetStatePropertyAll(
                          BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
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
