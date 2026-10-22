import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';
import 'package:fluxforge/features/discover/widgets/discover_channel_bar.dart';
import 'package:fluxforge/features/discover/widgets/discover_grid.dart';

/// 发现页的频道段与频道网格
///
/// 守两条契约：
/// 1. **频道段是类型导航**（不再是「列出所有规则源逐个切换」）；
/// 2. **空频道置灰** —— 点了只会得到空结果，不如直接不可点。
void main() {
  Rule rule(String name) => Rule(
    name: name,
    baseUrl: 'https://x.example',
    type: 'video',
    code: '',
  );

  DiscoverItem item(String title, Rule source) => DiscoverItem(
    title: title,
    url: 'https://x.com/1',
    cover: '',
    desc: '',
    badge: '',
    source: source,
    kind: MediaKind.video,
  );

  group('DiscoverChannelBar', () {
    testWidgets('展示全部媒体类型并回抛切换', (tester) async {
      MediaKind? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DiscoverChannelBar(
              isDark: false,
              selected: MediaKind.all,
              onSelected: (k) => picked = k,
              counts: const {
                MediaKind.all: 10,
                MediaKind.video: 6,
                MediaKind.novel: 3,
                MediaKind.comic: 1,
              },
            ),
          ),
        ),
      );

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('影视'), findsOneWidget);
      expect(find.text('小说'), findsOneWidget);
      expect(find.text('漫画·图集'), findsOneWidget);

      await tester.tap(find.text('影视'));
      await tester.pump();
      expect(picked, MediaKind.video);
    });

    testWidgets('零条目的频道置灰且不可点', (tester) async {
      MediaKind? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DiscoverChannelBar(
              isDark: false,
              selected: MediaKind.all,
              onSelected: (k) => picked = k,
              counts: const {
                MediaKind.all: 10,
                MediaKind.video: 6,
                MediaKind.novel: 0,
                MediaKind.comic: 0,
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('小说'));
      await tester.pump();
      expect(picked, isNull, reason: '没有条目的频道不该可点');
    });
  });

  group('DiscoverGrid', () {
    testWidgets('渲染条目并回抛点击', (tester) async {
      DiscoverItem? tapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DiscoverGrid(
              isDark: false,
              items: [item('星海拾遗', rule('极光影视'))],
              onItemTap: (i) => tapped = i,
            ),
          ),
        ),
      );

      expect(find.text('星海拾遗'), findsOneWidget);

      await tester.tap(find.text('星海拾遗'));
      await tester.pump();
      expect(tapped?.title, '星海拾遗');
    });

    testWidgets('空列表给出提示而不是白屏', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DiscoverGrid(
              isDark: false,
              items: const [],
              onItemTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('该频道暂无内容'), findsOneWidget);
    });
  });
}
