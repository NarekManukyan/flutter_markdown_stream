import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafeMarkdownParser.sanitize', () {
    group('no-ops', () {
      test('empty string returns empty string', () {
        expect(SafeMarkdownParser.sanitize(''), '');
      });

      test('plain text is unchanged', () {
        const s = 'Hello, world. Nothing to fix here.';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('well-formed bold is unchanged', () {
        const s = 'This is **bold** text.';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('well-formed code fence is unchanged', () {
        const s = 'before\n```dart\nfinal x = 1;\n```\nafter';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('well-formed link is unchanged', () {
        const s = 'See [docs](https://example.com) for more.';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('partial bold / italic', () {
      test('closes unclosed bold', () {
        final out = SafeMarkdownParser.sanitize('This is **bold');
        expect(out, endsWith('**'));
      });

      test('closes unclosed italic with *', () {
        final out = SafeMarkdownParser.sanitize('make it *italic');
        expect(out.endsWith('*') && !out.endsWith('**'), isTrue);
      });

      test('closes unclosed italic with _', () {
        final out = SafeMarkdownParser.sanitize('make it _italic');
        expect(out, endsWith('_'));
      });

      test('closes unclosed bold with __', () {
        final out = SafeMarkdownParser.sanitize('__bold__ and __half');
        expect(out, endsWith('__'));
      });

      test('leaves intra-word underscore alone', () {
        const s = 'snake_case_var identifier';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('handles combined partial bold + italic (***text)', () {
        final out = SafeMarkdownParser.sanitize('***loud');
        // 3 asterisks open bold+italic; should close with up to 3.
        expect(out.startsWith('***loud'), isTrue);
        expect(out.endsWith('*'), isTrue);
      });
    });

    group('partial fenced code block', () {
      test('adds closing fence for unclosed ``` block', () {
        final out = SafeMarkdownParser.sanitize('```dart\nfinal x = 1;');
        expect(out, contains('```dart\nfinal x = 1;'));
        expect(out.trim().endsWith('```'), isTrue);
      });

      test('adds closing fence for unclosed ~~~ block', () {
        final out = SafeMarkdownParser.sanitize('~~~\nsome code');
        expect(out.trim().endsWith('~~~'), isTrue);
      });

      test('leaves balanced ``` blocks alone', () {
        const s = '```\nabc\n```';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('emphasis inside unclosed code block is not balanced', () {
        // The **inside** is inside the (eventually-closed) code block, so
        // the sanitizer must NOT add trailing `**` to balance it.
        final out = SafeMarkdownParser.sanitize('```\n**not emphasis');
        expect(out.contains('**not emphasis'), isTrue);
        // Only fence closure is appended, not asterisks.
        expect(out.endsWith('```\n'), isTrue);
      });

      test('partial link before a code block still stripped correctly', () {
        final out = SafeMarkdownParser.sanitize('see [x](ht\n```\ncode');
        expect(out, contains('see '));
        expect(out.trim().endsWith('```'), isTrue);
      });
    });

    group('partial link', () {
      test('strips [label](partial-url', () {
        final out = SafeMarkdownParser.sanitize('See the [docs](https://exa');
        expect(out, 'See the ');
      });

      test('strips ![alt](partial-url', () {
        final out = SafeMarkdownParser.sanitize('before ![img](http');
        expect(out, 'before ');
      });

      test('leaves complete link alone', () {
        const s = 'See [docs](https://x.com).';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('leaves [label without ( alone', () {
        // Just a bracket — will render as literal text, no problem.
        final out = SafeMarkdownParser.sanitize('start of [label');
        expect(out, contains('[label'));
      });
    });

    group('partial autolink', () {
      test('strips <http://... with no closing >', () {
        final out = SafeMarkdownParser.sanitize('visit <https://example.co');
        expect(out, 'visit ');
      });

      test('leaves closed autolinks alone', () {
        const s = 'visit <https://example.com> now';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('partial inline code', () {
      test('closes unclosed inline code on a line', () {
        final out = SafeMarkdownParser.sanitize('run `dart test');
        expect(out.endsWith('`'), isTrue);
      });

      test('leaves balanced inline code alone', () {
        const s = 'run `dart test` now';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('partial header', () {
      test('leaves "## " (empty header) alone - renders fine', () {
        const s = '## ';
        // Parser renders empty h2 — acceptable, no change required.
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('leaves "## Title" alone', () {
        const s = '## Title';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('leaves "###" (no space, no text) alone', () {
        const s = '###';
        // Not a header per CommonMark (needs a space) — renders as text, fine.
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('partial text under setext underline renders fine', () {
        const s = 'Title\n==';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('strikethrough', () {
      test('closes unclosed ~~', () {
        final out = SafeMarkdownParser.sanitize('this is ~~gone');
        expect(out.endsWith('~~'), isTrue);
      });

      test('leaves balanced ~~ alone', () {
        const s = 'this is ~~gone~~';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('line endings', () {
      test('normalises CRLF to LF', () {
        final out = SafeMarkdownParser.sanitize('a\r\nb\r\nc');
        expect(out, 'a\nb\nc');
      });

      test('normalises lone CR to LF', () {
        final out = SafeMarkdownParser.sanitize('a\rb\rc');
        expect(out, 'a\nb\nc');
      });
    });

    group('robustness', () {
      test('never throws on adversarial input', () {
        const inputs = <String>[
          '**',
          '***',
          '```',
          '``',
          '`',
          '[',
          '[]',
          '[](',
          '![](',
          '<',
          '<http',
          '~~',
          '__',
          '___',
          '****abc****',
          '`dart\n```nested',
        ];
        for (final s in inputs) {
          expect(
            () => SafeMarkdownParser.sanitize(s),
            returnsNormally,
            reason: 'input: $s',
          );
        }
      });
    });

    // -------------------------------------------------------------------
    // Regression tests for the flanking-aware emphasis / strikethrough
    // rewrite and the LaTeX currency fix. Each of these previously
    // produced a spurious trailing marker (or, for LaTeX, a spurious
    // trailing `$`) on already-complete text.
    // -------------------------------------------------------------------
    group('flanking-aware emphasis (regression)', () {
      test('spaced asterisk is not emphasis', () {
        const s = 'a * b';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('bullet-list markers are not emphasis', () {
        const s = '* one\n* two\n* three';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('thematic break *** is left alone', () {
        const s = '***';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('arithmetic asterisk is not emphasis', () {
        const s = 'price 2 * 3 = 6';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('genuinely unclosed opener still closes', () {
        final out = SafeMarkdownParser.sanitize('This is **bold');
        expect(out, 'This is **bold**');
      });

      test('nested emphasis pairs still close correctly', () {
        const s = '**bold *and italic* end**';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('flanking-aware strikethrough (regression)', () {
      test('spaced ~~ is not strikethrough', () {
        const s = 'x ~~ y';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('unclosed ~~struck closes', () {
        final out = SafeMarkdownParser.sanitize('~~struck');
        expect(out, '~~struck~~');
      });
    });

    group('LaTeX currency false positive (regression)', () {
      test('currency amount is left alone', () {
        const s = 'costs \$5 today';
        expect(SafeMarkdownParser.sanitize(s, latexEnabled: true), s);
      });

      test('real inline math is still balanced/kept intact', () {
        const s = 'solve \$x+1\$ now';
        expect(SafeMarkdownParser.sanitize(s, latexEnabled: true), s);
      });

      test('genuinely unclosed math still gets a closing \$', () {
        final out = SafeMarkdownParser.sanitize(
          'solve \$x+1',
          latexEnabled: true,
        );
        expect(out, 'solve \$x+1\$');
      });

      test('unbalanced \$\$ block still closes', () {
        final out = SafeMarkdownParser.sanitize(
          '\$\$E=mc^2',
          latexEnabled: true,
        );
        expect(out, '\$\$E=mc^2\$\$');
      });
    });

    group('GFM table repair', () {
      test('hides a partial trailing data row', () {
        final out = SafeMarkdownParser.sanitize('| a | b |\n|---|---|\n| 1 ');
        expect(out, '| a | b |\n|---|---|\n');
      });

      test('hides a half-typed delimiter row', () {
        final out = SafeMarkdownParser.sanitize('| a | b |\n|--');
        expect(out, '| a | b |\n');
      });

      test('hides a partial row after several complete rows', () {
        final out = SafeMarkdownParser.sanitize(
          '| a | b |\n|---|---|\n| 1 | 2 |\n| 3 ',
        );
        expect(out, '| a | b |\n|---|---|\n| 1 | 2 |\n');
      });

      test('a fully completed table (trailing newline) is untouched', () {
        const s = '| a | b |\n|---|---|\n| 1 | 2 |\n';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('a stray pipe with no table context is left alone', () {
        const s = 'Use pipe | here';
        expect(SafeMarkdownParser.sanitize(s), s);
      });

      test('a header row alone with unrelated next line is untouched', () {
        // The next line has letters, not just delimiter chars, so it is
        // not a plausible half-typed delimiter row -> nothing is hidden.
        const s = '| a | b |\n| pipes are neat';
        expect(SafeMarkdownParser.sanitize(s), s);
      });
    });

    group('idempotence / no spurious markers (property test)', () {
      // ~30 hand-written, already-complete Markdown snippets covering
      // bold, italic, lists, tables, code, links, and mixed content.
      // `sanitize` must be a no-op on every one of them, and must never
      // throw for any prefix (simulating a token-by-token stream).
      const corpus = <String>[
        'Hello, world.',
        'This is **bold** text.',
        'This is *italic* text.',
        'This is _italic_ text too.',
        'This is __bold__ text too.',
        'Mix of **bold** and *italic* and ***both***.',
        'A list:\n- one\n- two\n- three\n',
        'A numbered list:\n1. first\n2. second\n3. third\n',
        '* one\n* two\n* three\n',
        'A horizontal rule:\n\n---\n\nAfter the rule.',
        'Another rule style:\n\n***\n\nDone.',
        'Arithmetic: price 2 * 3 = 6 dollars.',
        'Spaced asterisk: a * b should not be emphasis.',
        '`inline code` sample.',
        '```dart\nfinal x = 1;\nprint(x);\n```\n',
        '~~strikethrough~~ text.',
        '[a link](https://example.com) in a sentence.',
        '![alt text](https://example.com/img.png)',
        '<https://example.com> autolink.',
        'snake_case_var and another_var_name here.',
        'A table:\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n',
        'A table without trailing blank:\n'
            '| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |\n',
        'Nested emphasis: **bold *and italic* end**.',
        'A blockquote:\n> quoted text\n> more quoted text\n',
        '## Heading\n\nSome paragraph text below the heading.',
        'Mixed content:\n\n- item one with `code`\n'
            '- item two with **bold**\n'
            '- item three with [link](https://x.com)\n',
        'Combined table and text:\n\n| Col1 | Col2 |\n|:-----|-----:|\n'
            '| a | b |\n\nAfter the table.',
        'A setext heading\n===\n',
        'Multiple paragraphs.\n\n'
            'Second paragraph with *emphasis* and `code`.\n\n'
            'Third paragraph.',
        'Currency amounts like \$5 and \$10 in plain text (no latex).',
      ];

      test('sanitize(complete) == complete for every corpus entry', () {
        for (final s in corpus) {
          expect(SafeMarkdownParser.sanitize(s), s, reason: 'input: $s');
        }
      });

      test('sanitize never throws on any streamed prefix of the corpus', () {
        for (final s in corpus) {
          for (var i = 1; i <= s.length; i++) {
            final prefix = s.substring(0, i);
            expect(
              () => SafeMarkdownParser.sanitize(prefix),
              returnsNormally,
              reason: 'prefix: $prefix',
            );
            expect(
              () => SafeMarkdownParser.sanitize(prefix, latexEnabled: true),
              returnsNormally,
              reason: 'prefix (latex): $prefix',
            );
          }
        }
      });
    });
  });
}
