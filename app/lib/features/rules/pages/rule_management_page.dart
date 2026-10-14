import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_confirm_dialog.dart';
import 'package:fluxforge/shared/widgets/app_delete_snack_bar.dart';
import 'package:fluxforge/shared/widgets/app_empty_state.dart';

/// 规则管理页（管理侧）
///
/// 与规则 Tab（使用侧）分工：这里只做管理动作 —— 启用与禁用、删除、调试测试、
/// 测速巡检、失效治理；「点击规则进分类发现」留在规则 Tab。
class RuleManagementPage extends StatefulWidget {
  const RuleManagementPage({super.key});

  @override
  State<RuleManagementPage> createState() => _RuleManagementPageState();
}

class _RuleManagementPageState extends State<RuleManagementPage> {
  final RuleService _ruleService = ruleService;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// 批量治理（一键禁用 / 一键清理）进行中
  bool _isBulkWorking = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 失效判定，与 [RuleService] 的批量治理口径一致
  static bool _isFailed(int? ms) => ms != null && (ms < 0 || ms > 2500);

  static String _typeLabel(String type) => switch (type) {
    'video' => '视频',
    'novel' => '小说',
    'picture' => '图片',
    _ => type.isEmpty ? '未知' : type,
  };

  List<Rule> _filtered(List<Rule> rules) {
    if (_searchQuery.isEmpty) return rules;
    final q = _searchQuery.toLowerCase();
    return rules
        .where(
          (r) =>
              r.name.toLowerCase().contains(q) ||
              r.baseUrl.toLowerCase().contains(q) ||
              r.type.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text(
          '规则管理',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _ruleService.isPingingNotifier,
            builder: (context, isPinging, _) {
              if (isPinging) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                tooltip: '一键测速巡检',
                icon: const Icon(Ionicons.speedometerOutline),
                onPressed: () => _ruleService.pingAllRules(),
              );
            },
          ),
          IconButton(
            tooltip: '规则市场',
            icon: const Icon(Ionicons.storefrontOutline),
            onPressed: () => context.pushMarket(),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Rule>>(
        valueListenable: _ruleService.rulesNotifier,
        builder: (context, rules, _) =>
            ValueListenableBuilder<Map<String, int>>(
              valueListenable: _ruleService.latenciesNotifier,
              builder: (context, latencies, _) {
                final filtered = _filtered(rules);
                final failedCount = rules
                    .where(
                      (r) => _isFailed(latencies[_ruleService.getRuleKey(r)]),
                    )
                    .length;

                return Column(
                  children: [
                    _buildToolbar(rules, isDark),
                    if (failedCount > 0) _buildBulkBar(failedCount),
                    Expanded(
                      child: filtered.isEmpty
                          ? AppEmptyState(
                              icon: Ionicons.optionsOutline,
                              title: rules.isEmpty ? '暂无本地规则' : '没有匹配的规则',
                              description: rules.isEmpty
                                  ? '从规则市场订阅，或在规则 Tab 导入规则后即可在此管理'
                                  : '换个关键词试试，或清空搜索框',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) => _buildRuleTile(
                                filtered[index],
                                latencies[_ruleService.getRuleKey(
                                  filtered[index],
                                )],
                                isDark,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  /// 搜索框与启用计数
  Widget _buildToolbar(List<Rule> rules, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final enabledCount = rules.where((r) => r.enabled).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索规则名称、类型或地址',
                hintStyle: TextStyle(fontSize: 13, color: muted),
                prefixIcon: Icon(
                  Ionicons.searchOutline,
                  size: 16,
                  color: muted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '启用 $enabledCount / ${rules.length}',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
        ],
      ),
    );
  }

  /// 失效治理条（仅在有失效规则时出现）
  Widget _buildBulkBar(int failedCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Ionicons.warningOutline,
              size: 16,
              color: AppColors.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '检测到 $failedCount 条失效或超时规则',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (_isBulkWorking)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              TextButton(
                onPressed: _disableFailed,
                child: const Text('一键禁用', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _removeFailed(failedCount),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('一键清理', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 单条规则行：点击弹出管理面板，尾部为启用开关
  Widget _buildRuleTile(Rule rule, int? latency, bool isDark) {
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        borderRadius: 14,
        onTap: () => _showActionsSheet(rule),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          rule.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _typeLabel(rule.type),
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                      if ((rule.version ?? '').isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Text(
                          'v${rule.version}',
                          style: TextStyle(fontSize: 10.5, color: muted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rule.baseUrl.isEmpty ? '未配置源站' : rule.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildLatencyLabel(latency, muted),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: rule.enabled,
              activeTrackColor: AppColors.primary,
              onChanged: (value) =>
                  _ruleService.toggleRule(rule.id ?? rule.name, value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyLabel(int? latency, Color muted) {
    if (latency == null) {
      return Text('未测速', style: TextStyle(fontSize: 11, color: muted));
    }
    final failed = _isFailed(latency);
    return Text(
      failed ? '超时' : '$latency ms',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: failed ? AppColors.danger : AppColors.success,
      ),
    );
  }

  /// 单条规则的管理动作面板
  void _showActionsSheet(Rule rule) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  rule.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Ionicons.flaskOutline, size: 20),
              title: const Text(
                '规则调试与测试',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                context.pushRuleTest(rule);
              },
            ),
            if (rule.baseUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Ionicons.copyOutline, size: 20),
                title: const Text('复制源站地址', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  rule.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _copyBaseUrl(rule);
                },
              ),
            ListTile(
              leading: const Icon(
                Ionicons.trashOutline,
                size: 20,
                color: AppColors.danger,
              ),
              title: const Text(
                '删除此规则',
                style: TextStyle(fontSize: 14, color: AppColors.danger),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDelete(rule);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _copyBaseUrl(Rule rule) {
    Clipboard.setData(ClipboardData(text: rule.baseUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制源站地址至剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _confirmDelete(Rule rule) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除规则',
      message: '将删除规则「${rule.name}」，该操作不可撤销。',
      confirmText: '删除',
    );
    if (!confirmed || !mounted) return;

    await _ruleService.removeRule(rule.id ?? rule.name);
    if (!mounted) return;
    showDeleteSnackBar(context, message: '已删除规则「${rule.name}」');
  }

  Future<void> _disableFailed() async {
    setState(() => _isBulkWorking = true);
    final count = await _ruleService.disableFailedRules();
    if (!mounted) return;
    setState(() => _isBulkWorking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已禁用 $count 条失效规则'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _removeFailed(int failedCount) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清理失效规则',
      message: '将删除 $failedCount 条失效或超时规则，该操作不可撤销。',
      confirmText: '清理',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isBulkWorking = true);
    final count = await _ruleService.removeFailedRules();
    if (!mounted) return;
    setState(() => _isBulkWorking = false);
    showDeleteSnackBar(context, message: '已清理 $count 条失效规则');
  }
}
