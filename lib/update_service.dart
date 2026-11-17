import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, ChangeNotifier;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 平台对应的 release 资产文件名匹配。
/// 资产命名格式：`glint_reader-<version>-<platform>.<ext>`
/// 例如：`glint_reader-1.7.0-android-universal.apk`
enum UpdateChannel {
  windows('.zip', 'windows-x64'),
  macos('.zip', 'macos'),
  linux('.tar.gz', 'linux-x64'),
  android('.apk', 'android-universal');

  const UpdateChannel(this.suffix, this.assetMarker);

  final String suffix;
  final String assetMarker;

  static UpdateChannel? get current {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return UpdateChannel.windows;
      case TargetPlatform.macOS:
        return UpdateChannel.macos;
      case TargetPlatform.linux:
        return UpdateChannel.linux;
      case TargetPlatform.android:
        return UpdateChannel.android;
      default:
        return null; // iOS / Fuchsia 不支持
    }
  }
}

/// 最新版本信息。
class UpdateInfo {
  final String version; // 不带 v 前缀
  final String tagName; // 原始 tag
  final String notes;
  final String assetUrl; // 当前平台资产下载地址
  final int assetSize;
  final String releasePageUrl;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.assetUrl,
    required this.assetSize,
    required this.releasePageUrl,
  });
}

/// 下载状态（跨对话框共享，通知栏也用它）。
class DownloadState extends ChangeNotifier {  bool downloading = false;
  double progress = 0;
  String? filePath; // 完成后的路径
  String? error;
  UpdateInfo? info;

  void _update({
    bool? downloading,
    double? progress,
    String? filePath,
    String? error,
    UpdateInfo? info,
  }) {
    if (downloading != null) this.downloading = downloading;
    if (progress != null) this.progress = progress;
    if (filePath != null) this.filePath = filePath;
    if (error != null) this.error = error;
    if (info != null) this.info = info;
    notifyListeners();
  }

  void reset() {
    downloading = false;
    progress = 0;
    filePath = null;
    error = null;
    notifyListeners();
  }
}

