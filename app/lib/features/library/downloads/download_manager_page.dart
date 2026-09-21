import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_confirm_dialog.dart';
import 'package:fluxforge/shared/widgets/app_empty_state.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 离线下载管理页（DownloadManagerPage）
///
/// 统一管理小说全本与漫画整部的离线下载任务：
/// 查看进度、暂停 / 继续 / 重试失败项、删除单条及清空全部，并展示沙盒占用空间。
class DownloadManagerPage extends StatefulWidget {
  const DownloadManagerPage({super.key});

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> {
  /// 沙盒中离线文件的总占用（字节）
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  /// 重新统计占用空间
  Future<void> _refreshSize() async {
    final bytes = await downloadService.totalBytes();
    if (mounted) setState(() => _totalBytes = bytes);
  }

  /// 字节转可读体积
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  /// 清理全部下载（二次确认）
  Future<void> _confirmClearAll() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清空全部离线内容',
      message: '将删除所有已下载的小说章节与漫画图片，该操作不可撤销。',
      confirmText: '确认清空',
    );
    if (!confirmed) return;

    await downloadService.clearAll();
    await _refreshSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空全部离线下载内容')),
    );
  }

  /// 删除单个任务（连带本地文件）
  Future<void> _removeTask(DownloadTask task) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除《${task.title}》离线内容',
      message: '将删除该书已下载的本地文件，该操作不可撤销。',
      confirmText: '删除',
    );
    if (!confirmed) return;

    await downloadService.remove(task.id);
    await _refreshSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除该书离线内容')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('离线下载', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          ValueListenableBuilder<List<DownloadTask>>(
            valueListenable: downloadService.tasksNotifier,
            builder: (context, tasks, _) {
              if (tasks.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空全部离线内容',
                icon: const Icon(Ionicons.trashOutline, size: 20),
                onPressed: _confirmClearAll,
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<DownloadTask>>(
        valueListenable: downloadService.tasksNotifier,
        builder: (context, tasks, _) {
          if (tasks.isEmpty) {
            return const AppEmptyState(
              icon: Ionicons.cloudDownloadOutline,
              title: '暂无离线下载',
              description:
                  '在小说、漫画或视频详情页点击「下载」，即可保存到手机沙盒离线观看或阅读',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildSummaryCard(tasks, isDark),
              const SizedBox(height: 14),
              ...tasks.map((task) => _buildTaskCard(task, isDark)),
            ],
          );
        },
      ),
    );
  }

  /// 顶部占用空间概览
  Widget _buildSummaryCard(List<DownloadTask> tasks, bool isDark) {
    final activeCount = tasks.where((t) => t.isActive).length;
    final doneCount = tasks.where((t) => t.isFinished).length;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: 14,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Ionicons.archiveOutline, color: AppColors.accentBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '沙盒占用 ${_formatBytes(_totalBytes)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '共 ${tasks.length} 项 · 已完成 $doneCount · 下载中 $activeCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 单个下载任务卡片
  Widget _buildTaskCard(DownloadTask task, bool isDark) {
    final unit = switch (task.mediaType) {
      'novel' => '章',
      'comic' => '页',
      'video' => '集',
      _ => '项',
    };

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderRadius: 14,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 70,
                  child: AppImage(imageUrl: task.cover, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),

              // 主体信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 类型徽标
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            switch (task.mediaType) {
                              'novel' => '小说',
                              'comic' => '漫画',
                              'video' => '视频',
                              _ => '其他',
                            },
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 状态徽标
                        Text(
                          task.status.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: _statusColor(task.status),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 4,
                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${task.progressLabel} $unit'
                      '${task.failed.isNotEmpty ? ' · 失败 ${task.failed.length} $unit' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 操作行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task.isActive)
                TextButton.icon(
                  style: _actionStyle(),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    downloadService.pause(task.id);
                  },
                  icon: const Icon(Ionicons.pauseOutline, size: 14),
                  label: const Text('暂停', style: TextStyle(fontSize: 12)),
                )
              else if (task.isFinished)
                TextButton.icon(
                  style: _actionStyle(),
                  onPressed: () => _showSnack('该作品已完整下载到本地沙盒'),
                  icon: const Icon(Ionicons.cloudDoneOutline, size: 14),
                  label: const Text('已完成', style: TextStyle(fontSize: 12)),
                )
              else
                TextButton.icon(
                  style: _actionStyle(),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (task.failed.isNotEmpty) {
                      downloadService.retryFailed(task.id);
                    } else {
                      downloadService.resume(task.id);
                    }
                  },
                  icon: const Icon(Ionicons.playOutline, size: 14),
                  label: Text(
                    task.failed.isNotEmpty ? '重试失败项' : '继续',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(width: 6),
              TextButton.icon(
                style: _actionStyle(color: Colors.redAccent),
                onPressed: () => _removeTask(task),
                icon: const Icon(Ionicons.trashOutline, size: 14),
                label: const Text('删除', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _actionStyle({Color color = AppColors.primary}) {
    return TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Color _statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return AppColors.success;
      case DownloadStatus.failed:
        return AppColors.danger;
      case DownloadStatus.paused:
        return AppColors.warning;
      case DownloadStatus.running:
      case DownloadStatus.pending:
        return AppColors.accentBlue;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(milliseconds: 1600)),
    );
  }
}
