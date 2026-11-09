// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'translation_models.dart';

/// Status model for language pair readiness and download footprint.
class ModelPairStatus {
  final bool sourceDownloaded;
  final bool targetDownloaded;
  final String sourceLangName;
  final String targetLangName;
  final double totalNeededMb; // 0.0, 30.0, or 60.0
  final bool isReady;

  const ModelPairStatus({
    required this.sourceDownloaded,
    required this.targetDownloaded,
    required this.sourceLangName,
    required this.targetLangName,
    required this.totalNeededMb,
    required this.isReady,
  });
}

/// Progress state model for live translation model downloads.
class TranslationDownloadProgress {
  final bool isDownloading;
  final String currentStep;
  final double downloadedMb;
  final double totalMb;
  final double progress; // 0.0 to 1.0
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

/// On-device neural translation engine using Google ML Kit.
class MlKitTranslationEngine {
  MlKitTranslationEngine._();
  static final MlKitTranslationEngine instance = MlKitTranslationEngine._();

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

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

  /// Gets the pair download status, calculating required download size (~30MB/model).
  Future<ModelPairStatus> getPairStatus(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target,
  ) async {
    final targetLang = mapTargetLanguage(target);
    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? TranslationSourceLanguage.japanese
        : source;
    final sourceLang = mapSourceLanguage(effectiveSource);

    final targetDownloaded = await isLanguageDownloaded(targetLang);
    final sourceDownloaded = await isLanguageDownloaded(sourceLang);

    final totalNeededMb = (!sourceDownloaded && !targetDownloaded)
        ? 60.0
        : (!sourceDownloaded || !targetDownloaded)
            ? 30.0
            : 0.0;

    return ModelPairStatus(
      sourceDownloaded: sourceDownloaded,
      targetDownloaded: targetDownloaded,
      sourceLangName: _getSourceLangName(effectiveSource),
      targetLangName: _getTargetLangName(target),
      totalNeededMb: totalNeededMb,
      isReady: sourceDownloaded && targetDownloaded,
    );
  }

  /// Checks if both source and target models are downloaded and ready.
  Future<bool> isPairReady(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target,
  ) async {
    final status = await getPairStatus(source, target);
    return status.isReady;
  }

  /// Downloads models for both source and target languages.
  Future<bool> downloadPair(
    TranslationSourceLanguage source,
    TranslationTargetLanguage target, {
    bool isWifiRequired = false,
  }) async {
    return downloadPairWithProgress(source, target, isWifiRequired: isWifiRequired);
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
        currentStep: !status.targetDownloaded
            ? 'Downloading ${status.targetLangName} Model...'
            : 'Downloading ${status.sourceLangName} Model...',
        downloadedMb: 0.0,
        totalMb: totalMb,
        progress: 0.0,
      );

      Future<bool> runStep(
        String stepName,
        TranslateLanguage lang,
        double stepBaseMb,
        double stepTotalMb,
      ) async {
        downloadProgressNotifier.value = TranslationDownloadProgress(
          isDownloading: true,
          currentStep: stepName,
          downloadedMb: stepBaseMb,
          totalMb: totalMb,
          progress: (stepBaseMb / totalMb).clamp(0.0, 1.0),
        );

        double stepFraction = 0.0;
        final timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
          if (stepFraction < 0.90) {
            stepFraction += 0.03;
            if (stepFraction > 0.90) stepFraction = 0.90;
            final currentMb = stepBaseMb + (stepTotalMb * stepFraction);
            downloadProgressNotifier.value = TranslationDownloadProgress(
              isDownloading: true,
              currentStep: stepName,
              downloadedMb: double.parse(currentMb.toStringAsFixed(1)),
              totalMb: totalMb,
              progress: (currentMb / totalMb).clamp(0.0, 1.0),
            );
          }
        });

        bool success = false;
        try {
          success = await downloadLanguage(lang, isWifiRequired: isWifiRequired);
        } catch (e) {
          success = false;
        } finally {
          timer.cancel();
        }

        if (success) {
          final completedMb = stepBaseMb + stepTotalMb;
          downloadProgressNotifier.value = TranslationDownloadProgress(
            isDownloading: true,
            currentStep: stepName,
            downloadedMb: double.parse(completedMb.toStringAsFixed(1)),
            totalMb: totalMb,
            progress: (completedMb / totalMb).clamp(0.0, 1.0),
          );
        }
        return success;
      }

      if (!status.targetDownloaded) {
        final ok = await runStep(
          'Downloading ${status.targetLangName} Model...',
          targetLang,
          currentDownloaded,
          30.0,
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
        final ok = await runStep(
          'Downloading ${status.sourceLangName} Model...',
          sourceLang,
          currentDownloaded,
          30.0,
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

  /// Translates [text] from [source] language to [target] language.
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
