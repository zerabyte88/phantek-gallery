import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

@immutable
class GridHiResState {
  const GridHiResState({
    required this.active,
    required this.generation,
  });

  final bool active;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is GridHiResState &&
      other.active == active &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(active, generation);
}

/// Coordinates viewport-aware hi-res thumbnail upgrades across scrollable grids.
///
/// Immediately downgrades all upgraded tiles when scrolling starts (or when
/// covered by another route / backgrounded) and upgrades only tiles overlapping
/// the active viewport once scrolling settles for [idleDelay].
class GridHiResController extends ValueNotifier<GridHiResState> {
  GridHiResController({
    this.idleDelay = const Duration(milliseconds: 180),
  }) : super(const GridHiResState(active: false, generation: 0));

  final Duration idleDelay;

  Timer? _idleTimer;
  bool _isActivelyScrolling = false;
  bool _externalScrolling = false;
  bool _isVisible = true;
  bool _disposed = false;

  void _downgradeNow() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_disposed) return;
    if (value.active) {
      value = GridHiResState(
        active: false,
        generation: value.generation + 1,
      );
    }
  }

  void _scheduleUpgrade() {
    _idleTimer?.cancel();
    if (_disposed ||
        !_isVisible ||
        _isActivelyScrolling ||
        _externalScrolling) {
      return;
    }
    _idleTimer = Timer(idleDelay, () {
      if (_disposed ||
          !_isVisible ||
          _isActivelyScrolling ||
          _externalScrolling) {
        return;
      }
      value = GridHiResState(
        active: true,
        generation: value.generation + 1,
      );
    });
  }

  void scheduleInitialIdle() => _scheduleUpgrade();

  void onScrollStart() {
    _isActivelyScrolling = true;
    _downgradeNow();
  }

  void onScrollUpdate(double? scrollDelta) {
    if (scrollDelta == null || scrollDelta.abs() <= 0.5) return;
    _downgradeNow();
    if (!_isActivelyScrolling && !_externalScrolling) {
      _scheduleUpgrade();
    }
  }

  void onScrollEnd() {
    _isActivelyScrolling = false;
    _scheduleUpgrade();
  }

  void setExternalScrolling(bool scrolling) {
    if (_externalScrolling == scrolling) return;
    _externalScrolling = scrolling;
    if (scrolling) {
      _downgradeNow();
    } else {
      _scheduleUpgrade();
    }
  }

  void setVisible(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (!visible) {
      _downgradeNow();
    } else {
      _scheduleUpgrade();
    }
  }

  /// Returns true only when [tileContext] genuinely overlaps both its enclosing
  /// [Scrollable] viewport and the visible screen bounds (excluding off-screen
  /// `cacheExtent` tiles and inactive `PageView` tabs).
  bool isTileVisibleInViewport(BuildContext tileContext) {
    final renderBox = tileContext.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.attached || !renderBox.hasSize) {
      return false;
    }
    final tileSize = renderBox.size;
    if (tileSize.isEmpty) return false;

    final screenSize = MediaQuery.maybeSizeOf(tileContext);
    if (screenSize != null && !screenSize.isEmpty) {
      final globalTopLeft = renderBox.localToGlobal(Offset.zero);
      final globalRect = globalTopLeft & tileSize;
      final screenRect = Offset.zero & screenSize;
      if (!globalRect.overlaps(screenRect)) {
        return false;
      }
    }

    final scrollable = Scrollable.maybeOf(tileContext);
    if (scrollable != null) {
      final viewportBox = scrollable.context.findRenderObject();
      if (viewportBox is RenderBox &&
          viewportBox.attached &&
          viewportBox.hasSize) {
        final localTopLeft = renderBox.localToGlobal(
          Offset.zero,
          ancestor: viewportBox,
        );
        final localRect = localTopLeft & tileSize;
        final viewportRect = Offset.zero & viewportBox.size;
        if (!localRect.overlaps(viewportRect)) {
          return false;
        }
      }
    }

    return true;
  }

  /// Computes a sharp decode width for [tileContext] based on physical pixels
  /// (1.5x supersampled for readable small text, clamped to [minWidth]..[maxWidth]).
  int computeTargetCacheWidth(
    BuildContext tileContext, {
    int minWidth = 640,
    int maxWidth = 960,
  }) {
    final renderBox = tileContext.findRenderObject();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(tileContext) ?? 2.0;
    if (renderBox is RenderBox && renderBox.attached && renderBox.hasSize) {
      final raw = (renderBox.size.width * dpr * 1.5).round();
      final bucketed = ((raw + 31) ~/ 32) * 32;
      return bucketed.clamp(minWidth, maxWidth);
    }
    return minWidth;
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    super.dispose();
  }
}

/// Provides a [GridHiResController] to descendant grid tiles and listens for
/// scroll activity, route visibility, and app lifecycle changes.
class GridHiResScope extends StatefulWidget {
  const GridHiResScope({
    super.key,
    required this.child,
    this.idleDelay = const Duration(milliseconds: 180),
    this.controller,
  });

  final Widget child;
  final Duration idleDelay;
  final GridHiResController? controller;

  static GridHiResController? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<_GridHiResInherited>()
        ?.controller;
  }

  @override
  State<GridHiResScope> createState() => _GridHiResScopeState();
}

class _GridHiResScopeState extends State<GridHiResScope>
    with WidgetsBindingObserver {
  late GridHiResController _controller;
  bool _ownsController = false;
  bool _isAppActive = true;
  bool _isRouteCurrent = true;

  @override
  void initState() {
    super.initState();
    final ls = WidgetsBinding.instance.lifecycleState;
    _isAppActive = ls == null || ls == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = GridHiResController(idleDelay: widget.idleDelay);
      _ownsController = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncVisibility();
        _controller.scheduleInitialIdle();
      }
    });
  }

  @override
  void didUpdateWidget(covariant GridHiResScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = GridHiResController(idleDelay: widget.idleDelay);
        _ownsController = true;
      }
      _syncVisibility();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _syncVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    _syncVisibility();
  }

  void _syncVisibility() {
    _controller.setVisible(_isAppActive && _isRouteCurrent);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _controller.onScrollStart();
    } else if (notification is ScrollUpdateNotification) {
      _controller.onScrollUpdate(notification.scrollDelta);
    } else if (notification is ScrollEndNotification) {
      _controller.onScrollEnd();
    } else if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _controller.onScrollEnd();
      } else {
        _controller.onScrollStart();
      }
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GridHiResInherited(
      controller: _controller,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: widget.child,
      ),
    );
  }
}

class _GridHiResInherited extends InheritedWidget {
  const _GridHiResInherited({
    required this.controller,
    required super.child,
  });

  final GridHiResController controller;

  @override
  bool updateShouldNotify(covariant _GridHiResInherited oldWidget) =>
      oldWidget.controller != controller;
}
