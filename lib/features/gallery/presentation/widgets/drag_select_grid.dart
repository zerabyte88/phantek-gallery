import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Wraps a scrollable grid to enable drag-to-select across items while
/// preserving vertical scrolling when selecting and pinch-to-zoom gestures.
class DragSelectGrid extends StatefulWidget {
  const DragSelectGrid({
    super.key,
    required this.isSelecting,
    required this.itemCount,
    required this.crossAxisCount,
    this.childAspectRatio = 1.0,
    this.crossAxisSpacing = 0.0,
    this.mainAxisSpacing = 0.0,
    this.padding = EdgeInsets.zero,
    required this.scrollController,
    required this.idAt,
    required this.isSelected,
    required this.onRangeSelectionChanged,
    this.indexAt,
    required this.child,
  });

  final bool isSelecting;
  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsetsGeometry padding;
  final ScrollController scrollController;
  final String Function(int index) idAt;
  final bool Function(String id) isSelected;
  final void Function(Set<String> ids, bool select) onRangeSelectionChanged;

  /// Optional custom hit-test mapper for non-uniform layouts (e.g. grouped timelines).
  final int? Function(
      Offset localPosition, Size viewportSize, bool requireExactItem)? indexAt;
  final Widget child;

  @override
  State<DragSelectGrid> createState() => _DragSelectGridState();
}