/// GitHub Release 应用内更新服务。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const owner = 'liudonghua123';
  static const repo = 'glint_reader';
  static const _latestUrl =
      'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const releasePage =
      'https://github.com/$owner/$repo/releases/latest';

  /// 全局下载状态（对话框与通知共用）。
  final DownloadState download = DownloadState();

  String? _currentVersion;
  String? get currentVersion => _currentVersion;

  Future<void> load() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
  }

  /// 比较语义化版本：a > b 返回 1，< 返回 -1，== 返回 0。
  static int compareVersions(String a, String b) {
    final pa = a.split(RegExp(r'[.+-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final pb = b.split(RegExp(r'[.+-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x > y) return 1;
      if (x < y) return -1;
    }
    return 0;
  }

  /// 查询最新 release；有更新则返回 UpdateInfo，否则（或出错）返回 null。
  /// 抛出异常表示网络失败。
  Future<UpdateInfo?> checkForUpdate() async {
    final channel = UpdateChannel.current;
    if (channel == null) return null;

    final resp = await http.get(
      Uri.parse(_latestUrl),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'glint_reader-updater',
      },
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw HttpException('GitHub API ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes))
        as Map<String, dynamic>;
    final tag = data['tag_name'] as String? ?? '';
    final notes = data['body'] as String? ?? '';
    final pageUrl = data['html_url'] as String? ?? releasePage;

    // 找到当前平台的资产：
    // 名称格式 glint_reader-<version>-<marker><suffix>
    String? assetUrl;
    int assetSize = 0;
    final assets = (data['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>();
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final url = a['browser_download_url'] as String? ?? '';
      final size = a['size'] as int? ?? 0;
      if (name.startsWith('glint_reader-') &&
          name.endsWith(channel.suffix) &&
          name.contains(channel.assetMarker)) {
        assetUrl = url;
        assetSize = size;
        break;
      }
    }

    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    final current = _currentVersion ?? '0.0.0';
    if (compareVersions(latest, current) > 0) {
      return UpdateInfo(
        version: latest,
        tagName: tag,
        notes: notes,
        assetUrl: assetUrl ?? pageUrl,
        assetSize: assetSize,
        releasePageUrl: pageUrl,
      );
    }
    return null; // 已是最新
  }

  // ────────────────────── 下载（断点续传） ──────────────────────

  /// 下载目录：Android 用应用私有外部缓存（FileProvider 可共享），
  /// 桌面端用系统临时目录下的 glint_reader_updates。
  Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      final base = await getExternalStorageDirectories();
      final dir = Directory(
          '${base!.first.path}${Platform.pathSeparator}updates');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}glint_reader_updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 版本化下载文件名（不同版本不互相覆盖）。
  String _fileNameFor(UpdateInfo info) {
    final original = info.assetUrl.split('/').last;
    return 'glint_reader-v${info.version}$original';
  }

  /// 已完整下载的文件路径（大小匹配即认为完整），没有则 null。
  Future<String?> findDownloadedFile(UpdateInfo info) async {
    if (info.assetSize <= 0) return null;
    final dir = await _downloadDir();
    final f = File(
        '${dir.path}${Platform.pathSeparator}${_fileNameFor(info)}');
    if (f.existsSync() && f.lengthSync() == info.assetSize) {
      return f.path;
    }
    return null;
  }

  /// 正在进行的 .part 临时文件已下载字节数（无则 0）。
  Future<int> partialBytes(UpdateInfo info) async {
    final dir = await _downloadDir();
    final part = File(
        '${dir.path}${Platform.pathSeparator}${_fileNameFor(info)}.part');
    return part.existsSync() ? part.lengthSync() : 0;
  }

  /// 是否正在下载（任意调用方）。
  bool get isDownloading => download.downloading;

  /// 下载资产（支持断点续传 + 已完成文件复用）。
  /// [onProgress] 进度回调 0.0-1.0；返回最终文件路径。
  Future<String> downloadAsset(
    UpdateInfo info,
    void Function(double progress) onProgress,
  ) async {
    // 已在下载：直接挂到全局状态等待
    if (download.downloading) {
      final completer = Completer<String>();
      late final void Function() listener;
      listener = () {
        if (download.filePath != null &&
            !completer.isCompleted) {
          completer.complete(download.filePath!);
        } else if (download.error != null &&
            !completer.isCompleted) {
          completer.completeError(download.error!);
        }
      };
      download.addListener(listener);
      try {
        return await completer.future;
      } finally {
        download.removeListener(listener);
      }
    }

    // 已有完整文件：直接复用
    final existing = await findDownloadedFile(info);
    if (existing != null) {
      onProgress(1.0);
      download._update(
          downloading: false, progress: 1.0, filePath: existing, info: info);
      return existing;
    }

    final dir = await _downloadDir();
    final fileName = _fileNameFor(info);
    final partFile = File('${dir.path}${Platform.pathSeparator}$fileName.part');
    final finalFile =
        File('${dir.path}${Platform.pathSeparator}$fileName');

    var downloaded = partFile.existsSync() ? partFile.lengthSync() : 0;
    // 总大小已知且 part 已不小于它：重新开始（上次可能中断在结尾）
    if (info.assetSize > 0 && downloaded >= info.assetSize) {
      partFile.deleteSync();
      downloaded = 0;
    }

    download._update(downloading: true, progress: 0, filePath: null,
        error: null, info: info);

    final client = http.Client();
    final sink = partFile.openWrite(mode: FileMode.append);
    try {
      final req = http.Request('GET', Uri.parse(info.assetUrl));
      req.headers['User-Agent'] = 'glint_reader-updater';
      if (downloaded > 0) {
        req.headers['Range'] = 'bytes=$downloaded-';
      }
      final resp = await client.send(req);

      if (resp.statusCode == 200) {
        // 服务器不支持 Range（返回全量）：从头写
        if (downloaded > 0) {
          await sink.close();
          await partFile.delete();
          downloaded = 0;
        }
      } else if (resp.statusCode == 206) {
        // 续传成功
      } else {
        throw HttpException('Download ${resp.statusCode}');
      }

      final total = info.assetSize > 0
          ? info.assetSize
          : (resp.contentLength ?? 0) + downloaded;
      var received = downloaded;

      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          final p = received / total;
          onProgress(p);
          download._update(progress: p);
        }
      }
      await sink.flush();
      await sink.close();

      if (info.assetSize > 0 &&
          received != info.assetSize) {
        throw HttpException(
            'Incomplete: $received / ${info.assetSize}');
      }

      // 下载完成：.part 改名为最终文件
      if (finalFile.existsSync()) finalFile.deleteSync();
      partFile.renameSync(finalFile.path);

      onProgress(1.0);
      download._update(
          downloading: false, progress: 1.0, filePath: finalFile.path);
      return finalFile.path;
    } catch (e) {
      download._update(downloading: false, error: e.toString());
      rethrow;
    } finally {
      await sink.close().catchError((_) {});
      client.close();
    }
  }

  // ────────────────────── 打开 / 安装 ──────────────────────

  /// 打开 release 页面（兜底方式）。
  static Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 打开下载的文件：
  /// - Android: 通过 FileProvider + ACTION_VIEW 调起系统安装器安装 APK
  /// - Windows: 直接启动（便携版即运行）
  /// - macOS/Linux: open / xdg-open
  static Future<void> openDownloadedFile(String path) async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      const channel = MethodChannel('glint_reader/files');
      try {
        await channel.invokeMethod('installApk', {'path': path});
      } on PlatformException {
        // 兜底：跳转 release 页
        await openReleasePage(releasePage);
      }
      return;
    }
    if (Platform.isWindows) {
      await Process.start(path, [], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  }
}
