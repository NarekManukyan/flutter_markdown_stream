/// Per-word fade-in for the currently-streaming text.
///
/// This renders a single run of inline Markdown (the paragraph being typed)
/// as a `Text.rich`, fading in the most recently revealed words — the
/// opacity-only, per-word effect used by ChatGPT / Claude.
///
/// Two modes:
///
/// * **Time-based** (when [WordFadeText.fadeDuration] is set, as
///   `MarkdownStream` does): each word fades from transparent to opaque over
///   `fadeDuration`, starting when it first appears. A word finishes fading
///   even if the stream stalls, and fades never restart when later words
///   arrive. Honours the platform's reduce-motion setting.
/// * **Position-based** (when `fadeDuration` is null): the last
///   [WordFadeText.fadeWindow] words are graded by distance from the
///   frontier, so a word brightens as the stream advances past it. When
///   [WordFadeText.isDone] is `true` everything is fully opaque.
///
/// Only inline formatting is handled here (bold, italic, strikethrough,
/// inline code); block structure, links and images are the caller's
/// responsibility (see how `MarkdownStream` renders settled blocks with a full
/// `MarkdownBody` and reserves this widget for the active paragraph via
/// [isSimpleParagraph]).
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownStyleSheet;
import 'package:markdown/markdown.dart' as md;

import 'motion.dart';

/// Renders inline Markdown [text] with a trailing per-word opacity fade.
class WordFadeText extends StatefulWidget {
  /// Creates a per-word fading text run.
  const WordFadeText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.isDone,
    this.styleSheet,
    this.textDirection,
    this.fadeWindow = 4,
    this.minOpacity = 0.15,
    this.trailing,
    this.fadeDuration,
    this.fadeCurve = kStreamEaseOut,
  });

  /// The inline element tags this widget styles itself. A caller that
  /// installs its own builder for any of these should not use this widget,
  /// since the custom builder would be bypassed.
  static const Set<String> renderedTags = <String>{
    'strong',
    'em',
    'del',
    'code',
    'a',
    'img',
  };

  /// The inline Markdown to render (a single paragraph's worth).
  final String text;

  /// The base text style; inline runs derive from it.
  final TextStyle baseStyle;

  /// Style sheet whose `strong`, `em`, `del` and `code` styles are applied to
  /// inline runs, so the text looks the same as when `MarkdownBody` renders
  /// it. When `null`, plain bold / italic / line-through / monospace styling
  /// is used.
  final MarkdownStyleSheet? styleSheet;

  /// Optional widget placed inline right after the last word, e.g. a cursor.
  final Widget? trailing;

  /// Position-based mode only: when `true`, all words are fully opaque (the
  /// stream has finished). In time-based mode words always finish their own
  /// fade, so the last words never snap to full opacity.
  final bool isDone;

  /// How long each new word takes to fade in. `null` selects the legacy
  /// position-based ramp ([fadeWindow], [minOpacity]).
  final Duration? fadeDuration;

  /// Easing of each word's fade in time-based mode.
  final Curve fadeCurve;

  /// Optional text direction forwarded to the underlying rich text.
  final TextDirection? textDirection;

  /// Position-based mode only: how many trailing words are graded from dim to
  /// opaque.
  final int fadeWindow;

  /// Position-based mode only: opacity of the newest word.
  final double minOpacity;

  /// Whether [text] is a plain paragraph this widget can fade — i.e. it is not
  /// a fenced code block, table, blockquote, heading, list, or horizontal
  /// rule, where inline-only rendering would drop structure, and it holds no
  /// link, URL or image, which need tap handling or image loading. Callers
  /// should fall back to a full Markdown renderer when this is `false`.
  static bool isSimpleParagraph(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return false;
    if (_linkLike.hasMatch(trimmed)) return false;
    // Block-level starters we do not render here.
    const blockStarts = <String>[
      '#',
      '>',
      '```',
      '~~~',
      '|',
      '---',
      '***',
      '___',
    ];
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

  // Inline links, images, autolinks and bare URLs.
  static final RegExp _linkLike =
      RegExp(r'\]\(|\]\[|<[a-zA-Z][\w+.-]*:|https?://|www\.');

  @override
  State<WordFadeText> createState() => _WordFadeTextState();
}

