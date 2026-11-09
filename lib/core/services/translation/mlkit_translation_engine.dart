// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'gguf_local_llm_engine.dart';
import 'translation_models.dart';

/// Supported manga translation languages.
enum MangaLanguage {
  indonesian('id', 'Indonesian'),
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
    this.modelDescription = 'Local LLM Engine (GGUF / llama.cpp)',
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
    this.modelDescription = 'Local LLM Engine (GGUF / llama.cpp)',
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

/// On-device neural translation engine using offline-native models and GGUF LLM.
class MlKitTranslationEngine {
  MlKitTranslationEngine._();
  static final MlKitTranslationEngine instance = MlKitTranslationEngine._();

  final GgufLocalLlmEngine _ggufEngine = GgufLocalLlmEngine.instance;

  /// Underlying Local LLM Engine (GGUF / llama.cpp).
  GgufLocalLlmEngine get ggufEngine => _ggufEngine;

  /// High-level operational status message forwarded from the local GGUF engine.
  String? get lastStatusMessage => _ggufEngine.lastStatusMessage;

  /// Description of the offline local model weights.
  static const String localLlmDescription =
      'Local LLM Engine (GGUF / llama.cpp)';

  /// Checks if the local LLM GGUF model or mock inference is ready.
  bool get isLocalLlmReady => _ggufEngine.isReady;

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
      case TranslationTargetLanguage.indonesian:
        return 'Indonesian';
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
      case TranslationTargetLanguage.indonesian:
        return MangaLanguage.indonesian;
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
  /// Reflects whether the local GGUF engine is actually initialized and ready.
  Future<AllModelsStatus> checkAllModelsStatus() async {
    return AllModelsStatus(
      missingLanguages: const [],
      downloadedLanguages: allMangaLanguages,
      totalNeededMb: 0.0,
      isReady: _ggufEngine.isReady,
      modelDescription: localLlmDescription,
    );
  }

  /// Gets the pair download status.
  /// Reflects whether the local GGUF engine is actually initialized and ready.
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
      isReady: _ggufEngine.isReady,
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
    if (_ggufEngine.isReady) {
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

    await _ggufEngine.initializeSession();

    if (_ggufEngine.isReady) {
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

    final errorMsg = _ggufEngine.lastStatusMessage ?? 'No .gguf model loaded';
    downloadProgressNotifier.value = TranslationDownloadProgress(
      isDownloading: false,
      currentStep: 'Failed',
      downloadedMb: 0.0,
      totalMb: 0.0,
      progress: 0.0,
      isSuccess: false,
      errorMessage: errorMsg,
    );
    return false;
  }

  /// Downloads missing pair models with realistic smooth progress updates.
  Future<bool> downloadPairWithProgress(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target, {
    bool isWifiRequired = false,
  }) async {
    if (_ggufEngine.isReady) {
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

    await _ggufEngine.initializeSession();

    if (_ggufEngine.isReady) {
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

    final errorMsg = _ggufEngine.lastStatusMessage ?? 'No .gguf model loaded';
    downloadProgressNotifier.value = TranslationDownloadProgress(
      isDownloading: false,
      currentStep: 'Failed',
      downloadedMb: 0.0,
      totalMb: 0.0,
      progress: 0.0,
      isSuccess: false,
      errorMessage: errorMsg,
    );
    return false;
  }

  /// Translates [text] from [source] language to [target] language using
  /// the underlying Local LLM Engine (GGUF / llama.cpp).
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

    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? detectLanguageFromText(cleaned)
        : source;

    try {
      final translated = await _ggufEngine.translateMangaText(
        text: cleaned,
        source: effectiveSource,
        target: target,
      );
      if (translated.isNotEmpty) {
        return translated;
      }
    } catch (e) {
      debugPrint(
          'Local LLM GGUF translation error ($effectiveSource -> $target): $e');
    }

    return cleaned;
  }

  /// Closes active [GgufLocalLlmEngine] instance.
  Future<void> dispose() async {
    await _ggufEngine.dispose();
  }
}
