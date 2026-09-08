import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_card.dart';
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

  /// 弹出底部快捷工具抽屉
  void _showActionMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(
                  icon: Icons.refresh_rounded,
                  label: '刷新',
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(ctx);
                    _controller.reload();
                  },
                ),
                _buildActionButton(
                  icon: Icons.open_in_browser_rounded,
                  label: '浏览器打开',
                  isDark: isDark,
                  onTap: () {
                    Navigator.pop(ctx);
                    launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
                  },
                ),
                _buildActionButton(
                  icon: LucideIcons.copy,
                  label: '复制链接',
                  isDark: isDark,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final currentUrl = await _controller.currentUrl();
                    if (currentUrl != null) {
                      await Clipboard.setData(ClipboardData(text: currentUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制网页链接至剪贴板')),
                        );
                      }
                    }
                  },
                ),
              ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppCard(
              padding: const EdgeInsets.all(12),
              borderRadius: 12,
              showShadow: false,
              child: Icon(icon, size: 24, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_canGoBack) {
          _controller.goBack();
        } else {
          context.pop();
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
            onPressed: () {
              if (_canGoBack) {
                _controller.goBack();
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
