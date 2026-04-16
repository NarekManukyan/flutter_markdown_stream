import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'latex_syntax.dart';
import 'safe_markdown_parser.dart';
import 'streaming_config.dart';
import 'streaming_text_controller.dart';

/// Signature for a convenience builder that renders a fenced code block.
typedef CodeBlockBuilder = Widget Function(String code, String language);

/// Signature for the `onDone` callback.
typedef MarkdownStreamDoneCallback = void Function(String fullText);

/// Extractor: turn a typed chunk [T] into plain Markdown text.
typedef ChunkToText<T> = String Function(T chunk);

/// Factory for producing a fresh stream on [StreamingTextController.restart].
typedef MarkdownStreamFactory<T> = Stream<T> Function();

/// A Markdown widget that renders progressively from a stream of token
/// chunks.
///
/// ### Chunk types
///
/// `MarkdownStream` is **generic over the chunk type `T`**. The common case
/// is `Stream<String>` — pass it in directly, no extractor required:
///
/// ```dart
/// MarkdownStream(stream: openAiPlainTextStream)
/// ```
///
/// For any other stream type (typed SDK chunks, raw bytes, JSON events),
/// supply a `chunkToText` extractor:
///
/// ```dart
/// MarkdownStream<ChatCompletionChunk>(
///   stream: sdkStream,
///   chunkToText: (c) => c.choices.first.delta?.content ?? '',
/// )
/// ```
///
/// For raw HTTP bytes, Server-Sent Events, or nested-JSON extraction, see
/// `StreamAdapters` — it decodes/parses the stream upstream of the widget.
///
/// ### Rendering
///
/// Every chunk is appended to an internal buffer; the buffer is sanitized
/// via [SafeMarkdownParser] before each render so partial Markdown syntax
/// never produces broken layout, flicker, or crashes. Rebuilds are scoped
/// via a [ValueNotifier] + [ValueListenableBuilder] (no `setState` in the
/// hot path) and throttled to roughly one frame so bursts of tokens
/// coalesce into a single rebuild.
///
/// Every `MarkdownBody` customisation hook (`styleSheet`,
/// `syntaxHighlighter`, `imageBuilder`, `checkboxBuilder`, `bulletBuilder`,
/// `builders`, `paddingBuilders`, `extensionSet`, `blockSyntaxes`,
/// `inlineSyntaxes`, etc.) is forwarded verbatim.
///
/// ### Playback control
///
/// Attach a [StreamingTextController] to pause, resume, skip to end, stop,
/// or restart the stream. The controller also carries a [speedMultiplier]
/// that shrinks or stretches the rebuild debounce.
///
/// ### Presets and fade
///
/// Use a [StreamingTextConfig] (or one of the `StreamingPresets`) to bundle
/// the debounce and fade-in settings into a single value.
///
/// ### LaTeX
///
/// Provide a [LaTeXBuilder] via [latexBuilder] to render `$…$` (inline) and
/// `$$…$$` (block) expressions using your preferred math library
/// (e.g. `flutter_math_fork`). No dependency is added unless you opt in.
///
/// ### RTL
///
/// Pass [textDirection] to force a specific directionality. Default inherits
/// from the nearest [Directionality].
class MarkdownStream<T> extends StatefulWidget {
  /// Creates a streaming Markdown widget.
  ///
  /// [chunkToText] is required for any stream whose element type is not
  /// [String]. A runtime [StateError] is thrown on the first chunk if this
  /// invariant is violated.
  const MarkdownStream({
    super.key,
    required this.stream,
    this.chunkToText,
    // --- stream-specific ---
    this.onDone,
    this.cursorWidget,
    this.rebuildDebounce = const Duration(milliseconds: 16),
    this.codeBuilder,
    this.config,
    this.controller,
    this.streamFactory,
    this.latexBuilder,
    this.textDirection,
    // --- MarkdownBody pass-through ---
    this.styleSheet,
    this.styleSheetTheme,
    this.syntaxHighlighter,
    this.onTapLink,
    this.onTapText,
    this.imageDirectory,
    this.blockSyntaxes,
    this.inlineSyntaxes,
    this.extensionSet,
    this.imageBuilder,
    this.checkboxBuilder,
    this.bulletBuilder,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.paddingBuilders = const <String, MarkdownPaddingBuilder>{},
    this.listItemCrossAxisAlignment =
        MarkdownListItemCrossAxisAlignment.baseline,
    this.fitContent = true,
    this.shrinkWrap = true,
    this.softLineBreak = false,
    this.selectable = false,
    this.padding = EdgeInsets.zero,
  });

