import 'package:material_ui/material_ui.dart';

/// FluxForge (流光视界) 统一调色板与语义颜色规范
/// 基于极光幽绿品牌主色，融合纯净星暮白与曜夜极光翡翠现代双主题
class AppColors {
  AppColors._();

  // ==================== 核心品牌色 (极光翡翠) ====================
  /// 品牌主色 (幽绿)
  static const Color primary = Color(0xFF059669); // Emerald 600
  /// 品牌浅辉色 (极光绿)
  static const Color primaryLight = Color(0xFF10B981); // Emerald 500
  /// 品牌深色 (暗夜幽绿)
  static const Color primaryDark = Color(0xFF047857); // Emerald 700
  /// 品牌荧光绿 (高光点缀)
  static const Color primaryGlow = Color(0xFF34D399); // Emerald 400

  // ==================== 辅助色 (科技潮流) ====================
  /// 辅助科技蓝 (算力与链接)
  static const Color accentBlue = Color(0xFF0EA5E9); // Sky 500
  /// 辅助紫罗兰 (多媒体与沙箱)
  static const Color accentPurple = Color(0xFF8B5CF6); // Violet 500
  /// 辅助琥珀橙 (灵感与发现)
  static const Color accentAmber = Color(0xFFF59E0B); // Amber 500
  /// 辅助极光青绿
  static const Color accentTeal = Color(0xFF14B8A6); // Teal 500

  // ==================== 状态语义色 ====================
  /// 成功状态色
  static const Color success = Color(0xFF10B981); // Emerald 500
  /// 警告状态色
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  /// 危险/错误状态色
  static const Color danger = Color(0xFFEF4444); // Red 500
  /// 提示信息色
  static const Color info = Color(0xFF3B82F6); // Blue 500

  // ==================== 浅色模式 (纯净星暮白) ====================
  /// 浅色全局背景
  static const Color lightBg = Color(0xFFF8FAFC); // Slate 50
  /// 浅色表面面板底色
  static const Color lightSurface = Colors.white;
  /// 浅色卡片底色
  static const Color lightCard = Color(0xFFFFFFFF);
  /// 浅色卡片微边框
  static const Color lightCardBorder = Color(0xFFE2E8F0); // Slate 200
  /// 浅色卡片微边框别名
  static const Color lightBorder = lightCardBorder;
  /// 浅色主文本
  static const Color lightTextPrimary = Color(0xFF0F172A); // Slate 900
  /// 浅色次级文本
  static const Color lightTextSecondary = Color(0xFF64748B); // Slate 500
  /// 浅色占位弱文本
  static const Color lightTextTertiary = Color(0xFF94A3B8); // Slate 400
  /// 浅色占位弱文本别名
  static const Color lightTextMuted = lightTextTertiary;

  // ==================== 深色模式 (曜夜极光翡翠) ====================
  /// 深色全局背景
  static const Color darkBg = Color(0xFF0A0D14); // 超深暗夜
  /// 深色表面面板底色
  static const Color darkSurface = Color(0xFF111827); // Gray 900
  /// 深色卡片底色
  static const Color darkCard = Color(0xFF151C2C); // 带有极微弱幽蓝的深灰
  /// 深色卡片微光边框
  static const Color darkCardBorder = Color(0xFF1E293B); // Slate 800
  /// 深色卡片微光边框别名
  static const Color darkBorder = darkCardBorder;
  /// 深色主文本
  static const Color darkTextPrimary = Color(0xFFF8FAFC); // Slate 50
  /// 深色次级文本
  static const Color darkTextSecondary = Color(0xFF94A3B8); // Slate 400
  /// 深色占位弱文本
  static const Color darkTextTertiary = Color(0xFF64748B); // Slate 500
  /// 深色占位弱文本别名
  static const Color darkTextMuted = darkTextTertiary;
}