class _DragSelectGridState extends State<DragSelectGrid>
    with SingleTickerProviderStateMixin {
  static const double _edgeScrollZone = 48.0;
  static const double _maxEdgeScrollSpeedPerSec = 480.0;

  late final Ticker _autoScrollTicker;
  Duration _lastTickElapsed = Duration.zero;

  final Set<int> _activePointers = <int>{};
  int? _trackedPointer;
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;
  bool _wasSelectingOnDown = false;
  bool _exceededSlopBeforeLongPress = false;

  bool _dragActive = false;
  bool _dragSelectMode = true;
  int? _anchorIndex;
  int? _lastIndex;
  int? _lastRangeStart;
  int? _lastRangeEnd;
  Offset? _lastLocalPos;
  final Map<String, bool> _preDragSelection = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _autoScrollTicker = createTicker(_onAutoScrollTick);
  }

  @override
  void didUpdateWidget(covariant DragSelectGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelecting && !widget.isSelecting) {
      _endDrag();
    }
  }

  @override
  void dispose() {
    _autoScrollTicker.dispose();
    super.dispose();
  }

  int? _indexAt(Offset localPos, {required bool requireExactItem}) {
    if (widget.itemCount <= 0 || widget.crossAxisCount <= 0) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    if (widget.indexAt != null) {
      final idx = widget.indexAt!(localPos, box.size, requireExactItem);
      if (idx == null) return null;
      return idx.clamp(0, widget.itemCount - 1);
    }

    final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final resolvedPadding = widget.padding.resolve(dir);
    final contentWidth =
        box.size.width - resolvedPadding.left - resolvedPadding.right;
    if (contentWidth <= 0) return null;

    final totalCrossSpacing =
        widget.crossAxisSpacing * (widget.crossAxisCount - 1);
    final tileWidth =
        (contentWidth - totalCrossSpacing) / widget.crossAxisCount;
    if (tileWidth <= 0 || widget.childAspectRatio <= 0) return null;

    final tileHeight = tileWidth / widget.childAspectRatio;
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;

    final x = localPos.dx - resolvedPadding.left;
    final y = localPos.dy + scrollOffset - resolvedPadding.top;
    final stepX = tileWidth + widget.crossAxisSpacing;
    final stepY = tileHeight + widget.mainAxisSpacing;
    final maxRow = (widget.itemCount - 1) ~/ widget.crossAxisCount;

    if (requireExactItem && (x < 0 || x > contentWidth || y < 0)) return null;
    final rawRow = (y / stepY).floor();
    if (requireExactItem && (rawRow < 0 || rawRow > maxRow)) return null;

    final col = (x / stepX).floor().clamp(0, widget.crossAxisCount - 1);
    final logicalCol =
        dir == TextDirection.rtl ? (widget.crossAxisCount - 1 - col) : col;
    final index = rawRow.clamp(0, maxRow) * widget.crossAxisCount + logicalCol;
    if (requireExactItem && (index < 0 || index >= widget.itemCount)) {
      return null;
    }
    return index.clamp(0, widget.itemCount - 1);
  }

  void _startDrag(Offset anchorPos, Offset currentPos, {bool? forcedMode}) {
    final anchor = _indexAt(anchorPos, requireExactItem: true);
    if (anchor == null) return;

    final anchorId = widget.idAt(anchor);
    _dragActive = true;
    _anchorIndex = anchor;
    _lastIndex = anchor;
    _lastRangeStart = anchor;
    _lastRangeEnd = anchor;
    _lastLocalPos = currentPos;
    _preDragSelection.clear();

    final mode = forcedMode ?? !widget.isSelected(anchorId);
    _dragSelectMode = mode;
    _preDragSelection[anchorId] = widget.isSelected(anchorId);

    if (widget.isSelected(anchorId) != mode) {
      widget.onRangeSelectionChanged({anchorId}, mode);
      HapticFeedback.selectionClick();
    }

    _updateDragAt(currentPos);
    _syncAutoScroll();
  }

  void _updateDragAt(Offset localPos) {
    if (!_dragActive || _anchorIndex == null) return;
    _lastLocalPos = localPos;

    final current = _indexAt(localPos, requireExactItem: false);
    if (current == null) return;
    if (current == _lastIndex) {
      _syncAutoScroll();
      return;
    }

    _lastIndex = current;
    final anchor = _anchorIndex!;
    final newStart = math.min(anchor, current);
    final newEnd = math.max(anchor, current);
    final prevStart = _lastRangeStart ?? newStart;
    final prevEnd = _lastRangeEnd ?? newEnd;

    final toSelect = <String>{};
    final toDeselect = <String>{};

    for (var i = prevStart; i <= prevEnd; i++) {
      if (i >= newStart && i <= newEnd) continue;
      if (i < 0 || i >= widget.itemCount) continue;
      final id = widget.idAt(i);
      final original = _preDragSelection[id];
      if (original != null && widget.isSelected(id) != original) {
        (original ? toSelect : toDeselect).add(id);
      }
    }

    for (var i = newStart; i <= newEnd; i++) {
      if (i < 0 || i >= widget.itemCount) continue;
      final id = widget.idAt(i);
      _preDragSelection.putIfAbsent(id, () => widget.isSelected(id));
      if (widget.isSelected(id) != _dragSelectMode) {
        (_dragSelectMode ? toSelect : toDeselect).add(id);
      }
    }

    _lastRangeStart = newStart;
    _lastRangeEnd = newEnd;

    if (toSelect.isNotEmpty) {
      widget.onRangeSelectionChanged(toSelect, true);
    }
    if (toDeselect.isNotEmpty) {
      widget.onRangeSelectionChanged(toDeselect, false);
    }
    if (toSelect.isNotEmpty || toDeselect.isNotEmpty) {
      HapticFeedback.selectionClick();
    }

    _syncAutoScroll();
  }

  void _endDrag() {
    _dragActive = false;
    _anchorIndex = null;
    _lastIndex = null;
    _lastRangeStart = null;
    _lastRangeEnd = null;
    _lastLocalPos = null;
    _preDragSelection.clear();
    if (_autoScrollTicker.isActive) {
      _autoScrollTicker.stop();
    }
    _lastTickElapsed = Duration.zero;
  }

  void _syncAutoScroll() {
    if (!_dragActive || _lastLocalPos == null) {
      if (_autoScrollTicker.isActive) _autoScrollTicker.stop();
      return;
    }
    final velocity = _computeEdgeVelocity(_lastLocalPos!.dy);
    if (velocity != 0.0) {
      if (!_autoScrollTicker.isActive) {
        _lastTickElapsed = Duration.zero;
        _autoScrollTicker.start();
      }
    } else if (_autoScrollTicker.isActive) {
      _autoScrollTicker.stop();
      _lastTickElapsed = Duration.zero;
    }
  }

  double _computeEdgeVelocity(double localDy) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !widget.scrollController.hasClients) {
      return 0.0;
    }
    final height = box.size.height;
    final pos = widget.scrollController.position;

    if (localDy < _edgeScrollZone && pos.pixels > pos.minScrollExtent) {
      final t = ((_edgeScrollZone - localDy) / _edgeScrollZone).clamp(0.0, 1.0);
      return -_maxEdgeScrollSpeedPerSec * t;
    }
    if (localDy > height - _edgeScrollZone &&
        pos.pixels < pos.maxScrollExtent) {
      final t = ((localDy - (height - _edgeScrollZone)) / _edgeScrollZone)
          .clamp(0.0, 1.0);
      return _maxEdgeScrollSpeedPerSec * t;
    }
    return 0.0;
  }

  void _onAutoScrollTick(Duration elapsed) {
    if (!_dragActive ||
        _lastLocalPos == null ||
        !widget.scrollController.hasClients) {
      _autoScrollTicker.stop();
      return;
    }

    final dt = _lastTickElapsed == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTickElapsed).inMicroseconds / 1000000.0;
    _lastTickElapsed = elapsed;
    if (dt <= 0) return;

    final velocity = _computeEdgeVelocity(_lastLocalPos!.dy);
    if (velocity == 0.0) {
      _autoScrollTicker.stop();
      return;
    }

    final pos = widget.scrollController.position;
    final target = (pos.pixels + velocity * dt)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 0.1) return;

    widget.scrollController.jumpTo(target);
    _updateDragAt(_lastLocalPos!);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _trackedPointer = null;
      _endDrag();
      return;
    }
    _trackedPointer = event.pointer;
    _pointerDownPos = event.localPosition;
    _pointerDownTime = DateTime.now();
    _wasSelectingOnDown = widget.isSelecting;
    _exceededSlopBeforeLongPress = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _trackedPointer || _activePointers.length > 1) return;

    final downPos = _pointerDownPos;
    final downTime = _pointerDownTime;
    if (downPos == null || downTime == null) return;

    if (_dragActive) {
      _updateDragAt(event.localPosition);
      return;
    }

    final distance = (event.localPosition - downPos).distance;
    final heldDuration = DateTime.now().difference(downTime);

    if (distance > kTouchSlop && heldDuration < kLongPressTimeout) {
      _exceededSlopBeforeLongPress = true;
    }

    if (!widget.isSelecting || _exceededSlopBeforeLongPress) return;

    // Require holding past long-press when already selecting so vertical swipes still scroll.
    final longPressOccurred =
        !_wasSelectingOnDown || heldDuration >= kLongPressTimeout;
    if (longPressOccurred && distance > kTouchSlop * 0.5) {
      final anchor = _indexAt(downPos, requireExactItem: true);
      final forcedMode =
          anchor != null ? widget.isSelected(widget.idAt(anchor)) : true;
      _startDrag(downPos, event.localPosition, forcedMode: forcedMode);
    }
  }

  void _handlePointerUpOrCancel(int pointer) {
    _activePointers.remove(pointer);
    if (pointer == _trackedPointer) {
      _trackedPointer = null;
      _pointerDownPos = null;
      _pointerDownTime = null;
      _exceededSlopBeforeLongPress = false;
      if (_dragActive) {
        _endDrag();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (e) => _handlePointerUpOrCancel(e.pointer),
      onPointerCancel: (e) => _handlePointerUpOrCancel(e.pointer),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: widget.isSelecting
            ? (details) {
                if (_activePointers.length > 1 || _dragActive) return;
                _startDrag(
                  _pointerDownPos ?? details.localPosition,
                  details.localPosition,
                );
              }
            : null,
        onHorizontalDragUpdate: widget.isSelecting
            ? (details) {
                if (_dragActive) {
                  _updateDragAt(details.localPosition);
                }
              }
            : null,
        onHorizontalDragEnd: widget.isSelecting ? (_) => _endDrag() : null,
        onHorizontalDragCancel: widget.isSelecting ? _endDrag : null,
        child: widget.child,
      ),
    );
  }
}