  // ----- stream-specific ------------------------------------------------------

  /// The stream of chunks to render. Each event is appended to the
  /// accumulated buffer after conversion via [chunkToText].
  final Stream<T> stream;

  /// Converts each chunk [T] to a plain text fragment.
  ///
  /// Required for any `T` other than [String]. When `T == String`, leave
  /// this `null` to use identity.
  final ChunkToText<T>? chunkToText;

  /// Called when [stream] emits a `done` event, with the full accumulated
  /// text.
  final MarkdownStreamDoneCallback? onDone;

  /// Optional widget appended to the end of the rendered Markdown while
  /// the stream is still open. A typical choice is `BlinkingCursor()`.
  final Widget? cursorWidget;

  /// Minimum time between rebuilds. Bursts of tokens inside a debounce
  /// window produce at most one rebuild. Defaults to one frame (16ms).
  /// Set to [Duration.zero] to rebuild on every chunk (useful for tests).
  ///
  /// Overridden by [config]`.rebuildDebounce` when both are provided.
  final Duration rebuildDebounce;

  /// Optional convenience builder for fenced (block) code only.
  ///
  /// If [builders] also contains a `'code'` entry, the entry in [builders]
  /// wins.
  final CodeBlockBuilder? codeBuilder;

  /// Optional bundle of streaming-animation settings (debounce, fade, …).
  ///
  /// Takes precedence over [rebuildDebounce] when both are supplied.
  final StreamingTextConfig? config;

  /// Optional controller for programmatic playback (pause / resume / skip).
  final StreamingTextController? controller;

  /// Factory that produces a fresh stream on
  /// [StreamingTextController.restart]. Required if [restart][StreamingTextController.restart]
  /// will be used; otherwise ignored.
  final MarkdownStreamFactory<T>? streamFactory;

  /// Optional LaTeX renderer. When supplied, inline (`$…$`) and block
  /// (`$$…$$`) LaTeX expressions are extracted and rendered through this
  /// callback. No LaTeX dependency is added to the package — bring your own
  /// math renderer.
  final LaTeXBuilder? latexBuilder;

  /// Forces a specific text direction. When `null`, inherits from the
  /// ambient [Directionality].
  final TextDirection? textDirection;

  // ----- MarkdownBody pass-through -------------------------------------------

  /// See [MarkdownBody.styleSheet].
  final MarkdownStyleSheet? styleSheet;

  /// See [MarkdownBody.styleSheetTheme].
  final MarkdownStyleSheetBaseTheme? styleSheetTheme;

  /// See [MarkdownBody.syntaxHighlighter].
  final SyntaxHighlighter? syntaxHighlighter;

  /// See [MarkdownBody.onTapLink].
  final MarkdownTapLinkCallback? onTapLink;

  /// See [MarkdownBody.onTapText].
  final VoidCallback? onTapText;

  /// See [MarkdownBody.imageDirectory].
  final String? imageDirectory;

  /// See [MarkdownBody.blockSyntaxes].
  final List<md.BlockSyntax>? blockSyntaxes;

  /// See [MarkdownBody.inlineSyntaxes].
  final List<md.InlineSyntax>? inlineSyntaxes;

  /// See [MarkdownBody.extensionSet].
  final md.ExtensionSet? extensionSet;

  /// See [MarkdownBody.imageBuilder].
  final MarkdownImageBuilder? imageBuilder;

  /// See [MarkdownBody.checkboxBuilder].
  final MarkdownCheckboxBuilder? checkboxBuilder;

  /// See [MarkdownBody.bulletBuilder].
  final MarkdownBulletBuilder? bulletBuilder;

  /// See [MarkdownBody.builders]. Takes precedence over [codeBuilder] for
  /// the `'code'` key when both are supplied.
  final Map<String, MarkdownElementBuilder> builders;

