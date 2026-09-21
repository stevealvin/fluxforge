import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/rules/engines/rule_test_actions.dart';
import 'package:fluxforge/features/rules/engines/rule_test_report.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';

/// 规则四阶段自动化调试流水线
///
/// 发现 → 搜索 → 详情 → 解析，上一阶段的产物作为下一阶段的入参接力递送。
/// 与 UI 解耦：只就地写入 [RuleTestStep]，并通过 [onStepChanged] 通知宿主刷新；
/// 生命周期（是否仍在测试、测试起始时间）由宿主持有。
class RuleTestPipeline {
  RuleTestPipeline({
    required this.rule,
    required this.steps,
    required this.onStepChanged,
    this.actions = const RuleTestActions(),
  });

  final Rule rule;

  /// 四大生命周期测试阶段（顺序固定：discovery / search / detail / parse）
  final List<RuleTestStep> steps;

  /// 阶段状态变化通知（宿主内部自行处理 mounted 判定与 setState）
  final void Function() onStepChanged;

  /// 沙箱动作入口（默认走真实 `RuleEngine`，单测可注入可控假实现）
  final RuleTestActions actions;

  bool _isCancelled = false;

  /// 运行轮次：每次 [run] 递增，[cancel] 也递增
  ///
  /// 沙箱调用是 FFI 阻塞式的，**无法真正打断**，所以这里只能保证「结果不落地」：
  /// 在途阶段返回时若轮次已变（被中止，或被新一轮测试顶替），一律丢弃结果 ——
  /// 不写共享的 [steps]、也不再通知宿主。否则「取消后立刻重开」时，
  /// 旧一轮的迟到结果会盖掉新一轮刚写好的阶段状态。
  int _generation = 0;

  /// 本轮测试是否已被用户中止
  bool get isCancelled => _isCancelled;

  /// 中止本轮测试（在途阶段的结果随之作废，后续阶段不再执行）
  void cancel() {
    _isCancelled = true;
    _generation++;
  }

  /// 执行完整四阶段接力测试
  Future<void> run(String keyword) async {
    _isCancelled = false;
    // 本轮的唯一标识：一旦被中止或被新一轮顶替，本轮所有在途结果一律作废
    final generation = ++_generation;
    bool isStale() => _isCancelled || generation != _generation;

    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule: ${rule.name}',
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
    if (!isStale()) {
      final step = steps[0];
      step.status = RuleTestStepStatus.running;
      step.requestParams = {'page': 1, 'baseUrl': rule.baseUrl};
      onStepChanged();

      final sw = Stopwatch()..start();
      try {
        final res = await actions.discovery(rule);
        // 在途期间被中止 / 被新一轮顶替：结果作废，不写入阶段状态
        if (isStale()) return;
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.rawResponse = res;
        step.formattedJson = RuleTestReport.formatJson(res);

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
        // 异常也可能来自已作废的那一轮（例如中止之后才抛出的超时）
        if (isStale()) return;
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.status = RuleTestStepStatus.failed;
        step.errorMessage = e.toString();
        step.summary = '发现页执行抛出异常: $e';
      }
      onStepChanged();
    }

    // ----------------------------------------------------
    // 阶段 2: 搜索测试 (Search)
    // ----------------------------------------------------
    if (!isStale()) {
      final step = steps[1];
      step.status = RuleTestStepStatus.running;
      step.requestParams = {'keyword': keyword, 'page': 1, 'baseUrl': rule.baseUrl};
      onStepChanged();

      final sw = Stopwatch()..start();
      try {
        final res = await actions.search(rule, keyword);
        // 在途期间被中止 / 被新一轮顶替：结果作废，不写入阶段状态
        if (isStale()) return;
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.rawResponse = res;
        step.formattedJson = RuleTestReport.formatJson(res);

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
        if (isStale()) return;
        sw.stop();
        step.elapsedMs = sw.elapsedMilliseconds;
        step.status = RuleTestStepStatus.failed;
        step.errorMessage = e.toString();
        step.summary = '搜索动作执行异常: $e';
      }
      onStepChanged();
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
    if (!isStale()) {
      final step = steps[2];
      if (candidateDetailUrl == null || candidateDetailUrl.isEmpty) {
        step.status = RuleTestStepStatus.skipped;
        step.summary = '由于前置发现与搜索阶段均未产生有效详情 URL，已跳过详情测试';
      } else {
        step.status = RuleTestStepStatus.running;
        step.requestParams = {
          'url': candidateDetailUrl,
          'item': candidateDetailItem,
          'baseUrl': rule.baseUrl,
        };
        onStepChanged();

        final sw = Stopwatch()..start();
        try {
          final res = await actions.detail(
            rule,
            candidateDetailUrl,
            item: candidateDetailItem,
          );
          // 在途期间被中止 / 被新一轮顶替：结果作废，不写入阶段状态
          if (isStale()) return;
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.rawResponse = res;
          step.formattedJson = RuleTestReport.formatJson(res);

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
          if (isStale()) return;
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.status = RuleTestStepStatus.failed;
          step.errorMessage = e.toString();
          step.summary = '详情页执行异常: $e';
        }
      }
      onStepChanged();
    }

    // ----------------------------------------------------
    // 阶段 4: 直链解析/正文提取测试 (Parse)
    // ----------------------------------------------------
    if (!isStale()) {
      final step = steps[3];
      if (candidateChapterUrl == null || candidateChapterUrl.isEmpty) {
        step.status = RuleTestStepStatus.skipped;
        step.summary = '前置详情阶段未获取到有效分集或章节 URL，已跳过直链解析测试';
      } else {
        step.status = RuleTestStepStatus.running;
        step.requestParams = {
          'url': candidateChapterUrl,
          'baseUrl': rule.baseUrl,
        };
        onStepChanged();

        final sw = Stopwatch()..start();
        try {
          final res = await actions.parse(rule, candidateChapterUrl);
          // 在途期间被中止 / 被新一轮顶替：结果作废，不写入阶段状态
          if (isStale()) return;
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.rawResponse = res;
          step.formattedJson = RuleTestReport.formatJson(res);

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
          if (isStale()) return;
          sw.stop();
          step.elapsedMs = sw.elapsedMilliseconds;
          step.status = RuleTestStepStatus.failed;
          step.errorMessage = e.toString();
          step.summary = '解析直链/正文动作抛出异常: $e';
        }
      }
      onStepChanged();
    }

    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule: ${rule.name}',
      message: '====== 规则四阶段自动化调试执行结束 ======',
    );
  }
}
