import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/rules/controllers/rule_test_pipeline.dart';
import 'package:fluxforge/features/rules/engines/rule_test_log_filter.dart';
import 'package:fluxforge/features/rules/engines/rule_test_report.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';
import 'package:fluxforge/features/rules/widgets/rule_test_app_bar.dart';
import 'package:fluxforge/features/rules/widgets/rule_test_console.dart';
import 'package:fluxforge/features/rules/widgets/rule_test_control_header.dart';
import 'package:fluxforge/features/rules/widgets/rule_test_step_card.dart';

/// 跨媒体规则流式测试与调试页面 (对齐开源阅读 Legado 书源调试体验)
///
/// 具备 4 阶段自动化流水线测试：
/// 1. [discovery] 发现/分类解析
/// 2. [search] 关键词搜索
/// 3. [detail] 详情元数据与选集抓取
/// 4. [parse] 真实直链嗅探与正文提取
///
/// 页面只负责「生命周期状态 + 装配」：
/// - 四阶段调度与阶段产物接力见 [RuleTestPipeline]；
/// - 报告拼接 / 日志过滤见 `engines/`；
/// - 三个面板（操作区、阶段卡片、控制台）见 `widgets/`。
class RuleTesterPage extends StatefulWidget {
  final Rule rule;

  const RuleTesterPage({
    super.key,
    required this.rule,
  });

  @override
  State<RuleTesterPage> createState() => _RuleTesterPageState();
}

class _RuleTesterPageState extends State<RuleTesterPage> {
  late final TextEditingController _keywordController;
  final FocusNode _keywordFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _logScrollController = ScrollController();

  /// 四阶段流水线调度器（页面只持有生命周期，阶段推进逻辑全在调度器内）
  late final RuleTestPipeline _pipeline;

  bool _isTesting = false;
  bool _isConsoleExpanded = true;
  DateTime? _testStartTime;

  /// 四大生命周期测试阶段列表
  late final List<RuleTestStep> _steps;

  @override
  void initState() {
    super.initState();
    // 智能根据规则类型预填默认测试关键字
    _keywordController =
        TextEditingController(text: RuleTestReport.defaultKeywordFor(widget.rule.type));
    _keywordFocusNode.addListener(_onFocusChanged);
    AppLogger.logsNotifier.addListener(_onLogsUpdated);

    _steps = [
      RuleTestStep(
        type: RuleTestStepType.discovery,
        title: '1. 发现/分类测试 (Discovery)',
        subtitle: '测试首页分类标签、筛选维度及首屏推荐条目解析',
      ),
      RuleTestStep(
        type: RuleTestStepType.search,
        title: '2. 关键字搜索测试 (Search)',
        subtitle: '使用测试关键词发起检索，校验条目列表与核心字段完整度',
      ),
      RuleTestStep(
        type: RuleTestStepType.detail,
        title: '3. 详情与选集测试 (Detail)',
        subtitle: '拉取目标详情页，解析简介、作者及选集/章节目录列表',
      ),
      RuleTestStep(
        type: RuleTestStepType.parse,
        title: '4. 直链/正文解析测试 (Parse)',
        subtitle: '对首集/首章发起最终解析，验证真实媒体直链或小说正文',
      ),
    ];

    _pipeline = RuleTestPipeline(
      rule: widget.rule,
      steps: _steps,
      onStepChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    // 页面销毁时中止仍在跑的流水线，避免回调打到已卸载的 State
    _pipeline.cancel();
    _keywordFocusNode.removeListener(_onFocusChanged);
    AppLogger.logsNotifier.removeListener(_onLogsUpdated);
    _keywordController.dispose();
    _keywordFocusNode.dispose();
    _scrollController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onLogsUpdated() {
    // 日志已变 → 过滤缓存失效；此处只置脏（O(1)），不做扫描
    _filteredLogsDirty = true;
    if (mounted && _isTesting) {
      setState(() {});
      // 控制台自动滚到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// 启动完整四阶段接力测试流水线
  Future<void> _startPipeline() async {
    if (_isTesting) return;

    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入用于测试的搜索关键词'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testStartTime = DateTime.now();
      // 过滤结果依赖本轮起始时间，起始时间一变缓存必须失效
      _filteredLogsDirty = true;
      for (final step in _steps) {
        step.reset();
      }
    });

    await _pipeline.run(keyword);

    if (mounted) {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// 终止正在运行的测试
  void _stopPipeline() {
    _pipeline.cancel();
    setState(() {
      _isTesting = false;
    });
    AppLogger.addLog(
      level: 'WARN',
      tag: 'Rule: ${widget.rule.name}',
      message: '用户主动中止了规则自动化调试测试',
    );
  }

  /// 复制完整 Markdown 调试诊断报告
  void _copyDebugReport() {
    final report = RuleTestReport.buildMarkdown(
      rule: widget.rule,
      keyword: _keywordController.text.trim(),
      generatedAt: DateTime.now(),
      steps: _steps,
      logs: _getFilteredLogs(),
    );

    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已成功复制完整 Markdown 调试报告至剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 本规则相关日志的缓存快照（惰性重算）
  List<LogEntry>? _filteredLogsCache;

  /// 缓存是否已失效
  bool _filteredLogsDirty = true;

  /// 过滤获取与当前规则相关的沙箱控制台日志（带缓存）
  ///
  /// 过滤是一次 O(全部日志) 的扫描（`AppLogger.getLogs()` 还会先拷贝一份不可变列表），
  /// 而控制台在每次重建时都要读它 —— 原先直接在 `build()` 里现算，
  /// 日志量大时等于「每次重建都做一次全量扫描」。
  ///
  /// 现改为惰性缓存：日志变化 / 本轮起始时间变化时只置脏标记（O(1)），
  /// 真正的扫描推迟到**下一次读取**（且一帧内多处读取只算一次）。
  List<LogEntry> _getFilteredLogs() {
    final cached = _filteredLogsCache;
    if (!_filteredLogsDirty && cached != null) return cached;

    final filtered = RuleTestLogFilter.forRule(
      AppLogger.getLogs(),
      ruleTag: 'Rule: ${widget.rule.name}',
      startTime: _testStartTime,
    );
    _filteredLogsCache = filtered;
    _filteredLogsDirty = false;
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: RuleTestAppBar(
        rule: widget.rule,
        onBack: () => context.pop(),
        onCopyReport: _copyDebugReport,
        onClearLogs: () {
          AppLogger.clear();
          setState(() {});
        },
      ),
      body: Column(
        children: [
          // 顶部关键词与测试控制台
          RuleTestControlHeader(
            isDark: isDark,
            controller: _keywordController,
            focusNode: _keywordFocusNode,
            isTesting: _isTesting,
            onChanged: (_) {
              if (mounted) setState(() {});
            },
            onStart: _startPipeline,
            onStop: _stopPipeline,
          ),

          // 主体内容区：四阶段流水线卡片 + 底部沙箱控制台
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // 阶段卡片列表
                ..._steps.map((step) => RuleTestStepCard(
                      step: step,
                      isDark: isDark,
                      onToggleExpanded: () {
                        setState(() {
                          step.isExpanded = !step.isExpanded;
                        });
                      },
                    )),
                const SizedBox(height: 12),

                // 底部沙箱控制台 (Console Logcat)
                RuleTestConsolePanel(
                  isDark: isDark,
                  logs: _getFilteredLogs(),
                  expanded: _isConsoleExpanded,
                  isTesting: _isTesting,
                  scrollController: _logScrollController,
                  onToggleExpanded: () {
                    setState(() {
                      _isConsoleExpanded = !_isConsoleExpanded;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
