import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/app/theme.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Grid Columns & Albums Grid Columns 2x2 Picker (Mockup B)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();
    });

    testWidgets(
      'renders 2x2 visual card picker and adapts colors across all 6 themes',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final themes = <String, ThemeData>{
          'amoledPure': AppTheme.amoledPure,
          'amoledSnowfall': AppTheme.amoledSnowfall,
          'amoledMidnight': AppTheme.amoledMidnight,
          'amoledSakura': AppTheme.amoledSakura,
          'light': AppTheme.light,
          'cleanLight': AppTheme.cleanLight,
        };

        for (final entry in themes.entries) {
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey(entry.key),
              child: MaterialApp(
                theme: entry.value,
                home: const SettingsScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.ensureVisible(find.text('Grid Columns'));
          await tester.tap(find.text('Grid Columns'));
          await tester.pumpAndSettle();

          final dialogFinder = find.byType(Dialog);
          expect(find.text('Select Grid Columns'), findsOneWidget,
              reason: 'Dialog should open in ${entry.key}');
          final col2 = find.descendant(
              of: dialogFinder, matching: find.text('2 columns'));
          final col3 = find.descendant(
              of: dialogFinder, matching: find.text('3 columns'));
          final col4 = find.descendant(
              of: dialogFinder, matching: find.text('4 columns'));
          final col5 = find.descendant(
              of: dialogFinder, matching: find.text('5 columns'));
          expect(col2, findsOneWidget);
          expect(col3, findsOneWidget);
          expect(col4, findsOneWidget);
          expect(col5, findsOneWidget);

          // Verify 2x2 layout: cards 2 & 3 share a row, cards 4 & 5 share a row below.
          final pos2 = tester.getTopLeft(col2);
          final pos3 = tester.getTopLeft(col3);
          final pos4 = tester.getTopLeft(col4);
          final pos5 = tester.getTopLeft(col5);
          expect((pos2.dy - pos3.dy).abs(), lessThan(4.0));
          expect(pos3.dx, greaterThan(pos2.dx));
          expect((pos4.dy - pos5.dy).abs(), lessThan(4.0));
          expect(pos5.dx, greaterThan(pos4.dx));
          expect(pos4.dy, greaterThan(pos2.dy));

          // Verify checkmark and density descriptions are removed, and labels are centered.
          expect(find.byIcon(Icons.check_rounded), findsNothing);
          expect(find.text('Standard balanced'), findsNothing);
          expect(tester.widget<Text>(col3).textAlign, TextAlign.center);

          // Verify selected card border adapts to active theme colorScheme.primary.
          final selectedCard = tester.widget<AnimatedContainer>(
            find.ancestor(of: col3, matching: find.byType(AnimatedContainer)),
          );
          final boxDeco = selectedCard.decoration! as BoxDecoration;
          expect((boxDeco.border! as Border).top.color,
              entry.value.colorScheme.primary);
          expect(tester.takeException(), isNull);

          // Select 4 columns and verify dismissal + update.
          await tester.tap(col4);
          await tester.pumpAndSettle();
          expect(find.text('Select Grid Columns'), findsNothing);
          expect(find.text('4 columns'), findsOneWidget);

          // Open Albums Grid Columns dialog and select 2 columns.
          await tester.ensureVisible(find.text('Albums Grid Columns'));
          await tester.tap(find.text('Albums Grid Columns'));
          await tester.pumpAndSettle();
          expect(find.text('Select Albums Grid Columns'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.descendant(
              of: dialogFinder, matching: find.text('2 columns')));
          await tester.pumpAndSettle();
          expect(find.text('Select Albums Grid Columns'), findsNothing);

          SharedPreferences.setMockInitialValues({});
          await SettingsService.init();
        }
      },
    );

    testWidgets(
      '2x2 picker dialog has zero overflow at 2.0x text scale on 360dp phone',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final isAlbum in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showGridColumnsDialogForTesting(
                        ctx,
                        3,
                        isAlbum: isAlbum,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull,
              reason: 'No overflow at 2.0x text scale (isAlbum: $isAlbum)');
          expect(find.text('2 columns'), findsOneWidget);
          expect(find.text('5 columns'), findsOneWidget);

          await tester.ensureVisible(find.text('5 columns'));
          await tester.tap(find.text('5 columns'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        }
      },
    );
  });
}
