import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/storage/app_storage.dart';

/// 章页数估算输入：只含排版参数与内容度量，**不含任何平台依赖**
@immutable
class ChapterPageEstimateInput {
  const ChapterPageEstimateInput({
    required this.contentLength,
    required this.contentWidthPx,
    required this.contentHeightPx,
    required this.textSizePx,
    required this.textHeightPx,
    required this.lineSpacingPx,
    required this.paragraphSpacingPx,
    this.titleLength = 0,
    this.includeTitle = false,
    this.titleTextSizePx = 0,
    this.titleTextHeightPx = 0,
    this.titleLineSpacingPx = 0,
    this.titleTopSpacingPx = 0,
    this.titleBottomSpacingPx = 0,
    this.endPaddingPx = 0,
    this.letterSpacingPx = 0,
  });

  /// 正文长度（字符数）
  final int contentLength;

  /// 版心尺寸（已扣除内边距）
  final double contentWidthPx;
  final double contentHeightPx;

  /// 正文度量
  final double textSizePx;
  final double textHeightPx;
  final double lineSpacingPx;
  final double paragraphSpacingPx;
  final double letterSpacingPx;

  /// 标题（章名）度量；[includeTitle] 为假时不参与估算
  final int titleLength;
  final bool includeTitle;
  final double titleTextSizePx;
  final double titleTextHeightPx;
  final double titleLineSpacingPx;
  final double titleTopSpacingPx;
  final double titleBottomSpacingPx;

  /// 章末留白
  final double endPaddingPx;

  /// 校准分桶：桶内排版参数**全为常数**，仿射拟合才有意义
  ///
  /// 与 legado 的 `PageEstimateConfig.calibrationBucket` 同构：
  /// 把影响排版的每个参数都混进 FNV-1a 稳定哈希（不含内容，故同一套排版
  /// 参数下所有章节共用一条标定曲线）。
  int get calibrationBucket {
    final hash = _StablePageHash();
    hash
      ..addDouble(textSizePx)
      ..addDouble(textHeightPx)
      ..addDouble(lineSpacingPx)
      ..addDouble(paragraphSpacingPx)
      ..addDouble(letterSpacingPx)
      ..addDouble(titleTextSizePx)
      ..addDouble(titleTextHeightPx)
      ..addDouble(titleLineSpacingPx)
      ..addDouble(titleTopSpacingPx)
      ..addDouble(titleBottomSpacingPx)
      ..addDouble(endPaddingPx)
      ..addDouble(contentWidthPx)
      ..addDouble(contentHeightPx);
    return hash.value;
  }
}

/// 章页数估算引擎（纯算法：无状态、无平台依赖，可直接单测）
///
/// 对应 legado 的 `HeuristicPageEstimator`：**不排版**就能给出连续页数，
/// 再由 [PageEstimateCalibration] 用在线最小二乘校准到真实页数。
///
/// ### 为什么值得有它
/// 真实页数只能靠文本排版得到（一次整章 layout，见 `PaginationEngine`），
/// 而"这一章大概多少页"在以下场景需要**立刻**知道、且不能等排版：
/// 整书进度、目录预览、加载占位页的页数提示。
///
/// ### 冷启动不退化
/// 无样本时 [PageEstimateCalibration] 的行为等价于 `ceil(估算值)`，
/// 与引入估算之前的观感一致；只有攒够样本后才会被校准得更准。
class PageEstimateEngine {
  const PageEstimateEngine._();

  /// 容量系数：实测排版容量相对"理想网格"的折损（与 legado 同值）
  static const double capacityScale = 0.82;

  /// 估算**连续**页数（不取整、不设下限）
  ///
  /// 取整与校准统一交给 [PageEstimateCalibration.apply] —— 对已经取整的值做回归
  /// 会把取整偏置算两遍，截距就永远学不对（legado 注释里明确踩过这个坑）。
  static double estimateContinuous(ChapterPageEstimateInput input) {
    final glyphWidth = math.max(input.textSizePx * 0.95, _epsilon);
    final lineHeight = math.max(
      input.textHeightPx + input.lineSpacingPx,
      _epsilon,
    );
    final charsPerLine = input.contentWidthPx / glyphWidth;
    final linesPerPage = input.contentHeightPx / lineHeight;
    final capacity = math.max(
      charsPerLine * linesPerPage * capacityScale * _paragraphLoss(input),
      _epsilon,
    );

    final bodyFraction = math.max(input.contentLength, 0) / capacity;
    final height = math.max(input.contentHeightPx, _epsilon);
    final titleFraction = _titleHeight(input) / height;
    final endPaddingFraction = input.endPaddingPx / height;

    return bodyFraction + titleFraction + endPaddingFraction;
  }

