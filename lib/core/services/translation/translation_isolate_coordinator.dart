// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'manga_ocr_service.dart';
import 'mlkit_translation_engine.dart';
import 'gguf_local_llm_engine.dart';
import 'translation_models.dart';

Future<List<MangaTranslatedBlock>> _translateBlocks(
  List<RawMangaTextBlock> rawBlocks,
  Size imageSize,
  MlKitTranslationEngine engine, {
  TranslationRenderMode mode = TranslationRenderMode.fullImageWithSfx,
  TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  required TranslationTargetLanguage targetLanguage,
  bool Function()? isCancelled,
}) async {
  final List<MangaTranslatedBlock> results = [];

  // Page-level language detection when source is set to auto
  TranslationSourceLanguage effectiveLanguage = language;
  if (language == TranslationSourceLanguage.auto && rawBlocks.isNotEmpty) {
    final combinedText = rawBlocks.map((b) => b.text).join('\n');
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(combinedText)) {
      effectiveLanguage = TranslationSourceLanguage.japanese;
    } else if (RegExp(r'[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]')
        .hasMatch(combinedText)) {
      effectiveLanguage = TranslationSourceLanguage.korean;
    } else if (RegExp(r'[\u4e00-\u9fff]').hasMatch(combinedText)) {
      effectiveLanguage = TranslationSourceLanguage.chinese;
    } else {
      effectiveLanguage = TranslationSourceLanguage.japanese;
    }
  }

  // Pre-merge adjacent blocks belonging to the same speech bubble
  final mergedBlocks = MangaOcrService.mergeAdjacentBlocks(
    rawBlocks,
    language: effectiveLanguage,
  );

  for (final raw in mergedBlocks) {
    if (isCancelled != null && isCancelled()) break;

    final trimmed = raw.text.trim();
    if (trimmed.isEmpty ||
        !GgufLocalLlmEngine.hasTranslatableDialogue(trimmed) ||
        raw.boundingBox.width < 8 ||
        raw.boundingBox.height < 8) {
      continue;
    }

    final isBubble = MangaOcrService.classifyIsSpeechBubble(
      raw.boundingBox,
      raw.text,
      imageSize,
    );

    final String translated;
    if (mode == TranslationRenderMode.speechBubblesOnly && !isBubble) {
      translated = '';
    } else {
      translated = await engine.translateText(
        raw.text,
        source: effectiveLanguage,
        target: targetLanguage,
      );
    }

    if (isCancelled != null && isCancelled()) break;

    results.add(MangaTranslatedBlock(
      boundingBox: raw.boundingBox,
      originalText: raw.text,
      translatedText: translated,
      isSpeechBubble: isBubble,
    ));
  }
  return results;
}

/// Coordinates OCR, translation, debouncing, and result caching.
class TranslationIsolateCoordinator {
  final MangaOcrService _ocrService;
  final MlKitTranslationEngine _translationEngine;

  TranslationIsolateCoordinator({
    MangaOcrService? ocrService,
    MlKitTranslationEngine? translationEngine,
  })  : _ocrService = ocrService ?? MangaOcrService(),
        _translationEngine =
            translationEngine ?? MlKitTranslationEngine.instance;

  Timer? _debounceTimer;
  int _activeSequence = 0;

  final Map<String, TranslationResult> _cache = {};
  final Map<String, ValueNotifier<TranslationResult?>> _resultNotifiers = {};
  final Map<String, ValueNotifier<bool>> _loadingNotifiers = {};

  String _buildCacheKey({
    required String imagePath,
    required TranslationRenderMode mode,
    required TranslationSourceLanguage language,
    required TranslationTargetLanguage targetLanguage,
  }) {
    final model = _translationEngine.ggufEngine.activeModelPath ?? 'default';
    return '${imagePath}__${model}__${mode.name}__${language.name}__${targetLanguage.name}';
  }

  ValueNotifier<TranslationResult?> getResultNotifier(String imagePath) {
    return _resultNotifiers.putIfAbsent(
      imagePath,
      () => ValueNotifier<TranslationResult?>(null),
    );
  }

  ValueNotifier<bool> getLoadingNotifier(String imagePath) {
    return _loadingNotifiers.putIfAbsent(
      imagePath,
      () => ValueNotifier<bool>(false),
    );
  }

