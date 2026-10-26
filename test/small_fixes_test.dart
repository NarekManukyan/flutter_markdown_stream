import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    );

/// Renders [text] as a completed stream.
Future<void> _renderDone(
  WidgetTester tester,
  String text, {
  MarkdownStyleSheet? styleSheet,
  double? tableColumnMaxWidth = 320,
  LaTeXBuilder? latexBuilder,
}) async {
  final controller = StreamController<String>();
  await tester.pumpWidget(
    _app(
      SizedBox(
        width: 300,
        child: MarkdownStream(
          stream: controller.stream,
          rebuildDebounce: Duration.zero,
          styleSheet: styleSheet,
          tableColumnMaxWidth: tableColumnMaxWidth,
          latexBuilder: latexBuilder,
        ),
      ),
    ),
  );
  controller.add(text);
  await controller.close();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

bool _hasStrikethrough(WidgetTester tester) {
  var found = false;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span.style?.decoration == TextDecoration.lineThrough) found = true;
      return true;
    });
  }
  return found;
}

Finder _horizontalScroll() => find.byWidgetPredicate(
      (w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );

void main() {
  group('single ~ between digits', () {
    String esc(String s, {bool latex = false}) =>
        SafeMarkdownParser.escapeSingleTildes(s, latexEnabled: latex);

    test('escapes a range so it is not strikethrough', () {
      expect(esc('20~25 and 30~40'), r'20\~25 and 30\~40');
      expect(esc('1~2~3'), r'1\~2\~3');
    });

    test('leaves real strikethrough and other tildes alone', () {
      for (final s in [
        '~~gone~~',
        'about ~5 minutes',
        'a~b',
        '5~~6',
        'no tilde here',
      ]) {
        expect(esc(s), s);
      }
    });

    test('skips code, URLs and math', () {
      for (final s in [
        '`20~25`',
        '```\n20~25\n```',
        'see https://x.com/a1~2b',
        '[link](https://x.com/1~2)',
      ]) {
        expect(esc(s), s);
      }
      expect(esc(r'$x_1~2$', latex: true), r'$x_1~2$');
      // CRLF line endings: the fence must still be recognised.
      expect(esc('```\r\n20~25\r\n```\r\n'), '```\r\n20~25\r\n```\r\n');
      expect(esc(r'$x_1~2$'), r'$x_1\~2$');
    });

    testWidgets('renders as a plain tilde, not strikethrough', (tester) async {
      await _renderDone(tester, '20~25 and 30~40');
      expect(_hasStrikethrough(tester), isFalse);
      expect(find.textContaining('20~25 and 30~40'), findsOneWidget);
    });

    testWidgets('double tilde still strikes', (tester) async {
      await _renderDone(tester, 'a ~~gone~~ b');
      expect(_hasStrikethrough(tester), isTrue);
    });
  });

  group('wide content', () {
    const table = '| a | b |\n| --- | --- |\n'
        '| a long cell that keeps going | another long cell here |\n';

    testWidgets('tables scroll sideways by default', (tester) async {
      await _renderDone(tester, table);
      expect(
        find.ancestor(of: find.byType(Table), matching: _horizontalScroll()),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('long cells wrap at tableColumnMaxWidth', (tester) async {
      await _renderDone(tester, table, tableColumnMaxWidth: 120);
      final size = tester.getSize(find.byType(Table));
      // Two columns of at most 120 plus cell padding, well under the
      // single-line width of either cell.
      expect(size.width, lessThan(280));
    });

    testWidgets('tableColumnMaxWidth: null keeps the flex table',
        (tester) async {
      await _renderDone(tester, table, tableColumnMaxWidth: null);
      expect(
        find.ancestor(of: find.byType(Table), matching: _horizontalScroll()),
        findsNothing,
      );
    });

    testWidgets("a style sheet's own column width wins", (tester) async {
      await _renderDone(
        tester,
        table,
        styleSheet: MarkdownStyleSheet(
          tableColumnWidth: const FlexColumnWidth(),
        ),
      );
      expect(
        find.ancestor(of: find.byType(Table), matching: _horizontalScroll()),
        findsNothing,
      );
    });

    testWidgets('display math scrolls sideways, inline math does not',
        (tester) async {
      Widget render(String latex, {required bool displayMode}) =>
          Text('M:$latex');
      await _renderDone(
        tester,
        'inline \$x\$ here\n\n\$\$y\$\$\n',
        latexBuilder: render,
      );
      expect(
        find.ancestor(of: find.text('M:y'), matching: _horizontalScroll()),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.textContaining('M:x'),
          matching: _horizontalScroll(),
        ),
        findsNothing,
      );
    });
  });

  group('AutoScroll and reduce motion', () {
    // A trigger fired while the view is pinned but a little above the bottom
    // follows with an animation; with reduce motion it jumps.
    Future<double> gapAfterTrigger(
      WidgetTester tester, {
      required bool reduceMotion,
    }) async {
      final controller = StickToBottomController();
      final trigger = ValueNotifier<int>(0);
      addTearDown(controller.dispose);
      addTearDown(trigger.dispose);
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 300,
            child: AutoScroll(
              controller: controller,
              trigger: trigger,
              child: Column(
                children: List<Widget>.generate(
                  20,
                  (i) => SizedBox(height: 60, child: Text('item $i')),
                ),
              ),
            ),
          ),
          reduceMotion: reduceMotion,
        ),
      );
      await tester.pumpAndSettle();
      final scroll = controller.scrollController;
      scroll.jumpTo(scroll.position.maxScrollExtent - 20);
      await tester.pump();
      expect(controller.isPinnedToBottom, isTrue);

      trigger.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));
      final gap = scroll.position.maxScrollExtent - scroll.position.pixels;
      await tester.pumpAndSettle();
      return gap;
    }

    testWidgets('animates while motion is allowed', (tester) async {
      expect(
        await gapAfterTrigger(tester, reduceMotion: false),
        allOf(greaterThan(0), lessThan(20)),
      );
    });

    testWidgets('jumps straight to the bottom with reduce motion',
        (tester) async {
      expect(await gapAfterTrigger(tester, reduceMotion: true), 0);
    });
  });
}
