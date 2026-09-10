import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../services/app_service.dart';
import '../../services/di.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import 'adblock_engine.dart';

/// 广告拦截规则管理独立页面
///
/// 提供全局拦截总开关、内置与自定义规则订阅源管理、单源/全量规则热更及三大防御能力全景展示
class AdBlockRulesPage extends StatefulWidget {
  const AdBlockRulesPage({super.key});

  @override
  State<AdBlockRulesPage> createState() => _AdBlockRulesPageState();
}

class _AdBlockRulesPageState extends State<AdBlockRulesPage> {
  final AdBlockEngine _engine = AdBlockEngine.instance;

  @override
  void initState() {
    super.initState();
    _engine.initialize();
  }

  /// 触发全量规则更新
  Future<void> _triggerGlobalSync() async {
    final success = await _engine.updateRules();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '全量广告规则同步成功，当前生效 ${_engine.totalRulesNotifier.value} 条规则'
              : '部分规则镜像拉取失败，已无缝回退至本地/保底种子规则',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 触发单源更新
  Future<void> _triggerSingleSync(AdFilterSource source) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在更新 [${source.name}]...'),
        duration: const Duration(seconds: 1),
      ),
    );
    final success = await _engine.updateSingleSource(source.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? '[${source.name}] 更新成功！' : '[${source.name}] 更新失败，请检查网络或订阅地址',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 弹出添加自定义订阅源对话框
  void _showAddCustomSourceDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.plus, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Text('添加自定义规则订阅', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '支持标准 AdBlock / EasyList 格式规则文本 (.txt 链接)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '规则名称',
                    hintText: '例如: 我的去广告规则',
                    hintStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: '订阅 URL 地址',
                    hintText: 'https://example.com/filter.txt',
                    hintStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('取消'),
              ),
              AppButton.compact(
                label: '添加并拉取',
                loading: isSubmitting,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  if (name.isEmpty || !url.startsWith('http')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入合法的规则名称和以 http 开头的订阅地址')),
                    );
                    return;
                  }

                  setDialogState(() => isSubmitting = true);
                  final success = await _engine.addCustomSource(name, url);
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success ? '已成功添加并编译规则源 [$name]' : '已添加源 [$name]，但网络拉取超时，下次同步时将自动重试',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('广告拦截管理', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: '添加自定义订阅',
            icon: const Icon(LucideIcons.plus, size: 20),
            onPressed: _showAddCustomSourceDialog,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _engine.isUpdatingNotifier,
            builder: (context, isUpdating, _) {
              return isUpdating
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: '拉取全部更新',
                      icon: const Icon(LucideIcons.refreshCw, size: 18),
                      onPressed: _triggerGlobalSync,
                    );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<AppSettings>(
        valueListenable: appService.settingsNotifier,
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 1. 顶层核心总览 Hero 卡片
              _buildHeroOverviewCard(context, settings, isDark),

              const SizedBox(height: 20),

              // 2. 规则订阅源管理列表
              _buildSourcesSection(context, settings, isDark),
            ],
          );
        },
      ),
    );
  }

  /// 1. 顶层核心总览 Hero 卡片
  Widget _buildHeroOverviewCard(BuildContext context, AppSettings settings, bool isDark) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      showBorder: false,
      color: isDark ? AppColors.darkCard : AppColors.lightCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：图标 + 标题 + 总开关
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: settings.enableAdBlock
                      ? AppColors.primary.withValues(alpha: 0.14)
                      : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Icon(
                    settings.enableAdBlock ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                    color: settings.enableAdBlock
                        ? AppColors.primary
                        : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.enableAdBlock ? '内置网页广告拦截已开启' : '内置网页广告拦截已停用',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      settings.enableAdBlock ? '全自动阻断恶意弹窗、暗刷探针与牛皮癣悬浮' : '网页将按原始形态加载，不执行任何规则过滤',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: settings.enableAdBlock,
                activeTrackColor: AppColors.primary,
                onChanged: (val) {
                  appService.updateSettings(settings.copyWith(enableAdBlock: val));
                },
              ),
            ],
          ),

          if (settings.enableAdBlock) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: _engine.totalRulesNotifier,
                  builder: (context, totalRules, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '生效规则: ',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        Text(
                          '$totalRules 条',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _engine.isUpdatingNotifier,
                  builder: (context, isUpdating, _) {
                    return AppButton.compactTonal(
                      icon: const Icon(LucideIcons.refreshCw, size: 12),
                      label: isUpdating ? '正在同步...' : '立即同步',
                      loading: isUpdating,
                      onPressed: isUpdating ? null : _triggerGlobalSync,
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 2. 规则订阅源管理列表
  Widget _buildSourcesSection(BuildContext context, AppSettings settings, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Icon(LucideIcons.listFilter, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                '规则订阅源',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '开启或关闭独立源，即改即生效',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        ValueListenableBuilder<List<AdFilterSource>>(
          valueListenable: _engine.sourcesNotifier,
          builder: (context, sources, _) {
            return Column(
              children: sources.map((source) => _buildSourceCard(context, source, isDark)).toList(),
            );
          },
        ),
      ],
    );
  }

  /// 订阅源卡片
  Widget _buildSourceCard(BuildContext context, AdFilterSource source, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
        showBorder: false,
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：自定义徽章(如有) + 名称 + 开关
            Row(
              children: [
                if (!source.isBuiltIn) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '自定义',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    source.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Transform.scale(
                  scale: 0.82,
                  child: Switch(
                    value: source.isEnabled,
                    activeTrackColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      _engine.toggleSource(source.id, val);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // 规则描述
            Text(
              source.description,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),

            const SizedBox(height: 10),

            // 底部：镜像节点数 + 操作按钮
            Row(
              children: [
                Icon(
                  LucideIcons.server,
                  size: 11.5,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${source.mirrorUrls.length} 个加速镜像容灾节点',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
                ),
                const Spacer(),

                // 单源更新按键
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _triggerSingleSync(source),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.refreshCw, size: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                        const SizedBox(width: 3),
                        Text(
                          '拉取更新',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 自定义源删除按键
                if (!source.isBuiltIn) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      _engine.deleteCustomSource(source.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已移除自定义规则源 [${source.name}]')),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.trash2, size: 11, color: AppColors.danger),
                          SizedBox(width: 3),
                          Text('删除', style: TextStyle(fontSize: 11, color: AppColors.danger)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
