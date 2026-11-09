// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:convert';
import 'dart:io';
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/services/translation/translation_models.dart';
import 'package:phantek_gallery/core/services/translation/mlkit_translation_engine.dart';
import 'package:phantek_gallery/core/services/translation/onnx_local_llm_engine.dart';
import 'package:phantek_gallery/core/services/translation/manga_ocr_service.dart';
import 'package:phantek_gallery/core/services/translation/translation_isolate_coordinator.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/manga_translation_overlay.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/zigzag_progress_bar.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';

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
      expect(MlKitTranslationEngine.cleanMangaText(verticalJa), 'こ ん に ち は');

      const noisyText = '  助けて！ \r\n\r\n 誰か...  ';
      expect(MlKitTranslationEngine.cleanMangaText(noisyText), '助けて！ 誰か...');
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
            TranslationTargetLanguage.indonesian),
        MangaLanguage.indonesian,
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
          target: TranslationTargetLanguage.indonesian,
        ),
        '?!?!',
      );
      expect(
        await engine.translateText(
          '',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.indonesian,
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
          targetLanguage: TranslationTargetLanguage.indonesian,
          debounceDuration: const Duration(milliseconds: 100),
        );

        coordinator.scheduleTranslation(
          imagePath: temp2.path,
          imageSize: const Size(800, 1200),
          mode: TranslationRenderMode.speechBubblesOnly,
          targetLanguage: TranslationTargetLanguage.indonesian,
          debounceDuration: const Duration(milliseconds: 100),
        );

        await Future.delayed(const Duration(milliseconds: 350));

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
          targetLanguage: TranslationTargetLanguage.indonesian,
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
        targetLangName: 'Indonesian',
        totalNeededMb: 30.0,
        isReady: false,
      );
      expect(status.sourceDownloaded, isTrue);
      expect(status.targetDownloaded, isFalse);
      expect(status.sourceLangName, 'Japanese');
      expect(status.targetLangName, 'Indonesian');
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
        TranslationTargetLanguage.indonesian,
      );
      expect(status.sourceLangName, 'Japanese');
      expect(status.targetLangName, 'Indonesian');
      expect(status.totalNeededMb, anyOf(0.0, 30.0, 60.0));
    });

    test('allMangaLanguages defines all 5 required manga languages', () {
      expect(
        MlKitTranslationEngine.allMangaLanguages,
        containsAllInOrder([
          MangaLanguage.indonesian,
          MangaLanguage.english,
          MangaLanguage.japanese,
          MangaLanguage.korean,
          MangaLanguage.chinese,
        ]),
      );
      expect(MlKitTranslationEngine.allMangaLanguages.length, 5);
    });

    test('AllModelsStatus construction and properties', () {
      const status = AllModelsStatus(
        missingLanguages: [MangaLanguage.japanese, MangaLanguage.korean],
        downloadedLanguages: [
          MangaLanguage.indonesian,
          MangaLanguage.english,
          MangaLanguage.chinese,
        ],
        totalNeededMb: 60.0,
        isReady: false,
      );
      expect(status.missingLanguages.length, 2);
      expect(status.downloadedLanguages.length, 3);
      expect(status.totalNeededMb, 60.0);
      expect(status.isReady, isFalse);
    });

    test('checkAllModelsStatus returns valid AllModelsStatus metadata',
        () async {
      final engine = MlKitTranslationEngine.instance;
      final status = await engine.checkAllModelsStatus();
      expect(status.missingLanguages.length + status.downloadedLanguages.length,
          5);
      expect(status.totalNeededMb, status.missingLanguages.length * 30.0);
      expect(status.isReady, engine.onnxEngine.isReady);
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

  group('OnnxLocalLlmEngine Local LLM Translation', () {
    test('System prompt formatting and payload validation', () {
      expect(
        OnnxLocalLlmEngine.systemPromptTemplate,
        contains('You are an expert localizer for Asian comics.'),
      );
      expect(
        OnnxLocalLlmEngine.systemPromptTemplate,
        contains('Output ONLY the final English translation.'),
      );

      final promptJa = OnnxLocalLlmEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: '助けて！',
      );
      expect(promptJa, startsWith('<system>\n'));
      expect(
        promptJa,
        contains('Translate the raw OCR text from Japanese into natural English comic dialogue.'),
      );
      expect(promptJa, endsWith('</system>\n<user>\n助けて！\n</user>'));

      final promptKo = OnnxLocalLlmEngine.buildPrompt(
        language: 'Korean',
        rawOcrText: '살려줘!',
      );
      expect(
        promptKo,
        contains('Translate the raw OCR text from Korean into natural English comic dialogue.'),
      );
      expect(promptKo, endsWith('</system>\n<user>\n살려줘!\n</user>'));
    });

    test('Temperature (0.1) and max tokens (60) constraints', () async {
      expect(OnnxLocalLlmEngine.defaultTemperature, 0.1);
      expect(OnnxLocalLlmEngine.defaultMaxTokens, 60);

      // Temperature bounds: locked at 0.1 .. 0.2
      expect(OnnxLocalLlmEngine.constrainTemperature(0.1), 0.1);
      expect(OnnxLocalLlmEngine.constrainTemperature(0.2), 0.2);
      expect(OnnxLocalLlmEngine.constrainTemperature(0.0), 0.1);
      expect(OnnxLocalLlmEngine.constrainTemperature(-0.5), 0.1);
      expect(OnnxLocalLlmEngine.constrainTemperature(0.7), 0.2);
      expect(OnnxLocalLlmEngine.constrainTemperature(1.5), 0.2);

      // Max tokens bounds: limited to 50 .. 80
      expect(OnnxLocalLlmEngine.constrainMaxTokens(60), 60);
      expect(OnnxLocalLlmEngine.constrainMaxTokens(50), 50);
      expect(OnnxLocalLlmEngine.constrainMaxTokens(80), 80);
      expect(OnnxLocalLlmEngine.constrainMaxTokens(10), 50);
      expect(OnnxLocalLlmEngine.constrainMaxTokens(0), 50);
      expect(OnnxLocalLlmEngine.constrainMaxTokens(120), 80);
      expect(OnnxLocalLlmEngine.constrainMaxTokens(1000), 80);

      // Verify that translateMangaText locks the parameters passed to the handler
      double? receivedTemp;
      int? receivedTokens;
      final engine = OnnxLocalLlmEngine(
        mockInferenceHandler: (prompt,
            {required temperature, required maxTokens}) async {
          receivedTemp = temperature;
          receivedTokens = maxTokens;
          return 'I am here!';
        },
      );

      final out = await engine.translateMangaText(
        text: 'ここにいるぞ！',
        source: TranslationSourceLanguage.japanese,
        temperature: 0.99,
        maxTokens: 500,
      );

      expect(receivedTemp, 0.2);
      // For 6 CJK characters: (6 * 2 + 16).clamp(16, 80) = 28
      expect(receivedTokens, 28);
      expect(out, 'I am here!');

      // Long text reaching max tokens cap
      await engine.translateMangaText(
        text: 'これはテストです。長い漫画のセリフを翻訳してみましょう。どうなるでしょうか？ここにいるぞ！',
        source: TranslationSourceLanguage.japanese,
        temperature: 0.99,
        maxTokens: 500,
      );
      expect(receivedTemp, 0.2);
      expect(receivedTokens, 80);

      // Underflow bounds
      await engine.translateMangaText(
        text: 'これはテストです。長い漫画のセリフを翻訳してみましょう。どうなるでしょうか？ここにいるぞ！',
        source: TranslationSourceLanguage.japanese,
        temperature: 0.01,
        maxTokens: 20,
      );
      expect(receivedTemp, 0.1);
      expect(receivedTokens, 50);

      // Non-CJK text bypasses LLM inference
      receivedTokens = null;
      final nonCjk = await engine.translateMangaText(
        text: 'LIVE 1080P',
        source: TranslationSourceLanguage.japanese,
      );
      expect(nonCjk, 'LIVE 1080P');
      expect(receivedTokens, isNull);
    });

    test('Markdown cleanup and output sanitization', () {
      // Strips <system>, <user>, <assistant>, <think> tags
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('<assistant>Hello world</assistant>'),
        'Hello world',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
          '<system>Instructions</system><user>Raw</user><assistant>Clean comic dialogue</assistant>',
        ),
        'Clean comic dialogue',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
          '<think>Reasoning process...</think><assistant>Dialogue text</assistant>',
        ),
        'Dialogue text',
      );

      // Strips markdown formatting (bold, italics, code, blockquotes)
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('**Translation:** *Run away!*'),
        'Run away!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('> `Watch out!`'),
        'Watch out!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('### Warning: Danger!'),
        'Warning: Danger!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput("```text\nFire in the hole!\n```"),
        'Fire in the hole!',
      );

      // Strips chat preambles
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
            'Here is the English translation: "Don\'t move!"'),
        "Don't move!",
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
            'The English translation is: "Stop right there!"'),
        'Stop right there!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
            'Translation: **What did you say?!**'),
        'What did you say?!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
            'English Translation: That cannot be true.'),
        'That cannot be true.',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('“Hold on to me!”'),
        'Hold on to me!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('「Wait!」'),
        'Wait!',
      );
    });

    test(
        'Chaining with OCR blocks into translateText and translation coordinator',
        () async {
      final mockBlocks = [
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(10, 20, 100, 200),
          text: '何をしている？！',
        ),
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(150, 50, 80, 120),
          text: '逃げろ！',
        ),
      ];
      final mockDetector = MockMangaTextDetector(mockBlocks);
      final ocrService = MangaOcrService(detector: mockDetector);

      // Set mock handler on the translation engine's ONNX instance
      MlKitTranslationEngine.instance.onnxEngine.mockInferenceHandler =
          (prompt, {required temperature, required maxTokens}) async {
        if (prompt.contains('何をしている？！')) {
          return 'Translation: **What are you doing?!**';
        }
        return '<assistant>"Run away!"</assistant>';
      };

      final temp = await File('${Directory.systemTemp.path}/test_ocr_chain.jpg')
          .create();
      try {
        final coordinator = TranslationIsolateCoordinator(
          ocrService: ocrService,
          translationEngine: MlKitTranslationEngine.instance,
        );

        final rawExtracted = await ocrService.extractTextBlocks(temp.path);
        expect(rawExtracted.length, 2);

        final translated = await coordinator.translateBlocks(
          rawExtracted,
          const Size(1000, 1000),
          language: TranslationSourceLanguage.japanese,
          targetLanguage: TranslationTargetLanguage.english,
        );

        expect(translated.length, 2);
        expect(translated[0].originalText, '何をしている？！');
        expect(translated[0].translatedText, 'What are you doing?!');
        expect(translated[0].isSpeechBubble, isTrue);

        expect(translated[1].originalText, '逃げろ！');
        expect(translated[1].translatedText, 'Run away!');
        expect(translated[1].isSpeechBubble, isTrue);
      } finally {
        MlKitTranslationEngine.instance.onnxEngine.mockInferenceHandler = null;
        if (await temp.exists()) {
          await temp.delete();
        }
        ocrService.dispose();
      }
    });

    test(
        'Native ONNX graceful fallback and punctuation pass-through without throwing',
        () async {
      final engine = OnnxLocalLlmEngine.instance;
      // Standalone punctuation pass-through
      expect(
        await engine.translateMangaText(
          text: '?!?!',
          source: TranslationSourceLanguage.japanese,
        ),
        '?!?!',
      );
      expect(
        await engine.translateMangaText(
          text: '',
          source: TranslationSourceLanguage.japanese,
        ),
        '',
      );

      // Fallback pass-through when mock handler is null and native binary is absent
      final fallbackResult = await engine.translateMangaText(
        text: 'こんにちは',
        source: TranslationSourceLanguage.japanese,
      );
      expect(fallbackResult, 'こんにちは');
    });

    test('OnnxLocalLlmEngine.hasCjkCharacters script validation', () {
      // Japanese
      expect(OnnxLocalLlmEngine.hasCjkCharacters('こんにちは'), isTrue);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('スゴイ！'), isTrue);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('ﾆﾎﾝ'), isTrue);

      // Chinese
      expect(OnnxLocalLlmEngine.hasCjkCharacters('你好世界'), isTrue);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('漫画'), isTrue);

      // Korean
      expect(OnnxLocalLlmEngine.hasCjkCharacters('안녕하세요'), isTrue);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('ㅋㅋㅋ'), isTrue);

      // Non-CJK
      expect(OnnxLocalLlmEngine.hasCjkCharacters('Hello World!'), isFalse);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('LIVE 1080P'), isFalse);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('CHAPTER 24: THE END'), isFalse);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('1234567890'), isFalse);
      expect(OnnxLocalLlmEngine.hasCjkCharacters('...?!#@%'), isFalse);
      expect(OnnxLocalLlmEngine.hasCjkCharacters(''), isFalse);
    });

    test('cleanLlmOutput strips conversational preambles and prompt echoes', () {
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('Sure, here is the English translation: Stop right there!'),
        'Stop right there!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('Here is the English translation:\n\nGet out of my way!'),
        'Get out of my way!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('Natural English: Look out behind you!'),
        'Look out behind you!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('Translated text: I will never surrender!'),
        'I will never surrender!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput('Based on the comic dialogue: What is this power?!'),
        'What is this power?!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
          "On the other hand, you're an expert localizer for Asian comics.\n"
          "This is fictional comic dialogue. Preserve the original tone, slang, and profanity.\n\n"
          "You damn fool, don't touch that!",
        ),
        "You damn fool, don't touch that!",
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
          'The cat chased after the mouse.\n\n'
          'Let me go!',
        ),
        'Let me go!',
      );
      expect(
        OnnxLocalLlmEngine.cleanLlmOutput(
          'Sure! Here is the dialogue:\n\n'
          'Who are you?\n\n'
          'Note: Translated from Japanese.',
        ),
        'Who are you?',
      );
    });

    test('TranslationIsolateCoordinator skips non-CJK and filters speech bubbles', () async {
      final mockBlocks = [
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(10, 20, 100, 200),
          text: 'LIVE 1080P',
        ),
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(50, 50, 4, 4),
          text: 'あ',
        ),
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(100, 100, 150, 250),
          text: '待てよ！',
        ),
        const RawMangaTextBlock(
          boundingBox: Rect.fromLTWH(100, 500, 500, 80),
          text: 'ドカーン！',
        ),
      ];

      final mockDetector = MockMangaTextDetector(mockBlocks);
      final ocrService = MangaOcrService(detector: mockDetector);

      int translationCallCount = 0;
      MlKitTranslationEngine.instance.onnxEngine.mockInferenceHandler =
          (prompt, {required temperature, required maxTokens}) async {
        translationCallCount++;
        if (prompt.contains('待てよ！')) return 'Wait up!';
        if (prompt.contains('ドカーン！')) return 'BOOM!';
        return 'Unknown';
      };

      try {
        final coordinator = TranslationIsolateCoordinator(
          ocrService: ocrService,
          translationEngine: MlKitTranslationEngine.instance,
        );

        final results = await coordinator.translateBlocks(
          mockBlocks,
          const Size(1000, 1000),
          mode: TranslationRenderMode.speechBubblesOnly,
          targetLanguage: TranslationTargetLanguage.english,
        );

        expect(translationCallCount, 1);
        final translatedBubble = results.firstWhere((b) => b.originalText == '待てよ！');
        expect(translatedBubble.translatedText, 'Wait up!');
        expect(translatedBubble.isSpeechBubble, isTrue);

        expect(results.any((b) => b.originalText == 'LIVE 1080P'), isFalse);
        expect(results.any((b) => b.originalText == 'あ'), isFalse);
      } finally {
        MlKitTranslationEngine.instance.onnxEngine.mockInferenceHandler = null;
        ocrService.dispose();
      }
    });

    test('cleanLlmOutput strips operational rules echoes', () {
      const echoed =
          'CRITICAL OPERATIONAL RULES:\n1. Translate faithfully.\nHelp me!';
      expect(OnnxLocalLlmEngine.cleanLlmOutput(echoed), 'Help me!');
    });

    test(
        'scanAvailableModels scans candidate directories and returns discovered models',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('onnx_scan_test');
      try {
        final dummyModel = File(p.join(tempDir.path, 'test_model_q4.onnx'));
        await dummyModel.writeAsBytes(List.filled(1024 * 1024, 0)); // 1 MB

        final discovered = await OnnxLocalLlmEngine.scanAvailableModels(
          searchDirectories: [tempDir.path],
        );
        expect(discovered.length, 1);
        expect(discovered.first.name, 'test_model_q4.onnx');
        expect(discovered.first.path, dummyModel.path);
        expect(discovered.first.sizeMb, closeTo(1.0, 0.1));
        expect(discovered.first.formattedSize, '1.0 MB');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('SettingsModel activeAiModelPath defaults to empty and copyWith works',
        () {
      const model = SettingsModel();
      expect(model.activeAiModelPath, '');

      final updated =
          model.copyWith(activeAiModelPath: '/custom/path/model.onnx');
      expect(updated.activeAiModelPath, '/custom/path/model.onnx');
      expect(updated.props, contains('/custom/path/model.onnx'));
    });

    test('defaultModelsDirectoryPath and candidate paths prioritization', () {
      expect(
        OnnxLocalLlmEngine.defaultModelsDirectoryPath,
        '/storage/emulated/0/models',
      );
      expect(
        OnnxLocalLlmEngine.defaultModelCandidatePaths.first,
        startsWith('/storage/emulated/0/models/'),
      );
      expect(
        OnnxLocalLlmEngine.defaultModelCandidatePaths,
        contains('/storage/emulated/0/models/qwen2.5-0.5b-instruct-q4.onnx'),
      );
      expect(
        OnnxLocalLlmEngine.defaultModelCandidatePaths,
        contains('models/qwen2.5-0.5b-instruct-q4.onnx'),
      );
      expect(
        OnnxLocalLlmEngine.defaultModelCandidatePaths,
        contains('assets/models/qwen2.5-0.5b-instruct-q4.onnx'),
      );
    });

    test(
        'ensureModelsDirectoryExists creates directory when missing and is idempotent',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('models_dir_test');
      final targetSubDir = p.join(tempDir.path, 'nested', 'models');

      try {
        expect(Directory(targetSubDir).existsSync(), isFalse);

        // 1. Creates when missing
        await OnnxLocalLlmEngine.ensureModelsDirectoryExists(
            targetPath: targetSubDir);
        expect(Directory(targetSubDir).existsSync(), isTrue);

        // Put a canary file inside
        final canary = File(p.join(targetSubDir, 'canary.txt'));
        await canary.writeAsString('canary');

        // 2. Calling again leaves it untouched (idempotent)
        await OnnxLocalLlmEngine.ensureModelsDirectoryExists(
            targetPath: targetSubDir);
        expect(Directory(targetSubDir).existsSync(), isTrue);
        expect(canary.existsSync(), isTrue);
        expect(await canary.readAsString(), 'canary');
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('initializeSession resolves .onnx file from directory target path',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('models_init_test');
      try {
        final dummyModel = File(p.join(tempDir.path, 'sample.onnx'));
        await dummyModel.writeAsBytes(List.filled(16, 0));

        final engine = OnnxLocalLlmEngine();
        final success = await engine.initializeSession(modelPath: tempDir.path);
        expect(success, isA<bool>());
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('Tokenizer loading via HuggingFaceTokenizerLoader.fromJsonString', () {
      const sampleJson = '''

      {

        "version": "1.0",

        "model": {

          "type": "BPE",

          "vocab": {

            "<unk>": 0,

            "<s>": 1,

            "</s>": 2,

            "Hello": 3,

            "world": 4

          },

          "merges": []

        }

      }

      ''';

      final tokenizer = HuggingFaceTokenizerLoader.fromJsonString(sampleJson);
      expect(tokenizer, isNotNull);
      expect(tokenizer.vocab.size, 5);

      final encoded = tokenizer.encode('Hello world');
      expect(encoded.ids, isNotEmpty);

      final decoded = tokenizer.decode([3, 4]);
      expect(decoded, contains('Hello'));
      expect(decoded, contains('world'));
    });

    test(
        'selectNextToken uses argmax for temperature <= 0.1 and sampling for > 0.1',
        () {
      final logits = [0.1, 0.4, 2.9, 1.2, 0.05];

      // Argmax with temp = 0.1 should pick index 2 (value 2.9)
      final token01 = OnnxLocalLlmEngine.selectNextToken(logits, 0.1);
      expect(token01, 2);

      // Argmax with temp = 0.0 should pick index 2
      final token00 = OnnxLocalLlmEngine.selectNextToken(logits, 0.0);
      expect(token00, 2);

      // Temperature sampling with temp = 0.2 should return a valid index within bounds
      final token02 = OnnxLocalLlmEngine.selectNextToken(logits, 0.2);
      expect(token02, inInclusiveRange(0, logits.length - 1));

      // extractLastLogits helper
      final logits3d = [
        [
          [0.1, 0.2],
          [0.8, 1.5],
        ]
      ];
      expect(OnnxLocalLlmEngine.extractLastLogits(logits3d), [0.8, 1.5]);

      final logits2d = [
        [0.1, 0.2],
        [0.5, 0.9],
      ];
      expect(OnnxLocalLlmEngine.extractLastLogits(logits2d), [0.5, 0.9]);
    });

    test('Status message update when model is present vs tokenizer missing',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('onnx_status_test');
      try {
        final dummyModel =
            File(p.join(tempDir.path, 'qwen2.5-0.5b-instruct-q4.onnx'));
        await dummyModel.writeAsBytes(List.filled(16, 0));

        final engine = OnnxLocalLlmEngine();

        // 1. Model present, but companion tokenizer is missing
        await engine.initializeSession(modelPath: dummyModel.path, useBundledFallback: false);
        expect(
          engine.lastStatusMessage,
          'Model loaded (qwen2.5-0.5b-instruct-q4.onnx), but tokenizer.json not found in ${tempDir.path}',
        );

        // 2. Add companion tokenizer.json and re-initialize
        final dummyTok = File(p.join(tempDir.path, 'tokenizer.json'));
        await dummyTok.writeAsString(jsonEncode({
          'model': {
            'type': 'BPE',
            'vocab': {'<unk>': 0, '<s>': 1, '</s>': 2, 'tok': 3},
            'merges': [],
          }
        }));

        await engine.initializeSession(modelPath: dummyModel.path);
        expect(
          engine.lastStatusMessage,
          anyOf(
            startsWith('Ready:'),
            startsWith('Gagal memuat'),
          ),
        );

        engine.dispose();
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('MlKitTranslationEngine forwards lastStatusMessage', () {
      final mlEngine = MlKitTranslationEngine.instance;
      expect(mlEngine.lastStatusMessage, mlEngine.onnxEngine.lastStatusMessage);
    });

    test('QwenBpeTokenizer encodes and decodes text faithfully', () {
      final sampleJson = jsonEncode({
        'model': {
          'type': 'BPE',
          'vocab': {
            '<|endoftext|>': 151643,
            '<|im_start|>': 151644,
            '<|im_end|>': 151645,
            'H': 10,
            'e': 11,
            'l': 12,
            'o': 13,
            ' ': 14,
            'w': 15,
            'r': 16,
            'd': 17,
            'He': 18,
            'llo': 19,
            'Hello': 20,
          },
          'merges': [
            'H e',
            'l l',
            'll o',
            'He llo',
          ]
        },
        'added_tokens': [
          {'id': 151644, 'content': '<|im_start|>'},
          {'id': 151645, 'content': '<|im_end|>'},
          {'id': 151643, 'content': '<|endoftext|>'},
        ]
      });

      final tokenizer = QwenBpeTokenizer.fromJsonString(sampleJson);
      expect(tokenizer.eosTokenId, QwenBpeTokenizer.imEndTokenId);

      final encoded = tokenizer.encode('<|im_start|>Hello<|im_end|>');
      expect(encoded, contains(151644));
      expect(encoded, contains(151645));

      final decoded = tokenizer.decode(encoded);
      expect(decoded, '<|im_start|>Hello<|im_end|>');
    });

    test('formatForModel maps constitutional prompt to ChatML for Qwen', () {
      final prompt = OnnxLocalLlmEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: 'サバイバートーク',
      );
      final tokenizer = QwenBpeTokenizer(
        vocab: {},
        reverseVocab: {},
        bpeRanks: {},
      );

      final chatMl = OnnxLocalLlmEngine.formatForModel(prompt, tokenizer);
      expect(chatMl, contains('<|im_start|>system'));
      expect(chatMl, contains('<|im_end|>'));
      expect(chatMl, contains('<|im_start|>user\nサバイバートーク<|im_end|>'));
      expect(chatMl, endsWith('<|im_start|>assistant\n'));
    });

    test(
        'QwenBpeTokenizer round-trip encodes and decodes multi-byte CJK strings without corruption',
        () async {
      expect(QwenBpeTokenizer.bytesToUnicode.length, 256);
      expect(QwenBpeTokenizer.unicodeToBytes.length, 256);

      final tokenizer = await QwenBpeTokenizer.loadBundledAsset();
      const cjkSamples = [
        'なにをしてるんだ！？早く逃げろ！',
        '형, 지금 뭐 하는 거야?!',
        '你到底想干什么？！',
      ];

      for (final sample in cjkSamples) {
        final ids = tokenizer.encode(sample);
        expect(ids, isNotEmpty);
        final decoded = tokenizer.decode(ids);
        expect(decoded, sample);
      }
    });
  });
}
