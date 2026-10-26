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

import 'fence_tracker.dart';

/// Static utilities for sanitizing partial Markdown.
final class SafeMarkdownParser {
  const SafeMarkdownParser._();

  /// Returns a version of [input] that is safe to hand to `flutter_markdown`
  /// even while tokens are still streaming in.
  ///
  /// Handles, in order:
  ///   1. Line-ending normalisation.
  ///   2. Unclosed fenced code blocks (``` or ~~~, at any indentation).
  ///   3. Incomplete trailing GFM table rows — hidden from the projection
  ///      until they finish streaming.
  ///   4. Partial autolinks (`<http://...` without `>`).
  ///   5. Partially-typed links (`[label](http...`) — rendered as their
  ///      label text until the URL completes — and partial images, which
  ///      are hidden.
  ///   6. Unclosed inline code spans (any backtick run length).
  ///   7. Unbalanced LaTeX delimiters (`$$…$$` and `$…$`), when
  ///      [latexEnabled] is `true`.
  ///   8. Unbalanced strikethrough (`~~`).
  ///   9. Unbalanced bold/italic emphasis runs (`*` and `_`).
  ///
  /// Steps 6–9 ignore delimiters inside inline code, backslash escapes, bare
  /// URLs and link destinations, and only consider the block still being
  /// written — an opener in an earlier, finished paragraph can never be
  /// closed by later text, so it is left as the literal character it is.
  /// Synthetic closers are appended innermost-first so nested spans close in
  /// the right order.
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
      final text = _normalizeLineEndings(input);