  /// See [MarkdownBody.paddingBuilders].
  final Map<String, MarkdownPaddingBuilder> paddingBuilders;

  /// See [MarkdownBody.listItemCrossAxisAlignment].
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  /// See [MarkdownBody.fitContent].
  final bool fitContent;

  /// See [MarkdownBody.shrinkWrap].
  final bool shrinkWrap;

  /// See [MarkdownBody.softLineBreak].
  final bool softLineBreak;

  /// See [MarkdownBody.selectable].
  final bool selectable;

  /// Padding applied around the rendered Markdown.
  final EdgeInsetsGeometry padding;

  @override
  State<MarkdownStream<T>> createState() => _MarkdownStreamState<T>();
}

/// Immutable render-time state.
@immutable
class _RenderState {
  const _RenderState({required this.text, required this.isDone});

  final String text;
  final bool isDone;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _RenderState && other.text == text && other.isDone == isDone);

  @override
  int get hashCode => Object.hash(text, isDone);

  _RenderState copyWith({String? text, bool? isDone}) =>
      _RenderState(text: text ?? this.text, isDone: isDone ?? this.isDone);
}

class _MarkdownStreamState<T> extends State<MarkdownStream<T>> {
  final StringBuffer _raw = StringBuffer();
  final ValueNotifier<_RenderState> _state =
      ValueNotifier<_RenderState>(const _RenderState(text: '', isDone: false));
  StreamSubscription<T>? _sub;
  Timer? _debounceTimer;
  bool _pendingRender = false;
  bool _paused = false;

