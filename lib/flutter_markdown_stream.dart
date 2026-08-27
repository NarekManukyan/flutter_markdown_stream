/// Flicker-free, crash-safe streaming Markdown widget for Flutter.
///
/// Drop [MarkdownStream] into any widget tree, give it a `Stream<String>`
/// of token chunks (e.g. from an LLM), and it will render the Markdown
/// progressively — handling unclosed bold, code fences, links, and headers
/// gracefully along the way.
library;

// Re-export the transitive packages whose types appear in MarkdownStream's
// public API (MarkdownStyleSheet, MarkdownElementBuilder, BlockSyntax, …) so
// consumers don't need to add flutter_markdown_plus / markdown to their own
// pubspec just to name a parameter type.
export 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
export 'package:markdown/markdown.dart'
    show BlockSyntax, ExtensionSet, InlineSyntax;

export 'src/auto_scroll.dart'
    show AutoScroll, AutoScrollState, StickToBottomController;
export 'src/code_block_view.dart' show CodeBlockView;
export 'src/cursors.dart'
    show
        BarCursor,
        BlinkingCursor,
        FadingCursor,
        PulsingCursor,
        ShimmerCursor,
        SpinnerCursor,
        TypingDotsCursor,
        WaveDotsCursor;
export 'src/incremental_markdown_body.dart'
    show IncrementalMarkdownBody, MarkdownSliceBuilder;
export 'src/latex_syntax.dart'
    show
        LaTeXBlockSyntax,
        LaTeXBuilder,
        LaTeXElementBuilder,
        LaTeXInlineSyntax,
        kLatexTag;
export 'src/markdown_stream.dart'
    show
        ChunkToText,
        CodeBlockBuilder,
        MarkdownStream,
        MarkdownStreamDoneCallback,
        MarkdownStreamFactory;
export 'src/output_smoother.dart' show OutputSmoother;
export 'src/safe_markdown_parser.dart' show SafeMarkdownParser;
export 'src/stream_adapters.dart' show StreamAdapters;
export 'src/streaming_config.dart' show StreamingPresets, StreamingTextConfig;
export 'src/word_fade.dart' show WordFadeText;
export 'src/streaming_text_controller.dart'
    show
        StreamingCommand,
        StreamingCommandKind,
        StreamingState,
        StreamingStateCallback,
        StreamingStateExtension,
        StreamingTextController;