  /// 段落留白造成的容量折损（段距越大，一页装得越少）
  static double _paragraphLoss(ChapterPageEstimateInput input) {
    final ratio =
        input.paragraphSpacingPx /
        math.max(input.textHeightPx + input.lineSpacingPx, _epsilon);
    return (1 - ratio * 0.08).clamp(0.7, 1.0);
  }

  /// 标题占用的高度（含上下间距）
  static double _titleHeight(ChapterPageEstimateInput input) {
    if (!input.includeTitle) return 0;
    final titleGlyphWidth = math.max(input.titleTextSizePx * 0.95, _epsilon);
    final titleCharsPerLine = math.max(
      input.contentWidthPx / titleGlyphWidth,
      _epsilon,
    );
    final titleLineCount = math.max(
      (input.titleLength / titleCharsPerLine).ceilToDouble(),
      1.0,
    );
    final titleLineHeight = math.max(
      input.titleTextHeightPx + input.titleLineSpacingPx,
      _epsilon,
    );
    return input.titleTopSpacingPx +
        titleLineCount * titleLineHeight +
        input.titleBottomSpacingPx;
  }

  static const double _epsilon = 1e-6;
}

/// 桶内仿射修正：`真实页数 ≈ slope × 估算连续页数 + intercept`
///
/// 一个桶内字号 / 行距 / 段距 / 版心全是常数（见
/// [ChapterPageEstimateInput.calibrationBucket]），于是只剩两个自由度：
/// [slope] 学段落断行的实际损耗，[intercept] 学标题、章末留白与取整偏置
/// —— 后者是乘性系数表达不出来的。
///
/// 默认 `slope = 1, intercept = 0` 让未拟合时的行为等价于 `ceil(估算值)`，
/// 即**冷启动不退化**。
@immutable
class PageEstimateCalibration {
  const PageEstimateCalibration({
    this.slope = 1,
    this.intercept = 0,
    this.sampleCount = 0,
    this.fitted = false,
  });

  final double slope;
  final double intercept;
  final int sampleCount;

  /// 显式标记而不是由 [sampleCount] 推导：样本够但拟合被判越界时必须退回冷启动
  final bool fitted;

  /// 最少样本数（低于它不做拟合）
  static const int minSamples = 4;

  /// 估算连续页数 → 整数页数
  ///
  /// 未拟合：`ceil`（与引入回归之前逐位一致）；已拟合：`round`（取整偏置已进截距）。
  int apply(double estimatedPages) {
    if (!estimatedPages.isFinite) return 1;
    if (!fitted) return math.max(estimatedPages.ceil(), 1);
    final value = slope * estimatedPages + intercept;
    if (!value.isFinite) return 1;
    return math.max(value.round(), 1);
  }
}

/// 流式最小二乘累加器：只留 5 个标量，不保留任何原始样本
@immutable
class PageEstimateSamples {
  const PageEstimateSamples({
    this.count = 0,
    this.sumX = 0,
    this.sumY = 0,
    this.sumXX = 0,
    this.sumXY = 0,
  });

  final int count;
  final double sumX;
  final double sumY;
  final double sumXX;
  final double sumXY;

  /// 有效样本上限：超过后按滑动衰减，让曲线跟着最近的实际排版走
  static const int maxEffectiveSamples = 256;

  static const double _degenerateDeterminant = 1e-6;
  static const double _minSlope = 0.3;
  static const double _maxSlope = 3.0;
  static const double _minIntercept = -2.0;
  static const double _maxIntercept = 5.0;

  PageEstimateSamples plus(double x, double y) {
    final retention = count >= maxEffectiveSamples
        ? (maxEffectiveSamples - 1) / count
        : 1.0;
    return PageEstimateSamples(
      count: math.min(count + 1, maxEffectiveSamples),
      sumX: sumX * retention + x,
      sumY: sumY * retention + y,
      sumXX: sumXX * retention + x * x,
      sumXY: sumXY * retention + x * y,
    );
  }

