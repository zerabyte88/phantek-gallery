import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/filter_option.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/bouncy_tap.dart';
import 'sort_bottom_sheet.dart';

/// Modern, responsive unified filter and sort bar.
/// Features an elegant segmented capsule controller for tabs and a compact sort chip.
class FilterSortBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const FilterSortBar({
    super.key,
    this.isAlbumDetail = false,
    this.currentFilter,
    this.onFilterChanged,
    this.currentSort,
    this.onSortChanged,
    this.pageController,
    this.isDirectTabTransition = false,
  });

  final bool isAlbumDetail;
  final FilterOption? currentFilter;
  final ValueChanged<FilterOption>? onFilterChanged;
  final SortOption? currentSort;
  final ValueChanged<SortOption>? onSortChanged;
  final PageController? pageController;
  final bool isDirectTabTransition;

  @override
  Size get preferredSize => const Size.fromHeight(96);

  @override
  ConsumerState<FilterSortBar> createState() => _FilterSortBarState();
}

class _FilterSortBarState extends ConsumerState<FilterSortBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Animation<double>? _tapAnimation;
  late double _lastVisualPage;

  List<FilterOption> get _options => widget.isAlbumDetail
      ? [
          FilterOption.all,
          FilterOption.photosOnly,
          FilterOption.videosOnly,
        ]
      : FilterOption.values;

  @override
  void initState() {
    super.initState();
    final options = _options;
    final initialFilter = widget.currentFilter ?? FilterOption.all;
    _lastVisualPage =
        options.indexOf(initialFilter).clamp(0, options.length - 1).toDouble();
  }

  @override
  void didUpdateWidget(covariant FilterSortBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final options = _options;
    final oldIdx = options
        .indexOf(oldWidget.currentFilter ?? FilterOption.all)
        .clamp(0, options.length - 1);
    final newIdx = options
        .indexOf(widget.currentFilter ?? FilterOption.all)
        .clamp(0, options.length - 1);

    if (widget.isDirectTabTransition &&
        (!oldWidget.isDirectTabTransition || oldIdx != newIdx)) {
      final double beginPage;
      if (_tapAnimController.isAnimating && _tapAnimation != null) {
        beginPage = _tapAnimation!.value;
      } else if (!oldWidget.isDirectTabTransition) {
        beginPage = _lastVisualPage;
      } else {
        beginPage = oldIdx.toDouble();
      }
      _tapAnimation = Tween<double>(
        begin: beginPage,
        end: newIdx.toDouble(),
      ).animate(
        CurvedAnimation(
          parent: _tapAnimController,
          curve: Curves.easeOutCubic,
        ),
      );
      _tapAnimController.forward(from: 0.0);
    } else if (!widget.isDirectTabTransition &&
        oldWidget.isDirectTabTransition) {
      _tapAnimController.stop();
      _tapAnimation = null;
    }
  }

  @override
  void dispose() {
    _tapAnimController.dispose();
    super.dispose();
  }

  void _onTapFilter(FilterOption f) {
    if (widget.onFilterChanged != null) {
      widget.onFilterChanged!(f);
    } else {
      ref
          .read(settingsNotifierProvider.notifier)
          .update((s) => s.copyWith(defaultFilter: f));
    }
  }

  Widget _buildTabItem(FilterOption f, Widget labelChild) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTapFilter(f),
        child: Center(child: labelChild),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final activeFilter = widget.currentFilter ?? settings.defaultFilter;
    final activeSort = widget.currentSort ?? settings.defaultSort;
    final options = _options;

    final selectedIndex =
        options.indexOf(activeFilter).clamp(0, options.length - 1);
    final alignmentX = options.length > 1
        ? -1.0 + (2.0 * selectedIndex / (options.length - 1))
        : 0.0;

    final capsuleIndicator = FractionallySizedBox(
      widthFactor: 1.0 / options.length,
      heightFactor: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 40,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildGlassBackdrop(cs, isDark, 24),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: widget.pageController == null
                          ? Stack(
                              children: [
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment(alignmentX, 0.0),
                                  child: capsuleIndicator,
                                ),
                                Row(
                                  children: options.map((f) {
                                    final selected = activeFilter == f;
                                    final labelChild =
                                        AnimatedDefaultTextStyle(
                                      duration:
                                          const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                      style: TextStyle(
                                        color: selected
                                            ? cs.onPrimary
                                            : cs.onSurfaceVariant,
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                      child: Text(
                                        f.localizedLabel(context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                    return _buildTabItem(f, labelChild);
                                  }).toList(),
                                ),
                              ],
                            )
                          : AnimatedBuilder(
                              animation: Listenable.merge([
                                widget.pageController!,
                                _tapAnimController,
                              ]),
                              builder: (context, _) {
                                final double visualPage =
                                    widget.isDirectTabTransition &&
                                            _tapAnimation != null
                                        ? _tapAnimation!.value
                                        : (widget.pageController!.hasClients &&
                                                widget.pageController!.page !=
                                                    null
                                            ? widget.pageController!.page!
                                            : selectedIndex.toDouble());
                                _lastVisualPage = visualPage;

                                final continuousAlignX = options.length > 1
                                    ? -1.0 +
                                        (2.0 *
                                            visualPage /
                                            (options.length - 1))
                                    : 0.0;

                                return Stack(
                                  children: [
                                    Align(
                                      alignment: Alignment(
                                          continuousAlignX.clamp(-1.0, 1.0),
                                          0.0),
                                      child: capsuleIndicator,
                                    ),
                                    Row(
                                      children:
                                          options.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final f = entry.value;
                                        final t =
                                            (1.0 - (visualPage - index).abs())
                                                .clamp(0.0, 1.0);
                                        final color = Color.lerp(
                                            cs.onSurfaceVariant,
                                            cs.onPrimary,
                                            t);
                                        final weight = FontWeight.lerp(
                                            FontWeight.w500,
                                            FontWeight.w600,
                                            t);
                                        final labelChild = Text(
                                          f.localizedLabel(context),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 13,
                                            fontWeight: weight,
                                          ),
                                        );
                                        return _buildTabItem(f, labelChild);
                                      }).toList(),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BouncyTap(
                scaleDown: 0.94,
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _buildGlassBackdrop(cs, isDark, 16),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              showSortBottomSheet(
                                context,
                                currentSort: activeSort,
                                onSortChanged: (s) {
                                  if (widget.onSortChanged != null) {
                                    widget.onSortChanged!(s);
                                  } else {
                                    ref
                                        .read(settingsNotifierProvider.notifier)
                                        .update((st) =>
                                            st.copyWith(defaultSort: s));
                                  }
                                },
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      activeSort.direction ==
                                              SortDirection.ascending
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      activeSort.localizedBarLabel(context),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassBackdrop(
    ColorScheme cs,
    bool isDark,
    double borderRadius,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  cs.surfaceContainerHigh.withValues(alpha: 0.88),
                  cs.surfaceContainerHighest.withValues(alpha: 0.78),
                ]
              : [
                  Colors.white.withValues(alpha: 0.86),
                  cs.surfaceContainerHighest.withValues(alpha: 0.78),
                ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.65),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
