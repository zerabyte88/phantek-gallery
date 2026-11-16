import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/providers/settings_provider.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/widgets/styled_popup_menu.dart';
import 'package:phantek_gallery/features/player/presentation/video_player_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  final SettingsModel initial;
  _TestSettingsNotifier(this.initial);

  @override
  SettingsModel build() => initial;
}

void main() {
  testWidgets(
      'StyledMoreMenuButton bottomBar opens strictly above trigger, hugs compact width, and uses hairline border',
      (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    String? picked;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 16),
              child: StyledMoreMenuButton<String>(
                placement: StyledMenuPlacement.bottomBar,
                forceDark: true,
                onSelected: (value) => picked = value,
                actions: const [
                  StyledMenuAction(
                    value: 'like',
                    icon: Icons.favorite_border,
                    label: 'Like',
                  ),
                  StyledMenuAction(
                    value: 'share',
                    icon: Icons.share_outlined,
                    label: 'Share',
                  ),
                  StyledMenuAction(
                    value: 'edit',
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                  ),
                  StyledMenuAction(
                    value: 'delete',
                    icon: Icons.delete_outline,
                    label: 'Del',
                    isDestructive: true,
                  ),
                ],
                child: const Padding(
                  key: Key('bottom_more_trigger'),
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.more_vert_rounded, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final triggerFinder = find.byKey(const Key('bottom_more_trigger'));
    final triggerRect = tester.getRect(triggerFinder);

    await tester.tap(triggerFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Locate the popup surface Material wrapping the menu items.
    final likeFinder = find.text('Like');
    expect(likeFinder, findsOneWidget);

    final menuMaterialFinder = find.ancestor(
      of: likeFinder,
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.shape is RoundedRectangleBorder,
      ),
    );
    expect(menuMaterialFinder, findsOneWidget);

    final menuMaterial = tester.widget<Material>(menuMaterialFinder);
    final shape = menuMaterial.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(14));
    expect(shape.side, isNot(BorderSide.none));
    expect(shape.side.width, closeTo(0.9, 0.01));

    final menuRect = tester.getRect(menuMaterialFinder);
    expect(
      menuRect.bottom,
      lessThanOrEqualTo(triggerRect.top),
      reason: 'Bottom-bar menu should open cleanly above the trigger button',
    );
    expect(
      menuRect.width,
      lessThan(180),
      reason: 'Menu should hug compact labels instead of stretching to maxWidth',
    );

    // Destructive action is tinted redAccent.
    final deleteText = tester.widget<Text>(find.text('Del'));
    expect(deleteText.style?.color, Colors.redAccent);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(picked, 'share');
  });

  testWidgets(
      'StyledMoreMenuButton topBar opens below trigger and adapts to light theme',
      (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    final lightTheme = ThemeData.light();

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          appBar: AppBar(
            actions: [
              StyledMoreMenuButton<String>(
                placement: StyledMenuPlacement.topBar,
                icon: const Icon(Icons.more_vert),
                onSelected: (_) {},
                actions: const [
                  StyledMenuAction(
                    value: 'select',
                    icon: Icons.checklist_rounded,
                    label: 'Select',
                  ),
                  StyledMenuAction(
                    value: 'manga',
                    icon: Icons.auto_stories_rounded,
                    label: 'Manga',
                    isActive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final triggerFinder = find.byIcon(Icons.more_vert);
    final triggerRect = tester.getRect(triggerFinder);

    await tester.tap(triggerFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final selectFinder = find.text('Select');
    expect(selectFinder, findsOneWidget);

    final menuMaterialFinder = find.ancestor(
      of: selectFinder,
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.shape is RoundedRectangleBorder,
      ),
    );
    expect(menuMaterialFinder, findsOneWidget);

    final menuMaterial = tester.widget<Material>(menuMaterialFinder);
    expect(menuMaterial.color, lightTheme.colorScheme.surfaceContainerHigh);

    final menuRect = tester.getRect(menuMaterialFinder);
    expect(
      menuRect.top,
      greaterThanOrEqualTo(triggerRect.bottom),
      reason: 'Top-bar menu should open cleanly below the AppBar trigger',
    );

    final activeText = tester.widget<Text>(find.text('Manga'));
    expect(activeText.style?.color, lightTheme.colorScheme.primary);
  });

  testWidgets(
      'Landscape VideoPlayerScreen 3-dot menu excludes Slideshow and shows Favorite, Share, Rename, Delete',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    final videoItem = MediaItem(
      id: 'vid_1',
      path: '/storage/emulated/0/Movies/sample.mp4',
      name: 'sample.mp4',
      date: DateTime(2026, 1, 1),
      size: 1024 * 1024,
      isVideo: true,
      width: 1920,
      height: 1080,
      duration: const Duration(seconds: 30),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsNotifierProvider.overrideWith(
            () => _TestSettingsNotifier(
              const SettingsModel(autoPlayVideo: false),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: VideoPlayerScreen(
            items: [videoItem],
            initialIndex: 0,
            isTrash: false,
          ),
        ),
      ),
    );

    // Allow initPlayer stages to settle without leaving pending timers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final moreTrigger = find.byIcon(Icons.more_vert_rounded);
    expect(moreTrigger, findsOneWidget);

    await tester.tap(moreTrigger);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.slideshow_rounded), findsNothing);
    expect(find.text('Slideshow'), findsNothing);

    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Close menu and dispose tree cleanly.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets(
      'Portrait VideoPlayerScreen 3-dot menu keeps Slideshow alongside Speed, Loop, Rename',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    final videoItem = MediaItem(
      id: 'vid_2',
      path: '/storage/emulated/0/Movies/portrait.mp4',
      name: 'portrait.mp4',
      date: DateTime(2026, 1, 1),
      size: 1024 * 1024,
      isVideo: true,
      width: 1080,
      height: 1920,
      duration: const Duration(seconds: 15),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsNotifierProvider.overrideWith(
            () => _TestSettingsNotifier(
              const SettingsModel(autoPlayVideo: false),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: VideoPlayerScreen(
            items: [videoItem],
            initialIndex: 0,
            isTrash: false,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final moreTrigger = find.byIcon(Icons.more_vert);
    expect(moreTrigger, findsOneWidget);

    await tester.tap(moreTrigger);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.slideshow_rounded), findsOneWidget);
    expect(find.text('Slideshow'), findsOneWidget);
    expect(find.textContaining('Speed'), findsOneWidget);
    expect(find.text('Loop: Off'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
