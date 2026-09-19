import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/sites/site_store.dart';
import 'package:fluxforge/features/sites/widgets/site_sheets.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 站点页：管理用户自建的网站入口，点击即用内置浏览器打开
///
/// 与「发现」的区别：发现是规则源驱动的媒体内容浏览，站点是用户手动添加的
/// 任意网站入口（含广告拦截与手势能力的内置浏览器承载打开动作）。
class SitesPage extends StatefulWidget {
  const SitesPage({super.key});

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  final SiteStore _store = siteStore;

  void _openSite(SiteEntry entry) {
    HapticFeedback.lightImpact();
    context.pushBrowser(url: entry.url, title: entry.name);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('站点', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: '添加站点',
            icon: const Icon(Ionicons.addOutline, size: 22),
            onPressed: () => showSiteEditorSheet(context, _store),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ValueListenableBuilder<List<SiteEntry>>(
        valueListenable: _store.sitesNotifier,
        builder: (context, sites, _) {
          if (sites.isEmpty) return _buildEmptyState(isDark);

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // 略高于宽度：为「图标 + 名称 + 域名」三行内容留余量，兼顾系统字体放大
              childAspectRatio: 0.92,
            ),
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final entry = sites[index];
              final host = Uri.tryParse(entry.url)?.host ?? entry.url;

              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                borderRadius: 14,
                // 无底色、无边框、无阴影：站点项直接浮在页面背景上，
                // 仅保留 AppCard 的点击水波与按压缩放反馈
                color: Colors.transparent,
                showBorder: false,
                showShadow: false,
                onTap: () => _openSite(entry),
                onLongPress: () => showSiteActionsSheet(context, _store, entry),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Ionicons.globeOutline,
                          size: 24, color: AppColors.primary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 空态引导：说明站点用途并给出添加入口
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Ionicons.globeOutline,
              size: 44,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
            const SizedBox(height: 14),
            const Text(
              '还没有站点',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '添加常用网站，点击即可用内置浏览器打开\n自带广告拦截与手势操作',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => showSiteEditorSheet(context, _store),
              icon: const Icon(Ionicons.addOutline, size: 18),
              label: const Text('添加站点'),
            ),
          ],
        ),
      ),
    );
  }
}
