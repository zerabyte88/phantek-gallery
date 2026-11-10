// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_llama/flutter_llama.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../settings_service.dart';
import 'translation_models.dart';

/// Discovered GGUF model file metadata from local storage.
class DiscoveredAiModel {
  final String name;
  final String path;
  final double sizeMb;

  const DiscoveredAiModel({
    required this.name,
    required this.path,
    required this.sizeMb,
  });

  String get formattedSize => '${sizeMb.toStringAsFixed(1)} MB';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredAiModel &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// Delegate type for mock or custom LLM inference in tests and headless environments.
typedef LlmInferenceHandler = Future<String> Function(
  String prompt, {
  required double temperature,
  required int maxTokens,
});

/// Offline Local LLM Translation Engine using llama.cpp via flutter_llama.
///
/// Executes on-device inference using quantized local LLMs in GGUF format
/// (e.g. Qwen 2.5 / Gemma 2) with strict 100% offline boundaries, deterministic
/// low-temperature generation, and comic-dialogue output sanitization.
class GgufLocalLlmEngine {
  GgufLocalLlmEngine({
    this.mockInferenceHandler,
  });

  static final GgufLocalLlmEngine instance = GgufLocalLlmEngine();

  /// System prompt template conforming strictly to the AGENTS.md Prompting Policy.
  static const String systemPromptTemplate =
      'You are an expert localizer for Asian comics. Translate the raw OCR text from {language} into natural English comic dialogue. \n'
      'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
      'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.';

  /// Default inference configuration parameters.
  static const double defaultTemperature = 0.1;
  static const int defaultMaxTokens = 60;

  /// Temperature constraints: locked at 0.1–0.2 to eliminate hallucination.
  static const double minTemperature = 0.1;
  static const double maxTemperature = 0.2;

  /// Max token constraints: limited to 50–80 tokens to conserve RAM & battery.
  static const int minTokens = 50;
  static const int maxTokensLimit = 80;

  /// Optional mock inference handler for unit testing and headless validation.
  LlmInferenceHandler? mockInferenceHandler;

  /// Default directory path for local LLM models on Android storage.
  static const String defaultModelsDirectoryPath = '/storage/emulated/0/models';

  /// Default model file candidate names to search for in workspace/app paths.
  static const List<String> defaultModelCandidatePaths = [
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-abliterated.q4_k_m.gguf',
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    '/storage/emulated/0/models/qwen2.5-1.5b-instruct-abliterated.q4_k_m.gguf',
    '/storage/emulated/0/models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    '/storage/emulated/0/models/gemma-2-2b-it-q4_k_m.gguf',
    '/storage/emulated/0/models/model.gguf',
    'models/qwen2.5-0.5b-instruct-abliterated.q4_k_m.gguf',
    'models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    'models/qwen2.5-1.5b-instruct-abliterated.q4_k_m.gguf',
    'models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    'models/gemma-2-2b-it-q4_k_m.gguf',
    'models/model.gguf',
    'assets/models/qwen2.5-0.5b-instruct-abliterated.q4_k_m.gguf',
    'assets/models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    'assets/models/gemma-2-2b-it-q4_k_m.gguf',
  ];

  /// Default directories searched for local GGUF models.
  static const List<String> defaultScanDirectories = [
    '/storage/emulated/0/models/',
    '/storage/emulated/0/Download/models/',
    '/storage/emulated/0/Download/',
    'models/',
    'assets/models/',
  ];

  String? lastStatusMessage;
  bool _isInitializing = false;
  bool get isInitializing => _isInitializing;

  String? _activeModelPath;
  String? get activeModelPath => _activeModelPath;

  bool get isModelLoaded => FlutterLlama.instance.isModelLoaded;
  bool get isReady => isModelLoaded || mockInferenceHandler != null;

