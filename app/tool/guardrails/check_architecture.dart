// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// FluxForge 架构门禁脚本（纯 dart:io，零第三方依赖）
///
/// 用法：
/// ```bash
/// dart run tool/guardrails/check_architecture.dart            # 校验（违规则 exit 1）
/// dart run tool/guardrails/check_architecture.dart --update    # 重写存量白名单基线
/// ```
///
/// 四条硬性规则（本文件即为这些约束的唯一可执行出处）：
/// 1. `lib/domain/**` 严禁出现任何 Flutter 依赖（domain 层必须与 UI 框架彻底解耦）；
/// 2. `lib/shared/**` 严禁反向依赖 `lib/features/**`（依赖只能单向向下流动）；
/// 3. `lib/` 下的 UI 文件（含 Widget 或位于 pages/ widgets/ views/）不得超过 300 行；
/// 4. 存量超大文件登记在 `baseline.txt` 白名单中，随重构推进必须逐条销账，严禁新增。
const int kMaxUiFileLines = 300;

const String kBaselinePath = 'tool/guardrails/baseline.txt';

/// 判定为 Flutter 依赖的 import 关键字
const List<String> kFlutterImports = [
  'package:flutter/',
  'package:material_ui/',
  'package:go_router/',
  'package:ionicons/',
  'dart:ui',
];

void main(List<String> args) {
  final updateBaseline = args.contains('--update');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('❌ 未找到 lib/ 目录，请在 app/ 根目录下运行本脚本');
    exit(2);
  }

  final baseline = _loadBaseline();
  final violations = <String>[];
  final oversizedFiles = <String>[];

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in dartFiles) {
    final rel = _relative(file.path);
    final source = file.readAsStringSync();
    // 使用 LineSplitter 而非 split('\n')：自动兼容 \r\n 且不产生末尾空行计数偏差
    final lines = const LineSplitter().convert(source).length;

    // 规则 1：domain 层零 Flutter 依赖
    if (_isUnder(rel, 'domain')) {
      for (final keyword in kFlutterImports) {
        if (source.contains(keyword)) {
          violations.add('[domain 层禁止 Flutter 依赖] $rel 引入了 $keyword');
        }
      }
    }

    // 规则 2：shared 层禁止反向依赖 features
    if (_isUnder(rel, 'shared')) {
      final matches = RegExp(r"package:fluxforge/features/[\w/]+\.dart")
          .allMatches(source)
          .map((m) => m.group(0)!)
          .toSet();
      for (final match in matches) {
        violations.add('[shared 层禁止反向依赖 features] $rel 引入了 $match');
      }
    }

    // 规则 3：UI 文件行数上限
    if (_isUiFile(rel, source) && lines > kMaxUiFileLines) {
      oversizedFiles.add(rel);
      if (!baseline.contains(rel)) {
        violations.add(
          '[UI 文件超长] $rel 共 $lines 行，超过 $kMaxUiFileLines 行上限，请按 ADR 拆分为 引擎/控制器/组件',
        );
      }
    }
  }

  if (updateBaseline) {
    _writeBaseline(oversizedFiles);
    print('✅ 已更新白名单基线（$kBaselinePath），登记 ${oversizedFiles.length} 个存量超大文件');
    return;
  }

  // 白名单中已销账的文件：提示可移除，但不阻断 CI
  final resolved = baseline.where((p) => !oversizedFiles.contains(p)).toList();
  if (resolved.isNotEmpty) {
    print('ℹ️  以下文件已销账，建议从 $kBaselinePath 中移除：');
    for (final p in resolved) {
      print('   - $p');
    }
  }

  if (violations.isEmpty) {
    print('✅ 架构门禁通过：domain 无 Flutter 依赖 / shared 无反向依赖 / 无新增超长 UI 文件');
    return;
  }

  stderr.writeln('❌ 架构门禁失败，共 ${violations.length} 项违规：');
  for (final v in violations) {
    stderr.writeln('   - $v');
  }
  exit(1);
}

/// 相对 lib/ 的路径（统一使用 / 分隔，便于跨平台比对）
String _relative(String path) => path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^lib/'), '');

/// 判断相对路径是否位于指定一级目录下
bool _isUnder(String rel, String dir) => rel.startsWith('$dir/');

/// 是否为 UI 文件：位于 pages / widgets / views 目录，或源码中定义了 Widget
bool _isUiFile(String rel, String source) {
  if (rel.contains('/pages/') || rel.contains('/widgets/') || rel.contains('/views/')) {
    return true;
  }
  return source.contains('extends StatelessWidget') ||
      source.contains('extends StatefulWidget');
}

/// 读取白名单基线（不存在时视为空）
Set<String> _loadBaseline() {
  final file = File(kBaselinePath);
  if (!file.existsSync()) return <String>{};
  return file
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();
}

/// 重写白名单基线（保持注释头，随后按路径排序写入）
void _writeBaseline(List<String> paths) {
  final sorted = [...paths]..sort();
  File(kBaselinePath).writeAsStringSync('''
# FluxForge 架构门禁 —— 存量超长 UI 文件白名单
#
# 本文件由 `dart run tool/guardrails/check_architecture.dart --update` 生成，
# 仅用于登记「重构启动前就已存在」的技术债，属于待销账清单而非豁免金牌。
# 每完成一个文件的拆分，请手动删除对应行，让门禁持续收紧。
${sorted.join('\n')}
''');
}
