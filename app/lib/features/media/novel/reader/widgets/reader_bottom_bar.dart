import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 阅读器底部控制面板
///
/// 结构：章内进度条（含上一章 / 下一章）+ 进度文案 + 四个功能按钮
/// （目录 / 缓存预取 / 翻页模式 / 排版设置）。
/// 底部同样使用纵向渐变遮罩，避免生硬切断正文。纯展示组件，行为通过回调上抛。
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.readerTheme,
    required this.progress,
    required this.progressLabel,
    required this.canGoPrev,
    required this.canGoNext,
    required this.downloadedChapterCount,
    required this.isHorizontalMode,
    required this.pageModeLabel,
    required this.onSeek,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onOpenCatalog,
    required this.onDownloadNext,
    required this.onTogglePageMode,
    required this.onToggleSettingsPanel,
  });

  final ReaderTheme readerTheme;

  /// 章内阅读进度（0.0 ~ 1.0）
  final double progress;

  /// 进度文案（横向：页码 / 纵向：百分比）
  final String progressLabel;

  final bool canGoPrev;
  final bool canGoNext;

  /// 当前已离线下载到沙盒的章节数
  ///
  /// 与目录抽屉顶部、下载管理页共用**同一口径**（沙盒落盘），
  /// 不再使用「会话级内存缓存」那套只在本次阅读内成立的临时计数 ——
  /// 用户视角里「缓存」就是「离线下载」，本来就是同一件事。
  final int downloadedChapterCount;

  /// 是否处于横向翻页模式（决定翻页模式按钮的图标）
  final bool isHorizontalMode;

  /// 翻页模式文案
  final String pageModeLabel;

  /// 拖动进度条 → 章内定位
  final ValueChanged<double> onSeek;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onOpenCatalog;

  /// 下载下一章到离线沙盒（不具备离线条件时降级为会话内预取）
  final VoidCallback onDownloadNext;

  final VoidCallback onTogglePageMode;
  final VoidCallback onToggleSettingsPanel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              readerTheme.bg,
              readerTheme.bg.withValues(alpha: 0.94),
              readerTheme.bg.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.74, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度控制行
            Row(
              children: [
                IconButton(
                  icon: Icon(Ionicons.chevronBackOutline, color: readerTheme.text),
                  onPressed: canGoPrev ? onPrevChapter : null,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: readerTheme.subText.withValues(alpha: 0.3),
                      thumbColor: AppColors.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    // 进度条语义为「当前章节内的阅读进度」（横向=页码比例，纵向=滚动比例）
                    child: Slider(
                      value: progress,
                      onChanged: onSeek,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Ionicons.chevronForwardOutline, color: readerTheme.text),
                  onPressed: canGoNext ? onNextChapter : null,
                ),
              ],
            ),

            // 章内进度文案
            Center(
              child: Text(
                progressLabel,
                style: TextStyle(fontSize: 11, color: readerTheme.subText),
              ),
            ),

            const SizedBox(height: 4),

            // 功能操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ReaderBarActionButton(
                  icon: Ionicons.bookOutline,
                  label: '目录',
                  color: readerTheme.text,
                  onTap: onOpenCatalog,
                ),
                // 离线下载状态 + 下载下一章（复制整章入口已统一收敛至顶栏，避免重复）
                ReaderBarActionButton(
                  icon: Ionicons.downloadOutline,
                  label: '已下载 $downloadedChapterCount 章',
                  color: readerTheme.text,
                  onTap: onDownloadNext,
                ),
                ReaderBarActionButton(
                  icon: isHorizontalMode
                      ? Ionicons.tabletPortraitOutline
                      : Ionicons.menuOutline,
                  label: pageModeLabel,
                  color: readerTheme.text,
                  onTap: onTogglePageMode,
                ),
                ReaderBarActionButton(
                  icon: Ionicons.optionsOutline,
                  label: '排版',
                  color: readerTheme.text,
                  onTap: onToggleSettingsPanel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部控制栏功能按钮（图标 + 文案的纵向组合，统一交互与视觉）
class ReaderBarActionButton extends StatelessWidget {
  const ReaderBarActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
