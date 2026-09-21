import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/novel/reader/engines/pagination_engine.dart';

/// 分页引擎单元测试
///
/// 这些用例在重构前是无法编写的 —— 当时分页逻辑内嵌在 2000 行的 `State` 中，
/// 与滚动控制器、章节缓存、PageController 等状态强耦合。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 16, height: 1.5);

  List<String> slice(
    String text, {
    double width = 320,
    double height = 240,
  }) {
    return PaginationEngine.sliceIntoPages(
      text: text,
      maxWidth: width,
      maxHeight: height,
      textStyle: style,
    );
  }

  group('PaginationEngine.sliceIntoPages', () {
    test('空文本返回单页空串', () {
      expect(slice(''), ['']);
    });

    test('可用尺寸非法时原样返回单页全文，交由调用方兜底', () {
      const text = '尚未测量到视口尺寸时的正文';
      expect(slice(text, width: 0), [text]);
      expect(slice(text, height: -1), [text]);
    });

    test('长文本切分为多页，且拼接后与原文完全一致（不丢字符）', () {
      final text = List.generate(
        200,
        (i) => '第 $i 行测试正文内容，用于验证分页切分是否完整无遗漏。',
      ).join('\n');

      final pages = slice(text);

      expect(pages.length, greaterThan(1), reason: '长文本应被切分为多页');
      expect(pages.join(), text, reason: '分页拼接必须能还原全文');
    });

    test('可用高度越小，分页数量越多（单调性）', () {
      final text = List.generate(
        120,
        (i) => '第 $i 行测试正文，用于验证分页行为随尺寸变化。',
      ).join('\n');

      final tall = slice(text, height: 600).length;
      final medium = slice(text, height: 320).length;
      final short = slice(text, height: 160).length;

      expect(medium, greaterThanOrEqualTo(tall));
      expect(short, greaterThan(medium));
    });

    test('每页可见正文都不超过可用高度（溢出的只可能是末尾空白行）', () {
      final text = List.generate(80, (i) => '第 $i 行内容，用于校验单页高度约束。').join('\n');
      const maxHeight = 200.0;
      // fontSize 16 * height 1.5 = 24
      const oneLineHeight = 24.0;

      double measuredHeight(String content) => (TextPainter(
            text: TextSpan(text: content, style: style),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 320))
              .height;

      for (final page in slice(text, height: maxHeight)) {
        final fullHeight = measuredHeight(page);

        // 断言 1（真正的不变量）：去掉末尾换行后必须完全放得下 ——
        // 溢出永远只发生在「末尾空白行」上，可见正文一行都不会被挤出可视区。
        // 可证明：二分查找保证切分点自身不超限，段落自然吸附只会把切分点**前移**，
        // 故页内正文恒 ≤ maxHeight；换行符落在页尾时 TextPainter 多算的那一行是空行。
        final visibleHeight = page.endsWith('\n')
            ? measuredHeight(page.substring(0, page.length - 1))
            : fullHeight;
        expect(visibleHeight, lessThanOrEqualTo(maxHeight));

        // 断言 2：整页高度至多多一行，且这一行只可能是末尾空白
        expect(fullHeight, lessThanOrEqualTo(maxHeight + oneLineHeight));
        if (fullHeight > maxHeight) {
          expect(page.endsWith('\n'), isTrue,
              reason: '超限页必须以换行结尾（末尾空白行），不得是正文被挤出');
        }
      }
    });
  });

  group('PaginationEngine.needsRepaginate', () {
    bool need({
      double currentWidth = 320,
      double currentHeight = 240,
      double nextWidth = 320,
      double nextHeight = 240,
      int pageCount = 5,
      bool wholeContent = false,
      int contentLength = 1000,
    }) =>
        PaginationEngine.needsRepaginate(
          currentWidth: currentWidth,
          currentHeight: currentHeight,
          nextWidth: nextWidth,
          nextHeight: nextHeight,
          pageCount: pageCount,
          firstPageIsWholeContent: wholeContent,
          contentLength: contentLength,
        );

    test('视口尺寸变化必须重排（首次渲染 / 横竖屏旋转 / 分屏）', () {
      expect(need(nextWidth: 400), isTrue);
      expect(need(nextHeight: 300), isTrue);
      // 亚像素抖动不触发（实测视口尺寸存在浮点误差）
      expect(need(nextWidth: 320.5), isFalse);
    });

    test('尚无任何分页时必须重排', () {
      expect(need(pageCount: 0), isTrue);
    });

    test('「单页即全文」的兜底结果：长文重排，短文保持', () {
      // 尚未测量尺寸时产生的兜底单页 → 长文必须重切
      expect(need(pageCount: 1, wholeContent: true, contentLength: 800), isTrue);
      // 短文本本就只有一页，重排没有意义
      expect(need(pageCount: 1, wholeContent: true, contentLength: 200), isFalse);
    });

    test('已正常分页且尺寸未变时不重排', () {
      expect(need(pageCount: 5), isFalse);
      expect(need(pageCount: 1, wholeContent: false), isFalse);
    });
  });
}
