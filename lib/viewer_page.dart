import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'highlight_service.dart';
import 'html_view.dart';
import 'i18n.dart';
import 'markdown_view.dart';
import 'models.dart';
import 'settings.dart';

/// 查看器页面：只读（可切换）高亮文本视图。
/// Markdown / HTML 文件支持源码 / 渲染预览切换。
class ViewerPage extends StatefulWidget {
  final OpenFile file;
  final bool wordWrap;
  final bool readOnly;
  final bool themeIsDark;
  final double fontSize;
  final double lineHeight;
  final bool showLineNumbers;

  const ViewerPage({
    super.key,
    required this.file,
    required this.wordWrap,
    required this.readOnly,
    required this.themeIsDark,
    this.fontSize = 14,
    this.lineHeight = 1.35,
    this.showLineNumbers = true,
  });

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  CodeLineEditingController? _controller;
  bool _preview = true; // md 默认渲染预览

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.file.content);
  }

  @override
  void didUpdateWidget(covariant ViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.content != widget.file.content) {
      _controller?.dispose();
      _controller = CodeLineEditingController.fromText(widget.file.content);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.themeIsDark;
    final colorScheme = Theme.of(context).colorScheme;

    // Markdown / HTML：源码 / 预览切换
    if (widget.file.kind.isPreviewable) {
      return Column(
        children: [
          // 切换条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF161B22) : const Color(0xFFEDF1F5),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                const Spacer(),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(
                        LanguageService.instance.s['viewer.preview'],
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      icon: const Icon(Icons.article_outlined, size: 15),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(
                        LanguageService.instance.s['viewer.source'],
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      icon: const Icon(Icons.code, size: 15),
                    ),
                  ],
                  selected: {_preview},
                  onSelectionChanged: (sel) =>
                      setState(() => _preview = sel.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _preview
                ? (widget.file.kind.isMarkdown
                    ? MarkdownView(
                        content: widget.file.content,
                        themeIsDark: dark,
                        fontSize: widget.fontSize,
                      )
                    : HtmlView(
                        content: widget.file.content,
                        themeIsDark: dark,
                        fontSize: widget.fontSize,
                        baseUrl: widget.file.path,
                      ))
                : _buildCodeEditor(dark, colorScheme),
          ),
        ],
      );
    }

    return _buildCodeEditor(dark, colorScheme);
  }

  Widget _buildCodeEditor(bool dark, ColorScheme colorScheme) {
    final codeTheme = HighlightService.buildTheme(dark);
    return CodeEditor(
      controller: _controller,
      readOnly: widget.readOnly,
      showCursorWhenReadOnly: true,
      wordWrap: widget.wordWrap,
      style: CodeEditorStyle(
        fontSize: widget.fontSize,
        fontHeight: widget.lineHeight,
        fontFamily: AppSettings.instance.font.family,
        codeTheme: codeTheme,
        backgroundColor: dark ? const Color(0xFF111418) : const Color(0xFFFFFFFF),
        // 当前光标所在行高亮
        cursorLineColor: dark
            ? const Color(0xFF2D3B4E)
            : const Color(0xFFE8F0FE),
        selectionColor: dark
            ? const Color(0xFF3B6FB6).withValues(alpha: 0.35)
            : const Color(0xFF3B6FB6).withValues(alpha: 0.18),
        highlightColor: dark
            ? const Color(0xFF5B8DD9).withValues(alpha: 0.30)
            : const Color(0xFF3B6FB6).withValues(alpha: 0.25),
        cursorColor: colorScheme.primary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      indicatorBuilder: widget.showLineNumbers
          ? (context, editingController, chunkController, notifier) {
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    DefaultCodeLineNumber(
                      controller: editingController,
                      notifier: notifier,
                      textStyle: TextStyle(
                        fontSize: widget.fontSize - 2,
                        height: widget.lineHeight,
                        color:
                            dark ? const Color(0xFF484F58) : const Color(0xFFA0AAB4),
                        fontFamily: 'monospace',
                      ),
                      focusedTextStyle: TextStyle(
                        fontSize: widget.fontSize - 2,
                        height: widget.lineHeight,
                        color:
                            dark ? const Color(0xFF9FC3F0) : const Color(0xFF3564AD),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    DefaultCodeChunkIndicator(
                      width: 14,
                      controller: chunkController,
                      notifier: notifier,
                    ),
                  ],
                ),
              );
            }
          : null,
      findBuilder: (context, controller, readOnly) =>
          _GlintFindPanel(controller: controller, readOnly: readOnly),
      toolbarController: const _GlintContextMenu(),
    );
  }
}

/// 查找面板（顶部右侧悬浮卡片）。
class _GlintFindPanel extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const _GlintFindPanel({required this.controller, required this.readOnly});

  @override
  Size get preferredSize => Size.fromHeight(controller.value == null ? 0 : 44);

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) return const SizedBox.shrink();
    final value = controller.value!;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

              final s = LanguageService.instance.s;
              return Container(
                margin: const EdgeInsets.only(top: 8, right: 12),
      alignment: Alignment.topRight,
      child: Material(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        color: isDark ? const Color(0xFF1E242C) : Colors.white,
        child: Container(
          width: 340,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller.findInputController,
                  focusNode: controller.findInputFocusNode,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: s['find.hint'],
                    hintStyle: const TextStyle(fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              // 匹配计数胶囊
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${value.result?.index != null && value.result!.index >= 0 ? value.result!.index + 1 : 0}/${value.result?.matches.length ?? 0}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _FindIcon(
                icon: Icons.keyboard_arrow_up,
                tooltip: s['find.prev'],
                onTap: controller.previousMatch,
              ),
              _FindIcon(
                icon: Icons.keyboard_arrow_down,
                tooltip: s['find.next'],
                onTap: controller.nextMatch,
              ),
              _FindIcon(
                icon: Icons.close,
                tooltip: s['find.close'],
                onTap: () => controller.findInputFocusNode.unfocus(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FindIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 右键菜单：复制 / 全选。
class _GlintContextMenu implements SelectionToolbarController {
  const _GlintContextMenu();

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final s = LanguageService.instance.s;
    showMenu<void>(
      context: context,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E242C)
          : Colors.white,
      position: RelativeRect.fromSize(
        anchors.primaryAnchor & const Size(160, double.infinity),
        MediaQuery.of(context).size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        PopupMenuItem<void>(
          height: 40,
          onTap: () => controller.copy(),
          child: Row(
            children: [
              const Icon(Icons.content_copy, size: 16),
              const SizedBox(width: 10),
              Text(s['menu.copy']),
            ],
          ),
        ),
        PopupMenuItem<void>(
          height: 40,
          onTap: () => controller.selectAll(),
          child: Row(
            children: [
              const Icon(Icons.select_all, size: 16),
              const SizedBox(width: 10),
              Text(s['menu.selectAll']),
            ],
          ),
        ),
      ],
    );
  }
}
