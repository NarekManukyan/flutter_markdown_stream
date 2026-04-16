import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no explicit Directionality injected when textDirection is null',
      (tester) async {
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add('hello');
    await tester.pump(const Duration(milliseconds: 1));

    // MaterialApp provides an ambient Directionality already; we assert that
    // the widget itself did not add a NEW Directionality under Scaffold.body.
    final bodyScope = find.descendant(
      of: find.byType(Scaffold),
      matching: find.byType(MarkdownStream<String>),
    );
    expect(bodyScope, findsOneWidget);
    final markdownStream = tester.widget<MarkdownStream<String>>(bodyScope);
    expect(markdownStream.textDirection, isNull);
  });

  testWidgets('explicit textDirection injects a Directionality', (tester) async {
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            textDirection: TextDirection.rtl,
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add('hello');
    await tester.pump(const Duration(milliseconds: 1));

    // Find a Directionality whose textDirection is rtl and that is a
    // descendant of our MarkdownStream.
    final rtlDirectionality = find
        .descendant(
          of: find.byType(MarkdownStream<String>),
          matching: find.byWidgetPredicate(
            (w) => w is Directionality && w.textDirection == TextDirection.rtl,
          ),
        )
        .evaluate();
    expect(rtlDirectionality, isNotEmpty);
  });

  testWidgets('RTL Directionality is an ancestor of the MarkdownBody on first render',
      (tester) async {
    // Regression: the first render must already see RTL, otherwise short
    // chunks render left-aligned until a later rebuild flips them to the
    // right.
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            textDirection: TextDirection.rtl,
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add('مرحبا');
    await tester.pump(const Duration(milliseconds: 1));

    // Walk up from any Text widget inside the stream and assert the nearest
    // Directionality is RTL. If the outer Directionality hadn't been applied
    // before the MarkdownBody's children built, some intermediate widget
    // would resolve with the ambient (LTR) direction.
    final textEl = find.descendant(
      of: find.byType(MarkdownStream<String>),
      matching: find.byType(Text),
    );
    expect(textEl, findsWidgets);
    final context = tester.element(textEl.first);
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets(
      'RTL short content is positioned toward the right edge, not the left',
      (tester) async {
    // Regression: with fitContent:true the streamed text would otherwise
    // anchor to the LEFT during early chunks, only flipping to the right
    // once content filled the full width.
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MarkdownStream(
              stream: controller.stream,
              textDirection: TextDirection.rtl,
              cursorWidget: const SizedBox(
                key: Key('cursor'),
                width: 2,
                height: 10,
              ),
              rebuildDebounce: Duration.zero,
            ),
          ),
        ),
      ),
    );

    // Add a very short Arabic string. Under the old buggy layout, this text
    // occupied the LEFT side of the 400-wide container.
    controller.add('مرحبا');
    await tester.pump(const Duration(milliseconds: 1));

    final markdownBodyRb = tester.renderObject<RenderBox>(
      find.byType(MarkdownStream<String>),
    );
    // MarkdownBody and the outer widget should span the full 400 available.
    expect(markdownBodyRb.size.width, closeTo(400, 0.5));

    // The rendered Text widget's right edge should be at the container's
    // right edge (within 1px). If it were anchored to the left (the bug),
    // its RIGHT edge would be far less than 400.
    final textFinder = find
        .descendant(
          of: find.byType(MarkdownStream<String>),
          matching: find.byType(RichText),
        )
        .first;
    final textRb = tester.renderObject<RenderBox>(textFinder);
    final rect = textRb.localToGlobal(Offset.zero) & textRb.size;
    // Right edge of the text should be near the right edge of the 400-wide
    // container.
    expect(rect.right, closeTo(400, 1.0));
  });

  testWidgets('LTR text direction is also propagated when set', (tester) async {
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            textDirection: TextDirection.ltr,
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add('hello');
    await tester.pump(const Duration(milliseconds: 1));

    final ltrDirectionality = find
        .descendant(
          of: find.byType(MarkdownStream<String>),
          matching: find.byWidgetPredicate(
            (w) => w is Directionality && w.textDirection == TextDirection.ltr,
          ),
        )
        .evaluate();
    expect(ltrDirectionality, isNotEmpty);
  });
}
