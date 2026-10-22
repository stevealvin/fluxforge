import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 发现页的频道网格：双列海报卡片
///
/// 每张卡带两个徽章：**类型**（左上）与**来源**（右上）。
/// 来源角标是刻意的 —— 用户要能溯源「这条是谁提供的」，但不必为此做选择
/// （选源是搜索页与规则市场的事，发现页不设导航主轴）。
class DiscoverGrid extends StatelessWidget {
  const DiscoverGrid({
    super.key,
    required this.isDark,
    required this.items,
    required this.onItemTap,
  });

  final bool isDark;
  final List<DiscoverItem> items;
  final ValueChanged<DiscoverItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
          child: Text(
            '该频道暂无内容',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        // 封面 16:10 + 标题 + 来源两行文字 ≈ 135 高，宽约 168
        childAspectRatio: 1.25,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildCard(items[index]),
    );
  }

  Widget _buildCard(DiscoverItem item) {
    final badge = item.badge ?? '';

    return GestureDetector(
      onTap: () => onItemTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppImage(
                    imageUrl: item.cover,
                    // 与详情页 / 旧发现页同口径：Referer 取规则 baseUrl，并固定移动端 UA
                    headers: {
                      'referer': item.source.baseUrl,
                      'user-agent':
                          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
                    },
                  ),
                ),

                // 左上：类型徽章
                Positioned(
                  left: 6,
                  top: 6,
                  child: _badge(item.kind.label, backgroundAlpha: 0.5),
                ),

                // 右上：来源角标
                Positioned(
                  right: 6,
                  top: 6,
                  child: _badge(item.source.name, backgroundAlpha: 0.42),
                ),

                // 底部：清晰度 / 集数角标
                if (badge.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _badge(badge, backgroundAlpha: 0.72),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.desc.isEmpty ? item.source.name : item.desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, {required double backgroundAlpha}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
