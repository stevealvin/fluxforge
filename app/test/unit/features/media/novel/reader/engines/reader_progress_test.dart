import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/novel/reader/engines/reader_progress.dart';
import 'package:fluxforge/features/media/novel/reader/models/chapter_metrics.dart';

/// 阅读进度换算引擎单元测试
///
/// 覆盖跨页 / 跨章的边界语义：页边界归入下一页、偏移超出正文归入末页、
/// 章块不足一屏视为读完、进度条拖到两端不越界。
void main() {
  // 三页正文（长度 3 / 4 / 2）→ 页起始偏移表
  const slices = [0, 3, 7];

  group('charOffsetFromPage 页码 → 字符偏移', () {
    test('首页偏移为 0', () {
      expect(ReaderProgress.charOffsetFromPage(slices, 0), 0);
    });

    test('直接查表得到该页起始偏移', () {
      expect(ReaderProgress.charOffsetFromPage(slices, 1), 3);
      expect(ReaderProgress.charOffsetFromPage(slices, 2), 7);
    });

    test('页码越界时收敛到末页起始偏移（不把位置拉回章首）', () {
      expect(ReaderProgress.charOffsetFromPage(slices, 99), 7);
    });

    test('空表返回 0', () {
      expect(ReaderProgress.charOffsetFromPage(const [], 3), 0);
    });
  });

  group('pageIndexFromCharOffset 字符偏移 → 页码', () {
    test('首字符落在第 1 页', () {
      expect(ReaderProgress.pageIndexFromCharOffset(slices, 0), 0);
    });

    test('恰好落在页边界时归入下一页', () {
      expect(ReaderProgress.pageIndexFromCharOffset(slices, 3), 1);
      expect(ReaderProgress.pageIndexFromCharOffset(slices, 7), 2);
    });

    test('页内偏移落在该页', () {
      expect(ReaderProgress.pageIndexFromCharOffset(slices, 6), 1);
    });

    test('偏移超出正文时归入末页', () {
      expect(ReaderProgress.pageIndexFromCharOffset(slices, 500), 2);
    });

    test('空切片返回 0', () {
      expect(ReaderProgress.pageIndexFromCharOffset(const [], 10), 0);
    });
  });

  group('horizontalProgress 横向章内进度', () {
    test('按已读页数占比', () {
      expect(ReaderProgress.horizontalProgress(0, 4), 0.25);
      expect(ReaderProgress.horizontalProgress(3, 4), 1.0);
    });

    test('无切片时为 0', () {
      expect(ReaderProgress.horizontalProgress(0, 0), 0.0);
    });

    test('页码越界时封顶 1.0', () {
      expect(ReaderProgress.horizontalProgress(99, 4), 1.0);
    });
  });

  group('pageIndexFromRatio 进度条比例 → 页码', () {
    test('拖到 0% 落在第 1 页（不越界回退）', () {
      expect(ReaderProgress.pageIndexFromRatio(0.0, 4), 0);
    });

    test('拖到 100% 精确落在末页', () {
      expect(ReaderProgress.pageIndexFromRatio(1.0, 4), 3);
    });

    test('中间比例按页向上取整', () {
      expect(ReaderProgress.pageIndexFromRatio(0.25, 4), 0);
      expect(ReaderProgress.pageIndexFromRatio(0.5, 4), 1);
    });

    test('比例越界时先 clamp', () {
      expect(ReaderProgress.pageIndexFromRatio(1.5, 4), 3);
      expect(ReaderProgress.pageIndexFromRatio(-1.0, 4), 0);
    });

    test('无切片时为 0', () {
      expect(ReaderProgress.pageIndexFromRatio(0.5, 0), 0);
    });
  });

  group('verticalProgress 纵向章内进度', () {
    const metrics = ChapterMetrics(top: 100, height: 1600, scrollable: 500);

    test('章块内滚动一半即 50%', () {
      expect(
        ReaderProgress.verticalProgress(currentOffset: 350, metrics: metrics),
        0.5,
      );
    });

    test('未滚到章块顶部时为 0', () {
      expect(
        ReaderProgress.verticalProgress(currentOffset: 50, metrics: metrics),
        0.0,
      );
    });

    test('滚过章块底部时封顶 1.0', () {
      expect(
        ReaderProgress.verticalProgress(currentOffset: 9999, metrics: metrics),
        1.0,
      );
    });

    test('章块不足一屏（无滚动空间）直接视为读完', () {
      const short = ChapterMetrics(top: 0, height: 400, scrollable: 0);
      expect(
        ReaderProgress.verticalProgress(currentOffset: 0, metrics: short),
        1.0,
      );
    });
  });

  group('verticalOffsetFromRatio 章内比例 → 滚动偏移', () {
    const metrics = ChapterMetrics(top: 100, height: 1600, scrollable: 500);

    test('按比例换算章块内绝对偏移', () {
      expect(
        ReaderProgress.verticalOffsetFromRatio(ratio: 0.5, metrics: metrics),
        350,
      );
    });

    test('比例越界时先 clamp', () {
      expect(
        ReaderProgress.verticalOffsetFromRatio(ratio: 2.0, metrics: metrics),
        600,
      );
      expect(
        ReaderProgress.verticalOffsetFromRatio(ratio: -1.0, metrics: metrics),
        100,
      );
    });
  });

  group('ratioFromCharOffset 字符偏移 → 章内比例', () {
    test('半程即 0.5', () {
      expect(ReaderProgress.ratioFromCharOffset(50, 100), 0.5);
    });

    test('正文为空时返回 0', () {
      expect(ReaderProgress.ratioFromCharOffset(10, 0), 0.0);
    });

    test('偏移越界时 clamp 到 [0, 1]', () {
      expect(ReaderProgress.ratioFromCharOffset(200, 100), 1.0);
      expect(ReaderProgress.ratioFromCharOffset(-10, 100), 0.0);
    });
  });

  group('章内进度文案', () {
    test('横向显示页码，空切片显示占位符', () {
      expect(ReaderProgress.horizontalLabel(0, 3), '本章 第 1 / 3 页');
      expect(ReaderProgress.horizontalLabel(2, 3), '本章 第 3 / 3 页');
      expect(ReaderProgress.horizontalLabel(0, 0), '--');
    });

    test('纵向显示百分比（四舍五入）', () {
      expect(ReaderProgress.verticalLabel(0.456), '本章 46%');
      expect(ReaderProgress.verticalLabel(1.0), '本章 100%');
      expect(ReaderProgress.verticalLabel(0.0), '本章 0%');
    });
  });
}
