// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'translation_models.dart';

/// OCR detector contract.
abstract class MangaTextDetector {
  Future<List<RawMangaTextBlock>> detectText(
    String imagePath, {
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  });
  void dispose();
}

/// Raw OCR text block.
class RawMangaTextBlock {
  final Rect boundingBox;
  final String text;
  final List<String> recognizedLanguages;

  const RawMangaTextBlock({
    required this.boundingBox,
    required this.text,
    this.recognizedLanguages = const [],
  });
}

/// Multi-script ML Kit OCR detector with Korean, Chinese, and Latin fallback.
class MlKitMangaTextDetector implements MangaTextDetector {
  final TextRecognitionScript script;
  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  MlKitMangaTextDetector({this.script = TextRecognitionScript.japanese});

  TextRecognizer _getRecognizer(TextRecognitionScript s) {
    return _recognizers.putIfAbsent(s, () => TextRecognizer(script: s));
  }

  TextRecognitionScript _scriptForLanguage(TranslationSourceLanguage lang) {
    switch (lang) {
      case TranslationSourceLanguage.japanese:
        return TextRecognitionScript.japanese;
      case TranslationSourceLanguage.korean:
        return TextRecognitionScript.korean;
      case TranslationSourceLanguage.chinese:
        return TextRecognitionScript.chinese;
      case TranslationSourceLanguage.auto:
        return script;
    }
  }

  @override
  Future<List<RawMangaTextBlock>> detectText(
    String imagePath, {
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  }) async {
    final targetScript = _scriptForLanguage(language);

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = _getRecognizer(targetScript);
      final recognized = await recognizer.processImage(inputImage);
      final blocks = _mapBlocks(recognized, script: targetScript);

      // Retry Korean and Chinese scripts if auto mode finds no blocks.
      if (language == TranslationSourceLanguage.auto && blocks.isEmpty) {
        for (final altScript in [
          TextRecognitionScript.korean,
          TextRecognitionScript.chinese,
        ]) {
          if (altScript == targetScript) continue;
          try {
            final altRec = _getRecognizer(altScript);
            final altRecognized = await altRec.processImage(inputImage);
            final altBlocks = _mapBlocks(altRecognized, script: altScript);
            if (altBlocks.isNotEmpty) {
              return altBlocks;
            }
          } catch (_) {}
        }
      }

      return blocks;
    } catch (e, stack) {
      debugPrint('ML Kit OCR error on $imagePath ($targetScript): $e\n$stack');

      if (targetScript == TextRecognitionScript.latin) {
        return [];
      }

      // Fall back to Latin script if the language model fails.
      try {
        debugPrint(
            'Attempting safe fallback to Latin script recognition for $imagePath');
        final inputImage = InputImage.fromFilePath(imagePath);
        final fallbackRecognizer = _getRecognizer(TextRecognitionScript.latin);
        final fallbackRecognized =
            await fallbackRecognizer.processImage(inputImage);
        return _mapBlocks(fallbackRecognized,
            script: TextRecognitionScript.latin);
      } catch (fallbackError) {
        debugPrint(
            'ML Kit Latin fallback OCR error on $imagePath: $fallbackError');
        return [];
      }
    }
  }

  static bool _hasCjkText(String text) {
    return RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]').hasMatch(text);
  }

  static bool _isBorderArtifact(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty && RegExp(r'^[|丨¦‖]+$').hasMatch(trimmed);
  }

  @visibleForTesting
  static List<RawMangaTextBlock> mapBlocks(
    RecognizedText recognized, {
    TextRecognitionScript? script,
  }) {
    return recognized.blocks.map((block) {
      final box = block.boundingBox;
      final blockRect = Rect.fromLTWH(
        box.left.toDouble(),
        box.top.toDouble(),
        box.width.toDouble(),
        box.height.toDouble(),
      );

      String processedText = block.text;

      final isCjkScript = script == TextRecognitionScript.japanese ||
          script == TextRecognitionScript.chinese ||
          _hasCjkText(block.text);

      if (block.lines.length > 1 && isCjkScript) {
        var lines = block.lines;
        final hasOtherCjkLines =
            lines.any((l) => _hasCjkText(l.text) && !_isBorderArtifact(l.text));
        if (hasOtherCjkLines) {
          final filtered =
              lines.where((l) => !_isBorderArtifact(l.text)).toList();
          if (filtered.isNotEmpty) {
            lines = filtered;
          }
        }

        final isVertical = (blockRect.height >= blockRect.width * 1.05) ||
            lines.any((l) => l.boundingBox.height > l.boundingBox.width * 1.2);

        if (isVertical) {
          final sortedLines = List<TextLine>.from(lines);
          sortedLines.sort(
            (a, b) =>
                b.boundingBox.center.dx.compareTo(a.boundingBox.center.dx),
          );
          processedText = sortedLines
              .map((l) => l.text.trim())
              .where((t) => t.isNotEmpty)
              .join('\n');
        } else if (lines.length != block.lines.length) {
          processedText = lines
              .map((l) => l.text.trim())
              .where((t) => t.isNotEmpty)
              .join('\n');
        }
      }

      return RawMangaTextBlock(
        boundingBox: blockRect,
        text: processedText,
        recognizedLanguages: block.recognizedLanguages,
      );
    }).toList();
  }

  List<RawMangaTextBlock> _mapBlocks(
    RecognizedText recognized, {
    TextRecognitionScript? script,
  }) =>
      mapBlocks(recognized, script: script);

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      try {
        recognizer.close();
      } catch (_) {}
    }
    _recognizers.clear();
  }
}

