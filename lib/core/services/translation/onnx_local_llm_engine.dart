// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88
// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../settings_service.dart';
import 'qwen_bpe_tokenizer.dart';
import 'translation_models.dart';

export 'qwen_bpe_tokenizer.dart' show LlmTokenizer, QwenBpeTokenizer;

/// Persistent native prefix KV-cache entry for reusing `<system>` prefix
/// `past_key_values` tensors across bubble translations within the same session.
class _CachedPrefixKv {
  final int sessionAddress;
  final String prefixKey;
  final int prefixLength;
  final Map<String, int> kvAddresses; // pkvInputName -> OrtValue.address

  const _CachedPrefixKv({
    required this.sessionAddress,
    required this.prefixKey,
    required this.prefixLength,
    required this.kvAddresses,
  });
}

/// Discovered ONNX model file metadata from local storage.
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

/// Adapter wrapping [SentencePieceTokenizer] into [LlmTokenizer].
class SentencePieceLlmTokenizer implements LlmTokenizer {
  final SentencePieceTokenizer _inner;
  final int _eosId;

  SentencePieceLlmTokenizer(this._inner, {int? eosId})
      : _eosId = eosId ?? _inner.vocab.eosId;

  @override
  List<int> encode(String text) => _inner.encode(text).ids;

  @override
  String decode(List<int> tokens) => _inner.decode(tokens);

  @override
  int get eosTokenId => _eosId;
}

/// Delegate type for mock or custom LLM inference in tests and headless environments.
typedef LlmInferenceHandler = Future<String> Function(
  String prompt, {
  required double temperature,
  required int maxTokens,
});

/// Offline Local LLM Translation Engine using ONNX Runtime.
///
/// Executes on-device inference using quantized local LLMs (e.g. Qwen 2.5 / Gemma 3 Nano)
/// with strict 100% offline boundaries, deterministic low-temperature generation,
/// and comic-dialogue output sanitization.
class OnnxLocalLlmEngine {
  OnnxLocalLlmEngine({
    this.mockInferenceHandler,
  });

