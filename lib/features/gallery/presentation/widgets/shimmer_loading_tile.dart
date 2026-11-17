import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shared ref-counted ticker driving all mounted [ShimmerLoadingTile] instances
/// so scrolling grids do not allocate per-tile [AnimationController] tickers.
class _SharedShimmerTicker {
  _SharedShimmerTicker._();

  static const Duration _period = Duration(milliseconds: 1400);
  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
  static Ticker? _ticker;
  static int _mountCount = 0;

  static void attach() {
    _mountCount++;
    if (_mountCount == 1) {
      _ticker ??= Ticker((elapsed) {
        final us = elapsed.inMicroseconds % _period.inMicroseconds;
        progress.value = us / _period.inMicroseconds;
      });
      if (!_ticker!.isActive) {
        _ticker!.start();
      }
    }
  }

  static void detach() {
    if (_mountCount > 0) {
      _mountCount--;
    }
    if (_mountCount == 0) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
      progress.value = 0.0;
    }
  }
}

/// A sleek, lightweight animated shimmer skeleton used as a placeholder
/// while gallery media thumbnails and album covers are decoding.
class ShimmerLoadingTile extends StatefulWidget {
  const ShimmerLoadingTile({
    super.key,
    this.icon,
    this.isVideo = false,
  });

  final IconData? icon;
  final bool isVideo;

  @visibleForTesting
  static int get debugActiveMountCount => _SharedShimmerTicker._mountCount;

  @visibleForTesting
  static bool get debugHasActiveTicker =>
      _SharedShimmerTicker._ticker?.isActive ?? false;

  @override
  State<ShimmerLoadingTile> createState() => _ShimmerLoadingTileState();
}

class _ShimmerLoadingTileState extends State<ShimmerLoadingTile> {
  @override
  void initState() {
    super.initState();
    _SharedShimmerTicker.attach();
  }

  @override
  void dispose() {
    _SharedShimmerTicker.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF16181C)
        : cs.surfaceContainerHighest.withValues(alpha: 0.6);
    final highlightColor =
        isDark ? const Color(0xFF282C34) : cs.surfaceContainerHighest;

    final displayIcon = widget.icon ??
        (widget.isVideo ? Icons.videocam_rounded : Icons.image_rounded);

    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _SharedShimmerTicker.progress,
        builder: (context, t, child) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.5 + 3.0 * t, -0.3),
                end: Alignment(-0.5 + 3.0 * t, 0.3),
                colors: [baseColor, highlightColor, baseColor],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: child,
          );
        },
        child: Center(
          child: Icon(
            displayIcon,
            size: 24,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}
