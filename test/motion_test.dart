import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: SizedBox(width: 400, child: child)),
      ),
    );

void _finish(StreamController<String> controller) {
  if (!controller.isClosed) unawaited(controller.close());
}

const _instant = StreamingTextConfig(rebuildDebounce: Duration.zero);

/// Alpha of the span holding [word] inside the fading paragraph.
double? _alphaOf(WidgetTester tester, String word) {
  double? alpha;
  for (final rich in tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(WordFadeText),
      matching: find.byType(RichText),
    ),
  )) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == word) {
        alpha = span.style?.color?.a;
      }
      return true;
    });
  }
  return alpha;
}

void main() {
  group('time-based word fade', () {
    testWidgets('a new word fades in over the fade duration', (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add('hello');
      await tester.pump();
      expect(_alphaOf(tester, 'hello'), lessThan(0.2));

      await tester.pump(const Duration(milliseconds: 100));
      final mid = _alphaOf(tester, 'hello')!;
      expect(mid, greaterThan(0.5)); // strong ease-out: most of it early
      expect(mid, lessThan(1));

      await tester.pump(const Duration(milliseconds: 250));
      expect(_alphaOf(tester, 'hello'), closeTo(1, 0.001));
    });

    testWidgets('words finish fading while the stream stalls', (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add('one two three');
      await tester.pump();
      // No new text arrives; the last word still reaches full opacity.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_alphaOf(tester, 'three'), closeTo(1, 0.001));
    });

    testWidgets('an older word keeps its own fade when new words arrive',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add('first');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      controller.add(' second');
      await tester.pump();
      await tester.pump();
      expect(_alphaOf(tester, 'first'), closeTo(1, 0.001));
      expect(_alphaOf(tester, 'second'), lessThan(0.2));
    });

    testWidgets('reduce motion shows words at full opacity', (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(stream: controller.stream, config: _instant),
          reduceMotion: true,
        ),
      );
      controller.add('hello there');
      await tester.pump();
      expect(_alphaOf(tester, 'there'), closeTo(1, 0.001));
    });

    testWidgets('wordFadeDuration: null keeps the position-based ramp',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            config: _instant,
            wordFadeDuration: null,
          ),
        ),
      );
      controller.add('a b c d e f');
      await tester.pump(const Duration(seconds: 1));
      expect(_alphaOf(tester, 'a'), closeTo(1, 0.001));
      expect(_alphaOf(tester, 'f'), lessThan(1));
    });
  });

  group('settling', () {
    testWidgets('a finished paragraph keeps fading, then uses MarkdownBody',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add('first paragraph');
      await tester.pump();
      controller.add('\n\nsecond');
      await tester.pump();

      // Both paragraphs still fade: the first one's last word has not
      // finished yet.
      expect(find.byType(WordFadeText), findsNWidgets(2));
      expect(_alphaOf(tester, 'paragraph'), lessThan(1));

      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(WordFadeText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on completion the last words finish fading first',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add('the very end');
      await tester.pump();
      _finish(controller);
      await tester.pump();
      await tester.pump();

      // Done, but the last word is mid-fade rather than snapped to opaque.
      expect(find.byType(WordFadeText), findsOneWidget);
      expect(_alphaOf(tester, 'end'), lessThan(1));

      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(WordFadeText), findsNothing);
      expect(find.byType(MarkdownBody), findsOneWidget);
    });
  });

  group('caret', () {
    double opacityOf(WidgetTester tester) => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byType(BlinkingCursor),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;

    testWidgets('stays solid while text arrives, blinks while waiting',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            config: _instant,
            wordFadeIn: false,
            cursorWidget: const BlinkingCursor(),
          ),
        ),
      );

      // Text keeps arriving every 300ms, longer than half a blink (450ms)
      // would allow without the hold: the caret never goes dark.
      for (var i = 0; i < 6; i++) {
        controller.add('word ');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(opacityOf(tester), 1, reason: 'after chunk $i');
      }

      // The stream stalls: the caret blinks off within one period.
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester), 0);
    });
  });

  group('copy button', () {
    testWidgets('icon and label cross-fade instead of swapping',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodeBlockView(code: 'x', language: 'dart')),
        ),
      );
      await tester.tap(find.text('Copy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mid-transition both labels are on screen.
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Copied'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Copy'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
