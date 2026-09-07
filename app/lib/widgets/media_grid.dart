import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';

class MediaGrid extends StatelessWidget {
  // 布局控制
  final int itemCount;
  final int crossAxisCount;
  final double spacing;
  final MediaGridItem? Function(BuildContext, int) itemBuilder;

  const MediaGrid({
    required this.itemCount,
    super.key,
    this.crossAxisCount = 2,
    this.spacing = 8,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth =
        (screenWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;

    const textHeight = 36.0; // 两行文字高度
    final imageHeight = itemWidth * 3 / 2;
    final ratio = itemWidth / (imageHeight + textHeight);

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: ratio,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

class MediaGridItem extends StatelessWidget {
  final String imageUrl;
  final String title;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final BorderRadius? borderRadius;
  final void Function()? onTap;

  const MediaGridItem({
    super.key,
    required this.imageUrl,
    required this.title,
    this.onTap,
    this.headers,
    this.fit,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap?.call(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          ExtendedImage.network(
            imageUrl,
            headers: headers,
            fit: BoxFit.cover,
            borderRadius: borderRadius,
          ),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
