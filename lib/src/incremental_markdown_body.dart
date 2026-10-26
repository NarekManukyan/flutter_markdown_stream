/// An incremental wrapper around `MarkdownBody` that avoids re-parsing
/// already-settled content on every streaming frame.
///
/// While Markdown streams in, the naive approach re-parses the *entire*
/// accumulated buffer on every rebuild — O(total length) per frame, which is
/// O(n²) over the life of a long response. [IncrementalMarkdownBody] splits the
/// text at **top-level blank-line boundaries** into blocks. Every block gets
/// its own `MarkdownBody` under a stable key, so a block that has settled keeps
/// its element and parsed widgets across frames — `MarkdownBody` only re-parses
/// when its text or style sheet changes. Only the last block, the one still
/// being written, is parsed per frame, so per-frame parse cost is
/// O(active block length).
///
/// Splitting only happens at a blank line that is **not** inside a fenced
/// code block, not before an indented continuation line, and not between two
/// items of the same list, so every block is self-contained Markdown that
/// renders the same as it would inside one `MarkdownBody`. When the text
/// contains a link reference or footnote definition (`[id]: …`), which must be
/// parsed together with the text that uses it, the whole text is rendered as a
/// single block.
///
/// Block boundaries are found incrementally: when the new text extends the
/// previous text, scanning resumes from the last boundary instead of the start.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'fence_tracker.dart';

/// Builds a `MarkdownBody` for a slice of the streamed text. The wrapper calls
/// this for each settled block and the active tail with identical styling, so
/// callers can forward every `MarkdownBody` parameter in one place.
typedef MarkdownSliceBuilder = Widget Function(String data);

/// Splits streamed Markdown into keyed per-block bodies and a live tail.
///
/// See the library doc comment for the rationale.
class IncrementalMarkdownBody extends StatefulWidget {
  /// Creates an incremental Markdown renderer.
  ///
  /// [data] is the full (already-sanitized) Markdown to render. [sliceBuilder]
  /// must build a `MarkdownBody` (or equivalent) for a given substring using
  /// the caller's styling; it is invoked for every block.
  const IncrementalMarkdownBody({
    super.key,
    required this.data,
    required this.sliceBuilder,
    this.tailBuilder,
    this.blockSpacing = 8,
    this.settleDuration = Duration.zero,
    this.tailSettled = false,
  });

  /// The full sanitized Markdown to render.
  final String data;

  /// Builds a Markdown widget for a slice of [data] (used for settled blocks,
  /// and for the active tail when [tailBuilder] is null).
  final MarkdownSliceBuilder sliceBuilder;

  /// Optional builder for the *active tail* only. When supplied, the still-
  /// streaming block is built with this instead of [sliceBuilder] — e.g. to
  /// apply a per-word fade to the paragraph currently being typed.
  final MarkdownSliceBuilder? tailBuilder;

  /// How long a block keeps using [tailBuilder] after it stops being the
  /// active tail, before switching to [sliceBuilder]. Lets an animated tail
  /// (such as a per-word fade) finish instead of snapping when the next block
  /// starts or the stream ends. Zero switches immediately.
  final Duration settleDuration;

  /// Whether the last block is finished too (the stream has ended). It then
  /// switches to [sliceBuilder] after [settleDuration], like any other
  /// settled block.
  final bool tailSettled;

  /// Vertical space between blocks. Should match the style sheet's
  /// `blockSpacing` so the split rendering is spaced like a single
  /// `MarkdownBody`.
  final double blockSpacing;

  /// Returns the index at which [data] can be safely split into a stable
  /// prefix `[0, index)` and an active tail `[index, end)`.
  ///
  /// The split point is the start of the **last** top-level block (see the
  /// library doc comment for what counts as a boundary). Returns `0` when
  /// there is no safe boundary, meaning the whole string is active.
  ///
  /// Exposed for testing.
  static int stableSplitIndex(String data) => _BlockSplitter().split(data).last;

  @override
  State<IncrementalMarkdownBody> createState() =>
      _IncrementalMarkdownBodyState();
}

class _IncrementalMarkdownBodyState extends State<IncrementalMarkdownBody> {
  final _BlockSplitter _splitter = _BlockSplitter();

  // Blocks that recently stopped being the active tail and still render with
  // the tail builder, each with the timer that ends its settle window.
  final Map<int, Timer> _settling = <int, Timer>{};
  int _blockCount = 0;
  bool _tailWasSettled = false;