      // Locate the prose that follows the last *closed* fenced code block —
      // only that tail can still be mid-typing. If the text ends inside an
      // open fence, closing the fence is the only repair needed: everything
      // before the fence is already finished.
      final fences = FenceTracker();
      var tailStart = 0;
      var offset = 0;
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final wasOpen = fences.isOpen;
        final isFence = fences.addLine(lines[i]);
        offset += lines[i].length + (i == lines.length - 1 ? 0 : 1);
        if (isFence && wasOpen) tailStart = offset;
      }
      if (fences.isOpen) {
        final len = fences.openLength < 3 ? 3 : fences.openLength;
        final closing = fences.openChar! * len;
        final needsNewline = !text.endsWith('\n');
        return '$text${needsNewline ? '\n' : ''}'
            '${fences.openIndent}$closing\n';
      }

      final head = text.substring(0, tailStart);
      final tail = text.substring(tailStart);
      return '$head${_repairTail(tail, latexEnabled: latexEnabled)}';
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
  // Repairs for the trailing prose region (outside any fenced code block).
  // ---------------------------------------------------------------------------
  static String _repairTail(String s, {required bool latexEnabled}) {
    if (s.isEmpty) return s;
    var out = s;
    out = _hidePartialTableRow(out);
    out = _stripPartialAutolink(out);
    out = _repairPartialLink(out);
    out = _stripPartialImageLabel(out);
    return '$out${_closers(out, latexEnabled: latexEnabled)}';
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
  // A half-written `[label](http` is rendered as just its label, so the
  // reader sees the words straight away instead of a gap that pops in when
  // the URL finishes. A half-written image has nothing useful to show yet,
  // so it is hidden. The raw buffer keeps every character, so once the
  // closing `)` arrives the link or image renders correctly.
  static final RegExp _partialInlineLink = RegExp(
    r'(!?)\[([^\]\n]*)\]\([^)\n]*$',
  );

  static String _repairPartialLink(String s) {
    final m = _partialInlineLink.firstMatch(s);
    if (m == null) return s;
    final isImage = m.group(1)!.isNotEmpty;
    final label = isImage ? '' : m.group(2)!;
    return '${s.substring(0, m.start)}$label';
  }

  // `![alt` with no closing bracket yet — an image is on its way.
  static final RegExp _partialImageLabel = RegExp(r'!\[[^\]\n]*$');

  static String _stripPartialImageLabel(String s) {
    final m = _partialImageLabel.firstMatch(s);
    if (m == null) return s;
    return s.substring(0, m.start);
  }

  // ---------------------------------------------------------------------------
  // 6–9. Inline delimiters.
  // ---------------------------------------------------------------------------
  //
  // The scan works on a *masked* copy of the text, the same length as the
  // original, in which every character that cannot act as a delimiter —
  // inside a code span, a backslash escape, a bare URL, a link destination
  // or (when enabled) a math span — is replaced by [_mask]. The mask
  // character is neither whitespace nor a word character, so it does not
  // change the flanking decisions of the delimiters around it.
  static const String _mask = '\u0001';

  static String _closers(String s, {required bool latexEnabled}) {
    final masked = s.split('');
    final pending = <_Closer>[];

    _maskCodeEscapesAndUrls(s, masked, pending);
    if (latexEnabled) _balanceLatex(masked, pending);

    final scan = masked.join();
    final scopeStart = _inlineScopeStart(scan);
    _balanceStrikethrough(scan, scopeStart, pending);
    _balanceEmphasisChar(scan, '*', scopeStart, pending);
    _balanceEmphasisChar(scan, '_', scopeStart, pending);

    if (pending.isEmpty) return '';
    // Innermost (latest-opened) span closes first.
    pending.sort((a, b) => b.position.compareTo(a.position));
    return pending.map((c) => c.text).join();
  }

  static final RegExp _paragraphBreak = RegExp(r'\n[ \t]*\n');

  // A line that begins a new block whose inline content cannot continue an
  // emphasis span from the line above: a list item, a heading or a table
  // row.
  static final RegExp _blockStartLine = RegExp(
    r'^[ \t]*([-+*][ \t]|\d{1,9}[.)][ \t]|#{1,6}([ \t]|$)|\|)',
  );
  static final RegExp _headingLine = RegExp(r'^[ \t]{0,3}#{1,6}([ \t]|$)');

  /// Returns the offset where the block still being written begins. Inline
  /// delimiters cannot span block boundaries, so only openers at or after
  /// this offset can still be closed by text that has yet to arrive.
  static int _inlineScopeStart(String s) {
    var start = 0;
    for (final m in _paragraphBreak.allMatches(s)) {
      start = m.end;
    }
    var lineStart = start;
    var previousWasHeading = false;
    while (lineStart <= s.length) {
      var lineEnd = s.indexOf('\n', lineStart);
      if (lineEnd == -1) lineEnd = s.length;
      final line = s.substring(lineStart, lineEnd);
      if (previousWasHeading || _blockStartLine.hasMatch(line)) {
        start = lineStart;
      }
      previousWasHeading = _headingLine.hasMatch(line);
      if (lineEnd == s.length) break;
      lineStart = lineEnd + 1;
    }
    return start;
  }

  static final RegExp _urlStart = RegExp(r'(https?://|www\.)');
  static const String _urlTrailingPunctuation = '?!.,:;*_~\'"';

  static void _maskRange(List<String> masked, int start, int end) {
    for (var k = start; k < end && k < masked.length; k++) {
      masked[k] = _mask;
    }
  }

  /// Masks code spans, escapes, bare URLs, autolinks and link destinations,
  /// and records a closer for a code span still open at the end of [s].
  static void _maskCodeEscapesAndUrls(
    String s,
    List<String> masked,
    List<_Closer> pending,
  ) {
    final breaks = _paragraphBreak.allMatches(s).map((m) => m.start).toList();
    int nextBreakAfter(int i) {
      for (final b in breaks) {
        if (b >= i) return b;
      }
      return s.length;
    }

    var i = 0;
    while (i < s.length) {
      final c = s[i];

      // Backslash escape of ASCII punctuation.
      if (c == r'\' && i + 1 < s.length && _isAsciiPunctuation(s[i + 1])) {
        _maskRange(masked, i, i + 2);
        i += 2;
        continue;
      }

      // Code span: a backtick run closed by the next run of the same
      // length within the same paragraph.
      if (c == '`') {
        var j = i;
        while (j < s.length && s[j] == '`') {
          j++;
        }
        final len = j - i;
        final limit = nextBreakAfter(j);
        var k = j;
        var closeAt = -1;
        while (k < limit) {
          if (s[k] != '`') {
            k++;
            continue;
          }
          var r = k;
          while (r < s.length && s[r] == '`') {
            r++;
          }
          if (r - k == len) {
            closeAt = k;
            break;
          }
          k = r;
        }
        if (closeAt != -1) {
          _maskRange(masked, i, closeAt + len);
          i = closeAt + len;
          continue;
        }
        // Unmatched run. It is a still-open code span if it sits in the
        // final paragraph — unless it is alone at the start of the last
        // line, where it is more likely the first characters of a fence.
        if (limit == s.length && !_isBareRunAtLineStart(s, i, j)) {
          pending.add(_Closer(i, '`' * len));
          _maskRange(masked, i, s.length);
          return;
        }
        i = j;
        continue;
      }

      // Complete autolink `<scheme:...>`.
      if (c == '<') {
        final close = s.indexOf('>', i);
        if (close != -1) {
          final inner = s.substring(i + 1, close);
          if (inner.contains(':') && !inner.contains(RegExp(r'\s'))) {
            _maskRange(masked, i, close + 1);
            i = close + 1;
            continue;
          }
        }
      }

      // Link destination `](...)`.
      if (c == ']' && i + 1 < s.length && s[i + 1] == '(') {
        final close = s.indexOf(')', i + 2);
        final lineEnd = s.indexOf('\n', i);
        if (close != -1 && (lineEnd == -1 || close < lineEnd)) {
          _maskRange(masked, i + 2, close);
          i = close + 1;
          continue;
        }
      }

      // Bare URL (GFM autolink extension). Trailing punctuation is not part
      // of the URL, so an emphasis closer right after it still counts.
      if ((c == 'h' || c == 'w') &&
          (i == 0 || !_isWord(s[i - 1])) &&
          s.startsWith(_urlStart, i)) {
        var end = i;
        while (end < s.length && !_isWhitespace(s[end]) && s[end] != '<') {
          end++;
        }
        while (end > i && _urlTrailingPunctuation.contains(s[end - 1])) {
          end--;
        }
        _maskRange(masked, i, end);
        i = end > i ? end : i + 1;
        continue;
      }

      i++;
    }
  }

  static bool _isBareRunAtLineStart(String s, int runStart, int runEnd) {
    if (runEnd != s.length) return false;
    final lineStart = runStart == 0 ? 0 : s.lastIndexOf('\n', runStart - 1) + 1;
    return s.substring(lineStart, runStart).trim().isEmpty;
  }

  // ---------------------------------------------------------------------------
  // 7. LaTeX delimiters (`$$…$$` and `$…$`).
  // ---------------------------------------------------------------------------
  //
  // Only invoked when the caller has opted into LaTeX parsing (a LaTeX
  // syntax extension is installed). `$$` toggles display math, which may
  // span lines. Outside display math, a `$` may only *open* inline math when
  // the following character is non-whitespace and not an ASCII digit — this
  // keeps "$x+1$" math intact while leaving a currency amount like "$5"
  // alone. Inline math cannot span lines, so an opener abandoned at a line
  // break stays literal. Matched math spans are masked so the emphasis scan
  // ignores `*` and `_` inside formulas.
  static void _balanceLatex(List<String> masked, List<_Closer> pending) {
    var blockOpen = -1;
    var inlineOpen = -1;
    var i = 0;
    while (i < masked.length) {
      final c = masked[i];
      if (c == r'$' && i + 1 < masked.length && masked[i + 1] == r'$') {
        if (blockOpen == -1) {
          blockOpen = i;
          inlineOpen = -1;
        } else {
          _maskRange(masked, blockOpen, i + 2);
          blockOpen = -1;
        }
        i += 2;
        continue;
      }
      if (blockOpen != -1) {
        i++;
        continue;
      }
      if (c == '\n') {
        inlineOpen = -1;
      } else if (c == r'$') {
        if (inlineOpen != -1) {
          _maskRange(masked, inlineOpen, i + 1);
          inlineOpen = -1;
        } else {
          final next = i + 1 < masked.length ? masked[i + 1] : null;
          if (next != null && !_isWhitespace(next) && !_isDigit(next)) {
            inlineOpen = i;
          }
        }
      }
      i++;
    }
    if (blockOpen != -1) {
      pending.add(_Closer(blockOpen, r'$$'));
      _maskRange(masked, blockOpen, masked.length);
    } else if (inlineOpen != -1) {
      pending.add(_Closer(inlineOpen, r'$'));
      _maskRange(masked, inlineOpen, masked.length);
    }
  }

  // ---------------------------------------------------------------------------
  // 8. Strikethrough (`~~`).
  // ---------------------------------------------------------------------------
  //
  // Flanking-aware, mirroring the emphasis balancer below: `~~` may only
  // *open* when followed by non-whitespace, and may only *close* when
  // preceded by non-whitespace. A spaced "x ~~ y" is left untouched, while
  // "~~struck" gets a synthetic closer.
  static void _balanceStrikethrough(
    String s,
    int scopeStart,
    List<_Closer> pending,
  ) {
    final openers = <int>[];
    var i = scopeStart;
    while (true) {
      final idx = s.indexOf('~~', i);
      if (idx == -1) break;
      final prev = idx > 0 ? s[idx - 1] : null;
      final nextIdx = idx + 2;
      final next = nextIdx < s.length ? s[nextIdx] : null;
      final canOpen = next != null && !_isWhitespace(next);
      final canClose = prev != null && !_isWhitespace(prev);
      if (canClose && openers.isNotEmpty) {
        openers.removeLast();
      } else if (canOpen) {
        openers.add(idx);
      }
      i = idx + 2;
    }
    for (final pos in openers) {
      pending.add(_Closer(pos, '~~'));
    }
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
  // dangling openers get a synthetic closer.
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

  static void _balanceEmphasisChar(
    String s,
    String ch,
    int scopeStart,
    List<_Closer> pending,
  ) {
    final stack = <(int, int)>[];
    var i = scopeStart;
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
        stack.add((i, j - i));
      }
      i = j;
    }
    for (final (pos, len) in stack) {
      pending.add(_Closer(pos, ch * len.clamp(1, 3)));
    }
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

  static bool _isAsciiPunctuation(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x21 && code <= 0x2F) ||
        (code >= 0x3A && code <= 0x40) ||
        (code >= 0x5B && code <= 0x60) ||
        (code >= 0x7B && code <= 0x7E);
  }
}

/// A synthetic closing delimiter for an opener at [position].
final class _Closer {
  const _Closer(this.position, this.text);

  final int position;
  final String text;
}