class _WordFadeTextState extends State<WordFadeText>
    with SingleTickerProviderStateMixin {
  // A monotonic clock built from the ticker's frame-synchronised elapsed
  // time, kept across ticker stops so arrival times stay comparable.
  late final Ticker _ticker = createTicker(_onTick);
  Duration _clockBase = Duration.zero;
  Duration _tickElapsed = Duration.zero;

  // When each word (by index) first appeared, in [_now] time.
  final List<Duration> _arrivals = <Duration>[];

  // Parsed runs, reused across animation frames while the text is unchanged.
  String? _runsText;
  TextStyle? _runsBaseStyle;
  MarkdownStyleSheet? _runsSheet;
  List<_Run> _runs = const <_Run>[];

  Duration get _now => _clockBase + _tickElapsed;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _tickElapsed = elapsed;
    final duration = widget.fadeDuration;
    if (duration == null ||
        _arrivals.isEmpty ||
        _now - _arrivals.last >= duration) {
      _stopTicker();
    }
    setState(() {});
  }

  void _stopTicker() {
    if (!_ticker.isActive) return;
    _clockBase += _tickElapsed;
    _tickElapsed = Duration.zero;
    _ticker.stop();
  }

  List<_Run> _parsedRuns() {
    if (_runsText == widget.text &&
        _runsBaseStyle == widget.baseStyle &&
        _runsSheet == widget.styleSheet) {
      return _runs;
    }
    // Flatten inline nodes into styled runs, splitting on whitespace so each
    // non-space run is one "word". GitHub-flavoured inline syntax matches
    // what MarkdownBody parses by default (e.g. `~~`).
    final runs = <_Run>[];
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseInline(widget.text);
    _walk(nodes, widget.baseStyle, runs);
    _runsText = widget.text;
    _runsBaseStyle = widget.baseStyle;
    _runsSheet = widget.styleSheet;
    _runs = runs;
    return runs;
  }

  @override
  Widget build(BuildContext context) {
    final runs = _parsedRuns();
    final totalWords = runs.where((r) => r.isWord).length;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? null : widget.fadeDuration;
    final timed = duration != null && duration > Duration.zero;
    if (timed) {
      if (_arrivals.length > totalWords) {
        _arrivals.removeRange(totalWords, _arrivals.length);
      }
      while (_arrivals.length < totalWords) {
        _arrivals.add(_now);
      }
      if (_arrivals.isNotEmpty &&
          _now - _arrivals.last < duration &&
          !_ticker.isActive) {
        _ticker.start();
      }
    } else {
      _stopTicker();
    }

    // Resolve the ambient text colour so the fade never falls back to a
    // hardcoded black (which would be invisible-on-dark).
    final Color fallbackColor = widget.baseStyle.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);

    var wordIndex = 0;
    final spans = <InlineSpan>[];
    for (final run in runs) {
      final double opacity;
      if (!run.isWord) {
        // Whitespace stays opaque to avoid flicker in the gaps.
        opacity = 1;
      } else if (timed) {
        final age = _now - _arrivals[wordIndex];
        final t =
            (age.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
        opacity = widget.fadeCurve.transform(t);
        wordIndex++;
      } else if (reduceMotion && widget.fadeDuration != null) {
        opacity = 1;
        wordIndex++;
      } else {
        opacity = _positionOpacity(totalWords - 1 - wordIndex);
        wordIndex++;
      }
      final color = run.style.color ?? fallbackColor;
      final background = run.style.backgroundColor;
      spans.add(
        TextSpan(
          text: run.text,
          style: run.style.copyWith(
            color: color.withValues(alpha: color.a * opacity),
            backgroundColor: background?.withValues(
              alpha: background.a * opacity,
            ),
          ),
        ),
      );
    }

    final trailingWidget = widget.trailing;
    if (trailingWidget != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: trailingWidget,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      textDirection: widget.textDirection,
    );
  }

  double _positionOpacity(int distanceFromEnd) {
    if (widget.isDone || distanceFromEnd >= widget.fadeWindow) return 1;
    // distanceFromEnd 0 (newest) -> minOpacity, fadeWindow -> 1.
    final t = (distanceFromEnd + 1) / widget.fadeWindow;
    final min = widget.minOpacity;
    return (min + (1 - min) * t).clamp(0.0, 1.0);
  }

  void _walk(List<md.Node> nodes, TextStyle style, List<_Run> out) {
    for (final node in nodes) {
      if (node is md.Text) {
        _emitText(node.text, style, out);
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
    final sheet = widget.styleSheet;
    switch (tag) {
      case 'strong':
        return sheet?.strong != null
            ? style.merge(sheet!.strong)
            : style.copyWith(fontWeight: FontWeight.bold);
      case 'em':
        return sheet?.em != null
            ? style.merge(sheet!.em)
            : style.copyWith(fontStyle: FontStyle.italic);
      case 'code':
        return sheet?.code != null
            ? style.merge(sheet!.code)
            : style.copyWith(fontFamily: 'monospace');
      case 'a':
        return sheet?.a != null
            ? style.merge(sheet!.a)
            : style.copyWith(decoration: TextDecoration.underline);
      case 'del':
        return sheet?.del != null
            ? style.merge(sheet!.del)
            : style.copyWith(decoration: TextDecoration.lineThrough);
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
}

class _Run {
  const _Run(this.text, this.style, {required this.isWord});
  final String text;
  final TextStyle style;
  final bool isWord;
}
