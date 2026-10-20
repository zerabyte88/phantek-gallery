enum TrashCleanupInterval {
  never,
  days7,
  days14,
  days30,
}

extension TrashCleanupIntervalX on TrashCleanupInterval {
  int? get inDays => switch (this) {
        TrashCleanupInterval.never => null,
        TrashCleanupInterval.days7 => 7,
        TrashCleanupInterval.days14 => 14,
        TrashCleanupInterval.days30 => 30,
      };
}
