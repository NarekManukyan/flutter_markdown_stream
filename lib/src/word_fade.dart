/// Per-word fade-in for the currently-streaming text.
///
/// This renders a single run of inline Markdown (the paragraph being typed)
/// as a `Text.rich`, grading the opacity of the most-recently-revealed words
/// so they fade from dim to opaque as more words arrive — the opacity-only,
/// per-word effect used by ChatGPT / Claude. The ramp is **position-based**
/// (no timer): the last [fadeWindow] words are graded by distance from the
/// frontier, so a word brightens naturally as the stream advances past it.
///
/// When [isDone] is `true` everything is fully opaque — so the final, settled
/// text never lingers dim.
///
/// Only inline formatting is handled here (bold, italic, inline code, links);
/// block structure is the caller's responsibility (see how `MarkdownStream`
/// renders settled blocks with a full `MarkdownBody` and reserves this widget
/// for the active paragraph via [isSimpleParagraph]).
library;

import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders inline Markdown [text] with a trailing per-word opacity fade.
class WordFadeText extends StatelessWidget {
  /// Creates a per-word fading text run.
  const WordFadeText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.isDone,
    this.textDirection,
    this.fadeWindow = 4,
    this.minOpacity = 0.15,
  });

  /// The inline Markdown to render (a single paragraph's worth).
  final String text;

  /// The base text style; inline runs derive from it.
  final TextStyle baseStyle;

  /// When `true`, all words are fully opaque (the stream has finished).
  final bool isDone;

  /// Optional text direction forwarded to the underlying rich text.
  final TextDirection? textDirection;

  /// How many trailing words are graded from dim to opaque.
  final int fadeWindow;

  /// Opacity of the newest word (the reveal frontier).
  final double minOpacity;

  /// Whether [text] is a plain paragraph this widget can fade — i.e. it is not
  /// a fenced code block, table, blockquote, heading, list, or horizontal
  /// rule, where inline-only rendering would drop structure. Callers should
  /// fall back to a full Markdown renderer when this is `false`.
  static bool isSimpleParagraph(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return false;
    // Block-level starters we do not render here.
    const blockStarts = <String>['#', '>', '```', '~~~', '|', '---', '***', '___'];
    for (final s in blockStarts) {
      if (trimmed.startsWith(s)) return false;
    }
    // List markers or a fenced block / table pipe on any line.
    for (final line in trimmed.split('\n')) {
      final l = line.trimLeft();
      if (l.startsWith('- ') ||
          l.startsWith('* ') ||
          l.startsWith('+ ') ||
          l.startsWith('```') ||
          l.startsWith('~~~') ||
          l.contains('|') ||
          RegExp(r'^\d+[.)]\s').hasMatch(l)) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Pass 1: flatten inline nodes into styled runs, splitting on whitespace
    // so each non-space run is one "word" we can grade.
    final runs = <_Run>[];
    final nodes = md.Document().parseInline(text);
    _walk(nodes, baseStyle, runs);

    final totalWords = runs.where((r) => r.isWord).length;

    // Resolve the ambient text colour so the fade never falls back to a
    // hardcoded black (which would be invisible-on-dark).
    final Color fallbackColor = baseStyle.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);

    // Pass 2: build spans, grading the last [fadeWindow] words.
    var wordIndex = 0;
    final spans = <InlineSpan>[];
    for (final run in runs) {
      final double opacity;
      if (run.isWord) {
        final distanceFromEnd = totalWords - 1 - wordIndex;
        opacity = _opacityFor(distanceFromEnd);
        wordIndex++;
      } else {
        // Whitespace inherits the following word's frontier state closely
        // enough; keep it opaque to avoid flicker in the gaps.
        opacity = 1;
      }
      final color = run.style.color ?? fallbackColor;
      spans.add(
        TextSpan(
          text: run.text,
          style: run.style.copyWith(color: color.withValues(alpha: opacity)),
        ),
      );
    }

    return Text.rich(TextSpan(children: spans), textDirection: textDirection);
  }

  double _opacityFor(int distanceFromEnd) {
    if (isDone || distanceFromEnd >= fadeWindow) return 1;
    // distanceFromEnd 0 (newest) -> minOpacity, fadeWindow -> 1.
    final t = (distanceFromEnd + 1) / fadeWindow;
    return (minOpacity + (1 - minOpacity) * t).clamp(0.0, 1.0);
  }

  void _walk(List<md.Node> nodes, TextStyle style, List<_Run> out) {
    for (final node in nodes) {
      if (node is md.Text) {
        _emitText(_unescape(node.text), style, out);
      } else if (node is md.Element) {
        final childStyle = _styleForTag(node.tag, style);
        final children = node.children;
        if (children != null && children.isNotEmpty) {
          _walk(children, childStyle, out);
        } else if (node.tag == 'br') {
          out.add(_Run('\n', style, isWord: false));
        }
      }
    }
  }

  TextStyle _styleForTag(String tag, TextStyle style) {
    switch (tag) {
      case 'strong':
        return style.copyWith(fontWeight: FontWeight.bold);
      case 'em':
        return style.copyWith(fontStyle: FontStyle.italic);
      case 'code':
        return style.copyWith(fontFamily: 'monospace');
      case 'a':
        return style.copyWith(decoration: TextDecoration.underline);
      case 'del':
        return style.copyWith(decoration: TextDecoration.lineThrough);
      default:
        return style;
    }
  }

  void _emitText(String text, TextStyle style, List<_Run> out) {
    // Split into alternating non-space (word) and space runs, preserving both.
    for (final match in RegExp(r'\S+|\s+').allMatches(text)) {
      final piece = match.group(0)!;
      final isWord = piece.trimLeft().isNotEmpty;
      out.add(_Run(piece, style, isWord: isWord));
    }
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

class _Run {
  const _Run(this.text, this.style, {required this.isWord});
  final String text;
  final TextStyle style;
  final bool isWord;
}
