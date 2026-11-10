// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/services/translation/translation_models.dart';

/// Overlay for translated manga text blocks.
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

/// Painter for speech bubbles and SFX text overlays.
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
    if (original.width <= 0 ||
        original.height <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final FittedSizes fitted = applyBoxFit(BoxFit.contain, original, size);
    final Rect destRect =
        Alignment.center.inscribe(fitted.destination, Offset.zero & size);

    final double scaleX = destRect.width / original.width;
    final double scaleY = destRect.height / original.height;

    for (final block in result.blocks) {
      if (mode == TranslationRenderMode.speechBubblesOnly &&
          !block.isSpeechBubble) {
        continue;
      }

      if (block.translatedText.trim().isEmpty ||
          block.translatedText.trim() == block.originalText.trim()) {
        continue;
      }

      final mappedRect = Rect.fromLTRB(
        destRect.left + block.boundingBox.left * scaleX,
        destRect.top + block.boundingBox.top * scaleY,
        destRect.left + block.boundingBox.right * scaleX,
        destRect.top + block.boundingBox.bottom * scaleY,
      );

      if (block.isSpeechBubble) {
        _drawSpeechBubbleBlock(canvas, mappedRect, block.translatedText);
      } else {
        _drawSfxBlock(canvas, mappedRect, block.translatedText);
      }
    }
  }

  void _drawSpeechBubbleBlock(Canvas canvas, Rect rect, String text) {
    Rect effectiveRect = rect;
    if (effectiveRect.height > effectiveRect.width * 1.5) {
      final double targetWidth = math.max(effectiveRect.width * 1.8, 50.0);
      final double extraWidth = targetWidth - effectiveRect.width;
      if (extraWidth > 0) {
        effectiveRect = Rect.fromLTRB(
          effectiveRect.left - extraWidth / 2.0,
          effectiveRect.top,
          effectiveRect.right + extraWidth / 2.0,
          effectiveRect.bottom,
        );
      }
    }

    final paddedRect = effectiveRect.inflate(4.0);
    final rrect =
        RRect.fromRectAndRadius(paddedRect, const Radius.circular(8.0));

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

    double fontSize = (effectiveRect.height * 0.35).clamp(10.0, 18.0);
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

    while (painter.height > maxTextHeight && fontSize > 6.5) {
      fontSize -= 0.5;
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

    final double dx =
        paddedRect.left + (paddedRect.width - painter.width) / 2.0;
    final double dy =
        paddedRect.top + (paddedRect.height - painter.height) / 2.0;

    canvas.save();
    canvas.clipRRect(rrect);
    painter.paint(canvas, Offset(dx, dy));
    canvas.restore();
  }

  void _drawSfxBlock(Canvas canvas, Rect rect, String text) {
    final double fontSize = (rect.height * 0.45).clamp(12.0, 24.0);
    final double maxTextWidth = math.max(rect.width * 1.4, 40.0);

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

    final pillRect = Rect.fromLTWH(
      dx - 4.0,
      dy - 2.0,
      fillPainter.width + 8.0,
      fillPainter.height + 4.0,
    );
    final pillRRect =
        RRect.fromRectAndRadius(pillRect, const Radius.circular(6.0));

    canvas.save();
    canvas.clipRect(rect.inflate(30.0));

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRRect, bgPaint);

    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);
    canvas.restore();
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
      maxLines: 10,
      ellipsis: '…',
    );
    painter.layout(maxWidth: maxWidth);
    return painter;
  }

  @override
  bool shouldRepaint(covariant MangaTranslationPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.mode != mode;
  }
}
