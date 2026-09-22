import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 阅读器顶部控制栏（返回 / 书名 / 刷新章节 / 章节目录）
///
/// 顶部采用纵向渐变遮罩，与正文过渡自然、不生硬切断。纯展示组件，行为通过回调上抛。
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.bookTitle,
    required this.readerTheme,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenCatalog,
  });

  final String bookTitle;
  final ReaderTheme readerTheme;
  final VoidCallback onBack;

  /// 强制重新抓取当前章正文
  final VoidCallback onRefresh;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              readerTheme.bg,
              readerTheme.bg.withValues(alpha: 0.92),
              readerTheme.bg.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.72, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: readerTheme.text,
                size: 20,
              ),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: readerTheme.text,
                ),
              ),
            ),

            // 重新刷新加载当前章
            IconButton(
              icon: Icon(
                Ionicons.refreshOutline,
                color: readerTheme.text,
                size: 18,
              ),
              tooltip: '刷新章节',
              onPressed: onRefresh,
            ),

            // 章节目录抽屉
            IconButton(
              icon: Icon(
                Ionicons.reorderFourOutline,
                color: readerTheme.text,
                size: 20,
              ),
              tooltip: '章节目录',
              onPressed: onOpenCatalog,
            ),
          ],
        ),
      ),
    );
  }
}
