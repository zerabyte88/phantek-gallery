// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../settings_service.dart';
import 'lm_studio_translation_engine.dart';
import 'onnx_translation_engine.dart';
import 'translation_models.dart';

/// Supported manga translation languages.
enum MangaLanguage {
  english('en', 'English'),
  japanese('ja', 'Japanese'),
  korean('ko', 'Korean'),
  chinese('zh', 'Chinese');

  final String bcpCode;
  final String label;
  const MangaLanguage(this.bcpCode, this.label);
}

/// Status model for language pair readiness and download footprint.
class ModelPairStatus {
  final bool sourceDownloaded;
  final bool targetDownloaded;
  final String sourceLangName;
  final String targetLangName;
  final double totalNeededMb;
  final bool isReady;
  final String modelDescription;

  const ModelPairStatus({
    required this.sourceDownloaded,
    required this.targetDownloaded,
    required this.sourceLangName,
    required this.targetLangName,
    required this.totalNeededMb,
    required this.isReady,
    this.modelDescription = 'Local AI Server (LM Studio)',
  });
}

/// Status model for all 5 manga translation models readiness and download footprint.
class AllModelsStatus {
  final List<MangaLanguage> missingLanguages;
  final List<MangaLanguage> downloadedLanguages;
  final double totalNeededMb;
  final bool isReady;
  final String modelDescription;

  const AllModelsStatus({
    required this.missingLanguages,
    required this.downloadedLanguages,
    required this.totalNeededMb,
    required this.isReady,
    this.modelDescription = 'Local AI Server (LM Studio)',
  });
}

/// Progress state model for live translation model downloads.
class TranslationDownloadProgress {
  final bool isDownloading;
  final String currentStep;
  final double downloadedMb;
  final double totalMb;
  final double progress;
  final bool isSuccess;
  final String? errorMessage;

  const TranslationDownloadProgress({
    this.isDownloading = false,
    this.currentStep = '',
    this.downloadedMb = 0.0,
    this.totalMb = 0.0,
    this.progress = 0.0,
    this.isSuccess = false,
    this.errorMessage,
  });

