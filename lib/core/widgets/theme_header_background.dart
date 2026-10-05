import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../providers/settings_provider.dart';

/// A sleek, high-performance animated header background that adapts to the active theme.
///
/// Themes:
/// - [AppThemeMode.amoled]: Pitch-black night sky with a glowing crescent moon,
///   twinkling stars, and shooting meteor streaks.
/// - [AppThemeMode.amoledSakura]: OLED black with an artistic sakura tree branch
///   and fluttering pink cherry blossom petals.
/// - [AppThemeMode.dark]: Flowing cyber plasma aurora waves and floating luminescent embers.
/// - [AppThemeMode.light]: Radiant morning sunburst with rotating prism rays and golden bokeh sparkles.
/// - [AppThemeMode.system]: Dynamically follows the system brightness.
class ThemeHeaderBackground extends ConsumerStatefulWidget {
  const ThemeHeaderBackground({super.key});

  @override
  ConsumerState<ThemeHeaderBackground> createState() => _ThemeHeaderBackgroundState();
}

class _ThemeHeaderBackgroundState extends ConsumerState<ThemeHeaderBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(
      settingsNotifierProvider.select((s) => s.themeMode),
    );
    final brightness = Theme.of(context).brightness;

    // Resolve system mode
    final effectiveMode = switch (themeMode) {
      AppThemeMode.system =>
        brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light,
      _ => themeMode,
    };

    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            final painter = switch (effectiveMode) {
              AppThemeMode.amoled => _AmoledHeaderPainter(progress: progress),
              AppThemeMode.amoledSakura =>
                _SakuraHeaderPainter(progress: progress),
              AppThemeMode.dark => _DarkHeaderPainter(progress: progress),
              AppThemeMode.light => _LightHeaderPainter(progress: progress),
              AppThemeMode.system => _DarkHeaderPainter(progress: progress),
            };

            return CustomPaint(
              painter: painter,
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. AMOLED Header Painter (Crescent Moon, Twinkling Stars, Shooting Meteors)
// ═════════════════════════════════════════════════════════════════════════════

class _StarData {
  final double x; // normalized 0..1
  final double y; // normalized 0..1
  final double size;
  final double speed;
  final double phase;
  final bool hasCrossGlow;

  const _StarData(
    this.x,
    this.y,
    this.size,
    this.speed,
    this.phase, [
    this.hasCrossGlow = false,
  ]);
}

class _AmoledHeaderPainter extends CustomPainter {
  final double progress;

  _AmoledHeaderPainter({required this.progress});

  static final List<_StarData> _stars = [
    const _StarData(0.06, 0.28, 1.4, 2.3, 0.1),
    const _StarData(0.12, 0.68, 1.8, 1.7, 1.4, true),
    const _StarData(0.18, 0.22, 1.2, 3.1, 2.2),
    const _StarData(0.24, 0.54, 1.5, 2.0, 0.8),
    const _StarData(0.31, 0.35, 1.1, 1.5, 3.1),
    const _StarData(0.38, 0.72, 1.9, 2.6, 1.9, true),
    const _StarData(0.44, 0.18, 1.3, 3.4, 0.4),
    const _StarData(0.52, 0.62, 1.6, 1.9, 2.7),
    const _StarData(0.58, 0.30, 1.2, 2.8, 1.1),
    const _StarData(0.65, 0.75, 1.7, 1.6, 0.5, true),
    const _StarData(0.72, 0.25, 1.5, 2.4, 3.5),
    const _StarData(0.79, 0.65, 1.3, 3.0, 1.8),
    const _StarData(0.85, 0.32, 2.0, 1.8, 0.9, true),
    const _StarData(0.92, 0.70, 1.4, 2.2, 2.4),
    const _StarData(0.96, 0.20, 1.6, 2.7, 1.5),
    const _StarData(0.04, 0.80, 1.2, 3.2, 2.0),
    const _StarData(0.28, 0.82, 1.5, 1.4, 0.7),
    const _StarData(0.68, 0.48, 1.1, 2.9, 1.3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 1. OLED Pitch Black Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black,
    );

    // Subtle celestial gradient wash across top edge
    final skyWashPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.7, -0.6),
        radius: 1.2,
        colors: [
          const Color(0xFF1E1B4B).withValues(alpha: 0.35), // Deep Indigo night
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, skyWashPaint);

    // 2. Twinkling Stars
    final starPaint = Paint()..style = PaintingStyle.fill;
    final starGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final star in _stars) {
      final sx = star.x * size.width;
      final sy = star.y * size.height;
      final twinkle = 0.35 +
          0.65 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi * star.speed + star.phase));

      starPaint.color = Colors.white.withValues(alpha: twinkle * 0.9);
      canvas.drawCircle(Offset(sx, sy), star.size * 0.85, starPaint);

      // 4-point cross-glimmer for bright stars
      if (star.hasCrossGlow && twinkle > 0.75) {
        final glowLen = star.size * 2.8 * ((twinkle - 0.75) / 0.25);
        starGlowPaint.color = const Color(0xFFBAE6FD).withValues(alpha: (twinkle - 0.75) * 2.0);
        canvas.drawLine(Offset(sx - glowLen, sy), Offset(sx + glowLen, sy), starGlowPaint);
        canvas.drawLine(Offset(sx, sy - glowLen), Offset(sx, sy + glowLen), starGlowPaint);
      }
    }

    // 3. Glowing Crescent Moon (Near Top-Right)
    final moonCenter = Offset(size.width - 42, size.height * 0.44);
    const moonRadius = 13.5;

    // Ambient lunar atmospheric halo
    final moonGlowPaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    canvas.drawCircle(moonCenter, moonRadius * 1.5, moonGlowPaint);

    final outerMoon = Path()
      ..addOval(Rect.fromCircle(center: moonCenter, radius: moonRadius));
    final innerMoon = Path()
      ..addOval(
        Rect.fromCircle(
          center: moonCenter.translate(-moonRadius * 0.42, -moonRadius * 0.15),
          radius: moonRadius * 0.88,
        ),
      );
    final moonPath = Path.combine(PathOperation.difference, outerMoon, innerMoon);

    final moonPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFE2E8F0),
          Color(0xFF94A3B8),
        ],
      ).createShader(Rect.fromCircle(center: moonCenter, radius: moonRadius));

    canvas.drawPath(moonPath, moonPaint);

    // 4. Shooting Meteor / Falling Star
    _drawMeteor(canvas, size, progress, cycleStart: 0.08, cycleDuration: 0.22, startX: 0.78, startY: -10);
    _drawMeteor(canvas, size, progress, cycleStart: 0.58, cycleDuration: 0.20, startX: 0.42, startY: -10);
  }

  void _drawMeteor(
    Canvas canvas,
    Size size,
    double progress, {
    required double cycleStart,
    required double cycleDuration,
    required double startX,
    required double startY,
  }) {
    if (progress < cycleStart || progress > cycleStart + cycleDuration) return;

    final t = (progress - cycleStart) / cycleDuration;
    final travel = t * 180.0;
    final angle = math.pi * 0.26; // ~47 degrees diagonal

    final headX = startX * size.width + math.cos(angle) * travel;
    final headY = startY + math.sin(angle) * travel;

    final trailLength = 55.0 * math.sin(t * math.pi);
    final tailX = headX - math.cos(angle) * trailLength;
    final tailY = headY - math.sin(angle) * trailLength;

    if (trailLength <= 2) return;

    final meteorPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          const Color(0xFF67E8F9).withValues(alpha: 0.6),
          Colors.white,
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromPoints(Offset(tailX, tailY), Offset(headX, headY)))
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(tailX, tailY), Offset(headX, headY), meteorPaint);

    final sparkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(Offset(headX, headY), 1.8, sparkPaint);
  }

  @override
  bool shouldRepaint(covariant _AmoledHeaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. AMOLED SAKURA Header Painter (Cherry Tree Branch & Fluttering Petals)
// ═════════════════════════════════════════════════════════════════════════════

class _PetalData {
  final double startX; // normalized
  final double startY; // normalized
  final double size;
  final double fallSpeed;
  final double swaySpeed;
  final double swayAmplitude;
  final double rotSpeed;
  final double phase;

  const _PetalData(
    this.startX,
    this.startY,
    this.size,
    this.fallSpeed,
    this.swaySpeed,
    this.swayAmplitude,
    this.rotSpeed,
    this.phase,
  );
}

class _SakuraHeaderPainter extends CustomPainter {
  final double progress;

  _SakuraHeaderPainter({required this.progress});

  static final List<_PetalData> _petals = [
    const _PetalData(0.88, 0.1, 6.5, 1.2, 2.4, 22.0, 1.8, 0.0),
    const _PetalData(0.78, 0.3, 5.0, 0.9, 1.8, 16.0, 2.2, 1.2),
    const _PetalData(0.65, 0.0, 7.2, 1.4, 2.1, 26.0, 1.5, 2.5),
    const _PetalData(0.55, 0.4, 4.8, 1.0, 2.8, 18.0, 3.0, 0.7),
    const _PetalData(0.42, 0.2, 6.0, 1.3, 1.9, 24.0, 2.0, 3.2),
    const _PetalData(0.30, 0.5, 5.5, 1.1, 2.5, 20.0, 1.7, 1.8),
    const _PetalData(0.20, 0.1, 6.8, 1.5, 2.0, 28.0, 2.4, 0.4),
    const _PetalData(0.12, 0.3, 4.5, 0.8, 2.2, 14.0, 2.8, 2.9),
    const _PetalData(0.92, 0.6, 5.8, 1.2, 2.6, 20.0, 1.9, 1.5),
    const _PetalData(0.72, 0.7, 6.2, 1.4, 1.7, 25.0, 2.1, 0.9),
    const _PetalData(0.48, 0.8, 5.2, 1.0, 2.3, 17.0, 2.6, 2.2),
    const _PetalData(0.05, 0.6, 6.4, 1.3, 2.0, 22.0, 1.6, 3.7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 1. OLED Pitch Black Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black,
    );

    // Soft subtle blooming sakura horizon glow
    final sakuraGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.7),
        radius: 1.1,
        colors: [
          const Color(0xFFFF7597).withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sakuraGlow);

    // 2. Artistic Sakura Tree Branch (Top-Right side)
    _drawSakuraBranch(canvas, size);

    // 3. Falling / Fluttering Sakura Petals
    for (final petal in _petals) {
      _drawPetal(canvas, size, petal, progress);
    }
  }

  void _drawSakuraBranch(Canvas canvas, Size size) {
    final branchPaint = Paint()
      ..color = const Color(0xFF2E1720) // Deep dark cherry wood
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final branchWidth = size.width;
    final startPt = Offset(branchWidth + 6, -6);

    // Main Bough
    final mainBranch = Path()
      ..moveTo(startPt.dx, startPt.dy)
      ..cubicTo(
        branchWidth - 30,
        size.height * 0.15,
        branchWidth - 65,
        size.height * 0.22,
        branchWidth - 110,
        size.height * 0.32,
      );

    branchPaint.strokeWidth = 3.2;
    canvas.drawPath(mainBranch, branchPaint);

    // Secondary twigs
    final twig1 = Path()
      ..moveTo(branchWidth - 50, size.height * 0.18)
      ..quadraticBezierTo(
        branchWidth - 75,
        size.height * 0.48,
        branchWidth - 88,
        size.height * 0.65,
      );
    branchPaint.strokeWidth = 1.8;
    canvas.drawPath(twig1, branchPaint);

    final twig2 = Path()
      ..moveTo(branchWidth - 85, size.height * 0.27)
      ..quadraticBezierTo(
        branchWidth - 115,
        size.height * 0.18,
        branchWidth - 138,
        size.height * 0.22,
      );
    branchPaint.strokeWidth = 1.4;
    canvas.drawPath(twig2, branchPaint);

    // Blooming Sakura Flowers on the Branch
    _drawBlossom(canvas, Offset(branchWidth - 45, size.height * 0.18), 7.5, 0.4);
    _drawBlossom(canvas, Offset(branchWidth - 88, size.height * 0.65), 6.5, 1.2);
    _drawBlossom(canvas, Offset(branchWidth - 110, size.height * 0.32), 8.0, 2.1);
    _drawBlossom(canvas, Offset(branchWidth - 138, size.height * 0.22), 6.0, 0.9);
    _drawBlossom(canvas, Offset(branchWidth - 25, size.height * 0.08), 7.0, 3.0);

    // Tiny buds
    _drawBud(canvas, Offset(branchWidth - 75, size.height * 0.48), 3.0);
    _drawBud(canvas, Offset(branchWidth - 125, size.height * 0.19), 2.6);
  }

  void _drawBlossom(Canvas canvas, Offset center, double radius, double rot) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rot);

    final petalPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFFFB7C5),
          Color(0xFFFF7597),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius))
      ..style = PaintingStyle.fill;

    // 5-petal flower
    for (var i = 0; i < 5; i++) {
      final angle = (i * 2 * math.pi) / 5;
      final petalPath = Path();
      final tipX = math.cos(angle) * radius;
      final tipY = math.sin(angle) * radius;
      final sideAngle1 = angle - 0.4;
      final sideAngle2 = angle + 0.4;
      final side1 = Offset(math.cos(sideAngle1) * radius * 0.6, math.sin(sideAngle1) * radius * 0.6);
      final side2 = Offset(math.cos(sideAngle2) * radius * 0.6, math.sin(sideAngle2) * radius * 0.6);

      petalPath.moveTo(0, 0);
      petalPath.quadraticBezierTo(side1.dx, side1.dy, tipX, tipY);
      petalPath.quadraticBezierTo(side2.dx, side2.dy, 0, 0);
      canvas.drawPath(petalPath, petalPaint);
    }

    // Yellow stamen center
    final stamenPaint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawCircle(Offset.zero, radius * 0.22, stamenPaint);

    canvas.restore();
  }

  void _drawBud(Canvas canvas, Offset center, double radius) {
    final budPaint = Paint()
      ..color = const Color(0xFFFF7597)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, budPaint);
  }

  void _drawPetal(Canvas canvas, Size size, _PetalData petal, double progress) {
    final totalFall = size.height + 40.0;
    final currentY = ((petal.startY * totalFall) + progress * petal.fallSpeed * totalFall) % totalFall - 20.0;

    final sway = math.sin(progress * 2 * math.pi * petal.swaySpeed + petal.phase) * petal.swayAmplitude;
    final currentX = (petal.startX * size.width + sway + size.width) % size.width;

    final angle = progress * 2 * math.pi * petal.rotSpeed + petal.phase;
    final flutterScale = (math.cos(progress * 2 * math.pi * petal.swaySpeed * 1.5 + petal.phase) * 0.4 + 0.6).abs();

    canvas.save();
    canvas.translate(currentX, currentY);
    canvas.rotate(angle);
    canvas.scale(1.0, flutterScale);

    final petalPath = Path()
      ..moveTo(0, -petal.size)
      ..cubicTo(petal.size * 0.8, -petal.size * 0.7, petal.size * 0.7, petal.size * 0.5, 0, petal.size)
      ..cubicTo(-petal.size * 0.7, petal.size * 0.5, -petal.size * 0.8, -petal.size * 0.7, 0, -petal.size);

    final petalPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFFF0F5).withValues(alpha: 0.95),
          const Color(0xFFFFB7C5).withValues(alpha: 0.9),
          const Color(0xFFFF7597).withValues(alpha: 0.8),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: petal.size))
      ..style = PaintingStyle.fill;

    canvas.drawPath(petalPath, petalPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SakuraHeaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. DARK Header Painter (Cyber Plasma Aurora Waves & Floating Embers)
// ═════════════════════════════════════════════════════════════════════════════

class _EmberData {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double phase;

  const _EmberData(this.x, this.y, this.size, this.speed, this.phase);
}

class _DarkHeaderPainter extends CustomPainter {
  final double progress;

  _DarkHeaderPainter({required this.progress});

  static final List<_EmberData> _embers = [
    const _EmberData(0.08, 0.8, 1.8, 1.1, 0.2),
    const _EmberData(0.18, 0.4, 2.2, 0.9, 1.5),
    const _EmberData(0.28, 0.9, 1.5, 1.3, 2.7),
    const _EmberData(0.40, 0.6, 2.4, 0.8, 0.8),
    const _EmberData(0.52, 0.3, 1.6, 1.4, 3.1),
    const _EmberData(0.64, 0.85, 2.0, 1.0, 1.9),
    const _EmberData(0.76, 0.5, 1.4, 1.2, 0.4),
    const _EmberData(0.88, 0.75, 2.5, 0.7, 2.3),
    const _EmberData(0.95, 0.2, 1.7, 1.5, 1.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dark surface background (#0E0E0E)
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0E0E0E),
    );

    // 2. Dual Undulating Cyber Aurora Plasma Ribbons
    final wave1 = Path();
    final wave2 = Path();

    wave1.moveTo(0, size.height * 0.4);
    wave2.moveTo(0, size.height * 0.6);

    final w = size.width;
    for (double x = 0; x <= w; x += 12) {
      final normX = x / w;
      final y1 = size.height * 0.42 +
          math.sin(normX * 2 * math.pi + progress * 2 * math.pi) * 12.0 +
          math.cos(normX * 4 * math.pi - progress * 2 * math.pi * 0.5) * 6.0;
      final y2 = size.height * 0.58 +
          math.cos(normX * 2.5 * math.pi - progress * 2 * math.pi) * 10.0 +
          math.sin(normX * 3 * math.pi + progress * 2 * math.pi * 0.7) * 7.0;

      wave1.lineTo(x, y1);
      wave2.lineTo(x, y2);
    }

    // Cyber Indigo/Violet Plasma Glow
    final wave1Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF6366F1).withValues(alpha: 0.25),
          const Color(0xFF9333EA).withValues(alpha: 0.35),
          const Color(0xFFEC4899).withValues(alpha: 0.25),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawPath(wave1, wave1Paint);

    // Electric Cyan/Blue Glow
    final wave2Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: 0.22),
          const Color(0xFF3B82F6).withValues(alpha: 0.30),
          const Color(0xFF6366F1).withValues(alpha: 0.20),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(wave2, wave2Paint);

    // 3. Floating Cosmic Firefly Embers
    for (final ember in _embers) {
      final curY = (ember.y * size.height - progress * ember.speed * size.height + size.height) % size.height;
      final sway = math.sin(progress * 2 * math.pi * 1.5 + ember.phase) * 10.0;
      final curX = (ember.x * size.width + sway + size.width) % size.width;

      final pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi * 2.5 + ember.phase));

      final emberGlow = Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: pulse * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
      canvas.drawCircle(Offset(curX, curY), ember.size * 1.8, emberGlow);

      final emberCore = Paint()
        ..color = const Color(0xFFE0E7FF).withValues(alpha: pulse * 0.85);
      canvas.drawCircle(Offset(curX, curY), ember.size * 0.8, emberCore);
    }
  }

  @override
  bool shouldRepaint(covariant _DarkHeaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. LIGHT Header Painter (Radiant Sunburst, Rotating Rays & Golden Sparkles)
// ═════════════════════════════════════════════════════════════════════════════

class _SparkleData {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double phase;

  const _SparkleData(this.x, this.y, this.size, this.speed, this.phase);
}

class _LightHeaderPainter extends CustomPainter {
  final double progress;

  _LightHeaderPainter({required this.progress});

  static final List<_SparkleData> _sparkles = [
    const _SparkleData(0.08, 0.65, 2.2, 1.2, 0.4),
    const _SparkleData(0.18, 0.35, 1.6, 2.0, 1.8),
    const _SparkleData(0.32, 0.75, 2.4, 1.5, 2.9),
    const _SparkleData(0.45, 0.25, 1.8, 1.8, 0.7),
    const _SparkleData(0.58, 0.68, 2.0, 1.4, 3.3),
    const _SparkleData(0.70, 0.38, 2.6, 1.1, 1.2),
    const _SparkleData(0.82, 0.70, 1.5, 2.2, 2.1),
    const _SparkleData(0.92, 0.45, 2.2, 1.7, 0.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Crisp light canvas with warm solar morning glow
    final solarGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.88, -0.6),
        radius: 1.3,
        colors: [
          const Color(0xFFFEF3C7).withValues(alpha: 0.6), // Warm Amber Cream
          const Color(0xFFFDE68A).withValues(alpha: 0.2),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, solarGlow);

    // 2. Radiant Golden Sunburst & Rotating Solar Prism Rays (Top-Right)
    final sunCenter = Offset(size.width - 36, size.height * 0.38);
    const sunRadius = 14.0;

    // Ambient Sun Halo
    final sunHalo = Paint()
      ..color = const Color(0xFFFBBF24).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    canvas.drawCircle(sunCenter, sunRadius * 1.8, sunHalo);

    // Rotating Rays
    canvas.save();
    canvas.translate(sunCenter.dx, sunCenter.dy);
    canvas.rotate(progress * 2 * math.pi * 0.1); // Slow majestic rotation

    final rayPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF59E0B).withValues(alpha: 0.35),
          const Color(0xFFFBBF24).withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: sunRadius * 3.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 8; i++) {
      final rayAngle = (i * 2 * math.pi) / 8;
      final rayLen = sunRadius * (2.2 + 0.4 * math.sin(progress * 2 * math.pi * 2.0 + i));
      canvas.drawLine(
        Offset(math.cos(rayAngle) * (sunRadius * 1.2), math.sin(rayAngle) * (sunRadius * 1.2)),
        Offset(math.cos(rayAngle) * rayLen, math.sin(rayAngle) * rayLen),
        rayPaint,
      );
    }
    canvas.restore();

    // Solid Sun Core
    final sunCorePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFBEB),
          Color(0xFFFDE68A),
          Color(0xFFF59E0B),
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(sunCenter, sunRadius, sunCorePaint);

    // 3. Floating Golden Bokeh Dust & Sparkles
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    final sparkCross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    for (final s in _sparkles) {
      final sx = s.x * size.width;
      final sy = (s.y * size.height - progress * s.speed * 15.0 + size.height) % size.height;
      final twinkle = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi * s.speed + s.phase));

      sparkPaint.color = const Color(0xFFD97706).withValues(alpha: twinkle * 0.6);
      canvas.drawCircle(Offset(sx, sy), s.size * 0.85, sparkPaint);

      if (twinkle > 0.7) {
        final sparkLen = s.size * 2.2 * ((twinkle - 0.7) / 0.3);
        sparkCross.color = const Color(0xFFF59E0B).withValues(alpha: (twinkle - 0.7) * 2.2);
        canvas.drawLine(Offset(sx - sparkLen, sy), Offset(sx + sparkLen, sy), sparkCross);
        canvas.drawLine(Offset(sx, sy - sparkLen), Offset(sx, sy + sparkLen), sparkCross);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LightHeaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
