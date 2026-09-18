import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 章首 / 章末衔接页
///
/// 横向分页模式滑到本章边界时展示的过渡页，随后自动切换到上一章 / 下一章。
///
/// 关键体验约定：**正文已就绪时不再渲染转圈动画**（改用对勾图标），
/// 否则会出现「明明已缓存却仍在加载」的错觉。
class ReaderChapterBridge extends StatelessWidget {
  const ReaderChapterBridge({
    super.key,
    required this.chapterTitle,
    required this.readerTheme,
    required this.isReady,
    required this.heading,
    required this.readyHint,
    required this.loadingHint,
  });

  /// 目标章节标题
  final String chapterTitle;

  /// 当前护眼配色
  final ReaderTheme readerTheme;

  /// 目标章正文是否已就绪（命中内存缓存 / 已下载 / 预取中）
  final bool isReady;

  /// 主标题（如「正在进入下一章」）
  final String heading;

  /// 就绪 / 未就绪时的副文案
  final String readyHint;
  final String loadingHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          isReady
              ? const Icon(Ionicons.checkmarkCircle, size: 26, color: AppColors.primary)
              : const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
                ),
          const SizedBox(height: 18),
          Text(
            heading,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: readerTheme.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            chapterTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: readerTheme.subText),
          ),
          const SizedBox(height: 10),
          Text(
            isReady ? readyHint : loadingHint,
            style: TextStyle(fontSize: 11, color: readerTheme.subText),
          ),
        ],
      ),
    );
  }
}
