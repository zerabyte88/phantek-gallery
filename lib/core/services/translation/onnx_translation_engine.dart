// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnx_translation/onnx_translation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'lm_studio_translation_engine.dart';
import 'mlkit_translation_engine.dart';
import 'translation_models.dart';

/// Handler type for mocking or intercepting ONNX translation in tests.
typedef OnnxInferenceHandler = Future<String> Function(
  String text,
  String sourceLang,
  String targetLang,
);

/// 100% offline, on-device Helsinki-NLP (MarianMT / Opus-MT) ONNX translation engine.
///
/// Features:
/// - Singleton lifecycle managing loaded [OnnxModel] and [OrtSession] instances.
/// - Hybrid model loading: assets ([rootBundle]) or local filesystem ([File.readAsBytes] + [OrtSession.fromBuffer]).
/// - SentencePiece tokenizer & autoregressive generation loop.
/// - Clean comic dialogue formatting & punctuation spacing.
/// - Automatic release of previous sessions when switching languages.
/// - Built-in offline manga dialogue & SFX dictionary fallback when physical model binaries are not present.
class OnnxTranslationEngine {
  OnnxTranslationEngine._();
  static final OnnxTranslationEngine instance = OnnxTranslationEngine._();

  /// User-specified custom model directory overrides keyed by language code ('ja', 'zh', 'ko').
  final Map<String, String> _customModelDirs = {};

  /// Optional mock handler for headless testing and validation.
  OnnxInferenceHandler? mockInferenceHandler;

  /// Currently loaded language code (e.g. 'ja', 'zh', 'ko').
  String? _currentLoadedLang;
  String? get currentLoadedLanguage => _currentLoadedLang;

  /// Asset-based loaded OnnxModel instance.
  OnnxModel? _currentOnnxModel;

  /// Filesystem-based ONNX sessions.
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;

  /// Tokenizer vocabularies for filesystem-loaded models.
  Map<String, int>? _vocab;
  Map<int, String>? _reverseVocab;
  int _eosTokenId = 0;
  int _padTokenId = 0;
  int _unkTokenId = 1;

  /// Regular expression for detecting special tokens (e.g. `<2en>`, `<pad>`).
  final RegExp _specialTokenRegex = RegExp(r'<[^>]+>');

  /// Whether an ONNX model or session is currently active in memory.
  bool get isModelLoaded =>
      _currentOnnxModel != null || _encoderSession != null;

  /// Normalizes language code to standard 2-letter ISO code ('ja', 'zh', 'ko').
  static String normalizeLangCode(String langCode) {
    final lower = langCode.trim().toLowerCase();
    if (lower.startsWith('ja') || lower == 'japanese') return 'ja';
    if (lower.startsWith('zh') || lower == 'chinese') return 'zh';
    if (lower.startsWith('ko') || lower == 'korean') return 'ko';
    return lower;
  }

  /// Sets a custom directory for language [langCode].
  void setModelDirectory(String langCode, String directoryPath) {
    _customModelDirs[normalizeLangCode(langCode)] = directoryPath;
  }

  /// Retrieves the custom model directory for [langCode] if configured.
  String? getModelDirectory(String langCode) {
    return _customModelDirs[normalizeLangCode(langCode)];
  }

  /// Maps [TranslationSourceLanguage] to 2-letter language code.
  static String mapSourceLanguageToCode(TranslationSourceLanguage source) {
    switch (source) {
      case TranslationSourceLanguage.japanese:
        return 'ja';
      case TranslationSourceLanguage.korean:
        return 'ko';
      case TranslationSourceLanguage.chinese:
        return 'zh';
      case TranslationSourceLanguage.auto:
        return 'ja';
    }
  }

