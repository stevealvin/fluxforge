import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/features/library/downloads/engines/download_action_resolver.dart';

/// 下载任务状态 → 动作判定单元测试
///
/// 这段判定原先在小说 / 漫画详情页各写一遍（逐行同构），视频那份只剩"全新开始"。
/// 这里把语义固定下来，尤其是**判定顺序**：「部分失败」的任务同时满足
/// "未完成、非进行中"，必须优先判失败，否则会走成「继续下载」而跳过失败条目。
void main() {
  final now = DateTime(2026, 9, 21);

  DownloadTask task({
    DownloadStatus status = DownloadStatus.pending,
    Set<int> failed = const {},
    Set<int> completed = const {},
  }) {
    return DownloadTask(
      id: 'book-1',
      title: '测试作品',
      status: status,
      failed: failed,
      completed: completed,
      // total 由目标地址数派生
      targetUrls: const ['a', 'b', 'c'],
      createdAt: now,
      updatedAt: now,
    );
  }

  test('没有任务 → 全新开始', () {
    expect(DownloadActionResolver.resolve(null), equals(DownloadAction.start));
  });

  test('进行中（pending / running）→ 暂停', () {
    expect(
      DownloadActionResolver.resolve(task(status: DownloadStatus.pending)),
      equals(DownloadAction.pause),
    );
    expect(
      DownloadActionResolver.resolve(task(status: DownloadStatus.running)),
      equals(DownloadAction.pause),
    );
  });

  test('已完成 → 仅提示，不再动作', () {
    expect(
      DownloadActionResolver.resolve(task(status: DownloadStatus.completed)),
      equals(DownloadAction.alreadyFinished),
    );
  });

  test('有失败条目 → 重试失败（优先于「继续」）', () {
    final halfFailed = task(
      status: DownloadStatus.paused,
      failed: const {1},
      completed: const {0},
    );
    expect(
      DownloadActionResolver.resolve(halfFailed),
      equals(DownloadAction.retryFailed),
      reason: '「部分失败」必须优先判失败，否则会走成继续下载而跳过失败条目',
    );
  });

  test('已暂停且无失败条目 → 继续', () {
    expect(
      DownloadActionResolver.resolve(
        task(status: DownloadStatus.paused, completed: const {0}),
      ),
      equals(DownloadAction.resume),
    );
  });

  test('顺序优先级：进行中 > 已完成 > 失败 > 继续', () {
    // 进行中优先（即便已有失败条目，也先让用户能暂停）
    expect(
      DownloadActionResolver.resolve(
        task(status: DownloadStatus.running, failed: const {1}),
      ),
      equals(DownloadAction.pause),
    );
    // 已完成优先于失败（历史失败条目不应让已完成的整体任务回退）
    expect(
      DownloadActionResolver.resolve(
        task(status: DownloadStatus.completed, failed: const {1}),
      ),
      equals(DownloadAction.alreadyFinished),
    );
  });
}
