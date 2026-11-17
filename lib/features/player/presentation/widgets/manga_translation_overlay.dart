// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/services/translation/translation_models.dart';

/// Overlay for translated manga text blocks.
class MangaTranslationOverlay extends StatelessWidget {
  final TranslationResult result;
  final TranslationRenderMode mode;
  final double fontScale;
  final TranslationOverlayStyle overlayStyle;

  const MangaTranslationOverlay({
    super.key,
    required this.result,
    required this.mode,
    this.fontScale = 1.0,
    this.overlayStyle = TranslationOverlayStyle.googleLens,
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
            fontScale: fontScale,
            overlayStyle: overlayStyle,
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
  final double fontScale;
  final TranslationOverlayStyle overlayStyle;

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
    this.fontScale = 1.0,
    this.overlayStyle = TranslationOverlayStyle.googleLens,
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
    final key = _ClusterCacheKey(
      result,
      mode,
      size.width,
      size.height,
      fontScale,
      overlayStyle,
    );
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
    double fontScale = 1.0,
    TranslationOverlayStyle overlayStyle = TranslationOverlayStyle.googleLens,
  }) {
    final normalizedText = _normalizeLayoutText(text);

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
        _computeTextBounds(bubbleRect, fontScale: fontScale);

    _getOrCreateFittedPainter(
      text: normalizedText,
      maxTextWidth: maxTextWidth,
      targetMaxHeight: targetMaxHeight,
      fontScale: fontScale,
      overlayStyle: overlayStyle,
    );

    return bubbleRect;
  }

  static bool _shouldRotateVertical(Rect bubbleRect) =>
      bubbleRect.height > bubbleRect.width * 1.45;

  static String _normalizeLayoutText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static double _safeCornerInset(double extent) => extent <= 12.0
      ? math.min(4.0, extent * 0.12)
      : (extent * 0.12).clamp(6.0, 12.0);

  static double _computeFitScale(
    double contentW,
    double contentH,
    double maxW,
    double maxH,
  ) {
    if (contentW <= maxW && contentH <= maxH) return 1.0;
    return math
        .min(
          maxW / math.max(1.0, contentW),
          maxH / math.max(1.0, contentH),
        )
        .clamp(0.01, 1.0);
  }

  static ({double maxTextWidth, double targetMaxHeight, bool isVertical})
      _computeTextBounds(Rect bubbleRect, {double fontScale = 1.0}) {
    final bool isVertical = _shouldRotateVertical(bubbleRect);
    final double padFactor = fontScale > 1.0
        ? 1.0 - ((fontScale - 1.0) / 0.3).clamp(0.0, 1.0) * 0.45
        : 1.0;
    final double hPad = _safeCornerInset(bubbleRect.width) * padFactor;
    final double vPad = _safeCornerInset(bubbleRect.height) * padFactor;
    final double availW = math.max(4.0, bubbleRect.width - hPad);
    final double availH = math.max(4.0, bubbleRect.height - vPad);
    return (
      maxTextWidth: isVertical ? availH : availW,
      targetMaxHeight: isVertical ? availW : availH,
      isVertical: isVertical,
    );
  }

  @visibleForTesting
  static TextPainter debugFitSpeechBubbleText(
    Rect bubbleRect,
    String text, {
    double fontScale = 1.0,
    TranslationOverlayStyle overlayStyle = TranslationOverlayStyle.googleLens,
  }) {
    final normalizedText = _normalizeLayoutText(text);
    final (:maxTextWidth, :targetMaxHeight, isVertical: _) =
        _computeTextBounds(bubbleRect, fontScale: fontScale);
    return _getOrCreateFittedPainter(
      text: normalizedText,
      maxTextWidth: maxTextWidth,
      targetMaxHeight: targetMaxHeight,
      fontScale: fontScale,
      overlayStyle: overlayStyle,
    );
  }

