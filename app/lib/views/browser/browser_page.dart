import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_colors.dart';
import 'adblock_engine.dart';

/// 现代化内置聚合浏览器页面
/// 
/// 支持多媒体自动播放、全屏适配、广告拦截与快捷操作面板
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.url,
    this.title,
    this.enableAdBlock = true,
  });

  /// 目标网页链接
  final String url;

  /// 页面标题 (未指定时动态获取 document.title)
  final String? title;

  /// 是否启用广告拦截
  final bool enableAdBlock;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController _controller;
  String _title = '';
  bool _canGoBack = false;
  double _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    _title = widget.title ?? '';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            _controller.canGoBack().then((value) {
              if (mounted) {
                setState(() {
                  _canGoBack = value;
                });
              }
            });
          },
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadProgress = progress / 100.0;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _loadProgress = 0.1;
              });
            }
            _fetchDocumentTitle();
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _loadProgress = 1.0;
              });
            }
            _fetchDocumentTitle();
            _controller.canGoBack().then((value) {
              if (mounted) {
                setState(() {
                  _canGoBack = value;
                });
              }
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // 如果启用了广告拦截引擎
            if (widget.enableAdBlock && AdBlockEngine.instance.shouldBlock(request.url)) {
              debugPrint('【广告拦截】拦截网址: ${request.url}');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    _setupAndroidFullscreen();
  }

  /// 配置 Android 平台全屏媒体播放回调
  void _setupAndroidFullscreen() {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget widget, OnHideCustomWidgetCallback callback) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => widget,
              fullscreenDialog: true,
            ),
          );
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        },
        onHideCustomWidget: () {
          Navigator.of(context).pop();
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        },
      );
    }
  }

  /// 动态提取网页实际标题
  void _fetchDocumentTitle() {
    _controller.getTitle().then((val) {
      if (mounted && val != null && val.isNotEmpty) {
        setState(() {
          _title = val;
        });
      }
    });
  }

  /// 弹出底部磨砂玻璃操作抽屉 (方案 A：底部抽屉 + 顶部居中药丸拖拽句柄条)
  void _showActionMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A).withValues(alpha: 0.82)
                    : const Color(0xFFF1F5F9).withValues(alpha: 0.88),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.80),
                    width: 0.8,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 顶部居中药丸拖拽句柄条 (Drag Handle)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 12),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.28)
                              : Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 页面当前信息简报
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.globe,
                            size: 13,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _title.isNotEmpty ? _title : widget.url,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextTertiary
                                    : AppColors.lightTextTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 快捷功能操作按键组
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: LucideIcons.rotateCw,
                            label: '刷新页面',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(ctx);
                              _controller.reload();
                            },
                          ),
                          _buildActionButton(
                            icon: LucideIcons.copy,
                            label: '复制链接',
                            isDark: isDark,
                            onTap: () async {
                              Navigator.pop(ctx);
                              final currentUrl =
                                  await _controller.currentUrl() ?? widget.url;
                              await Clipboard.setData(
                                ClipboardData(text: currentUrl),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已复制网页链接至剪贴板'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                          ),
                          _buildActionButton(
                            icon: LucideIcons.externalLink,
                            label: '浏览器打开',
                            isDark: isDark,
                            onTap: () async {
                              Navigator.pop(ctx);
                              final currentUrl =
                                  await _controller.currentUrl() ?? widget.url;
                              launchUrl(
                                Uri.parse(currentUrl),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 底部取消按钮 (纯白浮动实体卡片质感)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Container(
                        width: double.infinity,
                        height: 46,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFE2E8F0),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(ctx),
                            child: Center(
                              child: Text(
                                '取消',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final cardBgColor =
        isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);
    final iconColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B);
    final labelColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF475569);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primary.withValues(alpha: 0.16),
        highlightColor: AppColors.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cardBorderColor,
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(icon, size: 22, color: iconColor),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // 当网页无法再在内部后退时，允许系统/导航器直接出栈退出本页面，支持原生侧滑返回手势
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        // 若系统或上一级已经成功出栈，直接退出，避免重入和双重 pop
        if (didPop) return;

        // 若网页内部还有上一级历史记录，则优先在网页内部后退
        if (_canGoBack) {
          await _controller.goBack();
          final can = await _controller.canGoBack();
          if (mounted) {
            setState(() {
              _canGoBack = can;
            });
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _title.isEmpty ? '网页浏览' : _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () async {
              if (_canGoBack) {
                await _controller.goBack();
                final can = await _controller.canGoBack();
                if (mounted) {
                  setState(() {
                    _canGoBack = can;
                  });
                }
              } else {
                context.pop();
              }
            },
          ),
          actions: [
            if (_canGoBack)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.pop(),
              ),
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () => _showActionMenu(context, isDark),
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loadProgress < 1.0)
              LinearProgressIndicator(
                value: _loadProgress,
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
    );
  }
}
