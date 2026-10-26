/// Support for the `<think>…</think>` section that reasoning models (DeepSeek
/// R1, Qwen, QwQ and others) stream before their answer.
library;

import 'package:flutter/material.dart';

import 'motion.dart';

/// What a [ThinkingBuilder] gets to build the thinking section.
@immutable
class ThinkingState {
  /// Creates a thinking state.
  const ThinkingState({
    required this.text,
    required this.isActive,
    required this.content,
    this.elapsed,
  });

  /// The thinking text received so far (Markdown, without the tags).
  final String text;

  /// Whether the model is still thinking: the closing tag has not arrived
  /// and the stream is still open.
  final bool isActive;

  /// How long the model thought, once it finished. `null` while thinking,
  /// and for text that was not streamed (`MarkdownStream.text`).
  final Duration? elapsed;

  /// [text] rendered as Markdown with the stream's style sheet and builders,
  /// in a muted colour. Put it in your own container.
  final Widget content;
}

/// Builds the thinking section of a [MarkdownStream] answer.
typedef ThinkingBuilder = Widget Function(
  BuildContext context,
  ThinkingState state,
);

/// A thinking section split off the front of a response.
@immutable
class ThinkingSplit {
  /// Creates a split.
  const ThinkingSplit({
    required this.thinking,
    required this.answer,
    required this.isOpen,
  });

  /// The text between the tags.
  final String thinking;

  /// The text after the closing tag, without leading whitespace.
  final String answer;

  /// Whether the closing tag has not arrived yet.
  final bool isOpen;

  static final RegExp _open = RegExp(r'<(think|thinking)>', caseSensitive: false);
  static final RegExp _leadingSpace = RegExp(r'^\s+');
  static const List<String> _openTags = <String>['<think>', '<thinking>'];

  /// Splits [raw] when it starts (after whitespace) with `<think>` or
  /// `<thinking>`. Returns `null` when it does not.
  ///
  /// While the stream is open ([done] is `false`) a half-typed opening tag
  /// counts as an empty thinking section and a half-typed closing tag at the
  /// end is hidden, so neither flashes up as text.
  static ThinkingSplit? parse(String raw, {required bool done}) {
    var start = 0;
    while (start < raw.length && _isSpace(raw.codeUnitAt(start))) {
      start++;
    }
    if (start == raw.length || raw.codeUnitAt(start) != 0x3C) return null;

    final open = _open.matchAsPrefix(raw, start);
    if (open == null) {
      if (done) return null;
      final rest = raw.substring(start).toLowerCase();
      final partial = _openTags.any((t) => t.startsWith(rest));
      return partial
          ? const ThinkingSplit(thinking: '', answer: '', isOpen: true)
          : null;
    }

    final tag = open.group(1)!.toLowerCase();
    final body = raw.substring(open.end);
    final close = RegExp('</$tag>', caseSensitive: false).firstMatch(body);
    if (close == null) {
      var thinking = body;
      if (!done) thinking = _withoutPartialCloser(thinking, '</$tag>');
      return ThinkingSplit(thinking: thinking.trim(), answer: '', isOpen: true);
    }
    return ThinkingSplit(
      thinking: body.substring(0, close.start).trim(),
      answer: body.substring(close.end).replaceFirst(_leadingSpace, ''),
      isOpen: false,
    );
  }

  static String _withoutPartialCloser(String text, String closer) {
    final lower = text.toLowerCase();
    for (var n = closer.length - 1; n > 0; n--) {
      if (lower.endsWith(closer.substring(0, n))) {
        return text.substring(0, text.length - n);
      }
    }
    return text;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}

/// The default thinking section: a "Thinking…" header that shimmers while
/// the model thinks and becomes "Thought for 12s" when it is done, over the
/// thinking text.
///
/// It is open while the model thinks and folds away when the answer starts.
/// Tapping the header opens or closes it; once the user has done that, it
/// stays the way they left it.
class ThinkingBlock extends StatefulWidget {
  /// Creates a thinking section around [child].
  const ThinkingBlock({
    super.key,
    required this.child,
    required this.isActive,
    this.elapsed,
    this.activeLabel = 'Thinking…',
    this.doneLabel,
    this.initiallyExpanded,
  });

