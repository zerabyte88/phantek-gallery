// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/foundation.dart';
import 'lm_studio_translation_engine.dart';
import 'translation_models.dart';

/// Delegates manga dialogue translation to the local AI server.
class MlKitTranslationEngine {
  MlKitTranslationEngine._();
  static final MlKitTranslationEngine instance = MlKitTranslationEngine._();

  final LmStudioTranslationEngine _lmStudioEngine =
      LmStudioTranslationEngine.instance;

  LmStudioTranslationEngine get lmStudioEngine => _lmStudioEngine;

  String? get lastStatusMessage => _lmStudioEngine.lastStatusMessage;

  /// Detects source language from Unicode character ranges.
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

  /// Normalizes line breaks, removes border artifacts, and merges intra-CJK spaces.
  static String cleanMangaText(String text) {
    final cleaned = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'(?:^|\n)\s*[|丨¦‖]\s*(?=\n|$)'), '\n')
        // Vertical OCR misreads katakana long-vowel marks and 一 (e.g. 一旦) as a pipe.
        .replaceAll(RegExp(r'(?<=[\u30a0-\u30ff])\s*[|丨¦‖]'), 'ー')
        .replaceAll(RegExp(r'[|丨¦‖]\s*(?=[\u3040-\u30ff\u4e00-\u9fff])'), '一');

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

  Future<void> dispose() async {
    await _lmStudioEngine.dispose();
  }
}