  @override
  void dispose() {
    for (final timer in _settling.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _startSettling(int index) {
    if (widget.tailBuilder == null || widget.settleDuration <= Duration.zero) {
      return;
    }
    _settling[index]?.cancel();
    _settling[index] = Timer(widget.settleDuration, () {
      if (!mounted) return;
      setState(() => _settling.remove(index));
    });
  }

  void _clearSettling() {
    for (final timer in _settling.values) {
      timer.cancel();
    }
    _settling.clear();
  }

  void _trackSettling(int count) {
    if (count < _blockCount || (!widget.tailSettled && _tailWasSettled)) {
      // The text was replaced or restarted.
      _clearSettling();
    } else if (count > _blockCount && _blockCount > 0) {
      // The previous tail, and any block that came and went within one
      // update, are now settled.
      for (var i = _blockCount - 1; i < count - 1; i++) {
        _startSettling(i);
      }
    }
    if (widget.tailSettled && !_tailWasSettled) _startSettling(count - 1);
    _blockCount = count;
    _tailWasSettled = widget.tailSettled;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final starts = _splitter.split(data);
    _trackSettling(starts.length);
    final tailBuild = widget.tailBuilder ?? widget.sliceBuilder;
    final children = <Widget>[];
    for (var i = 0; i < starts.length; i++) {
      final isTail = i == starts.length - 1;
      final block = data.substring(
        starts[i],
        isTail ? data.length : starts[i + 1],
      );
      final active =
          (isTail && !widget.tailSettled) || _settling.containsKey(i);
      if (i > 0) children.add(SizedBox(height: widget.blockSpacing));
      // A stable key per block index keeps each settled block's element (and
      // its parsed Markdown) alive while later blocks stream in.
      children.add(
        KeyedSubtree(
          key: ValueKey<int>(i),
          child: active ? tailBuild(block) : widget.sliceBuilder(block),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// Finds top-level block boundaries, resuming from the previous result when
/// the text has only grown since the last call.
final class _BlockSplitter {
  static final RegExp _listItem = RegExp(r'^([-+*]|\d{1,9}[.)])([ \t]|$)');
  static final RegExp _definition = RegExp(r'^ {0,3}\[[^\]\n]+\]:');

  // Result of the previous call.
  List<int> _starts = const <int>[0];
  String _settled = '';
  bool _listOpenAtLastStart = false;

  /// Returns the start offsets of each block of [data]. The first entry is
  /// always `0`; the last entry is the start of the active tail.
  List<int> split(String data) {
    var starts = <int>[0];
    var resumeAt = 0;
    var listOpen = false;
    final last = _starts.last;
    if (last > 0 && data.length > last && data.startsWith(_settled)) {
      // Everything before the last boundary is unchanged, and a boundary is
      // never inside a fence, so scanning can resume there.
      starts = List<int>.of(_starts);
      resumeAt = last;
      listOpen = _listOpenAtLastStart;
    }

    final fences = FenceTracker();
    var listOpenAtLastStart = resumeAt > 0 && listOpen;
    var previousBlank = false;
    var lineStart = resumeAt;
    while (lineStart <= data.length) {
      var lineEnd = data.indexOf('\n', lineStart);
      if (lineEnd == -1) lineEnd = data.length;
      final line = data.substring(lineStart, lineEnd);

      final wasInFence = fences.isOpen;
      final isFence = fences.addLine(line);
      final blank = line.trim().isEmpty;
      if (!wasInFence && !blank) {
        if (_definition.hasMatch(line)) {
          // Reference definitions must be parsed with the text that uses
          // them, so this text is rendered as one block.
          _starts = const <int>[0];
          _settled = '';
          _listOpenAtLastStart = false;
          return _starts;
        }
        final indented = line.startsWith(' ') || line.startsWith('\t');
        final isListItem = !indented && _listItem.hasMatch(line);
        if (previousBlank &&
            lineStart > resumeAt &&
            !indented &&
            !(listOpen && isListItem)) {
          starts.add(lineStart);
          listOpenAtLastStart = listOpen;
        }
        if (!indented) listOpen = isListItem;
      }
      previousBlank = !wasInFence && !isFence && blank;

      if (lineEnd == data.length) break;
      lineStart = lineEnd + 1;
    }

    if (starts.last != resumeAt || resumeAt == 0) {
      _settled = data.substring(0, starts.last);
    }
    _starts = starts;
    _listOpenAtLastStart = listOpenAtLastStart;
    return starts;
  }
}
