import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 平台对应的 release 资产文件名匹配。
enum UpdateChannel {
  windows('.zip', 'windows-x64.zip'),
  macos('.zip', 'macos.zip'),
  linux('.tar.gz', 'linux-x64.tar.gz'),
  android('.apk', 'android.apk');

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

    // 找到当前平台的资产
    String? assetUrl;
    int assetSize = 0;
    final assets = (data['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>();
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final url = a['browser_download_url'] as String? ?? '';
      final size = a['size'] as int? ?? 0;
      if (name.endsWith(channel.suffix) &&
          name.contains(channel.assetMarker.replaceAll(channel.suffix, ''))) {
        assetUrl = url;
        assetSize = size;
        break;
      }
    }
    // 兜底：按 marker 精确匹配
    if (assetUrl == null) {
      const markers = {
        UpdateChannel.windows: 'windows-x64',
        UpdateChannel.macos: 'macos',
        UpdateChannel.linux: 'linux-x64',
        UpdateChannel.android: 'android',
      };
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        final url = a['browser_download_url'] as String? ?? '';
        final size = a['size'] as int? ?? 0;
        if (name.endsWith(channel.suffix) &&
            name.contains(markers[channel]!)) {
          assetUrl = url;
          assetSize = size;
          break;
        }
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

  /// 下载资产到临时目录，回调进度 (0.0-1.0)。返回下载文件路径。
  Future<String> downloadAsset(
    UpdateInfo info,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.assetUrl));
      req.headers['User-Agent'] = 'glint_reader-updater';
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw HttpException('Download ${resp.statusCode}');
      }
      final total = resp.contentLength ?? info.assetSize;
      final dir = await _downloadDir();
      final fileName = info.assetUrl.split('/').last;
      final filePath = '$dir${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      onProgress(1.0);
      return filePath;
    } finally {
      client.close();
    }
  }

  Future<String> _downloadDir() async {
    if (Platform.isAndroid) {
      // 应用私有下载目录
      final dir = Directory(
          '/data/data/com.example.glint_reader/cache/updates');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir.path;
    }
    return Directory.systemTemp.path;
  }

  /// 打开 release 页面（兜底方式）。
  static Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 打开下载的文件（Windows: 启动安装程序/直接打开；Android: 无法直接安装，提示用户）。
  static Future<void> openDownloadedFile(String path) async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      // APK 安装需 FileProvider 与 REQUEST_INSTALL_PACKAGES 权限，
      // 跳转 release 页让用户手动安装更可靠
      await openReleasePage(releasePage);
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