/// Manga OCR service with block merging and speech-bubble classification.
class MangaOcrService {
  final MangaTextDetector _detector;

  MangaOcrService({MangaTextDetector? detector})
      : _detector = detector ?? MlKitMangaTextDetector();

  Future<List<RawMangaTextBlock>> extractTextBlocks(
    String imagePath, {
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return [];
    }
    final raw = await _detector.detectText(imagePath, language: language);
    return mergeAdjacentBlocks(raw, language: language);
  }

  /// Merges fragmented adjacent OCR blocks belonging to the same speech bubble.
  static List<RawMangaTextBlock> mergeAdjacentBlocks(
    List<RawMangaTextBlock> blocks, {
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  }) {
    if (blocks.length <= 1) {
      return blocks;
    }

    // Scale thresholds by estimated glyph size rather than fixed pixels.
    double charSize(RawMangaTextBlock b) {
      final n = math.max(
        1,
        b.text.split('\n').where((s) => s.trim().isNotEmpty).length,
      );
      return math.max(
        8.0,
        math.min(b.boundingBox.width, b.boundingBox.height) / n,
      );
    }

    bool shouldMerge(RawMangaTextBlock b1, RawMangaTextBlock b2) {
      if (b1.boundingBox.overlaps(b2.boundingBox)) {
        return true;
      }

      final uni = b1.boundingBox.expandToInclude(b2.boundingBox);
      final sumArea = b1.boundingBox.width * b1.boundingBox.height +
          b2.boundingBox.width * b2.boundingBox.height;
      if (uni.width * uni.height > 2.4 * sumArea) {
        return false;
      }

      final ref = math.max(charSize(b1), charSize(b2));
      if (b1.boundingBox.inflate(0.25 * ref).overlaps(b2.boundingBox)) {
        return true;
      }

      final hGap = math.max(
        0.0,
        math.max(b1.boundingBox.left, b2.boundingBox.left) -
            math.min(b1.boundingBox.right, b2.boundingBox.right),
      );
      final vGap = math.max(
        0.0,
        math.max(b1.boundingBox.top, b2.boundingBox.top) -
            math.min(b1.boundingBox.bottom, b2.boundingBox.bottom),
      );

      if (hGap > 3.0 * ref || vGap > 3.0 * ref) {
        return false;
      }

      final vOverlap = math.max(
        0.0,
        math.min(b1.boundingBox.bottom, b2.boundingBox.bottom) -
            math.max(b1.boundingBox.top, b2.boundingBox.top),
      );
      final minH = math.min(b1.boundingBox.height, b2.boundingBox.height);

      final hOverlap = math.max(
        0.0,
        math.min(b1.boundingBox.right, b2.boundingBox.right) -
            math.max(b1.boundingBox.left, b2.boundingBox.left),
      );
      final minW = math.min(b1.boundingBox.width, b2.boundingBox.width);

      if (hGap <= 2.5 * ref &&
          (vOverlap >= 0.35 * minH ||
              (b1.boundingBox.top - b2.boundingBox.top).abs() <= minH * 0.35)) {
        return true;
      }

      if (vGap <= 1.3 * ref &&
          (hOverlap >= 0.35 * minW ||
              (b1.boundingBox.left - b2.boundingBox.left).abs() <=
                  minW * 0.35)) {
        return true;
      }

      return false;
    }

    final parent = List<int>.generate(blocks.length, (i) => i);
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

    for (int i = 0; i < blocks.length; i++) {
      for (int j = i + 1; j < blocks.length; j++) {
        if (shouldMerge(blocks[i], blocks[j])) {
          union(i, j);
        }
      }
    }

    final Map<int, List<RawMangaTextBlock>> clusters = {};
    for (int i = 0; i < blocks.length; i++) {
      final root = find(i);
      clusters.putIfAbsent(root, () => []).add(blocks[i]);
    }

    final List<RawMangaTextBlock> mergedList = [];

    for (final cluster in clusters.values) {
      if (cluster.length == 1) {
        final b = cluster.first;
        final lines =
            b.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty);
        final List<String> distinctLines = [];
        for (final t in lines) {
          int replaceIdx = -1;
          bool isDuplicate = false;
          for (int i = 0; i < distinctLines.length; i++) {
            final existing = distinctLines[i];
            if (existing == t) {
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
            distinctLines[replaceIdx] = t;
          } else if (!isDuplicate) {
            distinctLines.add(t);
          }
        }
        mergedList.add(RawMangaTextBlock(
          boundingBox: b.boundingBox,
          text: distinctLines.join('\n'),
          recognizedLanguages: b.recognizedLanguages,
        ));
        continue;
      }

      double left = cluster.first.boundingBox.left;
      double top = cluster.first.boundingBox.top;
      double right = cluster.first.boundingBox.right;
      double bottom = cluster.first.boundingBox.bottom;

      for (final b in cluster.skip(1)) {
        left = math.min(left, b.boundingBox.left);
        top = math.min(top, b.boundingBox.top);
        right = math.max(right, b.boundingBox.right);
        bottom = math.max(bottom, b.boundingBox.bottom);
      }
      final mergedRect = Rect.fromLTRB(left, top, right, bottom);

      final hasCjk =
          cluster.any((b) => MlKitMangaTextDetector._hasCjkText(b.text));
      final isCjkLang = language == TranslationSourceLanguage.japanese ||
          language == TranslationSourceLanguage.chinese ||
          (language == TranslationSourceLanguage.auto && hasCjk);

      final isVertical = (mergedRect.height >= mergedRect.width * 0.9) ||
          cluster.any((b) => b.boundingBox.height > b.boundingBox.width);

      final sortedCluster = List<RawMangaTextBlock>.from(cluster);
      if (isCjkLang && isVertical) {
        // Vertical CJK columns read right-to-left.
        sortedCluster.sort(
          (a, b) => b.boundingBox.center.dx.compareTo(a.boundingBox.center.dx),
        );
      } else {
        sortedCluster.sort((a, b) {
          final dy = a.boundingBox.top.compareTo(b.boundingBox.top);
          if (dy != 0) return dy;
          return a.boundingBox.left.compareTo(b.boundingBox.left);
        });
      }

      final List<String> distinctLines = [];
      for (final b in sortedCluster) {
        final lines =
            b.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (final t in lines) {
          int replaceIdx = -1;
          bool isDuplicate = false;
          for (int i = 0; i < distinctLines.length; i++) {
            final existing = distinctLines[i];
            if (existing == t) {
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
            distinctLines[replaceIdx] = t;
          } else if (!isDuplicate) {
            distinctLines.add(t);
          }
        }
      }

      final combinedText = distinctLines.join('\n');

      final allLangs =
          sortedCluster.expand((b) => b.recognizedLanguages).toSet().toList();

      mergedList.add(RawMangaTextBlock(
        boundingBox: mergedRect,
        text: combinedText,
        recognizedLanguages: allLangs,
      ));
    }

    return mergedList;
  }

  /// Reads image dimensions from file header.
  static Future<Size> getImageDimensions(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return Size.zero;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return Size.zero;
      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ImageDescriptor.encoded(buffer);
      final size =
          Size(descriptor.width.toDouble(), descriptor.height.toDouble());
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return Size.zero;
    }
  }

  /// Returns true if block geometry matches a speech bubble rather than SFX.
  static bool classifyIsSpeechBubble(
      Rect boundingBox, String text, Size imageSize) {
    if (boundingBox.width <= 0 || boundingBox.height <= 0) return false;

    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final aspectRatio = boundingBox.width / boundingBox.height;

    if (aspectRatio < 0.25 || aspectRatio > 4.2) {
      if (aspectRatio < 0.04 || aspectRatio > 15.0) {
        return false;
      }
      if (math.min(boundingBox.width, boundingBox.height) >= 80 &&
          !RegExp(r'[\u4E00-\u9FFF\u3040-\u309F]').hasMatch(trimmed)) {
        return false;
      }
    }

    if (trimmed.length == 1 &&
        (boundingBox.width > 120 || boundingBox.height > 120)) {
      return false;
    }

    if (imageSize.width > 0 && boundingBox.width > imageSize.width * 0.75) {
      return false;
    }

    return true;
  }

  void dispose() {
    _detector.dispose();
  }
}