  /// Checks whether storage permission (MANAGE_EXTERNAL_STORAGE on Android) is granted.
  static Future<bool> isStoragePermissionGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await Permission.manageExternalStorage.isGranted;
    } catch (e) {
      debugPrint('isStoragePermissionGranted error: $e');
      return false;
    }
  }

  /// Requests storage permission (MANAGE_EXTERNAL_STORAGE on Android).
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('requestStoragePermission error: $e');
      return false;
    }
  }

  /// Discovers app-specific directories that might contain model weights.
  static Future<List<String>> getAppModelDirectories() async {
    final dirs = <String>[];
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        dirs.add(p.join(ext.path, 'models'));
      }
    } catch (e) {
      debugPrint('getExternalStorageDirectory error: $e');
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      dirs.add(p.join(docs.path, 'models'));
    } catch (e) {
      debugPrint('getApplicationDocumentsDirectory error: $e');
    }
    return dirs;
  }

  /// Ensures that the target or default models directory exists.
  static Future<void> ensureModelsDirectoryExists({String? targetPath}) async {
    try {
      final dir = Directory(targetPath ?? defaultModelsDirectoryPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('ensureModelsDirectoryExists error: $e');
    }
  }

  /// Scans default (or custom [searchDirectories]) paths for available `.gguf` models.
  static Future<List<DiscoveredAiModel>> scanAvailableModels({
    List<String>? searchDirectories,
  }) async {
    await ensureModelsDirectoryExists();
    final dirsToScan = <String>[];
    if (searchDirectories != null) {
      dirsToScan.addAll(searchDirectories);
    } else {
      dirsToScan.addAll(defaultScanDirectories);
      try {
        final appDirs = await getAppModelDirectories();
        dirsToScan.addAll(appDirs);
      } catch (e) {
        debugPrint('Error getting app model directories: $e');
      }
    }

    final models = <DiscoveredAiModel>[];
    final seenPaths = <String>{};

    for (final rawDirPath in dirsToScan) {
      try {
        final dir = Directory(rawDirPath);
        if (dir.existsSync()) {
          final entries = dir.listSync(recursive: false);
          for (final entry in entries) {
            if (entry is File && entry.path.toLowerCase().endsWith('.gguf')) {
              final normalized = entry.path.replaceAll(r'\', '/');
              if (seenPaths.add(normalized)) {
                final fileStat = entry.statSync();
                final sizeMb = fileStat.size / (1024 * 1024);
                final fileName = p.basename(entry.path);
                models.add(DiscoveredAiModel(
                  name: fileName,
                  path: entry.path,
                  sizeMb: double.parse(sizeMb.toStringAsFixed(2)),
                ));
              }
            }
          }
        }
      } on FileSystemException catch (e) {
        debugPrint('FileSystemException scanning $rawDirPath for models: $e');
      } catch (e) {
        debugPrint('Error scanning $rawDirPath for models: $e');
      }
    }

    return models;
  }

  static double constrainTemperature(double temperature) {
    return temperature.clamp(minTemperature, maxTemperature);
  }

  static int constrainMaxTokens(int maxTokens) {
    return maxTokens.clamp(minTokens, maxTokensLimit);
  }

  /// Builds the prompt payload strictly adhering to the AGENTS.md Prompting Policy.
  static String buildPrompt({
    String? language,
    required String rawOcrText,
  }) {
    final lang = language ?? 'Japanese';
    return '<system>\n'
        'You are an expert localizer for Asian comics. Translate the raw OCR text from $lang into natural English comic dialogue. \n'
        'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
        'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.\n'
        '</system>\n'
        '<user>\n'
        '$rawOcrText\n'
        '</user>';
  }

  /// Extracts `(language, userContent)` from a constitutional prompt payload.
  static ({String language, String userContent}) extractPromptParts(
    String prompt,
  ) {
    final langMatch = RegExp(
      r'from\s+(\w+)\s+into',
      caseSensitive: false,
    ).firstMatch(prompt);
    final userMatch = RegExp(
      r'<user>([\s\S]*?)</user>',
      caseSensitive: false,
    ).firstMatch(prompt);
    return (
      language: langMatch?.group(1)?.trim() ?? 'Japanese',
      userContent: userMatch?.group(1)?.trim() ?? prompt.trim(),
    );
  }

  /// Maps constitutional prompt to ChatML or Gemma formatted text based on [activeModelPath].
  static String formatForModel(String prompt, {String? activeModelPath}) {
    final parts = extractPromptParts(prompt);
    final modelName = activeModelPath?.toLowerCase() ?? '';

    if (modelName.contains('llama')) {
      return '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n'
          'You are an expert localizer for Asian comics. Translate the raw OCR text from ${parts.language} into natural English comic dialogue. \n'
          'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
          'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n'
          '${parts.userContent}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n';
    }

    if (modelName.contains('gemma')) {
      return '<start_of_turn>user\n'
          'You are an expert localizer for Asian comics. Translate the raw OCR text from ${parts.language} into natural English comic dialogue. \n'
          'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
          'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.\n\n'
          '${parts.userContent}<end_of_turn>\n'
          '<start_of_turn>model\n';
    }

    return '<|im_start|>system\n'
        'You are an expert localizer for Asian comics. Translate the raw OCR text from ${parts.language} into natural English comic dialogue. \n'
        'This is fictional comic dialogue. Preserve the original tone, slang, and profanity faithfully without self-censorship or refusal.\n'
        'Output ONLY the final English translation. No chat, no notes, no markdown formatting. Fix OCR typos.<|im_end|>\n'
        '<|im_start|>user\n'
        '${parts.userContent}<|im_end|>\n'
        '<|im_start|>assistant\n';
  }

  static final RegExp _cjkRegex = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\uFF65-\uFF9F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]',
  );

  /// Returns true if [text] contains CJK characters.
  static bool hasCjkCharacters(String text) {
    if (text.isEmpty) return false;
    return _cjkRegex.hasMatch(text);
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

  /// Post-processing helper that cleans raw LLM output into comic dialogue.
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

    // 2. Immediately truncate at the first occurrence of any stop marker.
    // Everything after the first stop marker is completely discarded!
    final stopRegex = RegExp(
      r'(?:<\|im_end\|>|<\|endoftext\|>|<\|eot_id\|>|<\|end_of_text\|>|<\|im_start\|>|<end_of_turn>|<start_of_turn>|<eos>|</s>|\nUser:|\nAssistant:|\nHuman:|\nSystem:|\n<\|user\|>|\n<\|system\|>|<\|start_header_id\|>)',
      caseSensitive: false,
    );
    final stopMatch = stopRegex.firstMatch(text);
    if (stopMatch != null) {
      text = text.substring(0, stopMatch.start);
    }

    // 3. Strip reasoning / think tags (terminated or unterminated).
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*$', caseSensitive: false),
      '',
    );

    // 4. Strip prompt blocks if echoed by the model.
    text = text.replaceAll(
      RegExp(r'<system>[\s\S]*?</system>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<user>[\s\S]*?</user>', caseSensitive: false),
      '',
    );

    // Strip standalone tags.
    text = text.replaceAll(
      RegExp(r'</?(?:system|user|assistant|think)>', caseSensitive: false),
      '',
    );

    // Strip prompt echoes or operational rules echoes.
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
        r'You are a specialized,\s*strictly objective machine translation engine[^\n]*\n?',
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
        r'translate\s+(?:the\s+)?(?:raw\s+ocr|japanese|korean|chinese|comic)[^\n.]*[\n.]?\s*',
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

    // Strip hallucinated storytelling filler
    text = text.replaceAll(
      RegExp(r'The cat chased after the mouse[^\n]*\n?', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'The Legend of the Dragon[^\n]*\n?', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'The Legend of the Phoenix[^\n]*\n?', caseSensitive: false),
      '',
    );

    // 5. Strip code fences (```...```).
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*\n?|```'), '');

    // 6. Strip blockquotes (> line starts).
    text = text.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');

    // 7. Strip markdown headings (# ...).
    text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');

    // 8. Strip markdown formatting syntax (bold, italics, code).
    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    text = text.replaceAll(RegExp(r'[*`_]'), '');

    // 9. Strip common chat preambles and introductory phrases.
    text = text.replaceAll(
      RegExp(
        r'^\s*(?:sure(?: thing)?[!,.]?\s*)?(?:here\s+(?:is|are)\s+the\s+(?:final\s+)?(?:english\s+)?(?:comic\s+)?(?:dialogue|translation)\s*(?:is)?\s*:|the\s+english\s+translation\s+is\s*:|english\s+translation\s*:|translation\s*to\s*english\s*:|natural\s+english\s*:|translated\s+text\s*:|based\s+on\s+the\s+comic\s+dialogue\s*,?\s*:?|translation\s*:|dialogue\s*:|output\s*:)\s*',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'^\s*(?:sure(?: thing)?[!,.]?\s*)?(?:here\s+(?:is|are)\s+the\s+(?:final\s+)?(?:english\s+)?(?:comic\s+)?(?:dialogue|translation)\s*(?:is)?|the\s+english\s+translation\s+is|english\s+translation|translation\s*to\s*english|natural\s+english|translated\s+text|based\s+on\s+the\s+comic\s+dialogue|translation|dialogue|output)\s*:\s*\n+',
        caseSensitive: false,
      ),
      '',
    );

    // 10. If output has multiple paragraphs, pick the translated dialogue paragraph.
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
            lower.startsWith('user:') ||
            lower.startsWith('assistant:') ||
            lower.startsWith('system:') ||
            lower.contains('expert localizer') ||
            lower.contains('comic dialogue') ||
            lower.contains('ocr typos')) {
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

    // 11. Strip surrounding quotation marks if entire line is quoted.
    text = text.trim();
    if ((text.startsWith('"') && text.endsWith('"') && text.length >= 2) ||
        (text.startsWith("'") && text.endsWith("'") && text.length >= 2) ||
        (text.startsWith('“') && text.endsWith('”') && text.length >= 2) ||
        (text.startsWith('「') && text.endsWith('」') && text.length >= 2)) {
      text = text.substring(1, text.length - 1).trim();
    }

    return text;
  }

  /// Initializes the local GGUF model session via FlutterLlama safely.
  Future<bool> initializeSession({
    String? modelPath,
  }) async {
    _isInitializing = true;
    try {
      if (Platform.isAndroid && !(await isStoragePermissionGranted())) {
        lastStatusMessage =
            'Izin Akses Semua File diperlukan untuk membaca /storage/emulated/0/models/';
      }

      await ensureModelsDirectoryExists();

      String? resolvedPath = modelPath;

      // 1. Check SettingsService activeAiModelPath
      if (resolvedPath == null) {
        try {
          final activePath = SettingsService.instance.settings.activeAiModelPath;
          if (activePath.isNotEmpty &&
              (File(activePath).existsSync() || Directory(activePath).existsSync())) {
            resolvedPath = activePath;
          }
        } catch (_) {}
      }

      // 2. Directory inspection
      if (resolvedPath != null && Directory(resolvedPath).existsSync()) {
        try {
          final dir = Directory(resolvedPath);
          final entries = dir.listSync(recursive: false);
          for (final entry in entries) {
            if (entry is File && entry.path.toLowerCase().endsWith('.gguf')) {
              resolvedPath = entry.path;
              break;
            }
          }
        } catch (e) {
          debugPrint('Error inspecting directory $resolvedPath for models: $e');
          resolvedPath = null;
        }
      }

      // 3. Fallback search in defaultModelsDirectoryPath and candidates
      if (resolvedPath == null) {
        try {
          final defaultDir = Directory(defaultModelsDirectoryPath);
          if (defaultDir.existsSync()) {
            final entries = defaultDir.listSync(recursive: false);
            for (final entry in entries) {
              if (entry is File && entry.path.toLowerCase().endsWith('.gguf')) {
                resolvedPath = entry.path;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('Error inspecting defaultModelsDirectoryPath: $e');
        }

        if (resolvedPath == null) {
          for (final candidate in defaultModelCandidatePaths) {
            if (File(candidate).existsSync()) {
              resolvedPath = candidate;
              break;
            }
          }
        }

        if (resolvedPath == null) {
          try {
            final appDirs = await getAppModelDirectories();
            for (final appDir in appDirs) {
              final d = Directory(appDir);
              if (d.existsSync()) {
                final entries = d.listSync(recursive: false);
                for (final entry in entries) {
                  if (entry is File && entry.path.toLowerCase().endsWith('.gguf')) {
                    resolvedPath = entry.path;
                    break;
                  }
                }
                if (resolvedPath != null) break;
              }
            }
          } catch (_) {}
        }

        if (resolvedPath == null) {
          for (final scanDir in defaultScanDirectories) {
            try {
              final d = Directory(scanDir);
              if (d.existsSync()) {
                final entries = d.listSync(recursive: false);
                for (final entry in entries) {
                  if (entry is File && entry.path.toLowerCase().endsWith('.gguf')) {
                    resolvedPath = entry.path;
                    break;
                  }
                }
                if (resolvedPath != null) break;
              }
            } catch (_) {}
          }
        }
      }

      if (resolvedPath == null || !File(resolvedPath).existsSync()) {
        if (lastStatusMessage == null || !lastStatusMessage!.startsWith('Izin')) {
          lastStatusMessage = 'Tidak ada model .gguf di /storage/emulated/0/models/';
        }
        return false;
      }

      final fileName = p.basename(resolvedPath);
      final config = LlamaConfig(
        modelPath: resolvedPath,
        contextSize: 2048,
        nThreads: 4,
        nGpuLayers: -1,
        useGpu: true,
      );

      final loaded = await FlutterLlama.instance.loadModel(config);
      if (loaded) {
        _activeModelPath = resolvedPath;
        lastStatusMessage = 'Ready: $fileName';
        return true;
      } else {
        lastStatusMessage = 'Gagal memuat model .gguf ($fileName)';
        return false;
      }
    } catch (e) {
      lastStatusMessage = 'GgufLocalLlmEngine initialization error: $e';
      debugPrint('GGUF runtime initialization error: $e');
      return false;
    } finally {
      _isInitializing = false;
    }
  }

  /// Translates manga text using the local LLM engine.
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

    if (!hasCjkCharacters(cleaned)) {
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
    final constitutionalPrompt = buildPrompt(
      language: languageName,
      rawOcrText: cleaned,
    );

    // 1. Mock inference handler routing (tests and headless environments)
    if (mockInferenceHandler != null) {
      final rawResult = await mockInferenceHandler!(
        constitutionalPrompt,
        temperature: effectiveTemperature,
        maxTokens: targetTokens,
      );
      return cleanLlmOutput(rawResult);
    }

    // 2. Real FlutterLlama inference
    if (!isModelLoaded && !_isInitializing) {
      await initializeSession();
    }

    if (isModelLoaded) {
      try {
        final formattedPrompt = formatForModel(
          constitutionalPrompt,
          activeModelPath: _activeModelPath,
        );
        debugPrint('[GgufLocalLlmEngine] OCR input: "$cleaned" ($languageName)');
        final response = await FlutterLlama.instance.generate(
          GenerationParams(
            prompt: formattedPrompt,
            temperature: effectiveTemperature,
            maxTokens: targetTokens,
            stopSequences: const [
              '<|im_end|>',
              '<|endoftext|>',
              '<|eot_id|>',
              '<|end_of_text|>',
              '<end_of_turn>',
              '<eos>',
              '</s>',
              '\n\n',
              '<|im_start|>',
            ],
          ),
        );
        debugPrint('[GgufLocalLlmEngine] Raw LLM output: "${response.text}"');
        final cleanedOutput = cleanLlmOutput(response.text);
        debugPrint('[GgufLocalLlmEngine] Cleaned output: "$cleanedOutput"');
        if (cleanedOutput.isNotEmpty) {
          return cleanedOutput;
        }
      } catch (e) {
        debugPrint('FlutterLlama inference error ($languageName -> $target): $e');
      }
    }

    return cleaned;
  }

  /// Closes active FlutterLlama model and clears state.
  Future<void> dispose() async {
    try {
      if (FlutterLlama.instance.isModelLoaded) {
        await FlutterLlama.instance.unloadModel();
      }
    } catch (e) {
      debugPrint('Error unloading FlutterLlama model: $e');
    }
    _activeModelPath = null;
    lastStatusMessage = null;
  }
}
