import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'incremental_markdown_body.dart';
import 'cursor_activity.dart';
import 'latex_syntax.dart';
import 'motion.dart';
import 'output_smoother.dart';
import 'safe_markdown_parser.dart';
import 'word_fade.dart';
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

/// Signature for the `onError` callback.
typedef MarkdownStreamErrorCallback = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Builds a widget shown below the rendered text after the stream failed.
typedef MarkdownStreamErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
);

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
    this.onTextChanged,
    this.onError,
    this.errorBuilder,
    this.cursorWidget,
    this.rebuildDebounce = const Duration(milliseconds: 16),
    this.codeBuilder,
    this.config,
    this.controller,
    this.streamFactory,
    this.latexBuilder,
    this.textDirection,
    this.incrementalParsing = false,
    this.wordFadeIn = true,
    this.wordFadeWindow = 4,
    this.wordFadeDuration = kWordFadeDuration,
    this.tableColumnMaxWidth = 320,
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

  /// Called on every rendered-text change with the current *projected*
  /// (sanitized, and when smoothing is enabled, paced) text — the exact
  /// string handed to the underlying `MarkdownBody` that frame.
  ///
  /// Fires on each debounced batch (or each smoothing tick), plus once more
  /// with the final text on completion. Useful for driving an auto-scroll
  /// trigger, a live token/character counter, or telemetry without attaching
  /// a full [StreamingTextController]. Keep the callback cheap — it runs in
  /// the render hot path.
  final MarkdownStreamDoneCallback? onTextChanged;

  /// Called when [stream] emits an error. The text received so far stays on
  /// screen, the controller (if any) moves to [StreamingState.error], and
  /// [onDone] still fires afterwards with the partial text.
  final MarkdownStreamErrorCallback? onError;

  /// Optional widget shown below the rendered text after [stream] emitted an
  /// error — e.g. a "Response interrupted, retry" row.
  final MarkdownStreamErrorBuilder? errorBuilder;

  /// Optional widget shown at the end of the rendered Markdown while the
  /// stream is still open. A typical choice is `BlinkingCursor()`.
  ///
  /// The cursor sits inline, right after the last character, when the text
  /// ends inside a paragraph, heading, list item or blockquote. After a
  /// block that cannot hold inline content (a code block, table or rule) it
  /// is placed on its own line below.
  final Widget? cursorWidget;

  /// Minimum time between rebuilds. Bursts of tokens inside a debounce
  /// window produce at most one rebuild. Defaults to one frame (16ms).
  /// Set to [Duration.zero] to rebuild on every chunk (useful for tests).
  ///
  /// Overridden by [config]`.rebuildDebounce` when both are provided.
  ///
  /// **Inert while smoothing is active.** Since smoothing is on by default
  /// (see [config]), the smoother's own tick drives cadence and this value is
  /// ignored. It only takes effect when smoothing is disabled, e.g.
  /// `config: StreamingPresets.instant` or `StreamingTextConfig(smoothingEnabled: false)`.
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

  /// When `true`, already-settled Markdown blocks are parsed once and reused
  /// instead of re-parsed on every streaming frame (see
  /// [IncrementalMarkdownBody]). This keeps per-frame cost proportional to the
  /// active block rather than the whole response, which matters for long
  /// answers. Defaults to `false`; the settled output renders identically
  /// either way, so this is a pure performance switch.
  final bool incrementalParsing;

  /// When `true`, the words in the paragraph currently being streamed fade in
  /// (opacity only) as they arrive — the calm, per-word effect used by
  /// ChatGPT / Claude. Each word fades over [wordFadeDuration] from the moment
  /// it appears, and finishes its fade even when the paragraph settles or the
  /// stream completes. Settled blocks render through the normal
  /// `MarkdownBody`. Implies incremental rendering. With the platform's
  /// reduce-motion setting on, words appear without a fade.
  ///
  /// The fade applies to plain prose paragraphs (with inline bold/italic/code/
  /// links); code blocks, tables, lists, headings, and blockquotes stream
  /// without a fade. Defaults to `true` — pass `false` for instant text.
  final bool wordFadeIn;

  /// How long each new word takes to fade in when [wordFadeIn] is enabled.
  /// Defaults to 300ms with a strong ease-out. Pass `null` for the
  /// position-based ramp used before 0.6.0 (see [wordFadeWindow]).
  final Duration? wordFadeDuration;

  /// Position-based fade only (`wordFadeDuration: null`): how many trailing
  /// words are graded from dim to opaque. Defaults to 4.
  final int wordFadeWindow;

  /// Tables scroll sideways instead of squeezing their columns into the
  /// available width. Each column is as wide as its content, up to this many
  /// logical pixels; longer cells wrap. Defaults to 320.
  ///
  /// Only applies when [styleSheet] does not set
  /// `MarkdownStyleSheet.tableColumnWidth`. Pass `null` for the old
  /// behaviour: columns share the available width and the table never
  /// scrolls.
  final double? tableColumnMaxWidth;

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
  const _RenderState({required this.text, required this.isDone, this.error});

  final String text;
  final bool isDone;

  /// The error the stream failed with, or `null`.
  final Object? error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _RenderState &&
          other.text == text &&
          other.isDone == isDone &&
          other.error == error);

  @override
  int get hashCode => Object.hash(text, isDone, error);

  _RenderState copyWith({String? text, bool? isDone}) => _RenderState(
        text: text ?? this.text,
        isDone: isDone ?? this.isDone,
        error: error,
      );
}

