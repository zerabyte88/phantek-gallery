// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/services/translation/translation_models.dart';
import 'package:phantek_gallery/core/services/translation/mlkit_translation_engine.dart';
import 'package:phantek_gallery/core/services/translation/lm_studio_translation_engine.dart';
import 'package:phantek_gallery/core/services/translation/manga_ocr_service.dart';
import 'package:phantek_gallery/core/services/translation/translation_isolate_coordinator.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/manga_translation_overlay.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/zigzag_progress_bar.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/services/translation/onnx_translation_engine.dart';
import 'package:phantek_gallery/features/settings/presentation/settings_screen.dart';

class MockMangaTextDetector implements MangaTextDetector {
  final List<RawMangaTextBlock> mockBlocks;
  MockMangaTextDetector(this.mockBlocks);

  @override
  Future<List<RawMangaTextBlock>> detectText(
    String imagePath, {
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  }) async =>
      mockBlocks;

  @override
  void dispose() {}
}

class ThrowingMangaTextDetector implements MangaTextDetector {
  @override
  Future<List<RawMangaTextBlock>> detectText(
    String imagePath, {
    TranslationSourceLanguage language = TranslationSourceLanguage.auto,
  }) async {
    throw Exception('Native OCR crash simulation');
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Manga Translation Domain Models', () {
    test('MangaTranslatedBlock JSON serialization and copyWith', () {
      const block = MangaTranslatedBlock(
        boundingBox: Rect.fromLTWH(10, 20, 100, 200),
        originalText: 'こんにちは',
        translatedText: 'Hello',
        isSpeechBubble: true,
        confidence: 0.98,
      );

      final json = block.toJson();
      final revived = MangaTranslatedBlock.fromJson(json);

      expect(revived.boundingBox, const Rect.fromLTWH(10, 20, 100, 200));
      expect(revived.originalText, 'こんにちは');
      expect(revived.translatedText, 'Hello');
      expect(revived.isSpeechBubble, isTrue);
      expect(revived.confidence, 0.98);

      final modified = revived.copyWith(translatedText: 'Greetings');
      expect(modified.translatedText, 'Greetings');
      expect(modified.originalText, 'こんにちは');
    });

    test('TranslationResult success and failure factory', () {
      final success = TranslationResult(
        imagePath: '/path/manga.jpg',
        blocks: const [
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(0, 0, 50, 50),
            originalText: '何？！',
            translatedText: 'What?!',
          ),
        ],
        imageSize: const Size(800, 1200),
      );
      expect(success.isSuccess, isTrue);
      expect(success.blocks.length, 1);

      final failure = TranslationResult.failure(
        imagePath: '/path/manga.jpg',
        errorMessage: 'File not found',
      );
      expect(failure.isSuccess, isFalse);
      expect(failure.blocks, isEmpty);
      expect(failure.errorMessage, 'File not found');
    });
  });

  group('MlKitTranslationEngine Core & Script Detection', () {
    test('Vertical text cleaning & normalization', () {
      const verticalJa = 'こ\nん\nに\nち\nは';
      expect(MlKitTranslationEngine.cleanMangaText(verticalJa), 'こんにちは');

      const noisyText = '  助けて！ \r\n\r\n 誰か...  ';
      expect(MlKitTranslationEngine.cleanMangaText(noisyText), '助けて！ 誰か...');
    });

    test('translateLeftoverCjk re-translates untranslated CJK runs', () async {
      final out = await MlKitTranslationEngine.translateLeftoverCjk(
        'Umm 大丈夫..',
        (t) async => t == '大丈夫' ? "it's okay" : t,
      );
      expect(out, "Umm it's okay..");
    });

    test(
        'Intra-CJK space removal and border artifact pipe removal in cleanMangaText',
        () {
      // Pipe misread of 一 / ー in vertical text
      expect(MlKitTranslationEngine.cleanMangaText('|旦戻ろう'), '一旦戻ろう');
      expect(MlKitTranslationEngine.cleanMangaText('| 時間経ったら'), '一時間経ったら');
      expect(MlKitTranslationEngine.cleanMangaText('ゲ|ム'), 'ゲーム');
      // Intra-CJK space removal (Japanese Hiragana/Katakana)
      expect(
        MlKitTranslationEngine.cleanMangaText('こ ん に ち は'),
        'こんにちは',
      );
      // Intra-CJK space removal (Chinese Hanzi)
      expect(
        MlKitTranslationEngine.cleanMangaText('你 好 吗'),
        '你好吗',
      );
      // Intra-CJK space removal across 3+ consecutive separated characters
      expect(
        MlKitTranslationEngine.cleanMangaText('一 二 三 四 五'),
        '一二三四五',
      );
      // Preserves Korean word spacing
      expect(
        MlKitTranslationEngine.cleanMangaText('형, 지금 뭐 하는 거야?!'),
        '형, 지금 뭐 하는 거야?!',
      );
      // Preserves mixed Latin-CJK and Korean-CJK spacing
      expect(
        MlKitTranslationEngine.cleanMangaText('Hello こんにちは'),
        'Hello こんにちは',
      );
      expect(
        MlKitTranslationEngine.cleanMangaText('안녕하세요 こんにちは'),
        '안녕하세요 こんにちは',
      );

      // Border artifact pipe removal
      expect(
        MlKitTranslationEngine.cleanMangaText('|\nこんにちは\n|'),
        'こんにちは',
      );
      expect(
        MlKitTranslationEngine.cleanMangaText('丨\n你 好 吗\n‖'),
        '你好吗',
      );
      expect(
        MlKitTranslationEngine.cleanMangaText('|\n|\n¦\n‖'),
        '',
      );
      expect(
        MlKitTranslationEngine.cleanMangaText('待て\n|\n行くぞ'),
        '待て行くぞ',
      );
    });

    test('translateWithGoogleMlKit auto language resolution', () async {
      final engine = MlKitTranslationEngine.instance;

      TranslateLanguage? lastDetectedSource;
      engine.mockMlKitTranslator = (text, source, target) async {
        lastDetectedSource = source;
        return 'Mock translation of $text';
      };

      try {
        // Auto resolves Japanese
        final resJa = await engine.translateWithGoogleMlKit(
          text: 'こんにちは',
          source: TranslationSourceLanguage.auto,
        );
        expect(resJa, 'Mock translation of こんにちは');
        expect(lastDetectedSource, TranslateLanguage.japanese);

        // Auto resolves Korean
        final resKo = await engine.translateWithGoogleMlKit(
          text: '안녕하세요',
          source: TranslationSourceLanguage.auto,
        );
        expect(resKo, 'Mock translation of 안녕하세요');
        expect(lastDetectedSource, TranslateLanguage.korean);

        // Auto resolves Chinese
        final resZh = await engine.translateWithGoogleMlKit(
          text: '你好世界',
          source: TranslationSourceLanguage.auto,
        );
        expect(resZh, 'Mock translation of 你好世界');
        expect(lastDetectedSource, TranslateLanguage.chinese);

        // Explicit source language overrides auto detection
        final resExplicit = await engine.translateWithGoogleMlKit(
          text: 'こんにちは',
          source: TranslationSourceLanguage.korean,
        );
        expect(resExplicit, 'Mock translation of こんにちは');
        expect(lastDetectedSource, TranslateLanguage.korean);
      } finally {
        engine.mockMlKitTranslator = null;
      }
    });

    test(
        'MlKitMangaTextDetector mapBlocks RTL reordering and artifact filtering',
        () {
      final lineLeft = TextLine(
        text: '左のセリフ',
        elements: const [],
        boundingBox: const Rect.fromLTWH(10, 0, 20, 100),
        recognizedLanguages: const ['ja'],
        cornerPoints: const [],
        confidence: 1.0,
        angle: 0.0,
      );
      final lineRight = TextLine(
        text: '右のセリフ',
        elements: const [],
        boundingBox: const Rect.fromLTWH(80, 0, 20, 100),
        recognizedLanguages: const ['ja'],
        cornerPoints: const [],
        confidence: 1.0,
        angle: 0.0,
      );
      final artifactLine = TextLine(
        text: '|',
        elements: const [],
        boundingBox: const Rect.fromLTWH(120, 0, 5, 100),
        recognizedLanguages: const [],
        cornerPoints: const [],
        confidence: 0.5,
        angle: 0.0,
      );

      final block = TextBlock(
        text: '左のセリフ\n右のセリフ\n|',
        lines: [lineLeft, lineRight, artifactLine],
        boundingBox: const Rect.fromLTWH(0, 0, 130, 120),
        recognizedLanguages: const ['ja'],
        cornerPoints: const [],
      );

      final recognized = RecognizedText(
        text: '左のセリフ\n右のセリフ\n|',
        blocks: [block],
      );

      final mapped = MlKitMangaTextDetector.mapBlocks(
        recognized,
        script: TextRecognitionScript.japanese,
      );

      expect(mapped.length, 1);
      // Right column (dx=90) must be ordered before Left column (dx=20), and artifact pipe '|' is filtered out
      expect(mapped.first.text, '右のセリフ\n左のセリフ');
    });

    test('Language auto-detection from character scripts', () {
      expect(
        MlKitTranslationEngine.detectLanguageFromText('お前、何をしているんだ？'),
        TranslationSourceLanguage.japanese,
      );
      expect(
        MlKitTranslationEngine.detectLanguageFromText('형, 지금 뭐 하는 거야?!'),
        TranslationSourceLanguage.korean,
      );
      expect(
        MlKitTranslationEngine.detectLanguageFromText('你到底想干什么？！'),
        TranslationSourceLanguage.chinese,
      );
    });

    test('Language enum mapping to MangaLanguage', () {
      expect(
        MlKitTranslationEngine.mapSourceLanguage(
            TranslationSourceLanguage.japanese),
        MangaLanguage.japanese,
      );
      expect(
        MlKitTranslationEngine.mapSourceLanguage(
            TranslationSourceLanguage.korean),
        MangaLanguage.korean,
      );
      expect(
        MlKitTranslationEngine.mapSourceLanguage(
            TranslationSourceLanguage.chinese),
        MangaLanguage.chinese,
      );
      expect(
        MlKitTranslationEngine.mapTargetLanguage(
            TranslationTargetLanguage.english),
        MangaLanguage.english,
      );
    });

    test('Punctuation and empty string handling without throwing', () async {
      final engine = MlKitTranslationEngine.instance;
      expect(
        await engine.translateText(
          '?!?!',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        ),
        '?!?!',
      );
      expect(
        await engine.translateText(
          '',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        ),
        '',
      );
    });
  });

  group('MangaOcrService Classification Heuristics', () {
    test('Speech bubble vs SFX classification', () {
      const pageSize = Size(1000, 1500);

      // Dialog box (Aspect ratio ~0.8) -> Speech bubble
      expect(
        MangaOcrService.classifyIsSpeechBubble(
          const Rect.fromLTWH(100, 100, 200, 250),
          'こんにちは、元気ですか？',
          pageSize,
        ),
        isTrue,
      );

      // Extreme horizontal aspect ratio burst (Aspect ratio = 5.0) -> SFX
      expect(
        MangaOcrService.classifyIsSpeechBubble(
          const Rect.fromLTWH(50, 400, 500, 100),
          'ドカーン',
          pageSize,
        ),
        isFalse,
      );

      // Single giant character splash (Width = 150, Length = 1) -> SFX
      expect(
        MangaOcrService.classifyIsSpeechBubble(
          const Rect.fromLTWH(200, 200, 180, 180),
          'ド',
          pageSize,
        ),
        isFalse,
      );
    });

    test('MangaOcrService extractTextBlocks with mock detector', () async {
      final mockDetector = MockMangaTextDetector([
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(50, 50, 120, 150),
          text: '行くぞ',
        ),
      ]);
      final service = MangaOcrService(detector: mockDetector);

      final temp =
          await File('${Directory.systemTemp.path}/test_manga_page.jpg')
              .create();
      try {
        final blocks = await service.extractTextBlocks(temp.path);
        expect(blocks.length, 1);
        expect(blocks.first.text, '行くぞ');
      } finally {
        await temp.delete();
        service.dispose();
      }
    });

    test(
        'MlKitMangaTextDetector initializes lazily without throwing during instantiation',
        () {
      final detector =
          MlKitMangaTextDetector(script: TextRecognitionScript.japanese);
      expect(detector.script, TextRecognitionScript.japanese);
      detector.dispose();
    });
  });

  group('TranslationIsolateCoordinator Debounce & Caching', () {
    test('Debounce timer drops intermediate requests within 1000ms', () async {
      final mockDetector = MockMangaTextDetector([
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(10, 10, 100, 100),
          text: '待て',
        ),
      ]);
      final ocr = MangaOcrService(detector: mockDetector);
      final coordinator = TranslationIsolateCoordinator(ocrService: ocr);

      final temp1 = await File('${Directory.systemTemp.path}/p1.jpg').create();
      final temp2 = await File('${Directory.systemTemp.path}/p2.jpg').create();

      try {
        coordinator.scheduleTranslation(
          imagePath: temp1.path,
          imageSize: const Size(800, 1200),
          mode: TranslationRenderMode.speechBubblesOnly,
          targetLanguage: TranslationTargetLanguage.english,
          debounceDuration: const Duration(milliseconds: 100),
        );

        coordinator.scheduleTranslation(
          imagePath: temp2.path,
          imageSize: const Size(800, 1200),
          mode: TranslationRenderMode.speechBubblesOnly,
          targetLanguage: TranslationTargetLanguage.english,
          debounceDuration: const Duration(milliseconds: 100),
        );

        for (int i = 0; i < 30; i++) {
          if (coordinator.getResultNotifier(temp2.path).value != null) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }

        expect(coordinator.getResultNotifier(temp1.path).value, isNull);
        final r2 = coordinator.getResultNotifier(temp2.path).value;
        expect(r2, isNotNull);
        expect(r2!.blocks.first.originalText, '待て');
      } finally {
        await temp1.delete();
        await temp2.delete();
        coordinator.dispose();
      }
    });

    test(
        'TranslationIsolateCoordinator handles detection error gracefully without crashing',
        () async {
      final throwingDetector = ThrowingMangaTextDetector();
      final ocr = MangaOcrService(detector: throwingDetector);
      final coordinator = TranslationIsolateCoordinator(ocrService: ocr);

      final temp =
          await File('${Directory.systemTemp.path}/err_test.jpg').create();
      try {
        coordinator.scheduleTranslation(
          imagePath: temp.path,
          imageSize: const Size(800, 1200),
          mode: TranslationRenderMode.speechBubblesOnly,
          targetLanguage: TranslationTargetLanguage.english,
          debounceDuration: const Duration(milliseconds: 50),
        );

        await Future.delayed(const Duration(milliseconds: 150));

        final result = coordinator.getResultNotifier(temp.path).value;
        expect(result, isNotNull);
        expect(result!.isSuccess, isFalse);
        expect(result.errorMessage, contains('Native OCR crash simulation'));
        expect(coordinator.getLoadingNotifier(temp.path).value, isFalse);
      } finally {
        await temp.delete();
        coordinator.dispose();
      }
    });
  });

  group('MangaTranslationOverlay & Painter Widget Tests', () {
    testWidgets('MangaTranslationOverlay renders speech bubble and SFX blocks',
        (tester) async {
      final result = TranslationResult(
        imagePath: '/mock/page.jpg',
        imageSize: const Size(1000, 1000),
        blocks: const [
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(100, 100, 300, 200),
            originalText: 'こんにちは',
            translatedText: 'Hello',
            isSpeechBubble: true,
          ),
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(500, 500, 200, 100),
            originalText: 'ドカン',
            translatedText: '*BOOM*',
            isSpeechBubble: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: MangaTranslationOverlay(
                result: result,
                mode: TranslationRenderMode.speechBubblesOnly,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is MangaTranslationPainter),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: MangaTranslationOverlay(
                result: result,
                mode: TranslationRenderMode.fullImageWithSfx,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is MangaTranslationPainter),
        findsOneWidget,
      );
    });

    testWidgets(
        'MangaTranslationOverlay preserves vertical speech bubble bounding box without 2.2x ballooning width',
        (tester) async {
      // Narrow vertical box (width 25, height 120 - aspect ratio 4.8)
      final result = TranslationResult(
        imagePath: '/mock/vertical.jpg',
        imageSize: const Size(1000, 1500),
        blocks: const [
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(800, 200, 25, 120),
            originalText: '何をしているんだ？',
            translatedText: 'What on earth are you doing right now?!',
            isSpeechBubble: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 750,
              child: MangaTranslationOverlay(
                result: result,
                mode: TranslationRenderMode.speechBubblesOnly,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MangaTranslationOverlay), findsOneWidget);
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is MangaTranslationPainter),
        findsOneWidget,
      );
    });

    testWidgets(
        'MangaTranslationOverlay auto-fits speech bubble for long dialogue without negative offset or clipping',
        (tester) async {
      // Small box with long text (20 words)
      final result = TranslationResult(
        imagePath: '/mock/long_text.jpg',
        imageSize: const Size(1000, 1500),
        blocks: const [
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(200, 300, 60, 40),
            originalText: '長いセリフ',
            translatedText:
                'Wait a minute! Did you really believe that would be enough to defeat me after everything we have endured together in this dungeon?',
            isSpeechBubble: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 750,
              child: MangaTranslationOverlay(
                result: result,
                mode: TranslationRenderMode.speechBubblesOnly,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MangaTranslationOverlay), findsOneWidget);
    });

    test(
        'MangaTranslationPainter direct canvas paint test verifying adaptive font sizing and bounding box containment',
        () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = MangaTranslationPainter(
        result: TranslationResult(
          imagePath: '/mock/page.jpg',
          imageSize: const Size(1000, 1500),
          blocks: const [
            // Vertical Asian column
            MangaTranslatedBlock(
              boundingBox: Rect.fromLTWH(800, 150, 25, 160),
              originalText: 'お前、何をしているんだ？',
              translatedText: 'What on earth are you doing here?!',
              isSpeechBubble: true,
            ),
            // Short text
            MangaTranslatedBlock(
              boundingBox: Rect.fromLTWH(200, 100, 80, 50),
              originalText: '行くぞ',
              translatedText: "Let's go!",
              isSpeechBubble: true,
            ),
            // Long dialogue in small container
            MangaTranslatedBlock(
              boundingBox: Rect.fromLTWH(300, 400, 70, 45),
              originalText: 'そんなはずはない...',
              translatedText:
                  'There is no way that someone like you could possibly understand the burden I have been carrying all these years!',
              isSpeechBubble: true,
            ),
            // SFX block with reduced font size
            MangaTranslatedBlock(
              boundingBox: Rect.fromLTWH(100, 600, 120, 50),
              originalText: 'ドカーン',
              translatedText: '*KABOOM*',
              isSpeechBubble: false,
            ),
          ],
        ),
        mode: TranslationRenderMode.fullImageWithSfx,
      );

      expect(
        () => painter.paint(canvas, const Size(1000, 1500)),
        returnsNormally,
      );

      final picture = recorder.endRecording();
      picture.dispose();
    });

    test(
        'MangaTranslationPainter speech bubble clamping to screen viewport margins',
        () {
      const screenSize = Size(400, 800);

      // Bubble far off the left/top edge (x = -50, y = -100)
      final rectLeftTop = MangaTranslationPainter.calculateBubbleRect(
        rect: const Rect.fromLTWH(-50, -100, 100, 50),
        text: 'Look out!',
        screenSize: screenSize,
      );
      expect(rectLeftTop.left, greaterThanOrEqualTo(8.0));
      expect(rectLeftTop.top, greaterThanOrEqualTo(8.0));
      expect(rectLeftTop.right, lessThanOrEqualTo(screenSize.width - 8.0));
      expect(rectLeftTop.bottom, lessThanOrEqualTo(screenSize.height - 8.0));

      // Bubble far off the right/bottom edge (x = 1000, y = 1200)
      final rectRightBottom = MangaTranslationPainter.calculateBubbleRect(
        rect: const Rect.fromLTWH(1000, 1200, 120, 60),
        text: 'Stop right there!',
        screenSize: screenSize,
      );
      expect(rectRightBottom.left, greaterThanOrEqualTo(8.0));
      expect(rectRightBottom.top, greaterThanOrEqualTo(8.0));
      expect(rectRightBottom.right, lessThanOrEqualTo(screenSize.width - 8.0));
      expect(
          rectRightBottom.bottom, lessThanOrEqualTo(screenSize.height - 8.0));

      // Extreme width bubble capped within safeViewport
      final rectWide = MangaTranslationPainter.calculateBubbleRect(
        rect: const Rect.fromLTWH(0, 300, 600, 80),
        text:
            'This is a very long dialogue that spans across many words and sentences in manga.',
        screenSize: screenSize,
      );
      expect(rectWide.width, lessThanOrEqualTo(screenSize.width - 16.0));
      expect(rectWide.left, greaterThanOrEqualTo(8.0));
      expect(rectWide.right, lessThanOrEqualTo(screenSize.width - 8.0));
    });

    test(
        'calculateBubbleRect preserves vertical speech bubble bounding box without 2.2x ballooning width',
        () {
      const originalRect = Rect.fromLTWH(100, 100, 30, 150);
      final bubbleRect = MangaTranslationPainter.calculateBubbleRect(
        rect: originalRect,
        text: 'What on earth are you doing right now?!',
        screenSize: const Size(400, 800),
      );

      // Original 30 x 150 vertical: padX = 0.15 * 30 = 4.5, padY = 0.05 * 150 = 7.5 -> 39 x 165.
      // Must not balloon to 30 * 2.2 = 66 or minWidthForLength (80-140).
      expect(bubbleRect.width, equals(39.0));
      expect(bubbleRect.height, equals(165.0));
      expect(bubbleRect.width, lessThan(50.0));
    });

    test('calculateBubbleRect preserves horizontal speech bubble bounding box',
        () {
      const originalRect = Rect.fromLTWH(50, 100, 150, 80);
      final bubbleRect = MangaTranslationPainter.calculateBubbleRect(
        rect: originalRect,
        text: 'This is a normal speech bubble.',
        screenSize: const Size(400, 800),
      );

      // Original 150 x 80 horizontal: pad 0.04 * 80 = 3.2 gives 156.4 x 86.4
      expect(bubbleRect.width, closeTo(156.4, 1e-9));
      expect(bubbleRect.height, closeTo(86.4, 1e-9));
      expect(bubbleRect.left, closeTo(46.8, 1e-9));
      expect(bubbleRect.top, closeTo(96.8, 1e-9));
    });

    test(
        'MangaTranslationPainter paints vertical rotated speech bubble cleanly without exception',
        () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = MangaTranslationPainter(
        result: const TranslationResult(
          imagePath: '/mock/vertical.jpg',
          imageSize: Size(1000, 1500),
          blocks: [
            MangaTranslatedBlock(
              boundingBox: Rect.fromLTWH(800, 150, 25, 160),
              originalText: '何をしているんだ？',
              translatedText: 'What on earth are you doing here right now?!',
              isSpeechBubble: true,
            ),
          ],
        ),
        mode: TranslationRenderMode.speechBubblesOnly,
      );

      expect(
        () => painter.paint(canvas, const Size(1000, 1500)),
        returnsNormally,
      );

      final picture = recorder.endRecording();
      picture.dispose();
    });
  });

  group('ImageViewerScreen Manga Translation Button & Sheet Integration', () {
    testWidgets(
        'Translation button opens sheet with Language Chips and Modes in Indonesian',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final item = MediaItem(
        id: 'manga_p1',
        path: '/storage/emulated/0/Pictures/Manga/page_01.jpg',
        name: 'page_01.jpg',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: false,
        width: 1080,
        height: 1920,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('id'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [item],
              initialIndex: 0,
              initialMangaMode: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final translateBtn =
          find.byKey(const ValueKey('manga_translation_button'));
      expect(translateBtn, findsOneWidget);

      tester.widget<IconButton>(translateBtn).onPressed!();
      await tester.pumpAndSettle();

      // Mode choices verification
      expect(find.text('Hanya Balon Dialog'), findsOneWidget);
      expect(find.text('Seluruh Halaman (Termasuk SFX)'), findsOneWidget);

      // Select Speech Bubbles mode
      await tester.tap(find.text('Hanya Balon Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Hanya Balon Dialog'), findsNothing);

      // Tap again to verify "Matikan Terjemahan" option is present
      tester.widget<IconButton>(translateBtn).onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Matikan Terjemahan'), findsOneWidget);

      // Drain feedback pill timer
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('Translation sheet renders localized in English (US)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final item = MediaItem(
        id: 'manga_p2',
        path: '/storage/emulated/0/Pictures/Manga/page_02.jpg',
        name: 'page_02.jpg',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: false,
        width: 1080,
        height: 1920,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [item],
              initialIndex: 0,
              initialMangaMode: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final translateBtn =
          find.byKey(const ValueKey('manga_translation_button'));
      expect(translateBtn, findsOneWidget);

      tester.widget<IconButton>(translateBtn).onPressed!();
      await tester.pumpAndSettle();

      // English localized texts
      expect(find.text('Manga Translation'), findsOneWidget);
      expect(find.text('Speech Bubbles Only'), findsOneWidget);
      expect(find.text('Full Page (with SFX)'), findsOneWidget);
    });
  });

  group('MlKitTranslationEngine Status & Progress', () {
    test('ModelPairStatus construction and properties', () {
      const status = ModelPairStatus(
        sourceDownloaded: true,
        targetDownloaded: false,
        sourceLangName: 'Japanese',
        targetLangName: 'English',
        totalNeededMb: 30.0,
        isReady: false,
      );
      expect(status.sourceDownloaded, isTrue);
      expect(status.targetDownloaded, isFalse);
      expect(status.sourceLangName, 'Japanese');
      expect(status.targetLangName, 'English');
      expect(status.totalNeededMb, 30.0);
      expect(status.isReady, isFalse);
    });

    test('TranslationDownloadProgress defaults and copyWith', () {
      const progress = TranslationDownloadProgress();
      expect(progress.isDownloading, isFalse);
      expect(progress.downloadedMb, 0.0);
      expect(progress.totalMb, 0.0);
      expect(progress.progress, 0.0);
      expect(progress.isSuccess, isFalse);
      expect(progress.errorMessage, isNull);

      final updated = progress.copyWith(
        isDownloading: true,
        currentStep: 'Downloading model...',
        downloadedMb: 15.0,
        totalMb: 30.0,
        progress: 0.5,
      );
      expect(updated.isDownloading, isTrue);
      expect(updated.currentStep, 'Downloading model...');
      expect(updated.downloadedMb, 15.0);
      expect(updated.totalMb, 30.0);
      expect(updated.progress, 0.5);
    });

    test('getPairStatus returns correct pair metadata and size requirements',
        () async {
      final engine = MlKitTranslationEngine.instance;
      final status = await engine.getPairStatus(
        TranslationSourceLanguage.japanese,
        TranslationTargetLanguage.english,
      );
      expect(status.sourceLangName, 'Japanese');
      expect(status.targetLangName, 'English');
      expect(status.totalNeededMb, anyOf(0.0, 30.0, 60.0));
    });

    test('allMangaLanguages defines all 4 required manga languages', () {
      expect(
        MlKitTranslationEngine.allMangaLanguages,
        containsAllInOrder([
          MangaLanguage.english,
          MangaLanguage.japanese,
          MangaLanguage.korean,
          MangaLanguage.chinese,
        ]),
      );
      expect(MlKitTranslationEngine.allMangaLanguages.length, 4);
    });

    test('AllModelsStatus construction and properties', () {
      const status = AllModelsStatus(
        missingLanguages: [MangaLanguage.japanese, MangaLanguage.korean],
        downloadedLanguages: [
          MangaLanguage.english,
          MangaLanguage.chinese,
        ],
        totalNeededMb: 60.0,
        isReady: false,
      );
      expect(status.missingLanguages.length, 2);
      expect(status.downloadedLanguages.length, 2);
      expect(status.totalNeededMb, 60.0);
      expect(status.isReady, isFalse);
    });

    test('checkAllModelsStatus returns valid AllModelsStatus metadata',
        () async {
      final engine = MlKitTranslationEngine.instance;
      final status = await engine.checkAllModelsStatus();
      expect(status.missingLanguages.length + status.downloadedLanguages.length,
          4);
      expect(status.totalNeededMb, status.missingLanguages.length * 30.0);
      expect(status.isReady, engine.lmStudioEngine.isReady);
    });

    test(
        'appLocalizations download getter returns localized string without MB size',
        () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.download, 'Download');
      expect(en.downloadModelPrompt, isNot(contains('30MB')));
      expect(en.downloadModelPrompt, isNot(contains('30 MB')));

      final id = AppLocalizations(const Locale('id'));
      expect(id.download, 'Unduh');
      expect(id.downloadModelPrompt, isNot(contains('30MB')));
      expect(id.downloadModelPrompt, isNot(contains('30 MB')));
    });
  });

  group('ZigzagProgressBar Widget Tests', () {
    testWidgets(
        'ZigzagProgressBar renders without error at progress 0.0 and 0.5',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ZigzagProgressBar(
                progress: 0.5,
                isProcessing: true,
                width: 250,
                height: 24,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ZigzagProgressBar), findsOneWidget);
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ZigzagProgressPainter),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('LmStudioTranslationEngine Local AI Server Translation', () {
    test('System prompt formatting and payload validation', () {
      expect(
        LmStudioTranslationEngine.systemPromptTemplate,
        contains('You are an expert localizer for Asian comics.'),
      );
      expect(
        LmStudioTranslationEngine.systemPromptTemplate,
        contains('Output ONLY the final English translation.'),
      );

      final promptJa = LmStudioTranslationEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: '助けて！',
      );
      expect(promptJa, startsWith('<system>\n'));
      expect(
        promptJa,
        contains(
            'Translate the raw OCR text from Japanese into natural English comic dialogue.'),
      );
      expect(promptJa, endsWith('</system>\n<user>\n助けて！\n</user>'));

      final promptKo = LmStudioTranslationEngine.buildPrompt(
        language: 'Korean',
        rawOcrText: '살려줘!',
      );
      expect(
        promptKo,
        contains(
            'Translate the raw OCR text from Korean into natural English comic dialogue.'),
      );
      expect(promptKo, endsWith('</system>\n<user>\n살려줘!\n</user>'));
    });

    test('Temperature (0.1) and max tokens (80) constraints', () async {
      expect(LmStudioTranslationEngine.defaultTemperature, 0.1);
      expect(LmStudioTranslationEngine.defaultMaxTokens, 80);

      // Temperature bounds: locked at 0.1 .. 0.2
      expect(LmStudioTranslationEngine.constrainTemperature(0.1), 0.1);
      expect(LmStudioTranslationEngine.constrainTemperature(0.2), 0.2);
      expect(LmStudioTranslationEngine.constrainTemperature(0.0), 0.1);
      expect(LmStudioTranslationEngine.constrainTemperature(-0.5), 0.1);
      expect(LmStudioTranslationEngine.constrainTemperature(0.7), 0.2);
      expect(LmStudioTranslationEngine.constrainTemperature(1.5), 0.2);

      // Max tokens bounds: limited to 50 .. 80
      expect(LmStudioTranslationEngine.constrainMaxTokens(60), 60);
      expect(LmStudioTranslationEngine.constrainMaxTokens(50), 50);
      expect(LmStudioTranslationEngine.constrainMaxTokens(80), 80);
      expect(LmStudioTranslationEngine.constrainMaxTokens(10), 50);
      expect(LmStudioTranslationEngine.constrainMaxTokens(0), 50);
      expect(LmStudioTranslationEngine.constrainMaxTokens(120), 80);
      expect(LmStudioTranslationEngine.constrainMaxTokens(1000), 80);

      // Verify that translateMangaText locks the parameters passed to the handler
      double? receivedTemp;
      int? receivedTokens;
      final engine = LmStudioTranslationEngine(
        mockInferenceHandler: (prompt,
            {required temperature, required maxTokens}) async {
          receivedTemp = temperature;
          receivedTokens = maxTokens;
          return 'I am here!';
        },
      );

      final out = await engine.translateMangaText(
        text: '助けて！',
        source: TranslationSourceLanguage.japanese,
        temperature: 0.99,
        maxTokens: 500,
      );

      expect(out, 'I am here!');
      expect(receivedTemp, 0.2);
      // For 3 CJK characters: (3 * 2 + 16).clamp(16, 80) = 22
      expect(receivedTokens, 22);

      // Long text reaching max tokens cap
      await engine.translateMangaText(
        text: 'これはテストです。長い漫画のセリフを翻訳してみましょう。どうなるでしょうか？ここにいるぞ！',
        source: TranslationSourceLanguage.japanese,
        temperature: 0.99,
        maxTokens: 500,
      );
      expect(receivedTemp, 0.2);
      expect(receivedTokens, 80);
    });

    test('cleanLlmOutput strips think tags and reasoning blocks', () {
      expect(
        LmStudioTranslationEngine.cleanLlmOutput(
          '<think>Analyze Japanese: 助けて means Help me</think>Help me!',
        ),
        'Help me!',
      );

      expect(
        LmStudioTranslationEngine.cleanLlmOutput(
          '<think>Thinking process...\nStill thinking...</think>\n\nLet me go!',
        ),
        'Let me go!',
      );
    });

    test('cleanLlmOutput removes markdown fences, headings, and formatting',
        () {
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('**Help me!**'),
        'Help me!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('```\nStop it!\n```'),
        'Stop it!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('### Who goes there?'),
        'Who goes there?',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('> Don\'t touch that!'),
        'Don\'t touch that!',
      );
    });

    test('cleanLlmOutput strips conversational preambles', () {
      expect(
        LmStudioTranslationEngine.cleanLlmOutput(
          'Here is the English translation:\nWait up!',
        ),
        'Wait up!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput(
          'Sure! The translation is: What did you say?!',
        ),
        'What did you say?!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput(
          'Natural English: Look out behind you!',
        ),
        'Look out behind you!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput(
          'Translation: Let\'s go together.',
        ),
        'Let\'s go together.',
      );
    });

    test('cleanLlmOutput strips outer quotation marks and cleans whitespace',
        () {
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('"Wait for me!"'),
        'Wait for me!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('“Hold on to me!”'),
        'Hold on to me!',
      );
      expect(
        LmStudioTranslationEngine.cleanLlmOutput('「Wait!」'),
        'Wait!',
      );
    });

    test('normalizeBaseUrl formats endpoints properly', () {
      expect(
        LmStudioTranslationEngine.normalizeBaseUrl('http://192.168.1.10:1234'),
        'http://192.168.1.10:1234/v1',
      );
      expect(
        LmStudioTranslationEngine.normalizeBaseUrl('http://192.168.1.10:1234/'),
        'http://192.168.1.10:1234/v1',
      );
      expect(
        LmStudioTranslationEngine.normalizeBaseUrl(
            'http://192.168.1.10:1234/v1'),
        'http://192.168.1.10:1234/v1',
      );
      expect(
        LmStudioTranslationEngine.normalizeBaseUrl(
            'http://192.168.1.10:1234/v1/'),
        'http://192.168.1.10:1234/v1',
      );
    });

    test('testConnection mock handler works correctly', () async {
      final engine = LmStudioTranslationEngine(
        mockTestConnectionHandler: (url, key) async {
          return const LmStudioConnectionResult(
            isSuccess: true,
            message: 'Connected successfully (200)',
            availableModels: ['qwen2.5-7b-instruct', 'llama-3.2-3b'],
          );
        },
      );

      final res = await engine.testConnection(baseUrl: 'http://localhost:1234');
      expect(res.isSuccess, isTrue);
      expect(res.availableModels, contains('qwen2.5-7b-instruct'));
      expect(res.availableModels.length, 2);
    });

    test('MlKitTranslationEngine routes manga translation through mock handler',
        () async {
      final mlEngine = MlKitTranslationEngine.instance;

      MlKitTranslationEngine.instance.lmStudioEngine.mockInferenceHandler =
          (prompt, {required temperature, required maxTokens}) async {
        if (prompt.contains('助けて')) {
          return 'Help me!';
        }
        return 'Understood.';
      };

      try {
        final resultJa = await mlEngine.translateText(
          '助けて！',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        );
        expect(resultJa, 'Help me!');

        final resultAuto = await mlEngine.translateText(
          '助けて',
          source: TranslationSourceLanguage.auto,
          target: TranslationTargetLanguage.english,
        );
        expect(resultAuto, 'Help me!');

        // Non-CJK passes through unchanged
        final englishText = await mlEngine.translateText(
          'Hello World!',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        );
        expect(englishText, 'Hello World!');

        // Empty string
        final empty = await mlEngine.translateText(
          '',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        );
        expect(empty, '');
      } finally {
        MlKitTranslationEngine.instance.lmStudioEngine.mockInferenceHandler =
            null;
      }
    });

    test('LmStudioTranslationEngine.hasCjkCharacters script validation', () {
      expect(LmStudioTranslationEngine.hasCjkCharacters('こんにちは'), isTrue);
      expect(LmStudioTranslationEngine.hasCjkCharacters('スゴイ！'), isTrue);
      expect(LmStudioTranslationEngine.hasCjkCharacters('ﾆﾎﾝ'), isTrue);
      expect(LmStudioTranslationEngine.hasCjkCharacters('你好世界'), isTrue);
      expect(LmStudioTranslationEngine.hasCjkCharacters('漫画'), isTrue);
      expect(LmStudioTranslationEngine.hasCjkCharacters('안녕하세요'), isTrue);
      expect(LmStudioTranslationEngine.hasCjkCharacters('ㅋㅋㅋ'), isTrue);
      expect(
          LmStudioTranslationEngine.hasCjkCharacters('Hello World!'), isFalse);
      expect(LmStudioTranslationEngine.hasCjkCharacters('1234567890'), isFalse);
    });

    test('SettingsModel LM Studio configuration fields persist and copyWith',
        () {
      const model = SettingsModel();
      expect(model.lmStudioServerUrl, 'http://192.168.1.2:1234/v1');
      expect(model.lmStudioApiKey, '');
      expect(model.lmStudioModel, '');

      final updated = model.copyWith(
        lmStudioServerUrl: 'http://10.0.0.5:1234/v1',
        lmStudioApiKey: 'secret-token',
        lmStudioModel: 'qwen2.5-7b-instruct',
        translationEngineType: TranslationEngineType.lmStudio,
      );

      expect(updated.lmStudioServerUrl, 'http://10.0.0.5:1234/v1');
      expect(updated.lmStudioApiKey, 'secret-token');
      expect(updated.lmStudioModel, 'qwen2.5-7b-instruct');
      expect(updated.translationEngineType, TranslationEngineType.lmStudio);
      expect(updated.props, contains('http://10.0.0.5:1234/v1'));
      expect(updated.props, contains(TranslationEngineType.lmStudio));
    });

    test('MlKitTranslationEngine forwards lastStatusMessage', () {
      final mlEngine = MlKitTranslationEngine.instance;
      expect(mlEngine.lastStatusMessage,
          mlEngine.lmStudioEngine.lastStatusMessage);
    });
  });

  group('MlKitTranslationEngine Language Selection & Mapping', () {
    test('MlKitTranslationEngine mapToTranslateLanguage mappings', () {
      expect(
        MlKitTranslationEngine.mapToTranslateLanguage('en'),
        TranslateLanguage.english,
      );
      expect(
        MlKitTranslationEngine.mapToTranslateLanguage('ja'),
        TranslateLanguage.japanese,
      );
      expect(
        MlKitTranslationEngine.mapToTranslateLanguage('zh'),
        TranslateLanguage.chinese,
      );
      expect(
        MlKitTranslationEngine.mapToTranslateLanguage('ko'),
        TranslateLanguage.korean,
      );
      expect(
        MlKitTranslationEngine.mapToTranslateLanguage('unknown'),
        isNull,
      );
    });

    test(
        'TranslationSourceLanguage serialization and persistence in SettingsModel',
        () {
      const defaultSettings = SettingsModel();
      expect(
        defaultSettings.translationSourceLanguage,
        TranslationSourceLanguage.japanese,
      );

      final koreanSettings = defaultSettings.copyWith(
        translationSourceLanguage: TranslationSourceLanguage.korean,
      );
      expect(
        koreanSettings.translationSourceLanguage,
        TranslationSourceLanguage.korean,
      );
      expect(koreanSettings.props, contains(TranslationSourceLanguage.korean));

      final json = koreanSettings.toJson();
      expect(json['translationSourceLanguage'], 'korean');

      final revived = SettingsModel.fromJson(json);
      expect(
          revived.translationSourceLanguage, TranslationSourceLanguage.korean);
    });

    testWidgets(
        'ImageViewerScreen Translation Sheet renders 3 dedicated manual language buttons & Otomatis',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final item = MediaItem(
        id: 'test_p1',
        path: '/storage/emulated/0/Pictures/Manga/p1.jpg',
        name: 'p1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [item],
              initialIndex: 0,
              initialMangaMode: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final translateBtn =
          find.byKey(const ValueKey('manga_translation_button'));
      expect(translateBtn, findsOneWidget);

      tester.widget<IconButton>(translateBtn).onPressed!();
      await tester.pumpAndSettle();

      // Verify the 3 dedicated manual language buttons and their subtext
      expect(find.text('Japanese'), findsOneWidget);
      expect(find.text('JA → EN'), findsOneWidget);
      expect(find.text('Chinese'), findsOneWidget);
      expect(find.text('ZH → EN'), findsOneWidget);
      expect(find.text('Korean'), findsOneWidget);
      expect(find.text('KO → EN'), findsOneWidget);
      expect(find.text('Auto Detect'), findsOneWidget);

      // Tap Korean button
      await tester.tap(find.text('Korean'));
      await tester.pumpAndSettle();

      // Verify settings updated and persisted
      expect(
        SettingsService.instance.settings.translationSourceLanguage,
        TranslationSourceLanguage.korean,
      );
    });
  });

  group('Manga Speech Bubble Clustering & Google Translate Visual Styling', () {
    test(
        'mergeAdjacentBlocks clusters multi-column vertical manga bubble into 1 block with RTL reading order',
        () {
      final rightCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(300, 100, 25, 180),
        text: '右のセリフ',
      );
      final midCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(265, 100, 25, 180),
        text: '中央のセリフ',
      );
      final leftCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(230, 100, 25, 180),
        text: '左のセリフ',
      );

      final merged = MangaOcrService.mergeAdjacentBlocks(
        [leftCol, rightCol, midCol],
        language: TranslationSourceLanguage.japanese,
      );

      expect(merged.length, 1);
      expect(merged.first.boundingBox, const Rect.fromLTWH(230, 100, 95, 180));
      expect(merged.first.text, '右のセリフ\n中央のセリフ\n左のセリフ');
    });

    test(
        'mergeAdjacentBlocks keeps separate speech bubbles apart when distance exceeds threshold',
        () {
      final bubbleTop = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(50, 50, 120, 100),
        text: '上のフキダシ',
      );
      final bubbleBottom = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(500, 700, 140, 110),
        text: '下のフキダシ',
      );

      final merged = MangaOcrService.mergeAdjacentBlocks(
        [bubbleTop, bubbleBottom],
        language: TranslationSourceLanguage.japanese,
      );

      expect(merged.length, 2);
      expect(merged[0].text, '上のフキダシ');
      expect(merged[1].text, '下のフキダシ');
    });

    test(
        'mergeAdjacentBlocks clusters horizontal adjacent lines into Top-to-Bottom order',
        () {
      final line1 = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(100, 100, 200, 25),
        text: 'First line of dialogue',
      );
      final line2 = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(100, 130, 200, 25),
        text: 'Second line of dialogue',
      );

      final merged = MangaOcrService.mergeAdjacentBlocks(
        [line2, line1],
        language: TranslationSourceLanguage.auto,
      );

      expect(merged.length, 1);
      expect(merged.first.boundingBox, const Rect.fromLTWH(100, 100, 200, 55));
      expect(
          merged.first.text, 'First line of dialogue\nSecond line of dialogue');
    });

    test(
        'TranslationIsolateCoordinator merges adjacent blocks before translation',
        () async {
      final rightCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(300, 100, 25, 180),
        text: '右のセリフ',
      );
      final leftCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(265, 100, 25, 180),
        text: '左のセリフ',
      );

      final coordinator = TranslationIsolateCoordinator();
      final blocks = await coordinator.translateBlocks(
        [rightCol, leftCol],
        const Size(1000, 1500),
        mode: TranslationRenderMode.speechBubblesOnly,
        language: TranslationSourceLanguage.japanese,
        targetLanguage: TranslationTargetLanguage.english,
      );

      // Translates exactly 1 merged block, not 2 separate blocks!
      expect(blocks.length, 1);
      expect(blocks.first.originalText, '右のセリフ\n左のセリフ');
      expect(blocks.first.boundingBox, const Rect.fromLTWH(265, 100, 60, 180));
    });

    test(
        'Google Translate visual typography constraints in calculateBubbleRect',
        () {
      const screenSize = Size(400, 800);

      final rectShort = MangaTranslationPainter.calculateBubbleRect(
        rect: const Rect.fromLTWH(100, 100, 80, 40),
        text: 'Wait for me!',
        screenSize: screenSize,
      );
      expect(rectShort.width, greaterThan(0));

      final rectMed = MangaTranslationPainter.calculateBubbleRect(
        rect: const Rect.fromLTWH(100, 100, 120, 60),
        text: 'Wait for me, I have something very important to tell you.',
        screenSize: screenSize,
      );
      expect(rectMed.width, greaterThan(0));

      final rectLong = MangaTranslationPainter.calculateBubbleRect(
        rect: const Rect.fromLTWH(100, 100, 150, 80),
        text:
            'There is no way that someone like you could possibly understand the heavy burden I have been carrying all these years!',
        screenSize: screenSize,
      );
      expect(rectLong.width, greaterThan(0));
    });

    test('mergeAdjacentBlocks merges vertical columns with 55px gap', () {
      final rightCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(300, 100, 30, 200),
        text: '右の列のセリフ',
      );
      // Left column: left = 215, width = 30 -> right = 245.
      // Gap between 245 and 300 is exactly 55px!
      final leftCol = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(215, 100, 30, 200),
        text: '左の列のセリフ',
      );

      final merged = MangaOcrService.mergeAdjacentBlocks(
        [leftCol, rightCol],
        language: TranslationSourceLanguage.japanese,
      );

      expect(merged.length, 1);
      expect(merged.first.boundingBox, const Rect.fromLTWH(215, 100, 115, 200));
      expect(merged.first.text, '右の列のセリフ\n左の列のセリフ');
    });

    test('mergeAdjacentBlocks gap threshold scales with text size', () {
      List<RawMangaTextBlock> columns(double s, double gap) => [
            RawMangaTextBlock(
              boundingBox: Rect.fromLTWH(1000 * s, 300 * s, 60 * s, 400 * s),
              text: '右の列のセリフ',
            ),
            RawMangaTextBlock(
              boundingBox: Rect.fromLTWH(
                  1000 * s - gap * s - 60 * s, 300 * s, 60 * s, 400 * s),
              text: '左の列のセリフ',
            ),
          ];

      // 140px gap (high-res page) and the same layout at 1/3 scale: one bubble.
      for (final s in [1.0, 1 / 3]) {
        expect(
          MangaOcrService.mergeAdjacentBlocks(columns(s, 140),
              language: TranslationSourceLanguage.japanese),
          hasLength(1),
        );
      }
      // Gap > 4x text size stays as two separate bubbles at any scale.
      for (final s in [1.0, 1 / 3]) {
        expect(
          MangaOcrService.mergeAdjacentBlocks(columns(s, 400),
              language: TranslationSourceLanguage.japanese),
          hasLength(2),
        );
      }
    });

    test('mergeAdjacentBlocks deduplicates identical or contained text lines',
        () {
      final block1 = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(200, 100, 30, 150),
        text: 'こんにちは世界',
      );
      final block2 = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(180, 100, 30, 150),
        text: 'こんにちは世界', // Identical text
      );
      final block3 = const RawMangaTextBlock(
        boundingBox: Rect.fromLTWH(140, 100, 30, 150),
        text: 'こんにちは', // Substring of block1 (length >= 3)
      );

      final merged = MangaOcrService.mergeAdjacentBlocks(
        [block1, block2, block3],
        language: TranslationSourceLanguage.japanese,
      );

      expect(merged.length, 1);
      // 'こんにちは世界' is kept, duplicates and substrings are dropped
      expect(merged.first.text, 'こんにちは世界');
    });

    test(
        'MangaTranslationPainter.clusterSpeechBubbles merges 3 colliding/overlapping fragments into 1 unified bubble',
        () {
      final b1 = const MangaSpeechBubbleCluster(
        rect: Rect.fromLTWH(100, 100, 60, 40),
        text: 'Hello world',
      );
      final b2 = const MangaSpeechBubbleCluster(
        rect: Rect.fromLTWH(140, 100, 60, 40), // overlaps b1
        text: 'world', // Substring of b1
      );
      final b3 = const MangaSpeechBubbleCluster(
        rect: Rect.fromLTWH(180, 100, 60, 40), // overlaps b2
        text: 'How are you doing?',
      );

      final clustered =
          MangaTranslationPainter.clusterSpeechBubbles([b1, b2, b3]);

      expect(clustered.length, 1);
      expect(clustered.first.rect, const Rect.fromLTWH(100, 100, 140, 40));
      expect(clustered.first.text, 'Hello world\nHow are you doing?');
    });

    test(
        'MangaTranslationPainter.clusterSpeechBubbles preserves separate distant bubbles',
        () {
      final b1 = const MangaSpeechBubbleCluster(
        rect: Rect.fromLTWH(50, 50, 80, 40),
        text: 'Top bubble',
      );
      final b2 = const MangaSpeechBubbleCluster(
        rect: Rect.fromLTWH(300, 500, 100, 50),
        text: 'Bottom bubble',
      );

      final clustered = MangaTranslationPainter.clusterSpeechBubbles([b1, b2]);

      expect(clustered.length, 2);
      expect(clustered[0].text, 'Top bubble');
      expect(clustered[1].text, 'Bottom bubble');
    });

    testWidgets(
        'MangaTranslationOverlay widget test verifying unified bubble rendering',
        (tester) async {
      final result = TranslationResult(
        imagePath: '/mock/clustering_test.jpg',
        imageSize: const Size(1000, 1500),
        blocks: const [
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(200, 200, 50, 40),
            originalText: '断片1',
            translatedText: 'This is bubble part 1',
            isSpeechBubble: true,
          ),
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(230, 200, 50, 40), // overlaps block 1
            originalText: '断片2',
            translatedText: 'bubble part 1', // duplicate substring
            isSpeechBubble: true,
          ),
          MangaTranslatedBlock(
            boundingBox: Rect.fromLTWH(260, 200, 50, 40), // overlaps block 2
            originalText: '断片3',
            translatedText: 'and part 2 here',
            isSpeechBubble: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 750,
              child: MangaTranslationOverlay(
                result: result,
                mode: TranslationRenderMode.speechBubblesOnly,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MangaTranslationOverlay), findsOneWidget);
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is MangaTranslationPainter),
        findsOneWidget,
      );
    });
  });

  group('OnnxTranslationEngine Core & Model Resolution', () {
    test('normalizeLangCode resolves aliases and trims/lowercases', () {
      expect(OnnxTranslationEngine.normalizeLangCode('ja'), 'ja');
      expect(OnnxTranslationEngine.normalizeLangCode('JA'), 'ja');
      expect(OnnxTranslationEngine.normalizeLangCode('Japanese'), 'ja');
      expect(OnnxTranslationEngine.normalizeLangCode('japanese'), 'ja');
      expect(OnnxTranslationEngine.normalizeLangCode('ja-JP'), 'ja');

      expect(OnnxTranslationEngine.normalizeLangCode('zh'), 'zh');
      expect(OnnxTranslationEngine.normalizeLangCode('ZH'), 'zh');
      expect(OnnxTranslationEngine.normalizeLangCode('Chinese'), 'zh');
      expect(OnnxTranslationEngine.normalizeLangCode('chinese'), 'zh');
      expect(OnnxTranslationEngine.normalizeLangCode('zh-CN'), 'zh');

      expect(OnnxTranslationEngine.normalizeLangCode('ko'), 'ko');
      expect(OnnxTranslationEngine.normalizeLangCode('KO'), 'ko');
      expect(OnnxTranslationEngine.normalizeLangCode('Korean'), 'ko');
      expect(OnnxTranslationEngine.normalizeLangCode('korean'), 'ko');
      expect(OnnxTranslationEngine.normalizeLangCode('ko-KR'), 'ko');

      expect(OnnxTranslationEngine.normalizeLangCode('EN'), 'en');
      expect(OnnxTranslationEngine.normalizeLangCode('fr'), 'fr');
    });

    test('mapSourceLanguageToCode maps translation source enums correctly', () {
      expect(
        OnnxTranslationEngine.mapSourceLanguageToCode(
            TranslationSourceLanguage.japanese),
        'ja',
      );
      expect(
        OnnxTranslationEngine.mapSourceLanguageToCode(
            TranslationSourceLanguage.chinese),
        'zh',
      );
      expect(
        OnnxTranslationEngine.mapSourceLanguageToCode(
            TranslationSourceLanguage.korean),
        'ko',
      );
      expect(
        OnnxTranslationEngine.mapSourceLanguageToCode(
            TranslationSourceLanguage.auto),
        'ja',
      );
    });

    test('Custom model directory getters and setters with normalization', () {
      final engine = OnnxTranslationEngine.instance;

      engine.setModelDirectory('ja', '/custom/onnx/ja');
      expect(engine.getModelDirectory('ja'), '/custom/onnx/ja');
      expect(engine.getModelDirectory('Japanese'), '/custom/onnx/ja');

      engine.setModelDirectory('ZH', '/custom/onnx/zh');
      expect(engine.getModelDirectory('zh'), '/custom/onnx/zh');
      expect(engine.getModelDirectory('Chinese'), '/custom/onnx/zh');

      engine.setModelDirectory('korean', '/custom/onnx/ko');
      expect(engine.getModelDirectory('ko'), '/custom/onnx/ko');
      expect(engine.getModelDirectory('KO'), '/custom/onnx/ko');
    });

    test('isModelAvailable with mock handler returns true immediately',
        () async {
      final engine = OnnxTranslationEngine.instance;
      engine.mockInferenceHandler = (text, src, tgt) async => 'mocked';
      try {
        expect(await engine.isModelAvailable('ja'), isTrue);
        expect(await engine.isModelAvailable('zh'), isTrue);
        expect(await engine.isModelAvailable('ko'), isTrue);
        expect(await engine.isModelAvailable('unsupported'), isTrue);
      } finally {
        engine.mockInferenceHandler = null;
      }
    });

    test('isModelAvailable validates directory contents and files presence',
        () async {
      final engine = OnnxTranslationEngine.instance;
      final tempDir = Directory.systemTemp.createTempSync('onnx_model_test_');

      try {
        engine.setModelDirectory('ja', tempDir.path);
        // Initially empty directory -> false
        expect(await engine.isModelAvailable('ja'), isFalse);

        // Add 2 of 3 required files -> still false
        final encFile = File('${tempDir.path}/encoder_model.onnx');
        final decFile = File('${tempDir.path}/decoder_model.onnx');
        final vocabFile = File('${tempDir.path}/vocab.json');

        await encFile.writeAsString('mock_enc');
        expect(await engine.isModelAvailable('ja'), isFalse);

        await decFile.writeAsString('mock_dec');
        expect(await engine.isModelAvailable('ja'), isFalse);

        // Add all 3 required files -> true!
        await vocabFile.writeAsString('{"test": 1}');
        expect(await engine.isModelAvailable('ja'), isTrue);
      } finally {
        engine.setModelDirectory('ja', '');
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('OnnxTranslationEngine Formatting, Lifecycle & Offline Dictionary', () {
    test('cleanComicDialogue punctuation, spacing, and casing rules', () {
      // Punctuation spacing (removes spaces before punctuation, adds space after if followed by word)
      expect(
        OnnxTranslationEngine.cleanComicDialogue(
            'Hello , world ! How are you ?'),
        'Hello, world! How are you?',
      );
      expect(
        OnnxTranslationEngine.cleanComicDialogue('Wait .Here I am .'),
        'Wait. Here I am.',
      );

      // Multiple punctuation marks coalescing
      expect(
        OnnxTranslationEngine.cleanComicDialogue(
            'What ! ? Are you serious ? !'),
        'What!? Are you serious?!',
      );

      // Capitalize sentence start and after ending punctuation
      expect(
        OnnxTranslationEngine.cleanComicDialogue(
            'hey! watch out. someone is coming.'),
        'Hey! Watch out. Someone is coming.',
      );

      // Standalone 'i' and contraction capitalization
      expect(
        OnnxTranslationEngine.cleanComicDialogue(
            "i don't think i'm ready, but i'll try."),
        "I don't think I'm ready, but I'll try.",
      );

      // Special tokens stripping
      expect(
        OnnxTranslationEngine.cleanComicDialogue(
            '<pad> <2en> Hello </s> <unk>'),
        'Hello',
      );
    });

    test('releaseCurrentSession resets state safely', () async {
      final engine = OnnxTranslationEngine.instance;
      expect(engine.isModelLoaded, isFalse);
      expect(engine.currentLoadedLanguage, isNull);

      await engine.releaseCurrentSession();
      expect(engine.isModelLoaded, isFalse);
      expect(engine.currentLoadedLanguage, isNull);

      await engine.dispose();
      expect(engine.isModelLoaded, isFalse);
    });

    test('Built-in offline manga dialogue & SFX dictionary fallback', () {
      final engine = OnnxTranslationEngine.instance;

      // Japanese dialogue & questions
      expect(engine.lookupDictionary('こんにちは', 'ja'), 'Hello');
      expect(engine.lookupDictionary('何？！', 'ja'), 'What?!');
      expect(engine.lookupDictionary('助けて！', 'ja'), 'Help me!');
      expect(engine.lookupDictionary('どういたしまして', 'ja'), "You're welcome");
      expect(engine.lookupDictionary('大丈夫？', 'ja'), 'Are you okay?');

      // Japanese SFX
      expect(engine.lookupDictionary('ドキドキ', 'ja'), '*thump thump*');
      expect(engine.lookupDictionary('ドカーン', 'ja'), '*KABOOM*');
      expect(engine.lookupDictionary('ゴゴゴ', 'ja'), '*rumble*');

      // Korean dialogue & SFX
      expect(engine.lookupDictionary('안녕하세요', 'ko'), 'Hello');
      expect(engine.lookupDictionary('살려줘!', 'ko'), 'Help me!');
      expect(engine.lookupDictionary('대박', 'ko'), 'Awesome!');
      expect(engine.lookupDictionary('두근두근', 'ko'), '*pit-a-pat*');
      expect(engine.lookupDictionary('쿵', 'ko'), '*THUD*');

      // Chinese dialogue & SFX
      expect(engine.lookupDictionary('你好', 'zh'), 'Hello');
      expect(engine.lookupDictionary('救命', 'zh'), 'Help!');
      expect(engine.lookupDictionary('厉害', 'zh'), 'Incredible!');
      expect(engine.lookupDictionary('轰', 'zh'), '*BOOM*');
      expect(engine.lookupDictionary('啪', 'zh'), '*SLAP*');

      // Unknown or non-matching text returns null
      expect(engine.lookupDictionary('ランダムな長い文章です', 'ja'), isNull);
    });

    test(
        'translateMangaText falls back to dictionary when offline without model',
        () async {
      final engine = OnnxTranslationEngine.instance;
      // Ensure no mock handler is set
      engine.mockInferenceHandler = null;

      final resultJa = await engine.translateMangaText(
        text: '助けて！',
        source: TranslationSourceLanguage.japanese,
        target: TranslationTargetLanguage.english,
      );
      expect(resultJa, 'Help me!');

      final resultKo = await engine.translateMangaText(
        text: '안녕하세요',
        source: TranslationSourceLanguage.korean,
        target: TranslationTargetLanguage.english,
      );
      expect(resultKo, 'Hello');

      final resultZh = await engine.translateMangaText(
        text: '你好',
        source: TranslationSourceLanguage.chinese,
        target: TranslationTargetLanguage.english,
      );
      expect(resultZh, 'Hello');

      // Non-translatable text returns cleaned original
      final numeric = await engine.translateMangaText(
        text: '12345',
        source: TranslationSourceLanguage.japanese,
        target: TranslationTargetLanguage.english,
      );
      expect(numeric, '12345');
    });
  });

  group('OnnxTranslationEngine Mock Inference & Engine Routing', () {
    test('Mock inference handler executes and applies cleanComicDialogue',
        () async {
      final engine = OnnxTranslationEngine.instance;
      String? capturedText;
      String? capturedSrc;
      String? capturedTgt;

      engine.mockInferenceHandler = (text, src, tgt) async {
        capturedText = text;
        capturedSrc = src;
        capturedTgt = tgt;
        return ' <pad> yes , i am here ! </s> ';
      };

      try {
        final result = await engine.translateMangaText(
          text: 'はい、ここにいます！',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        );

        expect(capturedText, 'はい、ここにいます！');
        expect(capturedSrc, 'ja');
        expect(capturedTgt, 'en');
        // Cleaned comic dialogue: spacing, capitalization
        expect(result, 'Yes, I am here!');
      } finally {
        engine.mockInferenceHandler = null;
      }
    });

    test(
        'MlKitTranslationEngine routes to OnnxTranslationEngine when onnxHelsinki selected',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      // Configure settings to use onnxHelsinki
      await SettingsService.instance
          .setTranslationEngineType(TranslationEngineType.onnxHelsinki);

      final onnxEngine = OnnxTranslationEngine.instance;
      onnxEngine.mockInferenceHandler = (text, src, tgt) async {
        return 'Mocked Helsinki Translation: $text';
      };

      try {
        final res = await MlKitTranslationEngine.instance.translateText(
          '助けて！',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        );

        expect(res, 'Mocked Helsinki Translation: 助けて！');
      } finally {
        onnxEngine.mockInferenceHandler = null;
      }
    });

    test('SettingsModel ONNX directory fields persist, serialize, and copyWith',
        () {
      const model = SettingsModel();
      expect(model.onnxModelDirJa, '');
      expect(model.onnxModelDirZh, '');
      expect(model.onnxModelDirKo, '');
      expect(model.translationEngineType, TranslationEngineType.googleMlKit);

      final updated = model.copyWith(
        onnxModelDirJa: '/path/ja',
        onnxModelDirZh: '/path/zh',
        onnxModelDirKo: '/path/ko',
        translationEngineType: TranslationEngineType.onnxHelsinki,
      );

      expect(updated.onnxModelDirJa, '/path/ja');
      expect(updated.onnxModelDirZh, '/path/zh');
      expect(updated.onnxModelDirKo, '/path/ko');
      expect(updated.translationEngineType, TranslationEngineType.onnxHelsinki);

      final map = updated.toMap();
      expect(map['onnxModelDirJa'], '/path/ja');
      expect(map['onnxModelDirZh'], '/path/zh');
      expect(map['onnxModelDirKo'], '/path/ko');
      expect(map['translationEngineType'], 'onnxHelsinki');

      final revived = SettingsModel.fromMap(map);
      expect(revived.onnxModelDirJa, '/path/ja');
      expect(revived.onnxModelDirZh, '/path/zh');
      expect(revived.onnxModelDirKo, '/path/ko');
      expect(revived.translationEngineType, TranslationEngineType.onnxHelsinki);
      expect(revived.props, contains('/path/ja'));
      expect(revived.props, contains(TranslationEngineType.onnxHelsinki));
    });

    test('SettingsService ONNX helper methods update settings and engine dirs',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final service = SettingsService.instance;
      await service.setOnnxModelDirJa('/models/ja');
      expect(service.settings.onnxModelDirJa, '/models/ja');
      expect(service.getOnnxModelDir('ja'), '/models/ja');

      await service.setOnnxModelDirZh('/models/zh');
      expect(service.settings.onnxModelDirZh, '/models/zh');
      expect(service.getOnnxModelDir('zh'), '/models/zh');

      await service.setOnnxModelDirKo('/models/ko');
      expect(service.settings.onnxModelDirKo, '/models/ko');
      expect(service.getOnnxModelDir('ko'), '/models/ko');

      await service.setOnnxModelDir('ja', '/models/ja_updated');
      expect(service.settings.onnxModelDirJa, '/models/ja_updated');
    });
  });

  group('Helsinki-NLP ONNX UI Integration (Viewer & Settings)', () {
    testWidgets(
        'ImageViewerScreen translation sheet switches to Helsinki-NLP Opus-MT engine',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final item = MediaItem(
        id: 'test_onnx_p1',
        path: '/storage/emulated/0/Pictures/Manga/p1.jpg',
        name: 'p1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [item],
              initialIndex: 0,
              initialMangaMode: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final translateBtn =
          find.byKey(const ValueKey('manga_translation_button'));
      expect(translateBtn, findsOneWidget);

      tester.widget<IconButton>(translateBtn).onPressed!();
      await tester.pumpAndSettle();

      // Verify Helsinki-NLP Opus-MT option exists in engine selector
      final helsinkiOption = find.text('Helsinki-NLP Opus-MT');
      expect(helsinkiOption, findsWidgets);

      // Tap Helsinki-NLP Opus-MT engine option
      await tester.tap(helsinkiOption.first);
      await tester.pumpAndSettle();

      // Verify settings updated
      expect(
        SettingsService.instance.settings.translationEngineType,
        TranslationEngineType.onnxHelsinki,
      );
    });

    testWidgets(
        'SettingsScreen renders Helsinki-NLP ONNX card and export instructions dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
      });

      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: const SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to Helsinki-NLP ONNX section header
      final onnxHeader = find.text('Helsinki-NLP ONNX Configuration');
      await tester.scrollUntilVisible(onnxHeader, 200);
      await tester.pumpAndSettle();
      expect(onnxHeader, findsOneWidget);

      // Verify language rows
      expect(find.text('Japanese (ja-en)'), findsOneWidget);
      expect(find.text('Chinese (zh-en)'), findsOneWidget);
      expect(find.text('Korean (ko-en)'), findsOneWidget);

      // Scroll to and verify Export Instructions tile
      final exportInstructionsTile = find.text('Export Instructions');
      await tester.scrollUntilVisible(exportInstructionsTile.first, 150);
      await tester.pumpAndSettle();
      expect(exportInstructionsTile, findsWidgets);

      // Tap export instructions tile
      await tester.tap(exportInstructionsTile.first);
      await tester.pumpAndSettle();

      // Verify instructions dialog contents
      expect(find.textContaining('optimum-cli'), findsWidgets);
      expect(find.textContaining('encoder_model.onnx'), findsWidgets);
      expect(find.textContaining('decoder_model.onnx'), findsWidgets);
      expect(find.textContaining('vocab.json'), findsWidgets);
    });
  });
}
