import 'dart:async';
import 'package:flutter/material.dart';

/// A right-edge-docked fast-scroll thumb handle that appears when scrolling
/// vertically, tracks scroll progress, and auto-hides after [hideDelay].
class FastScrollHandle extends StatefulWidget {
  const FastScrollHandle({
    super.key,
    required this.controller,
    required this.child,
    this.hideDelay = const Duration(seconds: 3),
  });

  final ScrollController controller;
  final Widget child;
  final Duration hideDelay;

  @override
  State<FastScrollHandle> createState() => _FastScrollHandleState();
}

class _FastScrollHandleState extends State<FastScrollHandle> {
  static const double _handleWidth = 38.0;
  static const double _handleHeight = 54.0;
  static const double _topPadding = 12.0;
  static const double _bottomPadding = 16.0;

  final ValueNotifier<double> _fractionNotifier = ValueNotifier<double>(0.0);
  bool _visible = false;
  bool _isDragging = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fractionNotifier.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.hideDelay, () {
      if (mounted && !_isDragging && _visible) {
        setState(() => _visible = false);
      }
    });
  }

  void _showAndScheduleHide() {
    if (!_visible && mounted) {
      setState(() => _visible = true);
    }
    if (!_isDragging) {
      _scheduleHide();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      final maxExtent = notification.metrics.maxScrollExtent;
      if (maxExtent > 0) {
        if (!_isDragging) {
          _fractionNotifier.value =
              (notification.metrics.pixels / maxExtent).clamp(0.0, 1.0);
        }
        _showAndScheduleHide();
      }
    } else if (notification is ScrollEndNotification) {
      if (!_isDragging && _visible) {
        _scheduleHide();
      }
    }
    return false;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _hideTimer?.cancel();
    _isDragging = true;
    if (!_visible && mounted) {
      setState(() => _visible = true);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double usableHeight) {
    if (usableHeight <= 0) return;
    final newFrac =
        (_fractionNotifier.value + details.delta.dy / usableHeight).clamp(
      0.0,
      1.0,
    );
    _fractionNotifier.value = newFrac;
    if (widget.controller.hasClients) {
      final maxExtent = widget.controller.position.maxScrollExtent;
      if (maxExtent > 0) {
        widget.controller.jumpTo(newFrac * maxExtent);
      }
    }
  }

  void _onVerticalDragEnd() {
    _isDragging = false;
    _scheduleHide();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.controller.hasClients) {
      final maxExtent = widget.controller.position.maxScrollExtent;
      if (maxExtent > 0) {
        final target = details.localPosition.dy < _handleHeight / 2
            ? 0.0
            : maxExtent;
        widget.controller.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : cs.onSurfaceVariant;
    final surfaceColor = isDark
        ? const Color(0xE6222226)
        : cs.surfaceContainerHigh.withValues(alpha: 0.94);
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.25 : 0.45,
    );

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: widget.child,
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset =
                  _bottomPadding + MediaQuery.paddingOf(context).bottom;
              final usableHeight = (constraints.maxHeight -
                      _topPadding -
                      bottomInset -
                      _handleHeight)
                  .clamp(0.0, double.infinity);

              return ValueListenableBuilder<double>(
                valueListenable: _fractionNotifier,
                builder: (context, frac, _) {
                  final top = _topPadding + frac * usableHeight;
                  return Stack(
                    children: [
                      Positioned(
                        right: 0,
                        top: top,
                        width: _handleWidth,
                        height: _handleHeight,
                        child: IgnorePointer(
                          ignoring: !_visible,
                          child: AnimatedSlide(
                            offset:
                                _visible ? Offset.zero : const Offset(0.35, 0),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: AnimatedOpacity(
                              opacity: _visible ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: _onVerticalDragStart,
                                onVerticalDragUpdate: (details) =>
                                    _onVerticalDragUpdate(
                                  details,
                                  usableHeight,
                                ),
                                onVerticalDragEnd: (_) => _onVerticalDragEnd(),
                                onVerticalDragCancel: _onVerticalDragEnd,
                                onTapUp: _onTapUp,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: surfaceColor,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(24),
                                      bottomLeft: Radius.circular(24),
                                    ),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.35 : 0.14,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(-2, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.keyboard_arrow_up_rounded,
                                          size: 18,
                                          color: iconColor,
                                        ),
                                        Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 18,
                                          color: iconColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
