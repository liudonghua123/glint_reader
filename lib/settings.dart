import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可选主题色。
class AccentColor {
  final String id;
  final Color color;
  const AccentColor(this.id, this.color);

  static const all = <AccentColor>[
    AccentColor('blue', Color(0xFF3B6FB6)),
    AccentColor('teal', Color(0xFF00897B)),
    AccentColor('purple', Color(0xFF7E57C2)),
    AccentColor('rose', Color(0xFFD35B7A)),
    AccentColor('orange', Color(0xFFE07A3F)),
    AccentColor('green', Color(0xFF43A047)),
  ];

  static AccentColor fromId(String? id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

/// 可选等宽字体族。
class FontChoice {
  final String id;
  final String family; // 'monospace' 表示平台默认等宽
  const FontChoice(this.id, this.family);

  static const all = <FontChoice>[
    FontChoice('default', 'monospace'),
    FontChoice('consolas', 'Consolas'),
    FontChoice('cascadia', 'Cascadia Code'),
    FontChoice('jetbrains', 'JetBrains Mono'),
    FontChoice('courier', 'Courier New'),
  ];

  static FontChoice fromId(String? id) =>
      all.firstWhere((f) => f.id == id, orElse: () => all.first);
}

/// 应用设置：主题模式、主题色、阅读器外观。全局单例，持久化。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kThemeMode = 'themeMode';
  static const _kFontSize = 'fontSize';
  static const _kLineHeight = 'lineHeight';
  static const _kShowLineNumbers = 'showLineNumbers';
  static const _kWordWrap = 'wordWrap';
  static const _kAccent = 'accentColor';
  static const _kFontFamily = 'fontFamily';

  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 14;
  double _lineHeight = 1.35;
  bool _showLineNumbers = true;
  bool _wordWrap = true;
  AccentColor _accent = AccentColor.all.first;
  FontChoice _font = FontChoice.all.first;

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  bool get showLineNumbers => _showLineNumbers;
  bool get wordWrap => _wordWrap;
  AccentColor get accent => _accent;
  FontChoice get font => _font;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == (sp.getString(_kThemeMode) ?? 'system'),
      orElse: () => ThemeMode.system,
    );
    _fontSize = sp.getDouble(_kFontSize) ?? 14;
    _lineHeight = sp.getDouble(_kLineHeight) ?? 1.35;
    _showLineNumbers = sp.getBool(_kShowLineNumbers) ?? true;
    _wordWrap = sp.getBool(_kWordWrap) ?? true;
    _accent = AccentColor.fromId(sp.getString(_kAccent));
    _font = FontChoice.fromId(sp.getString(_kFontFamily));
    notifyListeners();
  }

  Future<void> _save(String key, Object value) async {
    final sp = await SharedPreferences.getInstance();
    if (value is ThemeMode) {
      await sp.setString(_kThemeMode, value.name);
    } else if (value is double) {
      await sp.setDouble(key, value);
    } else if (value is bool) {
      await sp.setBool(key, value);
    } else if (value is String) {
      await sp.setString(key, value);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _save(_kThemeMode, mode);
  }

  Future<void> setFontSize(double v) async {
    _fontSize = v.clamp(10, 24);
    notifyListeners();
    await _save(_kFontSize, _fontSize);
  }

  Future<void> setLineHeight(double v) async {
    _lineHeight = v.clamp(1.0, 2.2);
    notifyListeners();
    await _save(_kLineHeight, _lineHeight);
  }

  Future<void> setShowLineNumbers(bool v) async {
    _showLineNumbers = v;
    notifyListeners();
    await _save(_kShowLineNumbers, v);
  }

  Future<void> setWordWrap(bool v) async {
    _wordWrap = v;
    notifyListeners();
    await _save(_kWordWrap, v);
  }

  Future<void> setAccent(AccentColor accent) async {
    _accent = accent;
    notifyListeners();
    await _save(_kAccent, accent.id);
  }

  Future<void> setFont(FontChoice font) async {
    _font = font;
    notifyListeners();
    await _save(_kFontFamily, font.id);
  }
}
