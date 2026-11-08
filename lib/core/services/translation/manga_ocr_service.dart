// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Text detection abstraction for host unit testing without native platform channels.
abstract class MangaTextDetector {
  Future<List<RawMangaTextBlock>> detectText(String imagePath);
  void dispose();
}

/// Raw detected text block before domain translation.
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

/// Standard ML Kit implementation of text detection for on-device execution.
class MlKitMangaTextDetector implements MangaTextDetector {
  final TextRecognizer _recognizer;

  MlKitMangaTextDetector({TextRecognitionScript script = TextRecognitionScript.japanese})
      : _recognizer = TextRecognizer(script: script);

  @override
  Future<List<RawMangaTextBlock>> detectText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _recognizer.processImage(inputImage);

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
    } catch (e) {
      debugPrint('ML Kit OCR error on $imagePath: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _recognizer.close();
  }
}

/// Offline OCR service specialized in manga layouts, classifying text blocks into
/// dialog speech bubbles vs outer SFX based on geometric aspect ratio and structure.
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

  /// Evaluates whether a bounding box and text block belongs to a speech bubble
  /// versus outer comic sound effects (SFX) / background art text.
  static bool classifyIsSpeechBubble(Rect boundingBox, String text, Size imageSize) {
    if (boundingBox.width <= 0 || boundingBox.height <= 0) return false;

    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final aspectRatio = boundingBox.width / boundingBox.height;

    // Extreme aspect ratio heuristic: ultra-tall or ultra-wide text bursts are SFX
    if (aspectRatio < 0.25 || aspectRatio > 4.2) {
      return false;
    }

    // Isolated single-character bursts outside typical bubble dimensions
    if (trimmed.length == 1 && (boundingBox.width > 120 || boundingBox.height > 120)) {
      return false;
    }

    // Full-page overlay text exceeding 75% width is likely an SFX title or splash
    if (imageSize.width > 0 && boundingBox.width > imageSize.width * 0.75) {
      return false;
    }

    return true;
  }

  void dispose() {
    _detector.dispose();
  }
}
