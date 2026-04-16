import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'safe_markdown_parser.dart';

/// Signature for a convenience builder that renders a fenced code block.
typedef CodeBlockBuilder = Widget Function(String code, String language);

/// Signature for the `onDone` callback.
typedef MarkdownStreamDoneCallback = void Function(String fullText);

/// Extractor: turn a typed chunk [T] into plain Markdown text.
typedef ChunkToText<T> = String Function(T chunk);

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
/// [StreamAdapters] — it decodes/parses the stream upstream of the widget.
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
  final Duration rebuildDebounce;

  /// Optional convenience builder for fenced (block) code only.
  ///
  /// If [builders] also contains a `'code'` entry, the entry in [builders]
  /// wins.
  final CodeBlockBuilder? codeBuilder;

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

  @override
  void initState() {
    super.initState();
    _subscribe(widget.stream);
  }

  @override
  void didUpdateWidget(covariant MarkdownStream<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _sub?.cancel();
      _debounceTimer?.cancel();
      _raw.clear();
      _pendingRender = false;
      _state.value = const _RenderState(text: '', isDone: false);
      _subscribe(widget.stream);
    }
  }

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
    _scheduleRender();
  }

  void _onStreamDone() {
    _debounceTimer?.cancel();
    _renderNow(done: true);
    widget.onDone?.call(_raw.toString());
  }

  void _onStreamError(Object _, StackTrace __) {
    _onStreamDone();
  }

  void _scheduleRender() {
    if (_pendingRender) return;
    _pendingRender = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.rebuildDebounce, _renderNow);
  }

  void _renderNow({bool done = false}) {
    _pendingRender = false;
    if (!mounted) return;
    final raw = _raw.toString();
    final nextText = done ? raw : SafeMarkdownParser.sanitize(raw);
    _state.value = _state.value.copyWith(text: nextText, isDone: done);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
    _state.dispose();
    super.dispose();
  }

  Map<String, MarkdownElementBuilder> _effectiveBuilders() {
    final cb = widget.codeBuilder;
    if (cb == null) return widget.builders;
    if (widget.builders.containsKey('code')) return widget.builders;
    return <String, MarkdownElementBuilder>{
      'code': _CustomCodeBuilder(cb),
      ...widget.builders,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          blockSyntaxes: widget.blockSyntaxes,
          inlineSyntaxes: widget.inlineSyntaxes,
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
        ),
      ),
    );
  }
}

/// Pure, stateless render of the current [_RenderState].
class _MarkdownBodyWithCursor extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final body = MarkdownBody(
      data: state.text,
      selectable: selectable,
      styleSheet: styleSheet,
      styleSheetTheme: styleSheetTheme,
      syntaxHighlighter: syntaxHighlighter,
      onTapLink: onTapLink,
      onTapText: onTapText,
      imageDirectory: imageDirectory,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      fitContent: fitContent,
      shrinkWrap: shrinkWrap,
      softLineBreak: softLineBreak,
    );

    if (state.isDone || cursorWidget == null) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        body,
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: cursorWidget,
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
