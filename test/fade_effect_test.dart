import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no ShaderMask when fade is disabled', (tester) async {
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

    controller.add('streaming content');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('ShaderMask is present during streaming when fade is enabled',
      (tester) async {
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            config: const StreamingTextConfig(
              fadeInEnabled: true,
              rebuildDebounce: Duration.zero,
            ),
          ),
        ),
      ),
    );

    controller.add('streaming content');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('ShaderMask animates away after stream completes',
      (tester) async {
    final controller = StreamController<String>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            config: const StreamingTextConfig(
              fadeInEnabled: true,
              fadeInDuration: Duration(milliseconds: 200),
              rebuildDebounce: Duration.zero,
            ),
          ),
        ),
      ),
    );

    controller.add('streaming content');
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ShaderMask), findsOneWidget);

    await controller.close();
    // Complete frame right after done: mask still there, animating away.
    await tester.pump(const Duration(milliseconds: 1));
    // After the fade-out completes and some further pump, the ShaderMask
    // should be gone (we early-return when t <= 0).
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('toggling fadeInEnabled multiple times does not crash',
      (tester) async {
    // Regression: SingleTickerProviderStateMixin crashes when a new
    // AnimationController is created after disposing the old one. The render
    // state must use TickerProviderStateMixin to allow multiple tickers.
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    Widget build(StreamingTextConfig config) => MaterialApp(
          home: Scaffold(
            body: MarkdownStream(
              stream: controller.stream,
              config: config,
            ),
          ),
        );

    await tester.pumpWidget(build(const StreamingTextConfig(fadeInEnabled: true)));
    controller.add('a');
    await tester.pump(const Duration(milliseconds: 50));

    // fade off → disposes the controller
    await tester.pumpWidget(build(const StreamingTextConfig()));
    await tester.pump(const Duration(milliseconds: 50));

    // fade on again → must create a NEW AnimationController
    await tester.pumpWidget(build(const StreamingTextConfig(fadeInEnabled: true)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets('chatGPT preset produces a ShaderMask', (tester) async {
    final controller = StreamController<String>();
    addTearDown(() async => controller.close());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownStream(
            stream: controller.stream,
            config: StreamingPresets.chatGPT,
          ),
        ),
      ),
    );

    controller.add('hello');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}
