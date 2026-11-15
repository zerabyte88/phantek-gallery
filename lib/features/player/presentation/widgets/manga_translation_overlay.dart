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
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return CustomPaint(
          size: size,
          painter: MangaTranslationPainter(
            result: result,
            mode: mode,
            viewportSize: size,
          ),
        );
      },
    );
  }
}

/// Cluster of adjacent or overlapping speech bubbles rendered together.
class MangaSpeechBubbleCluster {
  final Rect rect;
  final String text;

  const MangaSpeechBubbleCluster({
    required this.rect,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MangaSpeechBubbleCluster &&
          runtimeType == other.runtimeType &&
          rect == other.rect &&
          text == other.text;

  @override
  int get hashCode => rect.hashCode ^ text.hashCode;
}

/// Painter for speech bubbles and SFX text overlays.
class MangaTranslationPainter extends CustomPainter {
  final TranslationResult result;
  final TranslationRenderMode mode;
  final Size? viewportSize;

  List<MangaSpeechBubbleCluster>? _precomputedClusters;
  List<({Rect rect, String text})>? _precomputedSfx;

  static final Map<
      _ClusterCacheKey,
      ({
        List<MangaSpeechBubbleCluster> bubbles,
        List<({Rect rect, String text})> sfx
      })> _clusterCache = {};
  static final Map<_FittedTextPainterCacheKey, TextPainter>
      _fittedPainterCache = {};

  MangaTranslationPainter({
    required this.result,
    required this.mode,
    this.viewportSize,
  }) {
    if (viewportSize != null &&
        viewportSize!.width > 0 &&
        viewportSize!.height > 0 &&
        result.imageSize.width > 0 &&
        result.imageSize.height > 0) {
      final cached = _getOrComputeClusters(viewportSize!);
      _precomputedClusters = cached.bubbles;
      _precomputedSfx = cached.sfx;
    }
  }

  ({
    List<MangaSpeechBubbleCluster> bubbles,
    List<({Rect rect, String text})> sfx
  }) _getOrComputeClusters(Size size) {
    final key = _ClusterCacheKey(result, mode, size.width, size.height);
    final existing = _clusterCache[key];
    if (existing != null) return existing;

    final original = result.imageSize;
    final FittedSizes fitted = applyBoxFit(BoxFit.contain, original, size);
    final Rect destRect =
        Alignment.center.inscribe(fitted.destination, Offset.zero & size);

    final double scaleX = destRect.width / original.width;
    final double scaleY = destRect.height / original.height;

    final List<MangaSpeechBubbleCluster> rawSpeechBubbles = [];
    final List<({Rect rect, String text})> sfxBlocks = [];

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
        rawSpeechBubbles.add(
          MangaSpeechBubbleCluster(
            rect: mappedRect,
            text: block.translatedText.trim(),
          ),
        );
      } else {
        sfxBlocks.add((rect: mappedRect, text: block.translatedText));
      }
    }

    final clusteredBubbles = clusterSpeechBubbles(rawSpeechBubbles);
    final resultPair = (bubbles: clusteredBubbles, sfx: sfxBlocks);

    if (_clusterCache.length >= 60) {
      _clusterCache.remove(_clusterCache.keys.first);
    }
    _clusterCache[key] = resultPair;
    return resultPair;
  }

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

    final ({
      List<MangaSpeechBubbleCluster> bubbles,
      List<({Rect rect, String text})> sfx
    }) data;
    if (_precomputedClusters != null &&
        _precomputedSfx != null &&
        size == viewportSize) {
      data = (bubbles: _precomputedClusters!, sfx: _precomputedSfx!);
    } else {
      data = _getOrComputeClusters(size);
    }

    for (final sfx in data.sfx) {
      _drawSfxBlock(canvas, sfx.rect, sfx.text, size);
    }

