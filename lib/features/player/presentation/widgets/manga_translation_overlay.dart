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
        _drawSpeechBubbleBlock(
          canvas,
          mappedRect,
          block.translatedText,
          destRect,
        );
      } else {
        _drawSfxBlock(canvas, mappedRect, block.translatedText);
      }
    }
  }

  void _drawSpeechBubbleBlock(
    Canvas canvas,
    Rect rect,
    String text, [
    Rect? destRect,
  ]) {
    final trimmedText = text.trim();
    final int charCount = trimmedText.length;
    final int wordCount =
        trimmedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    Rect effectiveRect = rect;

    // 1. Vertical text box expansion for horizontal English text.
    // Asian manga dialogue is often laid out vertically in narrow columns (20-30px wide).
    // English needs comfortable horizontal line lengths to avoid pathological wrapping.
    if (effectiveRect.height > effectiveRect.width * 1.1) {
      double minWidthForLength = 80.0;
      if (charCount > 60) {
        minWidthForLength = 140.0;
      } else if (charCount > 30) {
        minWidthForLength = 110.0;
      }

      double targetWidth = math.max(
        effectiveRect.width * 2.2,
        math.max(effectiveRect.height * 0.75, minWidthForLength),
      );

      if (destRect != null && destRect.width > 0) {
        targetWidth = targetWidth.clamp(20.0, destRect.width * 0.85);
      }

      effectiveRect = Rect.fromCenter(
        center: effectiveRect.center,
        width: targetWidth,
        height: effectiveRect.height,
      );
    }

    // 2. Compute max text width available inside the bubble
    double maxTextWidth = math.max(effectiveRect.width - 8.0, 60.0);
    if (destRect != null && destRect.width > 0) {
      maxTextWidth = math.min(maxTextWidth, destRect.width * 0.85 - 16.0);
    }

    // 3. Adaptive font size calculation based on dialogue length & bubble size.
    // Manga dialogue in standard scanlations is typically 9.0 - 13.0sp (never oversized 18sp).
    final double maxAllowedFontSize;
    if (wordCount <= 4) {
      maxAllowedFontSize = 13.0;
    } else if (wordCount <= 12) {
      maxAllowedFontSize = 11.5;
    } else {
      maxAllowedFontSize = 10.0;
    }

    // Adaptive starting font size bounded between 8.5sp and maxAllowedFontSize
    double fontSize =
        (effectiveRect.height * 0.25).clamp(8.5, maxAllowedFontSize);
    if (fontSize < maxAllowedFontSize && effectiveRect.width > 80.0) {
      fontSize = math.min(maxAllowedFontSize, math.max(fontSize, 10.0));
    }

    final double targetMaxHeight = math.max(effectiveRect.height, 40.0);

    TextPainter painter = _buildTextPainter(
      text: trimmedText,
      style: TextStyle(
        color: Colors.black87,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
      maxWidth: maxTextWidth,
    );

    // Iteratively scale down font size until text fits or reaches minimum legible size 8.5sp
    while (painter.height > targetMaxHeight && fontSize > 8.5) {
      fontSize = math.max(8.5, fontSize - 0.5);
      painter = _buildTextPainter(
        text: trimmedText,
        style: TextStyle(
          color: Colors.black87,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
        maxWidth: maxTextWidth,
      );
      if (fontSize <= 8.5) break;
    }

    // 4. Auto-fitting geometry: Encompass the laid-out text with safe margins so text is NEVER clipped.
    final double finalWidth =
        math.max(effectiveRect.width + 12.0, painter.width + 16.0);
    final double finalHeight =
        math.max(effectiveRect.height + 8.0, painter.height + 12.0);

    final Rect rawBubbleRect = Rect.fromCenter(
      center: effectiveRect.center,
      width: finalWidth,
      height: finalHeight,
    );

    // Clamp bubble within destination bounds if destRect is provided
    Rect bubbleRect = rawBubbleRect;
    if (destRect != null && destRect.width > 0 && destRect.height > 0) {
      double left = bubbleRect.left;
      double top = bubbleRect.top;
      double width = bubbleRect.width;
      double height = bubbleRect.height;

      if (width > destRect.width) {
        width = destRect.width;
        left = destRect.left;
      } else if (left < destRect.left) {
        left = destRect.left;
      } else if (left + width > destRect.right) {
        left = destRect.right - width;
      }

      if (height > destRect.height) {
        height = destRect.height;
        top = destRect.top;
      } else if (top < destRect.top) {
        top = destRect.top;
      } else if (top + height > destRect.bottom) {
        top = destRect.bottom - height;
      }

      bubbleRect = Rect.fromLTWH(left, top, width, height);
    }

    final rrect =
        RRect.fromRectAndRadius(bubbleRect, const Radius.circular(8.0));

    final patchPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, patchPaint);

    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // Centered coordinates guaranteed never to be negative or offscreen
    final double dx = bubbleRect.left +
        math.max(0.0, (bubbleRect.width - painter.width) / 2.0);
    final double dy = bubbleRect.top +
        math.max(0.0, (bubbleRect.height - painter.height) / 2.0);

    canvas.save();
    canvas.clipRRect(rrect);
    painter.paint(canvas, Offset(dx, dy));
    canvas.restore();
  }

  void _drawSfxBlock(Canvas canvas, Rect rect, String text) {
    final double fontSize = (rect.height * 0.35).clamp(11.0, 16.0);
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
    int? maxLines = 16,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines != null ? '…' : null,
    );
    painter.layout(maxWidth: maxWidth);
    return painter;
  }

  @override
  bool shouldRepaint(covariant MangaTranslationPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.mode != mode;
  }
}
