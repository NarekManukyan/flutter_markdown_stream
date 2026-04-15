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
        final out =
            SafeMarkdownParser.sanitize('See the [docs](https://exa');
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
  });
}
