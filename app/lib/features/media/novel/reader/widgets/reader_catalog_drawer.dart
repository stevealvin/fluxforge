import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 章节目录抽屉（左侧面板）
///
/// 纯展示组件：章节数据、下载状态、当前章等由宿主传入，
/// 选择章节 / 单章下载 / 切换排序 / 关闭等行为通过回调上抛 ——
/// 因此该组件不依赖任何仓储或页面状态，可独立进行 Widget 测试。
///
/// 状态图标语义（统一以沙盒离线下载为唯一状态源）：
/// - 下载中：转圈指示器；
/// - 已下载：云朵对勾（断网可读）；
/// - 未下载：云端下载入口（点击触发单章离线下载）。
class ReaderCatalogDrawer extends StatelessWidget {
  const ReaderCatalogDrawer({
    super.key,
    required this.bookTitle,
    required this.chapters,
    required this.readerTheme,
    required this.currentChapterIndex,
    required this.isReversed,
    required this.downloadedCount,
    required this.scrollController,
    required this.itemHeight,
    required this.isChapterDownloaded,
    required this.isChapterDownloading,
    required this.onToggleOrder,
    required this.onSelectChapter,
    required this.onDownloadChapter,
    required this.onClose,
  });

  /// 书名
  final String bookTitle;

  /// 章节列表
  final List<NovelChapter> chapters;

  /// 当前护眼配色
  final ReaderTheme readerTheme;

  /// 当前正在阅读的章节索引
  final int currentChapterIndex;

  /// 是否倒序（倒序 = 最新章节在前）
  final bool isReversed;

  /// 已下载章节数量（沙盒口径，用于顶部信息栏展示）
  final int downloadedCount;

  /// 列表滚动控制器（由宿主持有并负责定位）
  final ScrollController? scrollController;

  /// 固定行高（固定行高才能用 initialScrollOffset 精确跳转到指定章节）
  final double itemHeight;

  /// 单章是否已离线下载
  final bool Function(int index) isChapterDownloaded;

  /// 单章是否正在下载
  final bool Function(int index) isChapterDownloading;

  final VoidCallback onToggleOrder;
  final void Function(int index) onSelectChapter;
  final void Function(int index) onDownloadChapter;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.76,
      backgroundColor: readerTheme.bg,
      child: SafeArea(
        child: Column(
          children: [
            // 顶部信息栏（书名 + 章节总数 + 下载进度 + 排序切换 + 关闭）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: readerTheme.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 ${chapters.length} 章 · 已下载 $downloadedCount 章',
                          style: TextStyle(fontSize: 11, color: readerTheme.subText),
                        ),
                      ],
                    ),
                  ),
                  // 排序切换：正序（第 1 章在前）/ 倒序（最新章节在前）
                  TextButton.icon(
                    onPressed: onToggleOrder,
                    icon: const Icon(Ionicons.swapVerticalOutline, size: 14),
                    label: Text(
                      isReversed ? '倒序' : '正序',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          isReversed ? AppColors.primary : readerTheme.subText,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Ionicons.closeOutline, color: readerTheme.subText, size: 20),
                    tooltip: '关闭目录',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: readerTheme.subText.withValues(alpha: 0.18)),

            // 章节列表（固定行高，便于用 initialScrollOffset 精确定位到当前章）
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemExtent: itemHeight,
                itemCount: chapters.length,
                // 倒序时按显示行号镜像映射回真实章节索引
                itemBuilder: (context, index) => _buildItem(
                  isReversed ? chapters.length - 1 - index : index,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 目录单项：章节名 + 下载状态图标（下载中 / 已下载 / 未下载可一键下载）
  Widget _buildItem(int index) {
    final isCurrent = index == currentChapterIndex;
    final isDownloading = isChapterDownloading(index);
    final isDownloaded = isChapterDownloaded(index);

    final Widget statusIcon;
    if (isDownloading) {
      statusIcon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      );
    } else if (isDownloaded) {
      // 已下载到沙盒：断网也可阅读
      statusIcon = const Icon(
        Ionicons.cloudDoneOutline,
        size: 17,
        color: AppColors.primary,
      );
    } else {
      // 未下载章节：提供单章离线下载入口（与全本下载共用同一份沙盒数据）
      statusIcon = InkWell(
        onTap: () => onDownloadChapter(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Ionicons.cloudDownloadOutline,
            size: 17,
            color: readerTheme.subText.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () {
        onClose();
        onSelectChapter(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: isCurrent ? AppColors.primary.withValues(alpha: 0.10) : null,
        child: Row(
          children: [
            // 当前章左侧高亮竖条
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                chapters[index].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? AppColors.primary : readerTheme.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            statusIcon,
          ],
        ),
      ),
    );
  }
}
