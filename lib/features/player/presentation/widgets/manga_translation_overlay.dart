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
          size,
        );
      } else {
        _drawSfxBlock(canvas, mappedRect, block.translatedText, size);
      }
    }
  }

  /// Computes bubble geometry locked to original detected rect (+3.0px padding)
  /// clamped strictly within the safe screen viewport.
  static Rect calculateBubbleRect({
    required Rect rect,
    required String text,
    Rect? destRect,
    Size? screenSize,
  }) {
    final trimmedText = text.trim();
    final int wordCount =
        trimmedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final double screenW = screenSize?.width ?? destRect?.width ?? 400.0;
    final double screenH = screenSize?.height ?? destRect?.height ?? 800.0;
    final Rect safeViewport = Rect.fromLTWH(
      8.0,
      8.0,
      math.max(20.0, screenW - 16.0),
      math.max(20.0, screenH - 16.0),
    );

    // Derive bubbleRect from rect.inflate(3.0) clamped within safeViewport
    final inflated = rect.inflate(3.0);
    final double width = math.min(inflated.width, safeViewport.width);
    final double height = math.min(inflated.height, safeViewport.height);

    double left = inflated.left;
    double top = inflated.top;
    if (left < safeViewport.left) {
      left = safeViewport.left;
    } else if (left + width > safeViewport.right) {
      left = safeViewport.right - width;
    }
    if (left < safeViewport.left) left = safeViewport.left;

    if (top < safeViewport.top) {
      top = safeViewport.top;
    } else if (top + height > safeViewport.bottom) {
      top = safeViewport.bottom - height;
    }
    if (top < safeViewport.top) top = safeViewport.top;

    final Rect bubbleRect = Rect.fromLTWH(left, top, width, height);
    final bool isVertical = bubbleRect.height > bubbleRect.width * 1.25;

    // Compute text layout boundaries
    final double maxTextWidth;
    final double targetMaxHeight;
    if (isVertical) {
      maxTextWidth = math.max(20.0, bubbleRect.height - 10.0);
      targetMaxHeight = math.max(16.0, bubbleRect.width - 6.0);
    } else {
      maxTextWidth = math.max(16.0, bubbleRect.width - 8.0);
      targetMaxHeight = math.max(16.0, bubbleRect.height - 6.0);
    }

    final double maxAllowedFontSize;
    if (wordCount <= 4) {
      maxAllowedFontSize = 11.5;
    } else if (wordCount <= 12) {
      maxAllowedFontSize = 10.5;
    } else {
      maxAllowedFontSize = 9.5;
    }

    double fontSize = maxAllowedFontSize;
    TextPainter painter = _buildTextPainter(
      text: trimmedText,
      style: TextStyle(
        color: const Color(0xFF202124),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.22,
      ),
      maxWidth: maxTextWidth,
    );

    while ((painter.height > targetMaxHeight || painter.width > maxTextWidth) &&
        fontSize > 7.0) {
      fontSize = math.max(7.0, fontSize - 0.5);
      painter = _buildTextPainter(
        text: trimmedText,
        style: TextStyle(
          color: const Color(0xFF202124),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 1.22,
        ),
        maxWidth: maxTextWidth,
      );
      if (fontSize <= 7.0) break;
    }

    return bubbleRect;
  }

  void _drawSpeechBubbleBlock(
    Canvas canvas,
    Rect rect,
    String text, [
    Rect? destRect,
    Size? screenSize,
  ]) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    final bubbleRect = calculateBubbleRect(
      rect: rect,
      text: trimmedText,
      destRect: destRect,
      screenSize: screenSize,
    );

    final bool isVertical = bubbleRect.height > bubbleRect.width * 1.25;

    final double maxTextWidth;
    final double targetMaxHeight;
    if (isVertical) {
      maxTextWidth = math.max(20.0, bubbleRect.height - 10.0);
      targetMaxHeight = math.max(16.0, bubbleRect.width - 6.0);
    } else {
      maxTextWidth = math.max(16.0, bubbleRect.width - 8.0);
      targetMaxHeight = math.max(16.0, bubbleRect.height - 6.0);
    }

    final int wordCount =
        trimmedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final double maxAllowedFontSize;
    if (wordCount <= 4) {
      maxAllowedFontSize = 11.5;
    } else if (wordCount <= 12) {
      maxAllowedFontSize = 10.5;
    } else {
      maxAllowedFontSize = 9.5;
    }

    double fontSize = maxAllowedFontSize;

    TextPainter painter = _buildTextPainter(
      text: trimmedText,
      style: TextStyle(
        color: const Color(0xFF202124),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.22,
      ),
      maxWidth: maxTextWidth,
    );

    while ((painter.height > targetMaxHeight || painter.width > maxTextWidth) &&
        fontSize > 7.0) {
      fontSize = math.max(7.0, fontSize - 0.5);
      painter = _buildTextPainter(
        text: trimmedText,
        style: TextStyle(
          color: const Color(0xFF202124),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 1.22,
        ),
        maxWidth: maxTextWidth,
      );
      if (fontSize <= 7.0) break;
    }

    final rrect =
        RRect.fromRectAndRadius(bubbleRect, const Radius.circular(8.0));

    // Google Translate style: Soft semi-transparent light patch
    final patchPaint = Paint()
      ..color = const Color(0xFFF7F7F8).withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, patchPaint);

    // Google Translate style: Ultra-subtle hairline border (0.5px, 5% opacity)
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(rrect, borderPaint);

    if (isVertical) {
      final double marginH =
          math.max(2.0, (bubbleRect.height - painter.width) / 2.0);
      final double marginW =
          math.max(2.0, (bubbleRect.width - painter.height) / 2.0);
      final double originX = bubbleRect.right - marginW;
      final double originY = bubbleRect.top + marginH;

      canvas.save();
      canvas.clipRRect(rrect);
      canvas.translate(originX, originY);
      canvas.rotate(math.pi / 2);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      final double dx = bubbleRect.left +
          math.max(0.0, (bubbleRect.width - painter.width) / 2.0);
      final double dy = bubbleRect.top +
          math.max(0.0, (bubbleRect.height - painter.height) / 2.0);

      canvas.save();
      canvas.clipRRect(rrect);
      painter.paint(canvas, Offset(dx, dy));
      canvas.restore();
    }
  }

  void _drawSfxBlock(
    Canvas canvas,
    Rect rect,
    String text, [
    Size? screenSize,
  ]) {
    final double screenW = screenSize?.width ?? 400.0;
    final double screenH = screenSize?.height ?? 800.0;
    final Rect safeViewport = Rect.fromLTWH(
      8.0,
      8.0,
      math.max(20.0, screenW - 16.0),
      math.max(20.0, screenH - 16.0),
    );

    final double fontSize = (rect.height * 0.35).clamp(11.0, 16.0);
    final double maxTextWidth = math.min(
      math.max(rect.width * 1.4, 40.0),
      safeViewport.width - 16.0,
    );

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

    final double pillWidth =
        math.min(fillPainter.width + 8.0, safeViewport.width);
    final double pillHeight =
        math.min(fillPainter.height + 4.0, safeViewport.height);

    double pillLeft = rect.left + (rect.width - pillWidth) / 2.0;
    double pillTop = rect.top + (rect.height - pillHeight) / 2.0;

    // Strictly clamp pill within safeViewport
    if (pillLeft < safeViewport.left) {
      pillLeft = safeViewport.left;
    } else if (pillLeft + pillWidth > safeViewport.right) {
      pillLeft = safeViewport.right - pillWidth;
    }
    if (pillLeft < safeViewport.left) pillLeft = safeViewport.left;

    if (pillTop < safeViewport.top) {
      pillTop = safeViewport.top;
    } else if (pillTop + pillHeight > safeViewport.bottom) {
      pillTop = safeViewport.bottom - pillHeight;
    }
    if (pillTop < safeViewport.top) pillTop = safeViewport.top;

    final pillRect = Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight);
    final pillRRect =
        RRect.fromRectAndRadius(pillRect, const Radius.circular(6.0));

    final double textDx =
        pillRect.left + (pillRect.width - fillPainter.width) / 2.0;
    final double textDy =
        pillRect.top + (pillRect.height - fillPainter.height) / 2.0;
    final offset = Offset(textDx, textDy);

    canvas.save();
    canvas.clipRect(safeViewport);

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRRect, bgPaint);

    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);
    canvas.restore();
  }

  static TextPainter _buildTextPainter({
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
