import 'dart:io';
import 'dart:convert' show utf8;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import 'models.dart';
import 'i18n.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'viewer_page.dart';

/// 主页：文件打开 / 标签式查看。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialFile});

  /// 启动参数指定的初始文件路径（桌面端）。
  final String? initialFile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final List<OpenFile> _files = [];
  int _activeIndex = -1;
  bool _readOnly = true; // 阅读器默认只读，可切换为编辑

  // Android 返回手势：第一次提示，再按退出
  DateTime? _lastBackPress;

  // 空状态图标浮动动画
  late final AnimationController _float;

  static const _fileChannel = MethodChannel('glint_reader/files');

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettingsChanged);
    LanguageService.instance.addListener(_onSettingsChanged);
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _float.repeat(reverse: true);
    if (!kIsWeb && Platform.isAndroid) {
      _setupAndroidFileIntents();
    }
    if (widget.initialFile != null) {
      _loadPickedFile(
        widget.initialFile!.split(Platform.pathSeparator).last,
        widget.initialFile,
        null,
      );
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    LanguageService.instance.removeListener(_onSettingsChanged);
    _float.dispose();
    super.dispose();
  }

  /// 接收 Android 端通过 MethodChannel 传来的文件。
  Future<void> _setupAndroidFileIntents() async {
    void handleArgs(Map<String, dynamic> args) {
      final name = args['name'] as String? ?? 'unknown';
      final content = args['content'] as String?;
      final error = args['error'] as String?;
      if (!mounted) return;
      if (content != null) {
        _openContent(name, content, path: name);
      } else if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LanguageService.instance.s['app.cannotRead']} $name: $error',
            ),
          ),
        );
      }
    }

    _fileChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFile' && call.arguments is Map) {
        handleArgs(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    try {
      final initial = await _fileChannel.invokeMethod('getInitialFile');
      if (initial != null && initial is Map) {
        handleArgs(Map<String, dynamic>.from(initial));
      }
    } on PlatformException {
      // 忽略
    }
  }

  void _openContent(String name, String content, {String? path}) {
    setState(() {
      _files.add(OpenFile(
        path: path ?? name,
        name: name,
        content: content,
        kind: FileKind.fromFileName(name),
      ));
      _activeIndex = _files.length - 1;
    });
  }

  bool get hasFile => _files.isNotEmpty && _activeIndex >= 0;

  Future<void> _openFilePicker() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'txt', 'md', 'markdown', 'diff', 'patch', 'log', 'json', 'yaml', 'yml',
        'xml', 'svg', 'html', 'htm', 'css', 'scss', 'js', 'ts', 'py', 'java',
        'kt', 'swift', 'go', 'rs', 'c', 'h', 'cpp', 'cs', 'dart', 'rb', 'php',
        'sh', 'bash', 'ps1', 'sql', 'ini', 'cfg', 'conf', 'toml', 'csv', 'tsv',
        'lua', 'pl', 'r', 'dockerfile',
      ],
    );
    for (final f in files) {
      await _loadPickedFile(f.name, f.path, f);
    }
  }

  Future<void> _loadPickedFile(String name, String? path, PlatformFile? f) async {
    String content;
    try {
      if (path != null && !kIsWeb) {
        content = await File(path).readAsString();
      } else if (f != null) {
        // Web（blob URL）或无本地路径：从 PlatformFile 读取字节再解码
        final bytes = await f.readAsBytes();
        content = utf8.decode(bytes, allowMalformed: true);
      } else {
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LanguageService.instance.s['app.cannotRead']} $name: $e',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    _openContent(name, content, path: path);
  }

  void _closeFile(int index) {
    setState(() {
      _files.removeAt(index);
      if (_activeIndex >= _files.length) {
        _activeIndex = _files.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackGesture();
      },
      child: Scaffold(
        // 不再用 SafeArea 顶部内边距：工具栏渐变延伸到状态栏后面，
        // 由 _buildToolbar 自行用 MediaQuery.padding.top 预留状态栏高度。
        body: Column(
          children: [
            _buildToolbar(context, isDark),
            if (_files.isNotEmpty) _buildTabs(context, isDark),
            Expanded(
              child: hasFile
                  ? ViewerPage(
                      key: ValueKey(
                          _files[_activeIndex].path + _activeIndex.toString()),
                      file: _files[_activeIndex],
                      wordWrap: AppSettings.instance.wordWrap,
                      fontSize: AppSettings.instance.fontSize,
                      lineHeight: AppSettings.instance.lineHeight,
                      showLineNumbers: AppSettings.instance.showLineNumbers,
                      readOnly: _readOnly,
                      themeIsDark: isDark,
                    )
                  : _buildEmptyState(context, isDark),
            ),
          ],
        ),
      ),
    );
  }

  /// 返回手势：有关闭的标签先关标签，没有标签时连按两次退出。
  void _handleBackGesture() {
    // 1) 先关当前标签
    if (hasFile) {
      _closeFile(_activeIndex);
      return;
    }
    // 2) 没有文件了：2 秒内连按两次才退出
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LanguageService.instance.s['app.backToExit']),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 200,
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      ),
    );
  }

  // ───────────────────────────── 工具栏 ─────────────────────────────

  Widget _buildToolbar(BuildContext context, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    // Android edge-to-edge：顶部预留状态栏高度，渐变延伸到状态栏后面
    final topInset = MediaQuery.paddingOf(context).top;
    // 窄屏（手机竖屏）下精简布局：隐藏标题文字 / 按钮文字 / 文件信息胶囊
    final isNarrow = MediaQuery.sizeOf(context).width < 640;

    return Container(
      padding: EdgeInsets.fromLTRB(12, topInset, 12, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1B2129), const Color(0xFF171C23)]
              : [const Color(0xFFFFFFFF), const Color(0xFFF3F6FA)],
        ),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5B8DD9), Color(0xFF3B6FB6)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B6FB6).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.auto_stories, size: 17, color: Colors.white),
          ),
          // 标题文字：窄屏隐藏，给操作按钮让出空间
          if (!isNarrow) ...[
            const SizedBox(width: 10),
            Text(
              'Glint',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              ' Reader',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 12),
          // 打开文件按钮：窄屏只显示图标
          if (!isNarrow)
            FilledButton.tonalIcon(
              onPressed: _openFilePicker,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
                foregroundColor: colorScheme.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ).copyWith(
                overlayColor: WidgetStateProperty.all(
                  colorScheme.primary.withValues(alpha: 0.14),
                ),
              ),
              icon: const Icon(Icons.folder_open, size: 17),
              label: Text(LanguageService.instance.s['app.openFile'],
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            )
          else
            _ToolbarToggle(
              icon: Icons.folder_open,
              tooltip: LanguageService.instance.s['app.openFile'],
              active: false,
              onTap: _openFilePicker,
            ),
          const SizedBox(width: 6),
          // 分隔线
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          _ToolbarToggle(
            icon: Icons.wrap_text,
            tooltip: AppSettings.instance.wordWrap
                ? LanguageService.instance.s['wrap.on']
                : LanguageService.instance.s['wrap.off'],
            active: AppSettings.instance.wordWrap,
            onTap: () => AppSettings.instance
                .setWordWrap(!AppSettings.instance.wordWrap),
          ),
          const SizedBox(width: 4),
          _ToolbarToggle(
            icon: _readOnly ? Icons.visibility_outlined : Icons.edit_outlined,
            tooltip: _readOnly
                ? LanguageService.instance.s['mode.readonly']
                : LanguageService.instance.s['mode.edit'],
            active: !_readOnly,
            onTap: () => setState(() => _readOnly = !_readOnly),
          ),
          const SizedBox(width: 4),
          _ToolbarToggle(
            icon: Icons.settings_outlined,
            tooltip: LanguageService.instance.s['app.settings'],
            active: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          const Spacer(),
          // 文件信息胶囊：窄屏隐藏（文件名已显示在标签页上）
          if (hasFile && !isNarrow)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconFor(_files[_activeIndex].kind),
                      size: 13, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    _files[_activeIndex].kind.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                  Text(
                    '${_files[_activeIndex].content.split('\n').length} ${LanguageService.instance.s['app.lines']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────── 标签页 ─────────────────────────────

  Widget _buildTabs(BuildContext context, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF161B22)
            : const Color(0xFFEDF1F5),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: _files.length,
        itemBuilder: (context, i) {
          final file = _files[i];
          final active = i == _activeIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => setState(() => _activeIndex = i),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active
                          ? colorScheme.primary.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(file.kind),
                          size: 14,
                          color: active
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        file.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                          color: active
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 5),
                      _TabCloseButton(onClose: () => _closeFile(i)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────────── 空状态 ─────────────────────────────

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = LanguageService.instance.s;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 渐变光环图标（带浮动动画）
          AnimatedBuilder(
            animation: _float,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -6 * Curves.easeInOut.transform(_float.value)),
                child: child,
              );
            },
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.14),
                    colorScheme.secondary.withValues(alpha: 0.10),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    blurRadius: 32,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Icon(Icons.auto_stories_outlined,
                  size: 46, color: colorScheme.primary),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            s['app.openHint'],
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            s['app.openSub'],
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // 主按钮
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: _openFilePicker,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.folder_open, size: 20),
              label: Text(
                s['app.selectFile'],
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 40),
          // 格式徽章墙（逐个弹入）
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < _kBadges.length; i++)
                _StaggeredBadge(
                  label: _kBadges[i],
                  delay: i * 60,
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(FileKind kind) {
    switch (kind.id) {
      case 'markdown':
        return Icons.description;
      case 'diff':
        return Icons.difference;
      case 'json':
      case 'yaml':
      case 'xml':
        return Icons.data_object;
      default:
        return Icons.code;
    }
  }
}

// ───────────────────────────── 小组件 ─────────────────────────────

/// 工具栏切换按钮（带激活态）。
class _ToolbarToggle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _ToolbarToggle({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(
              icon,
              size: 19,
              color: active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签关闭按钮。
class _TabCloseButton extends StatelessWidget {
  final VoidCallback onClose;
  const _TabCloseButton({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onClose,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(Icons.close,
            size: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
      ),
    );
  }
}

/// 空状态徽章列表。
const _kBadges = [
  '.md', '.txt', '.diff', '.json', '.yaml', '.py',
  '.go', '.rs', '.dart', '.ts', '.sql', '.sh',
];

/// 带弹入动画的格式徽章。
class _StaggeredBadge extends StatefulWidget {
  final String label;
  final int delay;
  const _StaggeredBadge({required this.label, required this.delay});

  @override
  State<_StaggeredBadge> createState() => _StaggeredBadgeState();
}

class _StaggeredBadgeState extends State<_StaggeredBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(_anim),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1.0).animate(_anim),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

