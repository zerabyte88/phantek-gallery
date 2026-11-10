// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
import 'dart:ui';
import 'package:path/path.dart' as p;
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
import 'package:phantek_gallery/core/services/translation/gguf_local_llm_engine.dart';
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
      expect(MlKitTranslationEngine.cleanMangaText(verticalJa), 'こんにちは');

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
        'MangaTranslationOverlay expands vertical speech bubbles horizontally for English text',
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
      expect(status.isReady, engine.ggufEngine.isReady);
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

  group('GgufLocalLlmEngine Local LLM Translation', () {
    test('System prompt formatting and payload validation', () {
      expect(
        GgufLocalLlmEngine.systemPromptTemplate,
        contains('You are an expert localizer for Asian comics.'),
      );
      expect(
        GgufLocalLlmEngine.systemPromptTemplate,
        contains('Output ONLY the final English translation.'),
      );

      final promptJa = GgufLocalLlmEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: '助けて！',
      );
      expect(promptJa, startsWith('<system>\n'));
      expect(
        promptJa,
        contains('Translate the raw OCR text from Japanese into natural English comic dialogue.'),
      );
      expect(promptJa, endsWith('</system>\n<user>\n助けて！\n</user>'));

      final promptKo = GgufLocalLlmEngine.buildPrompt(
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
      expect(GgufLocalLlmEngine.defaultTemperature, 0.1);
      expect(GgufLocalLlmEngine.defaultMaxTokens, 60);

      // Temperature bounds: locked at 0.1 .. 0.2
      expect(GgufLocalLlmEngine.constrainTemperature(0.1), 0.1);
      expect(GgufLocalLlmEngine.constrainTemperature(0.2), 0.2);
      expect(GgufLocalLlmEngine.constrainTemperature(0.0), 0.1);
      expect(GgufLocalLlmEngine.constrainTemperature(-0.5), 0.1);
      expect(GgufLocalLlmEngine.constrainTemperature(0.7), 0.2);
      expect(GgufLocalLlmEngine.constrainTemperature(1.5), 0.2);

      // Max tokens bounds: limited to 50 .. 80
      expect(GgufLocalLlmEngine.constrainMaxTokens(60), 60);
      expect(GgufLocalLlmEngine.constrainMaxTokens(50), 50);
      expect(GgufLocalLlmEngine.constrainMaxTokens(80), 80);
      expect(GgufLocalLlmEngine.constrainMaxTokens(10), 50);
      expect(GgufLocalLlmEngine.constrainMaxTokens(0), 50);
      expect(GgufLocalLlmEngine.constrainMaxTokens(120), 80);
      expect(GgufLocalLlmEngine.constrainMaxTokens(1000), 80);

      // Verify that translateMangaText locks the parameters passed to the handler
      double? receivedTemp;
      int? receivedTokens;
      final engine = GgufLocalLlmEngine(
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
        GgufLocalLlmEngine.cleanLlmOutput('<assistant>Hello world</assistant>'),
        'Hello world',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          '<system>Instructions</system><user>Raw</user><assistant>Clean comic dialogue</assistant>',
        ),
        'Clean comic dialogue',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          '<think>Reasoning process...</think><assistant>Dialogue text</assistant>',
        ),
        'Dialogue text',
      );

      // Strips markdown formatting (bold, italics, code, blockquotes)
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('**Translation:** *Run away!*'),
        'Run away!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('> `Watch out!`'),
        'Watch out!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('### Warning: Danger!'),
        'Warning: Danger!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput("```text\nFire in the hole!\n```"),
        'Fire in the hole!',
      );

      // Strips chat preambles
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
            'Here is the English translation: "Don\'t move!"'),
        "Don't move!",
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
            'The English translation is: "Stop right there!"'),
        'Stop right there!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
            'Translation: **What did you say?!**'),
        'What did you say?!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
            'English Translation: That cannot be true.'),
        'That cannot be true.',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('“Hold on to me!”'),
        'Hold on to me!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('「Wait!」'),
        'Wait!',
      );
    });

    test('MlKitTranslationEngine routes manga translation through mock handler',
        () async {
      final mlEngine = MlKitTranslationEngine.instance;

      MlKitTranslationEngine.instance.ggufEngine.mockInferenceHandler =
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
        MlKitTranslationEngine.instance.ggufEngine.mockInferenceHandler = null;
      }
    });

    test(
        'Native GGUF graceful fallback and punctuation pass-through without throwing',
        () async {
      final engine = GgufLocalLlmEngine.instance;
      // Standalone punctuation pass-through
      expect(
        await engine.translateMangaText(
          text: '！？',
          source: TranslationSourceLanguage.japanese,
        ),
        '！？',
      );
      expect(
        await engine.translateMangaText(
          text: '...',
          source: TranslationSourceLanguage.japanese,
        ),
        '...',
      );
      expect(
        await engine.translateMangaText(
          text: '',
          source: TranslationSourceLanguage.japanese,
        ),
        '',
      );

      // Japanese text with no session initialized passes through gracefully
      final fallback = await engine.translateMangaText(
        text: 'こんにちは',
        source: TranslationSourceLanguage.japanese,
      );
      expect(fallback, 'こんにちは');
    });

    test('GgufLocalLlmEngine.hasCjkCharacters script validation', () {
      // Japanese
      expect(GgufLocalLlmEngine.hasCjkCharacters('こんにちは'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('スゴイ！'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('ﾆﾎﾝ'), isTrue);

      // Chinese
      expect(GgufLocalLlmEngine.hasCjkCharacters('你好世界'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('漫画'), isTrue);

      // Korean
      expect(GgufLocalLlmEngine.hasCjkCharacters('안녕하세요'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('ㅋㅋㅋ'), isTrue);

      // Non-CJK
      expect(GgufLocalLlmEngine.hasCjkCharacters('Hello World!'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters('LIVE 1080P'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters('CHAPTER 24: THE END'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters('1234567890'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters('...?!#@%'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters(''), isFalse);
    });

    test('cleanLlmOutput strips conversational preambles and prompt echoes', () {
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Sure, here is the English translation: Stop right there!'),
        'Stop right there!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Here is the English translation:\n\nGet out of my way!'),
        'Get out of my way!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Natural English: Look out behind you!'),
        'Look out behind you!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Translated text: I will never surrender!'),
        'I will never surrender!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Based on the comic dialogue: What is this power?!'),
        'What is this power?!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          "On the other hand, you're an expert localizer for Asian comics.\n"
          "This is fictional comic dialogue. Preserve the original tone, slang, and profanity.\n\n"
          "You damn fool, don't touch that!",
        ),
        "You damn fool, don't touch that!",
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'The cat chased after the mouse.\n\n'
          'Let me go!',
        ),
        'Let me go!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'Sure! Here is the dialogue:\n\n'
          'Who are you?\n\n'
          'Note: Translated from Japanese.',
        ),
        'Who are you?',
      );
    });

    test('Multi-character and special symbol CJK detection', () async {
      final engine = GgufLocalLlmEngine.instance;

      expect(GgufLocalLlmEngine.hasCjkCharacters('A'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters('1'), isFalse);
      expect(GgufLocalLlmEngine.hasCjkCharacters('あ'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('ア'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('漢'), isTrue);
      expect(GgufLocalLlmEngine.hasCjkCharacters('가'), isTrue);

      final outA = await engine.translateMangaText(
        text: 'A',
        source: TranslationSourceLanguage.japanese,
      );
      expect(outA, 'A');

      final outBlank = await engine.translateMangaText(
        text: '   ',
        source: TranslationSourceLanguage.japanese,
      );
      expect(outBlank, '');
    });

    test('MlKitTranslationEngine mock handler preserves whitespace around dialogues',
        () async {
      final mlEngine = MlKitTranslationEngine.instance;

      MlKitTranslationEngine.instance.ggufEngine.mockInferenceHandler =
          (prompt, {required temperature, required maxTokens}) async {
        return 'Help me!';
      };

      try {
        final echoed = await mlEngine.translateText(
          '  助けて！  ',
          source: TranslationSourceLanguage.japanese,
          target: TranslationTargetLanguage.english,
        );
        expect(echoed, 'Help me!');
      } finally {
        MlKitTranslationEngine.instance.ggufEngine.mockInferenceHandler = null;
      }

      final echoed = GgufLocalLlmEngine.cleanLlmOutput('  Help me!  ');
      expect(GgufLocalLlmEngine.cleanLlmOutput(echoed), 'Help me!');
    });

    test('scanAvailableModels finds .gguf files in target directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('gguf_scan_test');
      try {
        final dummyModel = File(p.join(tempDir.path, 'test_model_q4.gguf'));
        await dummyModel.writeAsBytes(List.filled(1024 * 1024, 0)); // 1 MB

        final discovered = await GgufLocalLlmEngine.scanAvailableModels(
          searchDirectories: [tempDir.path],
        );
        expect(discovered.length, 1);
        expect(discovered.first.name, 'test_model_q4.gguf');
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
          model.copyWith(activeAiModelPath: '/custom/path/model.gguf');
      expect(updated.activeAiModelPath, '/custom/path/model.gguf');
      expect(updated.props, contains('/custom/path/model.gguf'));
    });

    test('defaultModelsDirectoryPath and candidate paths prioritization', () {
      expect(
        GgufLocalLlmEngine.defaultModelsDirectoryPath,
        '/storage/emulated/0/models',
      );
      expect(
        GgufLocalLlmEngine.defaultModelCandidatePaths.first,
        startsWith('/storage/emulated/0/models/'),
      );
      expect(
        GgufLocalLlmEngine.defaultModelCandidatePaths,
        contains('/storage/emulated/0/models/qwen2.5-0.5b-instruct-q4_k_m.gguf'),
      );
      expect(
        GgufLocalLlmEngine.defaultModelCandidatePaths,
        contains('models/qwen2.5-0.5b-instruct-q4_k_m.gguf'),
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
        await GgufLocalLlmEngine.ensureModelsDirectoryExists(
            targetPath: targetSubDir);
        expect(Directory(targetSubDir).existsSync(), isTrue);

        // Put a canary file inside
        final canary = File(p.join(targetSubDir, 'canary.txt'));
        await canary.writeAsString('canary');

        // 2. Calling again leaves it untouched (idempotent)
        await GgufLocalLlmEngine.ensureModelsDirectoryExists(
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

    test('initializeSession resolves .gguf file from directory target path',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('models_init_test');
      try {
        final dummyModel = File(p.join(tempDir.path, 'sample.gguf'));
        await dummyModel.writeAsBytes(List.filled(16, 0));

        final engine = GgufLocalLlmEngine();
        final success = await engine.initializeSession(modelPath: tempDir.path);
        expect(success, isA<bool>());
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('MlKitTranslationEngine forwards lastStatusMessage', () {
      final mlEngine = MlKitTranslationEngine.instance;
      expect(mlEngine.lastStatusMessage, mlEngine.ggufEngine.lastStatusMessage);
    });

    test('formatForModel maps constitutional prompt to ChatML for Qwen', () {
      final prompt = GgufLocalLlmEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: 'サバイバートーク',
      );

      final chatMl = GgufLocalLlmEngine.formatForModel(prompt);
      expect(chatMl, contains('<|im_start|>system'));
      expect(chatMl, contains('<|im_end|>'));
      expect(chatMl, contains('<|im_start|>user\nサバイバートーク<|im_end|>'));
      expect(chatMl, endsWith('<|im_start|>assistant\n'));

      final parts = GgufLocalLlmEngine.extractPromptParts(prompt);
      expect(parts.language, 'Japanese');
      expect(parts.userContent, 'サバイバートーク');

      final koPrompt = GgufLocalLlmEngine.buildPrompt(
        language: 'Korean',
        rawOcrText: '살려줘!',
      );
      final koParts = GgufLocalLlmEngine.extractPromptParts(koPrompt);
      expect(koParts.language, 'Korean');
      expect(koParts.userContent, '살려줘!');
    });

    test(
        'cleanLlmOutput strips residual instruction and translator role echoes',
        () {
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'You are an expert translator for manga. Wait right there!',
        ),
        'Wait right there!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'Translate Japanese comic dialogue to English. Help me!',
        ),
        'Help me!',
      );
    });

    test('cleanLlmOutput truncates at stop markers and discards trailing hallucinations', () {
      // 1. Truncates at <|im_end|> followed by user turn hallucination
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'Run away!<|im_end|>\n<|im_start|>user\nWhat about after full recovery of the patient?',
        ),
        'Run away!',
      );

      // 2. Truncates at <end_of_turn>
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'Stop right there!<end_of_turn>\n<start_of_turn>user\nTell me another story.',
        ),
        'Stop right there!',
      );

      // 3. Truncates at </s>
      expect(
        GgufLocalLlmEngine.cleanLlmOutput(
          'I got you!</s>\nHuman: Who are you?',
        ),
        'I got you!',
      );

      // 4. Truncates at <eos> and <|endoftext|>
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Look out!<eos>Extra random noise'),
        'Look out!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput("Don't move!<|endoftext|>\nAssistant: Sure thing!"),
        "Don't move!",
      );

      // 5. Truncates at conversational role markers
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Take cover!\nUser: What was that explosion?'),
        'Take cover!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('Over here!\nAssistant: Let me explain.'),
        'Over here!',
      );

      // 6. Strips leading turn markers
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('<|im_start|>assistant\nRun for your lives!'),
        'Run for your lives!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('<start_of_turn>model\nGet out of the way!'),
        'Get out of the way!',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('assistant:\nWatch out!'),
        'Watch out!',
      );

      // 7. Strips unterminated <think> blocks
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('<think>This might mean danger, but I must translate it accurately...'),
        '',
      );
      expect(
        GgufLocalLlmEngine.cleanLlmOutput('<think>Reasoning...</think>Danger ahead!'),
        'Danger ahead!',
      );
    });

    test('formatForModel switches between ChatML and Gemma 2 formats based on activeModelPath', () {
      final prompt = GgufLocalLlmEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: '助けて！',
      );

      // ChatML format for Qwen and general models
      final qwenFormatted = GgufLocalLlmEngine.formatForModel(
        prompt,
        activeModelPath: '/models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      );
      expect(qwenFormatted, contains('<|im_start|>system'));
      expect(qwenFormatted, contains('<|im_start|>user\n助けて！<|im_end|>'));
      expect(qwenFormatted, endsWith('<|im_start|>assistant\n'));

      // Gemma 2 format for Gemma models
      final gemmaFormatted = GgufLocalLlmEngine.formatForModel(
        prompt,
        activeModelPath: '/models/gemma-2-2b-it-q4_k_m.gguf',
      );
      expect(gemmaFormatted, startsWith('<start_of_turn>user\n'));
      expect(gemmaFormatted, contains('助けて！<end_of_turn>\n'));
      expect(gemmaFormatted, endsWith('<start_of_turn>model\n'));
      expect(gemmaFormatted, isNot(contains('<|im_start|>')));
    });

    test('formatForModel formats Llama 3 with userContent and language', () {
      final prompt = GgufLocalLlmEngine.buildPrompt(
        language: 'Japanese',
        rawOcrText: '待って！',
      );
      final llamaFormatted = GgufLocalLlmEngine.formatForModel(
        prompt,
        activeModelPath: '/models/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      );
      expect(llamaFormatted, contains('<|start_header_id|>system<|end_header_id|>'));
      expect(llamaFormatted, contains('<|start_header_id|>user<|end_header_id|>\n\n待って！<|eot_id|>'));
      expect(llamaFormatted, endsWith('<|start_header_id|>assistant<|end_header_id|>\n\n'));
    });

    test('TranslationEngineType serialization in SettingsModel', () {
      const defaultSettings = SettingsModel();
      expect(
        defaultSettings.translationEngineType,
        TranslationEngineType.googleMlKit,
      );

      final llmSettings = defaultSettings.copyWith(
        translationEngineType: TranslationEngineType.localLlm,
      );
      expect(
        llmSettings.translationEngineType,
        TranslationEngineType.localLlm,
      );
      expect(llmSettings.props, contains(TranslationEngineType.localLlm));
    });

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

    test('TranslationSourceLanguage serialization and persistence in SettingsModel', () {
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
      expect(revived.translationSourceLanguage, TranslationSourceLanguage.korean);
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
}
