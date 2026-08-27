import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/src/word_fade.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects the alpha of every leaf text span under [span].
List<double> _alphas(InlineSpan span) {
  final out = <double>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if ((s.text ?? '').trim().isNotEmpty) {
        out.add((s.style?.color?.a ?? 1.0));
      }
      for (final child in s.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(span);
  return out;
}

Future<List<double>> _wordAlphas(
  WidgetTester tester, {
  required String text,
  required bool isDone,
  int fadeWindow = 4,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WordFadeText(
          text: text,
          baseStyle: const TextStyle(color: Color(0xFF000000)),
          isDone: isDone,
          fadeWindow: fadeWindow,
        ),
      ),
    ),
  );
  final rich = tester.widget<RichText>(find.byType(RichText));
  return _alphas(rich.text);
}

void main() {
  group('isSimpleParagraph', () {
    test('true for plain prose', () {
      expect(WordFadeText.isSimpleParagraph('The quick brown fox'), isTrue);
      expect(
        WordFadeText.isSimpleParagraph('has **bold** and *italic* and `code`'),
        isTrue,
      );
    });

    test('false for block structures', () {
      for (final s in <String>[
        '# Heading',
        '> quote',
        '```dart',
        '| a | b |',
        '- item',
        '* item',
        '1. item',
        '---',
      ]) {
        expect(WordFadeText.isSimpleParagraph(s), isFalse, reason: s);
      }
    });
  });

  group('per-word fade grading', () {
    testWidgets('trailing words are dimmer than earlier ones while streaming', (
      tester,
    ) async {
      final alphas = await _wordAlphas(
        tester,
        text: 'one two three four five six seven eight',
        isDone: false,
        fadeWindow: 4,
      );
      // Early words fully opaque.
      expect(alphas.first, closeTo(1.0, 0.001));
      // The very last word is the dimmest, and strictly below 1.
      expect(alphas.last, lessThan(1.0));
      expect(alphas.last, lessThan(alphas[alphas.length - 2]));
    });

    testWidgets('everything is opaque once done', (tester) async {
      final alphas = await _wordAlphas(
        tester,
        text: 'one two three four five six',
        isDone: true,
      );
      for (final a in alphas) {
        expect(a, closeTo(1.0, 0.001));
      }
    });

    testWidgets('inline bold survives the fade renderer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WordFadeText(
              text: 'plain **bold** end',
              baseStyle: TextStyle(color: Color(0xFF000000)),
              isDone: true,
            ),
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText));
      var sawBold = false;
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if ((s.text ?? '').contains('bold') &&
              s.style?.fontWeight == FontWeight.bold) {
            sawBold = true;
          }
          for (final c in s.children ?? const <InlineSpan>[]) {
            walk(c);
          }
        }
      }

      walk(rich.text);
      expect(sawBold, isTrue);
    });
  });
}
