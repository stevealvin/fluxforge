import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// `RuleService.matchByUrl`：按 baseUrl 反查，优先启用中的规则
void main() {
  test('按 baseUrl 反查，且优先返回启用中的规则', () async {
    final service = RuleService();
    await service.saveRules([
      Rule(
        id: 1,
        name: '已禁用的同站规则',
        baseUrl: 'https://site.com',
        type: 'comic',
        code: '// noop',
        enabled: false,
      ),
      Rule(
        id: 2,
        name: '启用中的同站规则',
        baseUrl: 'https://site.com',
        type: 'comic',
        code: '// noop',
      ),
      Rule(
        id: 3,
        name: '别的站',
        baseUrl: 'https://other.com',
        type: 'video',
        code: '// noop',
      ),
    ]);

    expect(service.matchByUrl('https://site.com/detail/1')?.id, 2);
    expect(service.matchByUrl('https://other.com/d/1')?.id, 3);
    expect(service.matchByUrl('https://unknown.com/d/1'), isNull);
    expect(service.matchByUrl(''), isNull);
  });

  test('启用中的规则都不匹配时，才回退到被禁用的同站规则', () async {
    final service = RuleService();
    await service.saveRules([
      Rule(
        id: 9,
        name: '唯一但被禁用',
        baseUrl: 'https://only.com',
        type: 'comic',
        code: '// noop',
        enabled: false,
      ),
    ]);

    expect(service.matchByUrl('https://only.com/d/1')?.id, 9);
  });
}
