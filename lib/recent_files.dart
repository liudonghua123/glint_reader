import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 最近打开的文件记录。
class RecentFile {
  final String path; // web 下为文件名
  final String name;
  final int openedAt; // epoch ms

  const RecentFile({
    required this.path,
    required this.name,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'openedAt': openedAt,
      };

  static RecentFile fromJson(Map<String, dynamic> json) => RecentFile(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '',
        openedAt: json['openedAt'] as int? ?? 0,
      );
}

/// 最近打开文件服务：全局单例，持久化 top N 条记录。
class RecentFilesService extends ChangeNotifier {
  RecentFilesService._();
  static final RecentFilesService instance = RecentFilesService._();

  static const _kRecentFiles = 'recentFiles';
  static const maxCount = 20;

  final List<RecentFile> _files = [];

  /// 最近打开的文件（最新在前）。
  List<RecentFile> get files => List.unmodifiable(_files);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kRecentFiles);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _files
          ..clear()
          ..addAll(list
              .map((e) => RecentFile.fromJson(Map<String, dynamic>.from(e)))
              .toList());
      } catch (_) {
        // 数据损坏时忽略
      }
    }
  }

  /// 记录一次打开（已存在的提到最前；超出上限移除最旧）。
  Future<void> record(String path, String name) async {
    if (path.isEmpty) return;
    _files.removeWhere((f) => f.path == path);
    _files.insert(
      0,
      RecentFile(
        path: path,
        name: name,
        openedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_files.length > maxCount) {
      _files.removeRange(maxCount, _files.length);
    }
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kRecentFiles,
      jsonEncode(_files.map((f) => f.toJson()).toList()),
    );
  }

  /// 清空最近记录。
  Future<void> clear() async {
    _files.clear();
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kRecentFiles);
  }
}