  /// 拟合；样本不足、x 无变化（行列式退化）或结果越界时**退回冷启动**
  PageEstimateCalibration fit() {
    final cold = PageEstimateCalibration(sampleCount: count);
    if (count < PageEstimateCalibration.minSamples) return cold;

    final n = count.toDouble();
    final determinant = n * sumXX - sumX * sumX;
    if (determinant <= _degenerateDeterminant) return cold;

    final slope = (n * sumXY - sumX * sumY) / determinant;
    final intercept = (sumY - slope * sumX) / n;
    if (!slope.isFinite || !intercept.isFinite) return cold;
    if (slope < _minSlope || slope > _maxSlope) return cold;
    if (intercept < _minIntercept || intercept > _maxIntercept) return cold;

    return PageEstimateCalibration(
      slope: slope,
      intercept: intercept,
      sampleCount: count,
      fitted: true,
    );
  }
}

/// 校准存储：按分桶累积样本并落盘
///
/// 持久化失败（例如未初始化偏好存储的单测环境）只降级为**内存态**，
/// 绝不影响阅读主链路 —— 估算本身只影响展示，不参与任何正确性判断。
class PageEstimateCalibrationStore {
  PageEstimateCalibrationStore();

  /// 阅读器使用的共享实例
  static final PageEstimateCalibrationStore instance =
      PageEstimateCalibrationStore();

  static const String storageKey = 'reader_page_estimate_calibration';

  final Map<int, PageEstimateSamples> _samples = {};

  /// 读取某桶的当前标定
  PageEstimateCalibration get(int bucket) =>
      (_samples[bucket] ?? const PageEstimateSamples()).fit();

  /// 累积一条样本（估算连续页数 → 真实页数），返回该桶更新后的标定
  PageEstimateCalibration record({
    required int bucket,
    required double estimatedPages,
    required int realPages,
  }) {
    if (!estimatedPages.isFinite || estimatedPages <= 0 || realPages <= 0) {
      return get(bucket);
    }
    final updated = (_samples[bucket] ?? const PageEstimateSamples()).plus(
      estimatedPages,
      realPages.toDouble(),
    );
    _samples[bucket] = updated;
    final calibration = updated.fit();
    // 落盘不阻塞、不抛错（fire-and-forget）
    _persist();
    return calibration;
  }

  bool _loadedOnce = false;

  /// 载入历史样本（幂等：重复调用只生效一次，避免把本会话新学的样本冲掉）
  Future<void> load() async {
    if (_loadedOnce) return;
    _loadedOnce = true;
    try {
      final raw = await AppStorage.getString(storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _samples
        ..clear()
        ..addAll({
          for (final entry in decoded.entries)
            if (int.tryParse(entry.key.toString()) case final bucket?)
              if (entry.value is Map)
                bucket: _samplesFromJson(entry.value as Map),
        });
    } catch (e) {
      debugPrint('[PageEstimate] 载入标定失败（降级为内存态）: $e');
    }
  }

  /// 清空（测试用）
  @visibleForTesting
  void reset() => _samples.clear();

  void _persist() {
    try {
      final payload = jsonEncode({
        for (final entry in _samples.entries)
          entry.key.toString(): _samplesToJson(entry.value),
      });
      AppStorage.setString(storageKey, payload);
    } catch (e) {
      debugPrint('[PageEstimate] 保存标定失败（不影响阅读）: $e');
    }
  }

  static Map<String, double> _samplesToJson(PageEstimateSamples samples) => {
    'n': samples.count.toDouble(),
    'x': samples.sumX,
    'y': samples.sumY,
    'xx': samples.sumXX,
    'xy': samples.sumXY,
  };

  static PageEstimateSamples _samplesFromJson(Map json) => PageEstimateSamples(
    count: (json['n'] as num?)?.toInt() ?? 0,
    sumX: (json['x'] as num?)?.toDouble() ?? 0,
    sumY: (json['y'] as num?)?.toDouble() ?? 0,
    sumXX: (json['xx'] as num?)?.toDouble() ?? 0,
    sumXY: (json['xy'] as num?)?.toDouble() ?? 0,
  );
}

/// FNV-1a 稳定哈希（与 legado `StablePageHash` 同构：跨平台、跨进程稳定）
class _StablePageHash {
  static const int _offsetBasis = -3750763034362895579;
  static const int _prime = 1099511628211;
  static const int _mask = 0xFFFFFFFFFFFFFFFF;

  int _value = _offsetBasis;

  int get value => _value;

  void addDouble(double value) {
    // 取原始 bit 表示：同一个排版参数必须得到同一个桶
    final bits = value.toDouble().hashCode;
    _addInt(bits);
    _addInt((value * 1000).round());
  }

  void _addInt(int value) {
    for (var byteIndex = 0; byteIndex < 8; byteIndex++) {
      _mix((value >> (byteIndex * 8)) & 0xff);
    }
  }

  void _mix(int byte) {
    _value = ((_value ^ byte) * _prime) & _mask;
  }
}
