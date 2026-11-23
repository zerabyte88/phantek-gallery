import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/services/media_metadata_service.dart';
import '../../../../core/services/psd_service.dart';
import '../../../../core/utils/media_utils.dart';

/// Shows a bottom sheet with technical and file details for [item].
void showMediaInfoSheet(
  BuildContext context,
  MediaItem item, {
  VideoPlayerController? player,
  double? fps,
  String? codec,
  MediaMetadata? metadata,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _MediaInfoSheetContent(
      item: item,
      player: player,
      fps: fps,
      codec: codec,
      initialMetadata: metadata,
    ),
  );
}

class _MediaInfoSheetContent extends StatefulWidget {
  const _MediaInfoSheetContent({
    required this.item,
    this.player,
    this.fps,
    this.codec,
    this.initialMetadata,
  });

  final MediaItem item;
  final VideoPlayerController? player;
  final double? fps;
  final String? codec;
  final MediaMetadata? initialMetadata;

  @override
  State<_MediaInfoSheetContent> createState() => _MediaInfoSheetContentState();
}

class _MediaInfoSheetContentState extends State<_MediaInfoSheetContent> {
  static const _tabularStyle = [FontFeature.tabularFigures()];

  MediaMetadata? _metadata;

  @override
  void initState() {
    super.initState();
    _metadata = widget.initialMetadata;
    if (_metadata == null) {
      MediaMetadataService.instance.inspect(widget.item).then((loaded) {
        if (mounted && loaded != null) {
          setState(() => _metadata = loaded);
        }
      });
    }
  }

