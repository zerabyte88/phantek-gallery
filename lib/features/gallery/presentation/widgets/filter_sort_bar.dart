import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/filter_option.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/bouncy_tap.dart';

/// Clean, responsive filter bar with fixed chips + compact sort button.
/// Fully visible without scrolling or clipping on any screen width.
/// Can be used in main gallery (with Albums tab) or inside an album (without Albums tab).
class FilterSortBar extends ConsumerWidget {
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

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Left spacer matching the 40px popup menu button for perfect screen centering
          const SizedBox(width: 40),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: options.map((f) {
                    final selected = activeFilter == f;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: BouncyTap(
                        scaleDown: 0.94,
                        child: Material(
                          color: selected
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                          shape: const StadiumBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () {
                              if (onFilterChanged != null) {
                                onFilterChanged!(f);
                              } else {
                                ref
                                    .read(settingsNotifierProvider.notifier)
                                    .update((s) => s.copyWith(defaultFilter: f));
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              constraints: const BoxConstraints(minWidth: 72),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: ShapeDecoration(
                                shape: StadiumBorder(
                                  side: BorderSide(
                                    color: selected
                                        ? cs.primary.withValues(alpha: 0.3)
                                        : cs.outline.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Text(
                                f.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: selected
                                      ? cs.onPrimaryContainer
                                      : cs.onSurface,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: BouncyTap(
              scaleDown: 0.88,
              child: PopupMenuButton<SortOption>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert, size: 22, color: cs.onSurfaceVariant),
                tooltip: 'Sort options',
                initialValue: activeSort,
                onSelected: (s) {
                  if (onSortChanged != null) {
                    onSortChanged!(s);
                  } else {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .update((st) => st.copyWith(defaultSort: s));
                  }
                },
                itemBuilder: (context) => SortOption.values
                    .map(
                      (s) => CheckedPopupMenuItem<SortOption>(
                        value: s,
                        checked: activeSort == s,
                        child: Text(s.label),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
