// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:ui';

/// Translation render modes.
enum TranslationRenderMode {
  speechBubblesOnly,
  fullImageWithSfx,
}

/// Source language selection for translation.
enum TranslationSourceLanguage {
  auto,
  japanese,
  korean,
  chinese,
}

/// Target language selection for translation.
enum TranslationTargetLanguage {
  english,
}

/// Translation engine selection.
enum TranslationEngineType {
  googleMlKit,
  localLlm,
}

/// Translated text block on a manga page.
class MangaTranslatedBlock {
  final Rect boundingBox;
  final String originalText;
  final String translatedText;
  final bool isSpeechBubble;
  final double confidence;

  const MangaTranslatedBlock({
    required this.boundingBox,
    required this.originalText,
    required this.translatedText,
    this.isSpeechBubble = true,
    this.confidence = 1.0,
  });

  MangaTranslatedBlock copyWith({
    Rect? boundingBox,
    String? originalText,
    String? translatedText,
    bool? isSpeechBubble,
    double? confidence,
  }) {
    return MangaTranslatedBlock(
      boundingBox: boundingBox ?? this.boundingBox,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      isSpeechBubble: isSpeechBubble ?? this.isSpeechBubble,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toJson() => {
        'boundingBox': [
          boundingBox.left,
          boundingBox.top,
          boundingBox.width,
          boundingBox.height,
        ],
        'originalText': originalText,
        'translatedText': translatedText,
        'isSpeechBubble': isSpeechBubble,
        'confidence': confidence,
      };

  factory MangaTranslatedBlock.fromJson(Map<String, dynamic> json) {
    final box = (json['boundingBox'] as List).cast<num>();
    return MangaTranslatedBlock(
      boundingBox: Rect.fromLTWH(
        box[0].toDouble(),
        box[1].toDouble(),
        box[2].toDouble(),
        box[3].toDouble(),
      ),
      originalText: json['originalText'] as String,
      translatedText: json['translatedText'] as String,
      isSpeechBubble: json['isSpeechBubble'] as bool? ?? true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Translation task payload.
class TranslationTask {
  final String imagePath;
  final TranslationRenderMode mode;
  final Size originalImageSize;
  final TranslationSourceLanguage language;
  final TranslationTargetLanguage targetLanguage;
  final int sequence;

  const TranslationTask({
    required this.imagePath,
    required this.mode,
    required this.originalImageSize,
    this.language = TranslationSourceLanguage.auto,
    this.targetLanguage = TranslationTargetLanguage.english,
    this.sequence = 0,
  });

  TranslationTask copyWith({
    String? imagePath,
    TranslationRenderMode? mode,
    Size? originalImageSize,
    TranslationSourceLanguage? language,
    TranslationTargetLanguage? targetLanguage,
    int? sequence,
  }) {
    return TranslationTask(
      imagePath: imagePath ?? this.imagePath,
      mode: mode ?? this.mode,
      originalImageSize: originalImageSize ?? this.originalImageSize,
      language: language ?? this.language,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      sequence: sequence ?? this.sequence,
    );
  }
}

/// Translation result for an image page.
class TranslationResult {
  final String imagePath;
  final List<MangaTranslatedBlock> blocks;
  final Size imageSize;
  final bool isSuccess;
  final String? errorMessage;

  const TranslationResult({
    required this.imagePath,
    required this.blocks,
    required this.imageSize,
    this.isSuccess = true,
    this.errorMessage,
  });

  factory TranslationResult.failure({
    required String imagePath,
    required String errorMessage,
    Size imageSize = Size.zero,
  }) {
    return TranslationResult(
      imagePath: imagePath,
      blocks: const [],
      imageSize: imageSize,
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }
}
