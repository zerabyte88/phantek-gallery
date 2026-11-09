// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive V6 Zig-Zag progress bar with serpentine wave undulation
/// from Phantek Video Toolkit Vega.
class ZigzagProgressBar extends StatefulWidget {
  final double progress;
  final bool isProcessing;
  final Color color;
  final Color? deepColor;
  final Color? crestColor;
  final Color? trackColor;
  final double height;
  final double? width;

  const ZigzagProgressBar({
    super.key,
    required this.progress,
    this.isProcessing = false,
    this.color = const Color(0xFF00E5FF),
    this.deepColor,
    this.crestColor,
    this.trackColor,
    this.height = 24.0,
    this.width,
  });

  @override
  State<ZigzagProgressBar> createState() => _ZigzagProgressBarState();
}

class _ZigzagProgressBarState extends State<ZigzagProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDeep =
        widget.deepColor ?? widget.color.withValues(alpha: 0.5);
    final effectiveCrest = widget.crestColor ?? Colors.white;
    final effectiveTrack =
        widget.trackColor ?? Colors.white.withValues(alpha: 0.08);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.width ?? double.infinity, widget.height),
            painter: ZigzagProgressPainter(
              progress: widget.progress,
              animTime: _controller.value * 2.4,
              isProcessing: widget.isProcessing,
              color: widget.color,
              deepColor: effectiveDeep,
              crestColor: effectiveCrest,
              trackColor: effectiveTrack,
            ),
          );
        },
      ),
    );
  }
}

/// CustomPainter executing the exact V6 Zig-Zag serpentine wave formulation.
class ZigzagProgressPainter extends CustomPainter {
  final double progress;
  final double animTime;
  final bool isProcessing;
  final Color color;
  final Color deepColor;
  final Color crestColor;
  final Color trackColor;

  const ZigzagProgressPainter({
    required this.progress,
    required this.animTime,
    required this.isProcessing,
    required this.color,
    required this.deepColor,
    required this.crestColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Subtle rounded track (pill)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.fill;
    final trackRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2.0),
    );
    canvas.drawRRect(trackRRect, trackPaint);

    final pad = math.min(12.0, size.width / 4.0);
    final usableWidth = math.max(0.0, size.width - 2 * pad);
    if (usableWidth <= 0) return;

    final safeProgress = progress.clamp(0.0, 1.0);
    final rawDist = usableWidth * safeProgress;
    final activeDist = (rawDist <= 0 && isProcessing && usableWidth > 0)
        ? math.min(usableWidth * 0.03, 8.0)
        : rawDist;

    if (activeDist <= 0) return;

    final headX = pad + activeDist;
    final tailX = pad;
    final yCenter = size.height / 2.0;
    const amplitude = 5.0;
    final k = (2 * math.pi * 4.2) / usableWidth;
    final omegaT = animTime * (4.0 / 2.4) * 2 * math.pi;

    double getY(double x) =>
        yCenter + amplitude * math.sin(k * (x - pad) + omegaT);
    double getSlope(double x) =>
        amplitude * k * math.cos(k * (x - pad) + omegaT);

    // 2. Spine gradient path
    final spinePath = Path();
    spinePath.moveTo(tailX, getY(tailX));
    const step = 2.0;
    for (double x = tailX + step; x < headX; x += step) {
      spinePath.lineTo(x, getY(x));
    }
    spinePath.lineTo(headX, getY(headX));

    final spinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [deepColor, color, crestColor],
      ).createShader(
        Rect.fromLTRB(
          tailX,
          0,
          math.max(headX, tailX + 1.0),
          size.height,
        ),
      );

    canvas.drawPath(spinePath, spinePaint);

    // 3. Head rotated along tangent atan(getSlope(headX))
    final slope = getSlope(headX);
    final angle = math.atan(slope);

    canvas.save();
    canvas.translate(headX, getY(headX));
    canvas.rotate(angle);

    // Head oval 14.5 x 9.0 filled with crestColor
    final headPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = crestColor;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 14.5, height: 9.0),
      headPaint,
    );

    // Inner glint 4.5 x 2.6 filled with white
    final glintPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 4.5, height: 2.6),
      glintPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ZigzagProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animTime != animTime ||
        oldDelegate.isProcessing != isProcessing ||
        oldDelegate.color != color ||
        oldDelegate.deepColor != deepColor ||
        oldDelegate.crestColor != crestColor ||
        oldDelegate.trackColor != trackColor;
  }
}
