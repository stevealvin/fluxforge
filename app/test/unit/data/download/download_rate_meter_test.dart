import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/data/download/download_rate_meter.dart';
import 'package:fluxforge/data/download/download_service.dart';

/// 下行速率：采样口径与展示口径
///
/// 速率是**瞬时值**，两条契约必须成立：
/// 1. 采样必须节流（否则下载时列表每秒重建几十次）；
/// 2. 窗口必须前移（否则速率会被整段历史拖住，停下后数字迟迟不掉）。
void main() {
  final t0 = DateTime(2026, 9, 22, 12);

  group('DownloadRateMeter', () {
    test('未满采样间隔不产出速率（节流，避免每块数据都刷新 UI）', () {
      final meter = DownloadRateMeter();

      expect(meter.add(1000, t0), isNull);
      expect(meter.add(1000, t0.add(const Duration(milliseconds: 400))), isNull);
    });

    test('满间隔后按「区间字节 ÷ 区间时长」给出速率', () {
      final meter = DownloadRateMeter(interval: const Duration(seconds: 1));

      meter.add(512 * 1024, t0);
      final speed = meter.add(512 * 1024, t0.add(const Duration(seconds: 1)));

      expect(speed, closeTo(1024 * 1024, 1), reason: '1 秒内共收 1MB → 1 MB/s');
    });

    test('窗口前移：下一段按新起点重新计，不被历史拖住', () {
      final meter = DownloadRateMeter(interval: const Duration(seconds: 1));

      meter.add(1024 * 1024, t0);
      final first = meter.add(1024 * 1024, t0.add(const Duration(seconds: 1)));
      expect(first, closeTo(2 * 1024 * 1024, 1));

      // 新窗口：这一秒只收到 512KB → 速率必须跟着掉下来
      final second = meter.add(512 * 1024, t0.add(const Duration(seconds: 2)));
      expect(second, closeTo(512 * 1024, 1));
    });

    test('非正增量一律忽略（不污染窗口）', () {
      final meter = DownloadRateMeter(interval: const Duration(seconds: 1));

      expect(meter.add(0, t0), isNull);
      expect(meter.add(-5, t0.add(const Duration(seconds: 2))), isNull);
    });

    test('reset 后重新计时：暂停再继续不会把暂停时长算进窗口', () {
      final meter = DownloadRateMeter(interval: const Duration(seconds: 1));

      meter.add(1024 * 1024, t0);
      meter.reset();

      // 重置后首次 add 只作为新窗口起点：即便真实时间已跳过 10 秒也不产出速率
      expect(meter.add(1024, t0.add(const Duration(seconds: 10))), isNull);
    });
  });

  group('formatDownloadSpeed', () {
    test('按量级切换单位，与体积口径一致（1024 进制）', () {
      expect(formatDownloadSpeed(2.5 * 1024 * 1024), '2.5 MB/s');
      expect(formatDownloadSpeed(500 * 1024), '500 KB/s');
      expect(formatDownloadSpeed(512), '512 B/s');
    });

    test('速率未知时返回空串（调用方直接拼接，不必判空）', () {
      expect(formatDownloadSpeed(0), '');
      expect(formatDownloadSpeed(-1), '');
    });
  });

  group('formatDownloadBytes', () {
    test('总量已知时给出「已下载 / 总量」', () {
      expect(
        formatDownloadBytes(1 * 1024 * 1024, 4 * 1024 * 1024),
        '1.0 MB / 4.0 MB',
      );
      expect(formatDownloadBytes(0, 2 * 1024 * 1024 * 1024), '0 MB / 2.00 GB');
    });

    test('总量未知时只给已下载，不编造分母（HLS / 需再解析的漫画章节）', () {
      expect(formatDownloadBytes(1024 * 1024, null), '1.0 MB');
      expect(formatDownloadBytes(0, null), '0 MB');
      expect(formatDownloadBytes(1024 * 1024, 0), '1.0 MB');
    });
  });
}
