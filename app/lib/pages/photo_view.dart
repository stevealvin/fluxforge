import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';

class PhotoView extends StatefulWidget {
  const PhotoView({
    super.key,
    required this.imgs,
    this.currentIndex = 0,
  });

  final List imgs;
  final int currentIndex;

  @override
  State<PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<PhotoView> {

  int currentIndex = 0;

  @override
  initState() {
    super.initState();
    setState(() {
      currentIndex = widget.currentIndex;
    });
  }

  List get list => widget.imgs;

  Widget _buildImages() {
    return ExtendedImageGesturePageView.builder(
      itemBuilder: (BuildContext context, int index) {
        var item = list[index];
        Widget image = ExtendedImage.network(
          item,
          fit: BoxFit.contain,
          initGestureConfigHandler: (state) {
            return GestureConfig(
              inPageView: true,
              initialScale: 1.0,
              minScale: 1.0
            );
          },
          mode: ExtendedImageMode.gesture,
        );
        image = Container(
          // padding: EdgeInsets.all(5.0),
          child: image,
        );
        if (index == currentIndex) {
          return Hero(
            tag: item + index.toString(),
            child: image,
          );
        } else {
          return image;
        }
      },
      itemCount: list.length,
      onPageChanged: (int index) {
        setState(() {
          currentIndex = index;
        });
      },
      controller: ExtendedPageController(
        initialPage: currentIndex,
      ),
      scrollDirection: Axis.vertical,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            _buildImages(),
            BackButton(color: Colors.white,)
          ],
        ),
      ),
    );
  }
}