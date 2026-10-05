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
///   with fresh leaves, abundant blossoms, and fluttering pink cherry blossom petals.
/// - [AppThemeMode.dark]: Luminous volumetric Aurora Borealis curtains with shimmering ray pillars and firefly embers.
/// - [AppThemeMode.light]: Prismatic morning breeze with flowing pastel silk waves, floating pearlescent glass orbs, and diamond prism sparkles.
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
  final double speed; // integer multiplier for seamless continuous looping
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
    const _StarData(0.06, 0.28, 1.4, 2.0, 0.1),
    const _StarData(0.12, 0.68, 1.8, 1.0, 1.4, true),
    const _StarData(0.18, 0.22, 1.2, 3.0, 2.2),
    const _StarData(0.24, 0.54, 1.5, 2.0, 0.8),
    const _StarData(0.31, 0.35, 1.1, 1.0, 3.1),
    const _StarData(0.38, 0.72, 1.9, 3.0, 1.9, true),
    const _StarData(0.44, 0.18, 1.3, 4.0, 0.4),
    const _StarData(0.52, 0.62, 1.6, 2.0, 2.7),
    const _StarData(0.58, 0.30, 1.2, 3.0, 1.1),
    const _StarData(0.65, 0.75, 1.7, 1.0, 0.5, true),
    const _StarData(0.72, 0.25, 1.5, 2.0, 3.5),
    const _StarData(0.79, 0.65, 1.3, 3.0, 1.8),
    const _StarData(0.85, 0.32, 2.0, 2.0, 0.9, true),
    const _StarData(0.92, 0.70, 1.4, 2.0, 2.4),
    const _StarData(0.96, 0.20, 1.6, 3.0, 1.5),
    const _StarData(0.04, 0.80, 1.2, 3.0, 2.0),
    const _StarData(0.28, 0.82, 1.5, 1.0, 0.7),
    const _StarData(0.68, 0.48, 1.1, 3.0, 1.3),
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

    // 2. Twinkling Stars (Continuous integer harmonics)
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
    final moonCenter = Offset(size.width - 42, math.min(size.height * 0.28, 48.0));
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

    // 4. Shooting Celestial Meteor Shower (6 Staggered Streaks Traversing Past Bottom Edge)
    _drawMeteor(canvas, size, progress, cycleStart: 0.04, cycleDuration: 0.17, startX: 0.80, startY: -15, angle: math.pi * 0.26, glowColor: const Color(0xFF67E8F9));
    _drawMeteor(canvas, size, progress, cycleStart: 0.19, cycleDuration: 0.15, startX: 0.44, startY: -15, angle: math.pi * 0.28, glowColor: const Color(0xFF93C5FD));
    _drawMeteor(canvas, size, progress, cycleStart: 0.36, cycleDuration: 0.18, startX: 0.95, startY: -15, angle: math.pi * 0.25, glowColor: const Color(0xFF38BDF8));
    _drawMeteor(canvas, size, progress, cycleStart: 0.54, cycleDuration: 0.16, startX: 0.28, startY: -15, angle: math.pi * 0.27, glowColor: const Color(0xFFE2E8F0));
    _drawMeteor(canvas, size, progress, cycleStart: 0.70, cycleDuration: 0.18, startX: 0.68, startY: -15, angle: math.pi * 0.26, glowColor: const Color(0xFF67E8F9));
    _drawMeteor(canvas, size, progress, cycleStart: 0.86, cycleDuration: 0.15, startX: 0.52, startY: -15, angle: math.pi * 0.29, glowColor: const Color(0xFF818CF8));
  }

  void _drawMeteor(
    Canvas canvas,
    Size size,
    double progress, {
    required double cycleStart,
    required double cycleDuration,
    required double startX,
    required double startY,
    double angle = math.pi * 0.26,
    Color glowColor = const Color(0xFF67E8F9),
  }) {
    if (progress < cycleStart || progress > cycleStart + cycleDuration) return;

    final t = (progress - cycleStart) / cycleDuration;
    // Dynamic trajectory guarantees meteor crosses fully through and beyond bottom edge
    final targetY = size.height + 50.0;
    final totalVerticalTravel = targetY - startY;
    final totalTravel = totalVerticalTravel / math.sin(angle);
    final currentTravel = t * totalTravel;

    final headX = startX * size.width + math.cos(angle) * currentTravel;
    final headY = startY + math.sin(angle) * currentTravel;

    // Sustained trail length: grows quickly upon entry, stays full-bodied throughout fall
    final maxTrail = math.min(size.width * 0.22, 65.0);
    final trailLength = maxTrail * math.min(1.0, t * 4.0);
    final tailX = headX - math.cos(angle) * trailLength;
    final tailY = headY - math.sin(angle) * trailLength;

    if (trailLength <= 1) return;

    // Opacity: rapid fade-in upon entry (0..0.12), full brightness, smooth fade-out as head exits past bottom (0.82..1.0)
    final opacity = (t < 0.12
            ? (t / 0.12)
            : (t > 0.82 ? ((1.0 - t) / 0.18) : 1.0))
        .clamp(0.0, 1.0);

    final meteorPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          glowColor.withValues(alpha: 0.65 * opacity),
          Colors.white.withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromPoints(Offset(tailX, tailY), Offset(headX, headY)))
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(tailX, tailY), Offset(headX, headY), meteorPaint);

    final sparkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    canvas.drawCircle(Offset(headX, headY), 2.0, sparkPaint);
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
  final double fallSpeed; // integer cycle speed
  final double swaySpeed; // integer cycle speed
  final double swayAmplitude;
  final double rotSpeed; // integer cycle speed
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
    const _PetalData(0.88, 0.1, 6.5, 1.0, 2.0, 22.0, 2.0, 0.0),
    const _PetalData(0.78, 0.3, 5.0, 1.0, 1.0, 16.0, 2.0, 1.2),
    const _PetalData(0.65, 0.0, 7.2, 2.0, 2.0, 26.0, 1.0, 2.5),
    const _PetalData(0.55, 0.4, 4.8, 1.0, 3.0, 18.0, 3.0, 0.7),
    const _PetalData(0.42, 0.2, 6.0, 1.0, 2.0, 24.0, -2.0, 3.2),
    const _PetalData(0.30, 0.5, 5.5, 1.0, 2.0, 20.0, 1.0, 1.8),
    const _PetalData(0.20, 0.1, 6.8, 2.0, 2.0, 28.0, 2.0, 0.4),
    const _PetalData(0.12, 0.3, 4.5, 1.0, 2.0, 14.0, -2.0, 2.9),
    const _PetalData(0.92, 0.6, 5.8, 1.0, 3.0, 20.0, 2.0, 1.5),
    const _PetalData(0.72, 0.7, 6.2, 2.0, 1.0, 25.0, 2.0, 0.9),
    const _PetalData(0.48, 0.8, 5.2, 1.0, 2.0, 17.0, -1.0, 2.2),
    const _PetalData(0.05, 0.6, 6.4, 1.0, 2.0, 22.0, 1.0, 3.7),
    const _PetalData(0.35, 0.85, 4.8, 2.0, 3.0, 19.0, 2.0, 4.1),
    const _PetalData(0.82, 0.45, 5.6, 1.0, 2.0, 23.0, -2.0, 0.5),
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

    // 2. Artistic Multi-Branch Sakura Tree with Leaves & Blossoms (Top-Right side)
    _drawSakuraBranch(canvas, size);

    // 3. Falling / Fluttering Sakura Petals (Seamless continuous loop)
    for (final petal in _petals) {
      _drawPetal(canvas, size, petal, progress);
    }
  }

  void _drawSakuraBranch(Canvas canvas, Size size) {
    final branchPaint = Paint()
      ..color = const Color(0xFF2B1620) // Deep dark cherry wood
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // ── 1. Main Trunk ────────────────────────────────────────────────────────
    final trunk = Path()
      ..moveTo(w + 10, -8)
      ..cubicTo(w - 35, h * 0.12, w - 75, h * 0.20, w - 120, h * 0.26);
    branchPaint.strokeWidth = 3.6;
    canvas.drawPath(trunk, branchPaint);

    // ── 2. Primary Branch: Central-Left Deep Reach ────────────────────────────
    final midBranch = Path()
      ..moveTo(w - 120, h * 0.26)
      ..cubicTo(w - 155, h * 0.28, w - 180, h * 0.22, w - 215, h * 0.25);
    branchPaint.strokeWidth = 2.2;
    canvas.drawPath(midBranch, branchPaint);

    // Mid twigs
    final twigMid1 = Path()
      ..moveTo(w - 165, h * 0.27)
      ..quadraticBezierTo(w - 175, h * 0.35, w - 190, h * 0.40);
    final twigMid2 = Path()
      ..moveTo(w - 195, h * 0.24)
      ..quadraticBezierTo(w - 210, h * 0.17, w - 230, h * 0.19);
    branchPaint.strokeWidth = 1.3;
    canvas.drawPath(twigMid1, branchPaint);
    canvas.drawPath(twigMid2, branchPaint);

    // ── 3. Primary Branch: Lower Sweeping Bough ──────────────────────────────
    final lowBranch = Path()
      ..moveTo(w - 60, h * 0.17)
      ..cubicTo(w - 85, h * 0.40, w - 95, h * 0.62, w - 112, h * 0.80);
    branchPaint.strokeWidth = 2.4;
    canvas.drawPath(lowBranch, branchPaint);

    // Low twigs
    final twigLow1 = Path()
      ..moveTo(w - 80, h * 0.38)
      ..quadraticBezierTo(w - 100, h * 0.44, w - 118, h * 0.48);
    final twigLow2 = Path()
      ..moveTo(w - 100, h * 0.65)
      ..quadraticBezierTo(w - 118, h * 0.78, w - 130, h * 0.90);
    final twigLow3 = Path()
      ..moveTo(w - 90, h * 0.52)
      ..quadraticBezierTo(w - 75, h * 0.62, w - 62, h * 0.70);
    branchPaint.strokeWidth = 1.3;
    canvas.drawPath(twigLow1, branchPaint);
    canvas.drawPath(twigLow2, branchPaint);
    canvas.drawPath(twigLow3, branchPaint);

    // ── 4. Primary Branch: Upper Crest Bough ─────────────────────────────────
    final topBranch = Path()
      ..moveTo(w - 95, h * 0.22)
      ..cubicTo(w - 120, h * 0.10, w - 145, h * 0.08, w - 170, h * 0.12);
    branchPaint.strokeWidth = 2.0;
    canvas.drawPath(topBranch, branchPaint);

    // Top twigs
    final twigTop1 = Path()
      ..moveTo(w - 135, h * 0.09)
      ..quadraticBezierTo(w - 142, h * 0.03, w - 152, h * -0.02);
    final twigTop2 = Path()
      ..moveTo(w - 155, h * 0.11)
      ..quadraticBezierTo(w - 168, h * 0.16, w - 182, h * 0.17);
    branchPaint.strokeWidth = 1.3;
    canvas.drawPath(twigTop1, branchPaint);
    canvas.drawPath(twigTop2, branchPaint);

    // ── 5. Sakura Leaves (Dedaunan) ──────────────────────────────────────────
    // Leaves on main trunk & base
    _drawLeaf(canvas, Offset(w - 32, h * 0.08), 8.5, -0.6);
    _drawLeaf(canvas, Offset(w - 55, h * 0.15), 7.5, 0.8);
    _drawLeaf(canvas, Offset(w - 70, h * 0.23), 8.0, -1.2);

    // Leaves on lower branch & twigs
    _drawLeaf(canvas, Offset(w - 78, h * 0.36), 7.0, 1.4);
    _drawLeaf(canvas, Offset(w - 116, h * 0.46), 7.5, -0.3);
    _drawLeaf(canvas, Offset(w - 92, h * 0.54), 6.8, 2.1);
    _drawLeaf(canvas, Offset(w - 64, h * 0.68), 6.5, 0.4);
    _drawLeaf(canvas, Offset(w - 108, h * 0.76), 7.2, 1.8);
    _drawLeaf(canvas, Offset(w - 128, h * 0.88), 6.0, 2.5);

    // Leaves on central reach
    _drawLeaf(canvas, Offset(w - 118, h * 0.24), 8.0, 0.2);
    _drawLeaf(canvas, Offset(w - 145, h * 0.28), 7.0, 1.1);
    _drawLeaf(canvas, Offset(w - 188, h * 0.38), 6.5, 2.0);
    _drawLeaf(canvas, Offset(w - 212, h * 0.23), 7.0, -0.7);
    _drawLeaf(canvas, Offset(w - 228, h * 0.18), 6.0, -1.5);

    // Leaves on upper crest
    _drawLeaf(canvas, Offset(w - 132, h * 0.08), 7.2, -1.8);
    _drawLeaf(canvas, Offset(w - 150, h * 0.01), 6.0, -2.4);
    _drawLeaf(canvas, Offset(w - 168, h * 0.10), 6.8, 0.3);
    _drawLeaf(canvas, Offset(w - 180, h * 0.15), 6.2, 1.0);

    // ── 6. Blooming Sakura Blossoms (Full 5-Petal) ───────────────────────────
    _drawBlossom(canvas, Offset(w - 30, h * 0.09), 7.5, 0.4);
    _drawBlossom(canvas, Offset(w - 60, h * 0.17), 9.0, 1.8);
    _drawBlossom(canvas, Offset(w - 120, h * 0.26), 8.5, 2.7);
    _drawBlossom(canvas, Offset(w - 165, h * 0.27), 7.0, 0.9);
    _drawBlossom(canvas, Offset(w - 215, h * 0.25), 6.5, 3.1);
    _drawBlossom(canvas, Offset(w - 190, h * 0.40), 6.0, 1.3);

    _drawBlossom(canvas, Offset(w - 80, h * 0.38), 7.5, 0.6);
    _drawBlossom(canvas, Offset(w - 118, h * 0.48), 6.5, 2.2);
    _drawBlossom(canvas, Offset(w - 112, h * 0.80), 7.0, 1.5);
    _drawBlossom(canvas, Offset(w - 62, h * 0.70), 5.8, 0.8);

    _drawBlossom(canvas, Offset(w - 135, h * 0.09), 6.8, 2.0);
    _drawBlossom(canvas, Offset(w - 170, h * 0.12), 6.2, 0.5);

    // ── 7. Buds & Bud Clusters ───────────────────────────────────────────────
    _drawBud(canvas, Offset(w - 152, h * -0.02), 3.0);
    _drawBud(canvas, Offset(w - 182, h * 0.17), 2.8);
    _drawBud(canvas, Offset(w - 230, h * 0.19), 2.8);
    _drawBud(canvas, Offset(w - 130, h * 0.90), 3.2);
    _drawBud(canvas, Offset(w - 98, h * 0.66), 2.6);
    _drawBud(canvas, Offset(w - 146, h * 0.29), 2.5);
  }

  void _drawLeaf(Canvas canvas, Offset stem, double length, double angle) {
    canvas.save();
    canvas.translate(stem.dx, stem.dy);
    canvas.rotate(angle);

    final leafPath = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.4, -length * 0.28, length, 0)
      ..quadraticBezierTo(length * 0.4, length * 0.28, 0, 0);

    final leafPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF3B5D3E), // Deep tender leaf green
          const Color(0xFF5A855A), // Vibrant spring green
          const Color(0xFF82A882), // Soft leaf tip
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, -length * 0.3, length, length * 0.6))
      ..style = PaintingStyle.fill;

    canvas.drawPath(leafPath, leafPaint);

    // Subtle central vein
    final veinPaint = Paint()
      ..color = const Color(0xFF2C4A2F).withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(length * 0.8, 0), veinPaint);

    canvas.restore();
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
    final flutterScale = (math.cos(progress * 2 * math.pi * petal.swaySpeed + petal.phase) * 0.35 + 0.65).abs();

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
// 3. DARK Header Painter (Volumetric Aurora Borealis Curtains & Embers)
// ═════════════════════════════════════════════════════════════════════════════