class _MarkdownStreamState<T> extends State<MarkdownStream<T>> {
  final StringBuffer _raw = StringBuffer();
  // Bumped on every rendered-text change; lets a blinking cursor stay solid
  // while text is arriving (see CursorActivity).
  final ValueNotifier<int> _textChanges = ValueNotifier<int>(0);
  final ValueNotifier<_RenderState> _state =
      ValueNotifier<_RenderState>(const _RenderState(text: '', isDone: false));
  StreamSubscription<T>? _sub;
  Timer? _debounceTimer;
  bool _pendingRender = false;
  bool _paused = false;

  /// Paces the raw buffer into a steadily-revealed prefix when
  /// [StreamingTextConfig.smoothingEnabled] is set. `null` when smoothing is
  /// off (the default), in which case the debounce path is used instead.
  OutputSmoother? _smoother;
  StreamSubscription<String>? _smoothSub;

  StreamingTextController? get _controller => widget.controller;

  /// When no [StreamingTextConfig] is supplied, the package defaults to a
  /// smooth (paced) feel. An explicit config always wins — including one with
  /// `smoothingEnabled: false` to opt back out.
  static const StreamingTextConfig _kDefaultConfig =
      StreamingTextConfig(smoothingEnabled: true, charsPerSecond: 120);

  StreamingTextConfig get _effectiveConfig => widget.config ?? _kDefaultConfig;

