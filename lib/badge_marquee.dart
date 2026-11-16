import 'dart:async';

import 'package:flutter/material.dart';

/// 格式徽章走马灯：双排无限循环自动滚动（上下排反向），
/// 悬停 / 按住暂停，两端渐隐遮罩，徽章渐变描边彩虹感。
class BadgeMarquee extends StatefulWidget {
  final List<String> items;
  final bool dark;

  const BadgeMarquee({super.key, required this.items, required this.dark});

  @override
  State<BadgeMarquee> createState() => _BadgeMarqueeState();
}

class _BadgeMarqueeState extends State<BadgeMarquee> {
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    // 拆成两排，交错排列更有走马灯层次感
    final row1 = <String>[];
    final row2 = <String>[];
    for (var i = 0; i < widget.items.length; i++) {
      (i.isEven ? row1 : row2).add(widget.items[i]);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _paused = true),
      onExit: (_) => setState(() => _paused = false),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ShaderMask(
          // 两端渐隐
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: const [0.0, 0.08, 0.92, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MarqueeRow(
                items: row1,
                dark: widget.dark,
                speed: 26, // px/s
                reverse: false,
                paused: _paused,
                width: width,
              ),
              const SizedBox(height: 10),
              _MarqueeRow(
                items: row2,
                dark: widget.dark,
                speed: 22,
                reverse: true,
                paused: _paused,
                width: width,
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// 单排无限滚动。
class _MarqueeRow extends StatefulWidget {
  final List<String> items;
  final bool dark;
  final double speed;
  final bool reverse;
  final bool paused;
  final double width;

  const _MarqueeRow({
    required this.items,
    required this.dark,
    required this.speed,
    required this.reverse,
    required this.paused,
    required this.width,
  });

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow> {
  late final ScrollController _ctrl;
  double _halfWidth = 0; // 内容一半宽度（循环点）
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    // 下一帧再测（布局稳定后测量内容宽度）
    final pos = _ctrl.position;
    if (pos.hasContentDimensions && pos.maxScrollExtent > 0) {
      _halfWidth = (pos.maxScrollExtent + pos.viewportDimension) / 2;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _halfWidth <= 0) return;
      if (widget.paused) return;
      final dir = widget.reverse ? -1.0 : 1.0;
      var next = _ctrl.offset + dir * widget.speed * 0.016;
      // 循环：越过半幅（内容 × 2）回到起点
      if (!widget.reverse && next >= _halfWidth) next -= _halfWidth;
      if (widget.reverse && next <= 0) next += _halfWidth;
      if (_ctrl.hasClients) {
        _ctrl.jumpTo(next.clamp(0.0, _ctrl.position.maxScrollExtent));
      }
    });
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 内容重复两遍实现无缝循环
    final doubled = [...widget.items, ...widget.items];
    return SingleChildScrollView(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < doubled.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: 8,
                left: i == 0 ? 8 : 0,
              ),
              child: _GlowBadge(
                label: doubled[i],
                dark: widget.dark,
                seed: i,
              ),
            ),
        ],
      ),
    );
  }
}

/// 渐变描边徽章（循环序列取色，形成彩虹流动感）。
class _GlowBadge extends StatelessWidget {
  final String label;
  final bool dark;
  final int seed;

  const _GlowBadge({
    required this.label,
    required this.dark,
    required this.seed,
  });

  static const _palette = [
    Color(0xFF3B6FB6),
    Color(0xFF00897B),
    Color(0xFF7E57C2),
    Color(0xFFD35B7A),
    Color(0xFFE07A3F),
    Color(0xFF43A047),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = _palette[seed % _palette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: dark ? 0.25 : 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: dark
              ? Color.lerp(accent, Colors.white, 0.55)
              : Color.lerp(accent, Colors.black, 0.25),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
