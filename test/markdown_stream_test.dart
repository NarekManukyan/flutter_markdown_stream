import 'dart:async';

import 'package:flutter/material.dart';
import 'package:streaming_markdown/streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChunk {
  const _FakeChunk(this.delta);
  final String delta;
}

void main() {
  testWidgets('renders incrementally and calls onDone', (tester) async {
    final controller = StreamController<String>();
    String? done;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            onDone: (text) => done = text,
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add('Hello ');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.textContaining('Hello'), findsOneWidget);

    controller.add('**world');
    await tester.pump(const Duration(milliseconds: 1));
    // Even though the bold is unclosed, the widget should still render.
    expect(find.textContaining('world'), findsOneWidget);

    controller.add('**!');
    await controller.close();
    await tester.pump(const Duration(milliseconds: 1));

    expect(done, 'Hello **world**!');
  });

  testWidgets('shows cursor widget until stream completes', (tester) async {
    final controller = StreamController<String>();
    const cursorKey = Key('cursor');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            cursorWidget: const SizedBox(key: cursorKey, width: 1, height: 1),
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add('streaming');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(cursorKey), findsOneWidget);

    await controller.close();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(cursorKey), findsNothing);
  });

  testWidgets('swapping streams resets the buffer', (tester) async {
    final first = StreamController<String>();
    final second = StreamController<String>();

    Widget build(Stream<String> s) => MaterialApp(
          home: Scaffold(
            body: MarkdownStream(stream: s, rebuildDebounce: Duration.zero),
          ),
        );

    await tester.pumpWidget(build(first.stream));
    first.add('alpha');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.textContaining('alpha'), findsOneWidget);

    // Swap in a new stream — the old buffer must be discarded.
    await tester.pumpWidget(build(second.stream));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.textContaining('alpha'), findsNothing);

    second.add('beta');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.textContaining('beta'), findsOneWidget);

    await first.close();
    await second.close();
  });

  testWidgets('accepts a typed stream via chunkToText', (tester) async {
    // A fake SDK-style typed chunk.
    final controller = StreamController<_FakeChunk>();
    String? done;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream<_FakeChunk>(
            stream: controller.stream,
            chunkToText: (c) => c.delta,
            onDone: (text) => done = text,
            rebuildDebounce: Duration.zero,
          ),
        ),
      ),
    );

    controller.add(const _FakeChunk('Hello '));
    controller.add(const _FakeChunk('**world**'));
    await controller.close();
    await tester.pump(const Duration(milliseconds: 1));

    expect(done, 'Hello **world**');
    expect(find.textContaining('world'), findsOneWidget);
  });

  testWidgets('survives partial code fence without crashing', (tester) async {
    final controller = StreamController<String>();

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

    controller.add('```dart\nfinal x = 1;');
    await tester.pump(const Duration(milliseconds: 1));
    // No exception should be thrown; widget should render the code.
    expect(tester.takeException(), isNull);

    controller.add('\n```\ndone');
    await controller.close();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
  });
}
