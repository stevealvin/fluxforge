import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';
import 'package:fluxforge/domain/media/media.dart';

/// 跨媒体通用详情头部元数据组件 (海报/标题/标签/作者/简介)
///
/// 版面取舍（小说与漫画共用同一份）：
///
/// 1. **标签紧跟标题**：题材标签是"这是什么作品"，与标题同属身份信息，
///    贴在标题下面扫读最顺；评分与规则来源则**移到封面上**做角标
///    （左上评分 / 左下规则来源）—— 它们本来各占半行文字区，而封面右侧
///    的 144 高度里通常还空着，角标不占任何文字行高。
/// 2. 封面左下角的规则来源用**品牌主题色实底 + 白字**：底图深浅不可控，
///    半透明底色在浅封面上会糊成一片，实底才保证任何封面上都读得清。
/// 3. **主操作位 [bottomAction]** 落在右列底部：封面 104×144，右列文字往往
///    填不满这 144，底部本就空着 —— 「继续阅读」放这儿既不新增行高，
///    也离标题最近（比在下面单开一整行大按钮省一屏）。
/// 4. 简介**不做卡片**：页面里已经有章节 / 画卷 / 相关推荐若干分组，
///    简介再包一层卡片只多一道边界，不增层次；改成与其它小节同构的
///    「主题色竖条 + 小标题 + 展开/收起」直接平铺。
class MediaMetaHeader extends StatefulWidget {
  const MediaMetaHeader({
    super.key,
    required this.data,
    this.rule,
    this.fallbackTitle = '',
    this.fallbackCover = '',
    this.showCover = true,
    this.onShareTap,
    this.bottomAction,
  });

  /// 结构化媒体详情数据
  final MediaDetailData data;

  /// 所属执行规则
  final Rule? rule;

  /// 兜底标题 (沙箱异步解析前由上一级页面传入)
  final String fallbackTitle;

  /// 兜底封面海报
  final String fallbackCover;

  /// 是否展示左侧海报封面 (视频详情页已有顶部大播放器，可设为 false 隐藏)
  final bool showCover;

  /// 分享回调
  final VoidCallback? onShareTap;

  /// 右列底部的操作位（如「继续阅读」）；为空则不占位
  final Widget? bottomAction;

  @override
  State<MediaMetaHeader> createState() => _MediaMetaHeaderState();
}

class _MediaMetaHeaderState extends State<MediaMetaHeader> {
  /// 封面尺寸：右列的 [bottomAction] 以它为准对齐底部
  static const double _coverWidth = 104;
  static const double _coverHeight = 144;

  bool _isDescExpanded = false;

  String get _displayTitle {
    if (widget.data.title.isNotEmpty) return widget.data.title;
    return widget.fallbackTitle.isNotEmpty ? widget.fallbackTitle : '未知作品';
  }

  String get _displayCover {
    if (widget.data.cover.isNotEmpty) return widget.data.cover;
    return widget.fallbackCover;
  }

