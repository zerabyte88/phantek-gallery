// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR detector contract.
abstract class MangaTextDetector {
  Future<List<RawMangaTextBlock>> detectText(String imagePath);
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

/// ML Kit OCR implementation.
class MlKitMangaTextDetector implements MangaTextDetector {
  final TextRecognitionScript script;
  TextRecognizer? _recognizer;
  TextRecognizer? _fallbackRecognizer;

  MlKitMangaTextDetector({this.script = TextRecognitionScript.japanese});

  TextRecognizer _getRecognizer() {
    return _recognizer ??= TextRecognizer(script: script);
  }

  TextRecognizer _getFallbackRecognizer() {
    return _fallbackRecognizer ??=
        TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  Future<List<RawMangaTextBlock>> detectText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = _getRecognizer();
      final recognized = await recognizer.processImage(inputImage);
      return _mapBlocks(recognized);
    } catch (e, stack) {
      debugPrint('ML Kit OCR error on $imagePath ($script): $e\n$stack');

      if (script == TextRecognitionScript.latin) {
        return [];
      }

      // Fallback to Latin if script model is unavailable
      try {
        debugPrint(
            'Attempting safe fallback to Latin script recognition for $imagePath');
        final inputImage = InputImage.fromFilePath(imagePath);
        final fallbackRecognizer = _getFallbackRecognizer();
        final fallbackRecognized =
            await fallbackRecognizer.processImage(inputImage);
        return _mapBlocks(fallbackRecognized);
      } catch (fallbackError) {
        debugPrint(
            'ML Kit Latin fallback OCR error on $imagePath: $fallbackError');
        return [];
      }
    }
  }

  List<RawMangaTextBlock> _mapBlocks(RecognizedText recognized) {
    return recognized.blocks.map((block) {
      final box = block.boundingBox;
      return RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(
          box.left.toDouble(),
          box.top.toDouble(),
          box.width.toDouble(),
          box.height.toDouble(),
        ),
        text: block.text,
        recognizedLanguages: block.recognizedLanguages,
      );
    }).toList();
  }

  @override
  void dispose() {
    try {
      _recognizer?.close();
    } catch (_) {}
    _recognizer = null;

    try {
      _fallbackRecognizer?.close();
    } catch (_) {}
    _fallbackRecognizer = null;
  }
}

/// Manga OCR service with speech bubble vs SFX classification.
class MangaOcrService {
  final MangaTextDetector _detector;

  MangaOcrService({MangaTextDetector? detector})
      : _detector = detector ?? MlKitMangaTextDetector();

  Future<List<RawMangaTextBlock>> extractTextBlocks(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return [];
    }
    return _detector.detectText(imagePath);
  }

  /// Returns true if text block matches speech bubble geometry.
  static bool classifyIsSpeechBubble(
      Rect boundingBox, String text, Size imageSize) {
    if (boundingBox.width <= 0 || boundingBox.height <= 0) return false;

    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final aspectRatio = boundingBox.width / boundingBox.height;

    // Extreme aspect ratio indicates SFX
    if (aspectRatio < 0.25 || aspectRatio > 4.2) {
      return false;
    }

    // Single large character indicates SFX
    if (trimmed.length == 1 &&
        (boundingBox.width > 120 || boundingBox.height > 120)) {
      return false;
    }

    // Full-page banner indicates SFX
    if (imageSize.width > 0 && boundingBox.width > imageSize.width * 0.75) {
      return false;
    }

    return true;
  }

  void dispose() {
    _detector.dispose();
  }
}
