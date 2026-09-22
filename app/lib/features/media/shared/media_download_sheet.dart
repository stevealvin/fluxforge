import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/features/library/downloads/models/download_unit.dart';
import 'package:fluxforge/features/library/downloads/widgets/download_bar.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

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
      // 内容（选集卡片 + 动作行 + 任务状态条）在窄屏上可能超过半屏高度：
      // 外层可滚动，避免 RenderFlex 溢出把面板顶穿
      child: SingleChildScrollView(
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

            // 底部动作行：「下载选中」为主，「下载全部」紧随其后（同族动作、范围不同）
            ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: widget.tasks,
              builder: (context, _, _) => _buildActionRow(),
            ),

            // 任务状态条：仅在已有任务时出现（承载进度与暂停 / 继续 / 重试）。
            // 未开始时「下载全部」已由动作行承担，两者同时出现等于同一动作两个入口。
            ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: widget.tasks,
              builder: (context, _, _) {
                final task = widget.taskOf();
                if (task == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: DownloadBar(
                    task: task,
                    unitLabel: widget.unitLabel,
                    onTap: _runTaskAction,
                  ),
                );
              },
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

  /// 选集区：标题行（摘要 + 全选 / 清空）+ 卡片列表（动作行由 [build] 统一给出）
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
        const SizedBox(height: 8),
        ConstrainedBox(
          // 高度自适应，最多占 220：单元少时不留大片空白，多时网格内滚动
          constraints: const BoxConstraints(maxHeight: 220),
          child: GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              // 对齐漫画章节目录的紧凑格子：高 40、间距 8，列数仍按可用宽度自适应
              maxCrossAxisExtent: 112,
              mainAxisExtent: 40,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: widget.units.length,
            itemBuilder: (context, i) => _buildUnitCard(i, isDark),
          ),
        ),
      ],
    );
  }

  /// 单个可下载单元（紧凑网格格子，密度对齐漫画章节目录）
  ///
  /// **未选中不画边框线**（透明边框仅用于占位，切换时不跳尺寸）；
  /// 选中态以颜色边框为主：主色描边 + 主色微底 + 主色加粗标题。边框在加色的同时
  /// **加粗**（0.8 → 1.4）—— 颜色之外还有一处可辨差异，色弱用户同样分得清。
  /// 格子窄且矮，故只放标题（单项大小仍在「已选 N 项 · 预计 X」摘要里给出）。
  Widget _buildUnitCard(int position, bool isDark) {
    final unit = widget.units[position];
    final checked = _selected.contains(unit.index);

    return AppCard.outlined(
      key: ValueKey('download_unit_${unit.index}'),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      borderRadius: 8,
      color: checked
          ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10)
          // 未选中用「比面板深一档」的内嵌块底色：地面板是纯白，铺纯白等于没有边界
          : (isDark ? AppColors.darkCard : AppColors.lightSurfaceVariant),
      borderColor: checked ? AppColors.primary : Colors.transparent,
      borderWidth: checked ? 1.4 : 0.8,
      onTap: () => _toggleUnit(unit.index),
      child: Center(
        child: Text(
          unit.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
            color: checked
                ? AppColors.primary
                : (isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary),
          ),
        ),
      ),
    );
  }

  /// 底部动作行：主按钮「下载选中」+ 次按钮「下载全部」
  ///
  /// 「下载全部」放在这里而不是选择工具栏（全选 / 清空）之后 —— 二者都是**发起下载**，
  /// 只是范围不同；「清空」属于选区编辑，与它并列会让「清空」读起来像下载的前置步骤。
  /// 已有任务时不再重复此入口：状态条本身承载「继续 / 重试」。
  Widget _buildActionRow() {
    final hasUnits = widget.units.isNotEmpty;
    final showDownloadAll = hasUnits && widget.taskOf() == null;

    if (!_canSelect && !hasUnits) return const SizedBox.shrink();

    return Row(
      children: [
        if (_canSelect)
          Expanded(
            flex: showDownloadAll ? 3 : 1,
            child: SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: _selected.isEmpty ? null : _downloadSelected,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _selected.isEmpty ? '下载选中' : '下载选中（${_selected.length} 项）',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        if (_canSelect && showDownloadAll) const SizedBox(width: 10),
        if (showDownloadAll)
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: () => _runTaskAction(null),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  '下载全部 ${widget.units.length} ${widget.unitLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 触发一次任务动作并把宿主反馈以 SnackBar 呈现（「下载全部」与状态条共用）
  Future<void> _runTaskAction(DownloadTask? task) async {
    final message = await widget.onAction(task);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1800),
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
