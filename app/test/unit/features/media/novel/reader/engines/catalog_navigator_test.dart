import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/novel/reader/engines/catalog_navigator.dart';

/// 目录导航计算单元测试
///
/// 重点覆盖「倒序镜像映射」与「停靠偏移在首章 / 末章时的边界」——
/// 这两处出错会表现为「切换排序后目录停在错误位置」。
void main() {
  group('displayIndex 显示行号映射', () {
    test('正序时显示行号即真实章节序号', () {
      expect(
        CatalogNavigator.displayIndex(
          chapterIndex: 3,
          chapterCount: 10,
          reversed: false,
        ),
        3,
      );
    });

    test('倒序时镜像翻转（末章显示在第 0 行）', () {
      expect(
        CatalogNavigator.displayIndex(
          chapterIndex: 9,
          chapterCount: 10,
          reversed: true,
        ),
        0,
      );
      expect(
        CatalogNavigator.displayIndex(
          chapterIndex: 0,
          chapterCount: 10,
          reversed: true,
        ),
        9,
      );
    });
  });

  group('offsetFor 停靠滚动偏移', () {
    test('首章被 clamp 到顶部，留白不为负', () {
      expect(CatalogNavigator.offsetFor(displayIndex: 0, chapterCount: 10), 0);
    });

    test('第 5 行停靠时上方保留 2 行上下文', () {
      // (5 - 2) * 56
      expect(
        CatalogNavigator.offsetFor(displayIndex: 5, chapterCount: 10),
        168,
      );
    });

    test('末章偏移即「行号 - 上下文行数」', () {
      // (9 - 2) * 56
      expect(
        CatalogNavigator.offsetFor(displayIndex: 9, chapterCount: 10),
        392,
      );
    });

    test('行号超过章节数时偏移被 clamp 到 chapterCount 行', () {
      // (20 - 2) 会被 clamp 到 chapterCount = 10
      expect(
        CatalogNavigator.offsetFor(displayIndex: 20, chapterCount: 10),
        10 * CatalogNavigator.itemHeight,
      );
    });

    test('行号为负（无章节时的兜底）也被 clamp', () {
      expect(CatalogNavigator.offsetFor(displayIndex: -1, chapterCount: 0), 0);
    });

    test('固定行高为 56，保证 initialScrollOffset 可精确跳转', () {
      expect(CatalogNavigator.itemHeight, 56.0);
      expect(CatalogNavigator.contextRows, 2);
    });
  });
}