class _EmberData {
  final double x;
  final double y;
  final double size;
  final double speed; // integer cycle speed
  final double phase;

  const _EmberData(this.x, this.y, this.size, this.speed, this.phase);
}

class _DarkHeaderPainter extends CustomPainter {
  final double progress;

  _DarkHeaderPainter({required this.progress});

  static final List<_EmberData> _embers = [
    const _EmberData(0.08, 0.8, 1.8, 1.0, 0.2),
    const _EmberData(0.18, 0.4, 2.2, 1.0, 1.5),
    const _EmberData(0.28, 0.9, 1.5, 1.0, 2.7),
    const _EmberData(0.40, 0.6, 2.4, 1.0, 0.8),
    const _EmberData(0.52, 0.3, 1.6, 2.0, 3.1),
    const _EmberData(0.64, 0.85, 2.0, 1.0, 1.9),
    const _EmberData(0.76, 0.5, 1.4, 1.0, 0.4),
    const _EmberData(0.88, 0.75, 2.5, 1.0, 2.3),
    const _EmberData(0.95, 0.2, 1.7, 2.0, 1.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Dark surface background (#0E0E0E)
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0E0E0E),
    );

    // 2. Luminous Boreal Atmospheric Glow (Deep Emerald & Arctic Indigo wash)
    final auroraAtmosphere = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.75),
        radius: 1.4,
        colors: [
          const Color(0xFF065F46).withValues(alpha: 0.42), // Luminous emerald night
          const Color(0xFF1E1B4B).withValues(alpha: 0.30), // Deep Arctic indigo
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, auroraAtmosphere);

