import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: child)));

/// Closes [controller] without awaiting inside the test body. Awaiting
/// `close()` directly deadlocks a `testWidgets` body: the `done` event is
/// dispatched on a microtask that only drains during `pump()`, which the
/// await would block. Callers must `pump()` afterwards to deliver `onDone`.
void _finish(StreamController<String> controller) {
  if (!controller.isClosed) unawaited(controller.close());
}

void main() {
  group('onTextChanged', () {
    testWidgets('fires with the projected text and the final raw text',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));
      final seen = <String>[];

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            wordFadeIn: false,
            config: const StreamingTextConfig(rebuildDebounce: Duration.zero),
            onTextChanged: seen.add,
          ),
        ),
      );

      controller.add('Hello ');
      await tester.pump();
      controller.add('**wor');
      await tester.pump();

      // Mid-stream, the unclosed bold is sanitized closed.
      expect(seen.any((t) => t.contains('**wor**')), isTrue);

      _finish(controller);
      await tester.pump();

      // On completion the callback reports the full *raw* buffer.
      expect(seen.last, 'Hello **wor');
    });
  });

  group('smoothing', () {
    testWidgets('reveals text progressively then completes with the full text',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));
      final seen = <String>[];
      String? doneText;

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            config: const StreamingTextConfig(
              smoothingEnabled: true,
              charsPerSecond: 100,
            ),
            onTextChanged: seen.add,
            onDone: (t) => doneText = t,
          ),
        ),
      );

      controller.add('abcdefghij'); // 10 chars
      await tester.pump(); // deliver the chunk

      // After a couple of ticks only a prefix is visible (paced, not instant).
      await tester.pump(const Duration(milliseconds: 32));
      expect(seen, isNotEmpty);
      expect(seen.last.length, lessThan(10));

      // Given enough time the whole target is revealed.
      await tester.pump(const Duration(seconds: 1));
      expect(seen.last, 'abcdefghij');

      _finish(controller);
      await tester.pump();
      expect(doneText, 'abcdefghij');
    });

    testWidgets('chatGPT/claude/smooth presets enable smoothing', (
      tester,
    ) async {
      expect(StreamingPresets.chatGPT.smoothingEnabled, isTrue);
      expect(StreamingPresets.claude.smoothingEnabled, isTrue);
      expect(StreamingPresets.smooth.smoothingEnabled, isTrue);
      expect(StreamingPresets.instant.smoothingEnabled, isFalse);
    });
  });

  group('IncrementalMarkdownBody.stableSplitIndex', () {
    test('returns 0 when there is no top-level blank-line boundary yet', () {
      expect(
        IncrementalMarkdownBody.stableSplitIndex('one paragraph still typing'),
        0,
      );
    });

    test('splits just after a blank line', () {
      const s = 'para one\n\npara two';
      final i = IncrementalMarkdownBody.stableSplitIndex(s);
      expect(s.substring(0, i), 'para one\n\n');
      expect(s.substring(i), 'para two');
    });

    test('chooses the LAST top-level boundary', () {
      const s = 'a\n\nb\n\nc';
      final i = IncrementalMarkdownBody.stableSplitIndex(s);
      expect(s.substring(i), 'c');
    });

    test('never splits on a blank line inside a fenced code block', () {
      const s = '```\ncode\n\nmore\n```';
      expect(IncrementalMarkdownBody.stableSplitIndex(s), 0);
    });
  });

  group('incrementalParsing', () {
    testWidgets('splits settled blocks into separate bodies while streaming',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));

      await tester.pumpWidget(
        _host(
          MarkdownStream(
            stream: controller.stream,
            wordFadeIn: false,
            config: const StreamingTextConfig(rebuildDebounce: Duration.zero),
            incrementalParsing: true,
          ),
        ),
      );

      controller.add('# Head\n\npara one\n\npara ');
      await tester.pump();
      controller.add('two');
      await tester.pump();

      // Settled prefix + active tail => two MarkdownBody widgets.
      expect(find.byType(MarkdownBody), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      _finish(controller);
      await tester.pump();

      // Once done, a single MarkdownBody renders the whole thing.
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
