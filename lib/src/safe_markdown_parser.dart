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
  ///   3. Incomplete trailing GFM table rows — hidden from the projection
  ///      until they finish streaming.
  ///   4. Partial autolinks (`<http://...` without `>`).
  ///   5. Partially-typed link / image syntax (`[label](http...`).
  ///   6. Unclosed inline code (single backticks).
  ///   7. Unbalanced LaTeX delimiters (`$$…$$` and `$…$`), when
  ///      [latexEnabled] is `true`.
  ///   8. Unbalanced strikethrough (`~~`).
  ///   9. Unbalanced bold/italic emphasis runs (`*` and `_`).
  ///
  /// The function never throws. If anything unexpected happens it falls back
  /// to returning [input] unchanged.
  ///
  /// Set [latexEnabled] to `true` only when the rendered Markdown is being
  /// parsed with LaTeX syntax extensions installed — otherwise a trailing
  /// "$5" (dollars, not math) would be wrongly paired with a synthetic
  /// closing `$`.
  static String sanitize(String input, {bool latexEnabled = false}) {
    if (input.isEmpty) return input;
    try {
      var text = _normalizeLineEndings(input);
      text = _closeFencedCodeBlock(text);
      // The following transforms only apply to content *outside* a fenced
      // code block. _closeFencedCodeBlock has already ensured the string
      // ends with a balanced fence, so by splitting we can skip code spans.
      text = _transformOutsideFences(text, (chunk) {
        var out = chunk;
        out = _hidePartialTableRow(out);
        out = _stripPartialAutolink(out);
        out = _stripPartialLink(out);
        out = _closeInlineCode(out);
        if (latexEnabled) {
          out = _balanceLatexDelimiters(out);
        }
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
  static final RegExp _fenceRegex = RegExp(
    r'^[ \t]{0,3}(`{3,}|~{3,})',
    multiLine: true,
  );

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
  // 3. GFM tables: hide an incomplete trailing row from the projection.
  // ---------------------------------------------------------------------------
  //
  // Tables are the single most common construct that renders badly when
  // caught mid-stream: a data row that hasn't finished typing (or a
  // delimiter row that's only half-typed) trips up `flutter_markdown`'s
  // table layout. Rather than trying to repair a half-typed row we simply
  // hide it from the *projection* — the raw buffer keeps every character,
  // so once the row completes on a later chunk it renders in full.
  //
  // We only ever act on a genuinely dangling *final* line: one with no
  // trailing newline (still being typed) that contains a `|` and sits
  // directly below a valid table start (a header row, then a delimiter
  // row made only of `|`, `-`, `:` and spaces). A completed row (one that
  // ends in `\n`) is never touched.
  static final RegExp _pipeRow = RegExp(r'^[ \t]{0,3}\|.*\|[ \t]*$');
  static final RegExp _delimiterRowChars = RegExp(r'^[ \t|:-]*$');

  static bool _looksLikeTableRow(String line) => _pipeRow.hasMatch(line);

  static bool _looksLikeDelimiterRow(String line) =>
      _delimiterRowChars.hasMatch(line) &&
      line.contains('-') &&
      line.contains('|');

  static String _hidePartialTableRow(String chunk) {
    if (chunk.isEmpty || chunk.endsWith('\n')) return chunk;
    final lastNewline = chunk.lastIndexOf('\n');
    if (lastNewline == -1) return chunk;
    final tail = chunk.substring(lastNewline + 1);
    if (!tail.contains('|')) return chunk;

    final head = chunk.substring(0, lastNewline + 1);
    final priorLines = head.substring(0, head.length - 1).split('\n');
    if (priorLines.isEmpty) return chunk;

    final lastPrior = priorLines.last;
    if (!_looksLikeTableRow(lastPrior)) return chunk;

    // Walk backward through the contiguous block of complete pipe rows
    // directly above the dangling tail.
    var start = priorLines.length - 1;
    while (start > 0 && _looksLikeTableRow(priorLines[start - 1])) {
      start--;
    }

    // Case 1: header + delimiter (+ optionally more rows) already present
    // -> the partial trailing row (data or otherwise) is hidden.
    if (priorLines.length - start >= 2 &&
        _looksLikeDelimiterRow(priorLines[start + 1])) {
      return head;
    }

    // Case 2: only the header row has landed so far, and the tail looks
    // like the start of a delimiter row (e.g. "|--") -> hide it too, since
    // rendering the header alone as a table would be worse than as plain
    // text for the split second before the delimiter row completes.
    if (start == priorLines.length - 1 && _delimiterRowChars.hasMatch(tail)) {
      return head;
    }

    return chunk;
  }

  // ---------------------------------------------------------------------------
  // 4. Partial autolink (`<http://...` without `>`).
  // ---------------------------------------------------------------------------
  static final RegExp _partialAutolink = RegExp(
    r'<(https?://|mailto:)[^>\s]*$',
  );

  static String _stripPartialAutolink(String s) {
    final m = _partialAutolink.firstMatch(s);
    if (m == null) return s;
    return s.substring(0, m.start);
  }

  // ---------------------------------------------------------------------------
  // 5. Partial link / image.
  // ---------------------------------------------------------------------------
  //
  // `flutter_markdown` tolerates `[foo`, but a half-written `[foo](http` can
  // trip edge cases in some themes. We strip trailing incomplete link syntax
  // — the raw buffer keeps the characters, so once the closing `)` arrives
  // the link renders correctly.
  static final RegExp _partialInlineLink = RegExp(r'!?\[[^\]\n]*\]\([^)\n]*$');

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
  // 6. Inline code.
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
  // 7. LaTeX delimiters (`$$…$$` and `$…$`).
  // ---------------------------------------------------------------------------
  //
  // Only invoked when the caller has opted into LaTeX parsing (a LaTeX
  // syntax extension is installed). Balances unclosed `$$` blocks first
  // (counted as pairs, two-by-two), then walks the string tracking whether
  // an unclosed inline `$…$` span is open. A `$` may only *open* inline math
  // when the following character is non-whitespace and not an ASCII digit
  // — this keeps "$x+1$" math intact while leaving a currency amount like
  // "$5" alone. Once a span is open, the next standalone `$` always closes
  // it.
  static String _balanceLatexDelimiters(String s) {
    var out = s;
    // Count `$$` occurrences. Odd → unclosed block; append a closing `$$`.
    final blockCount = r'$$'.allMatches(out).length;
    if (blockCount.isOdd) {
      out = '$out\$\$';
    }

    var openInline = false;
    var i = 0;
    while (i < out.length) {
      if (out[i] != '\$') {
        i++;
        continue;
      }
      if (i + 1 < out.length && out[i + 1] == '\$') {
        // Part of a `$$` token, not a standalone inline delimiter.
        i += 2;
        continue;
      }
      if (openInline) {
        // Any standalone `$` while a span is open closes it.
        openInline = false;
      } else {
        final next = i + 1 < out.length ? out[i + 1] : null;
        if (next != null && !_isWhitespace(next) && !_isDigit(next)) {
          openInline = true;
        }
      }
      i++;
    }
    if (openInline) {
      out = '$out\$';
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 8. Strikethrough (`~~`).
  // ---------------------------------------------------------------------------
  //
  // Flanking-aware, mirroring the emphasis balancer below: `~~` may only
  // *open* when followed by non-whitespace, and may only *close* when
  // preceded by non-whitespace. A spaced "x ~~ y" is left untouched, while
  // "~~struck" gets a synthetic closer.
  static String _balanceStrikethrough(String s) {
    var openCount = 0;
    var i = 0;
    while (true) {
      final idx = s.indexOf('~~', i);
      if (idx == -1) break;
      final prev = idx > 0 ? s[idx - 1] : null;
      final nextIdx = idx + 2;
      final next = nextIdx < s.length ? s[nextIdx] : null;
      final canOpen = next != null && !_isWhitespace(next);
      final canClose = prev != null && !_isWhitespace(prev);
      if (canClose && openCount > 0) {
        openCount--;
      } else if (canOpen) {
        openCount++;
      }
      i = idx + 2;
    }
    return openCount > 0 ? '$s~~' : s;
  }

  // ---------------------------------------------------------------------------
  // 9. Bold / italic emphasis.
  // ---------------------------------------------------------------------------
  //
  // We walk the string and, for each run of `*` or `_`, decide whether it
  // opens or closes emphasis, using a simplified version of CommonMark's
  // flanking rules: a run may *open* only when the character immediately
  // after it is non-whitespace (left-flanking), and may *close* only when
  // the character immediately before it is non-whitespace (right-flanking).
  // This keeps things like `"a * b"` (spaced asterisk), `"* one"` (a bullet
  // marker) and `"price 2 * 3 = 6"` (arithmetic) from being mistaken for
  // emphasis.
  //
  // Qualifying runs are tracked with a stack so that nested pairs
  // (`"**bold *and* text**"`) close in the right order, and only genuinely
  // dangling openers get a synthetic closer appended at the end.
  static String _balanceEmphasis(String s) {
    var result = s;
    result = _balanceEmphasisChar(result, '*');
    result = _balanceEmphasisChar(result, '_');
    return result;
  }

  static final RegExp _thematicBreakLine = RegExp(
    r'^[ ]{0,3}([*_])(\s*\1){2,}\s*$',
  );

  // Returns true when the run [runStart, runEnd) is the entire non-space
  // content of a thematic-break line (e.g. "***", "* * *"), in which case
  // it must not be treated as an emphasis opener/closer at all.
  static bool _isThematicBreakRun(String s, int runStart, int runEnd) {
    var lineStart = s.lastIndexOf('\n', runStart);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;
    var lineEnd = s.indexOf('\n', runEnd);
    lineEnd = lineEnd == -1 ? s.length : lineEnd;
    return _thematicBreakLine.hasMatch(s.substring(lineStart, lineEnd));
  }

  static String _balanceEmphasisChar(String s, String ch) {
    final stack = <int>[];
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
      final prev = i > 0 ? s[i - 1] : null;
      final next = j < s.length ? s[j] : null;

      // Intra-word `_` runs (word chars on both sides) are skipped, per
      // CommonMark — `snake_case_var` is not emphasis. This applies to
      // both potential opening and closing.
      if (ch == '_' &&
          prev != null &&
          next != null &&
          _isWord(prev) &&
          _isWord(next)) {
        i = j;
        continue;
      }

      // A run that is the entire content of a thematic-break line (e.g.
      // "***" on its own line) is structural, not emphasis.
      if (_isThematicBreakRun(s, i, j)) {
        i = j;
        continue;
      }

      final canOpen = next != null && !_isWhitespace(next);
      final canClose = prev != null && !_isWhitespace(prev);
      if (canClose && stack.isNotEmpty) {
        stack.removeLast();
      } else if (canOpen) {
        stack.add(j - i);
      }
      i = j;
    }
    if (stack.isEmpty) return s;
    final buffer = StringBuffer(s);
    for (final len in stack.reversed) {
      buffer.write(ch * len.clamp(1, 3));
    }
    return buffer.toString();
  }

  static bool _isWord(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || // 0-9
        (code >= 0x41 && code <= 0x5A) || // A-Z
        (code >= 0x61 && code <= 0x7A) || // a-z
        code > 0x7F; // assume non-ASCII is a word char
  }

  static bool _isWhitespace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
