import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../providers/settings_provider.dart';

/// A sleek AppBar title widget wrapped in a dynamic, theme-reactive animated border.
class AnimatedFlameTitle extends ConsumerStatefulWidget {
  final String title;

  const AnimatedFlameTitle({
    super.key,
    this.title = 'Phantek',
  });

  @override
  ConsumerState<AnimatedFlameTitle> createState() => _AnimatedFlameTitleState();
}

class _AnimatedFlameTitleState extends ConsumerState<AnimatedFlameTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _darkCyberColors = [
    Color(0xFF6366F1), // Electric Indigo
    Color(0xFF8B5CF6), // Neon Violet
    Color(0xFFEC4899), // Cyber Magenta
    Color(0xFF06B6D4), // Electric Cyan
    Color(0xFF3B82F6), // Royal Blue
    Color(0xFF6366F1), // Back to Indigo
  ];

  static const _amoledColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Purple
    Color(0xFF38BDF8), // Celestial Cyan
    Color(0xFFE2E8F0), // Starlight Silver
    Color(0xFF818CF8), // Soft Violet
    Color(0xFF6366F1),
  ];

  static const _sakuraColors = [
    Color(0xFFFF7597), // Rose Pink
    Color(0xFFFFB7C5), // Cherry Blossom
    Color(0xFFFF4081), // Vivid Blossom
    Color(0xFFFF8DA1), // Pastel Pink
    Color(0xFFFFC0CB), // Light Pink
    Color(0xFFFF7597),
  ];

  static const _lightColors = [
    Color(0xFF0284C7), // Sky Azure
    Color(0xFF8B5CF6), // Prismatic Violet
    Color(0xFFF43F5E), // Rose Quartz
    Color(0xFF06B6D4), // Arctic Cyan
    Color(0xFF38BDF8), // Light Cyan
    Color(0xFF0284C7),
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
    final themeMode = ref.watch(
      settingsNotifierProvider.select((s) => s.themeMode),
    );

    final effectiveMode = switch (themeMode) {
      AppThemeMode.system =>
        theme.brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light,
      _ => themeMode,
    };

    final (colors, icon, iconStartColor, iconEndColor) = switch (effectiveMode) {
      AppThemeMode.amoled => (
          _amoledColors,
          Icons.nights_stay_rounded,
          const Color(0xFF818CF8),
          const Color(0xFF38BDF8),
        ),
      AppThemeMode.amoledSakura => (
          _sakuraColors,
          Icons.local_florist_rounded,
          const Color(0xFFFF7597),
          const Color(0xFFFFB7C5),
        ),
      AppThemeMode.dark => (
          _darkCyberColors,
          Icons.auto_awesome_rounded,
          const Color(0xFF818CF8),
          const Color(0xFFEC4899),
        ),
      AppThemeMode.light => (
          _lightColors,
          Icons.wb_sunny_rounded,
          const Color(0xFF0284C7),
          const Color(0xFF8B5CF6),
        ),
      AppThemeMode.system => (
          _darkCyberColors,
          Icons.auto_awesome_rounded,
          const Color(0xFF818CF8),
          const Color(0xFFEC4899),
        ),
    };

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final iconColor = Color.lerp(
          iconStartColor,
          iconEndColor,
          (math.sin(progress * 2 * math.pi) + 1) / 2,
        );

        return FittedBox(
          fit: BoxFit.scaleDown,
          child: CustomPaint(
            painter: _FlameBorderPainter(
              progress: progress,
              colors: colors,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: iconColor,
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

    // 1. Vibrant outer glow
    final glowPaint = Paint()
      ..shader = SweepGradient(
        colors: colors.map((c) => c.withValues(alpha: 0.48)).toList(),
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    canvas.drawRRect(rrect, glowPaint);

    // 2. Sharp vibrant core border
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
