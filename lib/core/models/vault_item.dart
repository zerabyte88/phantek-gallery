import 'dart:io';
import 'package:equatable/equatable.dart';
import 'media_item.dart';

/// Represents a media item securely stored inside the Locked Vault.
class VaultItem extends Equatable {
  const VaultItem({
    required this.id,
    required this.originalPath,
    required this.vaultPath,
    required this.name,
    required this.dateMoved,
    required this.isVideo,
    this.size,
    this.duration,
    this.width,
    this.height,
    this.mimeType,
    this.originalAlbumName,
  });

  /// Unique identifier (original MediaItem.id or unique timestamp-based ID).
  final String id;

  /// Absolute path where the file originally lived.
  final String originalPath;

  /// Absolute path inside the hidden .PhantekVault directory.
  final String vaultPath;

  /// Original file name.
  final String name;

  /// When the item was moved to the vault.
  final DateTime dateMoved;

  /// True if the item is a video.
  final bool isVideo;

  /// File size in bytes.
  final int? size;

  /// Video duration.
  final Duration? duration;

  /// Media dimensions.
  final int? width;
  final int? height;

  /// MIME type string.
  final String? mimeType;

  /// Name of the album the media originated from.
  final String? originalAlbumName;

  /// Converts this [VaultItem] into a [MediaItem] so standard gallery viewers and widgets can display it seamlessly.
  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      path: vaultPath,
      name: name,
      date: dateMoved,
      dateAdded: dateMoved,
      size: size ?? (File(vaultPath).existsSync() ? File(vaultPath).lengthSync() : 0),
      isVideo: isVideo,
      duration: duration,
      width: width,
      height: height,
      mimeType: mimeType,
      album: 'Locked Vault',
    );
  }

  VaultItem copyWith({
    String? id,
    String? originalPath,
    String? vaultPath,
    String? name,
    DateTime? dateMoved,
    bool? isVideo,
    int? size,
    Duration? duration,
    int? width,
    int? height,
    String? mimeType,
    String? originalAlbumName,
  }) {
    return VaultItem(
      id: id ?? this.id,
      originalPath: originalPath ?? this.originalPath,
      vaultPath: vaultPath ?? this.vaultPath,
      name: name ?? this.name,
      dateMoved: dateMoved ?? this.dateMoved,
      isVideo: isVideo ?? this.isVideo,
      size: size ?? this.size,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      mimeType: mimeType ?? this.mimeType,
      originalAlbumName: originalAlbumName ?? this.originalAlbumName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalPath': originalPath,
        'vaultPath': vaultPath,
        'name': name,
        'dateMoved': dateMoved.toIso8601String(),
        'isVideo': isVideo,
        'size': size,
        'durationMs': duration?.inMilliseconds,
        'width': width,
        'height': height,
        'mimeType': mimeType,
        'originalAlbumName': originalAlbumName,
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        id: json['id'] as String,
        originalPath: json['originalPath'] as String,
        vaultPath: json['vaultPath'] as String,
        name: json['name'] as String,
        dateMoved: DateTime.parse(json['dateMoved'] as String),
        isVideo: json['isVideo'] as bool,
        size: json['size'] as int?,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        width: json['width'] as int?,
        height: json['height'] as int?,
        mimeType: json['mimeType'] as String?,
        originalAlbumName: json['originalAlbumName'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        originalPath,
        vaultPath,
        name,
        dateMoved,
        isVideo,
        size,
        duration,
        width,
        height,
        mimeType,
        originalAlbumName,
      ];
}
