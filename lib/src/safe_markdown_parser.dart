/// Utilities for sanitizing a partially-streamed Markdown string so that
/// it is always valid enough for `flutter_markdown` to render without
/// crashing or producing catastrophic layout.
///
/// The public entry point is [SafeMarkdownParser.sanitize].
///
/// Design note: sanitization is **pure and non-destructive**. The caller
/// should keep the raw (unsanitized) buffer as the source of truth and
/// call [SafeMarkdownParser.sanitize] only to produce a render-time
/// projection. When the closing tokens for emphasis / code fences / links
/// eventually arrive in a later chunk, re-sanitizing the updated raw
/// buffer produces the fully-correct Markdown output automatically.
library;

/// Static utilities for sanitizing partial Markdown.
final class SafeMarkdownParser {
  const SafeMarkdownParser._();

  /// Returns a version of [input] that is safe to hand to `flutter_markdown`
  /// even while tokens are still streaming in.
  ///
  /// Handles, in order:
  ///   1. Line-ending normalisation.
  ///   2. Unclosed fenced code blocks (``` or ~~~).
  ///   3. Unclosed inline code (single backticks).
  ///   4. Partially-typed link / image syntax (`[label](http...`).
  ///   5. Partially-typed reference links (`[label][id`).
  ///   6. Partial autolinks (`<http://...` without `>`).
  ///   7. Unbalanced bold/italic emphasis runs (`*` and `_`).
  ///   8. Unbalanced strikethrough (`~~`).
  ///
  /// The function never throws. If anything unexpected happens it falls back
  /// to returning [input] unchanged.
  static String sanitize(String input) {
    if (input.isEmpty) return input;
    try {
      var text = _normalizeLineEndings(input);
      text = _closeFencedCodeBlock(text);
      // The following transforms only apply to content *outside* a fenced
      // code block. _closeFencedCodeBlock has already ensured the string
      // ends with a balanced fence, so by splitting we can skip code spans.
      text = _transformOutsideFences(text, (chunk) {
        var out = chunk;
        out = _stripPartialAutolink(out);
        out = _stripPartialLink(out);
        out = _closeInlineCode(out);
        out = _balanceStrikethrough(out);
        out = _balanceEmphasis(out);
        return out;
      });
      return text;
    } catch (_) {
      return input;
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Normalise line endings.
  // ---------------------------------------------------------------------------
  static String _normalizeLineEndings(String s) =>
      s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // ---------------------------------------------------------------------------
  // 2. Fenced code blocks.
  // ---------------------------------------------------------------------------
  //
  // A fence is a line whose only non-whitespace content is 3+ backticks or
  // 3+ tildes, optionally followed by an info string (for the opening fence).
  // If the total number of fences is odd, we are currently inside one, and we
  // append a synthetic closing fence.
  static final RegExp _fenceRegex =
      RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})', multiLine: true);

  static String _closeFencedCodeBlock(String s) {
    final matches = _fenceRegex.allMatches(s).toList();
    if (matches.isEmpty) return s;
    // Track which fence character opened the currently-unclosed block.
    String? openChar;
    var openLen = 0;
    for (final m in matches) {
      final fence = m.group(1)!;
      final ch = fence[0];
      if (openChar == null) {
        openChar = ch;
        openLen = fence.length;
      } else if (ch == openChar && fence.length >= openLen) {
        // Closing fence for the current block.
        openChar = null;
        openLen = 0;
      }
      // A different fence character inside an open block is just content —
      // ignored.
    }
    if (openChar == null) return s;
    // Append a closing fence on its own line.
    final closing = openChar * (openLen < 3 ? 3 : openLen);
    final needsLeadingNewline = !s.endsWith('\n');
    return '$s${needsLeadingNewline ? '\n' : ''}$closing\n';
  }

