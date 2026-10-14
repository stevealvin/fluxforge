/// 数据体检的严重级别
enum AuditLevel {
  /// 通过
  ok,

  /// 有瑕疵但不影响跑通（如部分条目缺封面）
  warn,

  /// 契约被破坏，会导致实际功能不可用（如条目缺链接）
  fail,
}

/// 单个字段在一组条目里的覆盖情况
///
/// 例：20 条 items 里 17 条有封面 → `field=cover, present=17, total=20`。
///
/// 这是「规则写得好不好」最直接的判据 —— 规则测试此前只看**首项**，
/// 于是「20 条里有 3 条缺封面」这类问题在测试页上完全看不出来。
class FieldCoverage {
  const FieldCoverage({
    required this.field,
    required this.present,
    required this.total,
  });

  /// 字段名（title / url / cover / desc）
  final String field;

  /// 有值的条目数
  final int present;

  /// 参与统计的条目总数
  final int total;

  bool get isFull => total > 0 && present == total;

  /// 覆盖率展示文案，如 `17/20`
  String get label => '$present/$total';

  /// 全覆盖 → ok；一条都没有 → fail（说明字段名写错了）；部分缺失 → warn
  AuditLevel get level {
    if (total == 0 || present == total) return AuditLevel.ok;
    if (present == 0) return AuditLevel.fail;
    return AuditLevel.warn;
  }
}

/// 一条契约检查结果
///
/// 只承载「字段覆盖率表达不了」的判定（相对路径、tabs 结构、hasMore 自洽…），
/// 避免与 [FieldCoverage] 重复报同一件事。
class ContractCheck {
  const ContractCheck({
    required this.name,
    required this.level,
    required this.detail,
  });

  /// 检查项名称，如「链接为绝对地址」
  final String name;

  final AuditLevel level;

  /// 结论说明，带具体数字（如「20 条中有 3 条为相对路径」）
  final String detail;
}

/// 汇总一组级别的「最坏值」：任一 fail 即 fail，否则任一 warn 即 warn
///
/// 放在 models 层而非体检器里：阶段模型需要用它算「本阶段有无警告」，
/// 而 models 反向依赖 engines 会破坏分层。
AuditLevel auditWorstOf(Iterable<AuditLevel> levels) {
  var worst = AuditLevel.ok;
  for (final level in levels) {
    if (level == AuditLevel.fail) return AuditLevel.fail;
    if (level == AuditLevel.warn) worst = AuditLevel.warn;
  }
  return worst;
}
