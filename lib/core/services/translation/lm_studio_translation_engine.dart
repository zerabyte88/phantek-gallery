// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/settings_model.dart';
import '../settings_service.dart';
import 'translation_models.dart';

/// Connection test result from an OpenAI-compatible server.
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

/// Delegate for mock or custom LLM inference.
typedef LlmInferenceHandler = Future<String> Function(
  String prompt, {
  required double temperature,
  required int maxTokens,
});

/// Delegate for mock connection testing.
typedef LmStudioConnectionHandler = Future<LmStudioConnectionResult> Function(
  String baseUrl,
  String? apiKey,
);

/// Local AI translation engine via OpenAI-compatible REST API.
class LmStudioTranslationEngine {
  LmStudioTranslationEngine({
    this.mockInferenceHandler,
    this.mockTestConnectionHandler,
  });

  static final LmStudioTranslationEngine instance = LmStudioTranslationEngine();

  /// Prompt template matching AGENTS.md policy.
  static const String systemPromptTemplate = '''
Role: Automated OCR-to-English Literary Localization Engine.
Task: Convert raw {language} comic script into natural English dialogue.
Context: Fictional graphic novel dialogue. Source text is user-provided input requiring verbatim semantic equivalence, including slang, harsh register, and explicit language.

Rules:
1. Reconstruct broken OCR characters based on context.
2. Maintain exact emotional intensity and vulgarity without softening or omitting meaning.
3. Output strictly the final English translation. No chat, warnings, or markdown.
''';

  static const double defaultTemperature = 0.1;
  static const int defaultMaxTokens = 80;

  // Locked at 0.1–0.2 to prevent hallucination.
  static const double minTemperature = 0.1;
  static const double maxTemperature = 0.2;

  // Capped at 50–80 tokens to bound latency and bandwidth.
  static const int minTokens = 50;
  static const int maxTokensLimit = 80;

  LlmInferenceHandler? mockInferenceHandler;

  LmStudioConnectionHandler? mockTestConnectionHandler;

  String? lastStatusMessage;

  bool get isReady => true;

  static double constrainTemperature(double temperature) {
    return temperature.clamp(minTemperature, maxTemperature);
  }

  static int constrainMaxTokens(int maxTokens) {
    return maxTokens.clamp(minTokens, maxTokensLimit);
  }

  /// Strips trailing slashes and ensures a `/v1` suffix.
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

  /// Probes server connectivity via `GET /v1/models`.
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

  static String buildSystemPrompt(String language) {
    return 'You are an expert localizer for Asian comics. Translate the raw OCR text from $language into natural English comic dialogue. \n'
        'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
        'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.';
  }

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

  static bool hasCjkCharacters(String text) {
    if (text.isEmpty) return false;
    return _cjkRegex.hasMatch(text);
  }

  static final RegExp _translatableDialogueRegex = RegExp(
    r'[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff\u3400-\u4dbf\uac00-\ud7af\u1100-\u11ff\u3130-\u318f\u3005\u309d\u309e\u30fd\u30fe\uff66-\uff9f\uf900-\ufaff]',
  );

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

  /// Strips LLM wrappers, prompt echoes, markdown, and hallucinations from raw output.
  static String cleanLlmOutput(String rawOutput) {
    if (rawOutput.isEmpty) return '';

    String text = rawOutput;

    text = text.replaceFirst(
      RegExp(
        r'^\s*(?:<\|im_start\|>\s*assistant|<start_of_turn>\s*model|<\|start_header_id\|>\s*assistant\s*<\|end_header_id\|>\n*|assistant:\s*)\n?',
        caseSensitive: false,
      ),
      '',
    );

    final stopRegex = RegExp(
      r'(?:<\|im_end\|>|<\|endoftext\|>|<\|eot_id\|>|<\|end_of_text\|>|<\|im_start\|>|<end_of_turn>|<start_of_turn>|<eos>|</s>|\nUser:|\nAssistant:|\nHuman:|\nSystem:|\n<\|user\|>|\n<\|system\|>|<\|start_header_id\|>)',
      caseSensitive: false,
    );
    final stopMatch = stopRegex.firstMatch(text);
    if (stopMatch != null) {
      text = text.substring(0, stopMatch.start);
    }

    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*$', caseSensitive: false),
      '',
    );

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

    text = text.replaceAll(RegExp(r'```[a-zA-Z]*\n?|```'), '');

    text = text.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');

    text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');

    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    text = text.replaceAll(RegExp(r'[*`_]'), '');

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

