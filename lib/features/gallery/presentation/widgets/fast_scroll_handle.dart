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
    this.labelBuilder,
  });

  final ScrollController controller;
  final Widget child;
  final Duration hideDelay;

  /// Optional callback returning a floating pill label (e.g. `"Nov 2026"`)
  /// for the current scroll fraction `[0.0, 1.0]` while dragging the handle.
  final String? Function(double fraction)? labelBuilder;

  @override
  State<FastScrollHandle> createState() => _FastScrollHandleState();
}

class _FastScrollHandleState extends State<FastScrollHandle>
    with SingleTickerProviderStateMixin {
  static const double _handleWidth = 38.0;
  static const double _handleHeight = 54.0;
  static const double _topPadding = 12.0;
  static const double _bottomPadding = 16.0;

  final ValueNotifier<double> _fractionNotifier = ValueNotifier<double>(0.0);
  late final AnimationController _pillController;
  late final Animation<double> _pillOpacity;
  bool _visible = false;
  bool _isDragging = false;
  String? _lastLabel;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _pillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _pillOpacity = CurvedAnimation(
      parent: _pillController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pillController.dispose();
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
    final label = widget.labelBuilder?.call(_fractionNotifier.value);
    if (label != null && label.isNotEmpty) {
      _lastLabel = label;
      _pillController.forward();
    }
    if (!_isDragging || !_visible) {
      setState(() {
        _isDragging = true;
        _visible = true;
      });
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
    final label = widget.labelBuilder?.call(newFrac);
    if (label != null && label.isNotEmpty) {
      _lastLabel = label;
      if (_pillController.status != AnimationStatus.forward &&
          _pillController.status != AnimationStatus.completed) {
        _pillController.forward();
      }
    } else if (_pillController.status != AnimationStatus.reverse &&
        _pillController.status != AnimationStatus.dismissed) {
      _pillController.reverse();
    }
  }

  void _onVerticalDragEnd() {
    if (mounted) {
      setState(() => _isDragging = false);
    } else {
      _isDragging = false;
    }
    _pillController.reverse();
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
                  final activeLabel =
                      _isDragging ? widget.labelBuilder?.call(frac) : null;
                  final pillText = (activeLabel != null && activeLabel.isNotEmpty)
                      ? activeLabel
                      : _lastLabel;

                  return Stack(
                    children: [
                      if (widget.labelBuilder != null &&
                          pillText != null &&
                          pillText.isNotEmpty)
                        Positioned(
                          key: const ValueKey('fast_scroll_pill'),
                          right: _handleWidth + 12,
                          top: top,
                          height: _handleHeight,
                          child: IgnorePointer(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FadeTransition(
                                opacity: _pillOpacity,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.08),
                                      width: 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 200),
                                      child: Text(
                                        pillText,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: cs.onSurface,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        key: const ValueKey('fast_scroll_thumb'),
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
