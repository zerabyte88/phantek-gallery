import 'package:flutter/material.dart';
import '../features/gallery/presentation/gallery_screen.dart';
import '../features/gallery/presentation/album_detail_screen.dart';
import '../features/player/presentation/image_viewer_screen.dart';
import '../features/player/presentation/video_player_screen.dart';
import '../features/trash/presentation/trash_screen.dart';
import '../features/vault/presentation/vault_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../core/models/media_item.dart';

/// Global navigator key allowing overlays and dialogs to be shown from anywhere.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Named route constants.
class AppRoutes {
  static const gallery = '/';
  static const image = '/image';
  static const video = '/video';
  static const trash = '/trash';
  static const vault = '/vault';
  static const settings = '/settings';
  static const album = '/album';
}

Route<dynamic> generateRoute(RouteSettings s) {
  switch (s.name) {
    case AppRoutes.gallery:
      return _slide(const GalleryScreen());

    case AppRoutes.album:
      final albumName = s.arguments as String;
      return _slide(AlbumDetailScreen(albumName: albumName));

    case AppRoutes.image:
      final args = s.arguments as _ViewerArgs;
      return _mediaViewerRoute(
        ImageViewerScreen(
          items: args.items,
          initialIndex: args.initialIndex,
          isTrash: args.isTrash,
          startSlideshow: args.startSlideshow,
        ),
        duration: const Duration(milliseconds: 300),
      );

    case AppRoutes.video:
      if (s.arguments is _ViewerArgs) {
        final args = s.arguments as _ViewerArgs;
        return _mediaViewerRoute(
          VideoPlayerScreen(
            items: args.items,
            initialIndex: args.initialIndex,
            isTrash: args.isTrash,
            startSlideshow: args.startSlideshow,
          ),
          duration: const Duration(milliseconds: 300),
        );
      } else if (s.arguments is MediaItem) {
        final item = s.arguments as MediaItem;
        return _mediaViewerRoute(
          VideoPlayerScreen(item: item),
          duration: const Duration(milliseconds: 300),
        );
      }
      return _slide(const GalleryScreen());

    case AppRoutes.trash:
      return _slide(const TrashScreen());

    case AppRoutes.vault:
      return _slide(const VaultScreen());

    case AppRoutes.settings:
      return _slide(const SettingsScreen());

    default:
      return _slide(const GalleryScreen());
  }
}

PageRoute<T> _slide<T>(
  Widget page, {
  Duration duration = const Duration(milliseconds: 300),
}) =>
    PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(
          parent: anim,
          curve: const Cubic(0.2, 0.0, 0.0, 1.0),
          reverseCurve: const Cubic(0.2, 0.0, 0.0, 1.0),
        ),
        child: child,
      ),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );

PageRoute<T> _mediaViewerRoute<T>(
  Widget page, {
  Duration duration = const Duration(milliseconds: 300),
}) =>
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, __, ___, child) => child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );

/// Argument bundle for the image viewer.
class _ViewerArgs {
  const _ViewerArgs({
    required this.items,
    required this.initialIndex,
    this.isTrash = false,
    this.startSlideshow = false,
  });
  final List<MediaItem> items;
  final int initialIndex;
  final bool isTrash;
  final bool startSlideshow;
}

/// Helper extension on [NavigatorState] so call sites are clean.
extension AppNav on NavigatorState {
  Future<void> openImage(
    List<MediaItem> items,
    int index, {
    bool isTrash = false,
    bool startSlideshow = false,
  }) =>
      pushNamed(
        AppRoutes.image,
        arguments: _ViewerArgs(
          items: items,
          initialIndex: index,
          isTrash: isTrash,
          startSlideshow: startSlideshow,
        ),
      );

  Future<void> openVideo(
    List<MediaItem> items,
    int index, {
    bool isTrash = false,
    bool startSlideshow = false,
  }) =>
      pushNamed(
        AppRoutes.video,
        arguments: _ViewerArgs(
          items: items,
          initialIndex: index,
          isTrash: isTrash,
          startSlideshow: startSlideshow,
        ),
      );

  Future<void> openSingleVideo(MediaItem item) =>
      pushNamed(AppRoutes.video, arguments: item);

  Future<void> openTrash() => pushNamed(AppRoutes.trash);
  Future<void> openVault() => pushNamed(AppRoutes.vault);
  Future<void> openSettings() => pushNamed(AppRoutes.settings);
  Future<void> openAlbum(String albumName) =>
      pushNamed(AppRoutes.album, arguments: albumName);
}
