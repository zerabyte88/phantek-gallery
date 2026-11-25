import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/enums/sort_option.dart';
import 'package:phantek_gallery/core/enums/timeline_grouping.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/providers/media_provider.dart';
import 'package:phantek_gallery/core/providers/settings_provider.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/features/gallery/presentation/gallery_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/album_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/media_grid_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TrackingMediaListNotifier extends MediaListNotifier {
  _TrackingMediaListNotifier({
    this.initialItems,
    this.initialError,
    this.pendingCompleter,
  });

  final List<MediaItem>? initialItems;
  final Object? initialError;
  final Completer<List<MediaItem>>? pendingCompleter;
  int refreshCalls = 0;

  @override
  Future<List<MediaItem>> build() async {
    if (pendingCompleter != null) return pendingCompleter!.future;
    if (initialError != null) throw initialError!;
    return initialItems ?? const [];
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

MediaItem _item({
  required String id,
  required String name,
  required String album,
  required DateTime date,
  bool isVideo = false,
  int size = 200 * 1024,
  String? path,
}) {
  return MediaItem(
    id: id,
    path: path ?? '/storage/emulated/0/Pictures/$album/$name',
    name: name,
    date: date,
    dateAdded: date,
    size: size,
    isVideo: isVideo,
    album: album,
  );
}

Widget _wrapGallery(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('en')],
      home: GalleryScreen(),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _mockPermissionChannels({
  required bool manageStorageGranted,
  int? photoManagerResult,
  List<int>? photoManagerSequence,
}) {
  var callIdx = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async {
      if (call.method == 'checkPermissionStatus') {
        return manageStorageGranted ? 1 : 0; // PermissionStatus.granted = 1
      }
      return 0;
    },
  );

  messenger.setMockMethodCallHandler(
    const MethodChannel('com.fluttercandies/photo_manager'),
    (call) async {
      if (call.method == 'requestPermissionExtend') {
        if (photoManagerSequence != null && photoManagerSequence.isNotEmpty) {
          final idx = callIdx < photoManagerSequence.length
              ? callIdx
              : photoManagerSequence.length - 1;
          callIdx++;
          return photoManagerSequence[idx];
        }
        return photoManagerResult ?? 3; // PermissionState.authorized = 3
      }
      return null;
    },
  );
}

void _clearPermissionChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.fluttercandies/photo_manager'),
    null,
  );
}

