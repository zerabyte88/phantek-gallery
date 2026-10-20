import 'package:flutter/material.dart';

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

  @override
  State<ShimmerLoadingTile> createState() => _ShimmerLoadingTileState();
}

class _ShimmerLoadingTileState extends State<ShimmerLoadingTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
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

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
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
    );
  }
}
