// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/settings_model.dart';
import '../settings_service.dart';
import 'translation_models.dart';

/// Connection test result from an OpenAI-compatible Local AI / LM Studio server.
class LmStudioConnectionResult {
  final bool isSuccess;
  final String message;
  final List<String> availableModels;

  const LmStudioConnectionResult({
    required this.isSuccess,
    required this.message,
    this.availableModels = const [],
  });
}

/// Delegate type for mock or custom LLM inference in tests and headless environments.
typedef LlmInferenceHandler = Future<String> Function(
  String prompt, {
  required double temperature,
  required int maxTokens,
});

/// Delegate type for mock connection testing in unit tests.
typedef LmStudioConnectionHandler = Future<LmStudioConnectionResult> Function(
  String baseUrl,
  String? apiKey,
);

/// Local AI Translation Engine communicating via OpenAI-compatible REST API
/// (LM Studio, Ollama, vLLM, LocalAI) using standard library `dart:io` `HttpClient`.
class LmStudioTranslationEngine {
  LmStudioTranslationEngine({
    this.mockInferenceHandler,
    this.mockTestConnectionHandler,
  });

  static final LmStudioTranslationEngine instance = LmStudioTranslationEngine();

  /// System prompt template conforming strictly to the AGENTS.md Prompting Policy.
  static const String systemPromptTemplate =
      'You are an expert localizer for Asian comics. Translate the raw OCR text from {language} into natural English comic dialogue. \n'
      'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
      'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.';

  /// Default inference configuration parameters.
  static const double defaultTemperature = 0.1;
  static const int defaultMaxTokens = 80;

  /// Temperature constraints: locked at 0.1–0.2 to eliminate hallucination.
  static const double minTemperature = 0.1;
  static const double maxTemperature = 0.2;

  /// Max token constraints: limited to 50–80 tokens to conserve resources.
  static const int minTokens = 50;
  static const int maxTokensLimit = 80;

  /// Optional mock inference handler for unit testing and headless validation.
  LlmInferenceHandler? mockInferenceHandler;

  /// Optional mock connection test handler for unit testing.
  LmStudioConnectionHandler? mockTestConnectionHandler;

  String? lastStatusMessage;

  bool get isReady => true;

  static double constrainTemperature(double temperature) {
    return temperature.clamp(minTemperature, maxTemperature);
  }

  static int constrainMaxTokens(int maxTokens) {
    return maxTokens.clamp(minTokens, maxTokensLimit);
  }

