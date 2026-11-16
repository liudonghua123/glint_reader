import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_page.dart';
import 'i18n.dart';
import 'recent_files.dart';
import 'settings.dart';
import 'update_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  await LanguageService.instance.load();
  await RecentFilesService.instance.load();
  await UpdateService.instance.load();
  final initialFile = _initialFileFromArgs(args);
  runApp(initialFile != null
      ? GlintApp(initialFile: initialFile)
      : const GlintApp());
}

/// 从启动参数解析初始文件路径（桌面端: glint_reader.exe path/to/file）。
String? _initialFileFromArgs(List<String> args) {
  if (kIsWeb) return null;
  for (final arg in args) {
    // 仅接受存在的文件路径（同时兼容 / 与 \ 分隔符）
    if (arg.isEmpty || arg.startsWith('-')) continue;
    final f = File(arg);
    if (f.existsSync() && f.statSync().type == FileSystemEntityType.file) {
      return arg;
    }
  }
  return null;
}

class GlintApp extends StatelessWidget {
  const GlintApp({super.key, this.initialFile});

  /// 启动参数指定的初始文件路径（桌面端）。
  final String? initialFile;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettings.instance,
        LanguageService.instance,
      ]),
      builder: (context, _) {
        final settings = AppSettings.instance;
        final accent = settings.accent.color;

        return MaterialApp(
          title: 'Glint Reader',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light, accent),
          darkTheme: _buildTheme(Brightness.dark, accent),
          themeMode: settings.themeMode,
          locale: Locale(LanguageService.instance.language.code),
          supportedLocales: const [Locale('en'), Locale('zh')],
          home: HomePage(initialFile: initialFile),
        );
      },
    );
  }

  static ThemeData _buildTheme(Brightness brightness, Color accent) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: isDark
          ? Color.lerp(accent, Colors.white, 0.35)
          : Color.lerp(accent, Colors.black, 0.05),
      secondary: isDark ? const Color(0xFFE8B968) : const Color(0xFFC98A2B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF111418) : const Color(0xFFF6F8FA),
      fontFamily: 'Segoe UI',
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: const ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2F36) : const Color(0xFF2D333B),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 200),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ),
    );
  }
}
