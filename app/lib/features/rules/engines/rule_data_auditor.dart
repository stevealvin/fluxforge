import 'package:fluxforge/features/rules/models/rule_data_audit.dart';

/// 规则返回值的数据体检（纯逻辑，无状态，可纯 Dart 单测）
///
/// 补上一个长期缺口：规则测试此前只检查**首项**字段（`title` / `url` / `cover`），
/// 于是「20 条里有 3 条缺封面」「链接是相对路径」这类问题在测试页上完全看不出。
/// 本类对**全量条目**统计字段覆盖，并把 `docs/RULE_SPECIFICATION.md` 里
/// 可自动判定的约定变成断言。
///
/// 设计原则：**宁可漏报，不可误报**。规则源五花八门，把不确定的东西标成失败，
/// 只会让开发者对体检结果失去信任，反而不看它了。
class RuleDataAuditor {
  const RuleDataAuditor._();

  /// 参与体检的字段（顺序即展示顺序）
  static const List<String> defaultFields = ['title', 'url', 'cover', 'desc'];

  /// 统计各字段在一组条目里的覆盖情况
  static List<FieldCoverage> coverageOf(
    List<dynamic> items, {
    List<String> fields = defaultFields,
  }) {
    if (items.isEmpty) return const [];
    return [
      for (final field in fields)
        FieldCoverage(
          field: field,
          present: items.where((item) => stringOf(item, field).isNotEmpty).length,
          total: items.length,
        ),
    ];
  }

  /// 契约检查
  ///
  /// [hasMore] 传入 undefined（null）表示该阶段没有分页语义，跳过相关检查。
  static List<ContractCheck> contractChecks({
    required List<dynamic> items,
    List<dynamic>? tabs,
    bool? hasMore,
  }) {
    final checks = <ContractCheck>[];

    // 1. 条目链接必须是绝对地址：相对路径在跳详情时必然失败，
    //    而现在只有到用户点进去才会暴露
    if (items.isNotEmpty) {
      final withUrl = items
          .map((item) => stringOf(item, 'url'))
          .where((url) => url.isNotEmpty)
          .toList();
      if (withUrl.isNotEmpty) {
        final relative = withUrl.where((url) => !_isAbsolute(url)).length;
        checks.add(
          ContractCheck(
            name: '链接为绝对地址',
            level: relative == 0
                ? AuditLevel.ok
                : (relative == withUrl.length ? AuditLevel.fail : AuditLevel.warn),
            detail: relative == 0
                ? '${withUrl.length} 条链接均为绝对地址'
                : '${withUrl.length} 条中有 $relative 条为相对路径，跳详情会失败',
          ),
        );
      }
    }

    // 2. 分类页签的结构完整性：tabs 是 discovery 契约的核心，
    //    缺 url 的分类点击后无法回传 tab 参数
    if (tabs != null && tabs.isNotEmpty) {
      var missingTitle = 0;
      var missingUrl = 0;
      for (final tab in tabs) {
        if (stringOf(tab, 'title').isEmpty) missingTitle++;
        if (stringOf(tab, 'url').isEmpty) missingUrl++;
      }
      final broken = missingTitle + missingUrl;
      checks.add(
        ContractCheck(
          name: '分类页签结构完整',
          level: broken == 0
              ? AuditLevel.ok
              : (missingUrl == tabs.length ? AuditLevel.fail : AuditLevel.warn),
          detail: broken == 0
              ? '${tabs.length} 个分类的 title / url 均齐备'
              : '${tabs.length} 个分类中：缺 title $missingTitle 个、缺 url $missingUrl 个',
        ),
      );
    }

    // 3. hasMore 与条目数自洽：声明还有下一页却没返回任何条目，
    //    会让上滑加载陷入空轮询
    if (hasMore != null) {
      final inconsistent = hasMore && items.isEmpty;
      checks.add(
        ContractCheck(
          name: 'hasMore 与条目数自洽',
          level: inconsistent ? AuditLevel.warn : AuditLevel.ok,
          detail: inconsistent
              ? '声明 hasMore=true 但本页未返回任何条目，会导致空轮询'
              : 'hasMore=$hasMore 与本页 ${items.length} 条一致',
        ),
      );
    }

    return checks;
  }

  /// 安全取字符串字段（非 String 类型转成字符串，null / 空白一律视为缺失）
  static String stringOf(dynamic item, String field) {
    if (item is! Map) return '';
    final value = item[field];
    if (value == null) return '';
    return value.toString().trim();
  }

  static bool _isAbsolute(String url) {
    if (url.startsWith('//')) return true; // 协议相对地址，多数场景可用
    final uri = Uri.tryParse(url);
    return uri != null && uri.isAbsolute;
  }
}