    for (final bubble in data.bubbles) {
      _drawSpeechBubbleBlock(
        canvas,
        bubble.rect,
        bubble.text,
        destRect,
        size,
      );
    }
  }

  /// Merges overlapping or adjacent speech bubble fragments and deduplicates lines.
  static List<MangaSpeechBubbleCluster> clusterSpeechBubbles(
    List<MangaSpeechBubbleCluster> bubbles,
  ) {
    if (bubbles.length <= 1) {
      return bubbles;
    }

    bool shouldMerge(MangaSpeechBubbleCluster b1, MangaSpeechBubbleCluster b2) {
      if (b1.rect.overlaps(b2.rect)) {
        return true;
      }
      if (!b1.rect.inflate(1.5).overlaps(b2.rect.inflate(1.5))) {
        return false;
      }

      final union = b1.rect.expandToInclude(b2.rect);
      final sumArea =
          b1.rect.width * b1.rect.height + b2.rect.width * b2.rect.height;
      return union.width * union.height <= 1.45 * sumArea;
    }

    final parent = List<int>.generate(bubbles.length, (i) => i);
    int find(int i) {
      if (parent[i] == i) return i;
      return parent[i] = find(parent[i]);
    }

    void union(int i, int j) {
      final rootI = find(i);
      final rootJ = find(j);
      if (rootI != rootJ) {
        parent[rootI] = rootJ;
      }
    }

    for (int i = 0; i < bubbles.length; i++) {
      for (int j = i + 1; j < bubbles.length; j++) {
        if (shouldMerge(bubbles[i], bubbles[j])) {
          union(i, j);
        }
      }
    }

    final Map<int, List<MangaSpeechBubbleCluster>> clusters = {};
    for (int i = 0; i < bubbles.length; i++) {
      final root = find(i);
      clusters.putIfAbsent(root, () => []).add(bubbles[i]);
    }

    final List<MangaSpeechBubbleCluster> mergedList = [];

    for (final cluster in clusters.values) {
      if (cluster.length == 1) {
        mergedList.add(cluster.first);
        continue;
      }

      double left = cluster.first.rect.left;
      double top = cluster.first.rect.top;
      double right = cluster.first.rect.right;
      double bottom = cluster.first.rect.bottom;

      for (final b in cluster.skip(1)) {
        left = math.min(left, b.rect.left);
        top = math.min(top, b.rect.top);
        right = math.max(right, b.rect.right);
        bottom = math.max(bottom, b.rect.bottom);
      }
      final mergedRect = Rect.fromLTRB(left, top, right, bottom);

      final sortedCluster = List<MangaSpeechBubbleCluster>.from(cluster);
      sortedCluster.sort((a, b) {
        final dy = a.rect.top.compareTo(b.rect.top);
        if (dy != 0) return dy;
        return a.rect.left.compareTo(b.rect.left);
      });

      final List<String> distinctTexts = [];
      for (final b in sortedCluster) {
        final lines =
            b.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (final t in lines) {
          int replaceIdx = -1;
          bool isDuplicate = false;
          for (int i = 0; i < distinctTexts.length; i++) {
            final existing = distinctTexts[i];
            if (existing.toLowerCase() == t.toLowerCase()) {
              isDuplicate = true;
              break;
            }
            final minLen = math.min(t.length, existing.length);
            if (minLen >= 3 && (existing.contains(t) || t.contains(existing))) {
              if (t.length > existing.length) {
                replaceIdx = i;
              } else {
                isDuplicate = true;
              }
              break;
            }
          }
          if (replaceIdx != -1) {
            distinctTexts[replaceIdx] = t;
          } else if (!isDuplicate) {
            distinctTexts.add(t);
          }
        }
      }

      mergedList.add(
        MangaSpeechBubbleCluster(
          rect: mergedRect,
          text: distinctTexts.join('\n'),
        ),
      );
    }

    return mergedList;
  }

  /// Clamps bubble geometry strictly within the safe screen viewport.
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

    const double padX = 0.0;
    const double padY = 0.0;
    final inflated = Rect.fromLTRB(
      rect.left - padX,
      rect.top - padY,
      rect.right + padX,
      rect.bottom + padY,
    );
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
    final (:maxTextWidth, :targetMaxHeight, isVertical: _) =
        _computeTextBounds(bubbleRect);

    _getOrCreateFittedPainter(
      trimmedText: trimmedText,
      maxTextWidth: maxTextWidth,
      targetMaxHeight: targetMaxHeight,
      wordCount: wordCount,
    );

    return bubbleRect;
  }

  static bool _shouldRotateVertical(Rect bubbleRect) => false;

  static ({double maxTextWidth, double targetMaxHeight, bool isVertical})
      _computeTextBounds(Rect bubbleRect) {
    final bool isVertical = _shouldRotateVertical(bubbleRect);
    final double hPad = math.min(4.0, bubbleRect.width * 0.06);
    final double vPad = math.min(4.0, bubbleRect.height * 0.06);
    final double availW = math.max(6.0, bubbleRect.width - hPad);
    final double availH = math.max(6.0, bubbleRect.height - vPad);
    return (
      maxTextWidth: isVertical ? availH : availW,
      targetMaxHeight: isVertical ? availW : availH,
      isVertical: isVertical,
    );
  }

  @visibleForTesting
  static TextPainter debugFitSpeechBubbleText(Rect bubbleRect, String text) {
    final trimmedText = text.trim();
    final int wordCount =
        trimmedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final (:maxTextWidth, :targetMaxHeight, isVertical: _) =
        _computeTextBounds(bubbleRect);
    return _getOrCreateFittedPainter(
      trimmedText: trimmedText,
      maxTextWidth: maxTextWidth,
      targetMaxHeight: targetMaxHeight,
      wordCount: wordCount,
    );
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

    final (:maxTextWidth, :targetMaxHeight, isVertical: _) =
        _computeTextBounds(bubbleRect);

    final int wordCount =
        trimmedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final painter = _getOrCreateFittedPainter(
      trimmedText: trimmedText,
      maxTextWidth: maxTextWidth,
      targetMaxHeight: targetMaxHeight,
      wordCount: wordCount,
    );

    final rrect =
        RRect.fromRectAndRadius(bubbleRect, const Radius.circular(8.0));

    // Opaque patch hides the source text inside the bubble.
    canvas.drawRRect(rrect, Paint()..color = Colors.white);

    final double fitScale =
        (painter.width > maxTextWidth || painter.height > targetMaxHeight)
            ? math
                .min(
                  maxTextWidth / math.max(1.0, painter.width),
                  targetMaxHeight / math.max(1.0, painter.height),
                )
                .clamp(0.1, 1.0)
            : 1.0;

    canvas.save();
    canvas.clipRRect(rrect);
    if (fitScale < 1.0) {
      canvas.translate(bubbleRect.center.dx, bubbleRect.center.dy);
      canvas.scale(fitScale);
      painter.paint(
        canvas,
        Offset(-painter.width / 2.0, -painter.height / 2.0),
      );
    } else {
      final double dx =
          bubbleRect.left + (bubbleRect.width - painter.width) / 2.0;
      final double dy =
          bubbleRect.top + (bubbleRect.height - painter.height) / 2.0;
      painter.paint(canvas, Offset(dx, dy));
    }
    canvas.restore();
  }

  void _drawSfxBlock(
    Canvas canvas,
    Rect rect,
    String text, [
    Size? screenSize,
  ]) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final double screenW = screenSize?.width ?? 400.0;
    final double screenH = screenSize?.height ?? 800.0;
    final Rect safeViewport = Rect.fromLTWH(
      8.0,
      8.0,
      math.max(20.0, screenW - 16.0),
      math.max(20.0, screenH - 16.0),
    );

    final double pillWidth = math.min(rect.width, safeViewport.width);
    final double pillHeight = math.min(rect.height, safeViewport.height);
    if (pillWidth <= 0 || pillHeight <= 0) return;

    double pillLeft = rect.left;
    double pillTop = rect.top;

    // Clamp pill within safeViewport without expanding beyond rect.
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

    final double hPad = math.min(4.0, pillRect.width * 0.06);
    final double vPad = math.min(4.0, pillRect.height * 0.06);
    final double maxTextWidth = math.max(6.0, pillRect.width - hPad);
    final double maxTextHeight = math.max(6.0, pillRect.height - vPad);

    const double minFontSize = 1.5;
    double fontSize = (pillRect.height * 0.35).clamp(7.0, 14.0);

    TextStyle fillStyleFor(double size) => TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.w900,
          height: size <= 8.0 ? 1.08 : 1.15,
          shadows: const [
            Shadow(
              offset: Offset(1.5, 1.5),
              blurRadius: 3.0,
              color: Colors.black87,
            ),
          ],
        );

    String longestWord = '';
    for (final w in trimmed.split(RegExp(r'\s+'))) {
      if (w.length > longestWord.length) longestWord = w;
    }
    bool longestWordFits(double size) {
      if (longestWord.isEmpty) return true;
      final wp = _buildTextPainter(
        text: longestWord,
        style: fillStyleFor(size),
        maxWidth: double.infinity,
        maxLines: 1,
      );
      return wp.width <= maxTextWidth;
    }

    TextPainter fillPainter = _buildTextPainter(
      text: trimmed,
      style: fillStyleFor(fontSize),
      maxWidth: maxTextWidth,
      maxLines: null,
    );

    while ((fillPainter.height > maxTextHeight ||
            fillPainter.width > maxTextWidth ||
            !longestWordFits(fontSize)) &&
        fontSize > 5.0) {
      fontSize = math.max(5.0, fontSize - 0.5);
      fillPainter = _buildTextPainter(
        text: trimmed,
        style: fillStyleFor(fontSize),
        maxWidth: maxTextWidth,
        maxLines: null,
      );
    }

    while ((fillPainter.height > maxTextHeight ||
            fillPainter.width > maxTextWidth) &&
        fontSize > minFontSize) {
      fontSize = math.max(minFontSize, fontSize - 0.25);
      fillPainter = _buildTextPainter(
        text: trimmed,
        style: fillStyleFor(fontSize),
        maxWidth: maxTextWidth,
        maxLines: null,
      );
    }

    final double strokeWidth = (fontSize * 0.25).clamp(0.6, 3.5);
    final strokePainter = _buildTextPainter(
      text: trimmed,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: fontSize <= 8.0 ? 1.08 : 1.15,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black,
      ),
      maxWidth: maxTextWidth,
      maxLines: null,
    );

    final double fitScale =
        (fillPainter.width > maxTextWidth || fillPainter.height > maxTextHeight)
            ? math
                .min(
                  maxTextWidth / math.max(1.0, fillPainter.width),
                  maxTextHeight / math.max(1.0, fillPainter.height),
                )
                .clamp(0.1, 1.0)
            : 1.0;

    canvas.save();
    canvas.clipRRect(pillRRect);

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRRect, bgPaint);

    if (fitScale < 1.0) {
      canvas.translate(pillRect.center.dx, pillRect.center.dy);
      canvas.scale(fitScale);
      final centeredOffset =
          Offset(-fillPainter.width / 2.0, -fillPainter.height / 2.0);
      strokePainter.paint(canvas, centeredOffset);
      fillPainter.paint(canvas, centeredOffset);
    } else {
      final offset = Offset(
        pillRect.left + (pillRect.width - fillPainter.width) / 2.0,
        pillRect.top + (pillRect.height - fillPainter.height) / 2.0,
      );
      strokePainter.paint(canvas, offset);
      fillPainter.paint(canvas, offset);
    }
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
    return oldDelegate.result != result ||
        oldDelegate.mode != mode ||
        oldDelegate.viewportSize != viewportSize;
  }

  static TextPainter _getOrCreateFittedPainter({
    required String trimmedText,
    required double maxTextWidth,
    required double targetMaxHeight,
    required int wordCount,
  }) {
    final key = _FittedTextPainterCacheKey(
      text: trimmedText,
      maxTextWidth: (maxTextWidth * 10).round() / 10,
      targetMaxHeight: (targetMaxHeight * 10).round() / 10,
    );

    final cached = _fittedPainterCache[key];
    if (cached != null) return cached;

    final double maxAllowedFontSize;
    if (wordCount <= 4) {
      maxAllowedFontSize = 11.5;
    } else if (wordCount <= 12) {
      maxAllowedFontSize = 10.5;
    } else {
      maxAllowedFontSize = 9.5;
    }

    String longestWord = '';
    for (final w in trimmedText.split(RegExp(r'\s+'))) {
      if (w.length > longestWord.length) longestWord = w;
    }

    const double minFontSize = 1.5;
    double fontSize = maxAllowedFontSize;

    TextStyle styleFor(double size) => TextStyle(
          color: const Color(0xFF202124),
          fontSize: size,
          fontWeight: FontWeight.w500,
          height: size <= 8.0 ? 1.08 : 1.18,
        );

    bool longestWordFits(double size) {
      if (longestWord.isEmpty) return true;
      final wp = _buildTextPainter(
        text: longestWord,
        style: styleFor(size),
        maxWidth: double.infinity,
        maxLines: 1,
      );
      return wp.width <= maxTextWidth;
    }

    TextPainter painter = _buildTextPainter(
      text: trimmedText,
      style: styleFor(fontSize),
      maxWidth: maxTextWidth,
      maxLines: null,
    );

    while ((painter.height > targetMaxHeight ||
            painter.width > maxTextWidth ||
            !longestWordFits(fontSize)) &&
        fontSize > 5.0) {
      fontSize = math.max(5.0, fontSize - 0.5);
      painter = _buildTextPainter(
        text: trimmedText,
        style: styleFor(fontSize),
        maxWidth: maxTextWidth,
        maxLines: null,
      );
    }

    while ((painter.height > targetMaxHeight || painter.width > maxTextWidth) &&
        fontSize > minFontSize) {
      fontSize = math.max(minFontSize, fontSize - 0.25);
      painter = _buildTextPainter(
        text: trimmedText,
        style: styleFor(fontSize),
        maxWidth: maxTextWidth,
        maxLines: null,
      );
    }

    if (_fittedPainterCache.length >= 250) {
      _fittedPainterCache.remove(_fittedPainterCache.keys.first);
    }
    _fittedPainterCache[key] = painter;
    return painter;
  }
}

class _FittedTextPainterCacheKey {
  final String text;
  final double maxTextWidth;
  final double targetMaxHeight;

  const _FittedTextPainterCacheKey({
    required this.text,
    required this.maxTextWidth,
    required this.targetMaxHeight,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FittedTextPainterCacheKey &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          maxTextWidth == other.maxTextWidth &&
          targetMaxHeight == other.targetMaxHeight;

  @override
  int get hashCode => Object.hash(text, maxTextWidth, targetMaxHeight);
}

class _ClusterCacheKey {
  final Object resultIdentity;
  final TranslationRenderMode mode;
  final double width;
  final double height;

  const _ClusterCacheKey(
      this.resultIdentity, this.mode, this.width, this.height);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ClusterCacheKey &&
          runtimeType == other.runtimeType &&
          identical(resultIdentity, other.resultIdentity) &&
          mode == other.mode &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(resultIdentity), mode, width, height);
}
