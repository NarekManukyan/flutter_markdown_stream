/// Flicker-free, crash-safe streaming Markdown widget for Flutter.
///
/// Drop [MarkdownStream] into any widget tree, give it a `Stream<String>`
/// of token chunks (e.g. from an LLM), and it will render the Markdown
/// progressively — handling unclosed bold, code fences, links, and headers
/// gracefully along the way.
library flutter_markdown_stream;

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
export 'src/markdown_stream.dart'
    show ChunkToText, CodeBlockBuilder, MarkdownStream, MarkdownStreamDoneCallback;
export 'src/safe_markdown_parser.dart' show SafeMarkdownParser;
export 'src/stream_adapters.dart' show StreamAdapters;
