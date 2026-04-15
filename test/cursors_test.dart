import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies every cursor in the family pumps at least two frames of
/// animation without throwing and tears down its ticker cleanly on unmount.
void main() {
  final cursors = <String, Widget>{
    'BlinkingCursor': const BlinkingCursor(),
    'BarCursor': const BarCursor(),
    'FadingCursor': const FadingCursor(),
    'PulsingCursor': const PulsingCursor(),
    'TypingDotsCursor': const TypingDotsCursor(),
    'WaveDotsCursor': const WaveDotsCursor(),
    'SpinnerCursor': const SpinnerCursor(),
    'ShimmerCursor': const ShimmerCursor(),
  };

  cursors.forEach((name, cursor) {
    testWidgets('$name animates and disposes cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: cursor))),
      );
      // Pump a few frames of animation.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // Unmount — any leaked ticker would trigger a FlutterError here.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('cursors accept a custom color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BlinkingCursor(color: Colors.red),
              BarCursor(color: Colors.green),
              FadingCursor(color: Colors.blue),
              PulsingCursor(color: Colors.orange),
              TypingDotsCursor(color: Colors.purple),
              WaveDotsCursor(color: Colors.teal),
              SpinnerCursor(color: Colors.pink),
              ShimmerCursor(baseColor: Colors.grey, highlightColor: Colors.white),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PulsingCursor asserts minScale invariants', (tester) async {
    expect(
      () => PulsingCursor(minScale: 0, maxScale: 1),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => PulsingCursor(minScale: 1.5, maxScale: 1),
      throwsA(isA<AssertionError>()),
    );
  });
}
