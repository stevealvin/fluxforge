import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../models/rule.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_loading.dart';

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

/// 跨媒体规则流式测试与调试页面 (对齐开源阅读 Legado 书源调试体验)
///
/// 具备 4 阶段自动化流水线测试：
/// 1. [discovery] 发现/分类解析
/// 2. [search] 关键词搜索
/// 3. [detail] 详情元数据与选集抓取
/// 4. [parse] 真实直链嗅探与正文提取
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

  bool _isTesting = false;
  bool _isCancelled = false;
  bool _isConsoleExpanded = true;
  DateTime? _testStartTime;

  /// 四大生命周期测试阶段列表
  late final List<RuleTestStep> _steps;

  @override
  void initState() {
    super.initState();
    // 智能根据规则类型预填默认测试关键字
    _keywordController = TextEditingController(text: _getDefaultKeyword(widget.rule.type));
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
  }

  @override
  void dispose() {
    _isCancelled = true;
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

  /// 智能匹配不同媒体类型的默认推荐测试关键词
  String _getDefaultKeyword(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return '斗罗大陆';
      case 'novel':
        return '剑来';
      case 'picture':
      case 'comic':
        return '海贼王';
      case 'audio':
        return '三体';
      default:
        return '测试';
    }
  }

  /// 安全美化格式化 JSON 字符串
  String _formatJson(dynamic data) {
    if (data == null) return 'null';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (e) {
      return data.toString();
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
      _isCancelled = false;
      _testStartTime = DateTime.now();
      for (final step in _steps) {
        step.reset();
      }
    });

    // 记录测试启动日志
    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule: ${widget.rule.name}',
      message: '====== 开始执行规则多阶段自动化调试 (关键词: "$keyword") ======',
    );

    // 用于阶段间接力递送的数据载体
    Map<String, dynamic>? candidateItemFromDiscovery;
    Map<String, dynamic>? candidateItemFromSearch;
    String? candidateDetailUrl;
    Map<String, dynamic>? candidateDetailItem;
    String? candidateChapterUrl;

    // ----------------------------------------------------
    // 阶段 1: 发现页测试 (Discovery)
    // ----------------------------------------------------
    if (!_isCancelled) {
      final step = _steps[0];
      step.status = RuleTestStepStatus.running;
      step.requestParams = {'page': 1, 'baseUrl': widget.rule.baseUrl};
      setState(() {});

      final sw = Stopwatch()..start();
      try {
        final res = await RuleEngine.discovery(widget.rule, page: 1);
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.rawResponse = res;
        step.formattedJson = _formatJson(res);

        if (res is Map) {
          final tabs = res['tabs'] is List ? (res['tabs'] as List) : [];
          final items = res['items'] is List
              ? (res['items'] as List)
              : (res['list'] is List ? res['list'] as List : []);

          step.keyFields['分类标签 (tabs)'] = '${tabs.length} 个分类';
          step.keyFields['推荐条目 (items)'] = '${items.length} 个条目';

          if (items.isNotEmpty && items.first is Map) {
            final first = items.first as Map<String, dynamic>;
            candidateItemFromDiscovery = first;
            step.keyFields['首项标题'] = first['title']?.toString() ?? '无标题';
            step.keyFields['首项链接'] = first['url']?.toString() ?? '无链接';
            step.keyFields['首项封面'] = (first['cover']?.toString().isNotEmpty ?? false) ? '已提供' : '缺失';
          }
          step.summary = '成功获取 ${tabs.length} 个分类维度，解析到 ${items.length} 条首屏数据';
          step.status = RuleTestStepStatus.success;
        } else if (res is List) {
          step.keyFields['返回条目'] = '${res.length} 个条目';
          if (res.isNotEmpty && res.first is Map) {
            final first = res.first as Map<String, dynamic>;
            candidateItemFromDiscovery = first;
            step.keyFields['首项标题'] = first['title']?.toString() ?? '无标题';
            step.keyFields['首项链接'] = first['url']?.toString() ?? '无链接';
          }
          step.summary = '成功解析到 ${res.length} 条推荐数据';
          step.status = RuleTestStepStatus.success;
        } else {
          step.summary = '发现动作已返回，但数据格式不是预期的 Map 或 List';
          step.status = RuleTestStepStatus.failed;
        }
      } catch (e) {
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.status = RuleTestStepStatus.failed;
        step.errorMessage = e.toString();
        step.summary = '发现页执行抛出异常: $e';
      }
      if (mounted) setState(() {});
    }

    // ----------------------------------------------------
    // 阶段 2: 搜索测试 (Search)
    // ----------------------------------------------------
    if (!_isCancelled) {
      final step = _steps[1];
      step.status = RuleTestStepStatus.running;
      step.requestParams = {'keyword': keyword, 'page': 1, 'baseUrl': widget.rule.baseUrl};
      setState(() {});

      final sw = Stopwatch()..start();
      try {
        final res = await RuleEngine.search(widget.rule, keyword, page: 1);
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.rawResponse = res;
        step.formattedJson = _formatJson(res);

        List searchList = [];
        if (res is List) {
          searchList = res;
        } else if (res is Map && res['items'] is List) {
          searchList = res['items'] as List;
        } else if (res is Map && res['list'] is List) {
          searchList = res['list'] as List;
        }

        step.keyFields['命中条目数'] = '${searchList.length} 条';
        if (searchList.isNotEmpty) {
          final first = searchList.first;
          if (first is Map) {
            candidateItemFromSearch = Map<String, dynamic>.from(first);
            step.keyFields['首条匹配结果'] = first['title']?.toString() ?? '无标题';
            step.keyFields['详情页地址 (url)'] = first['url']?.toString() ?? '无链接';
            step.keyFields['海报封面 (cover)'] = (first['cover']?.toString().isNotEmpty ?? false) ? '有效' : '未提供';
            step.keyFields['附加描述 (desc)'] = first['desc']?.toString() ?? '无描述';
          }
          step.summary = '搜索 "$keyword" 成功命中 ${searchList.length} 条结果';
          step.status = RuleTestStepStatus.success;
        } else {
          step.summary = '未检索到关键词 "$keyword" 的匹配结果 (0条条目)';
          step.status = RuleTestStepStatus.failed;
          step.errorMessage = '返回列表为空，建议更换常用测试关键词重试';
        }
      } catch (e) {
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.status = RuleTestStepStatus.failed;
        step.errorMessage = e.toString();
        step.summary = '搜索动作执行异常: $e';
      }
      if (mounted) setState(() {});
    }

    // 智能选取进入详情测试的目标数据（优先取搜索结果，搜索为空则回退取发现页首项）
    if (candidateItemFromSearch != null) {
      candidateDetailItem = candidateItemFromSearch;
      candidateDetailUrl = candidateItemFromSearch['url']?.toString();
    } else if (candidateItemFromDiscovery != null) {
      candidateDetailItem = candidateItemFromDiscovery;
      candidateDetailUrl = candidateItemFromDiscovery['url']?.toString();
    }

    // ----------------------------------------------------
    // 阶段 3: 详情与选集测试 (Detail)
    // ----------------------------------------------------
    if (!_isCancelled) {
      final step = _steps[2];
      if (candidateDetailUrl == null || candidateDetailUrl.isEmpty) {
        step.status = RuleTestStepStatus.skipped;
        step.summary = '由于前置发现与搜索阶段均未产生有效详情 URL，已跳过详情测试';
      } else {
        step.status = RuleTestStepStatus.running;
        step.requestParams = {
          'url': candidateDetailUrl,
          'item': candidateDetailItem,
          'baseUrl': widget.rule.baseUrl,
        };
        setState(() {});

        final sw = Stopwatch()..start();
        try {
          final res = await RuleEngine.detail(
            widget.rule,
            candidateDetailUrl,
            item: candidateDetailItem,
          );
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.rawResponse = res;
          step.formattedJson = _formatJson(res);

          if (res is Map) {
            final title = res['title']?.toString() ?? candidateDetailItem?['title']?.toString() ?? '无标题';
            final desc = res['desc']?.toString() ?? '';
            final items = res['items'] is List ? (res['items'] as List) : [];

            step.keyFields['详情标题'] = title;
            step.keyFields['简介字数'] = '${desc.length} 字';

            if (items.isNotEmpty) {
              step.keyFields['资源条目 (items)'] = '${items.length} 项';
              final firstItem = items.first;
              if (firstItem is Map) {
                candidateChapterUrl = firstItem['url']?.toString();
                step.keyFields['首项名称与链接'] = '${firstItem['title'] ?? firstItem['name'] ?? '第1项'} -> $candidateChapterUrl';
              } else if (firstItem is String) {
                candidateChapterUrl = firstItem;
                step.keyFields['首项链接'] = firstItem;
              }
            } else if (res['playUrl'] != null) {
              candidateChapterUrl = res['playUrl'].toString();
              step.keyFields['详情直出播放链接'] = candidateChapterUrl;
            }

            step.summary = '详情解析成功: 《$title》，解析到 ${items.length} 个资源条目';
            step.status = RuleTestStepStatus.success;
          } else {
            step.summary = '详情动作未返回预期的 Map 对象结构';
            step.status = RuleTestStepStatus.failed;
          }
        } catch (e) {
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.status = RuleTestStepStatus.failed;
          step.errorMessage = e.toString();
          step.summary = '详情页执行异常: $e';
        }
      }
      if (mounted) setState(() {});
    }

    // ----------------------------------------------------
    // 阶段 4: 直链解析/正文提取测试 (Parse)
    // ----------------------------------------------------
    if (!_isCancelled) {
      final step = _steps[3];
      if (candidateChapterUrl == null || candidateChapterUrl.isEmpty) {
        step.status = RuleTestStepStatus.skipped;
        step.summary = '前置详情阶段未获取到有效分集或章节 URL，已跳过直链解析测试';
      } else {
        step.status = RuleTestStepStatus.running;
        step.requestParams = {
          'url': candidateChapterUrl,
          'baseUrl': widget.rule.baseUrl,
        };
        setState(() {});

        final sw = Stopwatch()..start();
        try {
          final res = await RuleEngine.parse(widget.rule, candidateChapterUrl);
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.rawResponse = res;
          step.formattedJson = _formatJson(res);

          if (res is Map) {
            final playUrl = res['url']?.toString() ?? res['playUrl']?.toString();
            final content = res['content']?.toString() ?? res['text']?.toString();
            final images = res['images'] is List ? (res['images'] as List) : [];

            if (playUrl != null && playUrl.isNotEmpty) {
              step.keyFields['视频播放直链 (url)'] = playUrl;
              final isM3u8 = playUrl.contains('.m3u8');
              step.keyFields['流媒体协议'] = isM3u8 ? 'HLS (m3u8 极速切片流)' : 'MP4/Direct 直链';
              step.summary = '嗅探解析成功！真实媒体地址就绪 (${step.keyFields['流媒体协议']})';
              step.status = RuleTestStepStatus.success;
            } else if (content != null && content.isNotEmpty) {
              step.keyFields['小说章节字数'] = '${content.length} 字';
              step.keyFields['首句预览'] = content.length > 50 ? '${content.substring(0, 50)}...' : content;
              step.summary = '小说正文抓取成功！已解密提取 ${content.length} 字纯文本';
              step.status = RuleTestStepStatus.success;
            } else if (images.isNotEmpty) {
              step.keyFields['解析图片总数'] = '${images.length} 张';
              step.keyFields['首图地址'] = images.first.toString();
              step.summary = '漫画/图集解析成功！已提取 ${images.length} 张高清画卷';
              step.status = RuleTestStepStatus.success;
            } else {
              step.summary = '解析完成但未识别到有效的 url / content / images 核心字段';
              step.status = RuleTestStepStatus.failed;
            }
          } else if (res is String && res.trim().isNotEmpty) {
            step.keyFields['直接返回文本/URL'] = res.trim();
            step.summary = '解析成功：已返回有效直链/文本字串';
            step.status = RuleTestStepStatus.success;
          } else {
            step.summary = '解析动作执行完毕，但返回内容为空';
            step.status = RuleTestStepStatus.failed;
          }
        } catch (e) {
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.status = RuleTestStepStatus.failed;
          step.errorMessage = e.toString();
          step.summary = '解析直链/正文动作抛出异常: $e';
        }
      }
      if (mounted) setState(() {});
    }

    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule: ${widget.rule.name}',
      message: '====== 规则四阶段自动化调试执行结束 ======',
    );

    if (mounted) {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// 终止正在运行的测试
  void _stopPipeline() {
    setState(() {
      _isCancelled = true;
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
    final buffer = StringBuffer();
    buffer.writeln('# FluxForge 规则诊断报告 (Rule Test Report)');
    buffer.writeln();
    buffer.writeln('- **规则名称**：${widget.rule.name}');
    buffer.writeln('- **规则类型**：${widget.rule.type}');
    buffer.writeln('- **规则版本**：v${widget.rule.version ?? '1.0.0'}');
    buffer.writeln('- **源站基址**：${widget.rule.baseUrl}');
    buffer.writeln('- **测试用词**：`${_keywordController.text.trim()}`');
    buffer.writeln('- **生成时间**：${DateTime.now().toIso8601String()}');
    buffer.writeln();
    buffer.writeln('## 流水线测试结果 (Pipeline)');
    buffer.writeln();

    for (final step in _steps) {
      final statusStr = step.status == RuleTestStepStatus.success
          ? '✅ 成功'
          : step.status == RuleTestStepStatus.failed
              ? '❌ 失败'
              : step.status == RuleTestStepStatus.skipped
                  ? '⏭️ 跳过'
                  : '⚪ 未执行';
      buffer.writeln('### ${step.title}');
      buffer.writeln('- **状态**：$statusStr (${step.elapsedMs}ms)');
      if (step.summary != null) buffer.writeln('- **摘要**：${step.summary}');
      if (step.errorMessage != null) buffer.writeln('- **错误**：`${step.errorMessage}`');
      if (step.keyFields.isNotEmpty) {
        buffer.writeln('- **核心指标**：');
        step.keyFields.forEach((k, v) {
          buffer.writeln('  - $k: $v');
        });
      }
      buffer.writeln();
    }

    buffer.writeln('## 沙箱控制台日志输出 (Console Logs)');
    buffer.writeln('```');
    final logs = _getFilteredLogs();
    for (final log in logs) {
      buffer.writeln('[${log.level}] ${log.tag}: ${log.message}');
    }
    buffer.writeln('```');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已成功复制完整 Markdown 调试报告至剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 过滤获取与当前规则相关的沙箱控制台日志
  List<LogEntry> _getFilteredLogs() {
    final allLogs = AppLogger.getLogs();
    final ruleTag = 'Rule: ${widget.rule.name}';
    return allLogs.where((l) {
      if (l.tag == ruleTag) return true;
      if (_testStartTime != null && l.time.isAfter(_testStartTime!)) {
        return l.tag.contains('Rule') || l.tag == 'Rule Sandbox';
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          // 顶部关键词与测试控制台
          _buildControlHeader(isDark),

          // 主体内容区：四阶段流水线卡片 + 底部沙箱控制台
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // 阶段卡片列表
                ..._steps.map((step) => _buildStepCard(step, isDark)),
                const SizedBox(height: 12),

                // 底部沙箱控制台 (Console Logcat)
                _buildConsoleSection(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部导航栏
  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      titleSpacing: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => context.pop(),
        tooltip: '返回',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '规则调试 · ${widget.rule.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.rule.type.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            widget.rule.baseUrl.isNotEmpty ? widget.rule.baseUrl : '无源站地址',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Ionicons.copyOutline, size: 18),
          tooltip: '复制调试诊断报告',
          onPressed: _copyDebugReport,
        ),
        IconButton(
          icon: const Icon(Ionicons.trashOutline, size: 18),
          tooltip: '清空沙箱控制台日志',
          onPressed: () {
            AppLogger.clear();
            setState(() {});
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// 顶部测试操作区：测试关键字输入框与启动按钮
  Widget _buildControlHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          // 纯净单圆角搜索关键词输入框
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.lightBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _keywordFocusNode.hasFocus
                      ? AppColors.primary
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  width: _keywordFocusNode.hasFocus ? 1.2 : 0.8,
                ),
              ),
              child: TextField(
                controller: _keywordController,
                focusNode: _keywordFocusNode,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '输入测试关键词...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.primary),
                  suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: _keywordController.text.isNotEmpty
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _keywordController.clear();
                            setState(() {});
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.clear_rounded, size: 15),
                          ),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  // 清除所有继承边框，杜绝双圆角重叠
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                ),
                onSubmitted: (_) {
                  if (!_isTesting) _startPipeline();
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 测试启动/停止按钮
          AppButton.compact(
            label: _isTesting ? '停止' : '开始测试',
            icon: _isTesting ? const Icon(Ionicons.squareOutline, size: 14) : const Icon(Ionicons.playOutline, size: 14),
            color: _isTesting ? Colors.redAccent : AppColors.primary,
            onPressed: _isTesting ? _stopPipeline : _startPipeline,
          ),
        ],
      ),
    );
  }

  /// 单个测试阶段卡片
  Widget _buildStepCard(RuleTestStep step, bool isDark) {
    final statusColor = _getStepStatusColor(step.status);
    final statusIcon = _getStepStatusIcon(step.status);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：阶段标题 + 状态徽章 + 耗时
          Row(
            children: [
              // 状态图标
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(child: statusIcon),
              ),
              const SizedBox(width: 10),

              // 标题与副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // 耗时 Badge
              if (step.elapsedMs > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${step.elapsedMs}ms',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
            ],
          ),

          // 摘要信息 (Summary)
          if (step.summary != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.18), width: 0.8),
              ),
              child: Text(
                step.summary!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: isDark ? statusColor.withValues(alpha: 0.9) : statusColor,
                ),
              ),
            ),
          ],

          // 核心提取指标键值对 (Key Fields)
          if (step.keyFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg.withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: step.keyFields.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            entry.value,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // 展开/收起原始 JSON 按钮
          if (step.rawResponse != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      step.isExpanded = !step.isExpanded;
                    });
                  },
                  icon: Icon(
                    step.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                  ),
                  label: Text(
                    step.isExpanded ? '收起原始 JSON' : '查看原始 JSON',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
                if (step.formattedJson != null)
                  IconButton(
                    icon: const Icon(Ionicons.copyOutline, size: 13),
                    tooltip: '复制该阶段 JSON',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: step.formattedJson!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制该阶段 JSON 数据'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
              ],
            ),
          ],

          // 折叠的原始 JSON 预览区
          if (step.isExpanded && step.formattedJson != null) ...[
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  step.formattedJson!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF38BDF8), // 浅蓝代码高亮
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部实时沙箱控制台 (Console Logcat)
  Widget _buildConsoleSection(bool isDark) {
    final logs = _getFilteredLogs();

    return AppCard(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 控制台头部操作区
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Ionicons.terminalOutline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '沙箱实时控制台 (Console)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${logs.length}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (logs.isNotEmpty)
                    IconButton(
                      icon: const Icon(Ionicons.copyOutline, size: 16),
                      tooltip: '复制全部控制台日志',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final logText = logs.map((l) => '[${l.level}] ${l.message}').join('\n');
                        Clipboard.setData(ClipboardData(text: logText));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制 ${logs.length} 条控制台日志'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      _isConsoleExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    tooltip: _isConsoleExpanded ? '收起控制台' : '展开控制台',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _isConsoleExpanded = !_isConsoleExpanded;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),

          if (_isConsoleExpanded) ...[
            const SizedBox(height: 8),
            Container(
              height: 180,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        _isTesting ? '等待沙箱 console 输出...' : '暂无调试日志，点击上方“开始测试”启动',
                        style: const TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final logColor = _getLogLevelColor(log.level);
                        final logText = '[${log.level}] ${log.message}';

                        return InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: logText));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已复制日志: ${log.message}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                            child: SelectableText.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.3),
                                children: [
                                  TextSpan(
                                    text: '[${log.level}] ',
                                    style: TextStyle(color: logColor, fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: log.message,
                                    style: const TextStyle(color: Color(0xFFE2E8F0)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// 状态颜色匹配
  Color _getStepStatusColor(RuleTestStepStatus status) {
    switch (status) {
      case RuleTestStepStatus.running:
        return AppColors.primary;
      case RuleTestStepStatus.success:
        return const Color(0xFF10B981); // Emerald
      case RuleTestStepStatus.failed:
        return Colors.redAccent;
      case RuleTestStepStatus.skipped:
        return Colors.orangeAccent;
      case RuleTestStepStatus.idle:
        return Colors.grey;
    }
  }

  /// 状态图标匹配
  Widget _getStepStatusIcon(RuleTestStepStatus status) {
    switch (status) {
      case RuleTestStepStatus.running:
        return const LoadingIndicator.compact(size: 14, strokeWidth: 2);
      case RuleTestStepStatus.success:
        return const Icon(Icons.check_rounded, size: 16, color: Color(0xFF10B981));
      case RuleTestStepStatus.failed:
        return const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent);
      case RuleTestStepStatus.skipped:
        return const Icon(Icons.skip_next_rounded, size: 16, color: Colors.orangeAccent);
      case RuleTestStepStatus.idle:
        return const Icon(Icons.circle_outlined, size: 14, color: Colors.grey);
    }
  }

  /// 控制台日志级别颜色
  Color _getLogLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Colors.redAccent;
      case 'WARN':
        return Colors.amberAccent;
      case 'DEBUG':
        return Colors.lightBlueAccent;
      case 'INFO':
      default:
        return const Color(0xFF34D399); // 浅翡翠绿
    }
  }
}
