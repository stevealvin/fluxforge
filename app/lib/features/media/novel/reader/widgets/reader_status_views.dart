import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 无章节空态（严禁再注入示例假章节，避免用户误认为真实正文）
class ReaderEmptyScaffold extends StatelessWidget {
  const ReaderEmptyScaffold({super.key, required this.readerTheme});

  final ReaderTheme readerTheme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: readerTheme.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Ionicons.bookOutline, size: 42, color: readerTheme.subText),
                const SizedBox(height: 16),
                Text(
                  '暂无章节内容',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: readerTheme.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '该作品尚未解析出章节目录，请返回详情页刷新后重试',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: readerTheme.subText),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Ionicons.arrowBackOutline, size: 15),
                  label: const Text('返回详情页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 正文加载中（本章尚无可用内容时的全屏等待态）
class ReaderLoadingView extends StatelessWidget {
  const ReaderLoadingView({super.key, required this.readerTheme});

  final ReaderTheme readerTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            '正在抓取并排版章节正文...',
            style: TextStyle(fontSize: 13, color: readerTheme.subText),
          ),
        ],
      ),
    );
  }
}

/// 正文抓取失败（含「重试加载」入口）
///
/// 该状态下上层必须撤除三区点击热层：热层为全屏 `Positioned.fill`，
/// 会遮挡此处的「重试加载」按钮，导致点击被抢走而误解为呼出菜单。
class ReaderErrorView extends StatelessWidget {
  const ReaderErrorView({
    super.key,
    required this.readerTheme,
    required this.message,
    required this.onRetry,
  });

  final ReaderTheme readerTheme;

  /// 失败原因（引擎 / 解析规则返回的错误说明）
  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Ionicons.alertCircleOutline, size: 36, color: readerTheme.subText),
            const SizedBox(height: 12),
            Text(
              '章节正文抓取失败',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: readerTheme.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: readerTheme.subText),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onRetry,
              icon: const Icon(Ionicons.refreshOutline, size: 14),
              label: const Text('重试加载'),
            ),
          ],
        ),
      ),
    );
  }
}
