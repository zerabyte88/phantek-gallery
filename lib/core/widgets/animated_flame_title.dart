import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A sleek AppBar title widget wrapped in a dynamic, fiery animated border.
class AnimatedFlameTitle extends StatefulWidget {
  final String title;

  const AnimatedFlameTitle({
    super.key,
    this.title = 'Phantek',
  });

  @override
  State<AnimatedFlameTitle> createState() => _AnimatedFlameTitleState();
}

class _AnimatedFlameTitleState extends State<AnimatedFlameTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _flameColors = [
    Color(0xFFFF1E00), // Deep Crimson Red
    Color(0xFFFF6A00), // Hot Blaze Orange
    Color(0xFFFFD000), // Fiery Gold
    Color(0xFFFF3B30), // Electric Coral
    Color(0xFFFF9500), // Bright Amber
    Color(0xFFFF1E00), // Back to Crimson
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final flameIconColor = Color.lerp(
          const Color(0xFFFF3D00),
          const Color(0xFFFFC107),
          (math.sin(progress * 2 * math.pi) + 1) / 2,
        );

        return FittedBox(
          fit: BoxFit.scaleDown,
          child: CustomPaint(
            painter: _FlameBorderPainter(
              progress: progress,
              colors: _flameColors,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: theme.colorScheme.surface.withValues(alpha: 0.82),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 17,
                    color: flameIconColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlameBorderPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _FlameBorderPainter({
    required this.progress,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    // 1. Fiery outer glow
    final glowPaint = Paint()
      ..shader = SweepGradient(
        colors: colors.map((c) => c.withValues(alpha: 0.48)).toList(),
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    canvas.drawRRect(rrect, glowPaint);

    // 2. Sharp vibrant fiery core border
    final borderPaint = Paint()
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _FlameBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
