import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_markdown_stream/src/thinking.dart' show ThinkingSplit;
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

const _instant = StreamingTextConfig(rebuildDebounce: Duration.zero);

void _finish(StreamController<String> controller) {
  if (!controller.isClosed) unawaited(controller.close());
}

/// Every TextSpan in the tree with a tap recognizer, by its text.
List<String> _linkTexts(WidgetTester tester) {
  final out = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null && span.text != null) {
        out.add(span.text!);
      }
      return true;
    });
  }
  return out;
}

void main() {
  group('MarkdownStream.text', () {
    const md = '# Title\n\nSome **bold** text.\n\n- one\n- two\n';

    testWidgets('renders like a completed stream', (tester) async {
      await tester.pumpWidget(_app(MarkdownStream.text(data: md)));
      final staticBodies = find.byType(MarkdownBody).evaluate().length;
      expect(find.text('Title'), findsOneWidget);
      expect(find.byType(WordFadeText), findsNothing);

      final controller = StreamController<String>();
      await tester.pumpWidget(
        _app(MarkdownStream(stream: controller.stream, config: _instant)),
      );
      controller.add(md);
      await controller.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MarkdownBody).evaluate().length, staticBodies);
    });

    testWidgets('shows new data when it changes', (tester) async {
      await tester.pumpWidget(_app(MarkdownStream.text(data: 'first')));
      expect(find.text('first'), findsOneWidget);
      await tester.pumpWidget(_app(MarkdownStream.text(data: 'second')));
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    });

    testWidgets('a thinking section starts folded', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownStream.text(
            data: '<think>private notes</think>\n\nThe answer.',
          ),
        ),
      );
      expect(find.text('Thoughts'), findsOneWidget);
      expect(find.text('private notes'), findsNothing);
      expect(find.text('The answer.'), findsOneWidget);
    });
  });

  group('initialText', () {
    testWidgets('appears at once and is part of the final text',
        (tester) async {
      final controller = StreamController<String>();
      String? done;
      await tester.pumpWidget(
        _app(
          MarkdownStream(
            stream: controller.stream,
            initialText: 'Already here. ',
            // Default config: smoothing on, so pacing would be visible.
            onDone: (t) => done = t,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Already here.'), findsOneWidget);

      controller.add('And more.');
      await controller.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(done, 'Already here. And more.');
      expect(find.textContaining('And more.'), findsOneWidget);
    });
  });

  group('LinkPolicy', () {
    const policy = LinkPolicy();

    test('reads schemes the way a URL parser does', () {
      expect(LinkPolicy.schemeOf('https://a.com'), 'https');
      expect(LinkPolicy.schemeOf('JavaScript:alert(1)'), 'javascript');
      expect(LinkPolicy.schemeOf('java\tscript:x'), 'javascript');
      expect(LinkPolicy.schemeOf('javascript&#58;x'), 'javascript');
      expect(LinkPolicy.schemeOf('javascript&#x3A;x'), 'javascript');
      expect(LinkPolicy.schemeOf(r'javascript\:x'), 'javascript');
      expect(LinkPolicy.schemeOf(' <data:text/html,x> '), 'data');
      expect(LinkPolicy.schemeOf('#notes'), isNull);
      expect(LinkPolicy.schemeOf('/docs/a.html'), isNull);
    });

    test('blocked links and images become text', () {
      expect(policy.apply('[click](javascript:alert(1)) now'), 'click now');
      expect(policy.apply('see ![hosts](file:///etc/hosts)'), 'see hosts');
      expect(policy.apply('![x](data:image/png;base64,AAA)'), 'x');
      expect(policy.apply('![a](foo.png)'), 'a');
      expect(policy.apply('<javascript:alert(1)>'), 'javascript:alert(1)');
      expect(
        policy.apply('[**bold** label](vbscript:x "t")'),
        '**bold** label',
      );
    });

    test('allowed links, code and escapes are left alone', () {
      for (final s in [
        '[docs](https://a.com/x_(y))',
        '[mail](mailto:a@b.com)',
        '[anchor](#part-2)',
        '<https://a.com>',
        '<a@b.com>',
        '`[c](javascript:x)`',
        '```\n[c](javascript:x)\n```',
        r'\[not](javascript:x)',
        '![pic](https://a.com/p.png)',
      ]) {
        expect(policy.apply(s), s, reason: s);
      }
    });

    test('nested blocked image inside an allowed link', () {
      expect(
        policy.apply('[![i](data:x)](https://ok.com)'),
        '[i](https://ok.com)',
      );
    });

    test('blocked reference definitions are removed', () {
      expect(
        policy.apply('[x][r]\n\n[r]: javascript:alert(1)\n'),
        '[x][r]\n\n\n',
      );
      expect(
        policy.apply('[x][r]\n\n[r]: https://ok.com\n'),
        '[x][r]\n\n[r]: https://ok.com\n',
      );
    });

    test('extra schemes can be allowed', () {
      const app = LinkPolicy(linkSchemes: {'https', 'myapp'});
      expect(app.apply('[open](myapp://chat/1)'), '[open](myapp://chat/1)');
      expect(app.apply('[mail](mailto:a@b.com)'), 'mail');
    });

    testWidgets('blocked links render as plain text, allowed ones tap',
        (tester) async {
      final taps = <String?>[];
      await tester.pumpWidget(
        _app(
          MarkdownStream.text(
            data: '[bad](javascript:alert(1)) and [good](https://a.com)',
            onTapLink: (text, href, title) => taps.add(href),
          ),
        ),
      );
      expect(_linkTexts(tester), <String>['good']);
      await tester.tap(find.textContaining('good'));
      // The tap lands on the paragraph; fire the recognizer directly.
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          final r = span is TextSpan ? span.recognizer : null;
          if (r is TapGestureRecognizer) r.onTap?.call();
          return true;
        });
      }
      expect(taps, contains('https://a.com'));
      expect(taps, isNot(contains('javascript:alert(1)')));
    });

    testWidgets('linkPolicy: null keeps every link', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownStream.text(
            data: '[bad](javascript:alert(1))',
            linkPolicy: null,
            onTapLink: (_, __, ___) {},
          ),
        ),
      );
      expect(_linkTexts(tester), <String>['bad']);
    });

    testWidgets('imageDirectory allows relative images', (tester) async {
      final loaded = <Uri>[];
      Widget build({String? dir}) => _app(
            MarkdownStream.text(
              data: '![logo](logo.png)',
              imageDirectory: dir,
              imageBuilder: (uri, title, alt) {
                loaded.add(uri);
                return const SizedBox(width: 10, height: 10);
              },
            ),
          );
      await tester.pumpWidget(build());
      expect(loaded, isEmpty);
      expect(find.text('logo'), findsOneWidget);
      await tester.pumpWidget(build(dir: 'https://cdn.example.com/'));
      expect(loaded, isNotEmpty);
    });
  });

  group('ThinkingSplit', () {
    test('no thinking section', () {
      expect(ThinkingSplit.parse('hello', done: false), isNull);
      expect(ThinkingSplit.parse('<b>x</b>', done: false), isNull);
    });

    test('half-typed opening tag is hidden while streaming', () {
      final s = ThinkingSplit.parse('  <thi', done: false)!;
      expect(s.thinking, '');
      expect(s.isOpen, isTrue);
      expect(ThinkingSplit.parse('<thi', done: true), isNull);
    });

    test('open section hides a half-typed closing tag', () {
      final s = ThinkingSplit.parse('<think>step one</thi', done: false)!;
      expect(s.thinking, 'step one');
      expect(s.answer, '');
      expect(s.isOpen, isTrue);
    });

    test('closed section splits off the answer', () {
      final s = ThinkingSplit.parse(
        '<THINKING>\nplan\n</Thinking>\n\n  Answer here',
        done: false,
      )!;
      expect(s.thinking, 'plan');
      expect(s.answer, 'Answer here');
      expect(s.isOpen, isFalse);
    });
  });

  group('thinking section', () {
    testWidgets('open while thinking, folds when the answer starts',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));
      await tester.pumpWidget(
        _app(
          MarkdownStream(
            stream: controller.stream,
            config: _instant,
            cursorWidget: const BlinkingCursor(),
          ),
        ),
      );
      controller.add('<think>Let me work this out');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ShimmerText), findsOneWidget);
      expect(find.text('Let me work this out'), findsOneWidget);
      expect(find.byType(BlinkingCursor), findsNothing);

      controller.add('</think>\n\nThe answer is 4.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ShimmerText), findsNothing);
      expect(find.textContaining('Thought for'), findsOneWidget);
      expect(find.text('Let me work this out'), findsNothing);
      expect(find.textContaining('The answer is 4.'), findsOneWidget);

      await tester.tap(find.textContaining('Thought for'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Let me work this out'), findsOneWidget);
    });

    testWidgets('custom thinkingBuilder gets the state', (tester) async {
      final states = <ThinkingState>[];
      await tester.pumpWidget(
        _app(
          MarkdownStream.text(
            data: '<think>notes</think>answer',
            thinkingBuilder: (context, state) {
              states.add(state);
              return const Text('custom thinking');
            },
          ),
        ),
      );
      expect(find.text('custom thinking'), findsOneWidget);
      expect(states.last.text, 'notes');
      expect(states.last.isActive, isFalse);
      expect(states.last.elapsed, isNull);
    });

    testWidgets('parseThinking: false leaves the text alone', (tester) async {
      await tester.pumpWidget(
        _app(
          MarkdownStream.text(
            data: '<think>notes</think>answer',
            parseThinking: false,
          ),
        ),
      );
      expect(find.byType(ThinkingBlock), findsNothing);
    });
  });

  group('placeholder', () {
    testWidgets('shows until the first chunk, then cross-fades away',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() => _finish(controller));
      await tester.pumpWidget(
        _app(
          MarkdownStream(
            stream: controller.stream,
            config: _instant,
            cursorWidget: const BlinkingCursor(),
            placeholder: const Text('waiting'),
          ),
        ),
      );
      expect(find.text('waiting'), findsOneWidget);
      expect(find.byType(BlinkingCursor), findsNothing);

      controller.add('Hello');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('waiting'), findsNothing);
      expect(find.textContaining('Hello'), findsOneWidget);
    });

    testWidgets('goes away when the stream ends empty', (tester) async {
      final controller = StreamController<String>();
      await tester.pumpWidget(
        _app(
          MarkdownStream(
            stream: controller.stream,
            config: _instant,
            placeholder: const Text('waiting'),
          ),
        ),
      );
      await controller.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('waiting'), findsNothing);
    });

    testWidgets('ShimmerText is still under reduce motion', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: ShimmerText('Thinking…')),
          ),
        ),
      );
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Thinking…'), findsOneWidget);
    });
  });
}