  StreamingTextController? get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _subscribe(widget.stream);
  }

  @override
  void didUpdateWidget(covariant MarkdownStream<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (oldWidget.stream != widget.stream) {
      _sub?.cancel();
      _debounceTimer?.cancel();
      _raw.clear();
      _pendingRender = false;
      _paused = false;
      _state.value = const _RenderState(text: '', isDone: false);
      final c = _controller;
      if (c != null) {
        // didUpdateWidget runs during build; notifyListeners on the
        // controller would cause "setState during build" for any listener
        // that calls setState. Defer to after the current frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller == c) c.internalReset();
        });
      }
      _subscribe(widget.stream);
    }
  }

  // --- controller plumbing ---------------------------------------------------

  void _attachController(StreamingTextController? c) {
    if (c == null) return;
    c.addListener(_onControllerNotify);
  }

  void _detachController(StreamingTextController? c) {
    if (c == null) return;
    c.removeListener(_onControllerNotify);
  }

  void _onControllerNotify() {
    final c = _controller;
    if (c == null) return;
    final cmd = c.lastCommand;
    if (cmd == null) return;
    // Consume the command once.
    c.internalClearCommand();
    switch (cmd.kind) {
      case StreamingCommandKind.pause:
        _handlePause();
      case StreamingCommandKind.resume:
        _handleResume();
      case StreamingCommandKind.skipToEnd:
        _handleSkipToEnd();
      case StreamingCommandKind.stop:
        _handleStop();
      case StreamingCommandKind.restart:
        _handleRestart();
    }
  }

  void _handlePause() {
    if (_paused || _state.value.isDone) return;
    _paused = true;
    _debounceTimer?.cancel();
    _pendingRender = false;
    _controller?.internalSetState(StreamingState.paused);
  }

  void _handleResume() {
    if (!_paused) return;
    _paused = false;
    _controller?.internalSetState(StreamingState.streaming);
    _renderNow();
  }

  void _handleSkipToEnd() {
    if (_state.value.isDone) return;
    _sub?.cancel();
    _debounceTimer?.cancel();
    _paused = false;
    _renderNow(done: true);
    widget.onDone?.call(_raw.toString());
    _controller?.internalSetState(StreamingState.completed);
  }

  void _handleStop() {
    if (_state.value.isDone) return;
    _sub?.cancel();
    _debounceTimer?.cancel();
    _paused = false;
    // Keep the currently-rendered text; just mark it as done so the cursor
    // disappears. Do NOT fire onDone — this is an explicit user-cancel.
    _state.value = _state.value.copyWith(isDone: true);
    _controller?.internalSetState(StreamingState.completed);
  }

  void _handleRestart() {
    final factory = widget.streamFactory;
    if (factory == null) {
      throw StateError(
        'StreamingTextController.restart() requires MarkdownStream to be '
        'constructed with a streamFactory.',
      );
    }
    _sub?.cancel();
    _debounceTimer?.cancel();
    _raw.clear();
    _pendingRender = false;
    _paused = false;
    _state.value = const _RenderState(text: '', isDone: false);
    _controller?.internalReset();
    _subscribe(factory());
  }

  // --- stream lifecycle ------------------------------------------------------

  void _subscribe(Stream<T> s) {
    _sub = s.listen(
      _onChunk,
      onDone: _onStreamDone,
      onError: _onStreamError,
      cancelOnError: true,
    );
  }

  /// Resolves a chunk to text. Uses the supplied [MarkdownStream.chunkToText]
  /// if present; otherwise requires `T` to be [String].
  String _toText(T chunk) {
    final extractor = widget.chunkToText;
    if (extractor != null) return extractor(chunk);
    if (chunk is String) return chunk;
    throw StateError(
      'MarkdownStream<$T> requires a chunkToText extractor because the '
      'chunk type is not String. Got: ${chunk.runtimeType}',
    );
  }

  void _onChunk(T chunk) {
    final text = _toText(chunk);
    if (text.isEmpty) return;
    _raw.write(text);
    final c = _controller;
    if (c != null) {
      c.internalIncrementChunkCount();
      if (c.state == StreamingState.idle) {
        c.internalSetState(StreamingState.streaming);
      }
    }
    if (_paused) return;
    _scheduleRender();
  }

  void _onStreamDone() {
    _debounceTimer?.cancel();
    _renderNow(done: true);
    widget.onDone?.call(_raw.toString());
    _controller?.internalSetState(StreamingState.completed);
  }

  void _onStreamError(Object _, StackTrace __) {
    _controller?.internalSetState(StreamingState.error);
    _onStreamDone();
  }

  Duration get _effectiveDebounce {
    final base = widget.config?.rebuildDebounce ?? widget.rebuildDebounce;
    final mult = _controller?.speedMultiplier ?? 1.0;
    if (mult == 1.0) return base;
    final us = (base.inMicroseconds / mult).round();
    return Duration(microseconds: us < 0 ? 0 : us);
  }

  void _scheduleRender() {
    if (_pendingRender) return;
    _pendingRender = true;
    _debounceTimer?.cancel();
    final d = _effectiveDebounce;
    if (d == Duration.zero) {
      _renderNow();
      return;
    }
    _debounceTimer = Timer(d, _renderNow);
  }

  void _renderNow({bool done = false}) {
    _pendingRender = false;
    if (!mounted) return;
    final raw = _raw.toString();
    final latex = widget.latexBuilder != null;
    final nextText = done ? raw : SafeMarkdownParser.sanitize(raw, latexEnabled: latex);
    _state.value = _state.value.copyWith(text: nextText, isDone: done);
    _controller?.internalSetCurrentText(nextText);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
    _detachController(widget.controller);
    _state.dispose();
    super.dispose();
  }

  // --- builder / syntax wiring ----------------------------------------------

  Map<String, MarkdownElementBuilder> _effectiveBuilders() {
    final cb = widget.codeBuilder;
    final latex = widget.latexBuilder;
    final hasCode = cb != null && !widget.builders.containsKey('code');
    final hasLatex = latex != null && !widget.builders.containsKey(kLatexTag);
    if (!hasCode && !hasLatex) return widget.builders;
    return <String, MarkdownElementBuilder>{
      if (hasCode) 'code': _CustomCodeBuilder(cb),
      if (hasLatex) kLatexTag: LaTeXElementBuilder(latex),
      ...widget.builders,
    };
  }

  List<md.BlockSyntax>? _effectiveBlockSyntaxes() {
    if (widget.latexBuilder == null) return widget.blockSyntaxes;
    return <md.BlockSyntax>[
      LaTeXBlockSyntax(),
      ...?widget.blockSyntaxes,
    ];
  }

  List<md.InlineSyntax>? _effectiveInlineSyntaxes() {
    if (widget.latexBuilder == null) return widget.inlineSyntaxes;
    // LaTeX inline must run BEFORE emphasis syntaxes, so prepend.
    return <md.InlineSyntax>[
      LaTeXInlineSyntax(),
      ...?widget.inlineSyntaxes,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    Widget tree = Padding(
      padding: widget.padding,
      child: ValueListenableBuilder<_RenderState>(
        valueListenable: _state,
        builder: (context, state, _) => _MarkdownBodyWithCursor(
          state: state,
          styleSheet: widget.styleSheet,
          styleSheetTheme: widget.styleSheetTheme,
          syntaxHighlighter: widget.syntaxHighlighter,
          onTapLink: widget.onTapLink,
          onTapText: widget.onTapText,
          imageDirectory: widget.imageDirectory,
          blockSyntaxes: _effectiveBlockSyntaxes(),
          inlineSyntaxes: _effectiveInlineSyntaxes(),
          extensionSet: widget.extensionSet,
          imageBuilder: widget.imageBuilder,
          checkboxBuilder: widget.checkboxBuilder,
          bulletBuilder: widget.bulletBuilder,
          builders: _effectiveBuilders(),
          paddingBuilders: widget.paddingBuilders,
          listItemCrossAxisAlignment: widget.listItemCrossAxisAlignment,
          fitContent: widget.fitContent,
          shrinkWrap: widget.shrinkWrap,
          softLineBreak: widget.softLineBreak,
          selectable: widget.selectable,
          cursorWidget: widget.cursorWidget,
          fadeInEnabled: config?.fadeInEnabled ?? false,
          fadeInDuration: config?.fadeInDuration ??
              const Duration(milliseconds: 300),
          fadeInCurve: config?.fadeInCurve ?? Curves.easeOut,
          trailingFadeHeight: config?.trailingFadeHeight ?? 40,
        ),
      ),
    );
    // Apply the explicit text direction at the OUTERMOST level so every
    // widget we build — Padding, ValueListenableBuilder, MarkdownBody,
    // cursor, fade mask — resolves alignment against the user's direction.
    if (widget.textDirection != null) {
      tree = Directionality(textDirection: widget.textDirection!, child: tree);
    }
    return tree;
  }
}

