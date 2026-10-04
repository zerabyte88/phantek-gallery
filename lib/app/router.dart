import 'package:flutter/material.dart';
import '../features/gallery/presentation/gallery_screen.dart';
import '../features/gallery/presentation/album_detail_screen.dart';
import '../features/player/presentation/image_viewer_screen.dart';
import '../features/player/presentation/video_player_screen.dart';
import '../features/trash/presentation/trash_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../core/models/media_item.dart';

/// Global navigator key allowing overlays and dialogs to be shown from anywhere.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Named route constants.
class AppRoutes {
  static const gallery  = '/';
  static const image    = '/image';
  static const video    = '/video';
  static const trash    = '/trash';
  static const settings = '/settings';
  static const album    = '/album';
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
      return _slide(
          ImageViewerScreen(
            items: args.items,
            initialIndex: args.initialIndex,
            isTrash: args.isTrash,
          ),
          duration: const Duration(milliseconds: 300));

    case AppRoutes.video:
      if (s.arguments is _ViewerArgs) {
        final args = s.arguments as _ViewerArgs;
        return _slide(VideoPlayerScreen(
          items: args.items,
          initialIndex: args.initialIndex,
          isTrash: args.isTrash,
        ));
      } else if (s.arguments is MediaItem) {
        final item = s.arguments as MediaItem;
        return _slide(VideoPlayerScreen(item: item));
      }
      return _slide(const GalleryScreen());

    case AppRoutes.trash:
      return _slide(const TrashScreen());

    case AppRoutes.settings:
      return _slide(const SettingsScreen());

    default:
      return _slide(const GalleryScreen());
  }
}

PageRoute<T> _slide<T>(Widget page,
        {Duration duration = const Duration(milliseconds: 180)}) =>
    PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );

/// Argument bundle for the image viewer.
class _ViewerArgs {
  const _ViewerArgs({
    required this.items,
    required this.initialIndex,
    this.isTrash = false,
  });
  final List<MediaItem> items;
  final int initialIndex;
  final bool isTrash;
}

/// Helper extension on [NavigatorState] so call sites are clean.
extension AppNav on NavigatorState {
  Future<void> openImage(List<MediaItem> items, int index, {bool isTrash = false}) =>
      pushNamed(AppRoutes.image,
          arguments: _ViewerArgs(items: items, initialIndex: index, isTrash: isTrash));

  Future<void> openVideo(List<MediaItem> items, int index, {bool isTrash = false}) =>
      pushNamed(AppRoutes.video,
          arguments: _ViewerArgs(items: items, initialIndex: index, isTrash: isTrash));

  Future<void> openSingleVideo(MediaItem item) =>
      pushNamed(AppRoutes.video, arguments: item);

  Future<void> openTrash() => pushNamed(AppRoutes.trash);
  Future<void> openSettings() => pushNamed(AppRoutes.settings);
  Future<void> openAlbum(String albumName) =>
      pushNamed(AppRoutes.album, arguments: albumName);
}
