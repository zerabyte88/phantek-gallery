import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/enums/filter_option.dart';
import 'package:phantek_gallery/core/enums/sort_option.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/utils/media_utils.dart';

void main() {
  group('Phantek Gallery Core Unit Tests', () {
    test('MediaUtils formatting tests', () {
      expect(MediaUtils.formatSize(500), '500 B');
      expect(MediaUtils.formatSize(1024 * 500), '500.0 KB');
      expect(MediaUtils.formatSize(1024 * 1024 * 5), '5.0 MB');
      expect(MediaUtils.formatDuration(const Duration(minutes: 2, seconds: 45)), '02:45');
      expect(MediaUtils.formatDuration(const Duration(hours: 1, minutes: 5, seconds: 2)), '1:05:02');
    });

    test('MediaItem model properties', () {
      final item = MediaItem(
        id: '123',
        path: '/storage/emulated/0/DCIM/test.mp4',
        name: 'test.mp4',
        date: DateTime(2026, 1, 1),
        size: 1048576,
        isVideo: true,
        width: 1920,
        height: 1080,
      );

      expect(item.resolution, '1920x1080');
      expect(item.isVideo, isTrue);
    });

    test('SettingsModel defaults', () {
      const settings = SettingsModel();
      expect(settings.gridColumns, 3);
      expect(settings.enableTrash, isTrue);
      expect(settings.hardwareAcceleration, isTrue);
      expect(settings.autoCheckUpdate, isTrue);
      expect(settings.defaultSort, SortOption.newest);
      expect(settings.defaultFilter, FilterOption.all);
    });
  });
}
