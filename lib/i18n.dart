import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支持的语言。
enum AppLanguage {
  en('en', 'English'),
  zh('zh', '简体中文');

  final String code;
  final String nativeName;
  const AppLanguage(this.code, this.nativeName);

  static AppLanguage fromCode(String? code) {
    if (code == 'zh') return AppLanguage.zh;
    return AppLanguage.en;
  }
}

/// 应用语言状态（全局单例，持久化）。
class LanguageService extends ChangeNotifier {
  LanguageService._();
  static final LanguageService instance = LanguageService._();

  static const _kLanguage = 'language';

  AppLanguage _language = AppLanguage.en;
  AppLanguage get language => _language;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _language = AppLanguage.fromCode(sp.getString(_kLanguage));
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLanguage, lang.code);
  }

  /// 当前语言的翻译。
  S get s => _language == AppLanguage.zh ? _zh : _en;
}

// ────────────────────────────── 翻译表 ──────────────────────────────

/// 翻译键值集合。
class S {
  final Map<String, String> _t;
  const S(this._t);
  String of(String key) => _t[key] ?? key;
  String operator [](String key) => of(key);
}

const _en = S({
  'app.name': 'Glint Reader',
  'app.openFile': 'Open File',
  'app.selectFile': 'Select File',
  'app.openHint': 'Open a text file to start reading',
  'app.openSub': 'Markdown · Diff · JSON · YAML · code files — 30+ formats with syntax highlighting',
  'app.settings': 'Settings',
  'app.lines': 'lines',
  'app.backToExit': 'Press back again to exit',
  'app.cannotRead': 'Cannot read file',
  'settings.title': 'Settings',
  'settings.appearance': 'Appearance',
  'settings.reader': 'Reader',
  'settings.language': 'Language',
  'settings.themeMode': 'Theme Mode',
  'settings.themeMode.system': 'System',
  'settings.themeMode.light': 'Light',
  'settings.themeMode.dark': 'Dark',
  'settings.accentColor': 'Accent Color',
  'settings.fontFamily': 'Font Family',
  'settings.fontSize': 'Font Size',
  'settings.lineHeight': 'Line Height',
  'settings.showLineNumbers': 'Show Line Numbers',
  'settings.wordWrap': 'Word Wrap',
  'find.hint': 'Find…',
  'find.prev': 'Previous',
  'find.next': 'Next',
  'find.close': 'Close',
  'menu.copy': 'Copy',
  'menu.selectAll': 'Select All',
  'mode.readonly': 'Read-only',
  'mode.edit': 'Edit',
  'wrap.on': 'Word wrap: on',
  'wrap.off': 'Word wrap: off',
  'app.recent': 'Recent Files',
  'app.noRecent': 'No recent files yet',
  'app.clearRecent': 'Clear',
  'viewer.preview': 'Preview',
  'viewer.source': 'Source',
  'status.file': 'File',
  'status.bytes': 'Bytes',
  'status.mdHeadings': 'Headings',
  'status.mdLinks': 'Links',
  'status.mdImages': 'Images',
  'status.mdCodeBlocks': 'Code blocks',
  'status.mdWords': 'Words',
  'status.jsonValid': 'Valid JSON',
  'status.jsonKeys': 'Keys',
  'status.csvRows': 'Rows (excl. header)',
  'status.csvCols': 'Columns',
  'status.diffAdded': 'Added',
  'status.diffRemoved': 'Removed',
  'status.htmlTags': 'Tags',
  'status.functions': 'Functions',
  'status.comments': 'Comment lines',
  'status.longestLine': 'Longest line',
});

const _zh = S({
  'app.name': 'Glint Reader',
  'app.openFile': '打开文件',
  'app.selectFile': '选择文件',
  'app.openHint': '打开一个文本文件开始阅读',
  'app.openSub': 'Markdown · Diff · JSON · YAML · 代码文件等 30+ 格式语法高亮',
  'app.settings': '设置',
  'app.lines': '行',
  'app.backToExit': '再按一次返回键退出',
  'app.cannotRead': '无法读取文件',
  'settings.title': '设置',
  'settings.appearance': '外观',
  'settings.reader': '阅读器',
  'settings.language': '语言 / Language',
  'settings.themeMode': '主题模式',
  'settings.themeMode.system': '跟随系统',
  'settings.themeMode.light': '浅色',
  'settings.themeMode.dark': '深色',
  'settings.accentColor': '主题色',
  'settings.fontFamily': '字体',
  'settings.fontSize': '字号',
  'settings.lineHeight': '行高',
  'settings.showLineNumbers': '显示行号',
  'settings.wordWrap': '自动换行',
  'find.hint': '查找…',
  'find.prev': '上一个',
  'find.next': '下一个',
  'find.close': '关闭',
  'menu.copy': '复制',
  'menu.selectAll': '全选',
  'mode.readonly': '只读模式',
  'mode.edit': '编辑模式',
  'wrap.on': '自动换行：开',
  'wrap.off': '自动换行：关',
  'app.recent': '最近打开',
  'app.noRecent': '暂无最近打开的文件',
  'app.clearRecent': '清空',
  'viewer.preview': '预览',
  'viewer.source': '源码',
  'status.file': '文件',
  'status.bytes': '字节',
  'status.mdHeadings': '标题',
  'status.mdLinks': '链接',
  'status.mdImages': '图片',
  'status.mdCodeBlocks': '代码块',
  'status.mdWords': '词数',
  'status.jsonValid': 'JSON 有效',
  'status.jsonKeys': '键数量',
  'status.csvRows': '数据行（不含表头）',
  'status.csvCols': '列数',
  'status.diffAdded': '新增',
  'status.diffRemoved': '删除',
  'status.htmlTags': '标签数',
  'status.functions': '函数',
  'status.comments': '注释行',
  'status.longestLine': '最长行',
});
