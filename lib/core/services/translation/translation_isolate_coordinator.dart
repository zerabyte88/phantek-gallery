// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'manga_ocr_service.dart';
import 'onnx_translation_engine.dart';
import 'translation_models.dart';

Future<List<MangaTranslatedBlock>> _translateBlocksInWorker(
  List<RawMangaTextBlock> rawBlocks,
  Size imageSize,
) async {
  final List<MangaTranslatedBlock> results = [];
  final engine = OnnxTranslationEngine.instance;

  for (final raw in rawBlocks) {
    final isBubble = MangaOcrService.classifyIsSpeechBubble(
      raw.boundingBox,
      raw.text,
      imageSize,
    );
    final translated = await engine.translate(raw.text);

    results.add(MangaTranslatedBlock(
      boundingBox: raw.boundingBox,
      originalText: raw.text,
      translatedText: translated,
      isSpeechBubble: isBubble,
    ));
  }
  return results;
}

/// Orchestrates OCR and ONNX model inference with a strict 1000ms idle-debounce timer,
/// result caching, and background isolate dispatch to protect UI 60fps scrolling.
class TranslationIsolateCoordinator {
  final MangaOcrService _ocrService;
  final OnnxTranslationEngine _translationEngine;

  TranslationIsolateCoordinator({
    MangaOcrService? ocrService,
    OnnxTranslationEngine? translationEngine,
  })  : _ocrService = ocrService ?? MangaOcrService(),
        _translationEngine = translationEngine ?? OnnxTranslationEngine.instance;

  Timer? _debounceTimer;
  int _activeSequence = 0;

  final Map<String, TranslationResult> _cache = {};
  final Map<String, ValueNotifier<TranslationResult?>> _resultNotifiers = {};
  final Map<String, ValueNotifier<bool>> _loadingNotifiers = {};

  ValueNotifier<TranslationResult?> getResultNotifier(String imagePath) {
    return _resultNotifiers.putIfAbsent(
      imagePath,
      () => ValueNotifier<TranslationResult?>(_cache[imagePath]),
    );
  }

  ValueNotifier<bool> getLoadingNotifier(String imagePath) {
    return _loadingNotifiers.putIfAbsent(
      imagePath,
      () => ValueNotifier<bool>(false),
    );
  }

  /// Schedules translation for the page at [imagePath].
  ///
  /// Resets the 1.000 ms debounce timer on every call so translation only initiates
  /// once scrolling has settled completely.
  void scheduleTranslation({
    required String imagePath,
    required Size imageSize,
    required TranslationRenderMode mode,
    Duration debounceDuration = const Duration(milliseconds: 1000),
  }) {
    _debounceTimer?.cancel();

    final cached = _cache[imagePath];
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
        sequence: seq,
      );
    });
  }

  Future<void> _executeTranslation({
    required String imagePath,
    required Size imageSize,
    required TranslationRenderMode mode,
    required int sequence,
  }) async {
    if (sequence != _activeSequence) return;

    final loadingNotifier = getLoadingNotifier(imagePath);
    final resultNotifier = getResultNotifier(imagePath);

    loadingNotifier.value = true;

    try {
      final rawBlocks = await _ocrService.extractTextBlocks(imagePath);
      if (sequence != _activeSequence) return;

      if (rawBlocks.isEmpty) {
        final emptyResult = TranslationResult(
          imagePath: imagePath,
          blocks: const [],
          imageSize: imageSize,
          isSuccess: true,
        );
        _cache[imagePath] = emptyResult;
        resultNotifier.value = emptyResult;
        return;
      }

      final translatedBlocks = await compute(
        (data) => _translateBlocksInWorker(data.$1, data.$2),
        (rawBlocks, imageSize),
      );

      if (sequence != _activeSequence) return;

      final result = TranslationResult(
        imagePath: imagePath,
        blocks: translatedBlocks,
        imageSize: imageSize,
        isSuccess: true,
      );

      _cache[imagePath] = result;
      resultNotifier.value = result;
    } catch (e) {
      if (sequence == _activeSequence) {
        final failResult = TranslationResult.failure(
          imagePath: imagePath,
          errorMessage: e.toString(),
          imageSize: imageSize,
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
