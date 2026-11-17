import 'dart:io';
import 'dart:convert' show utf8;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';

import 'badge_marquee.dart';
import 'models.dart';
import 'i18n.dart';
import 'recent_files.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'status_bar.dart';
import 'viewer_page.dart';

/// 主页：文件打开 / 标签式查看。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialFile});

  /// 启动参数指定的初始文件路径（桌面端）。
  final String? initialFile;

  @override
  State<HomePage> createState() => _HomePageState();
}

  /// 标签页项：文件或主页（Chrome 式新标签页）。
  class _TabItem {
    final OpenFile? file;
    final int homeId; // 主页标签唯一 id（文件标签为 -1）
    _TabItem.home(int id) : file = null, homeId = id;
    _TabItem.file(OpenFile f) : file = f, homeId = -1;
    bool get isHome => file == null;
  }

  class _HomePageState extends State<HomePage>
      with SingleTickerProviderStateMixin {
    final List<_TabItem> _tabs = [];
    int _activeIndex = -1;
    int _nextHomeId = 1; // 主页标签自增 id
    bool _readOnly = true; // 阅读器默认只读，可切换为编辑

  // Android 返回手势：第一次提示，再按退出
  DateTime? _lastBackPress;

  // 拖拽悬停高亮
  bool _dragging = false;
  bool get dragging => _dragging;

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
      final item = _TabItem.file(OpenFile(
        path: path ?? name,
        name: name,
        content: content,
        kind: FileKind.fromFileName(name),
      ));
      // 在主页标签中打开时，原地替换该主页标签（Chrome 行为）
      if (_activeIndex >= 0 &&
          _activeIndex < _tabs.length &&
          _tabs[_activeIndex].isHome) {
        _tabs[_activeIndex] = item;
      } else {
        _tabs.add(item);
        _activeIndex = _tabs.length - 1;
      }
    });
    // 记录到最近打开（web 下 path 为文件名，去重以 path 为准）
    RecentFilesService.instance.record(path ?? name, name);
  }

  /// Chrome 式新标签页：新建一个主页标签。
  void _newHomeTab() {
    setState(() {
      _tabs.add(_TabItem.home(_nextHomeId++));
      _activeIndex = _tabs.length - 1;
    });
  }

  bool get hasFile =>
      _tabs.isNotEmpty &&
      _activeIndex >= 0 &&
      !_tabs[_activeIndex].isHome;

  /// 当前激活标签是否为主页页。
  bool get _activeIsHome =>
      _tabs.isNotEmpty &&
      _activeIndex >= 0 &&
      _tabs[_activeIndex].isHome;

  /// 支持的扩展名（同时用于 Android 上自过滤）。
  static const _supportedExtensions = [
    'txt', 'md', 'markdown', 'diff', 'patch', 'log', 'json', 'yaml', 'yml',
    'xml', 'svg', 'html', 'htm', 'css', 'scss', 'js', 'ts', 'py', 'java',
    'kt', 'swift', 'go', 'rs', 'c', 'h', 'cpp', 'cs', 'dart', 'rb', 'php',
    'sh', 'bash', 'ps1', 'sql', 'ini', 'cfg', 'conf', 'toml', 'csv', 'tsv',
    'lua', 'pl', 'r', 'dockerfile',
  ];

  /// 支持的扩展名集合（拖拽 / 粘贴快速校验用）。
  static final Set<String> _supportedExtSet =
      _supportedExtensions.toSet();

  /// 根据扩展名判断文件类型是否受支持。
  bool _isSupportedName(String name) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0) {
      // 无扩展名：常见无后缀配置文件仍支持
      const noExt = ['dockerfile', 'makefile', 'nginx', 'license', 'readme'];
      return noExt.contains(lower);
    }
    return _supportedExtSet.contains(lower.substring(dot + 1));
  }

  /// 拖拽文件进入（desktop_drop，支持 Windows/macOS/Linux/Android/Web）。
  Future<void> _onDropFiles(DropDoneDetails details) async {
    setState(() => _dragging = false);
    for (final file in details.files) {
      final name = file.name;
      if (!_isSupportedName(name)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${LanguageService.instance.s['app.unsupported']}: $name',
              ),
            ),
          );
        }
        continue;
      }
      String? content;
      try {
        if (!kIsWeb) {
          content = await File(file.path).readAsString();
        } else {
          final bytes = await file.readAsBytes();
          content = utf8.decode(bytes, allowMalformed: true);
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
        continue;
      }
      if (!mounted) return;
      _openContent(name, content, path: kIsWeb ? name : file.path);
    }
  }

  /// Windows 剪贴板粘贴打开（Ctrl+V）：
  /// 1) 优先读取 OS 层面复制的文件对象（CF_HDROP，
  ///    资源管理器右键复制 / Ctrl+C）
  /// 2) 兑底读纯文本路径（「复制为路径」或手工拷贝路径）
  Future<void> _pasteClipboardFile() async {
    if (kIsWeb || !Platform.isWindows) return;
    // 1) 文件对象（可含多个文件）
    try {
      final paths = await _fileChannel
          .invokeMethod<List<dynamic>>('getClipboardFiles');
      if (paths != null && paths.isNotEmpty) {
        var opened = 0;
        for (final p in paths) {
          final path = p.toString();
          if (await _openLocalPath(path)) opened++;
        }
        if (opened > 0) return;
      }
    } on PlatformException {
      // 通道不可用，兑底文本路径
    }
    // 2) 纯文本路径
    final text = await Clipboard.getData('text/plain')
        .then((v) => v?.text?.trim()) ?? '';
    // 剥离资源管理器「复制为路径」带的引号
    final path = text.replaceAll('"', '');
    if (path.isEmpty) return;
    await _openLocalPath(path);
  }

  /// 打开本地路径（文件）：校验支持格式，失败提示。
  Future<bool> _openLocalPath(String path) async {
    final f = File(path);
    if (!f.existsSync()) return false;
    final name = path.replaceAll('\\', '/').split('/').last;
    if (!_isSupportedName(name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LanguageService.instance.s['app.unsupported']}: $name',
            ),
          ),
        );
      }
      return false;
    }
    await _loadPickedFile(name, path, null);
    return true;
  }

  Future<void> _openFilePicker() async {
    // Android：走原生 ACTION_GET_CONTENT 直达文件管理器浏览视图
    //（file_picker 的 OPEN_DOCUMENT 在部分 ROM 显示为「最近」聚合首页）。
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final path = await _fileChannel.invokeMethod<String>('pickFile');
        if (path == null) return; // 用户取消
        final name = path.replaceAll('\\', '/').split('/').last;
        final ext = name.contains('.')
            ? name.split('.').last.toLowerCase()
            : '';
        if (ext.isNotEmpty &&
            !_supportedExtensions.contains(ext) &&
            FileKind.fromFileName(name) == FileKind.plaintext) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${LanguageService.instance.s['app.unsupported']}: $name',
                ),
              ),
            );
          }
          return;
        }
        await _loadPickedFile(name, path, null);
      } on PlatformException catch (e) {
        if (mounted && e.code != 'ALREADY_ACTIVE') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${LanguageService.instance.s['app.cannotRead']}: ${e.message}',
              ),
            ),
          );
        }
      }
      return;
    }
    // 桌面端 / Web：file_picker
    final files = await FilePicker.pickFiles(
      dialogTitle: LanguageService.instance.s['app.selectFile'],
      type: FileType.custom,
      allowedExtensions: _supportedExtensions,
    );
    for (final f in files) {
      final nameNoPath = f.name.replaceAll('\\', '/').split('/').last;
      await _loadPickedFile(nameNoPath, f.path, f);
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

  /// 打开最近记录中的文件（仅本地路径可重开）。
  Future<void> _openRecent(RecentFile rf) async {
    if (kIsWeb) return;
    final f = File(rf.path);
    if (!f.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LanguageService.instance.s['app.cannotRead']}: ${rf.name}',
            ),
          ),
        );
      }
      return;
    }
    await _loadPickedFile(rf.name, rf.path, null);
  }

  void _closeFile(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 拖拽 + 粘贴支持：桌面与 Web 均启用（desktop_drop 支持
    // Windows/macOS/Linux/Android/Web）；Ctrl+V 粘贴路径仅 Windows。
    final dropEnabled = kIsWeb || isDesktop ||
        (!kIsWeb && Platform.isAndroid);

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackGesture();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _pasteClipboardFile,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _pasteClipboardFile,
        },
        child: Focus(
          autofocus: true,
          child: dropEnabled
              ? DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: _onDropFiles,
                  child: _buildScaffold(context, isDark),
                )
              : _buildScaffold(context, isDark),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget body = Scaffold(
        // 不再用 SafeArea 顶部内边距：工具栏渐变延伸到状态栏后面，
        // 由 _buildToolbar 自行用 MediaQuery.padding.top 预留状态栏高度。
        body: Column(
          children: [
            _buildToolbar(context, isDark),
            if (_tabs.isNotEmpty) _buildTabs(context, isDark),
            Expanded(
              child: hasFile
                  ? ViewerPage(
                      key: ValueKey(
                          _tabs[_activeIndex].file!.path +
                              _activeIndex.toString()),
                      file: _tabs[_activeIndex].file!,
                      wordWrap: AppSettings.instance.wordWrap,
                      fontSize: AppSettings.instance.fontSize,
                      lineHeight: AppSettings.instance.lineHeight,
                      showLineNumbers: AppSettings.instance.showLineNumbers,
                      readOnly: _readOnly,
                      themeIsDark: isDark,
                    )
                  : (_activeIsHome
                      // Chrome 式主页标签：复用空状态主页内容
                      ? KeyedSubtree(
                          key: ValueKey('home_${_tabs[_activeIndex].homeId}'),
                          child: _buildEmptyState(context, isDark),
                        )
                      : _buildEmptyState(context, isDark)),
            ),
            // 底部扩展状态栏
            if (hasFile)
              StatusBar(
                key: ValueKey('status_${_tabs[_activeIndex].file!.path}'),
                file: _tabs[_activeIndex].file!,
                stats: FileStats.from(_tabs[_activeIndex].file!),
              ),
          ],
        ),
    );
    // 拖拽悬停提示层：毛玻璃遮罩 + 虚线框 + 弹入动画
    return Stack(
      children: [
        body,
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  padding: const EdgeInsets.all(18),
                  alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.85),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.35),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: DashedBorderContainer(
                      color: colorScheme.primary.withValues(alpha: 0.7),
                      radius: 18,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 36, vertical: 30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    colorScheme.primary
                                        .withValues(alpha: 0.18),
                                    colorScheme.secondary
                                        .withValues(alpha: 0.14),
                                  ],
                                ),
                              ),
                              child: Icon(Icons.file_open_rounded,
                                  size: 30, color: colorScheme.primary),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              LanguageService
                                  .instance.s['app.dropToOpen'],
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.primary,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              LanguageService
                                  .instance.s['app.dropFormats'],
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 返回手势：有关闭的标签（文件或主页）先关标签，没有标签时连按两次退出。
  void _handleBackGesture() {
    // 1) 先关当前标签
    if (_tabs.isNotEmpty && _activeIndex >= 0) {
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
                  Icon(_iconFor(_tabs[_activeIndex].file!.kind),
                      size: 13, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    _tabs[_activeIndex].file!.kind.label,
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
                    '${_tabs[_activeIndex].file!.content.split('\n').length} ${LanguageService.instance.s['app.lines']}',
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
      child: Row(
        children: [
          // 标签列表（可横向滚动）
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
          final tab = _tabs[i];
          final active = i == _activeIndex;
          // 主页标签显示「主页」+ house 图标；文件标签显示简单文件名
          final displayName = tab.isHome
              ? LanguageService.instance.s['app.homeTab']
              : tab.file!.name.replaceAll('\\', '/').split('/').last;
          final icon = tab.isHome
              ? Icons.home_outlined
              : _iconFor(tab.file!.kind);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              // 悬停 / 长按显示完整路径（主页标签不提示）
              message: tab.isHome
                  ? LanguageService.instance.s['app.homeTab']
                  : tab.file!.path,
              waitDuration: const Duration(milliseconds: 400),
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
                      Icon(icon,
                          size: 14,
                          color: active
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        displayName,
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
          ),
        );
      },
            ),
          ),
          // Chrome 式「+」新建主页标签
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 6),
            child: Tooltip(
              message: LanguageService.instance.s['app.newTab'],
              child: InkWell(
                onTap: _newHomeTab,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── 空状态 ─────────────────────────────

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = LanguageService.instance.s;
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
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
          // 最近打开列表
          _buildRecentSection(context, isNarrow),
          const SizedBox(height: 32),
          // 格式徽章走马灯（双排反向滚动，悬停暂停）
          SizedBox(
            width: isNarrow ? 340 : 560,
            child: BadgeMarquee(items: _kBadges, dark: isDark),
          ),
        ],
      ),
    );
  }

  /// 最近打开文件列表（空状态主页显示）。
  Widget _buildRecentSection(BuildContext context, bool narrow) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = LanguageService.instance.s;

    return ListenableBuilder(
      listenable: RecentFilesService.instance,
      builder: (context, _) {
        final files = RecentFilesService.instance.files;
        if (files.isEmpty) {
          return Text(
            s['app.noRecent'],
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          );
        }
        final shown = files.take(narrow ? 5 : 8).toList();
        return Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.history, size: 15, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    s['app.recent'],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () =>
                        RecentFilesService.instance.clear(),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        s['app.clearRecent'],
                        style: TextStyle(
                          fontSize: 11.5,
                          color:
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final rf in shown)
                InkWell(
                  onTap: () => _openRecent(rf),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          _iconFor(FileKind.fromFileName(rf.name)),
                          size: 14,
                          color: colorScheme.primary.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rf.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          _formatTime(rf.openedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
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

/// 空状态徽章列表（走马灯用，更多格式）。
const _kBadges = [
  '.md', '.txt', '.json', '.py', '.diff', '.yaml',
  '.go', '.rs', '.dart', '.ts', '.sql', '.sh',
  '.html', '.css', '.js', '.java', '.kt', '.swift',
  '.cpp', '.cs', '.rb', '.php', '.lua', '.csv',
  '.xml', '.toml', '.log', '.proto', '.tex', '.ps1',
];

/// 虚线边框容器（拖拽提示用）。
class DashedBorderContainer extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  const DashedBorderContainer({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
    this.dashWidth = 6,
    this.dashGap = 4,
    this.strokeWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(
        color: color,
        radius: radius,
        dashWidth: dashWidth,
        dashGap: dashGap,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = (dist + dashWidth).clamp(0.0, metric.length);
        dashed.addPath(
          metric.extractPath(dist, next),
          Offset.zero,
        );
        dist = next + dashGap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dashWidth != dashWidth ||
      old.dashGap != dashGap;
}



