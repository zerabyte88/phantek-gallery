import 'package:flutter/widgets.dart';
import '../localization/app_localizations.dart';

/// Defines criteria for sorting media items and albums.
enum SortCriterion {
  shootingTime,
  timeAdded,
  name,
  size,
  album;

  String get label => switch (this) {
        SortCriterion.shootingTime => 'By shooting time',
        SortCriterion.timeAdded => 'By time added',
        SortCriterion.name => 'By name',
        SortCriterion.size => 'By size',
        SortCriterion.album => 'By album',
      };

  String localizedLabel(BuildContext context) => switch (this) {
        SortCriterion.shootingTime => context.tr.sortByShootingTime,
        SortCriterion.timeAdded => context.tr.sortByTimeAdded,
        SortCriterion.name => context.tr.sortByName,
        SortCriterion.size => context.tr.sortBySize,
        SortCriterion.album => context.tr.sortByAlbum,
      };

  SortDirection get defaultDirection => switch (this) {
        SortCriterion.shootingTime => SortDirection.descending,
        SortCriterion.timeAdded => SortDirection.descending,
        SortCriterion.name => SortDirection.ascending,
        SortCriterion.size => SortDirection.descending,
        SortCriterion.album => SortDirection.ascending,
      };

  String directionLabel(SortDirection direction) => switch (this) {
        SortCriterion.shootingTime ||
        SortCriterion.timeAdded =>
          direction == SortDirection.ascending
              ? 'Oldest to newest'
              : 'Newest to oldest',
        SortCriterion.name ||
        SortCriterion.album =>
          direction == SortDirection.ascending ? 'A to Z' : 'Z to A',
        SortCriterion.size => direction == SortDirection.ascending
            ? 'Smallest to largest'
            : 'Largest to smallest',
      };

  String localizedDirectionLabel(
          BuildContext context, SortDirection direction) =>
      switch (this) {
        SortCriterion.shootingTime ||
        SortCriterion.timeAdded =>
          direction == SortDirection.ascending
              ? context.tr.oldestToNewest
              : context.tr.newestToOldest,
        SortCriterion.name ||
        SortCriterion.album =>
          direction == SortDirection.ascending
              ? context.tr.aToZ
              : context.tr.zToA,
        SortCriterion.size => direction == SortDirection.ascending
            ? context.tr.smallestToLargest
            : context.tr.largestToSmallest,
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

  /// File name A → Z (natural alphanumeric).
  nameAZ,

  /// File name Z → A (natural alphanumeric).
  nameZA,

  /// File size: largest first.
  sizeDesc,

  /// File size: smallest first.
  sizeAsc,

  /// Album A → Z, then file name A → Z.
  albumAZ,

  /// Album Z → A, then file name A → Z.
  albumZA;

  SortCriterion get criterion => switch (this) {
        SortOption.newest || SortOption.oldest => SortCriterion.timeAdded,
        SortOption.shootingTimeDesc ||
        SortOption.shootingTimeAsc =>
          SortCriterion.shootingTime,
        SortOption.nameAZ || SortOption.nameZA => SortCriterion.name,
        SortOption.sizeDesc || SortOption.sizeAsc => SortCriterion.size,
        SortOption.albumAZ || SortOption.albumZA => SortCriterion.album,
      };

  SortDirection get direction => switch (this) {
        SortOption.oldest ||
        SortOption.shootingTimeAsc ||
        SortOption.nameAZ ||
        SortOption.sizeAsc ||
        SortOption.albumAZ =>
          SortDirection.ascending,
        SortOption.newest ||
        SortOption.shootingTimeDesc ||
        SortOption.nameZA ||
        SortOption.sizeDesc ||
        SortOption.albumZA =>
          SortDirection.descending,
      };

  String get barLabel =>
      '${criterion.label}: ${criterion.directionLabel(direction)}';

  String localizedBarLabel(BuildContext context) =>
      '${criterion.localizedLabel(context)}: ${criterion.localizedDirectionLabel(context, direction)}';

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
      SortCriterion.album => direction == SortDirection.descending
          ? SortOption.albumZA
          : SortOption.albumAZ,
    };
  }
}

extension SortOptionLabel on SortOption {
  String get label => barLabel;
}
