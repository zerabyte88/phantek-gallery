import 'package:equatable/equatable.dart';
import 'media_item.dart';

/// Represents a media item that has been moved to the trash.
class TrashItem extends Equatable {
  const TrashItem({
    required this.id,
    required this.originalPath,
    required this.trashPath,
    required this.name,
    required this.deletedDate,
    required this.isVideo,
    this.size,
  });

  /// Unique identifier (original MediaItem.id).
  final String id;

  /// Absolute path where the file originally lived.
  final String originalPath;

  /// Absolute path inside the trash folder.
  final String trashPath;

  /// Original file name.
  final String name;

  /// When the item was moved to trash.
  final DateTime deletedDate;

  final bool isVideo;
  final int? size;

  TrashItem copyWith({
    String? id,
    String? originalPath,
    String? trashPath,
    String? name,
    DateTime? deletedDate,
    bool? isVideo,
    int? size,
  }) {
    return TrashItem(
      id: id ?? this.id,
      originalPath: originalPath ?? this.originalPath,
      trashPath: trashPath ?? this.trashPath,
      name: name ?? this.name,
      deletedDate: deletedDate ?? this.deletedDate,
      isVideo: isVideo ?? this.isVideo,
      size: size ?? this.size,
    );
  }

  MediaItem toMediaItem() => MediaItem(
        id: id,
        path: trashPath,
        name: name,
        date: deletedDate,
        size: size ?? 0,
        isVideo: isVideo,
      );

  @override
  List<Object?> get props =>
      [id, originalPath, trashPath, name, deletedDate, isVideo, size];
}
