import 'package:material_ui/material_ui.dart';
import 'net_image.dart';

class MediaList extends StatelessWidget {
  const MediaList({
    super.key,
    required this.itemCount,
    this.shrinkWrap = false,
    required this.itemBuilder,
  });

  final int itemCount;
  final bool shrinkWrap;
  final MediaListItem? Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      itemCount: itemCount,
      itemBuilder: itemBuilder
    );
  }
}

class MediaListItem extends StatelessWidget {
  const MediaListItem({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subChild,
  });

  final String imageUrl;
  final String title;
  final Widget subChild;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        child: Ink(
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: NetImage(imageUrl: imageUrl),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(title), subChild],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
