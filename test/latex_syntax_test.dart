import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

Widget _render(
  String latex, {
  required bool displayMode,
}) =>
    Text(
      'LATEX[${displayMode ? "block" : "inline"}]:$latex',
      key: const Key('latex-render'),
    );

void main() {
  group('LaTeXInlineSyntax', () {
    test('parses inline dollar-delimited expression', () {
      final doc = md.Document(
        inlineSyntaxes: <md.InlineSyntax>[LaTeXInlineSyntax()],
      );
      final out = doc.parseInline(r'mass $E = mc^2$ here');
      final latex = out.whereType<md.Element>().firstWhere(
            (e) => e.tag == kLatexTag,
          );
      expect(latex.textContent, 'E = mc^2');
      expect(latex.attributes['displayMode'], 'false');
    });

    test('does not match bare dollars (e.g. prices)', () {
      final doc = md.Document(
        inlineSyntaxes: <md.InlineSyntax>[LaTeXInlineSyntax()],
      );
      final out = doc.parseInline(r'it costs $5 and $10');
      final latexes = out
          .whereType<md.Element>()
          .where((e) => e.tag == kLatexTag)
          .toList();
      expect(latexes, isEmpty);
    });
  });

  group('LaTeXBlockSyntax', () {
    test('parses block double-dollar expression across lines', () {
      final doc = md.Document(
        blockSyntaxes: <md.BlockSyntax>[LaTeXBlockSyntax()],
      );
      final out = doc.parseLines(<String>[
        r'$$',
        r'\int_0^1 x dx = \frac{1}{2}',
        r'$$',
      ]);
      final root = out.whereType<md.Element>().firstWhere(
            (e) => e.tag == kLatexTag,
          );
      expect(root.textContent.trim(), r'\int_0^1 x dx = \frac{1}{2}');
      expect(root.attributes['displayMode'], 'true');
    });

    test('parses single-line block expression', () {
      final doc = md.Document(
        blockSyntaxes: <md.BlockSyntax>[LaTeXBlockSyntax()],
      );
      final out = doc.parseLines(<String>[r'$$E=mc^2$$']);
      final root = out.whereType<md.Element>().firstWhere(
            (e) => e.tag == kLatexTag,
          );
      expect(root.textContent, 'E=mc^2');
      expect(root.attributes['displayMode'], 'true');
    });
  });

  group('SafeMarkdownParser LaTeX delimiter balancing', () {
    test('closes unclosed inline dollar', () {
      expect(
        SafeMarkdownParser.sanitize(
          r'the formula $E = mc^2',
          latexEnabled: true,
        ),
        r'the formula $E = mc^2$',
      );
    });

    test('closes unclosed block double-dollar', () {
      const input = r'ahead $$x=1';
      final out = SafeMarkdownParser.sanitize(input, latexEnabled: true);
      expect(out, endsWith(r'$$'));
    });

    test('leaves balanced dollars alone', () {
      const input = r'$a$ and $b$';
      expect(
        SafeMarkdownParser.sanitize(input, latexEnabled: true),
        input,
      );
    });

    test('latexEnabled false leaves dollars alone (no corruption of price)',
        () {
      const input = r'you owe $5';
      expect(SafeMarkdownParser.sanitize(input), input);
    });
  });

  group('LaTeXElementBuilder integration via MarkdownStream', () {
    testWidgets('latexBuilder is invoked for inline expression',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() async => controller.close());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownStream(
              stream: controller.stream,
              latexBuilder: _render,
              rebuildDebounce: Duration.zero,
            ),
          ),
        ),
      );

      controller.add(r'energy: $E=mc^2$ done');
      await controller.close();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const Key('latex-render')), findsOneWidget);
      expect(find.textContaining('LATEX[inline]:E=mc^2'), findsOneWidget);
    });

    testWidgets('latexBuilder receives displayMode: true for block',
        (tester) async {
      final controller = StreamController<String>();
      addTearDown(() async => controller.close());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownStream(
              stream: controller.stream,
              latexBuilder: _render,
              rebuildDebounce: Duration.zero,
            ),
          ),
        ),
      );

      controller.add('before\n\n\$\$x^2\$\$\n\nafter');
      await controller.close();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.textContaining('LATEX[block]:x^2'), findsOneWidget);
    });
  });
}
