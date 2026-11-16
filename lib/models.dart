import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// 支持的语言 / 文件类型定义。
class FileKind {
  final String id; // highlight language id (re_highlight)
  final String label;
  final List<String> extensions;
  const FileKind(this.id, this.label, this.extensions);

  static const all = <FileKind>[
    FileKind('markdown', 'Markdown', ['.md', '.markdown', '.mdown']),
    FileKind('plaintext', 'Plain Text', ['.txt', '.text', '.log']),
    FileKind('diff', 'Diff / Patch', ['.diff', '.patch']),
    FileKind('json', 'JSON', ['.json', '.jsonc', '.json5']),
    FileKind('yaml', 'YAML', ['.yaml', '.yml']),
    FileKind('xml', 'XML', ['.xml', '.svg', '.xsl', '.plist']),
    FileKind('html', 'HTML', ['.html', '.htm']),
    FileKind('css', 'CSS', ['.css', '.scss', '.less']),
    FileKind('javascript', 'JavaScript', ['.js', '.mjs', '.cjs', '.jsx']),
    FileKind('typescript', 'TypeScript', ['.ts', '.tsx']),
    FileKind('python', 'Python', ['.py', '.pyw']),
    FileKind('java', 'Java', ['.java']),
    FileKind('kotlin', 'Kotlin', ['.kt', '.kts']),
    FileKind('swift', 'Swift', ['.swift']),
    FileKind('go', 'Go', ['.go']),
    FileKind('rust', 'Rust', ['.rs']),
    FileKind('c', 'C', ['.c', '.h']),
    FileKind('cpp', 'C++', ['.cpp', '.cc', '.cxx', '.hpp', '.hh']),
    FileKind('csharp', 'C#', ['.cs']),
    FileKind('dart', 'Dart', ['.dart']),
    FileKind('ruby', 'Ruby', ['.rb']),
    FileKind('php', 'PHP', ['.php']),
    FileKind('shell', 'Shell', ['.sh', '.bash', '.zsh', '.fish']),
    FileKind('powershell', 'PowerShell', ['.ps1', '.psm1', '.psd1']),
    FileKind('sql', 'SQL', ['.sql']),
    FileKind('ini', 'INI / Config', ['.ini', '.cfg', '.conf', '.toml', '.properties']),
    FileKind('dockerfile', 'Dockerfile', ['dockerfile', '.dockerfile']),
    FileKind('makefile', 'Makefile', ['makefile', 'makefile.am', 'mk']),
    FileKind('csv', 'CSV', ['.csv', '.tsv']),
    FileKind('lua', 'Lua', ['.lua']),
    FileKind('perl', 'Perl', ['.pl', '.pm']),
    FileKind('r', 'R', ['.r', '.R']),
    FileKind('scala', 'Scala', ['.scala', '.sc']),
    FileKind('haskell', 'Haskell', ['.hs', '.lhs']),
    FileKind('elixir', 'Elixir', ['.ex', '.exs']),
    FileKind('erlang', 'Erlang', ['.erl', '.hrl']),
    FileKind('clojure', 'Clojure', ['.clj', '.cljs', '.edn']),
    FileKind('objectivec', 'Objective-C', ['.m', '.mm']),
    FileKind('groovy', 'Groovy', ['.groovy', '.gradle']),
    FileKind('julia', 'Julia', ['.jl']),
    FileKind('fortran', 'Fortran', ['.f90', '.f95', '.f', '.for']),
    FileKind('pascal', 'Pascal', ['.pas', '.pp', '.dpr']),
    FileKind('vbnet', 'Visual Basic', ['.vb', '.vbs']),
    FileKind('matlab', 'MATLAB', ['.matlab']),
    FileKind('vhdl', 'VHDL', ['.vhd', '.vhdl']),
    FileKind('verilog', 'Verilog', ['.v', '.sv']),
    FileKind('ada', 'Ada', ['.adb', '.ads']),
    FileKind('ocaml', 'OCaml', ['.ml', '.mli']),
    FileKind('nim', 'Nim', ['.nim']),
    FileKind('crystal', 'Crystal', ['.cr']),
    FileKind('graphql', 'GraphQL', ['.graphql', '.gql']),
    FileKind('protobuf', 'Protocol Buffers', ['.proto']),
    FileKind('nginx', 'Nginx', ['nginx', 'nginx.conf', '.conf2']),
    FileKind('apache', 'Apache Config', ['httpd.conf', '.htaccess']),
    FileKind('cmake', 'CMake', ['cmakelists.txt', '.cmake']),
    FileKind('nsis', 'NSIS', ['.nsi', '.nsh']),
    FileKind('latex', 'LaTeX / TeX', ['.tex', '.sty', '.cls']),
    FileKind('markdown', 'Markdown', ['.mdown']),
  ];

  /// 根据文件名推断语言，找不到则回退 plaintext。
  static FileKind fromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    // 无扩展名的特殊文件名（dockerfile / makefile 等）
    for (final k in all) {
      if (k.extensions.any((e) => !e.startsWith('.') && lower == e)) {
        return k;
      }
    }
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return plaintext;
    final ext = lower.substring(dot);
    for (final k in all) {
      if (k.extensions.contains(ext)) return k;
    }
    return plaintext;
  }

  /// 是否为 Markdown（支持渲染预览）。
  bool get isMarkdown => id == 'markdown';

  /// 是否为 HTML（支持渲染预览）。
  bool get isHtml => id == 'html';

  /// 是否支持渲染预览（Markdown / HTML）。
  bool get isPreviewable => isMarkdown || isHtml;

  /// 是否支持语法高亮（re_highlight 内置该语言）。
  bool get isHighlightable => id != 'plaintext';

  static const plaintext = FileKind('plaintext', 'Plain Text', ['.txt']);
}

/// 已打开的文件标签。
class OpenFile {
  final String path; // web 下为文件名
  final String name;
  final String content;
  final FileKind kind;
  OpenFile({
    required this.path,
    required this.name,
    required this.content,
    required this.kind,
  });
}

/// 桌面平台判断（用于启用拖放、菜单栏等）。
bool get isDesktop {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}
