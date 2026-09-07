import 'package:material_ui/material_ui.dart';

import 'movie_detail.dart';
import 'photo_detail.dart';

class DetailPage extends StatelessWidget {

  final String type;
  const DetailPage({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;

    switch (type) {
      case 'video':
      case 'tv':
        content = MovieDetail();
        break;
      case 'image':
        content = PhotoDetail(href: 'item');
        break;
      default:
        content = _buildDefault();
    }

    return content;
  }

  Widget _buildDefault() {
    return Container();
  }
}
