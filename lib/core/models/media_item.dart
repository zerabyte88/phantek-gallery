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
  });

  /// MediaStore / asset ID (from photo_manager AssetEntity.id).
  final String id;

  /// Absolute file path on device.
  final String path;

  /// File name with extension.
  final String name;

  /// Date taken / last modified.
  final DateTime date;

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
    );
  }

  @override
  List<Object?> get props =>
      [id, path, name, date, size, isVideo, duration, width, height, mimeType];
}
