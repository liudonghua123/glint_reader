import 'package:flutter/material.dart';

import 'i18n.dart';
import 'settings.dart';

/// 设置页面。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stagger;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _stagger = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fade = CurvedAnimation(parent: _stagger, curve: Curves.easeOutCubic);
    _stagger.forward();
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = AppSettings.instance;
    final s = LanguageService.instance.s;
    final isZh = LanguageService.instance.language == AppLanguage.zh;

    return Scaffold(
      appBar: AppBar(
        title: Text(s['settings.title']),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          AppSettings.instance,
          LanguageService.instance,
        ]),
        builder: (context, _) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(_fade),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ── 外观 ──
              _sectionHeader(context, s['settings.appearance']),
              _card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rowLabel(
                        context, Icons.brightness_6, s['settings.themeMode']),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text(s['settings.themeMode.system']),
                          icon: const Icon(Icons.settings_suggest, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text(s['settings.themeMode.light']),
                          icon: const Icon(Icons.light_mode, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text(s['settings.themeMode.dark']),
                          icon: const Icon(Icons.dark_mode, size: 16),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (selection) =>
                          settings.setThemeMode(selection.first),
                    ),
                    const SizedBox(height: 16),
                    _rowLabel(
                        context, Icons.palette_outlined, s['settings.accentColor']),
                    const SizedBox(height: 10),
                    // 主题色圆点选择器
                    Row(
                      children: [
                        for (final accent in AccentColor.all) ...[
                          _AccentDot(
                            color: accent.color,
                            selected: settings.accent.id == accent.id,
                            onTap: () => settings.setAccent(accent),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // ── 语言 ──
              _sectionHeader(context, s['settings.language']),
              _card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rowLabel(context, Icons.translate, s['settings.language']),
                    const SizedBox(height: 12),
                    SegmentedButton<AppLanguage>(
                      segments: [
                        ButtonSegment(
                          value: AppLanguage.en,
                          label: Text(AppLanguage.en.nativeName),
                          icon: const Icon(Icons.language, size: 16),
                        ),
                        ButtonSegment(
                          value: AppLanguage.zh,
                          label: Text(AppLanguage.zh.nativeName),
                          icon: const Icon(Icons.language, size: 16),
                        ),
                      ],
                      selected: {LanguageService.instance.language},
                      onSelectionChanged: (selection) =>
                          LanguageService.instance.setLanguage(selection.first),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              // ── 阅读器 ──
              _sectionHeader(context, s['settings.reader']),
              _card(
                context,
                child: Column(
                  children: [
                    // 字体
                    _rowLabel(context, Icons.font_download_outlined,
                        s['settings.fontFamily']),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<FontChoice>(
                      initialValue: settings.font,
                      isDense: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        hintText: isZh ? '选择字体' : 'Choose font',
                      ),
                      items: [
                        for (final f in FontChoice.all)
                          DropdownMenuItem(
                            value: f,
                            child: Text(
                              f.id == 'default'
                                  ? (isZh ? '默认等宽 (Default)' : 'Default Monospace')
                                  : f.family,
                              style: TextStyle(fontFamily: f.family),
                            ),
                          ),
                      ],
                      onChanged: (f) {
                        if (f != null) settings.setFont(f);
                      },
                    ),
                    const Divider(height: 24),
                    // 字号
                    Row(
                      children: [
                        Icon(Icons.format_size,
                            size: 18, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s['settings.fontSize'],
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        Text(
                          settings.fontSize.round().toString(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: settings.fontSize,
                      min: 10,
                      max: 24,
                      divisions: 14,
                      label: settings.fontSize.round().toString(),
                      onChanged: (v) => settings.setFontSize(v),
                    ),
                    // 行高
                    Row(
                      children: [
                        Icon(Icons.format_line_spacing,
                            size: 18, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s['settings.lineHeight'],
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        Text(
                          settings.lineHeight.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: settings.lineHeight,
                      min: 1.0,
                      max: 2.2,
                      divisions: 12,
                      label: settings.lineHeight.toStringAsFixed(2),
                      onChanged: (v) => settings.setLineHeight(v),
                    ),
                    const Divider(height: 1),
                    // 显示行号
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary:
                          Icon(Icons.tag, size: 18, color: colorScheme.primary),
                      title: Text(s['settings.showLineNumbers'],
                          style: Theme.of(context).textTheme.titleSmall),
                      value: settings.showLineNumbers,
                      onChanged: (v) => settings.setShowLineNumbers(v),
                    ),
                    const Divider(height: 1),
                    // 自动换行
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.wrap_text,
                          size: 18, color: colorScheme.primary),
                      title: Text(s['settings.wordWrap'],
                          style: Theme.of(context).textTheme.titleSmall),
                      value: settings.wordWrap,
                      onChanged: (v) => settings.setWordWrap(v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Glint Reader',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2129) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: child,
    );
  }

  Widget _rowLabel(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

/// 主题色圆点（带选中动画）。
class _AccentDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        width: selected ? 34 : 26,
        height: selected ? 34 : 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
      ),
    );
  }
}
