// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Shared contract for LLM tokenizers in Phantek Gallery.
abstract class LlmTokenizer {
  List<int> encode(String text);
  String decode(List<int> tokens);
  int get eosTokenId;
}

/// Pure Dart Byte-level Byte Pair Encoding (BPE) Tokenizer for Qwen 2 / 2.5 models.
///
/// Designed to load both uncompressed and gzip-compressed HuggingFace `tokenizer.json`
/// files without native C++ / SentencePiece normalizer dependencies.
class QwenBpeTokenizer implements LlmTokenizer {
  final Map<String, int> vocab;
  final Map<int, String> reverseVocab;
  final Map<(String, String), int> bpeRanks;
  final Map<String, int> specialTokens;
  final Map<int, String> specialTokensReverse;
  final int defaultEosTokenId;

  final Map<String, List<String>> _bpeCache = {};

  // Standard Qwen 2 / 2.5 special token IDs
  static const int imStartTokenId = 151644; // <|im_start|>
  static const int imEndTokenId = 151645; // <|im_end|>
  static const int endOfTextTokenId = 151643; // <|endoftext|>
  static const int padTokenId = 151665; // <|pad|>

  static const Map<String, int> defaultSpecialTokens = {
    '<|endoftext|>': 151643,
    '<|im_start|>': 151644,
    '<|im_end|>': 151645,
    '<|object_ref_start|>': 151646,
    '<|object_ref_end|>': 151647,
    '<|box_start|>': 151648,
    '<|box_end|>': 151649,
    '<|quad_start|>': 151650,
    '<|quad_end|>': 151651,
    '<|vision_start|>': 151652,
    '<|vision_end|>': 151653,
    '<|vision_pad|>': 151654,
    '<|image_pad|>': 151655,
    '<|video_pad|>': 151656,
  };

  /// GPT-2 / Qwen standard byte-to-character mapping table.
  static final Map<int, String> bytesToUnicode = _initBytesToUnicode();
  static final Map<String, int> unicodeToBytes = {
    for (final entry in bytesToUnicode.entries) entry.value: entry.key,
  };

  static Map<int, String> _initBytesToUnicode() {
    final Map<int, String> map = {};
    final List<int> bs = [];

    // '!' to '~' (33..126)
    for (int i = 33; i <= 126; i++) {
      bs.add(i);
    }
    // '¡' to '¬' (161..172)
    for (int i = 161; i <= 172; i++) {
      bs.add(i);
    }
    // '®' to 'ÿ' (174..255)
    for (int i = 174; i <= 255; i++) {
      bs.add(i);
    }

    final List<int> cs = List<int>.from(bs);
    int n = 0;
    for (int b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }

    for (int i = 0; i < bs.length; i++) {
      map[bs[i]] = String.fromCharCode(cs[i]);
    }
    return map;
  }

  /// Qwen 2 / 2.5 standard regex pattern for splitting text before BPE merging.
  static final RegExp _splitRegex = RegExp(
    r"'(?:[sS]|[tT]|[rR][eE]|[vV][eE]|[mM]|[lL][lL]|[dD])|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+",
    unicode: true,
  );

  QwenBpeTokenizer({
    required this.vocab,
    required this.reverseVocab,
    required this.bpeRanks,
    Map<String, int>? specialTokens,
    this.defaultEosTokenId = imEndTokenId,
  })  : specialTokens = Map<String, int>.from(specialTokens ?? defaultSpecialTokens),
        specialTokensReverse = {
          for (final e in (specialTokens ?? defaultSpecialTokens).entries) e.value: e.key,
        };

  @override
  int get eosTokenId => defaultEosTokenId;

  /// Loads and parses HuggingFace `tokenizer.json` from a JSON string.
  factory QwenBpeTokenizer.fromJsonString(String jsonStr) {
    final Map<String, dynamic> root = jsonDecode(jsonStr) as Map<String, dynamic>;
    final model = (root['model'] as Map<String, dynamic>?) ?? {};

    final Map<String, int> vocab = {};
    if (model['vocab'] is Map) {
      final v = model['vocab'] as Map;
      for (final entry in v.entries) {
        vocab[entry.key.toString()] = entry.value as int;
      }
    }

    final Map<int, String> reverseVocab = {
      for (final entry in vocab.entries) entry.value: entry.key,
    };

    final Map<(String, String), int> bpeRanks = {};
    if (model['merges'] is List) {
      final merges = model['merges'] as List;
      for (int i = 0; i < merges.length; i++) {
        final item = merges[i];
        if (item is String) {
          final spaceIdx = item.indexOf(' ');
          if (spaceIdx > 0) {
            bpeRanks[(item.substring(0, spaceIdx), item.substring(spaceIdx + 1))] = i;
          }
        } else if (item is List && item.length >= 2) {
          bpeRanks[(item[0].toString(), item[1].toString())] = i;
        }
      }
    }

    final Map<String, int> special = Map<String, int>.from(defaultSpecialTokens);
    if (root['added_tokens'] is List) {
      for (final item in root['added_tokens'] as List) {
        if (item is Map && item['id'] is int && item['content'] is String) {
          special[item['content'] as String] = item['id'] as int;
        }
      }
    }

    return QwenBpeTokenizer(
      vocab: vocab,
      reverseVocab: reverseVocab,
      bpeRanks: bpeRanks,
      specialTokens: special,
    );
  }

