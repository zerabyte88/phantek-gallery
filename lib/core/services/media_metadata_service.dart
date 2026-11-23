import 'dart:collection';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/media_item.dart';

/// Technical metadata extracted natively from a photo or video file.
class MediaMetadata {
  const MediaMetadata({
    this.mimeType,
    this.width,
    this.height,
    this.colorSpace,
    this.dpi,
    this.software,
    this.camera,
    this.iso,
    this.aperture,
    this.shutterSpeed,
    this.focalLength,
    this.focalLength35mm,
    this.bitrate,
    this.fps,
    this.videoCodec,
    this.audioCodec,
    this.audioChannels,
    this.audioSampleRate,
  });

  final String? mimeType;
  final int? width;
  final int? height;
  final String? colorSpace;
  final int? dpi;
  final String? software;

  // Camera EXIF (absent on non-camera artwork & stripped downloads)
  final String? camera;
  final int? iso;
  final double? aperture;
  final double? shutterSpeed;
  final double? focalLength;
  final int? focalLength35mm;

  // Video & Audio stream properties
  final int? bitrate;
  final double? fps;
  final String? videoCodec;
  final String? audioCodec;
  final int? audioChannels;
  final int? audioSampleRate;

  bool get hasCameraExif =>
      (camera != null && camera!.isNotEmpty) ||
      iso != null ||
      aperture != null ||
      shutterSpeed != null ||
      focalLength != null;

  factory MediaMetadata.fromMap(Map<dynamic, dynamic> map) {
    int? asInt(String k) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    double? asDouble(String k) {
      final v = map[k];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return null;
    }

    String? asStr(String k) {
      final v = map[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    return MediaMetadata(
      mimeType: asStr('mimeType'),
      width: asInt('width'),
      height: asInt('height'),
      colorSpace: asStr('colorSpace'),
      dpi: asInt('dpi'),
      software: asStr('software'),
      camera: asStr('camera'),
      iso: asInt('iso'),
      aperture: asDouble('aperture'),
      shutterSpeed: asDouble('shutterSpeed'),
      focalLength: asDouble('focalLength'),
      focalLength35mm: asInt('focalLength35mm'),
      bitrate: asInt('bitrate'),
      fps: asDouble('fps'),
      videoCodec: asStr('videoCodec'),
      audioCodec: asStr('audioCodec'),
      audioChannels: asInt('audioChannels'),
      audioSampleRate: asInt('audioSampleRate'),
    );
  }
}

/// Bridges Flutter to native Android ExifInterface / MediaExtractor metadata extraction.
class MediaMetadataService {
  MediaMetadataService._();
  static final MediaMetadataService instance = MediaMetadataService._();

  static const _channel = MethodChannel('com.phantek.gallery/metadata');
  static const int _maxCacheEntries = 40;
  final LinkedHashMap<String, MediaMetadata> _cache = LinkedHashMap();

  Future<MediaMetadata?> inspect(MediaItem item) async {
    final key = '${item.id}|${item.path}|${item.size}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getMediaMetadata',
        <String, dynamic>{
          'path': item.path,
          'assetId': item.id,
          'isVideo': item.isVideo,
        },
      );
      if (raw == null || raw.isEmpty) return null;
      final parsed = MediaMetadata.fromMap(raw);
      _cache[key] = parsed;
      if (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }
}
