// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phantek_gallery/core/services/psd_service.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/psd_layer_sheet.dart';

Uint8List _createDummyPng() {
  final image = img.Image(width: 16, height: 16, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('PsdLayerSheet Widget Tests', () {
    testWidgets('Sheet height is bounded to ~35% screen height in portrait',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0; // 360 x 800 logical
      addTearDown(() => tester.view.reset());

      const layers = [
        PsdLayerInfo(
            index: 0,
            name: 'Background',
            isVisible: true,
            opacity: 255,
            isFolder: false),
        PsdLayerInfo(
            index: 1,
            name: 'Layer 1',
            isVisible: true,
            opacity: 255,
            isFolder: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PsdLayerSheet.show(
                  context: context,
                  layers: layers,
                  hiddenIndices: {},
                  onVisibilityChanged: (_) {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final sheetFinder = find.byType(PsdLayerSheet);
      expect(sheetFinder, findsOneWidget);

      final size = tester.getSize(sheetFinder);
      // Logical height: 800 * 0.35 = 280.0
      expect(size.height, closeTo(280.0, 1.0));
    });

    testWidgets(
        'Displays folder hierarchy, indentation, and clipping elbow arrow',
        (tester) async {
      final dummyPng = _createDummyPng();
      final layers = [
        const PsdLayerInfo(
            index: 0,
            name: 'Base Background',
            isVisible: true,
            opacity: 255,
            isFolder: false),
        const PsdLayerInfo(
            index: 1,
            name: 'Group Folder',
            isVisible: true,
            opacity: 255,
            isFolder: true,
            depth: 0),
        const PsdLayerInfo(
            index: 2,
            name: 'Child Layer',
            isVisible: true,
            opacity: 255,
            isFolder: false,
            depth: 1,
            parentIndex: 1),
        const PsdLayerInfo(
            index: 3,
            name: 'Clipped Layer',
            isVisible: true,
            opacity: 255,
            isFolder: false,
            depth: 1,
            parentIndex: 1,
            isClipped: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PsdLayerSheet(
              layers: layers,
              hiddenIndices: const {},
              initialThumbnails: {2: dummyPng, 3: dummyPng},
              onVisibilityChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check titles
      expect(find.text('Group Folder'), findsOneWidget);
      expect(find.text('Child Layer'), findsOneWidget);
      expect(find.text('Clipped Layer'), findsOneWidget);

      // Check clipping arrow icon (Icons.subdirectory_arrow_right_rounded)
      expect(find.byIcon(Icons.subdirectory_arrow_right_rounded), findsWidgets);

      // Check folder icon
      expect(find.byIcon(Icons.folder_rounded), findsWidgets);

      // Check indentation for depth: 1 (SizedBox width = 20.0)
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final depthBox = sizedBoxes.any((box) => box.width == 20.0);
      expect(depthBox, isTrue);
    });

    testWidgets('Toggling folder toggles visibility of all descendant layers',
        (tester) async {
      Set<int> updatedHidden = {};
      final layers = [
        const PsdLayerInfo(
            index: 0,
            name: 'Base',
            isVisible: true,
            opacity: 255,
            isFolder: false),
        const PsdLayerInfo(
            index: 1,
            name: 'Folder 1',
            isVisible: true,
            opacity: 255,
            isFolder: true,
            depth: 0),
        const PsdLayerInfo(
            index: 2,
            name: 'Child 1',
            isVisible: true,
            opacity: 255,
            isFolder: false,
            depth: 1,
            parentIndex: 1),
        const PsdLayerInfo(
            index: 3,
            name: 'Child 2',
            isVisible: true,
            opacity: 255,
            isFolder: false,
            depth: 1,
            parentIndex: 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PsdLayerSheet(
              layers: layers,
              hiddenIndices: const {},
              onVisibilityChanged: (hidden) => updatedHidden = hidden,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find eye icon on Folder 1
      final folderEyeFinder = find.descendant(
        of: find.ancestor(
            of: find.text('Folder 1'), matching: find.byType(InkWell)),
        matching: find.byType(IconButton),
      );
      await tester.tap(folderEyeFinder);
      await tester.pumpAndSettle();

      // Folder 1 and both descendants (2 and 3) must be in updatedHidden!
      expect(updatedHidden.contains(1), isTrue);
      expect(updatedHidden.contains(2), isTrue);
      expect(updatedHidden.contains(3), isTrue);
    });

    testWidgets('Tapping folder row collapses/expands children in the list',
        (tester) async {
      final layers = [
        const PsdLayerInfo(
            index: 0,
            name: 'Base',
            isVisible: true,
            opacity: 255,
            isFolder: false),
        const PsdLayerInfo(
            index: 1,
            name: 'Collapsible Group',
            isVisible: true,
            opacity: 255,
            isFolder: true,
            depth: 0),
        const PsdLayerInfo(
            index: 2,
            name: 'Secret Child',
            isVisible: true,
            opacity: 255,
            isFolder: false,
            depth: 1,
            parentIndex: 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PsdLayerSheet(
              layers: layers,
              hiddenIndices: const {},
              onVisibilityChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Child is visible initially
      expect(find.text('Secret Child'), findsOneWidget);

      // Tap on Collapsible Group
      await tester.tap(find.text('Collapsible Group'));
      await tester.pumpAndSettle();

      // Now Secret Child is hidden (collapsed)
      expect(find.text('Secret Child'), findsNothing);

      // Tap again to expand
      await tester.tap(find.text('Collapsible Group'));
      await tester.pumpAndSettle();

      // Secret Child is visible again
      expect(find.text('Secret Child'), findsOneWidget);
    });
  });
}
