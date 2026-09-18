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

    test('每页高度不超过可用高度（段落吸附最多容忍一行误差）', () {
      final text = List.generate(80, (i) => '第 $i 行内容，用于校验单页高度约束。').join('\n');
      const maxHeight = 200.0;
      // fontSize 16 * height 1.5 = 24
      const oneLineHeight = 24.0;

      for (final page in slice(text, height: maxHeight)) {
        final painter = TextPainter(
          text: TextSpan(text: page, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 320);

        // 说明：二分查找保证切分点本身不溢出；随后若命中「段落自然吸附」
        // （断点恰好是换行符时会在其后多带 1 个字符），可能多出至多一行高度。
        expect(painter.height, lessThanOrEqualTo(maxHeight + oneLineHeight));
      }
    });
  });
}
