import 'package:equatable/equatable.dart';

/// Represents a single photo or video discovered during local media scan.
class MediaItem extends Equatable {
  const MediaItem({
    required this.id,
    required this.path,
    required this.name,
    required this.date,
    required this.size,
    required this.isVideo,
    this.duration,
    this.width,
    this.height,
    this.mimeType,
    this.album,
    this.dateAdded,
  });

  /// MediaStore / asset ID (from photo_manager AssetEntity.id).
  final String id;

  /// Absolute file path on device.
  final String path;

  /// File name with extension.
  final String name;

  /// Date taken / created.
  final DateTime date;

  /// Date added / modified on device.
  final DateTime? dateAdded;

  /// Effective time added (falls back to date taken if dateAdded is null).
  DateTime get timeAdded => dateAdded ?? date;

  /// File size in bytes.
  final int size;

  /// True when the item is a video file.
  final bool isVideo;

  /// Video duration (null for photos).
  final Duration? duration;

  /// Media width in pixels.
  final int? width;

  /// Media height in pixels.
  final int? height;

  /// MIME type, e.g. "video/mp4", "image/jpeg".
  final String? mimeType;

  /// Optional explicit album / folder name.
  final String? album;

  /// Name of the album / folder containing this media item.
  String get albumName {
    if (album != null && album!.trim().isNotEmpty) return album!.trim();
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final folder = parts[parts.length - 2];
      if (folder.isNotEmpty) return folder;
    }
    return 'Other';
  }

  String get resolution {
    if (width == null || height == null) return '';
    return '${width}x$height';
  }

  MediaItem copyWith({
    String? id,
    String? path,
    String? name,
    DateTime? date,
    int? size,
    bool? isVideo,
    Duration? duration,
    int? width,
    int? height,
    String? mimeType,
    String? album,
    DateTime? dateAdded,
  }) {
    return MediaItem(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      date: date ?? this.date,
      size: size ?? this.size,
      isVideo: isVideo ?? this.isVideo,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      mimeType: mimeType ?? this.mimeType,
      album: album ?? this.album,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  @override
  List<Object?> get props =>
      [id, path, name, date, dateAdded, size, isVideo, duration, width, height, mimeType, album];
}
