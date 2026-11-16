import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvw;

/// HTML 渲染视图。
/// - Windows: webview_windows (WebView2)
/// - Android / macOS: webview_flutter
/// - Linux / Web: flutter_widget_from_html 内联渲染兜底
/// 统一注入深色模式与字号，外链交给系统浏览器。
class HtmlView extends StatefulWidget {
  final String content;
  final bool themeIsDark;
  final double fontSize;
  /// 关联文件路径（保留接口一致性）。
  final String? baseUrl;

  const HtmlView({
    super.key,
    required this.content,
    required this.themeIsDark,
    this.fontSize = 15,
    this.baseUrl,
  });

  @override
  State<HtmlView> createState() => _HtmlViewState();
}

enum _HtmlBackend { webviewFlutter, webviewWindows, inline }

class _HtmlViewState extends State<HtmlView> {
  final _windowsController = wvw.WebviewController();
  WebViewController? _flutterController;
  bool _windowsReady = false;
  _HtmlBackend _backend = _HtmlBackend.inline;

  @override
  void initState() {
    super.initState();
    _backend = _pickBackend();
    _init();
  }

  _HtmlBackend _pickBackend() {
    if (kIsWeb) return _HtmlBackend.inline;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return _HtmlBackend.webviewWindows;
      case TargetPlatform.android:
      case TargetPlatform.macOS:
        return _HtmlBackend.webviewFlutter;
      default:
        return _HtmlBackend.inline; // Linux 等
    }
  }

  Future<void> _init() async {
    final html = _wrapHtml();
    switch (_backend) {
      case _HtmlBackend.webviewFlutter:
        final c = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(NavigationDelegate(
            // 外链（http/https）交给系统浏览器
            onNavigationRequest: (req) {
              if (req.url.startsWith('data:') ||
                  req.url.startsWith('about:')) {
                return NavigationDecision.navigate;
              }
              final uri = Uri.tryParse(req.url);
              if (uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https')) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            },
          ))
          ..loadHtmlString(html);
        if (mounted) setState(() => _flutterController = c);
      case _HtmlBackend.webviewWindows:
        try {
          await _windowsController.initialize();
          await _windowsController.setBackgroundColor(Colors.transparent);
          await _windowsController.loadStringContent(html);
          if (mounted) setState(() => _windowsReady = true);
        } catch (_) {
          if (mounted) setState(() => _backend = _HtmlBackend.inline);
        }
      case _HtmlBackend.inline:
        break;
    }
  }

  /// 包一层完整 HTML：注入深色配色 + 基础排版（含字号）。
  String _wrapHtml() {
    final dark = widget.themeIsDark;
    final fs = widget.fontSize + 1;
    final bg = dark ? '#111418' : '#FFFFFF';
    final fg = dark ? '#D7DDE4' : '#24292F';
    final heading = dark ? '#FFFFFF' : '#1A2129';
    final link = dark ? '#7CB1E8' : '#3B6FB6';
    final codeBg = dark ? '#161B22' : '#F6F8FA';
    final codeFg = dark ? '#E06C75' : '#C7254E';
    final border = dark ? '#2D333B' : '#D0D7DE';
    final quoteBg = dark ? '#1B2129' : '#F1F5F9';
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: ${dark ? 'dark' : 'light'}; }
  html, body {
    margin: 0; padding: 24px 28px;
    background: $bg; color: $fg;
    font-family: -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    font-size: ${fs}px; line-height: 1.65;
    word-wrap: break-word;
  }
  h1, h2, h3, h4, h5, h6 { color: $heading; margin: 0.8em 0 0.4em; line-height: 1.35; }
  h1 { font-size: 1.9em; font-weight: 800; border-bottom: 1px solid $border; padding-bottom: .25em; }
  h2 { font-size: 1.5em; font-weight: 700; border-bottom: 1px solid $border; padding-bottom: .2em; }
  h3 { font-size: 1.25em; font-weight: 700; }
  a { color: $link; text-decoration: none; }
  a:hover { text-decoration: underline; }
  code {
    font-family: Consolas, "Cascadia Code", monospace;
    background: $codeBg; color: $codeFg;
    padding: .15em .4em; border-radius: 4px; font-size: .9em;
  }
  pre {
    background: $codeBg; border: 1px solid $border;
    border-radius: 8px; padding: 14px; overflow: auto;
  }
  pre code { background: none; padding: 0; color: $fg; }
  blockquote {
    margin: .6em 0; padding: 4px 14px;
    background: $quoteBg; border-left: 3px solid $link;
    color: ${dark ? '#9DA7B1' : '#57606A'};
  }
  table { border-collapse: collapse; margin: .8em 0; }
  th, td { border: 1px solid $border; padding: 6px 12px; }
  th { background: $quoteBg; color: $heading; font-weight: 700; }
  img { max-width: 100%; border-radius: 6px; }
  hr { border: none; border-top: 1px solid $border; margin: 1.2em 0; }
  ::-webkit-scrollbar { width: 10px; height: 10px; }
  ::-webkit-scrollbar-thumb { background: ${dark ? '#3A424D' : '#C4CDD5'}; border-radius: 5px; }
  ::-webkit-scrollbar-track { background: transparent; }
</style>
</head>
<body>${widget.content}</body>
</html>''';
  }

  @override
  void didUpdateWidget(covariant HtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.themeIsDark != widget.themeIsDark ||
        oldWidget.fontSize != widget.fontSize) {
      final html = _wrapHtml();
      switch (_backend) {
        case _HtmlBackend.webviewFlutter:
          _flutterController?.loadHtmlString(html);
        case _HtmlBackend.webviewWindows:
          if (_windowsReady) _windowsController.loadStringContent(html);
        case _HtmlBackend.inline:
          break;
      }
    }
  }

  @override
  void dispose() {
    if (_backend == _HtmlBackend.webviewWindows) {
      _windowsController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_backend) {
      case _HtmlBackend.webviewFlutter:
        if (_flutterController == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return WebViewWidget(controller: _flutterController!);
      case _HtmlBackend.webviewWindows:
        if (!_windowsReady) {
          return const Center(child: CircularProgressIndicator());
        }
        return wvw.Webview(_windowsController);
      case _HtmlBackend.inline:
        return _InlineHtmlView(
          content: widget.content,
          themeIsDark: widget.themeIsDark,
          fontSize: widget.fontSize,
        );
    }
  }
}

/// Linux / Web 兜底：内联安全渲染（无 JS）。
class _InlineHtmlView extends StatefulWidget {
  final String content;
  final bool themeIsDark;
  final double fontSize;

  const _InlineHtmlView({
    required this.content,
    required this.themeIsDark,
    required this.fontSize,
  });

  @override
  State<_InlineHtmlView> createState() => _InlineHtmlViewState();
}

class _InlineHtmlViewState extends State<_InlineHtmlView> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.themeIsDark;
    final colorScheme = Theme.of(context).colorScheme;
    final textColor =
        dark ? const Color(0xFFD7DDE4) : const Color(0xFF24292F);
    final headingColor = dark ? Colors.white : const Color(0xFF1A2129);
    final linkColor = colorScheme.primary;

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: HtmlWidget(
          widget.content,
          onTapUrl: (url) async {
            final uri = Uri.tryParse(url);
            if (uri == null) return false;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return false;
          },
          textStyle: TextStyle(
            fontSize: widget.fontSize + 1,
            height: 1.65,
            color: textColor,
          ),
          customStylesBuilder: (element) {
            final tag = element.localName;
            if (tag == 'h1' || tag == 'h2' || tag == 'h3' ||
                tag == 'h4' || tag == 'h5' || tag == 'h6' ||
                tag == 'th' || tag == 'strong' || tag == 'b') {
              return {'color': headingColor.toCss()};
            }
            if (tag == 'a') {
              return {'color': linkColor.toCss()};
            }
            if (tag == 'code' || tag == 'pre') {
              return {
                'color': dark
                    ? const Color(0xFFE06C75).toCss()
                    : const Color(0xFFC7254E).toCss(),
                'font-family': 'monospace',
              };
            }
            return null;
          },
        ),
      ),
    );
  }
}

extension _ColorCss on Color {
  String toCss() =>
      '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}