  bool get _smoothing => _effectiveConfig.smoothingEnabled;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _setupSmoother();
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
      _teardownSmoother();
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
      _setupSmoother();
      _subscribe(widget.stream);
    } else if (_smoothingConfigChanged(oldWidget)) {
      // Smoothing was toggled (or its rate changed) without a stream swap.
      // Rebuild the smoother against the live buffer so the change takes
      // effect immediately without losing already-received text.
      _teardownSmoother();
      _setupSmoother();
      if (!_state.value.isDone && !_paused) {
        if (_smoothing) {
          _smoother?.push(_raw.toString());
        } else {
          _renderNow();
        }
      }
    }
  }

  bool _smoothingConfigChanged(MarkdownStream<T> oldWidget) {
    // Compare effective configs: a null config means the smoothing default,
    // so swapping `null` for an equivalent explicit config is not a change.
    final a = oldWidget.config ?? _kDefaultConfig;
    final b = _effectiveConfig;
    return a.smoothingEnabled != b.smoothingEnabled ||
        a.charsPerSecond != b.charsPerSecond ||
        a.smoothingMaxBacklogChars != b.smoothingMaxBacklogChars;
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
    if (_smoothing) {
      // Feed the latest buffer so paced reveal picks up where it left off.
      _smoother?.push(_raw.toString());
    } else {
      _renderNow();
    }
  }

  void _handleSkipToEnd() {
    if (_state.value.isDone) return;
    _sub?.cancel();
    _debounceTimer?.cancel();
    _teardownSmoother();
    _paused = false;
    _renderNow(done: true);
    widget.onDone?.call(_raw.toString());
    _controller?.internalSetState(StreamingState.completed);
  }

  void _handleStop() {
    if (_state.value.isDone) return;
    _sub?.cancel();
    _debounceTimer?.cancel();
    _teardownSmoother();
    _paused = false;
    // Keep the currently-rendered text; just mark it as done so the cursor
    // disappears. Do NOT fire onDone — this is an explicit user-cancel.
    _state.value = _state.value.copyWith(isDone: true);
    _controller?.internalSetState(StreamingState.completed);
  }

  void _handleRestart() {
    final factory = widget.streamFactory;
    if (factory == null) {
      // Reported rather than thrown: this runs inside the controller's
      // notifyListeners, where a throw would abort the remaining listeners.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'StreamingTextController.restart() requires MarkdownStream to be '
            'constructed with a streamFactory.',
          ),
          library: 'flutter_markdown_stream',
        ),
      );
      return;
    }
    _sub?.cancel();
    _debounceTimer?.cancel();
    _teardownSmoother();
    _raw.clear();
    _pendingRender = false;
    _paused = false;
    _state.value = const _RenderState(text: '', isDone: false);
    _controller?.internalReset();
    _setupSmoother();
    _subscribe(factory());
  }

  // --- smoothing plumbing ----------------------------------------------------

  void _setupSmoother() {
    if (!_smoothing) return;
    final cfg = _effectiveConfig;
    final mult = _controller?.speedMultiplier ?? 1.0;
    final cps = cfg.charsPerSecond * (mult <= 0 ? 1.0 : mult);
    final s = OutputSmoother(
      charsPerSecond: cps <= 0 ? 1.0 : cps,
      maxBacklogChars: cfg.smoothingMaxBacklogChars,
    );
    _smoother = s;
    _smoothSub = s.revealed.listen(_onRevealed);
  }

  void _teardownSmoother() {
    _smoothSub?.cancel();
    _smoothSub = null;
    _smoother?.dispose();
    _smoother = null;
  }

  /// Called for each paced prefix of the *raw* buffer. We sanitize the
  /// revealed prefix (never the full buffer) so partial syntax inside the
  /// slice is still repaired, then emit it.
  void _onRevealed(String rawPrefix) {
    if (!mounted || _paused || _state.value.isDone) return;
    final latex = widget.latexBuilder != null;
    final text = SafeMarkdownParser.sanitize(rawPrefix, latexEnabled: latex);
    _emitText(text, done: false);
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
    if (_smoothing) {
      _smoother?.push(_raw.toString());
    } else {
      _scheduleRender();
    }
  }

  void _onStreamDone() => _finish();

  void _onStreamError(Object error, StackTrace stackTrace) {
    widget.onError?.call(error, stackTrace);
    _finish(error: error);
  }

  void _finish({Object? error}) {
    _debounceTimer?.cancel();
    // Intentional: on completion we snap straight to the full text rather than
    // letting the smoother drain its backlog over `finishDuration`. Once the
    // stream is done the reader wants the whole answer immediately, not a few
    // more seconds of paced reveal. Tearing the smoother down first also stops
    // a late tick from overwriting the final, fully-rendered text.
    _teardownSmoother();
    _renderNow(done: true, error: error);
    widget.onDone?.call(_raw.toString());
    _controller?.internalSetState(
      error == null ? StreamingState.completed : StreamingState.error,
    );
  }

  Duration get _effectiveDebounce {
    final base = widget.config?.rebuildDebounce ?? widget.rebuildDebounce;
    // Note: when smoothing is active the smoother's own tick drives cadence;
    // this debounce only applies to the non-smoothing path.
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

  void _renderNow({bool done = false, Object? error}) {
    _pendingRender = false;
    if (!mounted) return;
    final raw = _raw.toString();
    final latex = widget.latexBuilder != null;
    final nextText =
        done ? raw : SafeMarkdownParser.sanitize(raw, latexEnabled: latex);
    _emitText(nextText, done: done, error: error);
  }

  /// Single funnel for every render-text update: pushes the new state, mirrors
  /// it onto the controller, and fires [MarkdownStream.onTextChanged].
  void _emitText(String text, {required bool done, Object? error}) {
    _state.value = _RenderState(
      text: text,
      isDone: done,
      error: error ?? _state.value.error,
    );
    _controller?.internalSetCurrentText(text);
    _textChanges.value++;
    widget.onTextChanged?.call(text);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
    _teardownSmoother();
    _detachController(widget.controller);
    _state.dispose();
    _textChanges.dispose();
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
          incrementalParsing: widget.incrementalParsing,
          wordFadeIn: widget.wordFadeIn,
          wordFadeWindow: widget.wordFadeWindow,
          wordFadeDuration: widget.wordFadeDuration,
          tableColumnMaxWidth: widget.tableColumnMaxWidth,
          textDirection: widget.textDirection,
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
          errorBuilder: widget.errorBuilder,
          latexEnabled: widget.latexBuilder != null,
          hasCustomInlineRendering:
              (widget.inlineSyntaxes?.isNotEmpty ?? false) ||
                  widget.builders.keys.any(WordFadeText.renderedTags.contains),
          fadeInEnabled: config?.fadeInEnabled ?? false,
          fadeInDuration:
              config?.fadeInDuration ?? const Duration(milliseconds: 300),
          fadeInCurve: config?.fadeInCurve ?? kStreamEaseOut,
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
    return CursorActivity(changes: _textChanges, child: tree);
  }
}

