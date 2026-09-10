import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_colors.dart';
import '../../services/di.dart';
import '../../widgets/app_button.dart';
import 'adblock_engine.dart';
import 'web_video_gesture_engine.dart';

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

  bool _isPromptingExternalLink = false;
  Widget? _customFullscreenWidget;
  OnHideCustomWidgetCallback? _onHideCustomWidgetCallback;




  bool get _isAdBlockActive =>
      widget.enableAdBlock && appService.settingsNotifier.value.enableAdBlock;

  @override
  void initState() {
    super.initState();
    _title = widget.title ?? '';

    // 若开启广告拦截，启动广告与弹窗拦截引擎
    if (_isAdBlockActive) {
      AdBlockEngine.instance.initialize();
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'FluxExternalLinkChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _promptExternalLink(message.message);
        },
      )
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

            // 尽早注入标准 Content Script (网络 Hook + 元素隐藏 + 防弹窗)
            if (_isAdBlockActive) {
              _controller
                  .runJavaScript(AdBlockEngine.instance.buildContentScriptForUrl(url))
                  .catchError((_) {});
            }

            // 尽早注入网页视频播放滑动手势引擎 (快进/快退 HUD 与倍速)
            _controller.runJavaScript(WebVideoGestureEngine.instance.buildVideoGestureScript()).catchError((_) {});
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _loadProgress = 1.0;
              });
            }
            _fetchDocumentTitle();

            // 页面加载完成后再次装配针对目标域名的专属 CSS 与 MutationObserver 动态清理
            if (_isAdBlockActive) {
              _controller
                  .runJavaScript(AdBlockEngine.instance.buildContentScriptForUrl(url))
                  .catchError((_) {});
            }

            // 页面完全加载后再次扫描，确保动态 DOM 视频节点挂载手势
            _controller.runJavaScript(WebVideoGestureEngine.instance.buildVideoGestureScript()).catchError((_) {});

            _controller.canGoBack().then((value) {
              if (mounted) {
                setState(() {
                  _canGoBack = value;
                });
              }
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            final uri = Uri.tryParse(url);
            final scheme = uri?.scheme.toLowerCase() ?? '';

            // 1. 拦截非 HTTP(S) 的外部应用跳转协议 (如 weixin://, alipays://, tbopen:// 等)
            if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
              if (scheme != 'about' && scheme != 'data' && scheme != 'blob' && scheme != 'javascript') {
                _promptExternalLink(url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            }

            // 2. 如果启用了广告拦截，且目标顶层页面命中了外部推广/广告重定向，提示用户是否跳转
            if (_isAdBlockActive && AdBlockEngine.instance.shouldBlock(url)) {
              debugPrint('【广告拦截】检测到外部重定向/推广链接，提示用户选择: $url');
              _promptExternalLink(url, isAdRedirect: true);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    _setupAndroidFullscreen();
  }

  /// 获取跳转协议或链接的友好应用展示名称
  String _getSchemeFriendlyName(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('alipays://') || lower.startsWith('alipay://')) {
      return '支付宝 (Alipay)';
    } else if (lower.startsWith('weixin://') || lower.startsWith('wechat://')) {
      return '微信 (WeChat)';
    } else if (lower.startsWith('tbopen://') || lower.startsWith('taobao://')) {
      return '手机淘宝 (Taobao)';
    } else if (lower.startsWith('snssdk1128://') || lower.startsWith('douyin://')) {
      return '抖音 (Douyin)';
    } else if (lower.startsWith('bilibili://')) {
      return '哔哩哔哩 (Bilibili)';
    } else if (lower.startsWith('zhihu://')) {
      return '知乎 (Zhihu)';
    } else if (lower.startsWith('baiduboxapp://')) {
      return '百度 App';
    } else if (lower.startsWith('openapp.jdmobile://') || lower.startsWith('jd://')) {
      return '京东 (JD)';
    } else if (lower.startsWith('pinduoduo://')) {
      return '拼多多 (Pinduoduo)';
    } else if (lower.startsWith('kwai://') || lower.startsWith('kuaishou://')) {
      return '快手 (Kuaishou)';
    } else if (lower.startsWith('youku://')) {
      return '优酷 (Youku)';
    } else if (lower.startsWith('iqiyi://')) {
      return '爱奇艺 (iQIYI)';
    } else if (lower.startsWith('tel:')) {
      return '系统电话拨号';
    } else if (lower.startsWith('mailto:')) {
      return '系统邮件客户端';
    }
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme;
    if (scheme != null && scheme.isNotEmpty) {
      return '外部应用 ($scheme)';
    }
    return '外部链接/应用';
  }

  /// 提示用户是否允许打开外部应用或跳转外链
  Future<void> _promptExternalLink(String url, {bool isAdRedirect = false}) async {
    if (!mounted || _isPromptingExternalLink) return;
    _isPromptingExternalLink = true;

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _isPromptingExternalLink = false;
      return;
    }

    final friendlyName = _getSchemeFriendlyName(url);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: (isAdRedirect ? AppColors.accentAmber : AppColors.primary).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isAdRedirect ? LucideIcons.shieldAlert : LucideIcons.externalLink,
                size: 20,
                color: isAdRedirect ? AppColors.accentAmber : AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isAdRedirect ? '检测到外部推广跳转' : '申请打开外部应用',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAdRedirect
                  ? '当前网页正在尝试重定向至外部推广网址，是否允许继续前往？'
                  : '当前网页申请离开当前浏览器，打开第三方应用：',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friendlyName,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    url,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消'),
          ),
          AppButton.compact(
            label: isAdRedirect ? '仍然前往' : '允许打开',
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );

    _isPromptingExternalLink = false;

    if (confirmed == true && mounted) {
      if (isAdRedirect) {
        _controller.loadRequest(uri);
      } else {
        try {
          final canLaunch = await canLaunchUrl(uri);
          if (canLaunch) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!launched && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('无法调起该应用，手机可能未安装 [$friendlyName]')),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('调起应用失败: $e')),
            );
          }
        }
      }
    }
  }

  /// 配置 Android 平台全屏媒体播放回调
  void _setupAndroidFullscreen() {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget widget, OnHideCustomWidgetCallback callback) {
          _onHideCustomWidgetCallback = callback;
          if (mounted) {
            setState(() {
              _customFullscreenWidget = widget;
            });
          }
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        },
        onHideCustomWidget: () {
          _exitFullscreen(notifyCallback: false);
        },
      );
    }
  }

  /// 退出媒体全屏模式并还原屏幕方向与沉浸态
  void _exitFullscreen({bool notifyCallback = true}) {
    if (_customFullscreenWidget != null) {
      if (notifyCallback) {
        try {
          _onHideCustomWidgetCallback?.call();
        } catch (_) {}
      }
      _onHideCustomWidgetCallback = null;
      if (mounted) {
        setState(() {
          _customFullscreenWidget = null;
        });
      } else {
        _customFullscreenWidget = null;
      }
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  /// 弹出底部磨砂玻璃操作抽屉 (4 宫格悬浮卡片阵列 + 广告拦截专属入口)
  /// 弹出底部磨砂玻璃操作抽屉 (4 宫格悬浮卡片阵列 + 广告拦截专属入口)
  void _showActionMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A).withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.78),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.8),
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
                              ? Colors.white.withValues(alpha: 0.22)
                              : Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 页面当前信息标题（去掉背景底色，纯净融入整体磨砂质感）
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.globe,
                              size: 13,
                              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _title.isNotEmpty ? _title : widget.url,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 快捷功能操作按键组 (4 宫格悬浮卡片)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: LucideIcons.rotateCw,
                            label: '刷新',
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
                            label: '浏览器',
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
                          _buildActionButton(
                            icon: LucideIcons.shieldCheck,
                            label: '广告拦截',
                            iconColor: _isAdBlockActive ? AppColors.primary : null,
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(ctx);
                              context.push('/adblock');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
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
    Color? iconColor,
  }) {
    final cardBgColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.65);
    final cardBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    final effectiveIconColor = iconColor ??
        (isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B));
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cardBorderColor,
                    width: 0.7,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(icon, size: 21, color: effectiveIconColor),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
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
  void dispose() {
    if (_customFullscreenWidget != null) {
      _exitFullscreen(notifyCallback: true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // 当处于全屏或网页还能在内部后退时，拦截系统出栈
      canPop: _customFullscreenWidget == null && !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        // 若系统或上一级已经成功出栈，直接退出，避免重入和双重 pop
        if (didPop) return;

        // 1. 若当前正处于全屏模式，优先退出全屏
        if (_customFullscreenWidget != null) {
          _exitFullscreen();
          return;
        }

        // 2. 若网页内部还有上一级历史记录，则优先在网页内部后退
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
        appBar: _customFullscreenWidget != null
            ? null
            : AppBar(
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
            // 全屏媒体视图：在当前页面同一路由层级顶层渲染，彻底消除跨路由导致的 WebView 失焦与 pause/play 死循环
            if (_customFullscreenWidget != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: _customFullscreenWidget!,
                ),
              ),
          ],
        ),
      ),
    );
  }

}
