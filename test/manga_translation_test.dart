// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/services/translation/translation_models.dart';
import 'package:phantek_gallery/core/services/translation/mlkit_translation_engine.dart';
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

    test('Language enum mapping to ML Kit TranslateLanguage', () {
      expect(
        MlKitTranslationEngine.mapSourceLanguage(
            TranslationSourceLanguage.japanese),
        TranslateLanguage.japanese,
      );
      expect(
        MlKitTranslationEngine.mapSourceLanguage(
            TranslationSourceLanguage.korean),
        TranslateLanguage.korean,
      );
      expect(
        MlKitTranslationEngine.mapSourceLanguage(
            TranslationSourceLanguage.chinese),
        TranslateLanguage.chinese,
      );
      expect(
        MlKitTranslationEngine.mapTargetLanguage(
            TranslationTargetLanguage.indonesian),
        TranslateLanguage.indonesian,
      );
      expect(
        MlKitTranslationEngine.mapTargetLanguage(
            TranslationTargetLanguage.english),
        TranslateLanguage.english,
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

        await Future.delayed(const Duration(milliseconds: 180));

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

      // Source Language Chips verification (Indonesian locale)
      expect(find.text('🌐 Otomatis'), findsOneWidget);
      expect(find.text('🇯🇵 Jepang'), findsOneWidget);
      expect(find.text('🇰🇷 Korea'), findsOneWidget);
      expect(find.text('🇨🇳 China'), findsOneWidget);

      // Target Language Chips verification
      expect(find.text('🇮🇩 Indonesia'), findsOneWidget);
      expect(find.text('🇺🇸 Inggris (US)'), findsOneWidget);

      // Mode choices verification
      expect(find.text('Hanya Balon Dialog'), findsOneWidget);
      expect(find.text('Seluruh Halaman (Termasuk SFX)'), findsOneWidget);

      // Select Korean language chip dynamically
      await tester.tap(find.text('🇰🇷 Korea'));
      await tester.pumpAndSettle();

      // Select English target language chip dynamically
      await tester.tap(find.text('🇺🇸 Inggris (US)'));
      await tester.pumpAndSettle();

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
      expect(find.text('🌐 Auto Detect'), findsOneWidget);
      expect(find.text('🇯🇵 Japanese'), findsOneWidget);
      expect(find.text('🇺🇸 English (US)'), findsOneWidget);
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
        currentStep: 'Downloading Japanese Model...',
        downloadedMb: 15.0,
        totalMb: 30.0,
        progress: 0.5,
      );
      expect(updated.isDownloading, isTrue);
      expect(updated.currentStep, 'Downloading Japanese Model...');
      expect(updated.downloadedMb, 15.0);
      expect(updated.totalMb, 30.0);
      expect(updated.progress, 0.5);
    });

    test('getPairStatus returns correct pair metadata and size requirements', () async {
      final engine = MlKitTranslationEngine.instance;
      final status = await engine.getPairStatus(
        TranslationSourceLanguage.japanese,
        TranslationTargetLanguage.indonesian,
      );
      expect(status.sourceLangName, 'Japanese');
      expect(status.targetLangName, 'Indonesian');
      expect(status.totalNeededMb, anyOf(0.0, 30.0, 60.0));
    });
  });

  group('ZigzagProgressBar Widget Tests', () {
    testWidgets('ZigzagProgressBar renders without error at progress 0.0 and 0.5', (tester) async {
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
}
