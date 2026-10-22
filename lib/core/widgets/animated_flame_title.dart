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

  // Snowfall
  static const _darkColors = [
    Color(0xFF38BDF8),
    Color(0xFFCFF0FF),
    Color(0xFFBAE6FD),
    Color(0xFFFDE047),
    Color(0xFF0284C7),
    Color(0xFF38BDF8),
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

  static const _cleanLightColors = [
    Color(0xFF0EA5E9),
    Color(0xFF38BDF8),
    Color(0xFF7DD3FC),
    Color(0xFFBAE6FD),
    Color(0xFF0284C7),
    Color(0xFF0EA5E9),
  ];

  static const _amoledPureColors = [
    Color(0xFF60A5FA),
    Color(0xFF93C5FD),
    Color(0xFF3B82F6),
    Color(0xFFBFDBFE),
    Color(0xFF1D4ED8),
    Color(0xFF60A5FA),
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
      AppThemeMode.system => theme.brightness == Brightness.dark
          ? AppThemeMode.amoledPure
          : AppThemeMode.cleanLight,
      _ => themeMode,
    };

    final (colors, icon, iconStartColor, iconEndColor) =
        switch (effectiveMode) {
      AppThemeMode.amoledMidnight => (
          _amoledColors,
          Icons.nights_stay_rounded,
          const Color(0xFF818CF8),
          const Color(0xFF38BDF8),
        ),
      AppThemeMode.amoledPure => (
          _amoledPureColors,
          Icons.brightness_2_outlined,
          const Color(0xFF60A5FA),
          const Color(0xFF93C5FD),
        ),
      AppThemeMode.amoledSakura => (
          _sakuraColors,
          Icons.local_florist_rounded,
          const Color(0xFFFF7597),
          const Color(0xFFFFB7C5),
        ),
      AppThemeMode.cleanLight => (
          _cleanLightColors,
          Icons.wb_sunny_outlined,
          const Color(0xFF0EA5E9),
          const Color(0xFF38BDF8),
        ),
      AppThemeMode.amoledSnowfall => (
          _darkColors,
          Icons.ac_unit_rounded,
          const Color(0xFFCFF0FF),
          const Color(0xFF38BDF8),
        ),
      AppThemeMode.light => (
          _lightColors,
          Icons.wb_sunny_rounded,
          const Color(0xFF0284C7),
          const Color(0xFF8B5CF6),
        ),
      AppThemeMode.system => (
          _amoledPureColors,
          Icons.brightness_2_outlined,
          const Color(0xFF60A5FA),
          const Color(0xFF93C5FD),
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
