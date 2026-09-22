import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 章首 / 章末衔接页（横向滑窗内「尚未分片」的章在此占位）
///
/// 横向模式**不再用全屏加载 / 错误视图顶掉 `PageView`**：跨章未就绪一律由本页
/// 在原地表达，正文就绪后由上层补切片原地顶替。整屏替换会销毁 `PageView`、
/// 丢失翻页动画与控制器位置，表现为「翻到下一章直接跳过去」。
///
/// 三种形态：
/// - **加载中**：转圈 + [loadingHint]；
/// - **已就绪**（正文在内存 / 沙盒，只差分片）：对勾 + [readyHint] ——
///   避免「明明已缓存却仍在加载」的错觉；
/// - **失败**：[errorMessage] 非空时展示失败说明与 [onRetry] 重试入口，
///   否则该章会永远转圈。
class ReaderChapterBridge extends StatelessWidget {
  const ReaderChapterBridge({
    super.key,
    required this.chapterTitle,
    required this.readerTheme,
    required this.isReady,
    required this.heading,
    required this.readyHint,
    required this.loadingHint,
    this.errorMessage,
    this.onRetry,
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

  /// 加载失败原因；非空时进入失败形态（展示重试入口）
  final String? errorMessage;

  /// 失败形态下的重试回调
  final VoidCallback? onRetry;

  bool get _hasError => errorMessage != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_hasError)
            Icon(
              Ionicons.alertCircleOutline,
              size: 26,
              color: readerTheme.subText,
            )
          else if (isReady)
            const Icon(
              Ionicons.checkmarkCircle,
              size: 26,
              color: AppColors.primary,
            )
          else
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primary,
              ),
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
            _hasError ? errorMessage! : (isReady ? readyHint : loadingHint),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: readerTheme.subText),
          ),
          if (_hasError && onRetry != null) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onRetry,
              icon: const Icon(Ionicons.refreshOutline, size: 14),
              label: const Text('重新加载本章'),
            ),
          ],
        ],
      ),
    );
  }
}
