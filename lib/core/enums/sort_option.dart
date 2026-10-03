/// Defines available sort orders for the gallery grid.
enum SortOption {
  /// Most recently taken/modified first.
  newest,

  /// Oldest first.
  oldest,

  /// File name A → Z (case-insensitive).
  nameAZ,

  /// File name Z → A (case-insensitive).
  nameZA,
}

extension SortOptionLabel on SortOption {
  String get label => switch (this) {
        SortOption.newest => 'Newest First',
        SortOption.oldest => 'Oldest First',
        SortOption.nameAZ => 'Name A → Z',
        SortOption.nameZA => 'Name Z → A',
      };
}