/// Render widget for the current [_RenderState]. Stateful so it can own the
/// [AnimationController] used for the trailing fade-out when the stream
/// completes.
class _MarkdownBodyWithCursor extends StatefulWidget {
  const _MarkdownBodyWithCursor({
    required this.state,
    required this.styleSheet,
    required this.styleSheetTheme,
    required this.syntaxHighlighter,
    required this.onTapLink,
    required this.onTapText,
    required this.imageDirectory,
    required this.blockSyntaxes,
    required this.inlineSyntaxes,
    required this.extensionSet,
    required this.imageBuilder,
    required this.checkboxBuilder,
    required this.bulletBuilder,
    required this.builders,
    required this.paddingBuilders,
    required this.listItemCrossAxisAlignment,
    required this.fitContent,
    required this.shrinkWrap,
    required this.softLineBreak,
    required this.selectable,
    required this.cursorWidget,
    required this.fadeInEnabled,
    required this.fadeInDuration,
    required this.fadeInCurve,
    required this.trailingFadeHeight,
  });

  final _RenderState state;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownStyleSheetBaseTheme? styleSheetTheme;
  final SyntaxHighlighter? syntaxHighlighter;
  final MarkdownTapLinkCallback? onTapLink;
  final VoidCallback? onTapText;
  final String? imageDirectory;
  final List<md.BlockSyntax>? blockSyntaxes;
  final List<md.InlineSyntax>? inlineSyntaxes;
  final md.ExtensionSet? extensionSet;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownCheckboxBuilder? checkboxBuilder;
  final MarkdownBulletBuilder? bulletBuilder;
  final Map<String, MarkdownElementBuilder> builders;
  final Map<String, MarkdownPaddingBuilder> paddingBuilders;
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;
  final bool fitContent;
  final bool shrinkWrap;
  final bool softLineBreak;
  final bool selectable;
  final Widget? cursorWidget;
  final bool fadeInEnabled;
  final Duration fadeInDuration;
  final Curve fadeInCurve;
  final double trailingFadeHeight;

