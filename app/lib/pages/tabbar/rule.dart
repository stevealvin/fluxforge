import 'package:material_ui/material_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../model/rule.dart';

import '../../di/rule_service.dart';

/// 客户端本地规则管理页面
/// 支持响应式规则列表、状态启停、网络/JSON多源导入、快速跳转市场与发现测试
class RulePage extends StatefulWidget {
  const RulePage({super.key});

  @override
  State<RulePage> createState() => _RulePageState();
}

class _RulePageState extends State<RulePage> {
  final RuleService _ruleService = GetIt.I<RuleService>();

  /// 弹出添加/导入规则对话框
  void _showImportDialog(BuildContext context) {
    int activeTab = 0;
    // 默认不预填任何内容，严格对齐用户偏好
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
                    // 顶部拖拽条
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
                    // 标题与前往市场快捷入口
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
                    // 切换导入模式 (网络链接 / 粘贴JSON)
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '支持 Legado 风格订阅源、单条规则或规则数组格式。',
                        style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.8)),
                      ),
                    ] else ...[
                      TextField(
                        controller: jsonController,
                        autofocus: true,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: '在此粘贴规则 JSON 文本...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.withValues(alpha: 0.8)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E2D27) : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // 确认操作按钮
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final text = activeTab == 0 ? urlController.text.trim() : jsonController.text.trim();
                              if (text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('输入内容不能为空')),
                                );
                                return;
                              }

                              setModalState(() {
                                isSubmitting = true;
                              });

                              try {
                                int count = 0;
                                if (activeTab == 0) {
                                  count = await _ruleService.importFromUrl(text);
                                } else {
                                  count = await _ruleService.importFromJson(text);
                                }

                                if (context.mounted) {
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('成功导入 $count 条规则！'),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() {
                                  isSubmitting = false;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('导入失败: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('立即导入', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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

  /// 删除规则确认
  void _confirmDeleteRule(BuildContext context, Rule rule) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('删除规则'),
          content: Text('确定要删除规则「${rule.name}」吗？此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                await _ruleService.removeRule(rule.id);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除规则「${rule.name}」')),
                  );
                }
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  /// 构建单张规则卡片
  Widget _buildRuleCard(BuildContext context, Rule rule, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D19) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rule.enabled
              ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.25)
              : (isDark ? const Color(0xFF1E2D27) : const Color(0xFFE5E7EB)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            context.push('/rule_discovery', extra: {'rule': rule});
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：类型标签、规则名称、开关
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        rule.type.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: rule.enabled ? null : Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch(
                      value: rule.enabled,
                      activeThumbColor: const Color(0xFF10B981),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        _ruleService.toggleRule(rule.id, val);
                      },
                    ),
                  ],
                ),
                // 规则描述
                if (rule.description != null && rule.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    rule.description!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                // 底部信息与快捷动作
                Row(
                  children: [
                    const Icon(LucideIcons.globe, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rule.baseUrl,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'v${rule.version ?? '1.0.0'}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onSelected: (action) {
                        if (action == 'discovery') {
                          context.push('/rule_discovery', extra: {'rule': rule});
                        } else if (action == 'delete') {
                          _confirmDeleteRule(context, rule);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'discovery',
                          child: Row(
                            children: [
                              Icon(LucideIcons.compass, size: 16),
                              SizedBox(width: 8),
                              Text('测试发现流'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('删除规则', style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 空状态构建
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.folderClosed, size: 40, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无本地规则',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '您可以前往在线规则市场一键订阅，或使用网络链接与剪贴板手动导入。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => context.push('/market'),
                  icon: const Icon(LucideIcons.store, size: 16),
                  label: const Text('前往规则市场'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showImportDialog(context),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('手动导入'),
                ),
              ],
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
      appBar: AppBar(
        title: const Text('规则管理', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: '规则市场',
            icon: const Icon(LucideIcons.store),
            onPressed: () => context.push('/market'),
          ),
          IconButton(
            tooltip: '导入规则',
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showImportDialog(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Rule>>(
        valueListenable: _ruleService.rulesNotifier,
        builder: (context, rules, _) {
          if (rules.isEmpty) {
            return _buildEmptyState(context);
          }

          final enabledCount = rules.where((r) => r.enabled).length;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: rules.length + 1,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                // 顶部统计信息卡
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131D19) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.layers, size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Text(
                            '已启用 $enabledCount / 总计 ${rules.length} 条规则',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFF059669),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => context.push('/market'),
                        icon: const Icon(LucideIcons.externalLink, size: 14),
                        label: const Text('发现更多', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }

              final rule = rules[index - 1];
              return _buildRuleCard(context, rule, isDark);
            },
          );
        },
      ),
    );
  }
}