  /// Builds a [ThinkingBlock] from a [ThinkingState]; the default
  /// `MarkdownStream.thinkingBuilder`.
  static Widget fromState(BuildContext context, ThinkingState state) =>
      ThinkingBlock(
        isActive: state.isActive,
        elapsed: state.elapsed,
        child: state.content,
      );

  /// The thinking content, usually [ThinkingState.content].
  final Widget child;

  /// Whether the model is still thinking.
  final bool isActive;

  /// How long the model thought, shown once it is done.
  final Duration? elapsed;

  /// Header text while thinking.
  final String activeLabel;

  /// Header text once done. Defaults to "Thought for Ns", or "Thoughts" when
  /// [elapsed] is unknown.
  final String Function(Duration? elapsed)? doneLabel;

  /// Whether to start open. Defaults to open while [isActive], closed
  /// otherwise.
  final bool? initiallyExpanded;

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  late bool _expanded = widget.initiallyExpanded ?? widget.isActive;
  bool _userToggled = false;

  @override
  void didUpdateWidget(covariant ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userToggled && oldWidget.isActive != widget.isActive) {
      _expanded = widget.isActive;
    }
  }

  void _toggle() => setState(() {
        _userToggled = true;
        _expanded = !_expanded;
      });

  String _doneLabel() {
    final custom = widget.doneLabel;
    if (custom != null) return custom(widget.elapsed);
    final elapsed = widget.elapsed;
    if (elapsed == null) return 'Thoughts';
    final seconds = (elapsed.inMilliseconds / 1000).round();
    return seconds < 1 ? 'Thought for a moment' : 'Thought for ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(color: muted) ??
        TextStyle(color: muted);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

    final header = Semantics(
      button: true,
      expanded: _expanded,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: widget.isActive
                    ? ShimmerText(widget.activeLabel, style: labelStyle)
                    : Text(_doneLabel(), style: labelStyle),
              ),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: _expanded ? 0.25 : 0,
                duration: duration,
                curve: kStreamEaseOut,
                child: Icon(Icons.chevron_right_rounded, size: 18, color: muted),
              ),
            ],
          ),
        ),
      ),
    );

    final body = _expanded
        ? Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: widget.child,
              ),
            ),
          )
        : const SizedBox(width: double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        header,
        ClipRect(
          child: AnimatedSize(
            duration: duration,
            curve: kStreamEaseOut,
            alignment: AlignmentDirectional.topStart,
            child: body,
          ),
        ),
      ],
    );
  }
}

/// Text with a soft highlight sweeping across it, for "Thinking…" or
/// "Searching…" style status lines. Also works as a
/// `MarkdownStream.placeholder`.
///
/// With reduce motion on it renders as plain text.
class ShimmerText extends StatefulWidget {
  /// Creates shimmering [text].
  const ShimmerText(
    this.text, {
    super.key,
    this.style,
    this.period = const Duration(milliseconds: 1600),
  });

  /// The text to show.
  final String text;

  /// Text style, merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Time for one sweep.
  final Duration period;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void didUpdateWidget(covariant ShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _c.duration = widget.period;
      if (_c.isAnimating) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final text = Text(widget.text, style: style);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
      return text;
    }
    if (!_c.isAnimating) _c.repeat();
    final base = style.color ?? const Color(0xFF808080);
    final dim = base.withValues(alpha: base.a * 0.4);
    return AnimatedBuilder(
      animation: _c,
      child: text,
      builder: (context, child) {
        // The bright band travels from just before the start to just past
        // the end, so each sweep enters and leaves cleanly.
        final center = -0.3 + 1.6 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: <Color>[dim, base, dim],
            stops: <double>[
              (center - 0.3).clamp(0.0, 1.0),
              center.clamp(0.0, 1.0),
              (center + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
