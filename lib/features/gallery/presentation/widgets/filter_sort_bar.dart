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
  });

  final bool isAlbumDetail;
  final FilterOption? currentFilter;
  final ValueChanged<FilterOption>? onFilterChanged;
  final SortOption? currentSort;
  final ValueChanged<SortOption>? onSortChanged;

  @override
  Size get preferredSize => const Size.fromHeight(96);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final cs = Theme.of(context).colorScheme;

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 1. Modern Segmented Filter Bar ──────────────────────────────
          Container(
            height: 42,
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // ── Sliding Capsule Indicator ────────────────────────────
                AnimatedAlign(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(alignmentX, 0.0),
                  child: FractionallySizedBox(
                    widthFactor: 1.0 / options.length,
                    heightFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Tab Labels and Tap Interactions ───────────────────────
                Row(
                  children: options.map((f) {
                    final selected = activeFilter == f;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (onFilterChanged != null) {
                            onFilterChanged!(f);
                          } else {
                            ref
                                .read(settingsNotifierProvider.notifier)
                                .update((s) => s.copyWith(defaultFilter: f));
                          }
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
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
                              f.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── 2. Compact Modern Sort Pill ─────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Modern clickable sort chip
              BouncyTap(
                scaleDown: 0.94,
                child: Material(
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
                                .update((st) => st.copyWith(defaultSort: s));
                          }
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            activeSort.direction == SortDirection.ascending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 14,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            activeSort.barLabel,
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
        ],
      ),
    );
  }
}
