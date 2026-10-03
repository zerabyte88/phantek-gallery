import 'package:flutter/material.dart';
import '../features/gallery/presentation/gallery_screen.dart';
import '../features/player/presentation/image_viewer_screen.dart';
import '../features/player/presentation/video_player_screen.dart';
import '../features/trash/presentation/trash_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../core/models/media_item.dart';

/// Named route constants.
class AppRoutes {
  static const gallery  = '/';
  static const image    = '/image';
  static const video    = '/video';
  static const trash    = '/trash';
  static const settings = '/settings';
}

Route<dynamic> generateRoute(RouteSettings s) {
  switch (s.name) {
    case AppRoutes.gallery:
      return _slide(const GalleryScreen());

    case AppRoutes.image:
      final args = s.arguments as _ViewerArgs;
      return _slide(ImageViewerScreen(
        items: args.items,
        initialIndex: args.initialIndex,
      ));

    case AppRoutes.video:
      final item = s.arguments as MediaItem;
      return _slide(VideoPlayerScreen(item: item));

    case AppRoutes.trash:
      return _slide(const TrashScreen());

    case AppRoutes.settings:
      return _slide(const SettingsScreen());

    default:
      return _slide(const GalleryScreen());
  }
}

PageRoute<T> _slide<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 180),
    );

/// Argument bundle for the image viewer.
class _ViewerArgs {
  const _ViewerArgs({required this.items, required this.initialIndex});
  final List<MediaItem> items;
  final int initialIndex;
}

/// Helper extension on [NavigatorState] so call sites are clean.
extension AppNav on NavigatorState {
  Future<void> openImage(List<MediaItem> items, int index) =>
      pushNamed(AppRoutes.image,
          arguments: _ViewerArgs(items: items, initialIndex: index));

  Future<void> openVideo(MediaItem item) =>
      pushNamed(AppRoutes.video, arguments: item);

  Future<void> openTrash() => pushNamed(AppRoutes.trash);
  Future<void> openSettings() => pushNamed(AppRoutes.settings);
}
