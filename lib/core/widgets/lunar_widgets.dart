import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/lunar_theme.dart';
import '../feedback/feedback_controller.dart';

class LunarPhases extends StatelessWidget {
  const LunarPhases({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      key: const ValueKey('lunar-phase-signature'),
      width: 86,
      height: 18,
      child: CustomPaint(painter: _PhasePainter(LunarPalette.of(context))),
    ),
  );
}

class _PhasePainter extends CustomPainter {
  _PhasePainter(this.p);
  final LunarPalette p;
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = p.gold;
    for (var i = 0; i < 5; i++) {
      final center = Offset(7 + 18.0 * i, size.height / 2);
      final rect = Rect.fromCircle(center: center, radius: 4.5);
      if (i == 0) {
        canvas.drawCircle(
          center,
          4.5,
          Paint()
            ..color = p.gold.withValues(alpha: .5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
        continue;
      }
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      canvas.drawCircle(center, 4.5, ink);
      if (i == 1) {
        canvas.drawOval(
          rect.shift(const Offset(-3, 0)),
          Paint()..color = p.paper,
        );
      }
      if (i == 2) {
        canvas.drawRect(
          Rect.fromLTRB(rect.left, rect.top, center.dx, rect.bottom),
          Paint()..color = p.paper,
        );
      }
      if (i == 3) {
        canvas.drawOval(
          Rect.fromLTWH(rect.left - 2, rect.top, 5, 9),
          Paint()..color = p.paper,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PhasePainter old) => p != old.p;
}

class LunarMoon extends StatelessWidget {
  const LunarMoon({super.key, this.full = false, this.size = 112});
  final bool full;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MoonPainter(LunarPalette.of(context), full)),
    ),
  );
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.p, this.full);
  final LunarPalette p;
  final bool full;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide * .33;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-.3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * .93,
        height: size.height * .99,
      ),
      Paint()
        ..color = p.moon.withValues(alpha: .27)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(size.width * .84, size.height * .16),
      1.6,
      Paint()..color = p.moon.withValues(alpha: .8),
    );
    final moon = Rect.fromCircle(center: c, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(moon));
    canvas.drawCircle(c, radius, Paint()..color = p.moon);
    final craters = [
      (-.35, -.2, .22),
      (.35, -.42, .13),
      (-.05, .38, .18),
      (.51, .42, .11),
    ];
    for (final (x, y, r) in craters) {
      canvas.drawCircle(
        c + Offset(x * radius, y * radius),
        radius * r,
        Paint()
          ..color = p.night.withValues(alpha: .15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .8),
      );
    }
    if (!full) {
      canvas.drawOval(
        Rect.fromCenter(
          center: c - Offset(radius * .6, 0),
          width: radius * 1.7,
          height: radius * 2.3,
        ),
        Paint()..color = p.night,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MoonPainter old) => p != old.p || full != old.full;
}

class LunarHeading extends StatelessWidget {
  const LunarHeading(this.text, {super.key, this.subtitle});
  final String text;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: TextStyle(
          fontFamily: 'serif',
          fontFamilyFallback: const ['Noto Serif CJK SC'],
          fontSize: 27,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: LunarPalette.of(context).ink,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          style: TextStyle(color: LunarPalette.of(context).muted, height: 1.6),
        ),
      ],
    ],
  );
}

class LunarHero extends StatelessWidget {
  const LunarHero({
    super.key,
    required this.label,
    required this.value,
    this.unit = '张',
    this.subtitle,
    this.fullMoon = false,
    this.child,
  });
  final String label, value, unit;
  final String? subtitle;
  final bool fullMoon;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final p = LunarPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: p.night,
        borderRadius: BorderRadius.circular(23),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: p.moon),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: p.moon, fontSize: 14)),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          text: value,
                          children: [
                            TextSpan(
                              text: ' $unit',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        semanticsLabel: '$label，$value $unit',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 58,
                          height: 1,
                          color: p.moon,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: p.moon.withValues(alpha: .88),
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ],
                );
                if (MediaQuery.textScalerOf(context).scale(14) > 23 &&
                    box.maxWidth < 400) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text,
                      Align(
                        alignment: Alignment.centerRight,
                        child: LunarMoon(full: fullMoon, size: 92),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 10),
                    LunarMoon(
                      full: fullMoon,
                      size: box.maxWidth < 300 ? 92 : 110,
                    ),
                  ],
                );
              },
            ),
            if (child != null) ...[const SizedBox(height: 20), child!],
          ],
        ),
      ),
    );
  }
}

class LunarStats extends StatelessWidget {
  const LunarStats(this.items, {super.key});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) {
    final p = LunarPalette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = math.max(
          1,
          math.min(items.length, (box.maxWidth / (100 * scale)).floor()),
        );
        final width = (box.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value) in items)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '$label，$value',
                  excludeSemantics: true,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              fontFamily: 'serif',
                              fontSize: 28,
                              color: p.jade,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            label,
                            style: TextStyle(fontSize: 13, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class LunarShortcut extends StatelessWidget {
  const LunarShortcut({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.warm = false,
  });
  final String label, hint;
  final IconData icon;
  final VoidCallback? onTap;
  final bool warm;
  @override
  Widget build(BuildContext context) {
    final p = LunarPalette.of(context);
    return Material(
      color: warm
          ? Color.alphaBlend(p.gold.withValues(alpha: .12), p.surface)
          : p.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                unawaited(FeedbackScope.of(context).tap());
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 110),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: p.jade),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 7),
                Text(
                  hint,
                  style: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LunarPair extends StatelessWidget {
  const LunarPair({super.key, required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (MediaQuery.textScalerOf(context).scale(14) > 21 &&
          box.maxWidth < 500) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );
}

class LunarBookCard extends StatelessWidget {
  const LunarBookCard({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = LunarPalette.of(context);
    final color = [
      p.jade,
      p.gold,
      Theme.of(context).colorScheme.tertiary,
    ][index % 3];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: child,
      ),
    );
  }
}
