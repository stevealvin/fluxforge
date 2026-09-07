import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../common/rule_engine.dart';
import '../../model/rule.dart';

class RuleDiscoveryPage extends StatefulWidget {
  const RuleDiscoveryPage({
    super.key,
    required this.rule,
  });

  final Rule rule;

  @override
  State<RuleDiscoveryPage> createState() => _RuleDiscoveryPageState();
}

class _RuleDiscoveryPageState extends State<RuleDiscoveryPage> {
  List _list = [];
  bool _loading = false;

  Future<void> load() async {
    setState(() {
      _loading = true;
    });
    try {
      var result = await RuleEngine.discovery(widget.rule);
      if (result is List) {
        setState(() {
          _list = result;
        });
      }
    } catch (e) {
      debugPrint('RuleDiscovery load error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Widget _buildListItem(List items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (BuildContext context, int index) {
        var item = items[index];
        return Card(
          clipBehavior: Clip.hardEdge,
          elevation: 0,
          child: InkWell(
            onTap: () {
              context.push('/rule_detail', extra: {
                'href': item['href'],
                'title': item['title'],
                'cover': item['cover'],
                'rule': widget.rule,
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: CachedNetworkImage(
                      imageUrl: item['cover'],
                      fit: BoxFit.cover,
                      httpHeaders: {
                        'referer': widget.rule.baseUrl,
                        'user-agent':
                            'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsGeometry.all(4),
                  child: Text(
                    item['title'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.rule.name)),
      body: Container(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _list.length,
                itemBuilder: (BuildContext context, int index) {
                  var item = _list[index];
                  return Column(
                    children: [
                      ListTile(
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.only(left: 12, right: 0),
                        title: Text(item['title'], style: TextStyle(fontSize: 17)),
                        trailing: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed: () {
                            // 点击事件
                          },
                        ),
                      ),
                      _buildListItem(item['items']),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
