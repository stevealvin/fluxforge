import 'package:fluxforge/features/rules/models/rule_data_audit.dart';

/// 规则测试阶段类型枚举
enum RuleTestStepType {
  discovery,
  search,
  detail,
  parse,
}

/// 规则测试各阶段运行状态
enum RuleTestStepStatus {
  idle,
  running,
  success,
  failed,
  skipped,
}

/// 单个测试阶段的数据模型
///
/// 由流水线（见 `controllers/rule_test_pipeline.dart`）就地写入，
/// UI 只读渲染；[reset] 用于新一轮测试开始前清空上一轮痕迹。
class RuleTestStep {
  final RuleTestStepType type;
  final String title;
  final String subtitle;
  RuleTestStepStatus status;
  int elapsedMs;
  String? summary;
  String? errorMessage;
  Map<String, dynamic>? requestParams;
  dynamic rawResponse;
  String? formattedJson;
  Map<String, String> keyFields;
  bool isExpanded;

  /// 数据体检：各字段在**全量条目**里的覆盖情况（空表示该阶段没有可体检的列表）
  List<FieldCoverage> coverages;

  /// 数据体检：契约检查结果
  List<ContractCheck> checks;

  RuleTestStep({
    required this.type,
    required this.title,
    required this.subtitle,
    this.status = RuleTestStepStatus.idle,
    this.elapsedMs = 0,
    this.summary,
    this.errorMessage,
    this.requestParams,
    this.rawResponse,
    this.formattedJson,
    Map<String, String>? keyFields,
    this.isExpanded = false,
    List<FieldCoverage>? coverages,
    List<ContractCheck>? checks,
  })  : keyFields = keyFields ?? {},
        coverages = coverages ?? [],
        checks = checks ?? [];

  /// 该阶段的体检结论（无体检数据时视为通过）
  ///
  /// 供阶段列表显示「有警告」提示，而不必逐个字段去比对。
  AuditLevel get auditLevel => auditWorstOf([
        ...coverages.map((c) => c.level),
        ...checks.map((c) => c.level),
      ]);

  /// 该阶段是否出现了体检问题（含 fail）
  bool get hasAuditIssue => auditLevel != AuditLevel.ok;

  void reset() {
    status = RuleTestStepStatus.idle;
    elapsedMs = 0;
    summary = null;
    errorMessage = null;
    requestParams = null;
    rawResponse = null;
    formattedJson = null;
    keyFields.clear();
    coverages = [];
    checks = [];
  }
}
