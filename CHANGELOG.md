# Changelog

## 0.1.0

Initial release of `flutter_markdown_stream` (formerly developed under the working
name `flutter_markdown_stream`).

- `MarkdownStream` widget that renders `Stream<String>` of Markdown chunks
  progressively, with a one-frame debounce and optional cursor widget.
- Rebuilds are scoped tightly via `ValueNotifier` + `ValueListenableBuilder`;
  no `setState` in the hot path, so incoming tokens do not invalidate the
  outer widget subtree or restart unrelated animations.
- `MarkdownStream` is generic over the chunk type: `MarkdownStream<T>`
  accepts any `Stream<T>` with a `chunkToText` extractor. `Stream<String>`
  remains the default and requires no extractor.
- `StreamAdapters` utility with three composable converters for common
  non-string stream shapes: `utf8Bytes` (UTF-8 safe across byte splits),
  `serverSentEvents` (multi-chunk-safe SSE parser honouring `[DONE]`),
  and `jsonField` (nested JSON string extraction).
- `SafeMarkdownParser.sanitize` utility that repairs unclosed bold, italic,
  strikethrough, inline code, fenced code blocks, inline links, and
  autolinks mid-stream.
- Full `MarkdownBody` pass-through: `styleSheet`, `styleSheetTheme`,
  `syntaxHighlighter`, `onTapLink`, `onTapText`, `imageDirectory`,
  `blockSyntaxes`, `inlineSyntaxes`, `extensionSet`, `sizedImageBuilder`,
  `checkboxBuilder`, `bulletBuilder`, `builders`, `paddingBuilders`,
  `listItemCrossAxisAlignment`, `fitContent`, `shrinkWrap`, `softLineBreak`,
  `selectable` — anything you can do with `flutter_markdown` you can do
  with `MarkdownStream`.
- `codeBuilder` fires only for fenced (block) code, never for inline code.
  A `builders['code']` entry takes precedence over `codeBuilder` if both
  are supplied.
- Stream errors cancel the subscription cleanly (`cancelOnError: true`) and
  are finalized through the same `onDone` path.
- Family of eight cursor widgets: `BlinkingCursor`, `BarCursor`,
  `FadingCursor`, `PulsingCursor`, `TypingDotsCursor`, `WaveDotsCursor`,
  `SpinnerCursor`, `ShimmerCursor`. All default to the ambient text
  colour, share the same customization shape (`color`, size, `period`),
  and dispose their tickers cleanly.
- `flutter_lints`-clean: zero analyzer issues. Targets Flutter `>=3.27.0`,
  Dart `>=3.6.0`. Uses `Color.withValues(alpha:)` (the `withOpacity`
  successor) and `MarkdownBody.sizedImageBuilder` (the `imageBuilder`
  successor) so the package stays green against current upstream APIs.
- Full unit-test coverage of the sanitizer across adversarial inputs.
- Widget tests cover stream swap, cursor lifecycle, partial code fences.
- Example app demonstrating the widget with a simulated token stream and
  a gallery of every cursor.