    // 3. Shimmering Aurora Vertical Ray Striations (Curtain Ray Pillars)
    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    for (int i = 0; i < 15; i++) {
      final rx = (i / 14) * w;
      final raySine = math.sin(progress * 2 * math.pi * 1.0 + i * 0.45);
      final rayHeight = (28.0 + raySine * 14.0).clamp(14.0, 52.0);
      final rayTop = h * 0.16 + math.cos(progress * 2 * math.pi * 2.0 + i * 0.6) * 6.0;
      final rayBottom = rayTop + rayHeight;
      final rayAlpha = (0.20 + 0.50 * (0.5 + 0.5 * raySine)).clamp(0.0, 0.75);

      final rayColor = (i % 2 == 0)
          ? const Color(0xFF34D399).withValues(alpha: rayAlpha)
          : const Color(0xFF38BDF8).withValues(alpha: rayAlpha * 0.9);

      rayPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, rayColor, Colors.transparent],
      ).createShader(Rect.fromLTWH(rx - 1.1, rayTop, 2.2, rayBottom - rayTop));

      canvas.drawLine(Offset(rx, rayTop), Offset(rx, rayBottom), rayPaint);
    }

    // 4. Primary Luminous Aurora Curtain 1: Emerald & Arctic Cyan Sheet
    final curtain1 = Path();
    final crest1 = Path();
    curtain1.moveTo(0, h);
    curtain1.lineTo(0, h * 0.28);
    crest1.moveTo(0, h * 0.28);

    for (double x = 0; x <= w; x += 10) {
      final normX = x / w;
      final waveY = h * 0.28 +
          math.sin(normX * 2 * math.pi + progress * 2 * math.pi * 1.0) * 15.0 +
          math.cos(normX * 4 * math.pi - progress * 2 * math.pi * 1.0) * 8.0;
      curtain1.lineTo(x, waveY);
      crest1.lineTo(x, waveY);
    }
    curtain1.lineTo(w, h);
    curtain1.close();

    final curtain1Paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.55), // Radiant Emerald
          const Color(0xFF06B6D4).withValues(alpha: 0.42), // Arctic Cyan
          const Color(0xFF3B82F6).withValues(alpha: 0.18), // Deep Blue wash
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 0.75, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(curtain1, curtain1Paint);

    // Radiant Crest Edge for Curtain 1
    final crest1Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF34D399).withValues(alpha: 0.80),
          const Color(0xFF67E8F9).withValues(alpha: 0.90),
          const Color(0xFF818CF8).withValues(alpha: 0.75),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawPath(crest1, crest1Paint);

    // 5. Secondary Flowing Aurora Curtain 2: Electric Cyan & Neon Violet
    final curtain2 = Path();
    final crest2 = Path();
    curtain2.moveTo(0, h);
    curtain2.lineTo(0, h * 0.48);
    crest2.moveTo(0, h * 0.48);

    for (double x = 0; x <= w; x += 10) {
      final normX = x / w;
      final waveY = h * 0.48 +
          math.cos(normX * 2.5 * math.pi - progress * 2 * math.pi * 1.0) * 14.0 +
          math.sin(normX * 3.5 * math.pi + progress * 2 * math.pi * 2.0) * 9.0;
      curtain2.lineTo(x, waveY);
      crest2.lineTo(x, waveY);
    }
    curtain2.lineTo(w, h);
    curtain2.close();

    final curtain2Paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: 0.50), // Electric Cyan
          const Color(0xFF8B5CF6).withValues(alpha: 0.45), // Neon Violet
          const Color(0xFFEC4899).withValues(alpha: 0.22), // Magenta glow
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.80, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(curtain2, curtain2Paint);

    // Radiant Crest Edge for Curtain 2
    final crest2Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF22D3EE).withValues(alpha: 0.85),
          const Color(0xFFA855F7).withValues(alpha: 0.88),
          const Color(0xFFF472B6).withValues(alpha: 0.72),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(crest2, crest2Paint);

    // 6. Floating Cosmic Firefly Embers (Seamless continuous loop)
    for (final ember in _embers) {
      final curY = (ember.y * size.height - progress * ember.speed * size.height + size.height) % size.height;
      final sway = math.sin(progress * 2 * math.pi * 2.0 + ember.phase) * 10.0;
      final curX = (ember.x * size.width + sway + size.width) % size.width;

      final pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi * 3.0 + ember.phase));

      final emberGlow = Paint()
        ..color = const Color(0xFF67E8F9).withValues(alpha: pulse * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(Offset(curX, curY), ember.size * 2.0, emberGlow);

      final emberCore = Paint()
        ..color = const Color(0xFFF0FDFA).withValues(alpha: pulse * 0.92);
      canvas.drawCircle(Offset(curX, curY), ember.size * 0.85, emberCore);
    }
  }

  @override
  bool shouldRepaint(covariant _DarkHeaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. LIGHT Header Painter (Prismatic Morning Breeze & Floating Glass Orbs)
// ═════════════════════════════════════════════════════════════════════════════

class _GlassOrbData {
  final double startX;
  final double startY;
  final double radius;
  final double speed;
  final double swaySpeed;
  final double swayAmplitude;
  final double phase;

  const _GlassOrbData(
    this.startX,
    this.startY,
    this.radius,
    this.speed,
    this.swaySpeed,
    this.swayAmplitude,
    this.phase,
  );
}

class _PrismSparkleData {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double phase;

  const _PrismSparkleData(this.x, this.y, this.size, this.speed, this.phase);
}

class _LightHeaderPainter extends CustomPainter {
  final double progress;

  _LightHeaderPainter({required this.progress});

  static final List<_GlassOrbData> _orbs = [
    const _GlassOrbData(0.12, 0.70, 7.5, 1.0, 2.0, 14.0, 0.4),
    const _GlassOrbData(0.24, 0.35, 5.0, 1.0, 3.0, 10.0, 1.8),
    const _GlassOrbData(0.38, 0.80, 8.5, 2.0, 2.0, 16.0, 2.9),
    const _GlassOrbData(0.50, 0.20, 6.0, 1.0, 2.0, 12.0, 0.7),
    const _GlassOrbData(0.66, 0.75, 7.0, 1.0, 3.0, 15.0, 3.3),
    const _GlassOrbData(0.78, 0.30, 9.0, 2.0, 2.0, 18.0, 1.2),
    const _GlassOrbData(0.88, 0.65, 5.5, 1.0, 2.0, 11.0, 2.1),
    const _GlassOrbData(0.04, 0.40, 6.5, 1.0, 3.0, 13.0, 0.9),
  ];

  static final List<_PrismSparkleData> _sparkles = [
    const _PrismSparkleData(0.07, 0.30, 2.2, 1.0, 0.5),
    const _PrismSparkleData(0.20, 0.60, 1.8, 2.0, 1.4),
    const _PrismSparkleData(0.35, 0.25, 2.5, 1.0, 2.8),
    const _PrismSparkleData(0.48, 0.70, 1.6, 2.0, 0.3),
    const _PrismSparkleData(0.62, 0.35, 2.4, 1.0, 3.1),
    const _PrismSparkleData(0.74, 0.75, 1.9, 2.0, 1.6),
    const _PrismSparkleData(0.85, 0.20, 2.6, 1.0, 2.2),
    const _PrismSparkleData(0.94, 0.55, 2.0, 2.0, 0.8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Soft, radiant daylight ambient wash
    final morningGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.65),
        radius: 1.30,
        colors: [
          const Color(0xFFBAE6FD).withValues(alpha: 0.38), // Morning sky cyan
          const Color(0xFFE0E7FF).withValues(alpha: 0.28), // Soft periwinkle
          const Color(0xFFFDF4FF).withValues(alpha: 0.16), // Morning blush
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, morningGlow);

    // 2. Dual Iridescent Fluid Silk Waves
    // ── Wave 1: Sky Azure & Periwinkle Silk Ribbon ──
    final silkWave1 = Path();
    final crest1 = Path();
    silkWave1.moveTo(0, h);
    silkWave1.lineTo(0, h * 0.35);
    crest1.moveTo(0, h * 0.35);

    for (double x = 0; x <= w; x += 10) {
      final normX = x / w;
      final waveY = h * 0.35 +
          math.sin(normX * 2 * math.pi + progress * 2 * math.pi * 1.0) * 11.0 +
          math.cos(normX * 4 * math.pi - progress * 2 * math.pi * 1.0) * 6.0;
      silkWave1.lineTo(x, waveY);
      crest1.lineTo(x, waveY);
    }
    silkWave1.lineTo(w, h);
    silkWave1.close();

    final silkPaint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.26), // Sky Cyan
          const Color(0xFF818CF8).withValues(alpha: 0.20), // Periwinkle
          const Color(0xFFC084FC).withValues(alpha: 0.12), // Soft Violet
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 0.75, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(silkWave1, silkPaint1);

    final crestPaint1 = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF0284C7).withValues(alpha: 0.42),
          const Color(0xFF6366F1).withValues(alpha: 0.45),
          const Color(0xFFA855F7).withValues(alpha: 0.35),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawPath(crest1, crestPaint1);

    // ── Wave 2: Rose Quartz & Sunrise Blush Ribbon ──
    final silkWave2 = Path();
    final crest2 = Path();
    silkWave2.moveTo(0, h);
    silkWave2.lineTo(0, h * 0.58);
    crest2.moveTo(0, h * 0.58);

    for (double x = 0; x <= w; x += 10) {
      final normX = x / w;
      final waveY = h * 0.58 +
          math.cos(normX * 2.5 * math.pi - progress * 2 * math.pi * 1.0) * 10.0 +
          math.sin(normX * 3.5 * math.pi + progress * 2 * math.pi * 2.0) * 6.0;
      silkWave2.lineTo(x, waveY);
      crest2.lineTo(x, waveY);
    }
    silkWave2.lineTo(w, h);
    silkWave2.close();

    final silkPaint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFF472B6).withValues(alpha: 0.22), // Rose Quartz
          const Color(0xFFFB923C).withValues(alpha: 0.16), // Morning Sunrise
          const Color(0xFF38BDF8).withValues(alpha: 0.12), // Cyan wash
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(silkWave2, silkPaint2);

    final crestPaint2 = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFEC4899).withValues(alpha: 0.36),
          const Color(0xFFF97316).withValues(alpha: 0.36),
          const Color(0xFF06B6D4).withValues(alpha: 0.30),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawPath(crest2, crestPaint2);

    // 3. Floating Pearlescent Glass Orbs / Iridescent Bubbles (Seamless continuous loop)
    for (final orb in _orbs) {
      final totalH = h + 40.0;
      final curY = ((orb.startY * totalH) - progress * orb.speed * totalH + totalH) % totalH - 20.0;
      final sway = math.sin(progress * 2 * math.pi * orb.swaySpeed + orb.phase) * orb.swayAmplitude;
      final curX = (orb.startX * w + sway + w) % w;

      _drawGlassOrb(canvas, Offset(curX, curY), orb.radius);
    }

    // 4. Prismatic Diamond Sparkles & Refraction Glints (Seamless continuous loop)
    for (final s in _sparkles) {
      final sx = s.x * w;
      final sy = (s.y * h - progress * s.speed * h + h) % h;
      final twinkle = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi * s.speed * 2.0 + s.phase));

      if (twinkle > 0.60) {
        final sparkLen = s.size * 2.4 * ((twinkle - 0.60) / 0.40);
        final sparkPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = const Color(0xFF0284C7).withValues(alpha: (twinkle - 0.60) * 1.8);
        canvas.drawLine(Offset(sx - sparkLen, sy), Offset(sx + sparkLen, sy), sparkPaint);
        canvas.drawLine(Offset(sx, sy - sparkLen), Offset(sx, sy + sparkLen), sparkPaint);

        final sparkCenter = Paint()..color = Colors.white.withValues(alpha: twinkle);
        canvas.drawCircle(Offset(sx, sy), 1.0, sparkCenter);
      }
    }
  }

  void _drawGlassOrb(Canvas canvas, Offset center, double radius) {
    // Translucent pearlescent glass bubble body
    final orbFill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.65),
          const Color(0xFFBAE6FD).withValues(alpha: 0.32),
          const Color(0xFFF5D0FE).withValues(alpha: 0.12),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, orbFill);

    // Subtle iridescent glass rim
    final rimPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.45),
          const Color(0xFFC084FC).withValues(alpha: 0.40),
          const Color(0xFFF472B6).withValues(alpha: 0.35),
          const Color(0xFF38BDF8).withValues(alpha: 0.45),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;
    canvas.drawCircle(center, radius, rimPaint);

    // Specular refraction highlight (crescent reflection)
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(center.dx - radius * 0.35, center.dy - radius * 0.35),
      radius * 0.28,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LightHeaderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
