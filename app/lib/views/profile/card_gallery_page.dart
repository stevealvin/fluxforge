import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../services/di.dart';
import '../../widgets/app_card.dart';

/// AppCard 设计系统视觉全量展廊页面
///
/// 集中展示 FluxForge 全局统一卡片组件的所有构造形态、交互手感与应用场景
class CardGalleryPage extends StatefulWidget {
  const CardGalleryPage({super.key});

  @override
  State<CardGalleryPage> createState() => _CardGalleryPageState();
}

class _CardGalleryPageState extends State<CardGalleryPage> {
  int _interactiveClickCount = 0;
  int _pressScaleClickCount = 0;
  String _selectedOutlinedTab = '全部规则';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        title: Text(
          '卡片组件设计体系 (AppCard)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            LucideIcons.arrowLeft,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '切换主题预览效果',
            icon: Icon(
              isDark ? LucideIcons.sun : LucideIcons.moon,
              color: AppColors.primary,
            ),
            onPressed: () {
              appService.toggleThemeMode(currentIsDark: isDark);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 顶部介绍横幅
          _buildBanner(isDark),
          const SizedBox(height: 20),

          // 1. 四大核心形态
          _buildSectionHeader('1. 四大核心卡片构造形态', LucideIcons.layoutGrid, isDark),
          const SizedBox(height: 12),
          _buildTypeStandard(isDark),
          const SizedBox(height: 12),
          _buildTypeFlat(isDark),
          const SizedBox(height: 12),
          _buildTypeOutlined(isDark),
          const SizedBox(height: 12),
          _buildTypeGradient(isDark),
          const SizedBox(height: 24),

          // 2. 交互手感与物理反馈
          _buildSectionHeader('2. 交互手感与按压微缩反馈', LucideIcons.mousePointerClick, isDark),
          const SizedBox(height: 12),
          _buildInteractionDemos(isDark),
          const SizedBox(height: 24),

          // 3. 真实业务场景模板
          _buildSectionHeader('3. 真实业务场景模板', LucideIcons.sparkles, isDark),
          const SizedBox(height: 12),
          _buildMetricsScenario(isDark),
          const SizedBox(height: 12),
          _buildMediaPosterScenario(isDark),
          const SizedBox(height: 12),
          _buildOutlinedChipsScenario(isDark),
          const SizedBox(height: 24),

          // 4. 圆角与边框自定义
          _buildSectionHeader('4. 圆角与边框自由定制', LucideIcons.squareDashed, isDark),
          const SizedBox(height: 12),
          _buildRadiusDemos(isDark),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  /// 顶部横幅
  Widget _buildBanner(bool isDark) {
    return AppCard.gradient(
      borderRadius: 18,
      gradient: LinearGradient(
        colors: isDark
            ? [
                AppColors.primaryDark.withValues(alpha: 0.7),
                const Color(0xFF0F2B22),
              ]
            : [
                AppColors.primary.withValues(alpha: 0.12),
                AppColors.accentTeal.withValues(alpha: 0.06),
              ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.layers,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '全局统一现代卡片规范',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '支持 Standard、Flat、Outlined、Gradient 等多种形态，内置微光边框、微阴影、严格圆角防溢出水波与弹性微缩。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 分组标题
  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
      ],
    );
  }

  /// 1.1 标准卡片
  Widget _buildTypeStandard(bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AppCard()',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '标准卡片 (默认)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const Spacer(),
              Icon(
                LucideIcons.sparkle,
                size: 14,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '自带 16px 圆角、主题自适应微阴影 (BoxShadow) 与柔和微光边框 (0.8px)。常用于规则列表、设置分组卡片与主看板。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 1.2 纯净平铺卡片
  Widget _buildTypeFlat(bool isDark) {
    return AppCard.flat(
      color: isDark
          ? const Color(0xFF1E2638)
          : const Color(0xFFEFF3F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AppCard.flat()',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '纯净平铺态卡片 (Flat)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '无微边框 (showBorder=false)、无阴影 (showShadow=false)，纯净色块平铺。适合次级内嵌面板、深色高密度列表容器或无凸起卡片需求。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 1.3 描边弱底色卡片
  Widget _buildTypeOutlined(bool isDark) {
    return AppCard.outlined(
      borderColor: isDark
          ? AppColors.primary.withValues(alpha: 0.4)
          : AppColors.primary.withValues(alpha: 0.35),
      borderWidth: 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AppCard.outlined()',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentAmber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '描边弱底态卡片 (Outlined)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '透明/弱底色、保留微边框、0 阴影。适合筛选标签、次级配置、轻量线框分组与表单外围包装。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 1.4 流光渐变卡片
  Widget _buildTypeGradient(bool isDark) {
    return AppCard.gradient(
      borderRadius: 18,
      gradient: const LinearGradient(
        colors: [
          Color(0xFF0D9488),
          Color(0xFF059669),
          Color(0xFF10B981),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AppCard.gradient()',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '流光渐变高光卡片 (Gradient)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              const Icon(
                LucideIcons.crown,
                size: 16,
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '支持自定义多色阶线性渐变与微阴影，视觉层次丰富吸睛。用于 Hero 顶流概览、VIP 特权看板与核心公告。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  /// 2. 交互演示
  Widget _buildInteractionDemos(bool isDark) {
    return Row(
      children: [
        // 普通水波纹
        Expanded(
          child: AppCard(
            onTap: () {
              setState(() {
                _interactiveClickCount++;
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.hand, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '标准水波纹',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '防溢出 InkWell',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '点击: $_interactiveClickCount 次',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // 弹性微缩
        Expanded(
          child: AppCard(
            enablePressScale: true,
            onTap: () {
              setState(() {
                _pressScaleClickCount++;
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.sparkles, size: 16, color: AppColors.accentPurple),
                    const SizedBox(width: 6),
                    Text(
                      '弹性微缩按压',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '0.98x 物理微缩质感',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '按压: $_pressScaleClickCount 次',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentPurple,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 3.1 真实业务场景：指标统计卡片
  Widget _buildMetricsScenario(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: AppCard(
            enablePressScale: true,
            onTap: () {},
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.codeXml, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '128 条',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      Text(
                        '本地解析规则',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppCard(
            enablePressScale: true,
            onTap: () {},
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.zap, color: AppColors.accentBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '42 ms',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      Text(
                        '沙箱平均响应',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 3.2 真实业务场景：媒体图文卡片
  Widget _buildMediaPosterScenario(bool isDark) {
    return AppCard(
      enablePressScale: true,
      onTap: () {},
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    LucideIcons.clapperboard,
                    size: 40,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '4K 超清',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '流光剧场 · 极速多源影音专区',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '展示卡片容器结合头部媒体、胶囊标签与底部图文的最佳实践排版。',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 3.3 真实业务场景：Outlined 标签筛选行
  Widget _buildOutlinedChipsScenario(bool isDark) {
    final tabs = ['全部规则', '视频影音', '小说阅读', '图片动漫', '插件工具'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedOutlinedTab == tab;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppCard.outlined(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              borderRadius: 20,
              color: isSelected
                  ? (isDark ? AppColors.primary.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.1))
                  : Colors.transparent,
              borderColor: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
              onTap: () {
                setState(() {
                  _selectedOutlinedTab = tab;
                });
              },
              child: Text(
                tab,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 4. 圆角形态展示
  Widget _buildRadiusDemos(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: AppCard(
            borderRadius: 8,
            padding: const EdgeInsets.all(10),
            child: Center(
              child: Text(
                '8px 紧凑圆角',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppCard(
            borderRadius: 16,
            padding: const EdgeInsets.all(10),
            child: Center(
              child: Text(
                '16px 标准圆角',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(10),
            child: Center(
              child: Text(
                '24px 柔和圆角',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
