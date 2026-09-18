import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/di/di.dart';

/// 呼出「数据全量备份与还原」底部操作面板
///
/// 统一「我的」页与系统设置页的备份入口，彻底消除此前两份逐行重复的实现。
Future<void> showBackupSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                '数据全量备份与还原',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // 1. 一键导出备份包
            ListTile(
              leading: const Icon(Ionicons.cloudUploadOutline, color: AppColors.primary),
              title: const Text('一键导出备份数据包'),
              subtitle: const Text(
                '将规则库、收藏、搜索历史与观看进度打包为 JSON 并分享/保存至本地',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                try {
                  await backupService.exportBackup();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('导出备份失败: $e')),
                    );
                  }
                }
              },
            ),
            // 2. 从 JSON 文本恢复
            ListTile(
              leading: const Icon(Ionicons.cloudDownloadOutline, color: Colors.amber),
              title: const Text('从 JSON 文本/剪贴板恢复'),
              subtitle: const Text(
                '解析备份文件，支持合并追加或全量覆盖',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showImportRestoreDialog(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// 呼出「恢复备份数据」导入对话框
///
/// 支持粘贴备份 JSON 文本，并选择「合并导入」或「完全覆盖」两种还原策略。
Future<void> showImportRestoreDialog(BuildContext context) async {
  final controller = TextEditingController();
  bool mergeMode = true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('恢复备份数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请粘贴导出的 FluxForge 备份 JSON 文本内容：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '{\n  "app": "FluxForge",\n  "data": { ... }\n}',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Ionicons.clipboardOutline, size: 16),
                  tooltip: '粘贴剪贴板',
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      setDialogState(() {
                        controller.text = data!.text!;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: mergeMode,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    setDialogState(() {
                      mergeMode = val ?? true;
                    });
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setDialogState(() => mergeMode = !mergeMode),
                    child: Text(
                      mergeMode ? '合并导入 (保留现有，追加新增)' : '完全覆盖 (清空现有，以备份为准)',
                      style: TextStyle(
                        fontSize: 12,
                        color: mergeMode ? AppColors.primary : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final jsonStr = controller.text.trim();
              if (jsonStr.isEmpty) return;

              final result = await backupService.restoreBackup(
                jsonStr: jsonStr,
                merge: mergeMode,
              );

              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result.success
                        ? '${result.message}：规则+${result.rulesImported}，收藏+${result.favoritesImported}，'
                            '搜索历史+${result.historyImported}，观看进度+${result.playHistoryImported}'
                        : result.message,
                  ),
                ),
              );
            },
            child: const Text('执行恢复'),
          ),
        ],
      ),
    ),
  );

  // 对话框关闭后释放控制器，避免内存泄漏
  controller.dispose();
}
