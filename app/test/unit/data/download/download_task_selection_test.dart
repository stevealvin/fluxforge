import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/data/download/download_service.dart';

/// 下载任务的「选集」语义
///
/// 核心契约：目标清单**始终全量**，选集只决定「跑哪些项」与「进度怎么算」——
/// 这样「先下 1-3 集、之后再补 5-7 集」不会因为下标错位而误判「已完成」。
void main() {
  DownloadTask task({
    int total = 5,
    Set<int>? selection,
    Set<int> completed = const {},
  }) => DownloadTask(
    id: 'book',
    title: '书名',
    targetUrls: List.generate(total, (i) => 'u$i'),
    targetTitles: List.generate(total, (i) => '第 ${i + 1} 集'),
    selection: selection,
    completed: completed,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  group('选集计量', () {
    test('selection 为 null 即全选（与改造前行为一致）', () {
      final t = task(completed: {0, 1});

      expect(t.isPartialSelection, isFalse);
      expect(t.selectedTotal, 5);
      expect(t.selectedDoneCount, 2);
      expect(t.progressLabel, '2 / 5');
      for (int i = 0; i < 5; i++) {
        expect(t.isSelected(i), isTrue);
      }
    });

    test('选集只计选中项：已完成但未选中的不计入分母/分子', () {
      final t = task(selection: {1, 3}, completed: {0, 3});

      expect(t.isPartialSelection, isTrue);
      expect(t.selectedTotal, 2);
      expect(t.selectedDoneCount, 1, reason: '第 0 集已完成但不在选集内');
      expect(t.progressLabel, '1 / 2');
      expect(t.progress, closeTo(0.5, 0.001));
      expect(t.isSelected(0), isFalse);
      expect(t.isSelected(1), isTrue);
    });

    test('越界下标被忽略，不放大分母', () {
      final t = task(selection: {0, 99});
      expect(t.selectedTotal, 1);
      expect(t.isSelected(99), isFalse);
    });

    test('空选集进度为 0 而不是除零', () {
      final t = task(selection: const {});
      expect(t.selectedTotal, 0);
      expect(t.progress, 0.0);
      expect(t.progressLabel, '0 / 0');
    });
  });

  group('选集改动', () {
    test('copyWith 不传选集即保持不变', () {
      final t = task(selection: {2});
      final paused = t.copyWith(status: DownloadStatus.paused);

      expect(paused.selection, {2});
      expect(paused.isSelected(0), isFalse);
    });

    test('copyWith 显式传 null 表示改回全选（哨兵区分「没传」与「置空」）', () {
      final t = task(selection: {2});

      expect(t.copyWith(selection: null).selection, isNull);
      expect(t.copyWith(selection: {1}).selection, {1});
    });
  });

  group('持久化', () {
    test('选集随任务存盘并可还原', () {
      final t = task(selection: {1, 4});
      final restored = DownloadTask.fromJson(t.toJson());

      expect(restored.selection, {1, 4});
      expect(restored.selectedTotal, 2);
      expect(restored.selectedDoneCount, 0);
    });

    test('缺字段的老任务按全选处理（无需迁移）', () {
      final legacy = DownloadTask.fromJson({
        'id': 'book',
        'title': '旧任务',
        'targetUrls': ['a', 'b'],
        'targetTitles': ['第 1 集', '第 2 集'],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
      });

      expect(legacy.selection, isNull);
      expect(legacy.selectedTotal, 2);
      expect(legacy.progressLabel, '0 / 2');
    });
  });

  test('体积格式化口径统一', () {
    expect(formatDownloadSize(0), '0 MB');
    expect(formatDownloadSize(-1), '0 MB');
    expect(formatDownloadSize(1024 * 1024), '1.0 MB');
    expect(formatDownloadSize(1024 * 1024 * 1024), '1.00 GB');
  });
}
