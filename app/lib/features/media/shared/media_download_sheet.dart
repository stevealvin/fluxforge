import 'package:flutter/foundation.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/features/library/downloads/widgets/download_bar.dart';

/// 呼出「离线下载」底部面板
///
/// 详情页顶部栏右侧的下载图标统一走这里：面板内展示任务当前状态
/// （复用 [DownloadBar] 的五态与实时进度），点击即执行对应动作
/// （暂停 / 继续 / 重试 / 开始），并给出「查看下载管理」入口。
///
/// **接线归调用方**：任务订阅（[tasks]）、任务查询（[taskOf]）与动作（[onAction]）
/// 全部由调用方注入 —— 面板自身不解析 DI、不决定动作，因此可脱 DI 测试。
Future<void> showMediaDownloadSheet(
  BuildContext context, {
  required String title,
  required String bookId,
  required String unitLabel,
  required ValueListenable<List<DownloadTask>> tasks,
  required DownloadTask? Function() taskOf,
  required Future<String> Function(DownloadTask? task) onAction,
  VoidCallback? onOpenDownloads,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
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
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
            ),

            // 五态下载入口：点击即执行动作，状态与进度随任务实时刷新
            ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: tasks,
              builder: (context, _, _) => DownloadBar(
                task: taskOf(),
                unitLabel: unitLabel,
                onTap: (task) async {
                  final message = await onAction(task);
                  if (!sheetContext.mounted) return;
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      duration: const Duration(milliseconds: 1800),
                    ),
                  );
                },
              ),
            ),

            if (onOpenDownloads != null)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 4),
                leading: const Icon(Ionicons.folderOpenOutline, color: AppColors.primary),
                title: const Text('查看下载管理', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onOpenDownloads();
                },
              ),
          ],
        ),
      ),
    ),
  );
}
