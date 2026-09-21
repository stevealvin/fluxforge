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
                Icon(
                  Ionicons.bookOutline,
                  size: 42,
                  color: readerTheme.subText,
                ),
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
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: readerTheme.subText,
                  ),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 0.8,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