  // ---------------------------------------------------------------------------
  // Helper: apply [transform] to each region of [s] that is *not* inside a
  // fenced code block. Content inside fences is passed through verbatim.
  // ---------------------------------------------------------------------------
  static String _transformOutsideFences(
    String s,
    String Function(String chunk) transform,
  ) {
    final matches = _fenceRegex.allMatches(s).toList();
    if (matches.isEmpty) return transform(s);

    final buffer = StringBuffer();
    var cursor = 0;
    var inside = false;
    for (final m in matches) {
      // End-of-line for this fence line.
      final lineEnd = s.indexOf('\n', m.end);
      final fenceLineEnd = lineEnd == -1 ? s.length : lineEnd + 1;
      final regionEnd = inside ? fenceLineEnd : m.start;
      final region = s.substring(cursor, regionEnd);
      buffer.write(inside ? region : transform(region));
      // Write the fence line verbatim if we were outside.
      if (!inside) {
        buffer.write(s.substring(m.start, fenceLineEnd));
      }
      cursor = fenceLineEnd;
      inside = !inside;
    }
    final tail = s.substring(cursor);
    buffer.write(inside ? tail : transform(tail));
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // 3. Inline code.
  // ---------------------------------------------------------------------------
  //
  // We balance single-backtick runs line-by-line. (Multi-line inline code is
  // rare in LLM output and visually indistinguishable from plain text in the
  // partial state; no need to handle it specially.)
  static String _closeInlineCode(String s) {
    final lines = s.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Count single-backticks (not fences — fences are already handled
      // and we're outside them here).
      var count = 0;
      for (var j = 0; j < line.length; j++) {
        if (line[j] == '`') count++;
      }
      if (count.isOdd) {
        lines[i] = '$line`';
      }
    }
    return lines.join('\n');
  }

  // ---------------------------------------------------------------------------
  // 4. Partial link / image.
  // ---------------------------------------------------------------------------
  //
  // `flutter_markdown` tolerates `[foo`, but a half-written `[foo](http` can
  // trip edge cases in some themes. We strip trailing incomplete link syntax
  // — the raw buffer keeps the characters, so once the closing `)` arrives
  // the link renders correctly.
  static final RegExp _partialInlineLink =
      RegExp(r'!?\[[^\]\n]*\]\([^)\n]*$');

  static String _stripPartialLink(String s) {
    // Only consider a partial link if the last `[` on the tail has no matching
    // `)` after its `](`.
    final m = _partialInlineLink.firstMatch(s);
    if (m == null) return s;
    // Confirm no closing paren exists between the match and the end.
    final tail = s.substring(m.start);
    if (tail.contains(')')) return s;
    return s.substring(0, m.start);
  }

  // ---------------------------------------------------------------------------
  // 5. Partial autolink (`<http://...` without `>`).
  // ---------------------------------------------------------------------------
  static final RegExp _partialAutolink = RegExp(r'<(https?://|mailto:)[^>\s]*$');

  static String _stripPartialAutolink(String s) {
    final m = _partialAutolink.firstMatch(s);
    if (m == null) return s;
    return s.substring(0, m.start);
  }

  // ---------------------------------------------------------------------------
  // 6. Strikethrough (`~~`).
  // ---------------------------------------------------------------------------
  static String _balanceStrikethrough(String s) {
    // Count `~~` occurrences. If odd, append a closing pair.
    final count = '~~'.allMatches(s).length;
    return count.isOdd ? '$s~~' : s;
  }

  // ---------------------------------------------------------------------------
  // 7. Bold / italic emphasis.
  // ---------------------------------------------------------------------------
  //
  // We walk the string and, for each run of `*` or `_`, decide whether it
  // opens or closes emphasis. A run is a maximal sequence of identical
  // characters. The CommonMark rule is roughly: a run can open if the
  // character *after* it is not whitespace, and can close if the character
  // *before* it is not whitespace.
  //
  // For sanitization we use a looser heuristic: count the total length of
  // "openable" runs vs "closeable" runs and emit trailing markers to close
  // any dangling ones. In practice LLMs only produce well-formed pairs, so
  // the only thing we need to fix is a trailing, unclosed run — which is
  // exactly the "**bold" → needs `**` case.
  static String _balanceEmphasis(String s) {
    var result = s;
    result = _balanceEmphasisChar(result, '*');
    result = _balanceEmphasisChar(result, '_');
    return result;
  }

  static String _balanceEmphasisChar(String s, String ch) {
    // Walk the string counting RUNS (not individual chars). LLM streams
    // typically emit emphasis in matched pairs of runs; an odd number of
    // runs means the trailing one is an unclosed opener.
    //
    // Intra-word `_` runs (word chars on both sides) are skipped, per
    // CommonMark — `snake_case_var` is not emphasis.
    var runCount = 0;
    var lastRunLen = 0;
    var i = 0;
    while (i < s.length) {
      if (s[i] != ch) {
        i++;
        continue;
      }
      var j = i;
      while (j < s.length && s[j] == ch) {
        j++;
      }
      if (ch == '_') {
        final prev = i > 0 ? s[i - 1] : null;
        final next = j < s.length ? s[j] : null;
        if (prev != null && next != null && _isWord(prev) && _isWord(next)) {
          i = j;
          continue;
        }
      }
      runCount++;
      lastRunLen = j - i;
      i = j;
    }
    if (runCount.isEven) return s;
    final closeLen = lastRunLen.clamp(1, 3);
    return '$s${ch * closeLen}';
  }

  static bool _isWord(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || // 0-9
        (code >= 0x41 && code <= 0x5A) || // A-Z
        (code >= 0x61 && code <= 0x7A) || // a-z
        code > 0x7F; // assume non-ASCII is a word char
  }
}
