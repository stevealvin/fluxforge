import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 发现页顶部的沉浸式轮播（全出血）
///
/// ### 它是什么
/// 一屏一张大图，横向滑动切换。展示的是**各源推荐位的代表内容**（每源一条），
/// 而不是「精选榜」—— 规则契约里没有热度 / 评分 / 时间戳，任何 Top N 都是假的。
/// 卡片上标注来源名，让用户看到「这是哪个站的内容」但不必为此做选择。
///
/// ### 为什么要顶部暗色渐变
/// 轮播是全出血的，AppBar 透明叠在它上面，状态栏图标也是浅色。
/// 浅色封面会让浅色状态栏文字彻底看不清，因此顶部压一层暗色渐变 ——
/// 这是流媒体 App 的通行做法（Apple Music / Netflix 均如此）。
class DiscoverHeroCarousel extends StatefulWidget {
  const DiscoverHeroCarousel({
    super.key,
    required this.isDark,
    required this.items,
    required this.onItemTap,
    this.height = 268,
  });

  final bool isDark;

  /// 轮播池：每个源贡献一条
  final List<DiscoverItem> items;

  final ValueChanged<DiscoverItem> onItemTap;

  /// 轮播区高度
  final double height;

  @override
  State<DiscoverHeroCarousel> createState() => _DiscoverHeroCarouselState();
}

class _DiscoverHeroCarouselState extends State<DiscoverHeroCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return SizedBox(height: widget.height);
    }

    // 轮播池随聚合结果增长而变长；越界时由 PageView 自身处理，无需额外兜底
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              if (mounted) setState(() => _index = i);
            },
            itemBuilder: (context, index) =>
                _buildPage(context, widget.items[index]),
          ),

          // 顶部暗色渐变：保证透明 AppBar 上的浅色图标与状态栏文字可读
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 116,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),

          // 指示器：选中项拉长成短条（比圆点更易读当前位置）
          Positioned(
            right: 14,
            bottom: 12,
            child: _buildIndicator(),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(left: 4),
            width: i == _index ? 14 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == _index
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  Widget _buildPage(BuildContext context, DiscoverItem item) {
    final badge = item.badge ?? '';

    return GestureDetector(
      onTap: () => widget.onItemTap(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(
            imageUrl: item.cover,
            // 与详情页 / 旧发现页同口径：Referer 取规则 baseUrl，并固定移动端 UA
            headers: {
              'referer': item.source.baseUrl,
              'user-agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
            },
          ),

          // 底部渐变：托住标题与按钮
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 148,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 文字与动作
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (badge.isNotEmpty) badge,
                    item.source.name,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildPrimaryAction(),
                    const SizedBox(width: 9),
                    _buildGhostAction(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Text(
        '立即观看',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildGhostAction() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
      ),
      child: const Text(
        '加入追更',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