/// Render widget for the current [_RenderState]. Stateful so it can own the
/// [AnimationController] used for the trailing fade-out when the stream
/// completes.
class _MarkdownBodyWithCursor extends StatefulWidget {
  const _MarkdownBodyWithCursor({
    required this.state,
    required this.incrementalParsing,
    required this.wordFadeIn,
    required this.wordFadeWindow,
    required this.wordFadeDuration,
    required this.tableColumnMaxWidth,
    required this.textDirection,
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
    required this.errorBuilder,
    required this.latexEnabled,
    required this.hasCustomInlineRendering,
    required this.fadeInEnabled,
    required this.fadeInDuration,
    required this.fadeInCurve,
    required this.trailingFadeHeight,
  });

  final _RenderState state;
  final bool incrementalParsing;
  final bool wordFadeIn;
  final int wordFadeWindow;
  final Duration? wordFadeDuration;
  final double? tableColumnMaxWidth;
  final TextDirection? textDirection;
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
  final MarkdownStreamErrorBuilder? errorBuilder;
  final bool latexEnabled;

  /// Whether the caller supplied inline syntaxes or builders for inline tags
  /// that [WordFadeText] cannot reproduce; the fading tail is skipped then.
  final bool hasCustomInlineRendering;
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
    if (!widget.fadeInEnabled || widget.wordFadeIn) {
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
    // The word fade already fades the newest text; masking the bottom edge
    // on top of it greys out the whole last line and hides the word fade.
    if (widget.wordFadeIn) return child;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    _ensureController();
    final ctrl = _fadeController!;
    return AnimatedBuilder(
      animation: ctrl,
      child: child,
      builder: (context, inner) {
        // The mask dissolves by running the controller in reverse. Applying
        // the curve to the reversed value would turn an ease-out into an
        // ease-in, so the flipped curve is used on the way out.
        final curve = ctrl.status == AnimationStatus.forward
            ? widget.fadeInCurve
            : widget.fadeInCurve.flipped;
        final t = curve.transform(ctrl.value);
        if (t <= 0) return inner!;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final h = bounds.height;
            if (h <= 0) {
              return const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
              ).createShader(bounds);
            }
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

  // Inline syntaxes and builders for the current frame, including the cursor
  // syntax while a cursor is shown. Set at the top of [build].
  List<md.InlineSyntax>? _inlineSyntaxes;
  Map<String, MarkdownElementBuilder> _builders =
      const <String, MarkdownElementBuilder>{};

  /// Builds a `MarkdownBody` for [data] with the current styling. Used both
  /// for the whole text and, under incremental parsing, for each slice.
  Widget _buildBody(String data) => MarkdownBody(
        data: data,
        selectable: widget.selectable,
        styleSheet: _bodyStyleSheet(),
        styleSheetTheme: widget.styleSheetTheme,
        syntaxHighlighter: widget.syntaxHighlighter,
        onTapLink: widget.onTapLink,
        onTapText: widget.onTapText,
        imageDirectory: widget.imageDirectory,
        blockSyntaxes: widget.blockSyntaxes,
        inlineSyntaxes: _inlineSyntaxes,
        extensionSet: widget.extensionSet,
        imageBuilder: widget.imageBuilder,
        checkboxBuilder: widget.checkboxBuilder,
        bulletBuilder: widget.bulletBuilder,
        builders: _builders,
        paddingBuilders: widget.paddingBuilders,
        listItemCrossAxisAlignment: widget.listItemCrossAxisAlignment,
        fitContent: widget.fitContent,
        shrinkWrap: widget.shrinkWrap,
        softLineBreak: widget.softLineBreak,
      );

  /// [MarkdownStream.styleSheet] with scrollable table columns, unless the
  /// caller chose a column width or turned scrolling off.
  MarkdownStyleSheet? _bodyStyleSheet() {
    final maxWidth = widget.tableColumnMaxWidth;
    final sheet = widget.styleSheet;
    if (maxWidth == null || sheet?.tableColumnWidth != null) return sheet;
    return (sheet ?? MarkdownStyleSheet()).copyWith(
      tableColumnWidth: _CappedIntrinsicColumnWidth(maxWidth),
      // copyWith drops this field when it is not passed again.
      tableScrollbarThumbVisibility: sheet?.tableScrollbarThumbVisibility,
    );
  }

  /// Resolves the style sheet `MarkdownBody` itself would use, so the fading
  /// tail is styled exactly like the same paragraph once it settles.
  MarkdownStyleSheet _resolvedStyleSheet(BuildContext context) {
    final useCupertino = switch (widget.styleSheetTheme) {
      MarkdownStyleSheetBaseTheme.cupertino => true,
      MarkdownStyleSheetBaseTheme.platform =>
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS,
      _ => false,
    };
    final base = useCupertino
        ? MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context))
        : MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.merge(widget.styleSheet);
  }