  /// Chains [MangaOcrService] extracted blocks directly into [translateText].
  Future<List<MangaTranslatedBlock>> translateBlocks(
    List<RawMangaTextBlock> rawBlocks,
    Size imageSize, {
    TranslationRenderMode mode = TranslationRenderMode.fullImageWithSfx,
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
    required TranslationTargetLanguage targetLanguage,
    bool Function()? isCancelled,
  }) async {
    return _translateBlocks(
      rawBlocks,
      imageSize,
      _translationEngine,
      mode: mode,
      language: language,
      targetLanguage: targetLanguage,
      isCancelled: isCancelled,
    );
  }

  /// Schedules translation with debouncing for [imagePath].
  void scheduleTranslation({
    required String imagePath,
    required Size imageSize,
    required TranslationRenderMode mode,
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
    required TranslationTargetLanguage targetLanguage,
    Duration debounceDuration = const Duration(milliseconds: 1000),
  }) {
    _debounceTimer?.cancel();

    final cacheKey = _buildCacheKey(
      imagePath: imagePath,
      mode: mode,
      language: language,
      targetLanguage: targetLanguage,
    );
    final cached = _cache[cacheKey];
    if (cached != null) {
      getResultNotifier(imagePath).value = cached;
      getLoadingNotifier(imagePath).value = false;
      return;
    }

    final seq = ++_activeSequence;
    _debounceTimer = Timer(debounceDuration, () {
      _executeTranslation(
        imagePath: imagePath,
        imageSize: imageSize,
        mode: mode,
        language: language,
        targetLanguage: targetLanguage,
        sequence: seq,
      );
    });
  }

  Future<void> _executeTranslation({
    required String imagePath,
    required Size imageSize,
    required TranslationRenderMode mode,
    required TranslationSourceLanguage language,
    required TranslationTargetLanguage targetLanguage,
    required int sequence,
  }) async {
    if (sequence != _activeSequence) return;

    final loadingNotifier = getLoadingNotifier(imagePath);
    final resultNotifier = getResultNotifier(imagePath);

    loadingNotifier.value = true;

    // Resolve accurate dimensions if missing or zero for coordinate scaling
    Size actualSize = imageSize;
    if (actualSize.width <= 0 || actualSize.height <= 0) {
      actualSize = await MangaOcrService.getImageDimensions(imagePath);
    }

    try {
      final rawBlocks = await _ocrService.extractTextBlocks(
        imagePath,
        language: language,
      );
      if (sequence != _activeSequence) return;

      if (rawBlocks.isEmpty) {
        final emptyResult = TranslationResult(
          imagePath: imagePath,
          blocks: const [],
          imageSize: actualSize,
          isSuccess: true,
        );
        final cacheKey = _buildCacheKey(
          imagePath: imagePath,
          mode: mode,
          language: language,
          targetLanguage: targetLanguage,
        );
        _cache[cacheKey] = emptyResult;
        resultNotifier.value = emptyResult;
        return;
      }

      final translatedBlocks = await translateBlocks(
        rawBlocks,
        actualSize,
        mode: mode,
        language: language,
        targetLanguage: targetLanguage,
        isCancelled: () => sequence != _activeSequence,
      );

      if (sequence != _activeSequence) return;

      final result = TranslationResult(
        imagePath: imagePath,
        blocks: translatedBlocks,
        imageSize: actualSize,
        isSuccess: true,
      );

      final cacheKey = _buildCacheKey(
        imagePath: imagePath,
        mode: mode,
        language: language,
        targetLanguage: targetLanguage,
      );
      _cache[cacheKey] = result;
      resultNotifier.value = result;
    } catch (e, stack) {
      debugPrint('Translation execution error on $imagePath: $e\n$stack');
      if (sequence == _activeSequence) {
        final failResult = TranslationResult.failure(
          imagePath: imagePath,
          errorMessage: e.toString(),
          imageSize: actualSize,
        );
        resultNotifier.value = failResult;
      }
    } finally {
      if (sequence == _activeSequence) {
        loadingNotifier.value = false;
      }
    }
  }

  void cancelPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _activeSequence++;
  }

  void clearCache() {
    _cache.clear();
    for (final notifier in _resultNotifiers.values) {
      notifier.value = null;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _ocrService.dispose();
    _translationEngine.dispose();
    for (final n in _resultNotifiers.values) {
      n.dispose();
    }
    for (final n in _loadingNotifiers.values) {
      n.dispose();
    }
    _resultNotifiers.clear();
    _loadingNotifiers.clear();
  }
}
