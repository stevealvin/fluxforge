import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/features/rules/engines/rule_data_auditor.dart';
import 'package:fluxforge/features/rules/models/rule_data_audit.dart';

/// 规则返回值的数据体检（纯逻辑）
///
/// 守两条契约：
/// 1. **统计是全量的** —— 只检查首项时，「20 条里 3 条缺封面」在页面上完全看不出来；
/// 2. **宁可漏报不可误报** —— 规则源千奇百怪，把不确定的判成失败，
///    只会让开发者不再相信体检结果，反而不看它了。
void main() {
  group('coverageOf（字段覆盖）', () {
    test('统计全量条目，而不是只看首项', () {
      final items = [
        {'title': 'A', 'url': 'https://a.com/1', 'cover': 'https://a.com/1.jpg'},
        {'title': 'B', 'url': 'https://a.com/2'}, // 缺 cover
        {'title': 'C', 'url': 'https://a.com/3'}, // 缺 cover
      ];

      final cover = RuleDataAuditor.coverageOf(
        items,
      ).firstWhere((c) => c.field == 'cover');

      expect(cover.present, 1, reason: '首项有封面，但另有两条缺失');
      expect(cover.total, 3);
      expect(cover.label, '1/3');
      expect(cover.level, AuditLevel.warn);
    });

    test('空列表不产生任何统计', () {
      expect(RuleDataAuditor.coverageOf(const []), isEmpty);
    });

    test('全员有值 → ok；一个都没有 → fail（通常是字段名写错）', () {
      final items = [
        {'title': 'A'},
        {'title': 'B'},
      ];

      final coverages = RuleDataAuditor.coverageOf(items);
      expect(
        coverages.firstWhere((c) => c.field == 'title').level,
        AuditLevel.ok,
      );
      expect(
        coverages.firstWhere((c) => c.field == 'cover').level,
        AuditLevel.fail,
      );
    });

    test('空白字符串视为缺失', () {
      final items = [
        {'title': 'A'},
        {'title': '   '},
      ];

      expect(
        RuleDataAuditor.coverageOf(
          items,
        ).firstWhere((c) => c.field == 'title').present,
        1,
      );
    });
  });

  group('contractChecks（契约检查）', () {
    test('相对路径链接被判为问题', () {
      final items = [
        {'url': 'https://a.com/1'},
        {'url': '/detail/2'},
      ];

      final check = RuleDataAuditor.contractChecks(items: items).first;

      expect(check.name, '链接为绝对地址');
      expect(check.level, AuditLevel.warn);
      expect(check.detail, contains('1 条'));
    });

    test('全部是相对路径 → fail（规则基本不可用）', () {
      final items = [
        {'url': '/a'},
        {'url': '/b'},
      ];

      expect(
        RuleDataAuditor.contractChecks(items: items).first.level,
        AuditLevel.fail,
      );
    });

    test('tabs 缺 url 会被单独报出', () {
      final tabs = [
        {'title': '推荐', 'url': '/hot'},
        {'title': '电影'},
      ];

      final check = RuleDataAuditor.contractChecks(
        items: const [],
        tabs: tabs,
      ).firstWhere((c) => c.name == '分类页签结构完整');

      expect(check.level, AuditLevel.warn);
      expect(check.detail, contains('缺 url 1 个'));
    });

    test('hasMore 为真却零条目 → 提示空轮询', () {
      final check = RuleDataAuditor.contractChecks(
        items: const [],
        hasMore: true,
      ).firstWhere((c) => c.name == 'hasMore 与条目数自洽');

      expect(check.level, AuditLevel.warn);
    });

    test('没有分页语义时不报 hasMore（宁可漏报，不可误报）', () {
      final checks = RuleDataAuditor.contractChecks(
        items: [
          {'url': 'https://a.com/1'},
        ],
      );

      expect(checks.any((c) => c.name.contains('hasMore')), isFalse);
    });
  });

  group('auditWorstOf（级别汇总）', () {
    test('任一 fail 即 fail，否则任一 warn 即 warn', () {
      expect(auditWorstOf(const [AuditLevel.ok, AuditLevel.ok]), AuditLevel.ok);
      expect(
        auditWorstOf(const [AuditLevel.ok, AuditLevel.warn]),
        AuditLevel.warn,
      );
      expect(
        auditWorstOf(const [AuditLevel.warn, AuditLevel.fail, AuditLevel.ok]),
        AuditLevel.fail,
      );
      expect(auditWorstOf(const []), AuditLevel.ok);
    });
  });
}
