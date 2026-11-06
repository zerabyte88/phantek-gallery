import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/services/license_service.dart';
import 'package:phantek_gallery/core/services/psd_service.dart';

void main() {
  group('PsdService Tests', () {
    test(
        'PsdService.isPsd detects .psd extension accurately and case-insensitively',
        () {
      expect(PsdService.isPsd('photo.psd'), isTrue);
      expect(PsdService.isPsd('/storage/emulated/0/DCIM/artwork.PSD'), isTrue);
      expect(PsdService.isPsd('C:\\Users\\art\\banner.Psd'), isTrue);
      expect(PsdService.isPsd('.psd'), isTrue);
      expect(PsdService.isPsd('psd'), isTrue);
      expect(PsdService.isPsd('.PSD'), isTrue);

      expect(PsdService.isPsd('photo.jpg'), isFalse);
      expect(PsdService.isPsd('photo.png'), isFalse);
      expect(PsdService.isPsd('video.mp4'), isFalse);
      expect(PsdService.isPsd(''), isFalse);
    });

    test('LicenseService registers image Apache 2.0 license', () async {
      LicenseService.registerLicenses();
      final licenses = await LicenseRegistry.licenses.toList();
      final allPackages = licenses.expand((e) => e.packages).toSet();
      expect(allPackages.contains('image'), isTrue);
      expect(allPackages.contains('phantek_gallery'), isTrue);
      expect(allPackages.contains('androidx.media3 (ExoPlayer)'), isTrue);
    });

    test('PsdService gracefully handles non-existent or invalid files',
        () async {
      final embedded = await PsdService.instance
          .extractEmbeddedThumbnail('non_existent_file.psd');
      expect(embedded, isNull);

      final thumb =
          await PsdService.instance.decodeThumbnail('non_existent_file.psd');
      expect(thumb, isNull);

      final layers =
          await PsdService.instance.getLayers('non_existent_file.psd');
      expect(layers, isEmpty);

      final rendered = await PsdService.instance.renderWithLayers(
        'non_existent_file.psd',
        hiddenLayerIndices: {},
      );
      expect(rendered, isNull);
    });

    test('PsdLayerInfo copyWith and properties', () {
      const info = PsdLayerInfo(
        index: 0,
        name: 'Background',
        isVisible: true,
        opacity: 255,
        isFolder: false,
      );

      expect(info.index, 0);
      expect(info.name, 'Background');
      expect(info.isVisible, isTrue);
      expect(info.opacity, 255);
      expect(info.isFolder, isFalse);

      final updated = info.copyWith(isVisible: false, opacity: 128);
      expect(updated.isVisible, isFalse);
      expect(updated.opacity, 128);
      expect(updated.name, 'Background');
    });
  });
}