  static final OnnxLocalLlmEngine instance = OnnxLocalLlmEngine();

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
    '/storage/emulated/0/models/model_quantized.onnx',
    '/storage/emulated/0/models/model_int8.onnx',
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-abliterated-int8.onnx',
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-abliterated-q4.onnx',
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-q4.onnx',
    '/storage/emulated/0/models/model_q4.onnx',
    '/storage/emulated/0/models/model_q4f16.onnx',
    '/storage/emulated/0/models/model.onnx',
    'models/model_quantized.onnx',
    'models/model_int8.onnx',
    'models/qwen2.5-0.5b-instruct-abliterated-int8.onnx',
    'models/qwen2.5-0.5b-instruct-abliterated-q4.onnx',
    'models/qwen2.5-0.5b-instruct-q4.onnx',
    'models/model_q4.onnx',
    'models/model_q4f16.onnx',
    'models/model.onnx',
    'assets/models/model_quantized.onnx',
    'assets/models/qwen2.5-0.5b-instruct-abliterated-q4.onnx',
    'assets/models/qwen2.5-0.5b-instruct-q4.onnx',
  ];

  /// Candidate filenames for companion tokenizer discovery.
  static const List<String> defaultTokenizerCandidateNames = [
    'tokenizer.json',
    'qwen_tokenizer.json',
    'tokenizer.model',
  ];

  /// Default directories searched for local ONNX models.
  static const List<String> defaultScanDirectories = [
    '/storage/emulated/0/models/',
    '/storage/emulated/0/Download/models/',
    '/storage/emulated/0/Download/',
    'models/',
    'assets/models/',
  ];

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

  /// Scans default (or custom [searchDirectories]) paths for available `.onnx` models.
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
            if (entry is File && entry.path.toLowerCase().endsWith('.onnx')) {
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

  OrtEnv? _env;
  OrtSessionOptions? _sessionOptions;
  OrtSession? _session;
  bool _isNativeAvailable = false;
  bool _isInitializing = false;
  bool get isInitializing => _isInitializing;

  LlmTokenizer? _tokenizer;
  LlmTokenizer? get tokenizer => _tokenizer;

  static _CachedPrefixKv? _cachedPrefixKv;

  static void _releaseCachedPrefixKv() {
    final cached = _cachedPrefixKv;
    _cachedPrefixKv = null;
    if (cached == null) return;
    for (final int addr in cached.kvAddresses.values) {
      try {
        OrtValueTensor.fromAddress(addr).release();
      } catch (_) {}
    }
  }

  String? lastStatusMessage;

  @visibleForTesting
  void setMockTokenizer(dynamic tok) {
    if (tok is LlmTokenizer) {
      _tokenizer = tok;
    } else if (tok is SentencePieceTokenizer) {
      _tokenizer = SentencePieceLlmTokenizer(tok);
    }
  }

  OrtEnv? get env => _env;
  OrtSessionOptions? get sessionOptions => _sessionOptions;
  OrtSession? get session => _session;
  bool get isNativeAvailable => _isNativeAvailable;
  bool get isModelLoaded => _session != null;
  bool get isReady => isModelLoaded || mockInferenceHandler != null;

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

  /// Extracts `(language, userContent)` from a `<system>...from {language} into...</system><user>{userContent}</user>` prompt.
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

  static final RegExp _cjkRegex = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\uFF65-\uFF9F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]',
  );

  /// Returns true if [text] contains CJK characters:
  /// - Hiragana (\u3040-\u309F)
  /// - Katakana (\u30A0-\u30FF, \uFF65-\uFF9F)
  /// - CJK Unified / Compatibility Ideographs (\u3400-\u4DBF, \u4E00-\u9FFF, \uF900-\uFAFF)
  /// - Hangul (\uAC00-\uD7AF, \u1100-\u11FF, \u3130-\u318F)
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

  /// Post-processing helper that cleans raw LLM output into clean comic dialogue:
  /// - Strips `<system>`, `<user>`, `<assistant>`, `<think>` tags and blocks.
  /// - Strips markdown formatting (bold, italics, code, headings, blockquotes).
  /// - Strips chat preambles like "Translation:", "Here is the English translation:".
  /// - Strips surrounding quotes.
  static String cleanLlmOutput(String rawOutput) {
    if (rawOutput.isEmpty) return '';

    String text = rawOutput;

    // 1. Strip prompt blocks if echoed by the model.
    text = text.replaceAll(
      RegExp(r'<system>[\s\S]*?</system>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<user>[\s\S]*?</user>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
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

    // Strip hallucinated storytelling filler (e.g. "The cat chased after the mouse...", "The Legend of the Dragon...")
    text = text.replaceAll(
      RegExp(r'The cat chased after the mouse[^\n]*\n?', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'The Legend of the Dragon[^\n]*\n?', caseSensitive: false),
      '',
    );

    // 2. Strip code fences (```...```).
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*\n?|```'), '');

    // 3. Strip blockquotes (> line starts).
    text = text.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');

    // 4. Strip markdown headings (# ...).
    text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');

    // 5. Strip markdown formatting syntax (bold, italics, code).
    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m[1]!);
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    text = text.replaceAll(RegExp(r'[*`_]'), '');

    // 6. Strip common chat preambles and introductory phrases.
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

    // 7. If output has multiple paragraphs (separated by \n\n), pick only the translated dialogue paragraph.
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

    // 8. Strip surrounding quotation marks if entire line is quoted.
    text = text.trim();
    if ((text.startsWith('"') && text.endsWith('"') && text.length >= 2) ||
        (text.startsWith("'") && text.endsWith("'") && text.length >= 2) ||
        (text.startsWith('“') && text.endsWith('”') && text.length >= 2) ||
        (text.startsWith('「') && text.endsWith('」') && text.length >= 2)) {
      text = text.substring(1, text.length - 1).trim();
    }

    return text;
  }

  /// Creates an [OrtSession] from [path] in a background isolate and returns
  /// its native pointer address.
  static int _createSessionFromFileInIsolate(String path) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      final session = OrtSession.fromFile(File(path), options);
      return session.address;
    } finally {
      options.release();
    }
  }

  /// Initializes the native ONNX session and tokenizer safely.
  Future<bool> initializeSession({
    String? modelPath,
    Uint8List? modelBytes,
    String? tokenizerPath,
    bool useBundledFallback = true,
    bool? runInIsolate,
  }) async {
    final bool useIsolate =
        runInIsolate ?? !Platform.environment.containsKey('FLUTTER_TEST');
    _isInitializing = true;
    try {
      if (Platform.isAndroid && !(await isStoragePermissionGranted())) {
        lastStatusMessage =
            'Izin Akses Semua File diperlukan untuk membaca /storage/emulated/0/models/';
      }

      await ensureModelsDirectoryExists();

      _env ??= OrtEnv.instance..init();
      _sessionOptions ??= OrtSessionOptions()
        ..setIntraOpNumThreads(4)
        ..setInterOpNumThreads(1)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      String? resolvedPath = modelPath;

      // 1. If modelPath is null, check SettingsService.instance.settings.activeAiModelPath
      if (resolvedPath == null) {
        try {
          final activePath = SettingsService.instance.settings.activeAiModelPath;
          if (activePath.isNotEmpty &&
              (File(activePath).existsSync() || Directory(activePath).existsSync())) {
            resolvedPath = activePath;
          }
        } catch (_) {}
      }

      // 2. If modelPath points to an existing directory, inspect for .onnx
      if (resolvedPath != null && Directory(resolvedPath).existsSync()) {
        try {
          final dir = Directory(resolvedPath);
          final entries = dir.listSync(recursive: false);
          File? firstOnnx;
          for (final entry in entries) {
            if (entry is File && entry.path.toLowerCase().endsWith('.onnx')) {
              firstOnnx = entry;
              break;
            }
          }
          resolvedPath = firstOnnx?.path;
        } catch (e) {
          debugPrint('Error inspecting directory $resolvedPath for models: $e');
          resolvedPath = null;
        }
      }

      // 3. Fallback search in defaultModelsDirectoryPath, candidate paths, app dirs, and scan dirs
      if (resolvedPath == null && modelBytes == null) {
        try {
          final defaultDir = Directory(defaultModelsDirectoryPath);
          if (defaultDir.existsSync()) {
            final entries = defaultDir.listSync(recursive: false);
            for (final entry in entries) {
              if (entry is File && entry.path.toLowerCase().endsWith('.onnx')) {
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
                  if (entry is File && entry.path.toLowerCase().endsWith('.onnx')) {
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
                  if (entry is File && entry.path.toLowerCase().endsWith('.onnx')) {
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

      // If model file is not found
      if ((resolvedPath == null || !File(resolvedPath).existsSync()) && modelBytes == null) {
        if (lastStatusMessage == null || !lastStatusMessage!.startsWith('Izin')) {
          lastStatusMessage = 'Tidak ada model .onnx di /storage/emulated/0/models/';
        }
        _isNativeAvailable = false;
        _session = null;
        return false;
      }

      // 4. Resolve companion tokenizer file
      String? resolvedTokPath = tokenizerPath;
      if (resolvedTokPath != null && !File(resolvedTokPath).existsSync()) {
        resolvedTokPath = null;
      }

      if (resolvedTokPath == null && resolvedPath != null) {
        final modelDir = p.dirname(resolvedPath);
        for (final candidate in defaultTokenizerCandidateNames) {
          final candidatePath = p.join(modelDir, candidate);
          if (File(candidatePath).existsSync()) {
            resolvedTokPath = candidatePath;
            break;
          }
        }
      }

      if (resolvedTokPath == null) {
        for (final candidate in defaultTokenizerCandidateNames) {
          final candidatePath = p.join(defaultModelsDirectoryPath, candidate);
          if (File(candidatePath).existsSync()) {
            resolvedTokPath = candidatePath;
            break;
          }
        }
      }

      bool isBundledFallbackUsed = false;

      // Load companion tokenizer eagerly only if small (< 1 MB); large tokenizers
      // are loaded after session creation succeeds to avoid wasted work on failed loads.
      if (resolvedTokPath != null &&
          File(resolvedTokPath).existsSync() &&
          File(resolvedTokPath).lengthSync() < 1024 * 1024) {
        try {
          if (resolvedTokPath.toLowerCase().endsWith('.json')) {
            final jsonStr = await File(resolvedTokPath).readAsString();
            _tokenizer = (useIsolate && jsonStr.length > 50000)
                ? await Isolate.run(
                    () => QwenBpeTokenizer.fromJsonString(jsonStr),
                  )
                : QwenBpeTokenizer.fromJsonString(jsonStr);
          } else if (resolvedTokPath.toLowerCase().endsWith('.model')) {
            final sp = await SentencePieceTokenizer.fromModelFile(resolvedTokPath);
            _tokenizer = SentencePieceLlmTokenizer(sp);
          }
        } catch (e) {
          debugPrint('Failed to load tokenizer from $resolvedTokPath: $e');
          _tokenizer = null;
        }
      }

      if (resolvedPath != null && File(resolvedPath).existsSync()) {
        _releaseCachedPrefixKv();
        try {
          _session?.release();
        } catch (_) {}

        try {
          final String targetModelPath = resolvedPath;
          final File targetFile = File(targetModelPath);
          if (useIsolate &&
              !Platform.isWindows &&
              targetFile.lengthSync() > 1024 * 1024) {
            final int sessionAddress = await Isolate.run<int>(
              () => _createSessionFromFileInIsolate(targetModelPath),
            );
            _session = OrtSession.fromAddress(sessionAddress);
          } else {
            _session = OrtSession.fromFile(targetFile, _sessionOptions!);
          }
          _isNativeAvailable = true;

          // Load large companion tokenizer (>= 1 MB) after session creation succeeds
          if (_tokenizer == null &&
              resolvedTokPath != null &&
              File(resolvedTokPath).existsSync()) {
            try {
              if (resolvedTokPath.toLowerCase().endsWith('.json')) {
                final jsonStr = await File(resolvedTokPath).readAsString();
                _tokenizer = (useIsolate && jsonStr.length > 50000)
                    ? await Isolate.run(
                        () => QwenBpeTokenizer.fromJsonString(jsonStr),
                      )
                    : QwenBpeTokenizer.fromJsonString(jsonStr);
              } else if (resolvedTokPath.toLowerCase().endsWith('.model')) {
                final sp =
                    await SentencePieceTokenizer.fromModelFile(resolvedTokPath);
                _tokenizer = SentencePieceLlmTokenizer(sp);
              }
            } catch (e) {
              debugPrint('Failed to load tokenizer from $resolvedTokPath: $e');
              _tokenizer = null;
            }
          }

          // Load bundled fallback tokenizer after session is created
          if (_tokenizer == null && useBundledFallback) {
            try {
              _tokenizer = await QwenBpeTokenizer.loadBundledAsset(
                runInIsolate: useIsolate,
              );
              if (_tokenizer != null) {
                isBundledFallbackUsed = true;
              }
            } catch (e) {
              debugPrint('Failed to load bundled fallback tokenizer: $e');
              _tokenizer = null;
            }
          }

          if (_tokenizer != null) {
            if (isBundledFallbackUsed) {
              lastStatusMessage =
                  'Ready: ${p.basename(resolvedPath)} (built-in tokenizer)';
            } else {
              lastStatusMessage = 'Ready: ${p.basename(resolvedPath)}';
            }
          } else {
            lastStatusMessage =
                'Model loaded (${p.basename(resolvedPath)}), but tokenizer.json not found in ${p.dirname(resolvedPath)}';
          }
          return true;
        } catch (e) {
          final errorStr = e.toString();
          if (errorStr.contains('MatMulNBits') ||
              errorStr.contains('NOT_IMPLEMENTED')) {
            lastStatusMessage =
                'Model 4-bit (MatMulNBits) tidak didukung runtime. Gunakan model_quantized.onnx (INT8, 472MB)';
          } else if (_tokenizer == null) {
            lastStatusMessage =
                'Model loaded (${p.basename(resolvedPath)}), but tokenizer.json not found in ${p.dirname(resolvedPath)}';
          } else {
            lastStatusMessage = 'Gagal memuat ${p.basename(resolvedPath)}: $e';
          }
          debugPrint('ONNX Native runtime initialization error: $e');
          _isNativeAvailable = false;
          _session = null;
          return false;
        }
      } else if (modelBytes != null) {
        _releaseCachedPrefixKv();
        try {
          _session?.release();
        } catch (_) {}

        try {
          _session = OrtSession.fromBuffer(modelBytes, _sessionOptions!);
          _isNativeAvailable = true;

          if (_tokenizer == null && useBundledFallback) {
            try {
              _tokenizer = await QwenBpeTokenizer.loadBundledAsset();
            } catch (_) {}
          }

          if (_tokenizer != null) {
            lastStatusMessage = 'Ready: in-memory model';
          } else {
            lastStatusMessage =
                'Model loaded (in-memory), but tokenizer.json not found';
          }
          return true;
        } catch (e) {
          lastStatusMessage = 'Gagal memuat in-memory model: $e';
          debugPrint('ONNX Native runtime buffer initialization error: $e');
          _isNativeAvailable = false;
          _session = null;
          return false;
        }
      }
    } catch (e) {
      lastStatusMessage = 'ONNX runtime initialization error: $e';
      debugPrint('ONNX Native runtime initialization error: $e');
      _isNativeAvailable = false;
      _session = null;
    } finally {
      _isInitializing = false;
    }

    return false;
  }

  /// Translates manga text using the local LLM engine.
  /// Automatically calls [initializeSession] if session is not yet loaded.
  Future<String> translateMangaText({
    required String text,
    required TranslationSourceLanguage source,
    TranslationTargetLanguage target = TranslationTargetLanguage.english,
    double temperature = defaultTemperature,
    int maxTokens = defaultMaxTokens,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return '';

    // Pass through standalone comic punctuation.
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
    final prompt = buildPrompt(
      language: languageName,
      rawOcrText: cleaned,
    );

    // 1. Custom or Mock Inference (Testing and Headless Environments)
    if (mockInferenceHandler != null) {
      final rawResult = await mockInferenceHandler!(
        prompt,
        temperature: effectiveTemperature,
        maxTokens: targetTokens,
      );
      return cleanLlmOutput(rawResult);
    }

    // Auto-initialize session if not loaded
    if (_session == null && lastStatusMessage == null && !_isInitializing) {
      await initializeSession(runInIsolate: !Platform.isWindows);
    }

    // 2. Native ONNX Runtime Session Inference
    if (_session != null && _isNativeAvailable) {
      try {
        final nativeOutput = await _runNativeInference(
          prompt: prompt,
          temperature: effectiveTemperature,
          maxTokens: targetTokens,
        );
        if (nativeOutput.isNotEmpty) {
          return cleanLlmOutput(nativeOutput);
        }
      } catch (e) {
        lastStatusMessage = 'Translation execution error: $e';
        debugPrint('Local LLM ONNX native execution failed: $e');
      }
    }

    // 3. Fallback: Gracefully pass-through text without throwing symbol errors.
    return cleanLlmOutput(cleaned);
  }

  /// Extracts the last token logits as a list of doubles from ONNX tensor output.
  static List<double> extractLastLogits(dynamic outputValue) {
    if (outputValue is List) {
      if (outputValue.isEmpty) return const [];
      final first = outputValue.first;
      if (first is List) {
        if (first.isNotEmpty && first.first is List) {
          final lastTokenLogits = (outputValue[0] as List).last;
          if (lastTokenLogits is List) {
            return lastTokenLogits.map((e) => (e as num).toDouble()).toList();
          }
        } else {
          final lastTokenLogits = outputValue.last;
          if (lastTokenLogits is List) {
            return lastTokenLogits.map((e) => (e as num).toDouble()).toList();
          }
        }
      } else if (first is num) {
        return outputValue.map((e) => (e as num).toDouble()).toList();
      }
    }
    return const [];
  }

  /// Selects the next token ID from output logits using argmax (for temp <= 0.1)
  /// or temperature-scaled softmax sampling (for temp > 0.1).
  static int selectNextToken(List<double> logits, double temperature) {
    if (logits.isEmpty) return -1;

    if (temperature <= 0.1) {
      int maxIndex = 0;
      double maxVal = logits[0];
      for (int i = 1; i < logits.length; i++) {
        if (logits[i] > maxVal) {
          maxVal = logits[i];
          maxIndex = i;
        }
      }
      return maxIndex;
    }

    double maxLogit = logits.reduce(math.max);
    final expProbs = List<double>.generate(
      logits.length,
      (i) => math.exp((logits[i] - maxLogit) / temperature),
    );

    final sumExp = expProbs.reduce((a, b) => a + b);
    if (sumExp == 0 || sumExp.isNaN) {
      return logits.indexOf(maxLogit);
    }

    final r = math.Random().nextDouble() * sumExp;
    double cumulative = 0.0;
    for (int i = 0; i < expProbs.length; i++) {
      cumulative += expProbs[i];
      if (cumulative >= r) {
        return i;
      }
    }
    return expProbs.length - 1;
  }

  /// Formats the constitutional prompt payload into model-specific chat templates
  /// (e.g. ChatML for Qwen 2.5).
  static String formatForModel(String prompt, LlmTokenizer? tokenizer) {
    if (tokenizer is QwenBpeTokenizer) {
      final systemMatch =
          RegExp(r'<system>([\s\S]*?)</system>', caseSensitive: false)
              .firstMatch(prompt);
      final userMatch =
          RegExp(r'<user>([\s\S]*?)</user>', caseSensitive: false)
              .firstMatch(prompt);
      if (systemMatch != null && userMatch != null) {
        final sysContent = systemMatch.group(1)!.trim();
        final userContent = userMatch.group(1)!.trim();
        return '<|im_start|>system\n$sysContent<|im_end|>\n<|im_start|>user\n$userContent<|im_end|>\n<|im_start|>assistant\n';
      }
    }
    return prompt;
  }

  /// Selects the next token directly from an [OrtValue] logits tensor without
  /// boxing or copying the tensor into Dart heap lists (`outputVal.value`).
  static int selectNextTokenFromOrtValue(
    OrtValue logitsVal,
    int stepSeqLen,
    double temperature,
    List<int> generatedTokenIds,
  ) {
    final ortApi = OrtEnv.instance.ortApiPtr.ref;

    final infoPtrPtr = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    final dataPtrPtr = calloc<ffi.Pointer<ffi.Float>>();
    final countPtr = calloc<ffi.Size>();

    try {
      var statusPtr = ortApi.GetTensorTypeAndShape.asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                  ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(
          logitsVal.ptr, infoPtrPtr);
      OrtStatus.checkOrtStatus(statusPtr);

      final infoPtr = infoPtrPtr.value;
      try {
        statusPtr = ortApi.GetTensorShapeElementCount.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
                ffi.Pointer<ffi.Size>)>()(infoPtr, countPtr);
        OrtStatus.checkOrtStatus(statusPtr);
      } finally {
        ortApi.ReleaseTensorTypeAndShapeInfo.asFunction<
                void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(
            infoPtr);
      }

      final int totalElements = countPtr.value;
      if (totalElements <= 0 || stepSeqLen <= 0) return -1;

      final int vocabSize = totalElements ~/ stepSeqLen;
      if (vocabSize <= 0) return -1;

      statusPtr = ortApi.GetTensorMutableData.asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                  ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(
          logitsVal.ptr, dataPtrPtr.cast());
      OrtStatus.checkOrtStatus(statusPtr);

      final ffi.Pointer<ffi.Float> floatPtr = dataPtrPtr.value;
      if (floatPtr == ffi.nullptr) return -1;

      final int offset = (stepSeqLen - 1) * vocabSize;
      final Float32List rawLogits = floatPtr.asTypedList(totalElements);

      final Set<int>? seenTokens =
          generatedTokenIds.isEmpty ? null : generatedTokenIds.toSet();
      const double repetitionPenalty = 1.15;

      if (temperature <= 0.1) {
        int maxIdx = 0;
        double maxVal = double.negativeInfinity;
        for (int i = 0; i < vocabSize; i++) {
          double v = rawLogits[offset + i];
          if (seenTokens != null && seenTokens.contains(i)) {
            v = v < 0 ? v * repetitionPenalty : v / repetitionPenalty;
          }
          if (v > maxVal) {
            maxVal = v;
            maxIdx = i;
          }
        }
        return maxIdx;
      }

      double maxLogit = double.negativeInfinity;
      for (int i = 0; i < vocabSize; i++) {
        double v = rawLogits[offset + i];
        if (seenTokens != null && seenTokens.contains(i)) {
          v = v < 0 ? v * repetitionPenalty : v / repetitionPenalty;
        }
        if (v > maxLogit) {
          maxLogit = v;
        }
      }

      final Float64List expProbs = Float64List(vocabSize);
      double sumExp = 0.0;
      for (int i = 0; i < vocabSize; i++) {
        double v = rawLogits[offset + i];
        if (seenTokens != null && seenTokens.contains(i)) {
          v = v < 0 ? v * repetitionPenalty : v / repetitionPenalty;
        }
        final double p = math.exp((v - maxLogit) / temperature);
        expProbs[i] = p;
        sumExp += p;
      }

      if (sumExp <= 0.0 || sumExp.isNaN) {
        return 0;
      }

      final double r = math.Random().nextDouble() * sumExp;
      double cumulative = 0.0;
      for (int i = 0; i < vocabSize; i++) {
        cumulative += expProbs[i];
        if (cumulative >= r) {
          return i;
        }
      }
      return vocabSize - 1;
    } finally {
      calloc.free(infoPtrPtr);
      calloc.free(dataPtrPtr);
      calloc.free(countPtr);
    }
  }

  /// Autoregressive token generation loop executed in a background isolate
  /// with single-token incremental prefill, persistent prefix KV-cache reuse,
  /// and zero-copy FFI logits inspection.
  static ({
    List<int> tokenIds,
    Map<String, int>? newPrefixKvAddresses,
    int prefixLen,
  }) _generateTokensInIsolate({
    required int sessionAddress,
    required List<int> prefixIds,
    required List<int> suffixIds,
    Map<String, int>? cachedPrefixKvAddresses,
    required double temperature,
    required int maxTokens,
    required Set<int> eosTokenIds,
    Set<int> newlineTokenIds = const <int>{198, 271},
  }) {
    final OrtSession session = OrtSession.fromAddress(sessionAddress);

    final String inputIdsName = session.inputNames.isNotEmpty
        ? session.inputNames.firstWhere(
            (n) =>
                n.toLowerCase().contains('input_ids') ||
                n.toLowerCase().contains('input'),
            orElse: () => session.inputNames[0],
          )
        : 'input_ids';

    final String? attentionMaskName =
        session.inputNames.cast<String?>().firstWhere(
              (n) =>
                  n != null &&
                  (n.toLowerCase().contains('attention') ||
                      n.toLowerCase().contains('mask')),
              orElse: () => null,
            );

    final String? positionIdsName =
        session.inputNames.cast<String?>().firstWhere(
              (n) => n != null && n.toLowerCase().contains('position'),
              orElse: () => null,
            );

    final String outputName = session.outputNames.firstWhere(
      (n) => n.toLowerCase().contains('logits'),
      orElse: () =>
          session.outputNames.isNotEmpty ? session.outputNames.first : 'logits',
    );

    final List<String> pkvInputNames = session.inputNames
        .where((n) => n.toLowerCase().contains('past_key_values'))
        .toList();
    final List<String> presentOutputNames = session.outputNames
        .where((n) => n.toLowerCase().contains('present'))
        .toList();
    final bool canUseKvCache = pkvInputNames.isNotEmpty &&
        pkvInputNames.length == presentOutputNames.length;

    final List<String> requestedOutputs = <String>[
      outputName,
      if (canUseKvCache) ...presentOutputNames,
    ];

    final List<int> generatedTokenIds = <int>[];
    final OrtRunOptions runOptions = OrtRunOptions();
    Map<String, int>? newPrefixKvAddresses;
    final int prefixLen = prefixIds.length;

    if (canUseKvCache) {
      Map<String, OrtValue> prefixKv = <String, OrtValue>{};
      Map<String, OrtValue> stepKv = <String, OrtValue>{};
      bool ownsStepKv = false;

      try {
        // Step A: Prefix KV-Cache initialization or reuse
        if (cachedPrefixKvAddresses != null &&
            cachedPrefixKvAddresses.isNotEmpty) {
          prefixKv = <String, OrtValue>{
            for (final e in cachedPrefixKvAddresses.entries)
              e.key: OrtValueTensor.fromAddress(e.value),
          };
        } else if (prefixIds.isNotEmpty) {
          for (int i = 0; i < prefixIds.length; i++) {
            final List<OrtValueTensor> allocs = <OrtValueTensor>[];
            final OrtValueTensor inTensor =
                OrtValueTensor.createTensorWithDataList(
              <int>[prefixIds[i]],
              const <int>[1, 1],
            );
            allocs.add(inTensor);
            final Map<String, OrtValue> inputs = <String, OrtValue>{
              inputIdsName: inTensor,
            };

            if (attentionMaskName != null && attentionMaskName.isNotEmpty) {
              final OrtValueTensor maskTensor =
                  OrtValueTensor.createTensorWithDataList(
                List<int>.filled(i + 1, 1),
                <int>[1, i + 1],
              );
              allocs.add(maskTensor);
              inputs[attentionMaskName] = maskTensor;
            }

            if (positionIdsName != null && positionIdsName.isNotEmpty) {
              final OrtValueTensor posTensor =
                  OrtValueTensor.createTensorWithDataList(
                <int>[i],
                const <int>[1, 1],
              );
              allocs.add(posTensor);
              inputs[positionIdsName] = posTensor;
            }

            if (i == 0) {
              final OrtValueTensor emptyKv =
                  OrtValueTensor.createTensorWithDataList(
                Float32List(0),
                const <int>[1, 2, 0, 64],
              );
              allocs.add(emptyKv);
              for (final String pkvName in pkvInputNames) {
                inputs[pkvName] = emptyKv;
              }
            } else {
              inputs.addAll(prefixKv);
            }

            List<OrtValue?> outputs;
            try {
              outputs = session.run(runOptions, inputs, requestedOutputs);
            } finally {
              for (final OrtValueTensor t in allocs) {
                try {
                  t.release();
                } catch (_) {}
              }
            }

            if (outputs.isNotEmpty) {
              try {
                outputs.first?.release();
              } catch (_) {}
            }

            for (final OrtValue oldKv in prefixKv.values) {
              try {
                oldKv.release();
              } catch (_) {}
            }
            prefixKv.clear();

            if (outputs.length == 1 + presentOutputNames.length) {
              final Map<String, OrtValue> nextKv = <String, OrtValue>{};
              for (int j = 0; j < presentOutputNames.length; j++) {
                final OrtValue? presentVal = outputs[1 + j];
                if (presentVal != null) {
                  final String pkvKey = presentOutputNames[j]
                      .replaceFirst('present.', 'past_key_values.');
                  nextKv[pkvKey] = presentVal;
                }
              }
              prefixKv = nextKv;
            } else {
              for (int j = 1; j < outputs.length; j++) {
                try {
                  outputs[j]?.release();
                } catch (_) {}
              }
              break;
            }
          }

          if (prefixKv.isNotEmpty) {
            newPrefixKvAddresses = <String, int>{
              for (final e in prefixKv.entries) e.key: e.value.address,
            };
          }
        }

        // Step B: Suffix prefill (1 token at a time)
        stepKv = prefixKv;
        ownsStepKv = false;
        int nextToken = -1;

        for (int k = 0; k < suffixIds.length; k++) {
          final int pos = prefixLen + k;
          final List<OrtValueTensor> allocs = <OrtValueTensor>[];
          final OrtValueTensor inTensor =
              OrtValueTensor.createTensorWithDataList(
            <int>[suffixIds[k]],
            const <int>[1, 1],
          );
          allocs.add(inTensor);
          final Map<String, OrtValue> inputs = <String, OrtValue>{
            inputIdsName: inTensor,
          };

          if (attentionMaskName != null && attentionMaskName.isNotEmpty) {
            final OrtValueTensor maskTensor =
                OrtValueTensor.createTensorWithDataList(
              List<int>.filled(pos + 1, 1),
              <int>[1, pos + 1],
            );
            allocs.add(maskTensor);
            inputs[attentionMaskName] = maskTensor;
          }

          if (positionIdsName != null && positionIdsName.isNotEmpty) {
            final OrtValueTensor posTensor =
                OrtValueTensor.createTensorWithDataList(
              <int>[pos],
              const <int>[1, 1],
            );
            allocs.add(posTensor);
            inputs[positionIdsName] = posTensor;
          }

          if (stepKv.isEmpty) {
            final OrtValueTensor emptyKv =
                OrtValueTensor.createTensorWithDataList(
              Float32List(0),
              const <int>[1, 2, 0, 64],
            );
            allocs.add(emptyKv);
            for (final String pkvName in pkvInputNames) {
              inputs[pkvName] = emptyKv;
            }
          } else {
            inputs.addAll(stepKv);
          }

          List<OrtValue?> outputs;
          try {
            outputs = session.run(runOptions, inputs, requestedOutputs);
          } finally {
            for (final OrtValueTensor t in allocs) {
              try {
                t.release();
              } catch (_) {}
            }
          }

          if (outputs.isEmpty || outputs.first == null) {
            for (final OrtValue? out in outputs) {
              try {
                out?.release();
              } catch (_) {}
            }
            nextToken = -1;
            break;
          }

          final OrtValue logitsVal = outputs.first!;
          try {
            if (k == suffixIds.length - 1) {
              nextToken = selectNextTokenFromOrtValue(
                logitsVal,
                1,
                temperature,
                generatedTokenIds,
              );
            }
          } finally {
            try {
              logitsVal.release();
            } catch (_) {}
          }

          if (ownsStepKv) {
            for (final OrtValue oldKv in stepKv.values) {
              try {
                oldKv.release();
              } catch (_) {}
            }
          }

          if (outputs.length == 1 + presentOutputNames.length) {
            final Map<String, OrtValue> nextKv = <String, OrtValue>{};
            for (int j = 0; j < presentOutputNames.length; j++) {
              final OrtValue? presentVal = outputs[1 + j];
              if (presentVal != null) {
                final String pkvKey = presentOutputNames[j]
                    .replaceFirst('present.', 'past_key_values.');
                nextKv[pkvKey] = presentVal;
              }
            }
            stepKv = nextKv;
            ownsStepKv = true;
          } else {
            for (int j = 1; j < outputs.length; j++) {
              try {
                outputs[j]?.release();
              } catch (_) {}
            }
            stepKv = <String, OrtValue>{};
            ownsStepKv = false;
            nextToken = -1;
            break;
          }
        }

        // Step C: Autoregressive generation loop
        for (int step = 0; step < maxTokens; step++) {
          if (nextToken == -1 || eosTokenIds.contains(nextToken)) {
            break;
          }

          // Stop on newline once dialogue tokens have been produced
          if (generatedTokenIds.isNotEmpty &&
              newlineTokenIds.contains(nextToken)) {
            break;
          }

          // Skip leading whitespace/newline tokens without recording them
          final bool isLeadingNewline = generatedTokenIds.isEmpty &&
              newlineTokenIds.contains(nextToken);

          if (!isLeadingNewline) {
            // Early stop: repetitive single token (3 in a row)
            if (generatedTokenIds.length >= 2 &&
                generatedTokenIds.last == nextToken &&
                generatedTokenIds[generatedTokenIds.length - 2] == nextToken) {
              break;
            }

            // Early stop: repetitive 2-token cycle (e.g. A B A B)
            if (generatedTokenIds.length >= 4 &&
                generatedTokenIds[generatedTokenIds.length - 1] ==
                    generatedTokenIds[generatedTokenIds.length - 3] &&
                generatedTokenIds[generatedTokenIds.length - 2] ==
                    generatedTokenIds[generatedTokenIds.length - 4] &&
                nextToken == generatedTokenIds[generatedTokenIds.length - 2]) {
              break;
            }

            generatedTokenIds.add(nextToken);
            if (generatedTokenIds.length >= maxTokens) {
              break;
            }
          }

          final int pos = prefixLen + suffixIds.length + step;
          final List<OrtValueTensor> allocs = <OrtValueTensor>[];
          final OrtValueTensor inTensor =
              OrtValueTensor.createTensorWithDataList(
            <int>[nextToken],
            const <int>[1, 1],
          );
          allocs.add(inTensor);

          final Map<String, OrtValue> inputs = <String, OrtValue>{
            inputIdsName: inTensor,
          };

          if (attentionMaskName != null && attentionMaskName.isNotEmpty) {
            final OrtValueTensor maskTensor =
                OrtValueTensor.createTensorWithDataList(
              List<int>.filled(pos + 1, 1),
              <int>[1, pos + 1],
            );
            allocs.add(maskTensor);
            inputs[attentionMaskName] = maskTensor;
          }

          if (positionIdsName != null && positionIdsName.isNotEmpty) {
            final OrtValueTensor posTensor =
                OrtValueTensor.createTensorWithDataList(
              <int>[pos],
              const <int>[1, 1],
            );
            allocs.add(posTensor);
            inputs[positionIdsName] = posTensor;
          }

          inputs.addAll(stepKv);

          List<OrtValue?> outputs;
          try {
            outputs = session.run(runOptions, inputs, requestedOutputs);
          } finally {
            for (final OrtValueTensor t in allocs) {
              try {
                t.release();
              } catch (_) {}
            }
          }

          if (outputs.isEmpty || outputs.first == null) {
            for (final OrtValue? out in outputs) {
              try {
                out?.release();
              } catch (_) {}
            }
            break;
          }

          final OrtValue logitsVal = outputs.first!;
          try {
            nextToken = selectNextTokenFromOrtValue(
              logitsVal,
              1,
              temperature,
              generatedTokenIds,
            );
          } finally {
            try {
              logitsVal.release();
            } catch (_) {}
          }

          if (ownsStepKv) {
            for (final OrtValue oldKv in stepKv.values) {
              try {
                oldKv.release();
              } catch (_) {}
            }
          }

          if (outputs.length == 1 + presentOutputNames.length) {
            final Map<String, OrtValue> nextKv = <String, OrtValue>{};
            for (int j = 0; j < presentOutputNames.length; j++) {
              final OrtValue? presentVal = outputs[1 + j];
              if (presentVal != null) {
                final String pkvKey = presentOutputNames[j]
                    .replaceFirst('present.', 'past_key_values.');
                nextKv[pkvKey] = presentVal;
              }
            }
            stepKv = nextKv;
            ownsStepKv = true;
          } else {
            for (int j = 1; j < outputs.length; j++) {
              try {
                outputs[j]?.release();
              } catch (_) {}
            }
            stepKv = <String, OrtValue>{};
            ownsStepKv = false;
            break;
          }
        }
      } finally {
        if (ownsStepKv) {
          for (final OrtValue kv in stepKv.values) {
            try {
              kv.release();
            } catch (_) {}
          }
        }
        try {
          runOptions.release();
        } catch (_) {}
      }

      return (
        tokenIds: generatedTokenIds,
        newPrefixKvAddresses: newPrefixKvAddresses,
        prefixLen: prefixLen,
      );
    }

    // Fallback path for models without KV cache inputs
    final List<int> allInputIds = <int>[...prefixIds, ...suffixIds];
    try {
      for (int step = 0; step < maxTokens; step++) {
        final List<OrtValueTensor> stepAllocations = <OrtValueTensor>[];
        final List<int> stepTokens = <int>[
          ...allInputIds,
          ...generatedTokenIds,
        ];
        final int stepSeqLen = stepTokens.length;
        final int totalSeqLen = stepSeqLen;
        final List<int> posList = List<int>.generate(stepSeqLen, (i) => i);

        final OrtValueTensor inputTensor =
            OrtValueTensor.createTensorWithDataList(
          stepTokens,
          <int>[1, stepSeqLen],
        );
        stepAllocations.add(inputTensor);

        final Map<String, OrtValue> inputs = <String, OrtValue>{
          inputIdsName: inputTensor,
        };

        if (attentionMaskName != null && attentionMaskName.isNotEmpty) {
          final OrtValueTensor maskTensor =
              OrtValueTensor.createTensorWithDataList(
            List<int>.filled(totalSeqLen, 1),
            <int>[1, totalSeqLen],
          );
          stepAllocations.add(maskTensor);
          inputs[attentionMaskName] = maskTensor;
        }

        if (positionIdsName != null && positionIdsName.isNotEmpty) {
          final OrtValueTensor posTensor =
              OrtValueTensor.createTensorWithDataList(
            posList,
            <int>[1, stepSeqLen],
          );
          stepAllocations.add(posTensor);
          inputs[positionIdsName] = posTensor;
        }

        if (pkvInputNames.isNotEmpty) {
          final OrtValueTensor emptyKv =
              OrtValueTensor.createTensorWithDataList(
            Float32List(0),
            const <int>[1, 2, 0, 64],
          );
          stepAllocations.add(emptyKv);
          for (final String pkvName in pkvInputNames) {
            inputs[pkvName] = emptyKv;
          }
        }

        List<OrtValue?> outputs;
        try {
          outputs = session.run(runOptions, inputs, requestedOutputs);
        } finally {
          for (final OrtValueTensor t in stepAllocations) {
            try {
              t.release();
            } catch (_) {}
          }
        }

        if (outputs.isEmpty || outputs.first == null) {
          for (final OrtValue? out in outputs) {
            try {
              out?.release();
            } catch (_) {}
          }
          break;
        }

        final OrtValue logitsVal = outputs.first!;
        final int nextToken;
        try {
          nextToken = selectNextTokenFromOrtValue(
            logitsVal,
            stepSeqLen,
            temperature,
            generatedTokenIds,
          );
        } finally {
          try {
            logitsVal.release();
          } catch (_) {}
        }

        for (int i = 1; i < outputs.length; i++) {
          try {
            outputs[i]?.release();
          } catch (_) {}
        }

        if (nextToken == -1 || eosTokenIds.contains(nextToken)) {
          break;
        }

        if (generatedTokenIds.isNotEmpty &&
            newlineTokenIds.contains(nextToken)) {
          break;
        }

        if (generatedTokenIds.length >= 2 &&
            generatedTokenIds.last == nextToken &&
            generatedTokenIds[generatedTokenIds.length - 2] == nextToken) {
          break;
        }

        if (generatedTokenIds.length >= 4 &&
            generatedTokenIds[generatedTokenIds.length - 1] ==
                generatedTokenIds[generatedTokenIds.length - 3] &&
            generatedTokenIds[generatedTokenIds.length - 2] ==
                generatedTokenIds[generatedTokenIds.length - 4] &&
            nextToken == generatedTokenIds[generatedTokenIds.length - 2]) {
          break;
        }

        generatedTokenIds.add(nextToken);
      }
    } finally {
      try {
        runOptions.release();
      } catch (_) {}
    }

    return (
      tokenIds: generatedTokenIds,
      newPrefixKvAddresses: null,
      prefixLen: prefixLen,
    );
  }

  /// Executes inference on the loaded native ONNX session.
  Future<String> _runNativeInference({
    required String prompt,
    required double temperature,
    required int maxTokens,
  }) async {
    if (_session == null || !_isNativeAvailable) return '';

    if (_tokenizer == null) {
      debugPrint('ONNX Native inference skipped: Tokenizer not loaded.');
      return '';
    }

    try {
      final int effectiveMaxTokens = maxTokens.clamp(8, maxTokensLimit);
      final int sessionAddress = _session!.address;

      List<int> prefixIds;
      List<int> suffixIds;
      Map<String, int>? cachedKvAddresses;
      String? prefixKey;

      if (_tokenizer is QwenBpeTokenizer) {
        final parts = extractPromptParts(prompt);
        final String prefixStr =
            '<|im_start|>system\nTranslate ${parts.language} comic dialogue to English. Output only English.<|im_end|>\n<|im_start|>user\n';
        final String suffixStr =
            '${parts.userContent.replaceAll('\n', ' ').trim()}<|im_end|>\n<|im_start|>assistant\n';
        prefixKey = prefixStr;

        if (_cachedPrefixKv != null &&
            (_cachedPrefixKv!.sessionAddress != sessionAddress ||
                _cachedPrefixKv!.prefixKey != prefixStr)) {
          _releaseCachedPrefixKv();
        }

        prefixIds = _tokenizer!.encode(prefixStr);
        suffixIds = _tokenizer!.encode(suffixStr);
        cachedKvAddresses = _cachedPrefixKv?.kvAddresses;
      } else {
        prefixIds = const <int>[];
        final String effectivePrompt = formatForModel(prompt, _tokenizer);
        suffixIds = _tokenizer!.encode(effectivePrompt);
      }

      if (prefixIds.isEmpty && suffixIds.isEmpty) return '';

      final Set<int> eosTokenIds = <int>{
        151645, // <|im_end|> (Qwen)
        151643, // <|endoftext|> (Qwen)
        1, // </s> (Gemma / Llama)
        2, // <eos>
        _tokenizer!.eosTokenId,
      };

      final Set<int> newlineTokenIds = <int>{
        198, // Qwen \n
        271, // Qwen \n\n
        if (_tokenizer != null) ..._tokenizer!.encode('\n'),
        if (_tokenizer != null) ..._tokenizer!.encode('\n\n'),
      };

      final result = await Isolate.run(
        () => _generateTokensInIsolate(
          sessionAddress: sessionAddress,
          prefixIds: prefixIds,
          suffixIds: suffixIds,
          cachedPrefixKvAddresses: cachedKvAddresses,
          temperature: temperature,
          maxTokens: effectiveMaxTokens,
          eosTokenIds: eosTokenIds,
          newlineTokenIds: newlineTokenIds,
        ),
      );

      if (result.newPrefixKvAddresses != null && prefixKey != null) {
        _cachedPrefixKv = _CachedPrefixKv(
          sessionAddress: sessionAddress,
          prefixKey: prefixKey,
          prefixLength: result.prefixLen,
          kvAddresses: result.newPrefixKvAddresses!,
        );
      }

      if (result.tokenIds.isEmpty) return '';

      return _tokenizer!.decode(result.tokenIds);
    } catch (e) {
      lastStatusMessage = 'Inference error: $e';
      debugPrint('ONNX Native inference error: $e');
      return '';
    }
  }

  /// Releases native ONNX resources and tokenizer safely.
  void dispose() {
    _releaseCachedPrefixKv();
    try {
      _session?.release();
    } catch (_) {}
    try {
      _sessionOptions?.release();
    } catch (_) {}
    try {
      _env?.release();
    } catch (_) {}

    _session = null;
    _sessionOptions = null;
    _env = null;
    _isNativeAvailable = false;
    _tokenizer = null;
    lastStatusMessage = null;
  }
}
