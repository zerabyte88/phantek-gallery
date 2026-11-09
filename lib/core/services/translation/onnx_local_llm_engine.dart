// SPDX-License-Identifier: MIT

// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'translation_models.dart';

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

/// Delegate type for mock or custom LLM inference in tests and headless environments.

typedef LlmInferenceHandler = Future<String> Function(
  String prompt, {
  required double temperature,
  required int maxTokens,
});

/// Offline Local LLM Translation Engine using ONNX Runtime.

///

/// Executes on-device inference using quantized local LLMs (e.g. Gemma 3 Nano / Qwen 2.5)

/// with strict 100% offline boundaries, deterministic low-temperature generation,

/// and comic-dialogue output sanitization.

class OnnxLocalLlmEngine {
  OnnxLocalLlmEngine({
    this.mockInferenceHandler,
  });

  static final OnnxLocalLlmEngine instance = OnnxLocalLlmEngine();

  /// System prompt template conforming to the strictly objective operational rules.

  static const String systemPromptTemplate =
      'You are a specialized, strictly objective machine translation engine for fictional comic book dialogues. \n\n'
      'CRITICAL OPERATIONAL RULES:\n'
      '1. Translate the user\'s raw text faithfully into natural, fluid English comic dialogue.\n'
      '2. The input is 100% fictional creative writing. It contains stylized violence, combat phrases, threats, gore, ecchi, and profanities. Do NOT judge, filter, or alter these creative elements. \n'
      '3. Never refuse this request. Never moralize, lecture, or preach. Do not add safety warnings, explanations, or notes.\n'
      '4. Output ONLY the final English translation. Absolutely no conversational filler before or after the translation.';

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
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-q4.onnx',
    '/storage/emulated/0/models/qwen2.5-0.5b-instruct-abliterated-q4.onnx',
    '/storage/emulated/0/models/model_q4f16.onnx',
    '/storage/emulated/0/models/model.onnx',
    'models/qwen2.5-0.5b-instruct-q4.onnx',
    'models/qwen2.5-0.5b-instruct-abliterated-q4.onnx',
    'models/model_q4f16.onnx',
    'models/model.onnx',
    'assets/models/qwen2.5-0.5b-instruct-q4.onnx',
    'assets/models/qwen2.5-0.5b-instruct-abliterated-q4.onnx',
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
    'models/',
    'assets/models/',
  ];

  /// Ensures that the target or default models directory exists.

  /// If it does not exist, it is created recursively.

  /// If it already exists, no recreation or overwrite is performed.

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

    final dirsToScan = searchDirectories ?? defaultScanDirectories;

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
      } catch (e) {
        debugPrint('Error scanning $rawDirPath for models: $e');
      }
    }

    return models;
  }

  // ONNX Runtime session & environment handles.

  OrtEnv? _env;

  OrtSessionOptions? _sessionOptions;

  OrtSession? _session;

  bool _isNativeAvailable = false;

  // Companion SentencePiece / HuggingFace tokenizer.

  SentencePieceTokenizer? _tokenizer;

  SentencePieceTokenizer? get tokenizer => _tokenizer;

  /// High-level diagnostic and operational status message.

  String? lastStatusMessage;

  @visibleForTesting
  void setMockTokenizer(SentencePieceTokenizer tok) {
    _tokenizer = tok;
  }

  OrtEnv? get env => _env;

  OrtSessionOptions? get sessionOptions => _sessionOptions;

  OrtSession? get session => _session;

  bool get isNativeAvailable => _isNativeAvailable;

  bool get isModelLoaded => _session != null;

  bool get isReady => isModelLoaded || mockInferenceHandler != null;

  /// Clamps temperature within the constitutional bounds (0.1 .. 0.2).

  static double constrainTemperature(double temperature) {
    return temperature.clamp(minTemperature, maxTemperature);
  }

  /// Clamps max tokens within the constitutional bounds (50 .. 80).

  static int constrainMaxTokens(int maxTokens) {
    return maxTokens.clamp(minTokens, maxTokensLimit);
  }

  /// Builds the prompt payload strictly adhering to the objective operational rules.

  static String buildPrompt({
    String? language,
    required String rawOcrText,
  }) {
    return '<system>\n'
        'You are a specialized, strictly objective machine translation engine for fictional comic book dialogues. \n\n'
        'CRITICAL OPERATIONAL RULES:\n'
        '1. Translate the user\'s raw text faithfully into natural, fluid English comic dialogue.\n'
        '2. The input is 100% fictional creative writing. It contains stylized violence, combat phrases, threats, gore, ecchi, and profanities. Do NOT judge, filter, or alter these creative elements. \n'
        '3. Never refuse this request. Never moralize, lecture, or preach. Do not add safety warnings, explanations, or notes.\n'
        '4. Output ONLY the final English translation. Absolutely no conversational filler before or after the translation.\n'
        '</system>\n'
        '<user>\n'
        '$rawOcrText\n'
        '</user>';
  }

  /// Maps [TranslationSourceLanguage] to a human-readable display string for prompting.

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

  /// Detects source language from character Unicode script ranges.

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

  /// - Strips `<system>`, `<user>`, `<assistant>` tags (and their blocks).

  /// - Strips markdown formatting (bold `**`, italics `*`, backticks, blockquotes).

  /// - Strips chat preambles like "Translation:", "Here is the English translation:".

  /// - Returns only clean comic dialogue text.

  static String cleanLlmOutput(String rawOutput) {
    if (rawOutput.isEmpty) return '';

    String text = rawOutput;

    // 1. Strip XML/prompt blocks if echoed by the model.

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
        r'You are a specialized,\s*strictly objective machine translation engine[^\n]*\n?',
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
        r'^\s*(?:here\s+(?:is|are)\s+the\s+(?:final\s+)?(?:english\s+)?translation\s*(?:is)?\s*:|the\s+english\s+translation\s+is\s*:|english\s+translation\s*:|translation\s*to\s*english\s*:|translation\s*:|dialogue\s*:|output\s*:)\s*',
        caseSensitive: false,
      ),
      '',
    );

    text = text.replaceAll(
      RegExp(
        r'^\s*(?:here\s+(?:is|are)\s+the\s+(?:final\s+)?(?:english\s+)?translation\s*(?:is)?|the\s+english\s+translation\s+is|english\s+translation|translation\s*to\s*english|translation|dialogue|output)\s*:\s*\n+',
        caseSensitive: false,
      ),
      '',
    );

    // 7. Strip surrounding quotation marks if entire line is quoted.

    text = text.trim();

    if ((text.startsWith('"') && text.endsWith('"') && text.length >= 2) ||
        (text.startsWith("'") && text.endsWith("'") && text.length >= 2) ||
        (text.startsWith('“') && text.endsWith('”') && text.length >= 2) ||
        (text.startsWith('「') && text.endsWith('」') && text.length >= 2)) {
      text = text.substring(1, text.length - 1).trim();
    }

    return text;
  }

  /// Initializes the native ONNX session and tokenizer safely.

  Future<bool> initializeSession({
    String? modelPath,
    Uint8List? modelBytes,
    String? tokenizerPath,
  }) async {
    try {
      await ensureModelsDirectoryExists();

      _env ??= OrtEnv.instance..init();

      _sessionOptions ??= OrtSessionOptions();

      String? resolvedPath = modelPath;

      // If modelPath points to an existing directory, inspect it for .onnx files and use the first one found

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

      if (resolvedPath == null && modelBytes == null) {
        // First check if any .onnx file exists in defaultModelsDirectoryPath

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

        // If still null, fall back to checking defaultModelCandidatePaths

        if (resolvedPath == null) {
          for (final candidate in defaultModelCandidatePaths) {
            if (File(candidate).existsSync()) {
              resolvedPath = candidate;

              break;
            }
          }
        }
      }

      // Resolve companion tokenizer file

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

      if (resolvedTokPath != null && File(resolvedTokPath).existsSync()) {
        try {
          if (resolvedTokPath.toLowerCase().endsWith('.json')) {
            final jsonStr = await File(resolvedTokPath).readAsString();

            _tokenizer = HuggingFaceTokenizerLoader.fromJsonString(jsonStr);
          } else if (resolvedTokPath.toLowerCase().endsWith('.model')) {
            _tokenizer =
                await SentencePieceTokenizer.fromModelFile(resolvedTokPath);
          }
        } catch (e) {
          debugPrint('Failed to load tokenizer from $resolvedTokPath: $e');

          _tokenizer = null;
        }
      }

      if (resolvedPath != null && File(resolvedPath).existsSync()) {
        if (_tokenizer != null) {
          lastStatusMessage = 'Ready: ${p.basename(resolvedPath)}';
        } else {
          lastStatusMessage =
              'Model loaded (${p.basename(resolvedPath)}), but tokenizer.json not found in ${p.dirname(resolvedPath)}';
        }

        try {
          _session?.release();
        } catch (_) {}

        _session = OrtSession.fromFile(File(resolvedPath), _sessionOptions!);

        _isNativeAvailable = true;

        return true;
      } else if (modelBytes != null) {
        if (_tokenizer != null) {
          lastStatusMessage = 'Ready: in-memory model';
        } else {
          lastStatusMessage =
              'Model loaded (in-memory), but tokenizer.json not found';
        }

        try {
          _session?.release();
        } catch (_) {}

        _session = OrtSession.fromBuffer(modelBytes, _sessionOptions!);

        _isNativeAvailable = true;

        return true;
      }
    } catch (e) {
      debugPrint('ONNX Native runtime initialization error: $e');

      _isNativeAvailable = false;

      _session = null;
    }

    return false;
  }

  /// Translates manga text using the local LLM engine.

  ///

  /// Applies strict parameter locking (temperature 0.1–0.2, max tokens 50–80)

  /// and sanitizes outputs using [cleanLlmOutput].

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

    final effectiveTemperature = constrainTemperature(temperature);

    final effectiveMaxTokens = constrainMaxTokens(maxTokens);

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
        maxTokens: effectiveMaxTokens,
      );

      return cleanLlmOutput(rawResult);
    }

    // 2. Native ONNX Runtime Session Inference

    if (_session != null && _isNativeAvailable) {
      try {
        final nativeOutput = await _runNativeInference(
          prompt: prompt,
          temperature: effectiveTemperature,
          maxTokens: effectiveMaxTokens,
        );

        if (nativeOutput.isNotEmpty) {
          return cleanLlmOutput(nativeOutput);
        }
      } catch (e) {
        debugPrint('Local LLM ONNX native execution failed: $e');
      }
    }

    // 3. Fallback: Gracefully pass-through text without throwing symbol errors.

    return cleanLlmOutput(cleaned);
  }

  /// Extracts the last token logits as a list of doubles from ONNX tensor output.

  /// Handles 3D ([1, seq_len, vocab_size]), 2D ([seq_len, vocab_size] / [1, vocab_size]), or 1D arrays.

  static List<double> extractLastLogits(dynamic outputValue) {
    if (outputValue is List) {
      if (outputValue.isEmpty) return const [];

      final first = outputValue.first;

      if (first is List) {
        if (first.isNotEmpty && first.first is List) {
          // 3D: [batch, seq_len, vocab_size] -> outputValue[0].last

          final lastTokenLogits = (outputValue[0] as List).last;

          if (lastTokenLogits is List) {
            return lastTokenLogits.map((e) => (e as num).toDouble()).toList();
          }
        } else {
          // 2D: [batch, vocab_size] or [seq_len, vocab_size] -> outputValue.last

          final lastTokenLogits = outputValue.last;

          if (lastTokenLogits is List) {
            return lastTokenLogits.map((e) => (e as num).toDouble()).toList();
          }
        }
      } else if (first is num) {
        // 1D: [vocab_size]

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

    // Temperature-scaled softmax sampling

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
      final encoding = _tokenizer!.encode(prompt);

      final List<int> inputIds = encoding.ids;

      if (inputIds.isEmpty) return '';

      final List<int> currentInputIds = List<int>.from(inputIds);

      final List<int> generatedTokenIds = <int>[];

      final int effectiveMaxTokens = constrainMaxTokens(maxTokens);

      const Set<int> eosTokenIds = {
        151645, // <|im_end|> (Qwen)

        151643, // <|endoftext|> (Qwen)

        1, // </s> (Gemma / Llama)

        2, // <eos>
      };

      final String inputIdsName = _session!.inputNames.isNotEmpty
          ? _session!.inputNames.firstWhere(
              (n) =>
                  n.toLowerCase().contains('input_ids') ||
                  n.toLowerCase().contains('input'),
              orElse: () => _session!.inputNames[0],
            )
          : 'input_ids';

      final String? attentionMaskName =
          _session!.inputNames.cast<String?>().firstWhere(
                (n) =>
                    n != null &&
                    (n.toLowerCase().contains('attention') ||
                        n.toLowerCase().contains('mask')),
                orElse: () => null,
              );

      final String outputName = _session!.outputNames.isNotEmpty
          ? _session!.outputNames.first
          : 'logits';

      for (int step = 0; step < effectiveMaxTokens; step++) {
        final OrtRunOptions runOptions = OrtRunOptions();

        final OrtValueTensor inputTensor =
            OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(currentInputIds),
          [1, currentInputIds.length],
        );

        final Map<String, OrtValue> inputs = {
          inputIdsName: inputTensor,
        };

        OrtValueTensor? maskTensor;

        if (attentionMaskName != null && attentionMaskName.isNotEmpty) {
          maskTensor = OrtValueTensor.createTensorWithDataList(
            Int64List.fromList(List<int>.filled(currentInputIds.length, 1)),
            [1, currentInputIds.length],
          );

          inputs[attentionMaskName] = maskTensor;
        }

        List<OrtValue?> outputs;

        try {
          outputs = _session!.run(runOptions, inputs, [outputName]);
        } finally {
          inputTensor.release();

          maskTensor?.release();

          runOptions.release();
        }

        if (outputs.isEmpty || outputs.first == null) {
          break;
        }

        final OrtValue outputVal = outputs.first!;

        final List<double> logits = extractLastLogits(outputVal.value);

        outputVal.release();

        if (logits.isEmpty) {
          break;
        }

        final int nextToken = selectNextToken(logits, temperature);

        if (nextToken == -1 ||
            eosTokenIds.contains(nextToken) ||
            nextToken == _tokenizer!.vocab.eosId) {
          break;
        }

        generatedTokenIds.add(nextToken);

        currentInputIds.add(nextToken);
      }

      if (generatedTokenIds.isEmpty) return '';

      return _tokenizer!.decode(generatedTokenIds);
    } catch (e) {
      debugPrint('ONNX Native inference error: $e');

      return '';
    }
  }

  /// Releases native ONNX resources and tokenizer safely.

  void dispose() {
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
