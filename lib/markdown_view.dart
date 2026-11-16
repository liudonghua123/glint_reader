import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'settings.dart';

/// Markdown 渲染视图：标题 / 列表 / 表格 / 代码块高亮 / 引用等。
/// 外层为可滚动容器（滚轮 + 滚动条）+ 页边距。
class MarkdownView extends StatefulWidget {
  final String content;
  final bool themeIsDark;
  final double fontSize;

  const MarkdownView({
    super.key,
    required this.content,
    required this.themeIsDark,
    this.fontSize = 15,
  });

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
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

    // Scrollbar + SingleChildScrollView：垂直滚动、滚轮支持
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height,
          ),
          child: _buildMarkdown(context, dark, colorScheme),
        ),
      ),
    );
  }

  Widget _buildMarkdown(
      BuildContext context, bool dark, ColorScheme colorScheme) {
    return MarkdownBody(
      data: widget.content,
      selectable: true,
      softLineBreak: true,
      extensionSet: null, // 使用默认 gitHubFlavored
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          fontSize: widget.fontSize + 1,
          height: 1.65,
          color: dark ? const Color(0xFFD7DDE4) : const Color(0xFF24292F),
        ),
        h1: TextStyle(
          fontSize: widget.fontSize + 10,
          fontWeight: FontWeight.w800,
          height: 1.4,
          color: dark ? Colors.white : const Color(0xFF1A2129),
        ),
        h2: TextStyle(
          fontSize: widget.fontSize + 6,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: dark ? Colors.white : const Color(0xFF1A2129),
        ),
        h3: TextStyle(
          fontSize: widget.fontSize + 3,
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : const Color(0xFF1A2129),
        ),
        h4: TextStyle(
          fontSize: widget.fontSize + 1,
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : const Color(0xFF1A2129),
        ),
        h1Padding: const EdgeInsets.only(top: 8, bottom: 6),
        h2Padding: const EdgeInsets.only(top: 6, bottom: 4),
        h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
        strong: const TextStyle(fontWeight: FontWeight.w700),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: TextStyle(
          color: colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        listBullet: TextStyle(
          fontSize: widget.fontSize + 1,
          height: 1.6,
          color: dark ? const Color(0xFFD7DDE4) : const Color(0xFF24292F),
        ),
        blockquoteDecoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.06),
          border: Border(
            left: BorderSide(
              width: 3,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        codeblockDecoration: BoxDecoration(
          color: dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(14),
        code: TextStyle(
          fontSize: widget.fontSize - 1,
          fontFamily: AppSettings.instance.font.family,
          backgroundColor: dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          color: dark ? const Color(0xFFE06C75) : const Color(0xFFC7254E),
        ),
        tableHead: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: widget.fontSize,
          color: dark ? Colors.white : const Color(0xFF1A2129),
        ),
        tableBody: TextStyle(
          fontSize: widget.fontSize,
          color: dark ? const Color(0xFFD7DDE4) : const Color(0xFF24292F),
        ),
        tableBorder: TableBorder.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              width: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      // 代码块语法高亮
      syntaxHighlighter: _GlintSyntaxHighlighter(
        dark: dark,
        fontFamily: AppSettings.instance.font.family,
        fontSize: widget.fontSize - 1,
      ),
    );
  }
}

/// Markdown 代码块高亮器：```lang 信息串 + re_highlight 引擎。
class _GlintSyntaxHighlighter extends SyntaxHighlighter {
  final bool dark;
  final String fontFamily;
  final double fontSize;

  _GlintSyntaxHighlighter({
    required this.dark,
    required this.fontFamily,
    required this.fontSize,
  });

  @override
  TextSpan format(String source) {
    // flutter_markdown_plus 传入 pre 内的纯代码文本，
    // ```lang 信息串已由 parser 消费（class="language-xxx"），
    // 这里做自动语言检测 + 手动解析兜底不可行，
    // 因此采用 highlightAuto 自动检测（限制常用语言子集提速）。
    final highlight = _highlighter;
    final result = highlight.highlightAuto(source, _commonLanguages);
    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.5,
      color: dark ? const Color(0xFFD7DDE4) : const Color(0xFF24292F),
    );
    final theme = dark ? builtinAllThemes['github-dark']! : builtinAllThemes['github']!;
    final renderer = TextSpanRenderer(baseStyle, theme);
    result.render(renderer);
    return renderer.span ?? TextSpan(text: source, style: baseStyle);
  }

  static final Highlight _highlighter = Highlight()
    ..registerLanguages(builtinAllLanguages);

  /// 自动检测用的常用语言子集（避免全量检测导致误判 + 慢）。
  static const _commonLanguages = [
    'markdown', 'plaintext', 'diff', 'json', 'yaml', 'xml', 'html', 'css',
    'javascript', 'typescript', 'python', 'java', 'kotlin', 'swift', 'go',
    'rust', 'c', 'cpp', 'csharp', 'dart', 'ruby', 'php', 'shell',
    'powershell', 'sql', 'ini', 'dockerfile', 'makefile', 'lua', 'perl',
    'r', 'scala', 'haskell', 'elixir', 'erlang', 'clojure', 'objectivec',
    'groovy', 'julia', 'fortran', 'pascal', 'vbnet', 'matlab', 'vhdl',
    'verilog', 'ada', 'ocaml', 'nim', 'crystal', 'graphql', 'protobuf',
    'nginx', 'apache', 'cmake', 'nsis', 'latex',
  ];
}
