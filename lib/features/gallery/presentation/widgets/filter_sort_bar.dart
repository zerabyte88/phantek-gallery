import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/filter_option.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/bouncy_tap.dart';
import 'sort_bottom_sheet.dart';

/// Modern, responsive unified filter and sort bar.
/// Features an elegant segmented capsule controller for tabs and a compact sort chip.
class FilterSortBar extends ConsumerWidget implements PreferredSizeWidget {
  const FilterSortBar({
    super.key,
    this.isAlbumDetail = false,
    this.currentFilter,
    this.onFilterChanged,
    this.currentSort,
    this.onSortChanged,
    this.pageController,
  });

  final bool isAlbumDetail;
  final FilterOption? currentFilter;
  final ValueChanged<FilterOption>? onFilterChanged;
  final SortOption? currentSort;
  final ValueChanged<SortOption>? onSortChanged;
  final PageController? pageController;

  @override
  Size get preferredSize => const Size.fromHeight(96);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final activeFilter = currentFilter ?? settings.defaultFilter;
    final activeSort = currentSort ?? settings.defaultSort;

    final options = isAlbumDetail
        ? [
            FilterOption.all,
            FilterOption.photosOnly,
            FilterOption.videosOnly,
          ]
        : FilterOption.values;

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
                      child: Stack(
                        children: [
                          if (pageController != null)
                            AnimatedBuilder(
                              animation: pageController!,
                              builder: (context, _) {
                                final page = pageController!.hasClients &&
                                        pageController!.page != null
                                    ? pageController!.page!
                                    : selectedIndex.toDouble();
                                final continuousAlignX = options.length > 1
                                    ? -1.0 + (2.0 * page / (options.length - 1))
                                    : 0.0;
                                return Align(
                                  alignment: Alignment(
                                      continuousAlignX.clamp(-1.0, 1.0), 0.0),
                                  child: capsuleIndicator,
                                );
                              },
                            )
                          else
                            AnimatedAlign(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment(alignmentX, 0.0),
                              child: capsuleIndicator,
                            ),
                          Row(
                            children: options.asMap().entries.map((entry) {
                              final index = entry.key;
                              final f = entry.value;

                              Widget labelChild;
                              if (pageController != null) {
                                labelChild = AnimatedBuilder(
                                  animation: pageController!,
                                  builder: (context, _) {
                                    final page = pageController!.hasClients &&
                                            pageController!.page != null
                                        ? pageController!.page!
                                        : selectedIndex.toDouble();
                                    final t = (1.0 - (page - index).abs())
                                        .clamp(0.0, 1.0);
                                    final color = Color.lerp(
                                        cs.onSurfaceVariant, cs.onPrimary, t);
                                    final weight = FontWeight.lerp(
                                        FontWeight.w500, FontWeight.w600, t);
                                    return Text(
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
                                  },
                                );
                              } else {
                                final selected = activeFilter == f;
                                labelChild = AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 280),
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
                              }

                              return Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (onFilterChanged != null) {
                                      onFilterChanged!(f);
                                    } else {
                                      ref
                                          .read(
                                              settingsNotifierProvider.notifier)
                                          .update((s) =>
                                              s.copyWith(defaultFilter: f));
                                    }
                                  },
                                  child: Center(
                                    child: labelChild,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
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
                                  if (onSortChanged != null) {
                                    onSortChanged!(s);
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
    return RepaintBoundary(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.12 : 0.35),
                cs.surfaceContainerHighest.withValues(alpha: 0.25),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.4),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
