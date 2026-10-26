import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: child)));

/// Closes [controller] without awaiting inside the test body (see
/// integration_features_test.dart for why awaiting would deadlock).
void _finish(StreamController<String> controller) {
  if (!controller.isClosed) unawaited(controller.close());
}

const _cursorKey = Key('cursor');
const _cursor = SizedBox(key: _cursorKey, width: 2, height: 10);

const _instant = StreamingTextConfig(rebuildDebounce: Duration.zero);

String _plainText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

/// The color of the innermost span whose text is exactly [text].
Color? _colorOf(WidgetTester tester, String text) {
  Color? found;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    void visit(InlineSpan span, TextStyle? inherited) {
      final style = inherited?.merge(span.style) ?? span.style;
      if (span is TextSpan) {
        if (span.text == text) found = style?.color;
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }
    }

    visit(rich.text, null);
  }
  return found;
}

void main() {
  group('inline cursor', () {
    for (final fade in <bool>[false, true]) {
      testWidgets('sits inside the paragraph text (wordFadeIn: $fade)',
          (tester) async {
        final controller = StreamController<String>();
        addTearDown(() => _finish(controller));

        await tester.pumpWidget(
          _host(
            MarkdownStream(
              stream: controller.stream,
              cursorWidget: _cursor,
              wordFadeIn: fade,
              config: _instant,
            ),
          ),
        );
        controller.add('Hello there');
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(RichText),
            matching: find.byKey(_cursorKey),
          ),
          findsOneWidget,
        );
        expect(_plainText(tester), isNot(contains('⸻')));

        _finish(controller);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(_cursorKey), findsNothing);
      });
    }

    testWidgets('does not break an emphasis closer right before it',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            cursorWidget: _cursor,
            wordFadeIn: false,
            config: _instant,
          ),
        ),
      );
      controller.add('say _hi_');
      await tester.pump();

      expect(_plainText(tester), isNot(contains('_')));
      expect(find.byKey(_cursorKey), findsOneWidget);
    });

    testWidgets('is shown after a closed code block', (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            cursorWidget: _cursor,
            config: _instant,
          ),
        ),
      );
      controller.add('```dart\nfinal x = 1;\n```\n');
      await tester.pump();

      expect(find.byKey(_cursorKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is shown before any text arrives', (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            cursorWidget: _cursor,
            config: _instant,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(_cursorKey), findsOneWidget);
    });
  });

  group('settled blocks follow style changes', () {
    testWidgets('a new styleSheet restyles already-settled blocks',
        (tester) async {
      final controller = StreamController<String>.broadcast();
      addTearDown(() => _finish(controller));

      Widget build(Color color) => _host(
            MarkdownStream(
              stream: controller.stream,
              incrementalParsing: true,
              wordFadeIn: false,
              config: _instant,
              styleSheet: MarkdownStyleSheet(p: TextStyle(color: color)),
            ),
          );

      await tester.pumpWidget(build(const Color(0xFFFF0000)));
      controller.add('first para\n\nsecond');
      await tester.pump();

      await tester.pumpWidget(build(const Color(0xFF0000FF)));
      await tester.pump();

      expect(_colorOf(tester, 'first para'), const Color(0xFF0000FF));
    });
  });

  group('word fade styling', () {
    testWidgets('fading tail uses the style sheet for bold runs',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));
      const green = Color(0xFF00AA00);

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            config: _instant,
            styleSheet: MarkdownStyleSheet(
              strong: const TextStyle(color: green),
            ),
          ),
        ),
      );
      controller.add('one two **bold** three four five six seven');
      await tester.pump();

      expect(find.byType(WordFadeText), findsOneWidget);
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(WordFadeText),
          matching: find.byType(RichText),
        ),
      );
      final spans = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'bold') spans.add(span);
        return true;
      });
      expect(spans, isNotEmpty);
      expect(spans.single.style!.color!.toARGB32() & 0xFFFFFF, 0x00AA00);
    });

    testWidgets('a paragraph with a link renders through MarkdownBody',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add('see [docs](https://example.com) for more');
      await tester.pump();

      expect(find.byType(WordFadeText), findsNothing);
      expect(_plainText(tester), contains('docs'));
      expect(_plainText(tester), isNot(contains('](')));
    });
  });

  group('stream errors', () {
    testWidgets('onError and errorBuilder fire; controller ends in error',
        (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() {
        _finish(controller);
        streamCtrl.dispose();
      });
      Object? seenError;
      var doneCalls = 0;

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            controller: streamCtrl,
            config: _instant,
            onError: (e, _) => seenError = e,
            onDone: (_) => doneCalls++,
            errorBuilder: (context, error) => Text('failed: $error'),
          ),
        ),
      );
      controller.add('partial answer');
      await tester.pump();
      controller.addError('boom');
      await tester.pump();
      await tester.pump();

      expect(seenError, 'boom');
      expect(doneCalls, 1);
      expect(streamCtrl.state, StreamingState.error);
      expect(find.text('failed: boom'), findsOneWidget);
      expect(_plainText(tester), contains('partial answer'));
    });
  });

  group('IncrementalMarkdownBody block boundaries', () {
    test('does not split between items of a loose list', () {
      const s = '- one\n\n- two\n\n- three';
      expect(IncrementalMarkdownBody.stableSplitIndex(s), 0);
    });

    test('splits between a paragraph and the list that follows', () {
      const s = 'Intro:\n\n- one\n\n- two';
      final i = IncrementalMarkdownBody.stableSplitIndex(s);
      expect(s.substring(i), '- one\n\n- two');
    });

    test('does not split before an indented continuation', () {
      const s = '1. step\n\n   more about the step';
      expect(IncrementalMarkdownBody.stableSplitIndex(s), 0);
    });

    test('keeps text with reference definitions in one block', () {
      const s = 'See [the docs][d].\n\nMore.\n\n[d]: https://example.com';
      expect(IncrementalMarkdownBody.stableSplitIndex(s), 0);
    });

    test('a fence nested in a list hides its blank lines', () {
      const s = '- item\n\n    ```\n    a\n\n    b\n    ```\n\nafter';
      final i = IncrementalMarkdownBody.stableSplitIndex(s);
      expect(s.substring(i), 'after');
    });

    testWidgets('resumed scanning matches a fresh scan', (tester) async {
      const full = '# Title\n\nPara one.\n\n- a\n\n- b\n\n```\nx\n\ny\n```\n\n'
          'Closing para.\n\nLast';
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            wordFadeIn: false,
            incrementalParsing: true,
            config: _instant,
          ),
        ),
      );
      for (final ch in full.split('')) {
        controller.add(ch);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);

      // Blocks: title, para one, list, code, closing para, last.
      expect(find.byType(MarkdownBody), findsNWidgets(6));
    });
  });
}
