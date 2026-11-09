// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'translation_models.dart';

/// On-device neural translation engine using Google ML Kit.
class MlKitTranslationEngine {
  MlKitTranslationEngine._();
  static final MlKitTranslationEngine instance = MlKitTranslationEngine._();

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

  /// Maps [TranslationSourceLanguage] to ML Kit's [TranslateLanguage].
  static TranslateLanguage mapSourceLanguage(TranslationSourceLanguage source) {
    switch (source) {
      case TranslationSourceLanguage.japanese:
        return TranslateLanguage.japanese;
      case TranslationSourceLanguage.korean:
        return TranslateLanguage.korean;
      case TranslationSourceLanguage.chinese:
        return TranslateLanguage.chinese;
      case TranslationSourceLanguage.auto:
        return TranslateLanguage.japanese;
    }
  }

  /// Maps [TranslationTargetLanguage] to ML Kit's [TranslateLanguage].
  static TranslateLanguage mapTargetLanguage(TranslationTargetLanguage target) {
    switch (target) {
      case TranslationTargetLanguage.indonesian:
        return TranslateLanguage.indonesian;
      case TranslationTargetLanguage.english:
        return TranslateLanguage.english;
    }
  }

  /// Determines source language based on character Unicode ranges.
  static TranslationSourceLanguage detectLanguageFromText(String text) {
    if (RegExp(r'[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]').hasMatch(text)) {
      return TranslationSourceLanguage.korean;
    }
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) {
      return TranslationSourceLanguage.japanese;
    }
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) {
      return TranslationSourceLanguage.chinese;
    }
    return TranslationSourceLanguage.japanese;
  }

  /// Normalizes vertical line breaks and trims whitespace.
  static String cleanMangaText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Checks if the model for [lang] is downloaded on-device.
  Future<bool> isLanguageDownloaded(TranslateLanguage lang) async {
    try {
      return await _modelManager.isModelDownloaded(lang.bcpCode);
    } catch (e) {
      debugPrint('Error checking model download status for ${lang.name}: $e');
      return false;
    }
  }

  /// Downloads the on-device model for [lang].
  Future<bool> downloadLanguage(
    TranslateLanguage lang, {
    bool isWifiRequired = false,
  }) async {
    try {
      return await _modelManager.downloadModel(
        lang.bcpCode,
        isWifiRequired: isWifiRequired,
      );
    } catch (e) {
      debugPrint('Error downloading model for ${lang.name}: $e');
      return false;
    }
  }

  /// Checks if both source and target models are downloaded and ready.
  Future<bool> isPairReady(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target,
  ) async {
    try {
      final targetLang = mapTargetLanguage(target);
      final targetReady = await isLanguageDownloaded(targetLang);
      if (!targetReady) return false;

      final effectiveSource = (source == TranslationSourceLanguage.auto)
          ? TranslationSourceLanguage.japanese
          : source;
      final sourceLang = mapSourceLanguage(effectiveSource);
      return await isLanguageDownloaded(sourceLang);
    } catch (e) {
      debugPrint('Error checking isPairReady ($source -> $target): $e');
      return false;
    }
  }

  /// Downloads models for both source and target languages.
  Future<bool> downloadPair(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target, {
    bool isWifiRequired = false,
  }) async {
    try {
      final targetLang = mapTargetLanguage(target);
      final targetOk = await downloadLanguage(
        targetLang,
        isWifiRequired: isWifiRequired,
      );
      if (!targetOk) return false;

      final effectiveSource = (source == TranslationSourceLanguage.auto)
          ? TranslationSourceLanguage.japanese
          : source;
      final sourceLang = mapSourceLanguage(effectiveSource);
      return await downloadLanguage(
        sourceLang,
        isWifiRequired: isWifiRequired,
      );
    } catch (e) {
      debugPrint('Error downloading pair ($source -> $target): $e');
      return false;
    }
  }

  /// Translates [text] from [source] language to [target] language.
  Future<String> translateText(
    String text, {
    required TranslationSourceLanguage source,
    required TranslationTargetLanguage target,
  }) async {
    final cleaned = cleanMangaText(text);
    if (cleaned.isEmpty) return '';

    // Pure punctuation or whitespace returns as-is
    if (RegExp(r'^[!?！？\.\s…]+$').hasMatch(cleaned)) {
      return cleaned;
    }

    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? detectLanguageFromText(cleaned)
        : source;

    final srcLang = mapSourceLanguage(effectiveSource);
    final dstLang = mapTargetLanguage(target);

    try {
      final translator = _getTranslator(srcLang, dstLang);
      final translated = await translator.translateText(cleaned);
      if (translated.isNotEmpty) {
        return translated;
      }
    } catch (e) {
      debugPrint('ML Kit translation error ($effectiveSource -> $target): $e');
    }

    // Fallback gracefully without crashing
    return cleaned;
  }

  OnDeviceTranslator _getTranslator(
    TranslateLanguage source,
    TranslateLanguage target,
  ) {
    final key = '${source.bcpCode}->${target.bcpCode}';
    return _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      ),
    );
  }

  /// Closes all active [OnDeviceTranslator] instances and releases native resources.
  Future<void> dispose() async {
    for (final translator in _translators.values) {
      try {
        await translator.close();
      } catch (e) {
        debugPrint('Error closing OnDeviceTranslator: $e');
      }
    }
    _translators.clear();
  }
}
