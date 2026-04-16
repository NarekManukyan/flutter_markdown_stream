import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _scaffold({
  required Stream<String> stream,
  StreamingTextController? controller,
  MarkdownStreamFactory<String>? streamFactory,
  MarkdownStreamDoneCallback? onDone,
}) =>
    MaterialApp(
      home: Scaffold(
        body: MarkdownStream(
          stream: stream,
          controller: controller,
          streamFactory: streamFactory,
          onDone: onDone,
          rebuildDebounce: Duration.zero,
        ),
      ),
    );

void main() {
  group('StreamingTextController (unit)', () {
    test('initial state is idle', () {
      final c = StreamingTextController();
      expect(c.state, StreamingState.idle);
      expect(c.isStreaming, isFalse);
      expect(c.isPaused, isFalse);
      expect(c.isCompleted, isFalse);
      expect(c.currentText, '');
      expect(c.chunkCount, 0);
      expect(c.speedMultiplier, 1.0);
      c.dispose();
    });

    test('speedMultiplier validation', () {
      final c = StreamingTextController();
      expect(() => c.speedMultiplier = 0, throwsArgumentError);
      expect(() => c.speedMultiplier = -1, throwsArgumentError);
      c.speedMultiplier = 2.5;
      expect(c.speedMultiplier, 2.5);
      c.dispose();
    });

    test('constructor speedMultiplier assertion', () {
      expect(
        () => StreamingTextController(speedMultiplier: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('onStateChanged + onCompleted fire on state transitions', () {
      final seen = <StreamingState>[];
      var completedCalls = 0;
      final c = StreamingTextController(
        onStateChanged: seen.add,
        onCompleted: () => completedCalls++,
      );
      c.internalSetState(StreamingState.streaming);
      c.internalSetState(StreamingState.completed);
      expect(seen, [StreamingState.streaming, StreamingState.completed]);
      expect(completedCalls, 1);
      c.dispose();
    });
  });

  group('StreamingTextController (widget)', () {
    testWidgets('pause buffers chunks without rendering; resume renders',
        (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() async {
        if (!controller.isClosed) await controller.close();
        streamCtrl.dispose();
      });

      await tester.pumpWidget(
        _scaffold(stream: controller.stream, controller: streamCtrl),
      );

      controller.add('Hello ');
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.textContaining('Hello'), findsOneWidget);
      expect(streamCtrl.state, StreamingState.streaming);

      streamCtrl.pause();
      await tester.pump();
      expect(streamCtrl.state, StreamingState.paused);

      controller.add('world');
      await tester.pump(const Duration(milliseconds: 1));
      // Still showing only "Hello " because paused.
      expect(find.textContaining('world'), findsNothing);

      streamCtrl.resume();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.textContaining('world'), findsOneWidget);
      expect(streamCtrl.state, StreamingState.streaming);
    });

    testWidgets('skipToEnd cancels stream and renders raw buffer immediately',
        (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() async {
        if (!controller.isClosed) await controller.close();
        streamCtrl.dispose();
      });
      String? doneText;

      await tester.pumpWidget(
        _scaffold(
          stream: controller.stream,
          controller: streamCtrl,
          onDone: (t) => doneText = t,
        ),
      );

      controller.add('Partial **bold');
      await tester.pump(const Duration(milliseconds: 1));

      streamCtrl.skipToEnd();
      // Let microtasks settle after the cancel.
      await tester.pump(const Duration(milliseconds: 10));
      await tester.idle();

      expect(streamCtrl.state, StreamingState.completed);
      expect(doneText, 'Partial **bold');
    });

    testWidgets('stop cancels stream without firing onDone', (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() async {
        if (!controller.isClosed) await controller.close();
        streamCtrl.dispose();
      });
      var onDoneCalls = 0;

      await tester.pumpWidget(
        _scaffold(
          stream: controller.stream,
          controller: streamCtrl,
          onDone: (_) => onDoneCalls++,
        ),
      );

      controller.add('x');
      await tester.pump(const Duration(milliseconds: 1));
      streamCtrl.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.idle();

      expect(streamCtrl.state, StreamingState.completed);
      expect(onDoneCalls, 0);
    });

    testWidgets('restart without streamFactory throws', (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() async {
        if (!controller.isClosed) await controller.close();
        streamCtrl.dispose();
      });

      await tester.pumpWidget(
        _scaffold(stream: controller.stream, controller: streamCtrl),
      );

      controller.add('first');
      await tester.pump(const Duration(milliseconds: 1));

      streamCtrl.restart();
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
    });

    testWidgets('restart with streamFactory resubscribes fresh stream',
        (tester) async {
      var generation = 0;
      Stream<String> makeStream() async* {
        generation++;
        yield 'gen$generation ';
      }

      final streamCtrl = StreamingTextController();
      addTearDown(streamCtrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownStream(
              stream: makeStream(),
              streamFactory: makeStream,
              controller: streamCtrl,
              rebuildDebounce: Duration.zero,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.textContaining('gen1'), findsOneWidget);

      streamCtrl.restart();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.idle();
      // Old text is gone, new text shows (controller was reset).
      expect(find.textContaining('gen1'), findsNothing);
      expect(find.textContaining('gen2'), findsOneWidget);
    });

    testWidgets('chunk count increments on each chunk', (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() async {
        if (!controller.isClosed) await controller.close();
        streamCtrl.dispose();
      });

      await tester.pumpWidget(
        _scaffold(stream: controller.stream, controller: streamCtrl),
      );

      controller.add('a');
      controller.add('b');
      controller.add('c');
      await tester.pump(const Duration(milliseconds: 1));
      expect(streamCtrl.chunkCount, 3);
    });

    testWidgets('currentText tracks the rendered sanitized text',
        (tester) async {
      final controller = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(streamCtrl.dispose);

      await tester.pumpWidget(
        _scaffold(stream: controller.stream, controller: streamCtrl),
      );

      controller.add('Hello **bold');
      await tester.pump(const Duration(milliseconds: 1));
      // Sanitized → trailing `**` added.
      expect(streamCtrl.currentText, 'Hello **bold**');

      await controller.close();
      await tester.pump(const Duration(milliseconds: 1));
      // Final (non-sanitized) raw text.
      expect(streamCtrl.currentText, 'Hello **bold');
    });

    testWidgets(
        'swapping streams while a listener calls setState does not crash',
        (tester) async {
      // Regression: MarkdownStream.didUpdateWidget resetting the controller
      // synchronously would trigger "setState() called during build" when the
      // listener rebuilds a parent widget.
      final firstCtl = StreamController<String>();
      final secondCtl = StreamController<String>();
      final streamCtrl = StreamingTextController();
      addTearDown(() async {
        if (!firstCtl.isClosed) await firstCtl.close();
        if (!secondCtl.isClosed) await secondCtl.close();
        streamCtrl.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: streamCtrl,
              builder: (_, __) => MarkdownStream(
                stream: firstCtl.stream,
                controller: streamCtrl,
                rebuildDebounce: Duration.zero,
              ),
            ),
          ),
        ),
      );

      firstCtl.add('first');
      await tester.pump(const Duration(milliseconds: 1));

      // Swap the stream while the widget tree is live; the controller's
      // reset should not fire during build.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: streamCtrl,
              builder: (_, __) => MarkdownStream(
                stream: secondCtl.stream,
                controller: streamCtrl,
                rebuildDebounce: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.idle();

      // Should have no exceptions.
      expect(tester.takeException(), isNull);
    });

    testWidgets('onCompleted fires when natural stream completion happens',
        (tester) async {
      final controller = StreamController<String>();
      var completed = 0;
      final streamCtrl = StreamingTextController(
        onCompleted: () => completed++,
      );
      addTearDown(streamCtrl.dispose);

      await tester.pumpWidget(
        _scaffold(stream: controller.stream, controller: streamCtrl),
      );

      controller.add('done');
      await controller.close();
      await tester.pump(const Duration(milliseconds: 1));
      expect(completed, 1);
    });
  });
}
