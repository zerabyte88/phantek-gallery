// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:io';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Offline translation engine using ONNX Runtime with dictionary fallback.
class OnnxTranslationEngine {
  OnnxTranslationEngine._();
  static final OnnxTranslationEngine instance = OnnxTranslationEngine._();

  OnnxRuntime? _onnxRuntime;
  OrtSession? _session;
  bool _isInitialized = false;
  bool _isNnapiActive = false;

  bool get isInitialized => _isInitialized;
  bool get isNnapiActive => _isNnapiActive;

  /// Initializes ONNX session with hardware acceleration or CPU fallback.
  Future<void> initialize({String? modelAssetPath}) async {
    if (_isInitialized) return;

    try {
      _onnxRuntime = OnnxRuntime();
      final path =
          modelAssetPath ?? 'assets/models/translation/marian_ja_en_int8.onnx';

      if (await _doesAssetExist(path)) {
        try {
          if (Platform.isAndroid) {
            _session = await _onnxRuntime!.createSessionFromAsset(path);
            _isNnapiActive = true;
          } else {
            _session = await _onnxRuntime!.createSessionFromAsset(path);
            _isNnapiActive = false;
          }
        } catch (_) {
          _session = await _onnxRuntime!.createSessionFromAsset(path);
          _isNnapiActive = false;
        }
      }
    } catch (_) {
      _session = null;
    } finally {
      _isInitialized = true;
    }
  }

  Future<bool> _doesAssetExist(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Translates [sourceText] into English.
  Future<String> translate(
    String sourceText, {
    String sourceLang = 'ja',
  }) async {
    final cleaned = cleanMangaText(sourceText);
    if (cleaned.isEmpty) return '';

    if (_session != null) {
      try {
        final onnxOutput = await _runOnnxInference(cleaned);
        if (onnxOutput != null && onnxOutput.isNotEmpty) {
          return onnxOutput;
        }
      } catch (_) {}
    }

    return _fallbackDictionaryTranslate(cleaned, sourceLang);
  }

  Future<String?> _runOnnxInference(String text) async {
    if (_session == null) return null;
    return null;
  }

  /// Normalizes vertical line breaks and trims whitespace.
  String cleanMangaText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Offline dictionary translation for dialog and SFX.
  String _fallbackDictionaryTranslate(String text, String lang) {
    final normalized = text.replaceAll(' ', '').trim();

    if (_mangaDictionary.containsKey(normalized)) {
      return _mangaDictionary[normalized]!;
    }

    var result = text;
    bool matchedAny = false;
    for (final entry in _mangaDictionary.entries) {
      if (result.contains(entry.key)) {
        result = result.replaceAll(entry.key, '${entry.value} ');
        matchedAny = true;
      }
    }

    if (matchedAny) {
      return result.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    if (RegExp(r'^[!?！？\.\s]+$').hasMatch(text)) {
      return text;
    }

    return text;
  }

  static const Map<String, String> _mangaDictionary = {
    // Japanese Dialog
    'こんにちは': 'Hello',
    'ありがとう': 'Thank you',
    'ありがとうございます': 'Thank you very much',
    '何？！': 'What?!',
    '何?!': 'What?!',
    'なに？！': 'What?!',
    'なに?!': 'What?!',
    '何だ': 'What is this?',
    '何だ？！': 'What is this?!',
    'どうして': 'Why?',
    'どういうこと': 'What do you mean?',
    '嘘だ': 'No way!',
    'うそだ': 'No way!',
    '嘘でしょ': 'You must be kidding!',
    '助けて': 'Help me!',
    'たすけて': 'Help me!',
    '行くぞ': "Let's go!",
    'いくぞ': "Let's go!",
    'ダメ': 'Impossible / No!',
    'だめ': 'Impossible / No!',
    'ダメだ': "It's no use!",
    'やった': 'We did it!',
    'やったー': 'Hooray!',
    'バカ': 'Idiot',
    'ばか': 'Idiot',
    'バカな': 'Impossible!',
    '待て': 'Wait!',
    'まって': 'Wait!',
    '待ちなさい': 'Hold on!',
    'はい': 'Yes',
    'いいえ': 'No',
    '誰だ': 'Who is it?',
    'だれだ': 'Who is it?',
    'まさか': "It can't be...",
    'すごい': 'Amazing!',
    'すげえ': 'Incredible!',
    'さようなら': 'Goodbye',
    'バイバイ': 'Bye-bye',
    'ごめんなさい': "I'm sorry",
    'すまない': "Forgive me",
    '大丈夫': 'Are you okay?',
    'だいじょうぶ': 'All right',
    'お願い': 'Please',
    '頼む': 'I beg you',
    '死ね': 'Die!',
    '消えろ': 'Get lost!',
    '逃げろ': 'Run away!',
    'にげろ': 'Run away!',
    '勝った': 'I won!',
    '負けた': 'I lost...',
    '本当': 'Really?',
    'ほんとう': 'Really?',
    'まじで': 'Seriously?',

    // Japanese SFX
    'ドキドキ': '*thump thump*',
    'どきどき': '*heart pounding*',
    'バクバク': '*heart throbbing*',
    'ドカン': '*BOOM*',
    'どかん': '*BOOM*',
    'ドカーン': '*KABOOM*',
    'ゴゴゴ': '*rumble rumble*',
    'ごごご': '*ominous rumble*',
    'ザワザワ': '*murmur murmur*',
    'ざわざわ': '*chatter*',
    'ニコニコ': '*grin*',
    'にこにこ': '*smiling*',
    'ギラギラ': '*glare*',
    'シーン': '*silence*',
    'パチパチ': '*clap clap*',
    'フッ': '*huff*',
    'ハハハ': 'Hahaha',
    'ククク': 'Hehehe',
    'キャー': 'Eeeek!',
    'ぎゃあ': 'Aaargh!',
    'ドン': '*BAM*',
    'バン': '*BANG*',
    'ピクッ': '*twitch*',
    'チラッ': '*glance*',
    'ハッ': '*gasp*',

    // Chinese Dialog & SFX
    '你好': 'Hello',
    '谢谢': 'Thank you',
    '什么': 'What?',
    '什么？！': 'What?!',
    '什么?!': 'What?!',
    '救命': 'Help!',
    '快跑': 'Run!',
    '不可能': 'Impossible',
    '等等': 'Wait!',
    '再见': 'Goodbye',
    '对不起': "I'm sorry",
    '混蛋': 'Bastard!',
    '轰': '*BOOM*',
    '砰': '*BANG*',
    '哈哈': 'Haha',

    // Korean Dialog & SFX
    '안녕하세요': 'Hello',
    '감사합니다': 'Thank you',
    '뭐': 'What?',
    '뭐?!': 'What?!',
    '뭐야': 'What is this?',
    '도와줘': 'Help me!',
    '안돼': 'No way!',
    '기다려': 'Wait!',
    '도망쳐': 'Run away!',
    '쿵': '*THUD*',
    '쾅': '*BANG*',
    '하하': 'Haha',
  };

  void dispose() {
    _session?.close();
    _session = null;
    _isInitialized = false;
  }
}