  String _formatAudioSummary(MediaMetadata meta) {
    final parts = <String>[];
    if (meta.audioCodec != null) {
      final c = MediaUtils.formatAudioCodec(meta.audioCodec!);
      if (c.isNotEmpty) parts.add(c);
    }
    if (meta.audioChannels != null && meta.audioChannels! > 0) {
      final ch = MediaUtils.formatAudioChannels(meta.audioChannels!);
      if (ch.isNotEmpty) parts.add(ch);
    }
    if (meta.audioSampleRate != null && meta.audioSampleRate! > 0) {
      final khz = meta.audioSampleRate! / 1000.0;
      final sr = khz == khz.roundToDouble()
          ? '${khz.toInt()} kHz'
          : '${khz.toStringAsFixed(1)} kHz';
      parts.add(sr);
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hairline = cs.onSurface.withValues(alpha: 0.08);
    final cardColor = cs.surfaceContainerLow;

    final item = widget.item;
    final meta = _metadata;
    final player = widget.player;

    final double? effectiveFps = widget.fps ?? meta?.fps;
    final String? effectiveCodec = widget.codec ?? meta?.videoCodec;
    final int? effectiveBitrate = meta?.bitrate;

    String resolution = item.resolution;
    Duration? duration = item.duration;

    if (player != null && player.value.isInitialized) {
      final size = player.value.size;
      if (size.width > 0 && size.height > 0) {
        resolution = '${size.width.toInt()} × ${size.height.toInt()}';
      }
      if (player.value.duration > Duration.zero) {
        duration = player.value.duration;
      }
    } else if (resolution.isEmpty &&
        meta?.width != null &&
        meta?.height != null &&
        meta!.width! > 0 &&
        meta.height! > 0) {
      resolution = '${meta.width} × ${meta.height}';
    }

    final fileFormat =
        MediaUtils.formatFileFormat(item.path, mimeType: meta?.mimeType);
    final colorSpace = meta?.colorSpace != null
        ? MediaUtils.formatColorSpace(meta!.colorSpace!)
        : '';
    final audioSummary =
        (item.isVideo && meta != null) ? _formatAudioSummary(meta) : '';
    final isPsd = !item.isVideo && PsdService.isPsd(item.path);
    final psdLayers =
        isPsd ? PsdService.instance.getCachedLayersSync(item.path) : null;

    // Compact 2-column technical spec items (empty values omitted).
    final gridSpecs = <({String label, String value})>[
      (label: context.tr.size, value: MediaUtils.formatSize(item.size)),
      if (fileFormat.isNotEmpty) (label: context.tr.format, value: fileFormat),
      if (resolution.isNotEmpty)
        (label: context.tr.resolution, value: resolution),
      if (!item.isVideo && colorSpace.isNotEmpty)
        (label: context.tr.colorSpace, value: colorSpace),
      if (!item.isVideo && meta?.dpi != null && meta!.dpi! > 0)
        (label: context.tr.dpi, value: '${meta.dpi} DPI'),
      if (psdLayers != null && psdLayers.isNotEmpty)
        (label: context.tr.layers, value: '${psdLayers.length}'),
      if (item.isVideo && duration != null)
        (label: context.tr.duration, value: MediaUtils.formatDuration(duration)),
      if (item.isVideo && effectiveFps != null && effectiveFps > 0)
        (label: context.tr.frameRate, value: MediaUtils.formatFps(effectiveFps)),
      if (item.isVideo &&
          effectiveCodec != null &&
          effectiveCodec.trim().isNotEmpty)
        (label: context.tr.codec, value: MediaUtils.formatCodec(effectiveCodec)),
      if (item.isVideo && effectiveBitrate != null && effectiveBitrate > 0)
        (
          label: context.tr.bitrate,
          value: MediaUtils.formatBitrate(effectiveBitrate),
        ),
    ];

    final fullWidthSpecs = <({IconData icon, String label, String value})>[
      if (!item.isVideo &&
          meta?.software != null &&
          meta!.software!.isNotEmpty)
        (
          icon: Icons.brush_outlined,
          label: context.tr.software,
          value: meta.software!,
        ),
      if (item.isVideo && audioSummary.isNotEmpty)
        (
          icon: Icons.graphic_eq_outlined,
          label: context.tr.audio,
          value: audioSummary,
        ),
    ];

    final exposureChips = <String>[];
    if (!item.isVideo && meta != null) {
      if (meta.aperture != null) {
        final f = MediaUtils.formatAperture(meta.aperture!);
        if (f.isNotEmpty) exposureChips.add(f);
      }
      if (meta.shutterSpeed != null) {
        final s = MediaUtils.formatShutterSpeed(meta.shutterSpeed!);
        if (s.isNotEmpty) exposureChips.add(s);
      }
      if (meta.iso != null && meta.iso! > 0) {
        exposureChips.add('ISO ${meta.iso}');
      }
      if (meta.focalLength != null) {
        final fl = MediaUtils.formatFocalLength(
          meta.focalLength!,
          focalLength35mm: meta.focalLength35mm,
        );
        if (fl.isNotEmpty) exposureChips.add(fl);
      }
    }

    final hasCameraBlock = !item.isVideo &&
        meta != null &&
        ((meta.camera != null && meta.camera!.isNotEmpty) ||
            exposureChips.isNotEmpty);

    void copyPath() {
      Clipboard.setData(ClipboardData(text: item.path));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr.pathCopied),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final mediaIcon = item.isVideo
        ? Icons.movie_outlined
        : (isPsd ? Icons.layers_outlined : Icons.image_outlined);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr.details,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      letterSpacing: 0,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          mediaIcon,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                letterSpacing: 0,
                                color: cs.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${MediaUtils.formatViewerDate(item.date)}, ${MediaUtils.formatViewerTime(item.date)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                                letterSpacing: 0,
                                color: cs.onSurfaceVariant,
                                fontFeatures: _tabularStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (gridSpecs.isNotEmpty || fullWidthSpecs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SpecGroupCard(
                      color: cardColor,
                      borderColor: hairline,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < gridSpecs.length; i += 2) ...[
                            if (i > 0) Divider(height: 1, color: hairline),
                            if (i + 1 < gridSpecs.length)
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _SpecCell(
                                        label: gridSpecs[i].label,
                                        value: gridSpecs[i].value,
                                      ),
                                    ),
                                    VerticalDivider(width: 1, color: hairline),
                                    Expanded(
                                      child: _SpecCell(
                                        label: gridSpecs[i + 1].label,
                                        value: gridSpecs[i + 1].value,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              SizedBox(
                                width: double.infinity,
                                child: _SpecCell(
                                  label: gridSpecs[i].label,
                                  value: gridSpecs[i].value,
                                ),
                              ),
                          ],
                          for (final row in fullWidthSpecs) ...[
                            if (gridSpecs.isNotEmpty)
                              Divider(height: 1, color: hairline),
                            _CardInfoRow(
                              icon: row.icon,
                              label: row.label,
                              value: row.value,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (hasCameraBlock) ...[
                    const SizedBox(height: 12),
                    _SpecGroupCard(
                      color: cardColor,
                      borderColor: hairline,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (meta.camera != null && meta.camera!.isNotEmpty)
                            _CardInfoRow(
                              icon: Icons.camera_alt_outlined,
                              label: context.tr.camera,
                              value: meta.camera!,
                            ),
                          if (exposureChips.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                (meta.camera != null && meta.camera!.isNotEmpty)
                                    ? 0
                                    : 12,
                                16,
                                12,
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final chip in exposureChips)
                                    _ExifSpecChip(
                                      text: chip,
                                      borderColor: hairline,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SpecGroupCard(
                    color: cardColor,
                    borderColor: hairline,
                    child: InkWell(
                      onTap: copyPath,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr.path,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      height: 1.33,
                                      letterSpacing: 0,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.path,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      height: 1.4,
                                      letterSpacing: 0,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.copy_outlined,
                                size: 20,
                                color: cs.onSurfaceVariant,
                              ),
                              tooltip: context.tr.copyPath,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed: copyPath,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecGroupCard extends StatelessWidget {
  const _SpecGroupCard({
    required this.color,
    required this.borderColor,
    required this.child,
  });

  final Color color;
  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SpecCell extends StatelessWidget {
  const _SpecCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.33,
              letterSpacing: 0,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
              letterSpacing: 0,
              color: cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardInfoRow extends StatelessWidget {
  const _CardInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.33,
                    letterSpacing: 0,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    letterSpacing: 0,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExifSpecChip extends StatelessWidget {
  const _ExifSpecChip({
    required this.text,
    required this.borderColor,
  });

  final String text;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.2,
          letterSpacing: 0,
          color: cs.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
