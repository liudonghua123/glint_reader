import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/all.dart';

import 'models.dart';

/// 语法高亮核心：为 re_editor 提供 CodeHighlightTheme。
class HighlightService {
  HighlightService._();

  static final Set<String> _available = builtinAllLanguages.keys.toSet();

  /// 高亮语言 id 是否可用（不可用时 re_editor 自动降级为无高亮）。
  static bool isSupported(String id) => _available.contains(id);

  /// 构建 re_editor 的代码高亮主题（浅色 / 深色）。
  static CodeHighlightTheme buildTheme(bool dark) {
    return CodeHighlightTheme(
      languages: {
        for (final entry in builtinAllLanguages.entries)
          if (FileKind.all.any((k) => k.id == entry.key))
            entry.key: CodeHighlightThemeMode(mode: entry.value),
      },
      theme: dark ? builtinAllThemes['github-dark']! : builtinAllThemes['github']!,
    );
  }
}
