import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a fresh instance of each cursor, forwarding [semanticLabel] to the
/// underlying widget. Used by the accessibility tests below.
final cursorBuilders = <String, Widget Function(String? semanticLabel)>{
  'BlinkingCursor': (label) => BlinkingCursor(semanticLabel: label),
  'BarCursor': (label) => BarCursor(semanticLabel: label),
  'FadingCursor': (label) => FadingCursor(semanticLabel: label),
  'PulsingCursor': (label) => PulsingCursor(semanticLabel: label),
  'TypingDotsCursor': (label) => TypingDotsCursor(semanticLabel: label),
  'WaveDotsCursor': (label) => WaveDotsCursor(semanticLabel: label),
  'SpinnerCursor': (label) => SpinnerCursor(semanticLabel: label),
  'ShimmerCursor': (label) => ShimmerCursor(semanticLabel: label),
};

/// Counts every [SemanticsNode] in the subtree rooted at [node], inclusive.
int _semanticsNodeCount(SemanticsNode? node) {
  if (node == null) {
    return 0;
  }
  var count = 1;
  node.visitChildren((SemanticsNode child) {
    count += _semanticsNodeCount(child);
    return true;
  });
  return count;
}

/// Pumps [child] inside a minimal `MaterialApp`/`Scaffold` shell and returns
/// the total number of semantics nodes produced.
Future<int> _pumpAndCountSemantics(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return _semanticsNodeCount(
    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode,
  );
}

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
        MaterialApp(
          home: Scaffold(body: Center(child: cursor)),
        ),
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
              ShimmerCursor(
                baseColor: Colors.grey,
                highlightColor: Colors.white,
              ),
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

  group('accessibility', () {
    cursorBuilders.forEach((name, build) {
      testWidgets('$name contributes no semantics nodes by default', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();

        final baseline = await _pumpAndCountSemantics(
          tester,
          const SizedBox.shrink(),
        );
        final withCursor = await _pumpAndCountSemantics(tester, build(null));

        expect(withCursor, equals(baseline));
        expect(find.bySemanticsLabel(RegExp(r'.+')), findsNothing);
        handle.dispose();
      });

      testWidgets(
        '$name exposes semanticLabel as a single semantics node when provided',
        (tester) async {
          final handle = tester.ensureSemantics();

          final baseline = await _pumpAndCountSemantics(
            tester,
            const SizedBox.shrink(),
          );
          final withLabel = await _pumpAndCountSemantics(
            tester,
            build('typing'),
          );

          expect(withLabel, equals(baseline + 1));
          expect(find.bySemanticsLabel('typing'), findsOneWidget);
          handle.dispose();
        },
      );
    });
  });
}
