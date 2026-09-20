import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/novel/reader/controllers/chapter_cache.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';

/// 会话缓存单元测试
///
/// 覆盖两类此前无法验证的行为：
/// 1. 基本读写与「读取刷新 LRU 顺序」；
/// 2. 超容量淘汰 + 保护集合语义（长卷正在渲染的章节绝不能被淘汰）。
void main() {
  group('ChapterCache 基本读写', () {
    test('写入后可读，containsKey 与计数正确', () {
      final cache = ChapterCache();

      expect(cache.containsKey(3), isFalse);
      expect(cache[3], isNull);

      cache[3] = '第三章正文';
      cache[4] = '';

      expect(cache.containsKey(3), isTrue);
      expect(cache[3], '第三章正文');
      expect(cache.length, 2);
      // 空正文不算「有效缓存」
      expect(cache.nonEmptyCount, 1);
    });

    test('重复写入同一索引不会产生重复条目', () {
      final cache = ChapterCache();
      cache[1] = '旧正文';
      cache[1] = '新正文';

      expect(cache.length, 1);
      expect(cache[1], '新正文');
    });

    test('移除与清空', () {
      final cache = ChapterCache();
      cache[1] = 'A';
      cache[2] = 'B';

      cache.remove(1);
      expect(cache.containsKey(1), isFalse);
      expect(cache.length, 1);

      cache.clear();
      expect(cache.length, 0);
    });

    test('seedFromChapters 只种入非空正文', () {
      final cache = ChapterCache();
      cache.seedFromChapters(const [
        NovelChapter(title: '第1章', content: '第一章正文'),
        NovelChapter(title: '第2章', content: ''),
        NovelChapter(title: '第3章', content: '第三章正文'),
      ]);

      expect(cache.length, 2);
      expect(cache.containsKey(1), isFalse);
      expect(cache[0], '第一章正文');
      expect(cache[2], '第三章正文');
    });
  });

  group('ChapterCache.evictOverflow', () {
    test('未超容量时不淘汰', () {
      final cache = ChapterCache(capacity: 3);
      cache[0] = 'A';
      cache[1] = 'B';
      cache[2] = 'C';

      expect(cache.evictOverflow(), isEmpty);
      expect(cache.length, 3);
    });

    test('超容量时淘汰最久未使用者', () {
      final cache = ChapterCache(capacity: 3);
      for (int i = 0; i < 5; i++) {
        cache[i] = '第 $i 章';
      }

      final evicted = cache.evictOverflow();

      expect(evicted, {0, 1}, reason: '最早写入的 0 / 1 章应被淘汰');
      expect(cache.length, 3);
      expect(cache.containsKey(2), isTrue);
      expect(cache.containsKey(3), isTrue);
      expect(cache.containsKey(4), isTrue);
    });

    test('读取会刷新使用顺序，使最近读过的章节免于淘汰', () {
      final cache = ChapterCache(capacity: 3);
      cache[0] = 'A';
      cache[1] = 'B';
      cache[2] = 'C';

      // 回读第 0 章 —— 它应被移到访问序末尾
      expect(cache[0], 'A');

      cache[3] = 'D';
      final evicted = cache.evictOverflow();

      expect(evicted, {1}, reason: '第 1 章成为最久未使用者');
      expect(cache.containsKey(0), isTrue, reason: '刚读过的第 0 章必须保留');
    });

    test('protect 中的索引永不被淘汰', () {
      final cache = ChapterCache(capacity: 2);
      cache[0] = 'A';
      cache[1] = 'B';
      cache[2] = 'C';
      cache[3] = 'D';

      // 保护最早写入的 0 / 1（模拟「长卷正在渲染」）
      final evicted = cache.evictOverflow(protect: {0, 1});

      expect(evicted, {2, 3});
      expect(cache.containsKey(0), isTrue);
      expect(cache.containsKey(1), isTrue);
    });

    test('全部受保护时宁可持续超容，也不淘汰正在阅读的内容', () {
      final cache = ChapterCache(capacity: 1);
      cache[0] = 'A';
      cache[1] = 'B';

      final evicted = cache.evictOverflow(protect: {0, 1});

      expect(evicted, isEmpty);
      expect(cache.length, 2, reason: '允许暂时超容，优先保证阅读正确性');
    });

    test('capacity <= 0 表示不限制容量', () {
      final cache = ChapterCache(capacity: 0);
      for (int i = 0; i < 50; i++) {
        cache[i] = '第 $i 章';
      }

      expect(cache.evictOverflow(), isEmpty);
      expect(cache.length, 50);
    });
  });

  group('evictAllExcept（系统内存告警下的主动释放）', () {
    test('释放 keep 之外的全部条目，且不受容量上限约束', () {
      final cache = ChapterCache(capacity: 100);
      for (int i = 0; i < 8; i++) {
        cache[i] = '第 $i 章';
      }

      final evicted = cache.evictAllExcept({3, 4});

      expect(evicted, {0, 1, 2, 5, 6, 7});
      expect(cache.length, 2, reason: '内存告警时不看容量，只保 keep');
      expect(cache.containsKey(3), isTrue);
      expect(cache.containsKey(4), isTrue);
    });

    test('keep 覆盖全部条目时不释放任何内容', () {
      final cache = ChapterCache();
      cache[0] = 'A';
      cache[1] = 'B';

      expect(cache.evictAllExcept({0, 1}), isEmpty);
      expect(cache.length, 2);
    });

    test('keep 为空集合时释放全部条目', () {
      final cache = ChapterCache();
      cache[0] = 'A';
      cache[1] = 'B';

      expect(cache.evictAllExcept(const {}), {0, 1});
      expect(cache.length, 0);
    });

    test('空缓存调用返回空集合', () {
      expect(ChapterCache().evictAllExcept({0}), isEmpty);
    });
  });
}
