import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/features/library/downloads/models/download_unit.dart';
import 'package:fluxforge/features/library/downloads/widgets/download_bar.dart';

/// 呼出「离线下载」底部面板
///
/// 详情页顶部栏右侧的下载图标统一走这里，面板提供两条路径：
/// - **选集下载**：勾选要保存的分集 / 章节 / 页，只下这些；
/// - **全部下载**：一键全量（复用 [DownloadBar] 的五态与实时进度，
///   点击即执行 暂停 / 继续 / 重试 / 开始）。
///
/// **接线归调用方**：任务订阅（[tasks]）、任务查询（[taskOf]）、动作（[onAction]、
/// [onDownloadSelection]）与大小探测（[probeUnitSizes]）全部由调用方注入 ——
/// 面板自身不解析 DI、不决定动作，因此可脱 DI 测试。
Future<void> showMediaDownloadSheet(
  BuildContext context, {
  required String title,
  required String bookId,
  required String unitLabel,
  required ValueListenable<List<DownloadTask>> tasks,
  required DownloadTask? Function() taskOf,
  required Future<String> Function(DownloadTask? task) onAction,
  VoidCallback? onOpenDownloads,
  List<DownloadUnit> units = const [],
  Future<String> Function(Set<int> selection)? onDownloadSelection,
  Future<List<int?>> Function()? probeUnitSizes,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _DownloadSheetBody(
      title: title,
      unitLabel: unitLabel,
      tasks: tasks,
      taskOf: taskOf,
      onAction: onAction,
      onOpenDownloads: onOpenDownloads,
      units: units,
      onDownloadSelection: onDownloadSelection,
      probeUnitSizes: probeUnitSizes,
      isDark: isDark,
    ),
  );
}

class _DownloadSheetBody extends StatefulWidget {
  const _DownloadSheetBody({
    required this.title,
    required this.unitLabel,
    required this.tasks,
    required this.taskOf,
    required this.onAction,
    required this.units,
    required this.isDark,
    this.onOpenDownloads,
    this.onDownloadSelection,
    this.probeUnitSizes,
  });

  final String title;
  final String unitLabel;
  final ValueListenable<List<DownloadTask>> tasks;
  final DownloadTask? Function() taskOf;
  final Future<String> Function(DownloadTask? task) onAction;
  final List<DownloadUnit> units;
  final bool isDark;
  final VoidCallback? onOpenDownloads;
  final Future<String> Function(Set<int> selection)? onDownloadSelection;

  /// 返回**与 [units] 位置对齐**的单项大小（字节；`null` = 该项未知）
  final Future<List<int?>> Function()? probeUnitSizes;

  @override
  State<_DownloadSheetBody> createState() => _DownloadSheetBodyState();
}

class _DownloadSheetBodyState extends State<_DownloadSheetBody> {
  /// 已勾选的单元下标（`DownloadUnit.index`）
  final Set<int> _selected = <int>{};

  /// 与 [widget.units] 位置对齐的单项大小；`null` 表示尚未探测
  List<int?>? _sizes;
  bool _probing = false;

  bool get _canSelect =>
      widget.onDownloadSelection != null && widget.units.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final probe = widget.probeUnitSizes;
    if (probe != null && widget.units.isNotEmpty) {
      _probing = true;
      unawaited(_loadSizes(probe));
    }
  }

  Future<void> _loadSizes(Future<List<int?>> Function() probe) async {
    List<int?>? sizes;
    try {
      sizes = await probe();
    } catch (_) {
      // 探测失败只影响「预计大小」这一行展示，不影响下载
      sizes = null;
    }
    if (!mounted) return;
    setState(() {
      _sizes = sizes;
      _probing = false;
    });
  }

  /// 选中项的合计大小；`null` = 没有一项拿到大小
  int? get _selectedBytes {
    final sizes = _sizes;
    if (sizes == null) return null;
    var total = 0;
    var known = false;
    for (int i = 0; i < widget.units.length; i++) {
      if (!_selected.contains(widget.units[i].index)) continue;
      final size = i < sizes.length ? sizes[i] : null;
      if (size == null || size <= 0) continue;
      total += size;
      known = true;
    }
    return known ? total : null;
  }

  /// 选中项里是否还有拿不到大小的（HLS 等）
  bool get _hasUnknownSelectedSize {
    final sizes = _sizes;
    if (sizes == null) return false;
    for (int i = 0; i < widget.units.length; i++) {
      if (!_selected.contains(widget.units[i].index)) continue;
      final size = i < sizes.length ? sizes[i] : null;
      if (size == null || size <= 0) return true;
    }
    return false;
  }

  /// 「已选 N 项 · 预计约 X」摘要
  String get _selectionSummary {
    final count = _selected.length;
    if (_probing) return '已选 $count 项 · 正在估算大小…';
    final bytes = _selectedBytes;
    if (bytes == null) {
      return _selected.isEmpty ? '已选 0 项' : '已选 $count 项 · 大小未知';
    }
    final text = '已选 $count 项 · 预计 ${formatDownloadSize(bytes)}';
    return _hasUnknownSelectedSize ? '$text 以上' : text;
  }

  void _toggleUnit(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(widget.units.map((u) => u.index));
    });
  }

  void _clearAll() => setState(_selected.clear);

  Future<void> _downloadSelected() async {
    final action = widget.onDownloadSelection;
    if (action == null || _selected.isEmpty) return;
    final message = await action({..._selected});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                '离线下载',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 12),
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
            ),

            if (_canSelect) ...[
              _buildSelectionSection(isDark),
              const SizedBox(height: 12),
            ],

            // 全部下载 / 状态条：五态入口，点击即执行动作，进度实时刷新
            ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: widget.tasks,
              builder: (context, _, _) => DownloadBar(
                task: widget.taskOf(),
                unitLabel: widget.unitLabel,
                idleLabel: widget.units.isEmpty
                    ? null
                    : '下载全部 ${widget.units.length} ${widget.unitLabel}',
                onTap: (task) async {
                  final message = await widget.onAction(task);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      duration: const Duration(milliseconds: 1800),
                    ),
                  );
                },
              ),
            ),

            if (widget.onOpenDownloads != null)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 4),
                leading: const Icon(
                  Ionicons.folderOpenOutline,
                  color: AppColors.primary,
                ),
                title: const Text('查看下载管理', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenDownloads!();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 选集区：标题行 + 勾选列表 + 「下载选中」
  Widget _buildSelectionSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '选集下载',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectionSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
            ),
            TextButton(
              style: _linkStyle(),
              onPressed: _selectAll,
              child: const Text('全选', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              style: _linkStyle(),
              onPressed: _selected.isEmpty ? null : _clearAll,
              child: const Text('清空', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            // 列表高度自适应，最多占 200：单元少时不留大片空白，多时可滚动
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: widget.units.length,
              itemBuilder: (context, i) => _buildUnitRow(i, isDark),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selected.isEmpty ? null : _downloadSelected,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _selected.isEmpty ? '下载选中' : '下载选中（${_selected.length} 项）',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnitRow(int position, bool isDark) {
    final unit = widget.units[position];
    final checked = _selected.contains(unit.index);
    final sizes = _sizes;
    final size = (sizes != null && position < sizes.length)
        ? sizes[position]
        : null;

    return InkWell(
      onTap: () => _toggleUnit(unit.index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => _toggleUnit(unit.index),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                unit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: checked
                      ? AppColors.primary
                      : (isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary),
                ),
              ),
            ),
            if (size != null && size > 0)
              Text(
                formatDownloadSize(size),
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _linkStyle() {
    return TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
