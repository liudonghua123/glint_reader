import 'dart:convert';

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'models.dart';

/// 文件统计信息（底部状态栏数据）。
class FileStats {
  final FileKind kind;
  final int lines;
  final int characters;
  final int bytes; // UTF-8 字节数
  final String encoding;

  const FileStats({
    required this.kind,
    required this.lines,
    required this.characters,
    required this.bytes,
    required this.encoding,
  });

  factory FileStats.from(OpenFile file) {
    final content = file.content;
    final bytes = utf8.encode(content).length;
    return FileStats(
      kind: file.kind,
      lines: content.split('\n').length,
      characters: content.length,
      bytes: bytes,
      encoding: _detectEncodingLabel(content),
    );
  }

  static String _detectEncodingLabel(String content) {
    // Dart 字符串读入即 UTF-8（读取时已处理 BOM/解码）；
    // 重新检查字符完整性，若含 U+FFFD 说明源文件非 UTF-8。
    if (content.contains('\u{FFFD}')) return 'Non-UTF-8';
    if (content.startsWith('\u{FEFF}')) return 'UTF-8 BOM';
    return 'UTF-8';
  }

  String get humanSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

/// 底部扩展状态栏：
/// 普通文本显示大小/行数/字符数/编码；特定格式显示专属信息，可点击展开。
class StatusBar extends StatefulWidget {
  final OpenFile file;
  final FileStats stats;

  const StatusBar({
    super.key,
    required this.file,
    required this.stats,
  });

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = LanguageService.instance.s;
    final stats = widget.stats;

    return Material(
      color: isDark ? const Color(0xFF161B22) : const Color(0xFFEDF1F5),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                // 主行：始终显示
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  child: Row(
                    children: [
                      _Item(
                        icon: Icons.description_outlined,
                        text: stats.kind.label,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: _Item(
                          icon: Icons.insert_drive_file_outlined,
                          text: stats.humanSize,
                        ),
                      ),
                      const SizedBox(width: 14),
                      _Item(
                        icon: Icons.format_list_numbered,
                        text: '${stats.lines} ${s['app.lines']}',
                      ),
                      const SizedBox(width: 14),
                      _Item(
                        icon: Icons.text_fields,
                        text: '${stats.characters}',
                      ),
                      const SizedBox(width: 14),
                      _Item(
                        icon: Icons.code,
                        text: stats.encoding,
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more,
                          size: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 展开区：格式专属详情
                if (_expanded) _buildExpanded(context, stats),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, FileStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final details = _detailEntries(stats, LanguageService.instance.s);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      color: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.black.withValues(alpha: 0.02),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final e in details)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                e,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _detailEntries(FileStats stats, S s) {
    final content = widget.file.content;
    final entries = <String>[
      '${s['status.file']}: ${widget.file.name}',
      '${s['status.bytes']}: ${stats.bytes}',
    ];

    switch (stats.kind.id) {
      case 'markdown':
        entries.addAll([
          '${s['status.mdHeadings']}: ${_countMatches(content, RegExp(r'^#{1,6} ', multiLine: true))}',
          '${s['status.mdLinks']}: ${_countMatches(content, RegExp(r'\[[^\]]*\]\([^)]*\)'))}',
          '${s['status.mdImages']}: ${_countMatches(content, RegExp(r'!\[[^\]]*\]\([^)]*\)'))}',
          '${s['status.mdCodeBlocks']}: ${_countMatches(content, RegExp(r'^```', multiLine: true)) ~/ 2}',
          '${s['status.mdWords']}: ${_wordCount(content)}',
        ]);
        break;
      case 'json':
        entries.addAll([
          '${s['status.jsonValid']}: ${_isJsonValid(content) ? "✓" : "✗"}',
          '${s['status.jsonKeys']}: ${_countMatches(content, RegExp(r'"[^"]+"\s*:'))}',
        ]);
        break;
      case 'csv':
      case 'tsv':
        final sep = stats.kind.id == 'tsv' ? '\t' : ',';
        final firstLine = content.split('\n').first;
        entries.addAll([
          '${s['status.csvRows']}: ${stats.lines > 0 ? stats.lines - 1 : 0}',
          '${s['status.csvCols']}: ${firstLine.split(sep).length}',
        ]);
        break;
      case 'diff':
      case 'patch':
        entries.addAll([
          '${s['status.diffAdded']}: ${_countMatches(content, RegExp(r'^\+[^+]', multiLine: true))}',
          '${s['status.diffRemoved']}: ${_countMatches(content, RegExp(r'^-[^-]', multiLine: true))}',
        ]);
        break;
      case 'html':
      case 'xml':
      case 'svg':
        entries.add('${s['status.htmlTags']}: ${_countMatches(content, RegExp(r'<[a-zA-Z][^>]*>'))}');
        break;
      default:
        if (stats.kind.isHighlightable) {
          // 代码文件：行级启发式统计
          entries.addAll([
            '${s['status.functions']}~: ${_countMatches(content, _functionPattern)}',
            '${s['status.comments']}~: ${_countMatches(content, RegExp(r'(^|\s)//|(^|\s)# |/\*|\* '))}',
            '${s['status.longestLine']}: ${_longestLine(content)}',
          ]);
        }
        break;
    }
    return entries;
  }

  static int _countMatches(String text, RegExp pattern) =>
      pattern.allMatches(text).length;

  static int _wordCount(String text) => text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  static int _longestLine(String text) {
    var max = 0;
    for (final line in text.split('\n')) {
      if (line.length > max) max = line.length;
    }
    return max;
  }

  bool _isJsonValid(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  static final _functionPattern = RegExp(
    r'^\s*(function |def |fn |func |fun |public |private |protected |static |final )?\w[\w<>\[\]]*\s*\([^)]*\)\s*\{?',
    multiLine: true,
  );
}

/// 状态栏单项。
class _Item extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _Item({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11.5, color: c)),
      ],
    );
  }
}