  /// Checks whether required ONNX model files are available for [langCode].
  Future<bool> isModelAvailable(String langCode) async {
    if (mockInferenceHandler != null) return true;

    final code = normalizeLangCode(langCode);

    // 1. Check custom configured directory
    final customDir = _customModelDirs[code];
    if (customDir != null && await _isFsModelValid(customDir)) {
      return true;
    }

    // 2. Check standard application documents & support paths
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final candidateDoc = p.join(docDir.path, 'models', 'onnx', code);
      if (await _isFsModelValid(candidateDoc)) return true;

      final supportDir = await getApplicationSupportDirectory();
      final candidateSupport = p.join(supportDir.path, 'models', 'onnx', code);
      if (await _isFsModelValid(candidateSupport)) return true;
    } catch (_) {}

    // 3. Check local project filesystem paths
    final localCandidates = [
      p.join('assets', 'models', 'translation', code),
      p.join('assets', 'models', 'translation', 'marian_${code}_en'),
      p.join('assets', 'onnx_model', code),
    ];
    for (final cand in localCandidates) {
      if (await _isFsModelValid(cand)) return true;
    }

    // 4. Check Flutter assets bundle
    final assetCandidates = [
      'assets/models/translation/$code',
      'assets/models/translation/marian_${code}_en',
      'assets/onnx_model/$code',
    ];
    for (final assetPath in assetCandidates) {
      if (await _isAssetModelValid(assetPath)) return true;
    }

