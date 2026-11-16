import 'package:flutter/material.dart';

import 'i18n.dart';
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

/// 获取根 navigator 的 context，保证对话框覆盖全屏。
BuildContext navigatorKeyContext(BuildContext context) {
  Navigator.of(context, rootNavigator: true).context;
  return context;
}

/// 更新确认 + 下载进度对话框。
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdatePhase { confirm, downloading, done, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.confirm;
  double _progress = 0;
  String? _downloadPath;
  String? _error;

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
            // Release notes（截断显示）
            if (widget.info.notes.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.notes,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
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
          if (_phase == _UpdatePhase.confirm)
            TextButton(
              onPressed: () =>
                  UpdateService.openReleasePage(widget.info.releasePageUrl),
              child: Text(s['update.openPage']),
            ),
          if (_phase == _UpdatePhase.confirm)
            FilledButton(
              onPressed: _startDownload,
              child: Text(s['update.download']),
            ),
          if (_phase == _UpdatePhase.done)
            FilledButton(
              onPressed: () {
                UpdateService.openDownloadedFile(_downloadPath!);
                Navigator.of(context).pop();
              },
              child: Text(s['update.install']),
            ),
          if (_phase == _UpdatePhase.error)
            FilledButton(
              onPressed: _startDownload,
              child: Text(s['update.retry']),
            ),
        ],
        if (_phase != _UpdatePhase.downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s['update.later']),
          ),
      ],
    );
  }

  bool get _assetMissing => widget.info.assetUrl == widget.info.releasePageUrl;

  Future<void> _startDownload() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _error = null;
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