  /// Normalizes base URL ensuring no trailing slash and standardizing `/v1`.
  static String normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.isEmpty) return 'http://192.168.1.2:1234/v1';
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.endsWith('/v1')) {
      trimmed = '$trimmed/v1';
    }
    return trimmed;
  }

  /// Tests connection to the OpenAI-compatible server via `GET /v1/models`.
  Future<LmStudioConnectionResult> testConnection({
    String? baseUrl,
    String? apiKey,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final effectiveUrl = baseUrl ??
        (SettingsService.hasInstance
            ? SettingsService.instance.settings.lmStudioServerUrl
            : 'http://192.168.1.2:1234/v1');
    final effectiveKey = apiKey ??
        (SettingsService.hasInstance
            ? SettingsService.instance.settings.lmStudioApiKey
            : '');

    if (mockTestConnectionHandler != null) {
      return await mockTestConnectionHandler!(effectiveUrl, effectiveKey);
    }

    final normalized = normalizeBaseUrl(effectiveUrl);
    final endpoint = Uri.parse('$normalized/models');

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.getUrl(endpoint).timeout(timeout);
      request.headers.set('Accept', 'application/json');
      if (effectiveKey.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${effectiveKey.trim()}');
      }

      final response = await request.close().timeout(timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final List<String> models = [];
        try {
          final json = jsonDecode(responseBody) as Map<String, dynamic>;
          final data = json['data'] as List?;
          if (data != null) {
            for (final item in data) {
              if (item is Map && item['id'] != null) {
                models.add(item['id'].toString());
              }
            }
          }
        } catch (_) {}

        lastStatusMessage = 'Connected (${models.length} models)';
        return LmStudioConnectionResult(
          isSuccess: true,
          message: 'Connected successfully (${response.statusCode})',
          availableModels: models,
        );
      } else {
        lastStatusMessage = 'Error: HTTP ${response.statusCode}';
        return LmStudioConnectionResult(
          isSuccess: false,
          message: 'Server returned HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      lastStatusMessage = 'Connection failed: $e';
      return LmStudioConnectionResult(
        isSuccess: false,
        message: 'Could not connect to server: $e',
      );
    } finally {
      client.close();
    }
  }

  /// Builds system prompt text for a specific source language.
  static String buildSystemPrompt(String language) {
    return 'You are an expert localizer for Asian comics. Translate the raw OCR text from $language into natural English comic dialogue. \n'
        'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
        'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.';
  }

  /// Builds prompt payload for testing/legacy parity.
  static String buildPrompt({
    String? language,
    required String rawOcrText,
  }) {
    final lang = language ?? 'Japanese';
    return '<system>\n'
        '${buildSystemPrompt(lang)}\n'
        '</system>\n'
        '<user>\n'
        '$rawOcrText\n'
        '</user>';
  }

  static final RegExp _cjkRegex = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\uFF65-\uFF9F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]',
  );

  /// Returns true if [text] contains CJK characters.
  static bool hasCjkCharacters(String text) {
    if (text.isEmpty) return false;
    return _cjkRegex.hasMatch(text);
  }

  static final RegExp _translatableDialogueRegex = RegExp(
    r'[\u4e00-\u9fff\u3400-\u4dbf\u3041-\u3096\u30a1-\u30fa\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]',
  );

  /// Returns true if [text] contains real Asian dialogue characters.
  static bool hasTranslatableDialogue(String text) {
    if (text.isEmpty) return false;
    return _translatableDialogueRegex.hasMatch(text);
  }

  static String resolveLanguageName(
    TranslationSourceLanguage source, [
    String? sampleText,
  ]) {
    switch (source) {
      case TranslationSourceLanguage.japanese:
        return 'Japanese';
      case TranslationSourceLanguage.korean:
        return 'Korean';
      case TranslationSourceLanguage.chinese:
        return 'Chinese';
      case TranslationSourceLanguage.auto:
        if (sampleText != null && sampleText.isNotEmpty) {
          final detected = detectSourceLanguage(sampleText);
          return resolveLanguageName(detected);
        }
        return 'Japanese';
    }
  }

  static TranslationSourceLanguage detectSourceLanguage(String text) {
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

  /// Cleans raw LLM output into clean comic dialogue.
  static String cleanLlmOutput(String rawOutput) {
    if (rawOutput.isEmpty) return '';

    String text = rawOutput;

    // 1. Strip leading turn markers if present.
    text = text.replaceFirst(
      RegExp(
        r'^\s*(?:<\|im_start\|>\s*assistant|<start_of_turn>\s*model|<\|start_header_id\|>\s*assistant\s*<\|end_header_id\|>\n*|assistant:\s*)\n?',
        caseSensitive: false,
      ),
      '',
    );

    // 2. Immediately truncate at the first occurrence of stop markers.
    final stopRegex = RegExp(
      r'(?:<\|im_end\|>|<\|endoftext\|>|<\|eot_id\|>|<\|end_of_text\|>|<\|im_start\|>|<end_of_turn>|<start_of_turn>|<eos>|</s>|\nUser:|\nAssistant:|\nHuman:|\nSystem:|\n<\|user\|>|\n<\|system\|>|<\|start_header_id\|>)',
      caseSensitive: false,
    );
    final stopMatch = stopRegex.firstMatch(text);
    if (stopMatch != null) {
      text = text.substring(0, stopMatch.start);
    }

    // 3. Strip reasoning / think tags.
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*$', caseSensitive: false),
      '',
    );

    // 4. Strip prompt tags.
    text = text.replaceAll(
      RegExp(r'<system>[\s\S]*?</system>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<user>[\s\S]*?</user>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'</?(?:system|user|assistant|think)>', caseSensitive: false),
      '',
    );

    // Strip operational rules or prompt echoes.
    text = text.replaceAll(
      RegExp(r'CRITICAL OPERATIONAL RULES:?', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'(?:On the other hand,\s*)?You are an expert localizer for Asian comics[^\n]*\n?',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'This is fictional comic dialogue[^\n]*\n?',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Preserve the original tone, slang, and profanity[^\n]*\n?',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Output ONLY the final English translation[^\n]*\n?',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Fix OCR typos[^\n]*\n?',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Translate the raw OCR text from[^\n]*\n?',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'(?:On the other hand,\s*)?(?:you are|you\x27re)\s+(?:an?\s+)?(?:expert\s+)?(?:localizer|translator)[^\n.]*[\n.]?\s*',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'^\s*[0-9]+\.\s+[^\n]*\n?',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );

    // 5. Strip code fences (```...```).
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*\n?|```'), '');

    // 6. Strip blockquotes.
    text = text.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');

    // 7. Strip markdown headings.
    text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');

    // 8. Strip markdown bold, italics, code.
    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    text = text.replaceAll(RegExp(r'[*`_]'), '');

    // 9. Strip chat preambles.
    text = text.replaceAll(
      RegExp(
        r'^\s*(?:I(?:\x27m| am)\s+(?:going\s+to\s+)?|I\s+will\s+|Let\s+me\s+)(?:translate|convert|localize)\s+[^\n.:]*[.:]\s*(?:(?:Here(?:\x27s| is)\s+(?:the\s+)?(?:English\s+)?(?:comic\s+)?(?:dialogue|translation)\s*:\s*)?)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'^\s*Here(?:\x27s| is)\s+(?:the\s+)?(?:English\s+)?(?:comic\s+)?(?:dialogue|translation)\s*:\s*',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'^\s*(?:sure(?: thing)?[!,.]?\s*)?(?:(?:here\s+(?:is|are)\s+)?the\s+(?:final\s+)?(?:english\s+)?(?:comic\s+)?(?:dialogue|translation)\s*(?:is)?\s*:|the\s+translation\s+is\s*:|the\s+english\s+translation\s+is\s*:|english\s+translation\s*:|translation\s*to\s*english\s*:|natural\s+english\s*:|translated\s+text\s*:|based\s+on\s+the\s+comic\s+dialogue\s*,?\s*:?|translation\s*:|dialogue\s*:|output\s*:)\s*',
        caseSensitive: false,
      ),
      '',
    );

    // 10. Multi-paragraph handling.
    if (text.contains('\n\n')) {
      final paragraphs = text
          .split(RegExp(r'\n\s*\n+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final filtered = paragraphs.where((p) {
        final lower = p.toLowerCase();
        if (lower.startsWith('note:') ||
            lower.startsWith('explanation:') ||
            lower.startsWith('here is') ||
            lower.startsWith('sure') ||
            lower.startsWith('based on') ||
            lower.contains('expert localizer') ||
            lower.contains('comic dialogue')) {
          return false;
        }
        return true;
      }).toList();

      if (filtered.isNotEmpty) {
        text = filtered.first;
      } else if (paragraphs.isNotEmpty) {
        text = paragraphs.first;
      }
    }

    // 11. Strip surrounding quotes.
    text = text.trim();
    if ((text.startsWith('"') && text.endsWith('"') && text.length >= 2) ||
        (text.startsWith("'") && text.endsWith("'") && text.length >= 2) ||
        (text.startsWith('“') && text.endsWith('”') && text.length >= 2) ||
        (text.startsWith('「') && text.endsWith('」') && text.length >= 2)) {
      text = text.substring(1, text.length - 1).trim();
    }

    // 12. Reject readiness and waiting-for-input hallucinations.
    final lowerCleaned = text.toLowerCase();
    if (lowerCleaned.contains("i'm ready") ||
        lowerCleaned.contains("i’m ready") ||
        lowerCleaned.contains("i am ready") ||
        lowerCleaned.contains("ready to translate") ||
        lowerCleaned.contains("please send") ||
        lowerCleaned.contains("please provide") ||
        lowerCleaned.contains("send me the") ||
        lowerCleaned.contains("send the ocr") ||
        lowerCleaned.contains("waiting for the") ||
        lowerCleaned.contains("ready for the ocr")) {
      return '';
    }

    return text;
  }

  /// Translates manga text via OpenAI-compatible endpoint or mock handler.
  Future<String> translateMangaText({
    required String text,
    required TranslationSourceLanguage source,
    TranslationTargetLanguage target = TranslationTargetLanguage.english,
    double temperature = defaultTemperature,
    int maxTokens = defaultMaxTokens,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return '';

    if (RegExp(r'^[!?！？\.\s…]+$').hasMatch(cleaned)) {
      return cleaned;
    }

    if (!hasTranslatableDialogue(cleaned)) {
      return cleaned;
    }

    final effectiveTemperature = constrainTemperature(temperature);
    final effectiveMaxTokens = constrainMaxTokens(maxTokens);
    final cjkCount = cleaned.runes
        .where((r) => hasCjkCharacters(String.fromCharCode(r)))
        .length;
    final int targetTokens =
        (cjkCount * 2 + 16).clamp(16, effectiveMaxTokens);
    final languageName = resolveLanguageName(source, cleaned);

    // 1. Mock inference handler routing (tests and headless environments)
    if (mockInferenceHandler != null) {
      final constitutionalPrompt = buildPrompt(
        language: languageName,
        rawOcrText: cleaned,
      );
      final rawResult = await mockInferenceHandler!(
        constitutionalPrompt,
        temperature: effectiveTemperature,
        maxTokens: targetTokens,
      );
      final cleanedResult = cleanLlmOutput(rawResult);
      return cleanedResult.isNotEmpty ? cleanedResult : cleaned;
    }

    // 2. Real OpenAI-compatible REST API request
    final settings = SettingsService.hasInstance
        ? SettingsService.instance.settings
        : const SettingsModel();

    final serverUrl = settings.lmStudioServerUrl;
    final apiKey = settings.lmStudioApiKey;
    final model = settings.lmStudioModel.isNotEmpty
        ? settings.lmStudioModel
        : 'default';

    final normalized = normalizeBaseUrl(serverUrl);
    final endpoint = Uri.parse('$normalized/chat/completions');

    final payload = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': buildSystemPrompt(languageName),
        },
        {
          'role': 'user',
          'content': cleaned,
        }
      ],
      'temperature': effectiveTemperature,
      'max_tokens': targetTokens,
      'stream': false,
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client.postUrl(endpoint).timeout(
            const Duration(seconds: 15),
          );
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      if (apiKey.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${apiKey.trim()}');
      }

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.add(bodyBytes);

      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices[0] as Map<String, dynamic>;
          final message = firstChoice['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String? ?? '';
          final cleanedOutput = cleanLlmOutput(content);
          if (cleanedOutput.isNotEmpty) {
            lastStatusMessage = 'OK: $model';
            return cleanedOutput;
          }
        }
      } else {
        lastStatusMessage = 'Server error HTTP ${response.statusCode}';
      }
    } catch (e) {
      lastStatusMessage = 'Inference error: $e';
      debugPrint('[LmStudioTranslationEngine] HTTP error: $e');
    } finally {
      client.close();
    }

    return cleaned;
  }

  Future<void> dispose() async {
    lastStatusMessage = null;
  }
}