  /// Whether the active paragraph [data] can be rendered by [WordFadeText]
  /// without losing anything `MarkdownBody` would show.
  bool _canFade(String data) =>
      !widget.hasCustomInlineRendering &&
      !(widget.latexEnabled && data.contains(r'$')) &&
      WordFadeText.isSimpleParagraph(data);

  /// Builds the active (streaming) paragraph with a per-word fade when it is a
  /// plain paragraph; otherwise falls back to a normal MarkdownBody.
  Widget _buildFadingTail(BuildContext context, String data) {
    final hasCursor = data.endsWith(_kCursorSentinel);
    final text = hasCursor
        ? data.substring(0, data.length - _kCursorSentinel.length)
        : data;
    if (!_canFade(text)) return _buildBody(data);
    final sheet = _resolvedStyleSheet(context);
    return WordFadeText(
      text: text,
      baseStyle: sheet.p ?? DefaultTextStyle.of(context).style,
      styleSheet: sheet,
      isDone: widget.state.isDone,
      textDirection: widget.textDirection,
      fadeWindow: widget.wordFadeWindow,
      fadeDuration: widget.wordFadeDuration,
      trailing: hasCursor ? widget.cursorWidget : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final streaming = !widget.state.isDone;
    final cursor = streaming ? widget.cursorWidget : null;
    var data = SafeMarkdownParser.escapeSingleTildes(
      widget.state.text,
      latexEnabled: widget.latexEnabled,
    );
    if (cursor != null) {
      data = _appendCursorSentinel(data);
      _inlineSyntaxes = <md.InlineSyntax>[
        _CursorSyntax(),
        ...?widget.inlineSyntaxes,
      ];
      _builders = <String, MarkdownElementBuilder>{
        ...widget.builders,
        _kCursorTag: _CursorBuilder(cursor),
      };
    } else {
      _inlineSyntaxes = widget.inlineSyntaxes;
      _builders = widget.builders;
    }

    final Widget body;
    if (widget.wordFadeIn || widget.incrementalParsing) {
      // One keyed MarkdownBody per top-level block. The same structure is
      // kept after the stream completes, so finishing does not re-parse the
      // whole response or rebuild the settled blocks.
      body = IncrementalMarkdownBody(
        data: data,
        sliceBuilder: _buildBody,
        tailBuilder: widget.wordFadeIn
            ? (tail) => _buildFadingTail(context, tail)
            : null,
        blockSpacing: widget.styleSheet?.blockSpacing ?? 8,
        // A paragraph keeps its fading renderer until its last word has
        // finished fading, then switches to MarkdownBody, so neither a new
        // paragraph nor completion makes the last words snap to full opacity.
        tailSettled: !streaming,
        settleDuration: widget.wordFadeDuration ?? Duration.zero,
      );
    } else {
      body = _buildBody(data);
    }
    final faded = _applyFade(body);

    final error = widget.state.error;
    final errorBuilder = widget.errorBuilder;
    if (error == null || errorBuilder == null) return faded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[faded, errorBuilder(context, error)],
    );
  }
}

