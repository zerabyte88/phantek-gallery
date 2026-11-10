// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
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

/// Multi-script ML Kit OCR implementation with Korean, Chinese, Japanese, and Latin fallback.
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
      final blocks = _mapBlocks(recognized);

      // In auto mode, if initial script returns no blocks, try Korean and Chinese scripts
      if (language == TranslationSourceLanguage.auto && blocks.isEmpty) {
        for (final altScript in [
          TextRecognitionScript.korean,
          TextRecognitionScript.chinese,
        ]) {
          if (altScript == targetScript) continue;
          try {
            final altRec = _getRecognizer(altScript);
            final altRecognized = await altRec.processImage(inputImage);
            final altBlocks = _mapBlocks(altRecognized);
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

      // Safe fallback to Latin script recognition if language-specific model fails
      try {
        debugPrint(
            'Attempting safe fallback to Latin script recognition for $imagePath');
        final inputImage = InputImage.fromFilePath(imagePath);
        final fallbackRecognizer = _getRecognizer(TextRecognitionScript.latin);
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
    for (final recognizer in _recognizers.values) {
      try {
        recognizer.close();
      } catch (_) {}
    }
    _recognizers.clear();
  }
}

/// Manga OCR service with speech bubble vs SFX classification and dimension resolution.
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
    return _detector.detectText(imagePath, language: language);
  }

  /// Reads actual image dimensions from file header if missing or zero.
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
