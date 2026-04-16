/// Markdown syntax extensions and an element-builder for rendering LaTeX
/// expressions inside a [MarkdownStream].
///
/// LaTeX *rendering* is intentionally left to the caller — the package
/// itself adds no dependency on any math-rendering library. Supply a
/// [LaTeXBuilder] that wraps your renderer of choice (e.g.
/// `flutter_math_fork`) and [MarkdownStream] will wire it up automatically.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Signature for a widget that renders a single LaTeX expression.
///
/// [latex] is the raw expression between the delimiters (without the
/// surrounding `$` or `$$`). [displayMode] is `true` for block expressions
/// (`$$…$$`) and `false` for inline (`$…$`).
typedef LaTeXBuilder = Widget Function(
  String latex, {
  required bool displayMode,
});

/// The Markdown element tag emitted by [LaTeXInlineSyntax] and
/// [LaTeXBlockSyntax]. [LaTeXElementBuilder] is registered against this tag.
const String kLatexTag = 'latex';

/// Inline LaTeX syntax: `$…$`.
///
/// Matches a single-dollar pair with non-empty content. Rejects
/// double-dollars (those are handled by [LaTeXBlockSyntax]) and standalone
/// single dollars so that prose like "$5" is not mangled. Spaces adjacent
/// to the delimiters are disallowed, per common LaTeX conventions and to
/// reduce false positives on currency.
class LaTeXInlineSyntax extends md.InlineSyntax {
  /// Creates the inline-LaTeX syntax.
  LaTeXInlineSyntax() : super(r'(?<!\$)\$(?!\$)([^\s$][^$\n]*?[^\s$]|[^\s$])\$(?!\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1) ?? '';
    final element = md.Element.text(kLatexTag, content)
      ..attributes['displayMode'] = 'false';
    parser.addNode(element);
    return true;
  }
}

/// Block LaTeX syntax: `$$…$$`.
///
/// Matches a block that starts with `$$` and continues until the matching
/// `$$` — across lines if necessary.
class LaTeXBlockSyntax extends md.BlockSyntax {
  /// Creates the block-LaTeX syntax.
  LaTeXBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) {
    final lines = <md.Line>[];
    // Consume the opening line (already matched by [canParse]).
    final first = parser.current;
    parser.advance();
    // If the opening line already contains a matching `$$`, we're done.
    final firstText = first.content;
    final firstStart = firstText.indexOf(r'$$');
    final firstAfter = firstStart + 2;
    final firstClose = firstText.indexOf(r'$$', firstAfter);
    if (firstClose != -1) {
      lines.add(
        md.Line(firstText.substring(firstAfter, firstClose)),
      );
      return lines;
    }
    // Otherwise, capture the opener's trailing content (if any) and read
    // subsequent lines until a line containing a closing `$$`.
    final opener = firstText.substring(firstAfter);
    if (opener.isNotEmpty) {
      lines.add(md.Line(opener));
    }
    while (!parser.isDone) {
      final line = parser.current.content;
      final close = line.indexOf(r'$$');
      if (close != -1) {
        final before = line.substring(0, close);
        if (before.isNotEmpty) {
          lines.add(md.Line(before));
        }
        parser.advance();
        break;
      }
      lines.add(md.Line(line));
      parser.advance();
    }
    return lines;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = parseChildLines(parser);
    final content = lines.map((l) => l.content).join('\n');
    return md.Element.text(kLatexTag, content)
      ..attributes['displayMode'] = 'true';
  }
}

/// A [MarkdownElementBuilder] that delegates rendering of the [kLatexTag]
/// element to a user-provided [LaTeXBuilder].
class LaTeXElementBuilder extends MarkdownElementBuilder {
  /// Creates a builder that renders LaTeX via [builder].
  LaTeXElementBuilder(this.builder);

  /// The user-provided LaTeX renderer.
  final LaTeXBuilder builder;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final content = element.textContent;
    final displayMode = element.attributes['displayMode'] == 'true';
    return builder(content, displayMode: displayMode);
  }
}
