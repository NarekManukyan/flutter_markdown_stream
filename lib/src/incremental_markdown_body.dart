/// An incremental wrapper around `MarkdownBody` that avoids re-parsing
/// already-settled content on every streaming frame.
///
/// While Markdown streams in, the naive approach re-parses the *entire*
/// accumulated buffer on every rebuild — O(total length) per frame, which is
/// O(n²) over the life of a long response. [IncrementalMarkdownBody] splits the
/// text at the last **top-level blank-line boundary** into a *stable* prefix
/// (blocks that will not change any more this stream) and an *active* tail (the
/// block still being written). The stable prefix is rendered by a memoized
/// `MarkdownBody` that is only rebuilt when the settled text actually changes,
/// so per-frame parse cost drops to O(active block length).
///
/// Splitting only ever happens at a blank line that is **not** inside a fenced
/// code block, so a stable prefix is always self-contained, balanced Markdown
/// and renders identically to the equivalent single `MarkdownBody`. When there
/// is no safe boundary yet (e.g. the whole response is one paragraph), the
/// entire text is treated as the active tail and behaviour is identical to a
/// plain `MarkdownBody`.
///
/// This is an opt-in optimization (`MarkdownStream(incrementalParsing: true)`);
/// the default rendering path is unchanged.
library;

import 'package:flutter/widgets.dart';

/// Builds a `MarkdownBody` for a slice of the streamed text. The wrapper calls
/// this for the stable prefix and the active tail with identical styling, so
/// callers can forward every `MarkdownBody` parameter in one place.
typedef MarkdownSliceBuilder = Widget Function(String data);

/// Splits streamed Markdown into a memoized stable prefix and a live tail.
///
/// See the library doc comment for the rationale.
class IncrementalMarkdownBody extends StatefulWidget {
  /// Creates an incremental Markdown renderer.
  ///
  /// [data] is the full (already-sanitized) Markdown to render. [sliceBuilder]
  /// must build a `MarkdownBody` (or equivalent) for a given substring using
  /// the caller's styling; it is invoked for the stable prefix and the active
  /// tail separately.
  const IncrementalMarkdownBody({
    super.key,
    required this.data,
    required this.sliceBuilder,
    this.tailBuilder,
  });

  /// The full sanitized Markdown to render.
  final String data;

  /// Builds a Markdown widget for a slice of [data] (used for the settled
  /// prefix, and for the active tail when [tailBuilder] is null).
  final MarkdownSliceBuilder sliceBuilder;

  /// Optional builder for the *active tail* only. When supplied, the still-
  /// streaming block is built with this instead of [sliceBuilder] — e.g. to
  /// apply a per-word fade to the paragraph currently being typed.
  final MarkdownSliceBuilder? tailBuilder;

  /// Returns the index at which [data] can be safely split into a stable
  /// prefix `[0, index)` and an active tail `[index, end)`.
  ///
  /// The split point is the start of the line following the **last** blank
  /// line that sits at top level (outside any fenced code block). Returns `0`
  /// when there is no safe boundary, meaning the whole string is active.
  ///
  /// Exposed for testing.
  static int stableSplitIndex(String data) {
    if (data.isEmpty) return 0;
    // Track fenced-code state line by line; only blank lines encountered while
    // *outside* a fence are valid split boundaries.
    var insideFence = false;
    String? fenceChar;
    var fenceLen = 0;
    var offset = 0;
    var lastBoundary = 0;
    // A boundary is the offset just after a blank line, i.e. the start of the
    // next block. We record the offset of the character following the newline
    // that terminates a blank line.
    var previousLineWasBlank = false;

    final lines = data.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLast = i == lines.length - 1;
      // Newline terminates every line except possibly the last (if `data`
      // does not end with '\n').
      final lineWithNewlineLen = line.length + (isLast ? 0 : 1);

      final trimmed = line.trimLeft();
      final isFenceLine = _isFenceLine(trimmed);
      if (isFenceLine) {
        final ch = trimmed[0];
        final len = _leadingRunLength(trimmed, ch);
        if (!insideFence) {
          insideFence = true;
          fenceChar = ch;
          fenceLen = len;
        } else if (ch == fenceChar && len >= fenceLen) {
          insideFence = false;
          fenceChar = null;
          fenceLen = 0;
        }
      }

      final isBlank = line.trim().isEmpty;
      // Record a boundary at the start of THIS line when the PREVIOUS line was
      // a top-level blank line — i.e. this line begins a fresh top-level block.
      if (previousLineWasBlank && !insideFence) {
        lastBoundary = offset;
      }
      previousLineWasBlank = isBlank && !insideFence && !isFenceLine;

      offset += lineWithNewlineLen;
    }
    return lastBoundary;
  }

  static bool _isFenceLine(String trimmedLine) {
    if (trimmedLine.length < 3) return false;
    final ch = trimmedLine[0];
    if (ch != '`' && ch != '~') return false;
    return _leadingRunLength(trimmedLine, ch) >= 3;
  }

  static int _leadingRunLength(String s, String ch) {
    var n = 0;
    while (n < s.length && s[n] == ch) {
      n++;
    }
    return n;
  }

  @override
  State<IncrementalMarkdownBody> createState() =>
      _IncrementalMarkdownBodyState();
}

class _IncrementalMarkdownBodyState extends State<IncrementalMarkdownBody> {
  String? _stableData;
  Widget? _stableChild;

  Widget _buildStable(String data) {
    if (_stableChild == null || _stableData != data) {
      _stableData = data;
      // Rebuilt only when the settled prefix changes; otherwise reused as-is
      // so the underlying MarkdownBody does not re-parse the prefix.
      _stableChild = data.isEmpty
          ? const SizedBox.shrink()
          : widget.sliceBuilder(data);
    }
    return _stableChild!;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final splitAt = IncrementalMarkdownBody.stableSplitIndex(data);
    final tailBuild = widget.tailBuilder ?? widget.sliceBuilder;
    if (splitAt <= 0) {
      // No settled prefix yet — the whole thing is the active tail.
      return tailBuild(data);
    }
    final stable = data.substring(0, splitAt);
    final tail = data.substring(splitAt);
    final stableChild = _buildStable(stable);
    final tailChild =
        tail.isEmpty ? const SizedBox.shrink() : tailBuild(tail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[stableChild, tailChild],
    );
  }
}
