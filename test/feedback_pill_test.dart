import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/widgets/feedback_pill.dart';

void main() {
  testWidgets('showFeedbackPill displays message, icon, and dismisses automatically',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: Container(
            height: 70,
            color: Colors.blue,
            child: const Center(child: Text('Footer')),
          ),
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    showFeedbackPill(
                      context,
                      message: 'Media moved to trash',
                      icon: Icons.delete_outline_rounded,
                    );
                  },
                  child: const Text('Delete Item'),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Initial state: no pill
    expect(find.text('Media moved to trash'), findsNothing);

    // Tap button to show pill
    await tester.tap(find.text('Delete Item'));
    await tester.pump(); // Start animation
    await tester.pump(const Duration(milliseconds: 150)); // Animation complete

    // Verify pill is displayed
    expect(find.text('Media moved to trash'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    // Verify it is positioned above the footer
    final pillFinder = find.ancestor(
      of: find.text('Media moved to trash'),
      matching: find.byType(Positioned),
    );
    expect(pillFinder, findsOneWidget);
    final positioned = tester.widget<Positioned>(pillFinder);
    expect(positioned.bottom, greaterThanOrEqualTo(84.0));

    // Wait past the auto-dismiss timer (1350ms + 150ms reverse animation)
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 200));

    // Pill should now be dismissed
    expect(find.text('Media moved to trash'), findsNothing);
  });

  testWidgets('showFeedbackPill updates smoothly when triggered multiple times',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      showFeedbackPill(
                        context,
                        message: '1 item restored',
                        icon: Icons.restore_rounded,
                      );
                    },
                    child: const Text('Restore'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showFeedbackPill(
                        context,
                        message: 'Media deleted',
                        icon: Icons.delete_outline_rounded,
                      );
                    },
                    child: const Text('Delete'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    // Tap restore
    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('1 item restored'), findsOneWidget);
    expect(find.byIcon(Icons.restore_rounded), findsOneWidget);

    // Tap delete before restore dismisses
    await tester.tap(find.text('Delete'));
    await tester.pump();

    // Verify it updated smoothly without duplicate pills
    expect(find.text('Media deleted'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.text('1 item restored'), findsNothing);

    // Clean up timer
    await tester.pump(const Duration(milliseconds: 1600));
  });
}