  /// 评分 / 规则来源是否可贴到封面上（无封面时退回文字区）
  bool get _badgesOnCover =>
      _displayCover.isNotEmpty &&
      ((widget.data.rating?.isNotEmpty ?? false) || widget.rule != null);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetUrl = widget.data.url;
    final desc = widget.data.desc?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部海报与主元信息行
          if (widget.showCover)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCoverCard(isDark, targetUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: ConstrainedBox(
                    // 与封面等高：右列文字不足 144 时，底部的操作位才贴得住封面下沿
                    constraints: const BoxConstraints(minHeight: _coverHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetaColumn(isDark, badgesOnCover: _badgesOnCover),
                        if (widget.bottomAction != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: widget.bottomAction,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetaColumn(isDark, badgesOnCover: false),
                if (widget.bottomAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: widget.bottomAction,
                  ),
              ],
            ),

          // 作品简介（平铺，无卡片）
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildDescSection(isDark, desc),
          ],
        ],
      ),
    );
  }

  /// 构建左侧海报卡片（封面 + 两张角标）
  Widget _buildCoverCard(bool isDark, String targetUrl) {
    final rating = widget.data.rating?.trim() ?? '';
    final ruleName = widget.rule?.name.trim() ?? '';

    return Hero(
      tag: 'media_cover_${targetUrl.isNotEmpty ? targetUrl : _displayTitle}',
      child: SizedBox(
        width: _coverWidth,
        height: _coverHeight,
        child: Stack(
          children: [
            // 底图
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: _coverWidth,
                height: _coverHeight,
                color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                child: _displayCover.isNotEmpty
                    ? AppImage(
                        imageUrl: _displayCover,
                        headers: widget.data.customHeaders,
                        // 封面尺寸固定 104×144 → 按 3x 屏降采样，避免按原图解码
                        cacheWidth: 312,
                        errorWidget: Icon(
                          Ionicons.imageOutline,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                          size: 28,
                        ),
                      )
                    : Center(
                        child: Icon(
                          Ionicons.filmOutline,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                          size: 32,
                        ),
                      ),
              ),
            ),

            // 左上角：评分（与封面左上圆弧呼应，故只做左上圆角）
            if (_badgesOnCover && rating.isNotEmpty)
              Positioned(
                left: 0,
                top: 0,
                child: _buildCoverBadge(
                  text: rating,
                  color: Colors.amber.shade700,
                  icon: Icons.star_rounded,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomRight: Radius.circular(8),
                  ),
                ),
              ),

            // 左下角：规则来源（品牌主题色半透明底 + 白字，不带图标）
            if (_badgesOnCover && ruleName.isNotEmpty)
              Positioned(
                left: 0,
                bottom: 0,
                child: _buildCoverBadge(
                  text: ruleName,
                  color: AppColors.primary.withValues(alpha: 0.75),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    topRight: Radius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 封面角标：白字 + 可带图标
  ///
  /// [icon] 为空时只显示文字（规则来源就不带图标 —— 它本来就只是一个名字，
  /// 配个图标既挤宽度又没有信息量）。底色由调用方决定透明度：
  /// 规则来源走 75% 主题色，压住底图的同时仍透出封面。
  Widget _buildCoverBadge({
    required String text,
    required Color color,
    required BorderRadius borderRadius,
    IconData? icon,
  }) {
    return Container(
      // 角标底图宽度不可控：限宽到封面宽度，长规则名截断而不是溢出
      constraints: const BoxConstraints(maxWidth: _coverWidth),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建右侧 (或全宽) 元数据列
  ///
  /// [badgesOnCover] 为 true 时，评分 / 规则来源已贴到封面上，此处不再占文字行。
  Widget _buildMetaColumn(bool isDark, {required bool badgesOnCover}) {
    final rating = widget.data.rating?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主标题 (高对比度深色模式主文本)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _displayTitle,
                style: TextStyle(
                  // 标题不再是唯一的大字：下面紧跟标签与元信息，收小一档更透气
                  fontSize: widget.showCover ? 16.5 : 18,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: widget.showCover ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onShareTap != null)
              IconButton(
                icon: Icon(
                  Ionicons.shareSocialOutline,
                  size: 18,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
                onPressed: widget.onShareTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        const SizedBox(height: 7),

        // 题材标签 Chips：与标题同属身份信息，紧跟标题扫读最顺
        if (widget.data.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.data.tags.take(widget.showCover ? 4 : 8).map((
              tag,
            ) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 7),
        ],

        // 无封面（文字区无处借位）时，评分 / 规则来源退回这一行
        if (!badgesOnCover && (rating.isNotEmpty || widget.rule != null)) ...[
          Row(
            children: [
              if (rating.isNotEmpty) ...[
                _buildInlineBadge(
                  icon: Icons.star_rounded,
                  text: rating,
                  color: Colors.amber,
                  background: Colors.amber.withValues(
                    alpha: isDark ? 0.2 : 0.12,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.rule != null)
                Flexible(
                  child: _buildInlineBadge(
                    text: widget.rule!.name,
                    color: AppColors.primary,
                    background: AppColors.primary.withValues(
                      alpha: isDark ? 0.2 : 0.12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
        ],

        // 作者 / 主演信息
        if (widget.data.author != null && widget.data.author!.isNotEmpty) ...[
          Text(
            '作者/主演: ${widget.data.author}',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // 更新时间
        if (widget.data.updateTime != null &&
            widget.data.updateTime!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '更新: ${widget.data.updateTime}',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// 文字区里的内联徽标（无封面时用）
  Widget _buildInlineBadge({
    required String text,
    required Color color,
    required Color background,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 作品简介（**平铺，无卡片**）
  ///
  /// 与页面其它小节同构：主题色竖条 + 小标题 + 展开/收起，正文直接铺在页面上。
  /// 整段可点（移动端热区），不必精准点中「展开」两个字。
  Widget _buildDescSection(bool isDark, String desc) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _isDescExpanded = !_isDescExpanded;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                '作品简介',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _isDescExpanded ? '收起' : '展开',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                _isDescExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            maxLines: _isDescExpanded ? 100 : 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