  @override
  State<_MarkdownBodyWithCursor> createState() =>
      _MarkdownBodyWithCursorState();
}

class _MarkdownBodyWithCursorState extends State<_MarkdownBodyWithCursor>
    with TickerProviderStateMixin {
  AnimationController? _fadeController;

  @override
  void didUpdateWidget(covariant _MarkdownBodyWithCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.fadeInEnabled) {
      _fadeController?.dispose();
      _fadeController = null;
      return;
    }
    _ensureController();
    final ctrl = _fadeController!;
    // Animate: mask fully visible while streaming (value 1.0),
    // mask fully hidden when done (value 0.0).
    if (widget.state.isDone && oldWidget.state.isDone == false) {
      ctrl.reverse(from: 1);
    } else if (!widget.state.isDone && oldWidget.state.isDone) {
      ctrl.forward(from: 0);
    }
  }

  void _ensureController() {
    if (_fadeController != null) {
      _fadeController!.duration = widget.fadeInDuration;
      return;
    }
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.fadeInDuration,
      // Start fully visible if we're streaming, invisible if already done.
      value: widget.state.isDone ? 0.0 : 1.0,
    );
  }

  @override
  void dispose() {
    _fadeController?.dispose();
    super.dispose();
  }

  Widget _applyFade(Widget child) {
    if (!widget.fadeInEnabled) return child;
    _ensureController();
    final ctrl = _fadeController!;
    return AnimatedBuilder(
      animation: ctrl,
      child: child,
      builder: (context, inner) {
        final t = widget.fadeInCurve.transform(ctrl.value);
        if (t <= 0) return inner!;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final h = bounds.height;
            if (h <= 0) return const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)]).createShader(bounds);
            // Fade occupies the bottom `trailingFadeHeight * t` pixels.
            final fadeH = widget.trailingFadeHeight * t;
            final opaqueStop = (1 - fadeH / h).clamp(0.0, 1.0);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const <Color>[
                Color(0xFFFFFFFF),
                Color(0xFFFFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: <double>[0, opaqueStop, 1],
            ).createShader(bounds);
          },
          child: inner,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = MarkdownBody(
      data: widget.state.text,
      selectable: widget.selectable,
      styleSheet: widget.styleSheet,
      styleSheetTheme: widget.styleSheetTheme,
      syntaxHighlighter: widget.syntaxHighlighter,
      onTapLink: widget.onTapLink,
      onTapText: widget.onTapText,
      imageDirectory: widget.imageDirectory,
      blockSyntaxes: widget.blockSyntaxes,
      inlineSyntaxes: widget.inlineSyntaxes,
      extensionSet: widget.extensionSet,
      imageBuilder: widget.imageBuilder,
      checkboxBuilder: widget.checkboxBuilder,
      bulletBuilder: widget.bulletBuilder,
      builders: widget.builders,
      paddingBuilders: widget.paddingBuilders,
      listItemCrossAxisAlignment: widget.listItemCrossAxisAlignment,
      fitContent: widget.fitContent,
      shrinkWrap: widget.shrinkWrap,
      softLineBreak: widget.softLineBreak,
    );
    final faded = _applyFade(body);
    if (widget.state.isDone || widget.cursorWidget == null) {
      return faded;
    }
    // Stretch the cross axis so the MarkdownBody fills the full available
    // width. This makes `TextAlign.start` inside each RichText resolve
    // correctly against the ambient Directionality (right in RTL) — with
    // CrossAxisAlignment.start, short content would instead shrink to its
    // intrinsic width and get positioned at the parent's LTR start.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        faded,
        Align(
          alignment: AlignmentDirectional.topStart,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: widget.cursorWidget,
          ),
        ),
      ],
    );
  }
}

/// Bridges the [CodeBlockBuilder] callback into a [MarkdownElementBuilder].
class _CustomCodeBuilder extends MarkdownElementBuilder {
  _CustomCodeBuilder(this.builder);

  final CodeBlockBuilder builder;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final classAttr = element.attributes['class'];
    if (classAttr == null || !classAttr.startsWith('language-')) {
      return null; // fall back to default (inline) rendering
    }
    final code = element.textContent;
    final lang = classAttr.replaceAll('language-', '').trim();
    return builder(code, lang);
  }
}
