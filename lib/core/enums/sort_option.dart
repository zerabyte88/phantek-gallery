/// Defines criteria for sorting media items and albums.
enum SortCriterion {
  shootingTime,
  timeAdded,
  name,
  size;

  String get label => switch (this) {
        SortCriterion.shootingTime => 'By shooting time',
        SortCriterion.timeAdded => 'By time added',
        SortCriterion.name => 'By name',
        SortCriterion.size => 'By size',
      };

  SortDirection get defaultDirection => switch (this) {
        SortCriterion.shootingTime => SortDirection.descending,
        SortCriterion.timeAdded => SortDirection.descending,
        SortCriterion.name => SortDirection.ascending,
        SortCriterion.size => SortDirection.descending,
      };

  String directionLabel(SortDirection direction) => switch (this) {
        SortCriterion.shootingTime || SortCriterion.timeAdded =>
          direction == SortDirection.ascending
              ? 'Oldest to newest'
              : 'Newest to oldest',
        SortCriterion.name =>
          direction == SortDirection.ascending ? 'A to Z' : 'Z to A',
        SortCriterion.size =>
          direction == SortDirection.ascending
              ? 'Smallest to largest'
              : 'Largest to smallest',
      };
}

/// Order direction for sorting.
enum SortDirection {
  ascending,
  descending;

  SortDirection get toggled => this == SortDirection.ascending
      ? SortDirection.descending
      : SortDirection.ascending;
}

/// Defines available sort orders for the gallery grid and albums.
enum SortOption {
  /// Most recently added first (default).
  newest,

  /// Oldest added first.
  oldest,

  /// Shooting time: newest first.
  shootingTimeDesc,

  /// Shooting time: oldest first.
  shootingTimeAsc,

  /// File name A → Z (case-insensitive).
  nameAZ,

  /// File name Z → A (case-insensitive).
  nameZA,

  /// File size: largest first.
  sizeDesc,

  /// File size: smallest first.
  sizeAsc;

  SortCriterion get criterion => switch (this) {
        SortOption.newest || SortOption.oldest => SortCriterion.timeAdded,
        SortOption.shootingTimeDesc || SortOption.shootingTimeAsc =>
          SortCriterion.shootingTime,
        SortOption.nameAZ || SortOption.nameZA => SortCriterion.name,
        SortOption.sizeDesc || SortOption.sizeAsc => SortCriterion.size,
      };

  SortDirection get direction => switch (this) {
        SortOption.oldest ||
        SortOption.shootingTimeAsc ||
        SortOption.nameAZ ||
        SortOption.sizeAsc =>
          SortDirection.ascending,
        SortOption.newest ||
        SortOption.shootingTimeDesc ||
        SortOption.nameZA ||
        SortOption.sizeDesc =>
          SortDirection.descending,
      };

  String get barLabel =>
      '${criterion.label}: ${criterion.directionLabel(direction)}';

  static SortOption fromCriterionAndDirection(
    SortCriterion criterion,
    SortDirection direction,
  ) {
    return switch (criterion) {
      SortCriterion.timeAdded => direction == SortDirection.descending
          ? SortOption.newest
          : SortOption.oldest,
      SortCriterion.shootingTime => direction == SortDirection.descending
          ? SortOption.shootingTimeDesc
          : SortOption.shootingTimeAsc,
      SortCriterion.name => direction == SortDirection.ascending
          ? SortOption.nameAZ
          : SortOption.nameZA,
      SortCriterion.size => direction == SortDirection.descending
          ? SortOption.sizeDesc
          : SortOption.sizeAsc,
    };
  }
}

extension SortOptionLabel on SortOption {
  String get label => barLabel;
}
