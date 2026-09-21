import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';
import 'package:fluxforge/features/library/history/history_center_page.dart';

/// 「继续观看 / 继续阅读」横向卡片流 (ContinueWatchingRow)
///
/// **纯展示**：消费记录由宿主订阅后经 [records] 传入 —— 组件不解析 DI、不订阅服务，
/// 于是它对记录数据是一支纯函数，可脱离服务直接测。
/// 呈现内容：把「上次看到哪一集、第几分钟」以可一键续播的横滑卡片形式列出。
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({super.key, required this.records});

  /// 跨媒体消费记录（由宿主订阅 `PlayHistoryService.recordsNotifier` 后传入）
  final List<PlayRecord> records;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recent = records.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题与「全部历史」快捷入口
        Row(
          children: [
            Container(
              width: 3.5,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '继续观看',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Text(
              '${records.length}',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
            const Spacer(),
            if (records.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.pushHistory(),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '全部历史',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        if (recent.isEmpty)
          _buildEmptyCard(context, isDark)
        else
          // 卡片内容实测高度：封面 74 + 文本区（上 7 + 标题 12px + 间距 3 + 进度 10.5px + 下 8）≈ 126
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _buildRecordCard(context, recent[index], isDark),
            ),
          ),
      ],
    );
  }

  /// 单张继续观看卡片（封面 + 叠加进度条 + 标题 + 进度文案）
  Widget _buildRecordCard(
    BuildContext context,
    PlayRecord record,
    bool isDark,
  ) {
    return SizedBox(
      width: 128,
      child: AppCard(
        padding: EdgeInsets.zero,
        borderRadius: 14,
        onTap: () => openPlayRecord(context, record),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面与叠加进度条
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Stack(
                children: [
                  SizedBox(
                    width: 128,
                    height: 74,
                    child: AppImage(imageUrl: record.cover, fit: BoxFit.cover),
                  ),
                  // 底部渐变遮罩，保证进度条与角标在任何封面上都清晰可见
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 进度条
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: record.progress,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  // 类型角标
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        MediaDisplay.typeLabel(record.mediaType),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    record.progressLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }

  /// 空态引导卡片
  Widget _buildEmptyCard(BuildContext context, bool isDark) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      borderRadius: 14,
      color: isDark ? AppColors.darkCard : AppColors.lightCard,
      onTap: () => context.pushSearch(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Ionicons.playCircleOutline,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '还没有观看记录',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '搜索或发现心仪内容，播放后将自动记录进度',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 13,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }
}