  /// Loads and decompresses gzipped bytes of `qwen_tokenizer.json.gz`.
  factory QwenBpeTokenizer.fromGzipBytes(List<int> gzBytes) {
    final decompressed = gzip.decode(gzBytes);
    final jsonStr = utf8.decode(decompressed);
    return QwenBpeTokenizer.fromJsonString(jsonStr);
  }

  static QwenBpeTokenizer? _cachedBundledTokenizer;

  /// Static helper to load the bundled asset `'assets/tokenizers/qwen_tokenizer.json.gz'`.
  /// Gracefully falls back to inspecting local filesystem paths for headless tests.
  static Future<QwenBpeTokenizer> loadBundledAsset({
    String assetPath = 'assets/tokenizers/qwen_tokenizer.json.gz',
    bool? runInIsolate,
  }) async {
    final bool useIsolate =
        runInIsolate ?? !Platform.environment.containsKey('FLUTTER_TEST');
    if (_cachedBundledTokenizer != null &&
        assetPath == 'assets/tokenizers/qwen_tokenizer.json.gz') {
      return _cachedBundledTokenizer!;
    }
    try {
      final byteData = await rootBundle.load(assetPath);
      final bytes = Uint8List.fromList(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
      final tok = useIsolate
          ? await Isolate.run(() => QwenBpeTokenizer.fromGzipBytes(bytes))
          : QwenBpeTokenizer.fromGzipBytes(bytes);
      if (assetPath == 'assets/tokenizers/qwen_tokenizer.json.gz') {
        _cachedBundledTokenizer = tok;
      }
      return tok;
    } catch (_) {
      final candidates = [
        assetPath,
        '../$assetPath',
        '../../$assetPath',
        p.join(Directory.current.path, assetPath),
      ];
      for (final candidate in candidates) {
        final file = File(candidate);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          final tok = useIsolate
              ? await Isolate.run(() => QwenBpeTokenizer.fromGzipBytes(bytes))
              : QwenBpeTokenizer.fromGzipBytes(bytes);
          if (assetPath == 'assets/tokenizers/qwen_tokenizer.json.gz') {
            _cachedBundledTokenizer = tok;
          }
          return tok;
        }
      }
      rethrow;
    }
  }

  List<String> _bpe(String token) {
    final cached = _bpeCache[token];
    if (cached != null) return cached;

    List<String> word = token.split('');
    if (word.length <= 1) {
      _bpeCache[token] = word;
      return word;
    }

    while (word.length > 1) {
      int minRank = 1 << 30;
      (String, String)? bestPair;

      for (int i = 0; i < word.length - 1; i++) {
        final pair = (word[i], word[i + 1]);
        final rank = bpeRanks[pair];
        if (rank != null && rank < minRank) {
          minRank = rank;
          bestPair = pair;
        }
      }

      if (bestPair == null) break;

      final List<String> newWord = [];
      int i = 0;
      while (i < word.length) {
        if (i < word.length - 1 &&
            word[i] == bestPair.$1 &&
            word[i + 1] == bestPair.$2) {
          newWord.add(bestPair.$1 + bestPair.$2);
          i += 2;
        } else {
          newWord.add(word[i]);
          i++;
        }
      }
      word = newWord;
    }

    if (_bpeCache.length < 50000) {
      _bpeCache[token] = word;
    }
    return word;
  }

  void _processPiece(String piece, List<int> ids) {
    if (piece.isEmpty) return;
    final bytes = utf8.encode(piece);
    final sb = StringBuffer();
    for (final b in bytes) {
      final mappedChar = bytesToUnicode[b];
      if (mappedChar != null) {
        sb.write(mappedChar);
      }
    }
    final mapped = sb.toString();
    final bpeTokens = _bpe(mapped);
    for (final t in bpeTokens) {
      final id = vocab[t];
      if (id != null) {
        ids.add(id);
      } else {
        for (int i = 0; i < t.length; i++) {
          final charId = vocab[t[i]];
          if (charId != null) {
            ids.add(charId);
          }
        }
      }
    }
  }

  List<int> _encodeChunk(String text) {
    final List<int> ids = [];
    final matches = _splitRegex.allMatches(text);
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        _processPiece(text.substring(lastIndex, match.start), ids);
      }
      _processPiece(match.group(0)!, ids);
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      _processPiece(text.substring(lastIndex), ids);
    }

    return ids;
  }

  @override
  List<int> encode(String text) {
    if (text.isEmpty) return const [];
    if (specialTokens.isEmpty) {
      return _encodeChunk(text);
    }

    final List<int> ids = [];
    final pattern = specialTokens.keys.map(RegExp.escape).join('|');
    final specialRegex = RegExp(pattern);
    final matches = specialRegex.allMatches(text);
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        ids.addAll(_encodeChunk(text.substring(lastIndex, match.start)));
      }
      final specialStr = match.group(0)!;
      final tokenId = specialTokens[specialStr];
      if (tokenId != null) {
        ids.add(tokenId);
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      ids.addAll(_encodeChunk(text.substring(lastIndex)));
    }

    return ids;
  }

  @override
  String decode(List<int> tokens) {
    if (tokens.isEmpty) return '';
    final List<int> bytes = [];

    for (final id in tokens) {
      final specialStr = specialTokensReverse[id];
      if (specialStr != null) {
        bytes.addAll(utf8.encode(specialStr));
        continue;
      }

      final tokenStr = reverseVocab[id];
      if (tokenStr != null) {
        for (int i = 0; i < tokenStr.length; i++) {
          final byte = unicodeToBytes[tokenStr[i]];
          if (byte != null) {
            bytes.add(byte);
          }
        }
      }
    }

    return utf8.decode(bytes, allowMalformed: true);
  }
}