/// Sizes a table column to its widest cell, capped at [maxWidth] so long
/// cells wrap. Extends [IntrinsicColumnWidth] because `MarkdownBody` only
/// puts a table in a horizontal scroll view for intrinsic or fixed widths.
/// Equality by value keeps `MarkdownBody` from re-parsing on every rebuild.
class _CappedIntrinsicColumnWidth extends IntrinsicColumnWidth {
  const _CappedIntrinsicColumnWidth(this.maxWidth);

  final double maxWidth;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final widest = super.maxIntrinsicWidth(cells, containerWidth);
    if (widest <= maxWidth) return widest;
    // Never narrower than the longest unbreakable word.
    final narrowest = super.minIntrinsicWidth(cells, containerWidth);
    return narrowest > maxWidth ? narrowest : maxWidth;
  }

  @override
  bool operator ==(Object other) =>
      other is _CappedIntrinsicColumnWidth && other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(_CappedIntrinsicColumnWidth, maxWidth);
}

/// Marks where the cursor goes in the projected text. Starts with a Unicode
/// punctuation character so an emphasis closer right before it (`_word_`)
/// still counts as right-flanking; the private-use second character makes a
/// collision with real model output practically impossible.
const String _kCursorSentinel = '⸻';

const String _kCursorTag = 'x-stream-cursor';

// A last line that cannot hold inline content: a table row, a thematic break
// or setext underline, or display math.
final RegExp _kBlockOnlyLine = RegExp(r'^\s*(\||\$\$|[-=*_](\s*[-=*_])*\s*$)');

/// Appends the cursor sentinel so the cursor renders inline after the last
/// character — or, when the text ends with a block that cannot hold inline
/// content (a closed code fence, a table, a rule), as its own paragraph.
String _appendCursorSentinel(String text) {
  if (text.isEmpty) return _kCursorSentinel;
  if (text.endsWith('\n')) return '$text\n$_kCursorSentinel';
  final lastLine = text.substring(text.lastIndexOf('\n') + 1);
  if (_kBlockOnlyLine.hasMatch(lastLine)) return '$text\n\n$_kCursorSentinel';
  return '$text$_kCursorSentinel';
}

class _CursorSyntax extends md.InlineSyntax {
  _CursorSyntax() : super(RegExp.escape(_kCursorSentinel));

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty(_kCursorTag));
    return true;
  }
}

class _CursorBuilder extends MarkdownElementBuilder {
  _CursorBuilder(this.cursor);

  final Widget cursor;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Returned as text so MarkdownBody merges it into the paragraph's
    // RichText, placing the cursor right after the last character.
    return Text.rich(
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: cursor),
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
