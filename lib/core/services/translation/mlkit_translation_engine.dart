// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'onnx_local_llm_engine.dart';
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
    this.modelDescription = 'Local LLM Engine (ONNX / Gemma 3 Nano)',
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
    this.modelDescription = 'Local LLM Engine (ONNX / Gemma 3 Nano)',
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

/// On-device neural translation engine using offline-native models and ONNX LLM.
class MlKitTranslationEngine {
  MlKitTranslationEngine._();
  static final MlKitTranslationEngine instance = MlKitTranslationEngine._();

  final OnnxLocalLlmEngine _onnxEngine = OnnxLocalLlmEngine.instance;

  /// Underlying Local LLM Engine (ONNX / Gemma 3 Nano).
  OnnxLocalLlmEngine get onnxEngine => _onnxEngine;

  /// Description of the offline local model weights.
  static const String localLlmDescription =
      'Local LLM Engine (ONNX / Gemma 3 Nano)';

  /// Checks if the local LLM ONNX model or mock inference is ready.
  bool get isLocalLlmReady => _onnxEngine.isReady;

  /// The 5 manga translation languages required for all source and target pairs.
  static const List<MangaLanguage> allMangaLanguages = MangaLanguage.values;

  /// Reactive notifier for model download progress and statuses.
  final ValueNotifier<TranslationDownloadProgress> downloadProgressNotifier =
      ValueNotifier<TranslationDownloadProgress>(const TranslationDownloadProgress());

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
  /// In the Offline Local LLM architecture, all models are on-device and ready out of the box.
  Future<AllModelsStatus> checkAllModelsStatus() async {
    return const AllModelsStatus(
      missingLanguages: [],
      downloadedLanguages: allMangaLanguages,
      totalNeededMb: 0.0,
      isReady: true,
      modelDescription: localLlmDescription,
    );
  }

