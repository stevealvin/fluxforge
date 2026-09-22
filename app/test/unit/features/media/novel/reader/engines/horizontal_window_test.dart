import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/features/media/novel/reader/engines/horizontal_window.dart';

/// 横向滑窗换算引擎单元测试
///
/// 这套规则原先埋在页面与视图里各写一遍（`_windowPageCountOf` / `_pageCountOf` /
/// itemBuilder 内联倒推），且必须逐位一致 —— 任一处口径漂移都不会报错，
/// 只会让翻页落点与底部页码静默错位。此处把不变量固定下来。
///
/// 每章的取值是**页起始偏移表**（见 `PaginationEngine.sliceIntoPageStarts`）：
/// 本引擎只用到它的长度（页数）与是否为空，故用例里的偏移数值本身无意义。
void main() {
  group('HorizontalWindow 页数统计', () {
    test('未分片章恒占 1 页（加载占位页）', () {
      expect(HorizontalWindow.pageCountOf(null), equals(1));
      expect(HorizontalWindow.pageCountOf(const []), equals(1));
      expect(HorizontalWindow.pageCountOf(const [0]), equals(1));
      expect(HorizontalWindow.pageCountOf(const [0, 100, 200]), equals(3));
    });

    test('映射中缺章一律按未分片处理', () {
      final pageStarts = <int, List<int>>{
        0: const [0, 100],
      };
      expect(HorizontalWindow.pageCountIn(pageStarts, 0), equals(2));
      expect(HorizontalWindow.pageCountIn(pageStarts, 9), equals(1));
    });

    test('总页数为各章页数（含占位页）之和，空窗口为 0', () {
      final pageStarts = <int, List<int>>{
        4: const [0, 100, 200],
        6: const [0],
        // 5 未分片 → 占 1 页
      };
      expect(
        HorizontalWindow.totalPages(const [4, 5, 6], pageStarts),
        equals(5),
      );
      expect(HorizontalWindow.totalPages(const [], pageStarts), equals(0));
    });
  });

  group('HorizontalWindow 扁平索引换算', () {
    final pageStarts = <int, List<int>>{
      4: const [0, 100, 200], // 3 页
      // 5 未分片 → 1 页（占位页）
      6: const [0, 100], // 2 页
    };
    const window = [4, 5, 6];

    test('按章顺序累加定位（占位章恰好占一个扁平位）', () {
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, 0),
        equals((4, 0)),
      );
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, 2),
        equals((4, 2)),
      );
      // 关键点：未分片章占 1 页，页面与视图必须都按这个口径编号
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, 3),
        equals((5, 0)),
      );
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, 4),
        equals((6, 0)),
      );
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, 5),
        equals((6, 1)),
      );
    });

    test('越界兜底为窗口最后一章第 0 页，负索引归首章', () {
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, 99),
        equals((6, 0)),
      );
      expect(
        HorizontalWindow.resolveFlat(window, pageStarts, -1),
        equals((4, 0)),
      );
    });

    test('反向换算：章不在窗口内时兜底 0', () {
      expect(HorizontalWindow.flatIndexOf(window, pageStarts, 4, 1), equals(1));
      expect(HorizontalWindow.flatIndexOf(window, pageStarts, 5, 0), equals(3));
      expect(HorizontalWindow.flatIndexOf(window, pageStarts, 6, 1), equals(5));
      expect(HorizontalWindow.flatIndexOf(window, pageStarts, 7, 0), equals(0));
    });

    test('往返一致：窗口内每个扁平索引都能原样还原', () {
      final total = HorizontalWindow.totalPages(window, pageStarts);
      expect(total, equals(6));

      for (var index = 0; index < total; index++) {
        final (chapter, pageInChapter) = HorizontalWindow.resolveFlat(
          window,
          pageStarts,
          index,
        );
        expect(
          HorizontalWindow.flatIndexOf(
            window,
            pageStarts,
            chapter,
            pageInChapter,
          ),
          equals(index),
          reason: '扁平索引 $index 往返后必须回到原位，否则翻页落点会错位',
        );
      }
    });
  });
}