  void _drawSpeechBubbleBlock(
    Canvas canvas,
    Rect rect,
    String text, [
    Rect? destRect,
    Size? screenSize,
  ]) {
    final normalizedText = _normalizeLayoutText(text);
    if (normalizedText.isEmpty) return;

    final bubbleRect = calculateBubbleRect(
      rect: rect,
      text: normalizedText,
      destRect: destRect,
      screenSize: screenSize,
      fontScale: fontScale,
      overlayStyle: overlayStyle,
    );

    final (:maxTextWidth, :targetMaxHeight, :isVertical) =
        _computeTextBounds(bubbleRect, fontScale: fontScale);

    final painter = _getOrCreateFittedPainter(
      text: normalizedText,
      maxTextWidth: maxTextWidth,
      targetMaxHeight: targetMaxHeight,
      fontScale: fontScale,
      overlayStyle: overlayStyle,
    );

    final double screenW = screenSize?.width ?? destRect?.width ?? 400.0;
    final double screenH = screenSize?.height ?? destRect?.height ?? 800.0;
    final Rect safeViewport = Rect.fromLTWH(
      4.0,
      4.0,
      math.max(20.0, screenW - 8.0),
      math.max(20.0, screenH - 8.0),
    );
    final Rect eraseRect = bubbleRect.inflate(3.5).intersect(safeViewport);
    final double cornerRadius =
        (isVertical || math.min(bubbleRect.width, bubbleRect.height) < 55.0)
            ? 3.5
            : 8.0;
    final RRect eraseRRect =
        RRect.fromRectAndRadius(eraseRect, Radius.circular(cornerRadius));

    final palette = _OverlayStylePalette.fromStyle(overlayStyle);
    canvas.drawRRect(eraseRRect, Paint()..color = palette.bubbleFill);
    canvas.drawRRect(
      eraseRRect,
      Paint()
        ..color = palette.bubbleBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = palette.bubbleBorderWidth,
    );

    final double fitScale = _computeFitScale(
      painter.width,
      painter.height,
      maxTextWidth,
      targetMaxHeight,
    );

    canvas.save();
    canvas.clipRRect(eraseRRect);
    if (isVertical) {
      canvas.translate(bubbleRect.center.dx, bubbleRect.center.dy);
      canvas.rotate(math.pi / 2);
      if (fitScale < 1.0) {
        canvas.scale(fitScale);
      }
      painter.paint(
        canvas,
        Offset(-painter.width / 2.0, -painter.height / 2.0),
      );
    } else if (fitScale < 1.0) {
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
    final normalized = _normalizeLayoutText(text);
    if (normalized.isEmpty) return;

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
    final Rect eraseRect = pillRect.inflate(2.5).intersect(safeViewport);
    final RRect eraseRRect =
        RRect.fromRectAndRadius(eraseRect, const Radius.circular(4.0));

    const double strokeMargin = 4.0;
    final double padFactor = fontScale > 1.0
        ? 1.0 - ((fontScale - 1.0) / 0.3).clamp(0.0, 1.0) * 0.45
        : 1.0;
    final double hPad = _safeCornerInset(pillRect.width) * padFactor +
        (pillRect.width > 16.0 ? strokeMargin : 0.0);
    final double vPad = _safeCornerInset(pillRect.height) * padFactor +
        (pillRect.height > 16.0 ? strokeMargin : 0.0);
    final double maxTextWidth = math.max(4.0, pillRect.width - hPad);
    final double maxTextHeight = math.max(4.0, pillRect.height - vPad);

    final palette = _OverlayStylePalette.fromStyle(overlayStyle);

    final (painter: fillPainter, :fontSize) = _fitTextPainterToBounds(
      text: normalized,
      maxWidth: maxTextWidth,
      maxHeight: maxTextHeight,
      fontScale: fontScale,
      styleBuilder: (size) => TextStyle(
        color: palette.sfxText,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: size <= 8.0 ? 1.08 : 1.15,
      ),
    );

    final double strokeWidth = (fontSize * 0.22).clamp(0.8, 2.5);
    final strokePainter = _buildTextPainter(
      text: normalized,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: fontSize <= 8.0 ? 1.08 : 1.15,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = palette.sfxStroke,
      ),
      maxWidth: maxTextWidth,
      maxLines: null,
    );

    final double fitScale = _computeFitScale(
      fillPainter.width + strokeWidth,
      fillPainter.height + strokeWidth,
      math.max(1.0, pillRect.width - 2.0),
      math.max(1.0, pillRect.height - 2.0),
    );

    canvas.drawRRect(
      eraseRRect,
      Paint()
        ..color = palette.sfxFill
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      eraseRRect,
      Paint()
        ..color = palette.sfxBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    canvas.save();
    canvas.clipRRect(eraseRRect);

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

  static ({TextPainter painter, double fontSize}) _fitTextPainterToBounds({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextStyle Function(double size) styleBuilder,
    double minFontSize = 1.5,
    double? maxFontSize,
    double fontScale = 1.0,
  }) {
    final normalizedText = _normalizeLayoutText(text);
    final double effectiveCap = (24.0 * fontScale).clamp(10.0, 34.0);
    final double upperBound =
        (maxFontSize ?? math.min(effectiveCap, math.max(12.0 * fontScale, maxHeight * 0.72)))
            .clamp(minFontSize, effectiveCap)
            .toDouble();

    String longestWord = '';
    for (final w in normalizedText.split(' ')) {
      if (w.length > longestWord.length) longestWord = w;
    }

    bool longestWordFits(double size) {
      if (longestWord.isEmpty) return true;
      final wp = _buildTextPainter(
        text: longestWord,
        style: styleBuilder(size),
        maxWidth: double.infinity,
        maxLines: 1,
      );
      return wp.width <= maxWidth;
    }

    TextPainter? tryFit(double size) {
      if (!longestWordFits(size)) return null;
      final candidate = _buildTextPainter(
        text: normalizedText,
        style: styleBuilder(size),
        maxWidth: maxWidth,
        maxLines: null,
      );
      if (candidate.height <= maxHeight && candidate.width <= maxWidth) {
        return candidate;
      }
      return null;
    }

    TextPainter bestPainter;
    double bestSize;

    final upperCandidate = tryFit(upperBound);
    if (upperCandidate != null) {
      bestPainter = upperCandidate;
      bestSize = upperBound;
    } else {
      final minCandidate = tryFit(minFontSize);
      if (minCandidate == null) {
        final fallback = _buildTextPainter(
          text: normalizedText,
          style: styleBuilder(minFontSize),
          maxWidth: maxWidth,
          maxLines: null,
        );
        bestPainter = fallback;
        bestSize = minFontSize;
      } else {
        double low = minFontSize;
        double high = upperBound;
        bestPainter = minCandidate;
        bestSize = minFontSize;

        while (high - low > 0.1) {
          final double mid = (low + high) / 2.0;
          final candidate = tryFit(mid);
          if (candidate != null) {
            bestPainter = candidate;
            bestSize = mid;
            low = mid;
          } else {
            high = mid;
          }
        }
      }
    }

    if (fontScale < 1.0) {
      final scaledSize =
          (bestSize * fontScale).clamp(minFontSize, effectiveCap).toDouble();
      final scaledPainter = _buildTextPainter(
        text: normalizedText,
        style: styleBuilder(scaledSize),
        maxWidth: maxWidth,
        maxLines: null,
      );
      return (painter: scaledPainter, fontSize: scaledSize);
    }

    return (painter: bestPainter, fontSize: bestSize);
  }

  @override
  bool shouldRepaint(covariant MangaTranslationPainter oldDelegate) {
    return oldDelegate.result != result ||
        oldDelegate.mode != mode ||
        oldDelegate.viewportSize != viewportSize ||
        oldDelegate.fontScale != fontScale ||
        oldDelegate.overlayStyle != overlayStyle;
  }

  static TextPainter _getOrCreateFittedPainter({
    required String text,
    required double maxTextWidth,
    required double targetMaxHeight,
    double fontScale = 1.0,
    TranslationOverlayStyle overlayStyle = TranslationOverlayStyle.googleLens,
  }) {
    final normalizedText = _normalizeLayoutText(text);
    final key = _FittedTextPainterCacheKey(
      text: normalizedText,
      maxTextWidth: (maxTextWidth * 10).round() / 10,
      targetMaxHeight: (targetMaxHeight * 10).round() / 10,
      fontScale: (fontScale * 100).round() / 100,
      overlayStyle: overlayStyle,
    );

    final cached = _fittedPainterCache[key];
    if (cached != null) return cached;

    final palette = _OverlayStylePalette.fromStyle(overlayStyle);

    final (:painter, fontSize: _) = _fitTextPainterToBounds(
      text: normalizedText,
      maxWidth: maxTextWidth,
      maxHeight: targetMaxHeight,
      fontScale: fontScale,
      styleBuilder: (size) => TextStyle(
        color: palette.textColor,
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: size <= 8.0 ? 1.08 : 1.18,
      ),
    );

    if (_fittedPainterCache.length >= 250) {
      _fittedPainterCache.remove(_fittedPainterCache.keys.first);
    }
    _fittedPainterCache[key] = painter;
    return painter;
  }
}

class _OverlayStylePalette {
  const _OverlayStylePalette({
    required this.bubbleFill,
    required this.bubbleBorder,
    required this.bubbleBorderWidth,
    required this.textColor,
    required this.sfxFill,
    required this.sfxBorder,
    required this.sfxText,
    required this.sfxStroke,
  });

  final Color bubbleFill;
  final Color bubbleBorder;
  final double bubbleBorderWidth;
  final Color textColor;
  final Color sfxFill;
  final Color sfxBorder;
  final Color sfxText;
  final Color sfxStroke;

  factory _OverlayStylePalette.fromStyle(TranslationOverlayStyle style) {
    return switch (style) {
      TranslationOverlayStyle.googleLens => _OverlayStylePalette(
          bubbleFill: const Color(0xFFFDFDFD),
          bubbleBorder: const Color(0xFF5F6368),
          bubbleBorderWidth: 1.1,
          textColor: const Color(0xFF202124),
          sfxFill: Colors.white.withValues(alpha: 0.94),
          sfxBorder: const Color(0xFFDADCE0),
          sfxText: const Color(0xFF202124),
          sfxStroke: Colors.white,
        ),
      TranslationOverlayStyle.classicManga => const _OverlayStylePalette(
          bubbleFill: Color(0xFFFFFFFF),
          bubbleBorder: Color(0xFF111111),
          bubbleBorderWidth: 1.5,
          textColor: Color(0xFF000000),
          sfxFill: Colors.white,
          sfxBorder: Color(0xFF111111),
          sfxText: Color(0xFF000000),
          sfxStroke: Colors.white,
        ),
      TranslationOverlayStyle.darkContrast => const _OverlayStylePalette(
          bubbleFill: Color(0xF218181B),
          bubbleBorder: Color(0xFF71717A),
          bubbleBorderWidth: 1.1,
          textColor: Color(0xFFF4F4F5),
          sfxFill: Color(0xEE18181B),
          sfxBorder: Color(0xFF52525B),
          sfxText: Color(0xFFF4F4F5),
          sfxStroke: Color(0xFF09090B),
        ),
      TranslationOverlayStyle.translucent => const _OverlayStylePalette(
          bubbleFill: Color(0xC7111318),
          bubbleBorder: Colors.white38,
          bubbleBorderWidth: 1.0,
          textColor: Color(0xFFFFFFFF),
          sfxFill: Color(0xBD111318),
          sfxBorder: Colors.white30,
          sfxText: Color(0xFFFFFFFF),
          sfxStroke: Color(0xFF000000),
        ),
    };
  }
}

class _FittedTextPainterCacheKey {
  final String text;
  final double maxTextWidth;
  final double targetMaxHeight;
  final double fontScale;
  final TranslationOverlayStyle overlayStyle;

  const _FittedTextPainterCacheKey({
    required this.text,
    required this.maxTextWidth,
    required this.targetMaxHeight,
    required this.fontScale,
    required this.overlayStyle,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FittedTextPainterCacheKey &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          maxTextWidth == other.maxTextWidth &&
          targetMaxHeight == other.targetMaxHeight &&
          fontScale == other.fontScale &&
          overlayStyle == other.overlayStyle;

  @override
  int get hashCode => Object.hash(
        text,
        maxTextWidth,
        targetMaxHeight,
        fontScale,
        overlayStyle,
      );
}

class _ClusterCacheKey {
  final Object resultIdentity;
  final TranslationRenderMode mode;
  final double width;
  final double height;
  final double fontScale;
  final TranslationOverlayStyle overlayStyle;

  const _ClusterCacheKey(
    this.resultIdentity,
    this.mode,
    this.width,
    this.height,
    this.fontScale,
    this.overlayStyle,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ClusterCacheKey &&
          runtimeType == other.runtimeType &&
          identical(resultIdentity, other.resultIdentity) &&
          mode == other.mode &&
          width == other.width &&
          height == other.height &&
          fontScale == other.fontScale &&
          overlayStyle == other.overlayStyle;

  @override
  int get hashCode => Object.hash(
        identityHashCode(resultIdentity),
        mode,
        width,
        height,
        fontScale,
        overlayStyle,
      );
}
