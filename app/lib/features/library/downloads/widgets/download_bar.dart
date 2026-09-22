import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 通用离线下载状态条（小说 / 漫画详情页共用）
///
/// 五态展示：未下载 / 下载中（点击暂停） / 已暂停（点击继续） / 部分失败（点击重试） / 已完成。
///
/// **纯展示组件**：任务数据由宿主传入，`onTap` 透传当前任务 ——
/// 组件自身不解析 DI、不订阅服务、不决定动作。订阅（宿主侧
/// `ValueListenableBuilder`）与动作分派都归宿主，于是这里对任务状态是一支纯函数，
/// 可以脱离 DI 直接测。
class DownloadBar extends StatelessWidget {
  const DownloadBar({
    super.key,
    required this.task,
    required this.onTap,
    this.unitLabel = '章',
    this.idleLabel,
  });

  /// 当前下载任务；`null` 表示尚未开始
  final DownloadTask? task;

  /// 点击回调，透传当前任务（未开始为 null）
  final void Function(DownloadTask? task) onTap;

  /// 进度单位（小说「章」/ 漫画「页」）
  final String unitLabel;

  /// 未开始下载时的引导文案；`null` 用内置默认（「下载全本」）
  final String? idleLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 局部变量：public final 字段不参与类型提升，取一份局部引用以便安全使用非空成员
    final task = this.task;

    final isActive = task != null && task.isActive;
    final isDone = task?.isFinished ?? false;
    final isPaused = task?.status == DownloadStatus.paused;
    final hasFailed = (task?.failed.isNotEmpty) ?? false;

    final String label;
    final IconData icon;
    if (task == null) {
      label = idleLabel ?? '下载全本（离线阅读，无网也能看）';
      icon = Ionicons.cloudDownloadOutline;
    } else if (isDone) {
      // 选集下载时别写成「全本」：用户只勾了几集，进度也按选中项计量
      label = task.isPartialSelection
          ? '已下载选集（${task.progressLabel} $unitLabel）'
          : '已下载全本（${task.progressLabel} $unitLabel）';
      icon = Ionicons.cloudDoneOutline;
    } else if (isActive) {
      label = '下载中 ${task.progressLabel} · 点击暂停';
      icon = Ionicons.cloudDownloadOutline;
    } else if (isPaused) {
      label = '已暂停 ${task.progressLabel} · 点击继续';
      icon = Ionicons.playOutline;
    } else if (hasFailed) {
      label = '部分失败 ${task.progressLabel} · 点击重试';
      icon = Ionicons.refreshOutline;
    } else {
      label = '继续下载 ${task.progressLabel}';
      icon = Ionicons.cloudDownloadOutline;
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 12,
      color: isDark ? AppColors.darkCard : AppColors.lightSurface,
      onTap: () => onTap(task),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isDone ? AppColors.primary : AppColors.accentBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          // 进行中的实时进度条
          if (task != null && !isDone) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 3,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
