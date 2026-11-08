// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/services/translation/translation_models.dart';

/// Interactive overlay widget rendering translated manga text blocks over the source page.
class MangaTranslationOverlay extends StatelessWidget {
  final TranslationResult result;
  final TranslationRenderMode mode;

  const MangaTranslationOverlay({
    super.key,
    required this.result,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    if (result.blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: MangaTranslationPainter(
            result: result,
            mode: mode,
          ),
        );
      },
    );
  }
}

/// CustomPainter that maps original image coordinates to rendered viewport dimensions
/// and renders adaptive speech bubble patches or dual-pass stroked SFX overlays.
class MangaTranslationPainter extends CustomPainter {
  final TranslationResult result;
  final TranslationRenderMode mode;

  MangaTranslationPainter({
    required this.result,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final original = result.imageSize;
    if (original.width <= 0 || original.height <= 0 || size.width <= 0 || size.height <= 0) {
      return;
    }

    final double scaleX = size.width / original.width;
    final double scaleY = size.height / original.height;

    for (final block in result.blocks) {
      if (mode == TranslationRenderMode.speechBubblesOnly && !block.isSpeechBubble) {
        continue;
      }

      final mappedRect = Rect.fromLTRB(
        block.boundingBox.left * scaleX,
        block.boundingBox.top * scaleY,
        block.boundingBox.right * scaleX,
        block.boundingBox.bottom * scaleY,
      );

      if (block.isSpeechBubble) {
        _drawSpeechBubbleBlock(canvas, mappedRect, block.translatedText);
      } else {
        _drawSfxBlock(canvas, mappedRect, block.translatedText);
      }
    }
  }

  void _drawSpeechBubbleBlock(Canvas canvas, Rect rect, String text) {
    final paddedRect = rect.inflate(4.0);
    final rrect = RRect.fromRectAndRadius(paddedRect, const Radius.circular(8.0));

    final patchPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, patchPaint);

    final borderPaint = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    final double maxTextWidth = math.max(paddedRect.width - 6.0, 10.0);
    final double maxTextHeight = math.max(paddedRect.height - 6.0, 10.0);

    double fontSize = (rect.height * 0.35).clamp(10.0, 18.0);
    TextPainter painter = _buildTextPainter(
      text: text,
      style: TextStyle(
        color: Colors.black87,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
      maxWidth: maxTextWidth,
    );

    while (painter.height > maxTextHeight && fontSize > 9.0) {
      fontSize -= 1.0;
      painter = _buildTextPainter(
        text: text,
        style: TextStyle(
          color: Colors.black87,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
        maxWidth: maxTextWidth,
      );
    }

    final double dx = paddedRect.left + (paddedRect.width - painter.width) / 2.0;
    final double dy = paddedRect.top + (paddedRect.height - painter.height) / 2.0;
    painter.paint(canvas, Offset(dx, dy));
  }

  void _drawSfxBlock(Canvas canvas, Rect rect, String text) {
    final double fontSize = (rect.height * 0.45).clamp(12.0, 24.0);
    final double maxTextWidth = math.max(rect.width * 1.4, 40.0);

    // Pass 1: Black outline stroke
    final strokePainter = _buildTextPainter(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black,
      ),
      maxWidth: maxTextWidth,
    );

    // Pass 2: White fill with drop shadow
    final fillPainter = _buildTextPainter(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        shadows: const [
          Shadow(
            offset: Offset(1.5, 1.5),
            blurRadius: 3.0,
            color: Colors.black87,
          ),
        ],
      ),
      maxWidth: maxTextWidth,
    );

    final double dx = rect.left + (rect.width - fillPainter.width) / 2.0;
    final double dy = rect.top + (rect.height - fillPainter.height) / 2.0;
    final offset = Offset(dx, dy);

    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);
  }

  TextPainter _buildTextPainter({
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: maxWidth);
    return painter;
  }

  @override
  bool shouldRepaint(covariant MangaTranslationPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.mode != mode;
  }
}
