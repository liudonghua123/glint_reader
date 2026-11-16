import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

/// HTML 渲染视图：安全内联渲染（不加载外部脚本），
/// 外层可滚动（滚轮 + 滚动条）+ 页边距，深浅色自适应。
class HtmlView extends StatefulWidget {
  final String content;
  final bool themeIsDark;
  final double fontSize;
  /// 关联文件的基目录（解析相对图片/链接用，可选）。
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

class _HtmlViewState extends State<HtmlView> {
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
          // 不启用网络图片懒加载以外的远程内容执行；
          // 链接走系统浏览器
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
              return {
                'color': headingColor.toCss(),
              };
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