    return false;
  }

  /// Verifies if a filesystem directory contains the necessary model files.
  Future<bool> _isFsModelValid(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return false;

      final enc = File(p.join(dirPath, 'encoder_model.onnx'));
      final dec = File(p.join(dirPath, 'decoder_model.onnx'));
      final vocab = File(p.join(dirPath, 'vocab.json'));

      return enc.existsSync() && dec.existsSync() && vocab.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Verifies if Flutter asset bundle contains the necessary model files.
  Future<bool> _isAssetModelValid(String basePath) async {
    try {
      final normalized = basePath.endsWith('/')
          ? basePath.substring(0, basePath.length - 1)
          : basePath;
      await rootBundle.load('$normalized/vocab.json');
      await rootBundle.load('$normalized/encoder_model.onnx');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads the ONNX model for [langCode], safely releasing any previous sessions.
  Future<bool> loadModel(String langCode) async {
    final code = normalizeLangCode(langCode);

    if (_currentLoadedLang == code && isModelLoaded) {
      return true;
    }

    // Release any previous sessions when switching languages
    await releaseCurrentSession();

    // 1. Check custom directory
    final customDir = _customModelDirs[code];
    if (customDir != null && await _isFsModelValid(customDir)) {
      final ok = await _loadFromFilesystem(customDir, code);
      if (ok) return true;
    }

    // 2. Check standard app paths
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final candDoc = p.join(docDir.path, 'models', 'onnx', code);
      if (await _isFsModelValid(candDoc)) {
        final ok = await _loadFromFilesystem(candDoc, code);
        if (ok) return true;
      }

      final supportDir = await getApplicationSupportDirectory();
      final candSupport = p.join(supportDir.path, 'models', 'onnx', code);
      if (await _isFsModelValid(candSupport)) {
        final ok = await _loadFromFilesystem(candSupport, code);
        if (ok) return true;
      }
    } catch (_) {}

    // 3. Check local filesystem project candidates
    final localCandidates = [
      p.join('assets', 'models', 'translation', code),
      p.join('assets', 'models', 'translation', 'marian_${code}_en'),
      p.join('assets', 'onnx_model', code),
    ];
    for (final cand in localCandidates) {
      if (await _isFsModelValid(cand)) {
        final ok = await _loadFromFilesystem(cand, code);
        if (ok) return true;
      }
    }

    // 4. Check assets via rootBundle & OnnxModel
    final assetCandidates = [
      'assets/models/translation/$code',
      'assets/models/translation/marian_${code}_en',
      'assets/onnx_model/$code',
    ];
    for (final assetPath in assetCandidates) {
      if (await _isAssetModelValid(assetPath)) {
        final ok = await _loadFromAssets(assetPath, code);
        if (ok) return true;
      }
    }

    return false;
  }

  /// Loads model sessions directly from local filesystem via [OrtSession.fromBuffer].
  Future<bool> _loadFromFilesystem(String dirPath, String langCode) async {
    try {
      final encFile = File(p.join(dirPath, 'encoder_model.onnx'));
      final decFile = File(p.join(dirPath, 'decoder_model.onnx'));
      final vocabFile = File(p.join(dirPath, 'vocab.json'));

      if (!encFile.existsSync() ||
          !decFile.existsSync() ||
          !vocabFile.existsSync()) {
        return false;
      }

      final encBytes = await encFile.readAsBytes();
      final decBytes = await decFile.readAsBytes();
      final vocabStr = await vocabFile.readAsString();

      String? tcfgStr;
      final tcfgFile = File(p.join(dirPath, 'tokenizer_config.json'));
      if (tcfgFile.existsSync()) {
        tcfgStr = await tcfgFile.readAsString();
      }

      String? gcfgStr;
      final gcfgFile = File(p.join(dirPath, 'generation_config.json'));
      if (gcfgFile.existsSync()) {
        gcfgStr = await gcfgFile.readAsString();
      }

      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();
      _encoderSession = OrtSession.fromBuffer(encBytes, sessionOptions);
      _decoderSession = OrtSession.fromBuffer(decBytes, sessionOptions);

      _parseVocabAndConfigs(vocabStr, tcfgStr, gcfgStr);
      _currentLoadedLang = langCode;
      debugPrint('[OnnxTranslationEngine] Loaded filesystem model for: $langCode');
      return true;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Failed loading filesystem model: $e');
      await releaseCurrentSession();
      return false;
    }
  }

  /// Loads model assets via [OnnxModel] and [rootBundle].
  Future<bool> _loadFromAssets(String assetBasePath, String langCode) async {
    try {
      final model = OnnxModel();
      await model.init(modelBasePath: assetBasePath);
      _currentOnnxModel = model;
      _currentLoadedLang = langCode;
      debugPrint('[OnnxTranslationEngine] Loaded asset model for: $langCode');
      return true;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Failed loading asset model: $e');
      await releaseCurrentSession();
      return false;
    }
  }

  /// Parses vocabulary and tokenizer configurations.
  void _parseVocabAndConfigs(
    String vocabJsonStr,
    String? tokenizerConfigStr,
    String? generationConfigStr,
  ) {
    final vocabMap = jsonDecode(vocabJsonStr) as Map<String, dynamic>;
    _vocab = vocabMap.map((k, v) => MapEntry(k, (v as num).toInt()));
    _reverseVocab =
        Map.fromEntries(_vocab!.entries.map((e) => MapEntry(e.value, e.key)));

    _eosTokenId = _reverseVocab!.entries
        .firstWhere(
          (e) => e.value == '</s>',
          orElse: () => const MapEntry(0, '</s>'),
        )
        .key;
    _unkTokenId = _reverseVocab!.entries
        .firstWhere(
          (e) => e.value == '<unk>',
          orElse: () => const MapEntry(1, '<unk>'),
        )
        .key;
    _padTokenId = _reverseVocab!.entries
        .firstWhere(
          (e) => e.value == '<pad>',
          orElse: () => MapEntry(
            (_vocab!['<pad>'] ?? -1) >= 0 ? _vocab!['<pad>']! : 0,
            '<pad>',
          ),
        )
        .key;

    if (tokenizerConfigStr != null) {
      try {
        final tc = jsonDecode(tokenizerConfigStr) as Map<String, dynamic>;
        if (tc.containsKey('pad_token') && _vocab!.containsKey(tc['pad_token'])) {
          _padTokenId = _vocab![tc['pad_token']]!;
        }
        if (tc.containsKey('unk_token') && _vocab!.containsKey(tc['unk_token'])) {
          _unkTokenId = _vocab![tc['unk_token']]!;
        }
      } catch (_) {}
    }

    if (generationConfigStr != null) {
      try {
        final gc = jsonDecode(generationConfigStr) as Map<String, dynamic>;
        if (gc.containsKey('eos_token_id')) {
          _eosTokenId = (gc['eos_token_id'] as num).toInt();
        } else if (gc.containsKey('eos_token') &&
            _vocab!.containsKey(gc['eos_token'])) {
          _eosTokenId = _vocab![gc['eos_token']]!;
        }
      } catch (_) {}
    }
  }

  /// Releases loaded model and session resources.
  Future<void> releaseCurrentSession() async {
    try {
      _currentOnnxModel?.release();
      _currentOnnxModel = null;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Error releasing OnnxModel: $e');
    }
    try {
      _encoderSession?.release();
      _encoderSession = null;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Error releasing OrtSession encoder: $e');
    }
    try {
      _decoderSession?.release();
      _decoderSession = null;
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] Error releasing OrtSession decoder: $e');
    }
    _vocab = null;
    _reverseVocab = null;
    _currentLoadedLang = null;
  }

  /// Releases all engine resources.
  Future<void> dispose() async {
    await releaseCurrentSession();
    try {
      OrtEnv.instance.release();
    } catch (_) {}
  }

  /// Tokenizes text for MarianMT/Opus-MT models with SentencePiece prefix matching.
  List<int> tokenize(String text) {
    if (_vocab == null) return [0];

    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return [_eosTokenId];

    final tokenIds = <int>[];
    final tokens = _vocab!.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    int pos = 0;
    while (pos < normalized.length) {
      final match = _specialTokenRegex.matchAsPrefix(normalized, pos);
      if (match != null) {
        final specialTok = match.group(0)!;
        if (_vocab!.containsKey(specialTok)) {
          tokenIds.add(_vocab![specialTok]!);
          pos += specialTok.length;
          while (pos < normalized.length && normalized[pos] == ' ') {
            pos++;
          }
          continue;
        }
      }

      bool matched = false;
      for (final tok in tokens) {
        if (tok.length > normalized.length - pos) continue;
        final substr = normalized.substring(pos, pos + tok.length);

        if (substr == tok) {
          tokenIds.add(_vocab![tok]!);
          pos += tok.length;
          matched = true;
          break;
        }

        // Handle SentencePiece whitespace prefixes (U+2581 ' ' or '▁')
        if (tok.startsWith(' ') || tok.startsWith('▁')) {
          final plainTok = tok.substring(1);
          if ((pos == 0 || normalized[pos - 1] == ' ') &&
              pos + plainTok.length <= normalized.length &&
              normalized.substring(pos, pos + plainTok.length) == plainTok) {
            tokenIds.add(_vocab![tok]!);
            pos += plainTok.length;
            matched = true;
            break;
          }
        }
      }

      if (!matched) {
        tokenIds.add(_unkTokenId);
        pos += 1;
      } else {
        while (pos < normalized.length && normalized[pos] == ' ') {
          pos++;
        }
      }
    }

    tokenIds.add(_eosTokenId);
    return tokenIds;
  }

  /// Softmax activation for logits vector.
  List<double> _softmax(List<double> logits) {
    final maxValue = logits.reduce(max);
    final exps = logits.map((l) => exp(l - maxValue)).toList();
    final sumExp = exps.fold<double>(0.0, (a, b) => a + b);
    return exps.map((e) => e / (sumExp == 0 ? 1.0 : sumExp)).toList();
  }

  /// Detokenizes generated token IDs into human-readable text.
  String detokenize(List<int> tokenIds) {
    if (_reverseVocab == null) return '';

    final tokens =
        tokenIds.map((id) => _reverseVocab![id] ?? '<unk>').toList();
    final buffer = StringBuffer();

    for (int i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      if (tok == '</s>' || tok == '<pad>') continue;

      if (tok.startsWith('<') && tok.endsWith('>')) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(tok);
        continue;
      }

      if (tok.startsWith(' ') || tok.startsWith('▁')) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(tok.substring(1));
      } else {
        buffer.write(tok);
      }
    }

    return buffer.toString().trim();
  }

  /// Runs autoregressive inference using native [OrtSession]s.
  Future<String> _runAutoregressiveLoop(
    String inputText, {
    int maxNewTokens = 60,
  }) async {
    final inputIds = tokenize(inputText);
    final seqLen = inputIds.length;
    final attentionMask = List<int>.filled(seqLen, 1);

    final inputTensor =
        OrtValueTensor.createTensorWithDataList(inputIds, [1, seqLen]);
    final attentionMaskTensor =
        OrtValueTensor.createTensorWithDataList(attentionMask, [1, seqLen]);

    final encoderOutputs = await _encoderSession!.runAsync(
      OrtRunOptions(),
      {
        'input_ids': inputTensor,
        'attention_mask': attentionMaskTensor,
      },
    );
    final encoderHiddenStates = encoderOutputs![0];

    final decoderInputIds = <int>[_padTokenId];
    final generatedIds = <int>[];

    for (int step = 0; step < maxNewTokens; step++) {
      final decInputTensor = OrtValueTensor.createTensorWithDataList(
        decoderInputIds,
        [1, decoderInputIds.length],
      );

      final decoderOutputs = await _decoderSession!.runAsync(
        OrtRunOptions(),
        {
          'input_ids': decInputTensor,
          'encoder_hidden_states': encoderHiddenStates!,
          'encoder_attention_mask': attentionMaskTensor,
        },
      );

      final logitsTensor = decoderOutputs![0];
      if (logitsTensor == null || logitsTensor.value == null) break;

      final raw = logitsTensor.value as List<dynamic>;
      final lastStepLogits = (raw[0] as List<dynamic>).last as List<dynamic>;
      final logits = lastStepLogits.map((e) => (e as num).toDouble()).toList();
      final probs = _softmax(logits);

      int nextToken = 0;
      double best = double.negativeInfinity;
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > best) {
          best = probs[i];
          nextToken = i;
        }
      }

      generatedIds.add(nextToken);
      if (nextToken == _eosTokenId) break;
      decoderInputIds.add(nextToken);
    }

    return detokenize(generatedIds);
  }

  /// Post-processes and cleans comic dialogue formatting and punctuation spacing.
  static String cleanComicDialogue(String text) {
    if (text.isEmpty) return text;

    var cleaned = text.trim();

    // Remove any special token markers
    cleaned = cleaned
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('</s>', '')
        .replaceAll('<s>', '')
        .replaceAll('<pad>', '')
        .replaceAll('<unk>', '');

    // Normalize whitespace & trim leading/trailing
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

    // Spacing before punctuation: remove spaces before . , ! ? : ; … ~
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\s+([.,!?:;…~’”\)])'),
      (m) => m[1]!,
    );

    // Spacing after punctuation: ensure single space if immediately followed by letter/digit
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([.,!?:;])([A-Za-z0-9])'),
      (m) => '${m[1]} ${m[2]}',
    );

    // Normalize spacing around parentheses and quotes
    cleaned = cleaned
        .replaceAll(RegExp(r'\(\s+'), '(')
        .replaceAll(RegExp(r'\s+\)'), ')')
        .replaceAll(RegExp(r'“\s+'), '“')
        .replaceAll(RegExp(r'\s+”'), '”');

    // Fix multiple exclamation/question mark spacing: "! ?" -> "!?"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([!?])\s+([!?])'),
      (m) => '${m[1]}${m[2]}',
    );

    // Capitalize standalone "i" and English contractions
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\bi\b'),
      (_) => 'I',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r"\bi'([a-z]+)\b", caseSensitive: false),
      (m) => "I'${m[1]}",
    );

    // Capitalize sentence start and after terminating punctuation (. ! ?)
    final sentencePattern = RegExp(r'(^|[.!?…]\s+)([a-z])');
    cleaned = cleaned.replaceAllMapped(
      sentencePattern,
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
    );

    return cleaned.trim();
  }

  /// Built-in offline manga dialogue & SFX dictionary to guarantee zero-crash fallback.
  static final Map<String, Map<String, String>> _mangaDictionary = {
    'ja': {
      'こんにちは': 'Hello',
      'こんばんは': 'Good evening',
      'おはよう': 'Good morning',
      'ありがとう': 'Thank you',
      'ありがとうございます': 'Thank you very much',
      'どういたしまして': "You're welcome",
      'すみません': 'Excuse me',
      'ごめんなさい': "I'm sorry",
      'ごめん': 'Sorry',
      '何？！': 'What?!',
      '何?!': 'What?!',
      'なに？！': 'What?!',
      'なに?!': 'What?!',
      '何？': 'What?',
      'なに？': 'What?',
      '何': 'What',
      'どうして': 'Why?',
      'なんで': 'Why?',
      'まさか': 'No way...',
      'うそ': 'No way!',
      '嘘': 'Lie!',
      '助けて': 'Help me!',
      '助けて！': 'Help me!',
      '大丈夫': 'Are you okay?',
      '大丈夫？': 'Are you okay?',
      '大丈夫だ': "I'm fine",
      'やめて': 'Stop it!',
      '待って': 'Wait!',
      '待って！': 'Wait!',
      'ちょっと待って': 'Hold on!',
      '誰だ': 'Who is it?',
      'だれだ': 'Who is it?',
      'バカ': 'Idiot!',
      'ばか': 'Idiot!',
      '馬鹿': 'Idiot!',
      'すごい': 'Amazing!',
      'スゴイ': 'Amazing!',
      '本当に': 'Really?',
      'マジで': 'Seriously?!',
      '行くぞ': "Let's go!",
      '行くよ': "Here I go!",
      '誰か': 'Someone...',
      '誰か...': 'Someone...',
      '早く': 'Hurry!',
      '逃げて': 'Run away!',
      'はい': 'Yes',
      'いいえ': 'No',
      'うん': 'Yeah',
      'ううん': 'No',
      'わかった': 'Understood',
      '了解': 'Roger',
      'ドキドキ': '*thump thump*',
      'ドクン': '*thump*',
      'ドカーン': '*KABOOM*',
      'ゴゴゴ': '*rumble*',
      'ざわ…ざわ…': '*murmur...*',
      'ニコニコ': '*grin*',
      'フッ': 'Heh',
      'ふっ': 'Hmph',
    },
    'ko': {
      '안녕': 'Hello',
      '안녕하세요': 'Hello',
      '감사합니다': 'Thank you',
      '고마워': 'Thanks',
      '미안': 'Sorry',
      '미안해': "I'm sorry",
      '죄송합니다': "I'm sorry",
      '뭐?!': 'What?!',
      '뭐야?!': 'What is this?!',
      '뭐야': 'What?',
      '뭐라고?!': 'What did you say?!',
      '왜': 'Why?',
      '설마': 'No way...',
      '거짓말': 'Lie!',
      '살려줘': 'Help me!',
      '살려줘!': 'Help me!',
      '도와줘': 'Help!',
      '괜찮아': "It's okay",
      '괜찮아?': 'Are you okay?',
      '하지 마': 'Stop it!',
      '기다려': 'Wait!',
      '잠깐': 'Hold on',
      '누구야': 'Who are you?',
      '바보': 'Fool!',
      '대박': 'Awesome!',
      '진짜': 'Really?',
      '진짜?!': 'Seriously?!',
      '가자': "Let's go!",
      '빨리': 'Hurry!',
      '도망쳐': 'Run!',
      '네': 'Yes',
      '아니요': 'No',
      '응': 'Yeah',
      '아니': 'No',
      '알겠어': 'Understood',
      '두근두근': '*pit-a-pat*',
      '쿵': '*THUD*',
      '콰광': '*CRASH*',
      '쓱': '*glide*',
      '하하': 'Haha',
      '훗': 'Hmph',
    },
    'zh': {
      '你好': 'Hello',
      '谢谢': 'Thank you',
      '非常感谢': 'Thank you very much',
      '不客气': "You're welcome",
      '对不起': "I'm sorry",
      '抱歉': 'Sorry',
      '不好意思': 'Excuse me',
      '什么？！': 'What?!',
      '什么?!': 'What?!',
      '什么？': 'What?',
      '怎么可能': 'Impossible!',
      '为什么': 'Why?',
      '救命': 'Help!',
      '救命！': 'Help!',
      '没事': "It's fine",
      '没事吧？': 'Are you okay?',
      '不要': "Don't!",
      '住手': 'Stop it!',
      '等等': 'Wait!',
      '等一下': 'Wait a moment!',
      '是谁': 'Who is it?',
      '笨蛋': 'Idiot!',
      '厉害': 'Incredible!',
      '真的吗': 'Really?',
      '走吧': "Let's go!",
      '快点': 'Hurry up!',
      '快逃': 'Run!',
      '是': 'Yes',
      '不是': 'No',
      '好': 'Okay',
      '明白了': 'Understood',
      '轰': '*BOOM*',
      '啪': '*SLAP*',
      '咚': '*THUMP*',
      '哈哈': 'Haha',
      '哼': 'Hmph',
    },
  };

  /// Looks up [text] in the built-in manga dictionary for [langCode].
  String? lookupDictionary(String text, String langCode) {
    final dict = _mangaDictionary[normalizeLangCode(langCode)];
    if (dict == null) return null;

    final trimmed = text.trim();
    if (dict.containsKey(trimmed)) return dict[trimmed];

    // Strip ending punctuation and lookup
    final stripped = trimmed.replaceAll(RegExp(r'[！？!?…。\s]+$'), '');
    if (dict.containsKey(stripped)) {
      final base = dict[stripped]!;
      if (trimmed.endsWith('?!') || trimmed.endsWith('？！')) return '$base?!';
      if (trimmed.endsWith('!') || trimmed.endsWith('！')) return '$base!';
      if (trimmed.endsWith('?') || trimmed.endsWith('？')) return '$base?';
      if (trimmed.endsWith('...') || trimmed.endsWith('…')) return '$base...';
      return base;
    }

    return null;
  }

  /// Translates comic dialogue text using Helsinki-NLP ONNX models.
  Future<String> translateMangaText({
    required String text,
    required TranslationSourceLanguage source,
    required TranslationTargetLanguage target,
  }) async {
    final cleaned = MlKitTranslationEngine.cleanMangaText(text);
    if (cleaned.isEmpty) return '';

    if (!LmStudioTranslationEngine.hasTranslatableDialogue(cleaned)) {
      return cleaned;
    }

    final effectiveSource = (source == TranslationSourceLanguage.auto)
        ? MlKitTranslationEngine.detectLanguageFromText(cleaned)
        : source;

    final langCode = mapSourceLanguageToCode(effectiveSource);

    // 1. Mock inference hook for unit tests
    if (mockInferenceHandler != null) {
      final mockRes =
          await mockInferenceHandler!(cleaned, langCode, 'en');
      return cleanComicDialogue(mockRes);
    }

    // 2. Try loading and running ONNX model
    try {
      final isAvailable = await isModelAvailable(langCode);
      if (isAvailable) {
        final loaded = await loadModel(langCode);
        if (loaded) {
          String rawResult = '';
          if (_currentOnnxModel != null) {
            rawResult = await _currentOnnxModel!.runModel(
              cleaned,
              maxNewTokens: 60,
            );
          } else if (_encoderSession != null && _decoderSession != null) {
            rawResult = await _runAutoregressiveLoop(
              cleaned,
              maxNewTokens: 60,
            );
          }

          if (rawResult.isNotEmpty) {
            return cleanComicDialogue(rawResult);
          }
        }
      }
    } catch (e) {
      debugPrint('[OnnxTranslationEngine] ONNX inference error: $e');
    }

    // 3. Fallback to built-in offline manga dialog & SFX dictionary
    final dictTranslation = lookupDictionary(cleaned, langCode);
    if (dictTranslation != null && dictTranslation.isNotEmpty) {
      return cleanComicDialogue(dictTranslation);
    }

    // If completely unable to translate, return cleaned input
    return cleaned;
  }
}
