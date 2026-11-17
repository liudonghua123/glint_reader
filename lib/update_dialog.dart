import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'markdown_view.dart';
import 'update_service.dart';

/// 检查更新入口：在设置页或关于里调用。
/// 检查完成弹出结果（新版本对话框 / 已是最新 SnackBar / 错误 SnackBar）。
Future<void> showUpdateCheck(BuildContext context) async {
  final s = LanguageService.instance.s;
  final messenger = ScaffoldMessenger.of(context);
  final dialogContext = navigatorKeyContext(context);

  // 显示检查中对话框
  showDialog<void>(
    context: dialogContext,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(),
    ),
  );

  UpdateInfo? info;
  String? error;
  try {
    info = await UpdateService.instance.checkForUpdate();
  } catch (e) {
    error = e.toString();
  }

  if (!dialogContext.mounted) {
    messenger.hideCurrentSnackBar();
    return;
  }
  Navigator.of(dialogContext, rootNavigator: true).pop(); // 关闭 loading

  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text('${s['update.checkFailed']}: $error')),
    );
    return;
  }
  if (info == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${s['update.upToDate']} (v${UpdateService.instance.currentVersion ?? '?'})',
        ),
      ),
    );
    return;
  }
  if (!dialogContext.mounted) return;
  showDialog<void>(
    context: dialogContext,
    builder: (_) => UpdateDialog(info: info!),
  );
}

/// 启动后自动静默检测更新，发现新版本弹出更新对话框。
/// 挂在 MaterialApp.builder 中，静默失败（不打扰启动流程）。
class AutoUpdateChecker extends StatefulWidget {
  final Widget child;

  const AutoUpdateChecker({super.key, required this.child});

  @override
  State<AutoUpdateChecker> createState() => _AutoUpdateCheckerState();
}

