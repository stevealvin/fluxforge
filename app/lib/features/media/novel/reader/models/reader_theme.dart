import 'package:material_ui/material_ui.dart';

/// 护眼阅读配色方案
///
/// 说明：本类型含 `Color`，依赖 Flutter，因此属于「UI 模型」，
/// 按架构约定留在 feature 内（`reader/models/`），不得上提到 `domain/`。
enum ReaderTheme {
  parchment(
    name: '羊皮复古',
    bg: Color(0xFFF6F1E7),
    text: Color(0xFF3B2F1D),
    subText: Color(0xFF7A6B58),
  ),
  bamboo(
    name: '豆沙护眼',
    bg: Color(0xFFE4EDE1),
    text: Color(0xFF1D2E1A),
    subText: Color(0xFF536B50),
  ),
  night(
    name: '极夜深邃',
    bg: Color(0xFF0F141C),
    text: Color(0xFFA0ABC0),
    subText: Color(0xFF586377),
  ),
  porcelain(
    name: '纯净白瓷',
    bg: Color(0xFFFFFFFF),
    text: Color(0xFF1A202C),
    subText: Color(0xFF718096),
  );

  const ReaderTheme({
    required this.name,
    required this.bg,
    required this.text,
    required this.subText,
  });

  final String name;
  final Color bg;
  final Color text;
  final Color subText;
}
