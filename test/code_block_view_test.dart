import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_stream/src/code_block_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders code text and language label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBlockView(code: 'print("hi");', language: 'dart'),
        ),
      ),
    );

    expect(find.text('print("hi");'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
  });

  testWidgets('falls back to "code" label when language is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CodeBlockView(code: 'x = 1;')),
      ),
    );

    expect(find.text('code'), findsOneWidget);
  });

  testWidgets('tapping copy writes to the clipboard and shows feedback', (
    tester,
  ) async {
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          log.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBlockView(code: 'const answer = 42;', language: 'dart'),
        ),
      ),
    );

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(
      log,
      contains(
        isA<MethodCall>()
            .having((m) => m.method, 'method', 'Clipboard.setData')
            .having(
              (m) => (m.arguments! as Map<Object?, Object?>)['text'],
              'text',
              'const answer = 42;',
            ),
      ),
    );
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('copy feedback reverts after the configured duration', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBlockView(
            code: 'a',
            copiedFeedbackDuration: Duration(milliseconds: 50),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('copy button exposes a single "Copy" semantics label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBlockView(code: 'a', language: 'dart'),
        ),
      ),
    );

    // Exactly one node is labelled "Copy" — the descendant Tooltip/Text
    // semantics are collapsed so a screen reader does not announce it thrice.
    expect(find.bySemanticsLabel('Copy'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('showCopyButton false hides the copy control', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBlockView(
            code: 'a',
            language: 'dart',
            showCopyButton: false,
          ),
        ),
      ),
    );

    expect(find.text('Copy'), findsNothing);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(find.text('dart'), findsOneWidget);
  });

  testWidgets('showLanguageLabel false hides the language label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBlockView(
            code: 'a',
            language: 'dart',
            showLanguageLabel: false,
          ),
        ),
      ),
    );

    expect(find.text('dart'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets(
    'showCopyButton and showLanguageLabel both false renders no header',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CodeBlockView(
              code: 'a',
              language: 'dart',
              showCopyButton: false,
              showLanguageLabel: false,
            ),
          ),
        ),
      );

      expect(find.text('dart'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('a'), findsOneWidget);
    },
  );

  testWidgets('long unbroken code line does not overflow', (tester) async {
    final longLine = 'x' * 500;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 250,
              height: 200,
              child: CodeBlockView(code: longLine, language: 'text'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('builder() returns a CodeBlockBuilder-shaped function', (
    tester,
  ) async {
    final builder = CodeBlockView.builder(showLanguageLabel: false);
    final Widget built = builder('print(1);', 'dart');

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: built)));

    expect(find.text('print(1);'), findsOneWidget);
    expect(find.text('dart'), findsNothing);
  });

  testWidgets('copy button exposes a tap semantics action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CodeBlockView(code: 'a', language: 'dart')),
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Copy'))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('highlightBuilder renders the supplied spans', (tester) async {
    const highlightColor = Color(0xFFB388FF);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeBlockView(
            code: 'const x = 1;',
            language: 'dart',
            highlightBuilder: (code, language, base) => TextSpan(
              text: code,
              style: base.copyWith(color: highlightColor),
            ),
          ),
        ),
      ),
    );

    // The code body is now a Text.rich carrying the highlighter's colour.
    final riches = tester.widgetList<RichText>(find.byType(RichText));
    var sawColor = false;
    for (final r in riches) {
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.style?.color == highlightColor) sawColor = true;
          for (final c in s.children ?? const <InlineSpan>[]) {
            walk(c);
          }
        }
      }

      walk(r.text);
    }
    expect(sawColor, isTrue);
  });
}