void main() {
  tearDown(_clearPermissionChannelMocks);

  group('GalleryScreen startup optimizations', () {
    testWidgets(
      'single-sort tab derivation preserves order across All, Photos, and Videos',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        _mockPermissionChannels(manageStorageGranted: true);

        final items = [
          _item(
            id: 'p1',
            name: 'a_photo.jpg',
            album: 'Camera',
            date: DateTime(2026, 3, 1),
          ),
          _item(
            id: 'v1',
            name: 'b_video.mp4',
            album: 'Movies',
            date: DateTime(2026, 3, 3),
            isVideo: true,
          ),
          _item(
            id: 'p2',
            name: 'c_photo.jpg',
            album: 'Camera',
            date: DateTime(2026, 3, 4),
          ),
          _item(
            id: 'v2',
            name: 'd_video.mp4',
            album: 'Movies',
            date: DateTime(2026, 3, 2),
            isVideo: true,
          ),
        ];
        final notifier = _TrackingMediaListNotifier(initialItems: items);

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(GalleryScreen)),
        );
        container.read(settingsNotifierProvider.notifier).update(
              (s) => s.copyWith(
                timelineGrouping: TimelineGrouping.continuous,
                defaultSort: SortOption.newest,
              ),
            );
        await _pumpFrames(tester);

        List<String> visibleIds() => tester
            .widgetList<MediaGridItem>(find.byType(MediaGridItem))
            .map((w) => w.item.id)
            .toList();

        // All tab: newest first -> p2, v1, v2, p1
        expect(visibleIds(), ['p2', 'v1', 'v2', 'p1']);

        // Switch to Photos tab -> p2, p1
        await tester.tap(find.text('Photos'));
        await _pumpFrames(tester);
        expect(visibleIds(), ['p2', 'p1']);

        // Switch to Videos tab -> v1, v2
        await tester.tap(find.text('Videos'));
        await _pumpFrames(tester);
        expect(visibleIds(), ['v1', 'v2']);

        // Sort change invalidates and updates derived tabs
        container.read(settingsNotifierProvider.notifier).update(
              (s) => s.copyWith(defaultSort: SortOption.oldest),
            );
        await _pumpFrames(tester);
        expect(visibleIds(), ['v2', 'v1']);
      },
    );

    testWidgets(
      'lazy albums compute on demand and invalidate on favorites, filters, sort, and selection',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        _mockPermissionChannels(manageStorageGranted: true);

        final items = [
          _item(
            id: '1',
            name: 'cam.jpg',
            album: 'Camera',
            date: DateTime(2026, 3, 2),
            size: 200 * 1024,
          ),
          _item(
            id: '2',
            name: 'tiny.jpg',
            album: 'Tiny',
            date: DateTime(2026, 3, 1),
            size: 10 * 1024,
          ),
          _item(
            id: '3',
            name: 'secret.jpg',
            album: '.Secret',
            path: '/storage/emulated/0/.Secret/secret.jpg',
            date: DateTime(2026, 3, 3),
            size: 200 * 1024,
          ),
        ];
        final notifier = _TrackingMediaListNotifier(initialItems: items);

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(GalleryScreen)),
        );
        await _pumpFrames(tester);

        // Navigate to Albums tab
        await tester.tap(find.text('Albums'));
        await _pumpFrames(tester);

        List<String> albumNames() => tester
            .widgetList<AlbumGridItem>(find.byType(AlbumGridItem))
            .map((w) => w.album.name)
            .toList();

        // Hidden .Secret excluded by default
        expect(albumNames(), ['Camera', 'Tiny']);

        // Toggle favorite -> Favorites album appears
        container.read(settingsNotifierProvider.notifier).update(
              (s) => s.copyWith(favoriteIds: const ['1']),
            );
        await _pumpFrames(tester);
        expect(albumNames(), ['Favorites', 'Camera', 'Tiny']);

        // Enable filterSmallImages -> Tiny album removed
        container.read(settingsNotifierProvider.notifier).update(
              (s) => s.copyWith(filterSmallImages: true),
            );
        await _pumpFrames(tester);
        expect(albumNames(), ['Favorites', 'Camera']);

        // Enable showHiddenFiles -> .Secret appears
        container.read(settingsNotifierProvider.notifier).update(
              (s) => s.copyWith(showHiddenFiles: true),
            );
        await _pumpFrames(tester);
        expect(albumNames(), contains('.Secret'));

        // Long-press an album and use Select All (uses memoized albums)
        await tester.longPress(find.byType(AlbumGridItem).first);
        await _pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.select_all));
        await _pumpFrames(tester);
        expect(find.text('3 selected'), findsOneWidget);
      },
    );

    testWidgets(
      '_bootstrap skips redundant refresh when permission is granted and media exists',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        _mockPermissionChannels(manageStorageGranted: true);

        final notifier = _TrackingMediaListNotifier(
          initialItems: [
            _item(
              id: '1',
              name: 'img.jpg',
              album: 'Camera',
              date: DateTime(2026, 3, 1),
            ),
          ],
        );

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        await _pumpFrames(tester);

        expect(notifier.refreshCalls, 0);
      },
    );

    testWidgets(
      '_bootstrap skips redundant refresh while initial media load is in flight',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        _mockPermissionChannels(manageStorageGranted: true);

        final completer = Completer<List<MediaItem>>();
        final notifier = _TrackingMediaListNotifier(
          pendingCompleter: completer,
        );

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        await _pumpFrames(tester);

        expect(notifier.refreshCalls, 0);

        completer.complete([
          _item(
            id: '1',
            name: 'img.jpg',
            album: 'Camera',
            date: DateTime(2026, 3, 1),
          ),
        ]);
        await _pumpFrames(tester);
        expect(notifier.refreshCalls, 0);
      },
    );

    testWidgets(
      '_bootstrap calls refresh when permission is newly granted',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        // First call (hasMediaPermission) denied (2), second (requestMediaPermissions) authorized (3)
        _mockPermissionChannels(
          manageStorageGranted: false,
          photoManagerSequence: [2, 3],
        );

        final notifier = _TrackingMediaListNotifier(initialItems: const []);

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        await _pumpFrames(tester);

        expect(notifier.refreshCalls, 1);
      },
    );

    testWidgets(
      '_bootstrap calls refresh when permission already granted but media list is empty',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        _mockPermissionChannels(manageStorageGranted: true);

        final notifier = _TrackingMediaListNotifier(initialItems: const []);

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        await _pumpFrames(tester);

        expect(notifier.refreshCalls, 1);
      },
    );

    testWidgets(
      '_bootstrap calls refresh when mediaListProvider has an error',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.init();
        _mockPermissionChannels(manageStorageGranted: true);

        final notifier = _TrackingMediaListNotifier(
          initialError: StateError('scan failed'),
        );

        await tester.pumpWidget(
          _wrapGallery([
            mediaListProvider.overrideWith(() => notifier),
          ]),
        );
        await _pumpFrames(tester);

        expect(notifier.refreshCalls, 1);
      },
    );
  });
}
