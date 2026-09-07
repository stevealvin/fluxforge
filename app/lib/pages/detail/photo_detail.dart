import 'package:animations/animations.dart';
import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import '../photo_view.dart';

import '../../common/rule_engine.dart';

class PhotoDetail extends StatefulWidget {
  const PhotoDetail({super.key, required this.href});

  final String href;

  @override
  State<PhotoDetail> createState() => _PhotoDetailState();
}

class _PhotoDetailState extends State<PhotoDetail> {
  bool loading = false;
  List list = [];

  String getCode(String url) {
    return r'''
    const getData = async (url) => {
    try {
      let { data } = await axios.get(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
        }
      })
      let $ = cheerio.load(data)
      let list = $('.content img').map((i, el) => {
        return $(el).attr('src')
      }).toArray()
      return list
    } catch (error) {
    }
  }
  const getDetail = async (url) => {
    try {
      let { data } = await axios.get(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
        }
      })
      let $ = cheerio.load(data)
      let list = $('.page a').map((i, el) => {
        return 'https://meirentu.cc' + $(el).attr('href')
      }).toArray()
      list.pop()
      let result = []
      for (const item of list) {
        let arr = await getData(item)
        result = result.concat(arr)
      }
      return result
    } catch (error) {
    }
  }
    return getDetail("$url")
  ''';
  }

  Future<void> load() async {
    var url = widget.href;
    setState(() {
      loading = true;
    });
    try {
      var result = await RuleEngine.execute(getCode(url));
      setState(() {
        list = result;
      });
    } catch (e) {
      debugPrint('PhotoDetail load error: $e');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('详细内容')),
      body: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3))
          : _buildImgs(),
    );
  }

  Widget _buildImgs() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.67,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        return OpenContainer<bool>(
          openBuilder: (BuildContext context, VoidCallback _) {
            return PhotoView(imgs: list, currentIndex: index);
          },
          closedBuilder: (context, action) {
            return ExtendedImage.network(
              item,
              cache: true,
              fit: BoxFit.cover,
              headers: const {'Referer': 'https://meirentu.cc/'},
            );
          },
        );
      },
    );
  }
}
