import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/novel/reader/engines/page_estimate_engine.dart';

/// 页数估算与在线校准引擎单测
///
/// 这套能力的定位是「**不排版**也能给出可用页数」，因此用例重点是：
/// 冷启动不退化、估算方向正确、拟合收敛、以及异常样本必须退回冷启动。
void main() {
  ChapterPageEstimateInput input({
    int contentLength = 6000,
    double width = 320,
    double height = 560,
    double textSize = 16,
    double lineHeight = 24,
    double paragraphSpacing = 0,
    int titleLength = 0,
    bool includeTitle = false,
  }) {
    return ChapterPageEstimateInput(
      contentLength: contentLength,
      contentWidthPx: width,
      contentHeightPx: height,
      textSizePx: textSize,
      textHeightPx: lineHeight,
      lineSpacingPx: 0,
      paragraphSpacingPx: paragraphSpacing,
      letterSpacingPx: 0.5,
      titleLength: titleLength,
      includeTitle: includeTitle,
      titleTextSizePx: 18,
      titleTextHeightPx: 26,
      titleLineSpacingPx: 0,
      titleTopSpacingPx: 12,
      titleBottomSpacingPx: 16,
      endPaddingPx: 0,
    );
  }

  group('PageEstimateCalibration 冷启动不退化', () {
    test('未拟合时等价于 ceil（与引入估算之前逐位一致）', () {
      const cold = PageEstimateCalibration();
      expect(cold.fitted, isFalse);
      expect(cold.apply(3.2), 4);
      expect(cold.apply(3.0), 3);
      expect(cold.apply(0.4), 1);
    });

    test('页数恒 >= 1，非法输入兜底为 1', () {
      const cold = PageEstimateCalibration();
      expect(cold.apply(0), 1);
      expect(cold.apply(-5), 1);
      expect(cold.apply(double.nan), 1);
      expect(cold.apply(double.infinity), 1);
    });

    test('已拟合时按 slope/intercept 修正并 round（取整偏置已进截距）', () {
      const fitted = PageEstimateCalibration(
        slope: 2,
        intercept: 0.5,
        sampleCount: 8,
        fitted: true,
      );
      // 2 * 3 + 0.5 = 6.5 → 7
      expect(fitted.apply(3), 7);
      expect(fitted.apply(-10), 1, reason: '修正后为负也必须收敛到 1 页');
    });
  });

  group('PageEstimateEngine 估算方向与敏感度', () {
    test('内容越长估算页数越多', () {
      final short = PageEstimateEngine.estimateContinuous(
        input(contentLength: 2000),
      );
      final long = PageEstimateEngine.estimateContinuous(
        input(contentLength: 20000),
      );
      expect(long, greaterThan(short));
      expect(short, greaterThan(0));
    });

    test('字号越大估算页数越多（每行装的字更少）', () {
      final small = PageEstimateEngine.estimateContinuous(input(textSize: 14));
      final large = PageEstimateEngine.estimateContinuous(input(textSize: 22));
      expect(large, greaterThan(small));
    });

    test('版心越矮估算页数越多', () {
      final tall = PageEstimateEngine.estimateContinuous(input(height: 800));
      final short = PageEstimateEngine.estimateContinuous(input(height: 300));
      expect(short, greaterThan(tall));
    });

    test('段距越大估算页数越多（容量折损）', () {
      final tight = PageEstimateEngine.estimateContinuous(
        input(paragraphSpacing: 0),
      );
      final loose = PageEstimateEngine.estimateContinuous(
        input(paragraphSpacing: 12),
      );
      expect(loose, greaterThan(tight));
    });

    test('计入标题时页数不少于不计标题', () {
      final without = PageEstimateEngine.estimateContinuous(
        input(titleLength: 30),
      );
      final withTitle = PageEstimateEngine.estimateContinuous(
        input(titleLength: 30, includeTitle: true),
      );
      expect(withTitle, greaterThan(without));
    });

    test('空正文仍给出非负估算（由调用方决定是否采用）', () {
      expect(
        PageEstimateEngine.estimateContinuous(input(contentLength: 0)),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('校准分桶', () {
    test('同排版参数同桶，改任一项即换桶', () {
      final base = input().calibrationBucket;
      expect(input().calibrationBucket, base);
      expect(
        input(contentLength: 99999).calibrationBucket,
        base,
        reason: '内容长度不参与分桶：同一排版参数共用一条标定曲线',
      );
      expect(input(textSize: 17).calibrationBucket, isNot(base));
      expect(input(width: 360).calibrationBucket, isNot(base));
      expect(input(height: 600).calibrationBucket, isNot(base));
    });
  });

  group('PageEstimateSamples 拟合', () {
    PageEstimateSamples fit(List<List<double>> pairs) {
      var samples = const PageEstimateSamples();
      for (final pair in pairs) {
        samples = samples.plus(pair[0], pair[1]);
      }
      return samples;
    }

    test('样本不足时退回冷启动', () {
      final calibration = fit([
        [1, 2],
        [2, 4],
        [3, 6],
      ]).fit();
      expect(calibration.fitted, isFalse);
      expect(calibration.apply(3.2), 4);
    });

    test('样本足够时收敛到真实比例（y = 2x）', () {
      final calibration = fit([
        [1, 2],
        [2, 4],
        [3, 6],
        [4, 8],
        [5, 10],
      ]).fit();
      expect(calibration.fitted, isTrue);
      expect(calibration.slope, closeTo(2, 1e-6));
      expect(calibration.intercept, closeTo(0, 1e-6));
      // 2 * 3 = 6
      expect(calibration.apply(3), 6);
    });

    test('x 无变化（行列式退化）时退回冷启动', () {
      final calibration = fit([
        [5, 10],
        [5, 11],
        [5, 12],
        [5, 13],
      ]).fit();
      expect(calibration.fitted, isFalse);
    });

    test('拟合结果越界时退回冷启动（防止被异常样本带偏）', () {
      final calibration = fit([
        [1, 100],
        [2, 200],
        [3, 300],
        [4, 400],
      ]).fit();
      expect(calibration.fitted, isFalse, reason: 'slope 远超上限，必须退回冷启动');
    });
  });

  group('PageEstimateCalibrationStore', () {
    test('记录样本后按桶返回拟合结果，未记录过的桶为冷启动', () {
      final store = PageEstimateCalibrationStore();
      addTearDown(store.reset);
      const bucket = 42;

      for (var i = 1; i <= 5; i++) {
        store.record(
          bucket: bucket,
          estimatedPages: i.toDouble(),
          realPages: i * 2,
        );
      }

      final calibration = store.get(bucket);
      expect(calibration.fitted, isTrue);
      expect(calibration.sampleCount, 5);
      expect(store.get(7).fitted, isFalse, reason: '别的桶不受影响');
    });

    test('非法样本被忽略（不产生样本、不改动已有标定）', () {
      final store = PageEstimateCalibrationStore();
      addTearDown(store.reset);
      const bucket = 7;

      store.record(bucket: bucket, estimatedPages: 0, realPages: 5);
      store.record(bucket: bucket, estimatedPages: double.nan, realPages: 5);
      store.record(bucket: bucket, estimatedPages: 5, realPages: 0);

      expect(store.get(bucket).sampleCount, 0);
    });
  });
}
