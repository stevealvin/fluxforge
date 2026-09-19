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
  }) : keyFields = keyFields ?? {};

  void reset() {
    status = RuleTestStepStatus.idle;
    elapsedMs = 0;
    summary = null;
    errorMessage = null;
    requestParams = null;
    rawResponse = null;
    formattedJson = null;
    keyFields.clear();
  }
}
