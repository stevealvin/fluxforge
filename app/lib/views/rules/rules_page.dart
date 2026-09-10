import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/rule_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/loading_indicator.dart';

/// 客户端本地规则管理页面
/// 支持响应式规则列表、状态启停、网络/JSON多源导入、快速跳转市场与发现测试
class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final RuleService _ruleService = ruleService;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return LucideIcons.film;
      case 'novel':
        return LucideIcons.bookOpen;
      case 'picture':
      case 'comic':
      case 'image':
        return LucideIcons.image;
      case 'audio':
        return LucideIcons.headphones;
      case 'crawler':
      default:
        return LucideIcons.globe;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return const Color(0xFF10B981); // Emerald
      case 'novel':
        return const Color(0xFFF59E0B); // Amber
      case 'picture':
      case 'comic':
      case 'image':
        return const Color(0xFF8B5CF6); // Violet
      case 'audio':
        return const Color(0xFF0EA5E9); // Sky
      case 'crawler':
      default:
        return const Color(0xFF14B8A6); // Teal
    }
  }

  String _getTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return '视频';
      case 'novel':
        return '小说';
      case 'picture':
      case 'comic':
      case 'image':
        return '图集';
      case 'audio':
        return '音频';
      case 'crawler':
        return '通用';
      default:
        final t = type.trim();
        if (t.endsWith('源')) {
          return t.substring(0, t.length - 1);
        }
        return t.toUpperCase();
    }
  }

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
                          ? const LoadingIndicator.compact(size: 20, color: Colors.white)
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

  /// 构建测速延迟三色微胶囊指示器
  Widget _buildLatencyBadge(int? latency, bool isDark) {
    if (latency == null) return const SizedBox.shrink();
    final bool isTimeout = latency < 0 || latency > 2500;
    final bool isFast = latency >= 0 && latency < 500;

    final Color color = isTimeout
        ? Colors.redAccent
        : (isFast ? const Color(0xFF10B981) : const Color(0xFFF59E0B));
    final String label = isTimeout ? '超时' : '${latency}ms';

    return Container(
      margin: const EdgeInsets.only(left: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单张现代化规则卡片
  Widget _buildRuleCard(BuildContext context, Rule rule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor = _getTypeColor(rule.type);
    final hasUrl = rule.baseUrl.isNotEmpty &&
        (rule.baseUrl.startsWith('http://') || rule.baseUrl.startsWith('https://'));

    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      onTap: () {
        context.push('/rule_discovery', extra: {'rule': rule});
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：图标容器 + 规则名称/版本/类型Badge + 启停Switch
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 紧凑 36x36 图标容器
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: typeColor.withValues(alpha: 0.2), width: 0.8),
                ),
                child: Center(
                  child: Icon(
                    _getTypeIcon(rule.type),
                    color: typeColor,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 规则名称与标签
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            rule.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: rule.enabled
                                  ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                  : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (rule.version != null && rule.version!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'v${rule.version}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),

                    // 类型 Badge 与 毫秒级测速微胶囊
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getTypeIcon(rule.type), size: 9, color: typeColor),
                              const SizedBox(width: 3),
                              Text(
                                _getTypeLabel(rule.type),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: typeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<Map<String, int>>(
                          valueListenable: _ruleService.latenciesNotifier,
                          builder: (context, latencies, _) {
                            final latency = latencies[_ruleService.getRuleKey(rule)];
                            return _buildLatencyBadge(latency, isDark);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 启停 Switch (无水波外扩)
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: rule.enabled,
                  activeThumbColor: const Color(0xFF10B981),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    _ruleService.toggleRule(rule.id, val);
                  },
                ),
              ),
            ],
          ),

          // 规则描述
          if (rule.description != null && rule.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              rule.description!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 8),

          // 底部：左侧站点直达链接（点击跳转 WebView） + 右侧删除按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 站点链接与地球小图标（点击直接打开站点）
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: hasUrl
                      ? () {
                          final encodedUrl = Uri.encodeComponent(rule.baseUrl);
                          final encodedTitle = Uri.encodeComponent(rule.name);
                          context.push('/web?url=$encodedUrl&title=$encodedTitle');
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.globe,
                          size: 12,
                          color: hasUrl
                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                              : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            rule.baseUrl.isNotEmpty ? rule.baseUrl : '无指定源站地址',
                            style: TextStyle(
                              fontSize: 11,
                              color: hasUrl
                                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                  : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextSecondary),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUrl) ...[
                          const SizedBox(width: 2),
                          Icon(
                            LucideIcons.arrowUpRight,
                            size: 11,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 删除规则按钮（消除原生 IconButton 默认占用的 48px 隐形点击高度）
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _confirmDeleteRule(context, rule),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: isDark ? Colors.redAccent.withValues(alpha: 0.85) : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
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
          ValueListenableBuilder<bool>(
            valueListenable: _ruleService.isPingingNotifier,
            builder: (context, isPinging, _) {
              if (isPinging) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                tooltip: '一键测速巡检',
                icon: const Icon(LucideIcons.gauge),
                onPressed: () => _ruleService.pingAllRules(),
              );
            },
          ),
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

          // 根据输入框即时过滤
          final filteredRules = rules.where((r) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            final nameMatch = r.name.toLowerCase().contains(q);
            final urlMatch = r.baseUrl.toLowerCase().contains(q);
            final typeMatch = r.type.toLowerCase().contains(q);
            final descMatch = (r.description ?? '').toLowerCase().contains(q);
            return nameMatch || urlMatch || typeMatch || descMatch;
          }).toList();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // 1. 顶部即时搜索栏
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightCard,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '搜索规则名称、类型或地址...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            LucideIcons.search,
                            size: 16,
                            color: _searchQuery.isNotEmpty
                                ? AppColors.primary
                                : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                          ),
                        ),
                        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 38),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.black.withValues(alpha: 0.07),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 13,
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            width: 0.8,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            width: 0.8,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                ),
              ),

              // 2. 失效规则治理轻提示横幅
              ValueListenableBuilder<Map<String, int>>(
                valueListenable: _ruleService.latenciesNotifier,
                builder: (context, latencies, _) {
                  final failedCount = latencies.values
                      .where((v) => v < 0 || v > 2500)
                      .length;
                  if (failedCount == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());

                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.alertCircle, size: 16, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '检测到 $failedCount 个失效或超时规则',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: Colors.amber,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: () async {
                                final count = await _ruleService.disableFailedRules();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('已禁用 $count 个失效规则')),
                                  );
                                }
                              },
                              child: const Text('一键禁用', style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: () async {
                                final count = await _ruleService.removeFailedRules();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('已清理 $count 个失效规则')),
                                  );
                                }
                              },
                              child: const Text('一键清理', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // 3. 规则列表
              if (filteredRules.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.packageOpen,
                            size: 44,
                            color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '未找到符合条件的规则',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary, width: 0.8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(LucideIcons.rotateCcw, size: 14),
                            label: const Text('重置搜索', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final rule = filteredRules[index];
                      return _buildRuleCard(context, rule);
                    },
                    childCount: filteredRules.length,
                  ),
                ),

              // 底部避让导航栏
              const SliverToBoxAdapter(
                child: SizedBox(height: 96),
              ),
            ],
          );
        },
      ),
    );
  }
}