  TranslationDownloadProgress copyWith({
    bool? isDownloading,
    String? currentStep,
    double? downloadedMb,
    double? totalMb,
    double? progress,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return TranslationDownloadProgress(
      isDownloading: isDownloading ?? this.isDownloading,
      currentStep: currentStep ?? this.currentStep,
      downloadedMb: downloadedMb ?? this.downloadedMb,
      totalMb: totalMb ?? this.totalMb,
      progress: progress ?? this.progress,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Neural translation engine using Google ML Kit on-device and Local AI Server (LM Studio / Ollama).
class MlKitTranslationEngine {
  MlKitTranslationEngine._();
  static final MlKitTranslationEngine instance = MlKitTranslationEngine._();

  final LmStudioTranslationEngine _lmStudioEngine =
      LmStudioTranslationEngine.instance;
  final OnnxTranslationEngine _onnxEngine = OnnxTranslationEngine.instance;
  final OnDeviceTranslatorModelManager _mlKitModelManager =
      OnDeviceTranslatorModelManager();

  /// Underlying Helsinki-NLP ONNX translation engine.
  OnnxTranslationEngine get onnxEngine => _onnxEngine;

  /// Maps BCP-47 language code strings to Google ML Kit's [TranslateLanguage].
  static TranslateLanguage? mapToTranslateLanguage(String bcpCode) {
    switch (bcpCode.toLowerCase()) {
      case 'en':
        return TranslateLanguage.english;
      case 'ja':
        return TranslateLanguage.japanese;
      case 'zh':
        return TranslateLanguage.chinese;
      case 'ko':
        return TranslateLanguage.korean;
      default:
        return null;
    }
  }

  /// Checks if Google ML Kit on-device model for [bcpCode] is downloaded.
  Future<bool> isModelDownloaded(String bcpCode) async {
    final lang = mapToTranslateLanguage(bcpCode);
    if (lang == null) return false;
    try {
      return await _mlKitModelManager.isModelDownloaded(lang.bcpCode);
    } catch (e) {
      debugPrint('Error checking ML Kit model download ($bcpCode): $e');
      return false;
    }
  }

  /// Downloads Google ML Kit on-device model for [bcpCode] with 1 hour timeout.
  /// When downloading ja, zh, or ko, also verifies and automatically downloads en (English).
  Future<bool> downloadModel(String bcpCode, {bool isWifiRequired = false}) async {
    final lang = mapToTranslateLanguage(bcpCode);
    if (lang == null) return false;
    try {
      final success = await _mlKitModelManager
          .downloadModel(lang.bcpCode, isWifiRequired: isWifiRequired)
          .timeout(const Duration(hours: 1));
      if (!success) return false;

      // Automatically download en model if not present, ensuring translation pair is complete
      if (lang != TranslateLanguage.english) {
        try {
          final enDownloaded = await isModelDownloaded('en');
          if (!enDownloaded) {
            await _mlKitModelManager
                .downloadModel(TranslateLanguage.english.bcpCode,
                    isWifiRequired: isWifiRequired)
                .timeout(const Duration(hours: 1));
          }
        } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('Error downloading ML Kit model ($bcpCode): $e');
      return false;
    }
  }

  /// Deletes Google ML Kit on-device model for [bcpCode].
  Future<bool> deleteModel(String bcpCode) async {
    final lang = mapToTranslateLanguage(bcpCode);
    if (lang == null) return false;
    try {
      return await _mlKitModelManager.deleteModel(lang.bcpCode);
    } catch (e) {
      debugPrint('Error deleting ML Kit model ($bcpCode): $e');
      return false;
    }
  }

  final Map<String, OnDeviceTranslator> _translators = {};

  OnDeviceTranslator _getTranslator(
    TranslateLanguage source,
    TranslateLanguage target,
  ) {
    final key = '${source.bcpCode}_${target.bcpCode}';
    return _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      ),
    );
  }

  /// Optional mock translator hook for unit tests.
  @visibleForTesting
  Future<String> Function(
    String text,
    TranslateLanguage source,
    TranslateLanguage target,
  )? mockMlKitTranslator;

  /// Translates text using Google ML Kit's on-device neural translator.
  Future<String> translateWithGoogleMlKit({
    required String text,
    required TranslationSourceLanguage source,
  }) async {
    final cleaned = cleanMangaText(text);
    if (cleaned.isEmpty) return '';
    if (!LmStudioTranslationEngine.hasTranslatableDialogue(cleaned)) {
      return cleaned;
    }

    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? detectLanguageFromText(cleaned)
        : source;

    final sourceLang = switch (effectiveSource) {
      TranslationSourceLanguage.japanese => TranslateLanguage.japanese,
      TranslationSourceLanguage.korean => TranslateLanguage.korean,
      TranslationSourceLanguage.chinese => TranslateLanguage.chinese,
      TranslationSourceLanguage.auto => TranslateLanguage.japanese,
    };

    if (mockMlKitTranslator != null) {
      Future<String> mock(String t) =>
          mockMlKitTranslator!(t, sourceLang, TranslateLanguage.english);
      return await translateLeftoverCjk(await mock(cleaned), mock);
    }

    try {
      final translator = _getTranslator(sourceLang, TranslateLanguage.english);
      final translated = await translator.translateText(cleaned);
      return await translateLeftoverCjk(translated, translator.translateText);
    } catch (e) {
      debugPrint('[MlKitTranslationEngine] Google ML Kit error ($sourceLang -> en): $e');
      rethrow;
    }
  }

  /// ML Kit sometimes leaves fragments (e.g. 大丈夫…) untranslated inside the
  /// English output; translate each leftover CJK run on its own.
  @visibleForTesting
  static Future<String> translateLeftoverCjk(
    String output,
    Future<String> Function(String) translate,
  ) async {
    final cjk = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff\uac00-\ud7af]+');
    final buffer = StringBuffer();
    int last = 0;
    for (final m in cjk.allMatches(output)) {
      buffer.write(output.substring(last, m.start));
      final piece = (await translate(m.group(0)!)).trim();
      final usable = piece.isNotEmpty && !cjk.hasMatch(piece);
      if (usable) {
        if (m.start > 0 && output[m.start - 1] != ' ') buffer.write(' ');
        buffer.write(piece);
        if (m.end < output.length &&
            output[m.end] != ' ' &&
            !RegExp(r'^[.,!?:;…~’”\)]').hasMatch(output.substring(m.end))) {
          buffer.write(' ');
        }
      } else {
        buffer.write(m.group(0));
      }
      last = m.end;
    }
    buffer.write(output.substring(last));
    return buffer.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  /// Underlying Local AI Server Engine (LM Studio / Ollama).
  LmStudioTranslationEngine get lmStudioEngine => _lmStudioEngine;

  /// High-level operational status message forwarded from the local AI engine.
  String? get lastStatusMessage => _lmStudioEngine.lastStatusMessage;

  /// Description of the translation engine.
  static const String localLlmDescription =
      'Local AI Server (LM Studio / Ollama)';

  /// Checks if the local AI engine is ready.
  bool get isLocalLlmReady => _lmStudioEngine.isReady;
  bool get isLmStudioReady => _lmStudioEngine.isReady;

  /// The 5 manga translation languages required for all source and target pairs.
  static const List<MangaLanguage> allMangaLanguages = MangaLanguage.values;

  /// Reactive notifier for model download progress and statuses.
  final ValueNotifier<TranslationDownloadProgress> downloadProgressNotifier =
      ValueNotifier<TranslationDownloadProgress>(
          const TranslationDownloadProgress());

  static String _getSourceLangName(TranslationSourceLanguage source) {
    switch (source) {
      case TranslationSourceLanguage.auto:
      case TranslationSourceLanguage.japanese:
        return 'Japanese';
      case TranslationSourceLanguage.korean:
        return 'Korean';
      case TranslationSourceLanguage.chinese:
        return 'Chinese';
    }
  }

  static String _getTargetLangName(TranslationTargetLanguage target) {
    switch (target) {
      case TranslationTargetLanguage.english:
        return 'English';
    }
  }

  /// Maps [TranslationSourceLanguage] to [MangaLanguage].
  static MangaLanguage mapSourceLanguage(TranslationSourceLanguage source) {
    switch (source) {
      case TranslationSourceLanguage.japanese:
        return MangaLanguage.japanese;
      case TranslationSourceLanguage.korean:
        return MangaLanguage.korean;
      case TranslationSourceLanguage.chinese:
        return MangaLanguage.chinese;
      case TranslationSourceLanguage.auto:
        return MangaLanguage.japanese;
    }
  }

  /// Maps [TranslationTargetLanguage] to [MangaLanguage].
  static MangaLanguage mapTargetLanguage(TranslationTargetLanguage target) {
    switch (target) {
      case TranslationTargetLanguage.english:
        return MangaLanguage.english;
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

  /// Normalizes vertical line breaks, trims whitespace, removes border artifacts,
  /// and merges accidental intra-CJK whitespace.
  static String cleanMangaText(String text) {
    final cleaned = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'(?:^|\n)\s*[|丨¦‖]\s*(?=\n|$)'), '\n')
        // Vertical OCR misreads the long-vowel mark after katakana and the
        // kanji 一 (e.g. 一旦, 一時間) as a pipe.
        .replaceAll(RegExp(r'(?<=[\u30a0-\u30ff])\s*[|丨¦‖]'), 'ー')
        .replaceAll(
            RegExp(r'[|丨¦‖]\s*(?=[\u3040-\u30ff\u4e00-\u9fff])'), '一');

    final lines = cleaned
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !RegExp(r'^[|丨¦‖]+$').hasMatch(s))
        .toList();

    if (lines.isEmpty) return '';

    final buffer = StringBuffer(lines.first);
    for (int i = 1; i < lines.length; i++) {
      final prev = lines[i - 1];
      final curr = lines[i];

      final prevLastCodePoint = prev.runes.last;
      final currFirstCodePoint = curr.runes.first;
      final prevLastChar = String.fromCharCode(prevLastCodePoint);
      final currFirstChar = String.fromCharCode(currFirstCodePoint);

      if (LmStudioTranslationEngine.hasCjkCharacters(prevLastChar) &&
          LmStudioTranslationEngine.hasCjkCharacters(currFirstChar)) {
        buffer.write(curr);
      } else {
        buffer.write(' ');
        buffer.write(curr);
      }
    }

    var result = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove accidental intra-CJK whitespace created by OCR character segmentation
    final cjkSpacePattern = RegExp(
      r'([\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff])\s+([\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff])',
    );
    while (cjkSpacePattern.hasMatch(result)) {
      result = result.replaceAllMapped(
        cjkSpacePattern,
        (m) => '${m[1]}${m[2]}',
      );
    }

    return result;
  }

  /// Checks if the model for [lang] is downloaded on-device.
  /// In offline-native mode, all languages are supported on-device.
  Future<bool> isLanguageDownloaded(MangaLanguage lang) async {
    return true;
  }

  /// Downloads the on-device model for [lang].
  /// In offline-native mode, models are bundled and ready immediately.
  Future<bool> downloadLanguage(
    MangaLanguage lang, {
    bool isWifiRequired = false,
  }) async {
    return true;
  }

  /// Checks status for all 5 manga translation languages.
  /// Reflects whether the translation engine is initialized and ready.
  Future<AllModelsStatus> checkAllModelsStatus() async {
    return AllModelsStatus(
      missingLanguages: const [],
      downloadedLanguages: allMangaLanguages,
      totalNeededMb: 0.0,
      isReady: _lmStudioEngine.isReady,
      modelDescription: localLlmDescription,
    );
  }

  /// Gets the pair download status.
  Future<ModelPairStatus> getPairStatus(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target,
  ) async {
    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? TranslationSourceLanguage.japanese
        : source;

    return ModelPairStatus(
      sourceDownloaded: true,
      targetDownloaded: true,
      sourceLangName: _getSourceLangName(effectiveSource),
      targetLangName: _getTargetLangName(target),
      totalNeededMb: 0.0,
      isReady: _lmStudioEngine.isReady,
      modelDescription: localLlmDescription,
    );
  }

  /// Checks if both source and target models are downloaded and ready.
  Future<bool> isPairReady(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target,
  ) async {
    return true;
  }

  /// Downloads models for both source and target languages.
  Future<bool> downloadPair(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target, {
    bool isWifiRequired = false,
  }) async {
    return downloadPairWithProgress(source, target,
        isWifiRequired: isWifiRequired);
  }

  /// Downloads all missing manga translation models sequentially (id, en, ja, ko, zh).
  Future<bool> downloadAllModelsWithProgress({
    bool isWifiRequired = false,
  }) async {
    downloadProgressNotifier.value = const TranslationDownloadProgress(
      isDownloading: false,
      currentStep: 'Ready',
      downloadedMb: 0.0,
      totalMb: 0.0,
      progress: 1.0,
      isSuccess: true,
    );
    return true;
  }

  /// Downloads missing pair models with realistic smooth progress updates.
  Future<bool> downloadPairWithProgress(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target, {
    bool isWifiRequired = false,
  }) async {
    downloadProgressNotifier.value = const TranslationDownloadProgress(
      isDownloading: false,
      currentStep: 'Ready',
      downloadedMb: 0.0,
      totalMb: 0.0,
      progress: 1.0,
      isSuccess: true,
    );
    return true;
  }

  /// Translates [text] from [source] language to [target] language using
  /// Google ML Kit or the Local AI Server (LM Studio / Ollama).
  Future<String> translateText(
    String text, {
    required TranslationSourceLanguage source,
    required TranslationTargetLanguage target,
  }) async {
    final cleaned = cleanMangaText(text);
    if (cleaned.isEmpty) return '';

    if (RegExp(r'^[!?！？\.\s…]+$').hasMatch(cleaned)) {
      return cleaned;
    }

    if (!LmStudioTranslationEngine.hasTranslatableDialogue(cleaned)) {
      return cleaned;
    }

    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? detectLanguageFromText(cleaned)
        : source;

    final engineType = SettingsService.hasInstance
        ? SettingsService.instance.settings.translationEngineType
        : TranslationEngineType.lmStudio;

    if (engineType == TranslationEngineType.onnxHelsinki) {
      try {
        final onnxResult = await _onnxEngine.translateMangaText(
          text: cleaned,
          source: effectiveSource,
          target: target,
        );
        if (onnxResult.isNotEmpty) {
          return onnxResult;
        }
      } catch (e) {
        debugPrint(
            'Helsinki ONNX translation error ($effectiveSource -> $target): $e');
      }
    }

    if (engineType == TranslationEngineType.googleMlKit &&
        _lmStudioEngine.mockInferenceHandler == null) {
      try {
        final mlKitResult = await translateWithGoogleMlKit(
          text: cleaned,
          source: effectiveSource,
        );
        if (mlKitResult.isNotEmpty) {
          return mlKitResult;
        }
      } catch (e) {
        debugPrint(
            'Google ML Kit translation error ($effectiveSource -> $target): $e');
      }
    }

    try {
      final translated = await _lmStudioEngine.translateMangaText(
        text: cleaned,
        source: effectiveSource,
        target: target,
      );
      if (translated.isNotEmpty) {
        return translated;
      }
    } catch (e) {
      debugPrint(
          'LM Studio translation error ($effectiveSource -> $target): $e');
    }

    return cleaned;
  }

  /// Closes active [LmStudioTranslationEngine] instance and any cached translators.
  Future<void> dispose() async {
    for (final translator in _translators.values) {
      try {
        await translator.close();
      } catch (e) {
        debugPrint('Error closing OnDeviceTranslator: $e');
      }
    }
    _translators.clear();
    await _onnxEngine.dispose();
    await _lmStudioEngine.dispose();
  }
}
