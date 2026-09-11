import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../widgets/app_card.dart';

/// 客户端全链路沙箱与系统日志中心页面
///
/// 具备：
/// 1. 响应式无阻塞监听 QuickJS 沙箱内的 console.log 及网络与核心框架报错；
/// 2. 实时按关键词防抖搜索与多维度级别（Rule / Network / ERROR / WARN / INFO / DEBUG）筛选；
/// 3. 单条日志展开排查、长按复制与一键全量导出分享；
/// 4. Live 实时追踪自动滚屏模式，边调试规则边观察沙箱输出。
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 当前选中的标签分类过滤
  String _selectedFilter = 'ALL';

  /// 搜索关键词
  String _searchQuery = '';

  /// 是否开启 Live 实时自动滚动追踪最新日志
  bool _autoScroll = false;

  /// 已展开的日志条目索引集合 (以时间戳微秒作为稳定 key)
  final Set<int> _expandedLogKeys = {};

  @override
  void initState() {
    super.initState();
    // 监听日志更新，若开启自动滚动则在下一帧将列表滚到底部（注意倒序排列时顶部为最新）
    AppLogger.logsNotifier.addListener(_onLogsUpdated);
  }

  @override
  void dispose() {
    AppLogger.logsNotifier.removeListener(_onLogsUpdated);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsUpdated() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// 过滤后的日志条目
  List<LogEntry> _getFilteredLogs(List<LogEntry> allLogs) {
    return allLogs.where((entry) {
      // 1. 级别或来源标签过滤
      if (_selectedFilter == 'RULE') {
        if (!entry.tag.toLowerCase().contains('rule')) return false;
      } else if (_selectedFilter == 'NETWORK') {
        if (entry.tag.toLowerCase() != 'network') return false;
      } else if (_selectedFilter == 'ERROR') {
        if (entry.level != 'ERROR') return false;
      } else if (_selectedFilter == 'WARN') {
        if (entry.level != 'WARN' && entry.level != 'WARNING') return false;
      } else if (_selectedFilter == 'INFO') {
        if (entry.level != 'INFO') return false;
      } else if (_selectedFilter == 'DEBUG') {
        if (entry.level != 'DEBUG') return false;
      }

      // 2. 关键词模糊检索
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchMessage = entry.message.toLowerCase().contains(q);
        final matchTag = entry.tag.toLowerCase().contains(q);
        final matchError = entry.error?.toString().toLowerCase().contains(q) ?? false;
        if (!matchMessage && !matchTag && !matchError) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// 一键全量复制或分享诊断文本
  void _shareOrExportLogs(BuildContext context) {
    final text = AppLogger.exportLogsAsText();
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(LucideIcons.checkCheck, color: AppColors.primary),
                title: Text('全量日志已复制到剪贴板', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('您可以直接粘贴发送给开发者或附加至 Issue 中', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.share2, size: 16),
                      label: const Text('系统分享文本'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        SharePlus.instance.share(
                          ShareParams(
                            text: text,
                            subject: 'FluxForge 系统诊断日志',
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('好的'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出清空日志确认弹窗
  void _confirmClearLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空诊断日志'),
        content: const Text('确定要清空内存中的所有运行日志与本地错误缓存吗？该操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(ctx);
              await AppLogger.clear();
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('已清空全部日志记录')),
              );
            },
            child: const Text('确定清空'),
          ),
        ],
      ),
    );
  }

  /// 触发生成模拟测试日志 (方便未跑规则时快速验证 UI)
  void _injectDemoLogs() {
    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule: 极光示例源',
      message: '开始解析目标页面: https://api.fluxforge.internal/demo',
    );
    AppLogger.addLog(
      level: 'DEBUG',
      tag: 'Rule: 极光示例源',
      message: 'console.log => 抓取到 18 条章节数据, 耗时 42ms',
    );
    AppLogger.addLog(
      level: 'WARN',
      tag: 'Network',
      message: '图片直链加载较慢 (超过 1500ms): https://img.example.com/cover.jpg',
    );
    AppLogger.addLog(
      level: 'ERROR',
      tag: 'Rule: 测试嗅探器',
      message: 'TypeError: Cannot read property "length" of undefined in parse()',
      error: 'QuickJS ReferenceError',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已写入 4 条示例测试日志')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('沙箱运行日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(width: 8),
            ValueListenableBuilder<List<LogEntry>>(
              valueListenable: AppLogger.logsNotifier,
              builder: (context, logs, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${logs.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          // Live 实时滚动追踪开关
          IconButton(
            tooltip: _autoScroll ? '实时跟踪模式 (已开启)' : '开启实时跟踪',
            icon: Icon(
              _autoScroll ? LucideIcons.radio : LucideIcons.arrowDownToLine,
              color: _autoScroll ? AppColors.primary : Colors.grey,
              size: 20,
            ),
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 1),
                  content: Text(_autoScroll ? '已开启实时滚屏跟踪' : '已暂停自动滚屏'),
                ),
              );
            },
          ),
          // 一键全量导出与复制
          IconButton(
            tooltip: '导出/复制全部日志',
            icon: const Icon(LucideIcons.copy, size: 20),
            onPressed: () => _shareOrExportLogs(context),
          ),
          // 清空日志
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(LucideIcons.trash2, size: 20),
            onPressed: () => _confirmClearLogs(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部控制栏 (搜索输入与快捷过滤 Chips)
            _buildControlHeader(isDark),

            // 2. 日志列表主体区
            Expanded(
              child: ValueListenableBuilder<List<LogEntry>>(
                valueListenable: AppLogger.logsNotifier,
                builder: (context, allLogs, _) {
                  final filteredLogs = _getFilteredLogs(allLogs);

                  if (filteredLogs.isEmpty) {
                    return _buildEmptyState(allLogs.isEmpty, isDark);
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      final entry = filteredLogs[index];
                      final logKey = entry.time.microsecondsSinceEpoch;
                      final isExpanded = _expandedLogKeys.contains(logKey);

                      return _buildLogCard(entry, isExpanded, logKey, isDark);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部控制栏：搜索框与分类标签
  Widget _buildControlHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface.withValues(alpha: 0.5) : AppColors.lightSurface.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // 搜索框
          TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索日志关键词、规则名称或报错信息...',
              hintStyle: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              isDense: true,
              filled: true,
              fillColor: isDark ? Colors.black26 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 0.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 0.5,
                ),
              ),
            ),
            onChanged: (val) {
              setState(() => _searchQuery = val.trim());
            },
          ),
          const SizedBox(height: 8),

          // 级别与分类过滤 Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ALL', '全部', isDark),
                const SizedBox(width: 6),
                _buildFilterChip('RULE', '规则沙箱', isDark, icon: LucideIcons.code),
                const SizedBox(width: 6),
                _buildFilterChip('ERROR', '错误', isDark, color: Colors.redAccent),
                const SizedBox(width: 6),
                _buildFilterChip('WARN', '警告', isDark, color: Colors.amber),
                const SizedBox(width: 6),
                _buildFilterChip('INFO', '信息', isDark, color: AppColors.primary),
                const SizedBox(width: 6),
                _buildFilterChip('DEBUG', '调试', isDark, color: Colors.blueAccent),
                const SizedBox(width: 6),
                _buildFilterChip('NETWORK', '网络', isDark, icon: LucideIcons.globe),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, bool isDark, {Color? color, IconData? icon}) {
    final isSelected = _selectedFilter == key;
    final activeColor = color ?? AppColors.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.2)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: isSelected ? activeColor : (isDark ? Colors.grey : Colors.black54)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? activeColor : (isDark ? Colors.grey : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单条日志渲染卡片
  Widget _buildLogCard(LogEntry entry, bool isExpanded, int logKey, bool isDark) {
    final hasStackOrLong = entry.message.length > 90 || entry.error != null || entry.stackTrace != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: AppCard(
        padding: EdgeInsets.zero,
        borderRadius: 12,
        onTap: hasStackOrLong
            ? () {
                setState(() {
                  if (isExpanded) {
                    _expandedLogKeys.remove(logKey);
                  } else {
                    _expandedLogKeys.add(logKey);
                  }
                });
              }
            : null,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          Clipboard.setData(ClipboardData(text: entry.toExportString()));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 1),
              content: Text('已复制该条 [${entry.tag}] 日志'),
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧级别高亮指示条
            Container(
              width: 4,
              height: isExpanded ? null : 48,
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: entry.levelColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部元数据行 (时间 + 级别 Badge + Tag 标签)
                    Row(
                      children: [
                        Text(
                          entry.formattedTime,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: entry.levelColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.level,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: entry.levelColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                        if (hasStackOrLong)
                          Icon(
                            isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: 14,
                            color: Colors.grey,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 日志内容文本
                    SelectableText(
                      entry.message,
                      maxLines: isExpanded ? null : 3,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontFamily: 'monospace',
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),

                    // 展开的异常或堆栈详细视图
                    if (isExpanded && (entry.error != null || entry.stackTrace != null)) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black38 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: entry.levelColor.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.error != null)
                              Text(
                                'Error: ${entry.error}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.redAccent,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            if (entry.stackTrace != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${entry.stackTrace}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态视图
  Widget _buildEmptyState(bool isTotalEmpty, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.fileCode, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              isTotalEmpty ? '当前暂无运行日志' : '未匹配到符合条件的日志',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isTotalEmpty
                  ? '沙箱内的 console.log、网络请求与解析异常将在此实时汇聚呈现'
                  : '请尝试更换筛选条件或清空搜索关键词',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
            if (isTotalEmpty) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(LucideIcons.sparkles, size: 16),
                label: const Text('写入模拟测试日志'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 0.8),
                ),
                onPressed: _injectDemoLogs,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