  /// Gets the pair download status. In the Offline Local LLM architecture,
  /// models run on-device without requiring remote Google Play Services downloads.
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
      isReady: true,
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
    return downloadPairWithProgress(source, target, isWifiRequired: isWifiRequired);
  }

  Future<bool> _downloadModelWithPolling({
    required MangaLanguage lang,
    required double stepBaseMb,
    required double stepTotalMb,
    required double overallTotalMb,
    required String stepName,
    bool isWifiRequired = false,
  }) async {
    downloadProgressNotifier.value = TranslationDownloadProgress(
      isDownloading: true,
      currentStep: stepName,
      downloadedMb: stepBaseMb,
      totalMb: overallTotalMb,
      progress: (stepBaseMb / overallTotalMb).clamp(0.0, 1.0),
    );

    final completer = Completer<bool>();
    final stopwatch = Stopwatch()..start();

    final progressTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (completer.isCompleted) {
        t.cancel();
        return;
      }
      final elapsedMs = stopwatch.elapsedMilliseconds;
      double stepFraction;
      if (elapsedMs <= 25000) {
        stepFraction = (elapsedMs / 25000.0) * 0.95;
      } else {
        final creepProgress = ((elapsedMs - 25000) / 275000.0).clamp(0.0, 1.0);
        stepFraction = 0.95 + (0.04 * creepProgress);
      }
      stepFraction = stepFraction.clamp(0.0, 0.99);

      final currentMb = stepBaseMb + (stepTotalMb * stepFraction);
      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: true,
        currentStep: stepName,
        downloadedMb: double.parse(currentMb.toStringAsFixed(1)),
        totalMb: overallTotalMb,
        progress: (currentMb / overallTotalMb).clamp(0.0, 1.0),
      );
    });

    final pollTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (completer.isCompleted) {
        t.cancel();
        return;
      }
      try {
        final isDownloaded = await isLanguageDownloaded(lang);
        if (isDownloaded && !completer.isCompleted) {
          completer.complete(true);
        }
      } catch (_) {}
    });

    final timeoutTimer = Timer(const Duration(seconds: 300), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    downloadLanguage(lang, isWifiRequired: isWifiRequired)
        .then((success) {
          if (success && !completer.isCompleted) {
            completer.complete(true);
          }
        })
        .catchError((e) {
          debugPrint('Primary downloadLanguage error for ${lang.name}: $e');
        });

    final success = await completer.future;
    progressTimer.cancel();
    pollTimer.cancel();
    timeoutTimer.cancel();
    stopwatch.stop();

    if (success) {
      final completedMb = stepBaseMb + stepTotalMb;
      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: true,
        currentStep: stepName,
        downloadedMb: double.parse(completedMb.toStringAsFixed(1)),
        totalMb: overallTotalMb,
        progress: (completedMb / overallTotalMb).clamp(0.0, 1.0),
      );
      return true;
    } else {
      final finalCheck = await isLanguageDownloaded(lang);
      if (finalCheck) {
        final completedMb = stepBaseMb + stepTotalMb;
        downloadProgressNotifier.value = TranslationDownloadProgress(
          isDownloading: true,
          currentStep: stepName,
          downloadedMb: double.parse(completedMb.toStringAsFixed(1)),
          totalMb: overallTotalMb,
          progress: (completedMb / overallTotalMb).clamp(0.0, 1.0),
        );
        return true;
      }
      return false;
    }
  }

  /// Downloads all missing manga translation models sequentially (id, en, ja, ko, zh).
  Future<bool> downloadAllModelsWithProgress({
    bool isWifiRequired = false,
  }) async {
    try {
      final status = await checkAllModelsStatus();
      if (status.isReady) {
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

      final missing = status.missingLanguages;
      final totalMb = status.totalNeededMb;
      double currentDownloaded = 0.0;

      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: true,
        currentStep: 'Downloading model...',
        downloadedMb: 0.0,
        totalMb: totalMb,
        progress: 0.0,
      );

      for (final lang in missing) {
        final ok = await _downloadModelWithPolling(
          lang: lang,
          stepBaseMb: currentDownloaded,
          stepTotalMb: 30.0,
          overallTotalMb: totalMb,
          stepName: 'Downloading model...',
          isWifiRequired: isWifiRequired,
        );

        if (!ok) {
          downloadProgressNotifier.value = TranslationDownloadProgress(
            isDownloading: false,
            currentStep: 'Failed',
            downloadedMb: currentDownloaded,
            totalMb: totalMb,
            progress: (currentDownloaded / totalMb).clamp(0.0, 1.0),
            isSuccess: false,
            errorMessage: 'Failed to download ${lang.name} model',
          );
          return false;
        }

        currentDownloaded += 30.0;
      }

      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: false,
        currentStep: 'Ready',
        downloadedMb: totalMb,
        totalMb: totalMb,
        progress: 1.0,
        isSuccess: true,
      );
      return true;
    } catch (e) {
      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: false,
        currentStep: 'Error',
        downloadedMb: 0.0,
        totalMb: 0.0,
        progress: 0.0,
        isSuccess: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Downloads missing pair models with realistic smooth progress updates.
  Future<bool> downloadPairWithProgress(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target, {
    bool isWifiRequired = false,
  }) async {
    try {
      final status = await getPairStatus(source, target);
      if (status.isReady) {
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

      final totalMb = status.totalNeededMb;
      final targetLang = mapTargetLanguage(target);
      final effectiveSource = (source == TranslationSourceLanguage.auto)
          ? TranslationSourceLanguage.japanese
          : source;
      final sourceLang = mapSourceLanguage(effectiveSource);

      double currentDownloaded = 0.0;

      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: true,
        currentStep: 'Downloading model...',
        downloadedMb: 0.0,
        totalMb: totalMb,
        progress: 0.0,
      );

      if (!status.targetDownloaded) {
        final ok = await _downloadModelWithPolling(
          lang: targetLang,
          stepBaseMb: currentDownloaded,
          stepTotalMb: 30.0,
          overallTotalMb: totalMb,
          stepName: 'Downloading model...',
          isWifiRequired: isWifiRequired,
        );
        if (!ok) {
          downloadProgressNotifier.value = TranslationDownloadProgress(
            isDownloading: false,
            currentStep: 'Failed',
            downloadedMb: currentDownloaded,
            totalMb: totalMb,
            progress: (currentDownloaded / totalMb).clamp(0.0, 1.0),
            isSuccess: false,
            errorMessage: 'Failed to download ${status.targetLangName} model',
          );
          return false;
        }
        currentDownloaded += 30.0;
      }

      if (!status.sourceDownloaded) {
        final ok = await _downloadModelWithPolling(
          lang: sourceLang,
          stepBaseMb: currentDownloaded,
          stepTotalMb: 30.0,
          overallTotalMb: totalMb,
          stepName: 'Downloading model...',
          isWifiRequired: isWifiRequired,
        );
        if (!ok) {
          downloadProgressNotifier.value = TranslationDownloadProgress(
            isDownloading: false,
            currentStep: 'Failed',
            downloadedMb: currentDownloaded,
            totalMb: totalMb,
            progress: (currentDownloaded / totalMb).clamp(0.0, 1.0),
            isSuccess: false,
            errorMessage: 'Failed to download ${status.sourceLangName} model',
          );
          return false;
        }
        currentDownloaded += 30.0;
      }

      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: false,
        currentStep: 'Ready',
        downloadedMb: totalMb,
        totalMb: totalMb,
        progress: 1.0,
        isSuccess: true,
      );
      return true;
    } catch (e) {
      downloadProgressNotifier.value = TranslationDownloadProgress(
        isDownloading: false,
        currentStep: 'Error',
        downloadedMb: 0.0,
        totalMb: 0.0,
        progress: 0.0,
        isSuccess: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Translates [text] from [source] language to [target] language using
  /// the underlying Local LLM Engine (ONNX / Gemma 3 Nano).
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
      final translated = await _onnxEngine.translateMangaText(
        text: cleaned,
        source: effectiveSource,
        target: target,
      );
      if (translated.isNotEmpty) {
        return translated;
      }
    } catch (e) {
      debugPrint('Local LLM ONNX translation error ($effectiveSource -> $target): $e');
    }

    return cleaned;
  }

  /// Closes active [OnnxLocalLlmEngine] instance.
  Future<void> dispose() async {
    _onnxEngine.dispose();
  }
}