class _AutoUpdateCheckerState extends State<AutoUpdateChecker> {
  Timer? _timer;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // 启动 3 秒后静默检测（等首帧渲染完 + 网络就绪）
    _timer = Timer(const Duration(seconds: 3), _check);
  }

  Future<void> _check() async {
    if (_checked || !mounted) return;
    _checked = true;
    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (info == null || !mounted) return;
      // 有下载中的任务不弹（对话框会由用户手动打开）
      if (UpdateService.instance.isDownloading) return;
      showDialog<void>(
        context: context,
        builder: (_) => UpdateDialog(info: info),
      );
    } catch (_) {
      // 静默失败
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 获取根 navigator 的 context，保证对话框覆盖全屏。
BuildContext navigatorKeyContext(BuildContext context) {
  Navigator.of(context, rootNavigator: true).context;
  return context;
}

/// 更新确认 + 下载进度对话框。
/// 打开时自动检测：已下载 → 直接可安装；有 .part → 断点续传。
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdatePhase { checking, confirm, downloading, done, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.checking;
  double _progress = 0;
  String? _downloadPath;
  String? _error;
  bool _resumed = false; // 是否为续传（显示提示）

  @override
  void initState() {
    super.initState();
    _detectExisting();
  }

  /// 打开对话框时检测已有下载：完整文件直接可安装，.part 显示可续传。
  Future<void> _detectExisting() async {
    final service = UpdateService.instance;
    // 已在下载中（其他入口触发）：直接进入下载阶段挂到同一进度
    if (service.isDownloading) {
      if (!mounted) return;
      setState(() => _phase = _UpdatePhase.downloading);
      return;
    }
    try {
      final existing = await service.findDownloadedFile(widget.info);
      if (!mounted) return;
      if (existing != null) {
        setState(() {
          _phase = _UpdatePhase.done;
          _downloadPath = existing;
        });
        return;
      }
      final partial = await service.partialBytes(widget.info);
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.confirm;
        _resumed = partial > 0;
        if (widget.info.assetSize > 0 && partial > 0) {
          _progress = partial / widget.info.assetSize;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _UpdatePhase.confirm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageService.instance.s;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E242C) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Text(
            _phase == _UpdatePhase.done
                ? s['update.ready']
                : s['update.newVersion'],
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${widget.info.version}  ·  ${_humanSize(widget.info.assetSize)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            // Release notes：Markdown 渲染（截断滚动）
            if (widget.info.notes.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: MarkdownView(
                    content: _trimNotes(widget.info.notes),
                    themeIsDark: isDark,
                    fontSize: 12.5,
                  ),
                ),
              ),
            if (_phase == _UpdatePhase.downloading) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _progress > 0
                        ? '${(_progress * 100).toStringAsFixed(0)}%'
                        : '…',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            if (_resumed && _phase == _UpdatePhase.confirm) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.history, size: 14,
                      color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _resumedText(s),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_phase == _UpdatePhase.error) ...[
              const SizedBox(height: 12),
              Text(
                '${s['update.downloadFailed']}: $_error',
                style: const TextStyle(fontSize: 12.5, color: Colors.red),
              ),
            ],
            if (_phase == _UpdatePhase.done) ...[
              const SizedBox(height: 12),
              Text(
                s['update.savedTo'],
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _downloadPath ?? '',
                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
              ),
              // 桌面端压缩包：提示解压替换（不可直接运行安装）
              if (_isDesktopArchive) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s['update.desktopHint'],
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (_assetMissing)
          TextButton(
            onPressed: () =>
                UpdateService.openReleasePage(widget.info.releasePageUrl),
            child: Text(s['update.openPage']),
          )
        else ...[
          if (_phase == _UpdatePhase.confirm) ...[
            TextButton(
              onPressed: () =>
                  UpdateService.openReleasePage(widget.info.releasePageUrl),
              child: Text(s['update.openPage']),
            ),
            FilledButton(
              onPressed: _startDownload,
              child: Text(
                _resumed ? s['update.resume'] : s['update.download'],
              ),
            ),
          ],
          if (_phase == _UpdatePhase.done) ...[
            if (_isDesktopArchive)
              FilledButton.tonal(
                onPressed: () {
                  UpdateService.openDownloadedFile(_downloadPath!);
                },
                child: Text(s['update.openFolder']),
              )
            else
              FilledButton(
                onPressed: () {
                  UpdateService.openDownloadedFile(_downloadPath!);
                  Navigator.of(context).pop();
                },
                child: Text(s['update.install']),
              ),
          ],
          if (_phase == _UpdatePhase.error)
            FilledButton(
              onPressed: _startDownload,
              child: Text(s['update.retry']),
            ),
        ],
        if (_phase != _UpdatePhase.downloading &&
            _phase != _UpdatePhase.checking)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s['update.later']),
          ),
      ],
    );
  }

  String _resumedText(S s) {
    final pct = widget.info.assetSize > 0
        ? '${(_progress * 100).toStringAsFixed(0)}%'
        : '';
    return s['update.resumed'].replaceAll('%s', pct);
  }

  /// 精简 notes 用于对话框展示：
  /// 去掉 Full Changelog 尾部与空段落，限制长度防卡顿。
  String _trimNotes(String notes) {
    var text = notes.trim();
    final idx = text.indexOf('**Full Changelog**');
    if (idx > 0) text = text.substring(0, idx).trim();
    if (text.length > 4000) text = '${text.substring(0, 4000)}…';
    return text;
  }

  bool get _assetMissing => widget.info.assetUrl == widget.info.releasePageUrl;

  /// 桌面端下载的是压缩包（不能直接运行安装）。
  bool get _isDesktopArchive {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid || Platform.isIOS) return false;
    } catch (_) {
      return false;
    }
    final path = _downloadPath?.toLowerCase() ?? '';
    return path.endsWith('.zip') || path.endsWith('.tar.gz');
  }

  Future<void> _startDownload() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _error = null;
      if (!_resumed) _progress = 0;
    });
    try {
      final path = await UpdateService.instance
          .downloadAsset(widget.info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) {
        setState(() {
          _phase = _UpdatePhase.done;
          _downloadPath = path;
          _resumed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _UpdatePhase.error;
          _error = e.toString();
        });
      }
    }
  }

  String _humanSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