    final latinRegex = RegExp(r'[A-Za-z]');
    bool isPreambleSegment(String segment) {
      final lower = segment.toLowerCase();
      return lower.startsWith('note:') ||
          lower.startsWith('explanation:') ||
          lower.startsWith('here is') ||
          lower.startsWith('sure') ||
          lower.startsWith('based on') ||
          lower.contains('expert localizer') ||
          lower.contains('comic dialogue');
    }

    List<String> filterSegments(List<String> segments) {
      final nonPreamble = segments.where((s) => !isPreambleSegment(s)).toList();
      final pool = nonPreamble.isNotEmpty ? nonPreamble : segments;
      if (pool.any(latinRegex.hasMatch)) {
        return pool.where(latinRegex.hasMatch).toList();
      }
      return pool;
    }

    if (text.contains(RegExp(r'\n\s*\n+'))) {
      final paragraphs = text
          .split(RegExp(r'\n\s*\n+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final filtered = filterSegments(paragraphs);
      if (filtered.isNotEmpty) {
        text = filtered.first;
      } else if (paragraphs.isNotEmpty) {
        text = paragraphs.first;
      }
    }

    if (text.contains('\n')) {
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length > 1) {
        final filteredLines = filterSegments(lines);
        if (filteredLines.isNotEmpty) {
          text = filteredLines.join('\n');
        }
      }
    }

    String stripOuterQuotes(String s) {
      var out = s.trim();
      if ((out.startsWith('"') && out.endsWith('"') && out.length >= 2) ||
          (out.startsWith("'") && out.endsWith("'") && out.length >= 2) ||
          (out.startsWith('“') && out.endsWith('”') && out.length >= 2) ||
          (out.startsWith('「') && out.endsWith('」') && out.length >= 2)) {
        out = out.substring(1, out.length - 1).trim();
      }
      return out;
    }

    text = stripOuterQuotes(text);
    text = text.replaceFirst(
      RegExp(
          r'^[\u3000-\u9fff\uac00-\ud7af\uff00-\uffef\s]+(?:->|→|:|：|-|—)\s*(?=[A-Za-z])'),
      '',
    );
    text = text.replaceFirst(
      RegExp(r'\s*[\(（][\u3000-\u9fff\uac00-\ud7af\uff00-\uffef\s]+[\)）]\s*$'),
      '',
    );
    text = stripOuterQuotes(text);

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

  /// Translates [text] via OpenAI-compatible endpoint or mock handler.
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
    final int targetTokens = (cjkCount * 2 + 16).clamp(16, effectiveMaxTokens);
    final languageName = resolveLanguageName(source, cleaned);

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

    final settings = SettingsService.hasInstance
        ? SettingsService.instance.settings
        : const SettingsModel();

    final serverUrl = settings.lmStudioServerUrl;
    final apiKey = settings.lmStudioApiKey;
    final model =
        settings.lmStudioModel.isNotEmpty ? settings.lmStudioModel : 'default';

    final normalized = normalizeBaseUrl(serverUrl);
    final endpoint = Uri.parse('$normalized/chat/completions');

    final firstOutput = await _sendChatCompletionRequest(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      languageName: languageName,
      rawText: cleaned,
      temperature: effectiveTemperature,
      maxTokens: effectiveMaxTokens,
    );

    if (firstOutput != null) {
      if (firstOutput.isNotEmpty && !hasTranslatableDialogue(firstOutput)) {
        return firstOutput;
      }
      final retryOutput = await _sendChatCompletionRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        languageName: languageName,
        rawText: cleaned,
        temperature: effectiveTemperature,
        maxTokens: 256,
      );
      if (retryOutput != null && retryOutput.isNotEmpty) {
        return retryOutput;
      }
      if (firstOutput.isNotEmpty) {
        return firstOutput;
      }
    }

    return cleaned;
  }

  Future<String?> _sendChatCompletionRequest({
    required Uri endpoint,
    required String apiKey,
    required String model,
    required String languageName,
    required String rawText,
    required double temperature,
    required int maxTokens,
  }) async {
    final payload = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': buildSystemPrompt(languageName),
        },
        {
          'role': 'user',
          'content': rawText,
        }
      ],
      'temperature': temperature,
      'max_tokens': maxTokens,
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
          lastStatusMessage = 'OK: $model';
          return cleanLlmOutput(content);
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

    return null;
  }

  Future<void> dispose() async {
    lastStatusMessage = null;
  }
}
