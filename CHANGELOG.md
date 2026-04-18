# Changelog

## 0.4.0

- **Re-exported transitive types**: `flutter_markdown_stream` now re-exports
  `flutter_markdown_plus` and the relevant symbols from `markdown`
  (`BlockSyntax`, `InlineSyntax`, `ExtensionSet`) from its main library.
  Consumers that name types like `MarkdownStyleSheet`,
  `MarkdownElementBuilder`, `SyntaxHighlighter`, or `BlockSyntax` no longer
  need to add `flutter_markdown_plus` / `markdown` to their own pubspec —
  a single import of `package:flutter_markdown_stream/flutter_markdown_stream.dart`
  is enough.

## 0.3.0

- **`StreamingTextController`**: programmatic playback control for
  `MarkdownStream`. Call `pause()`, `resume()`, `skipToEnd()`, `stop()`, or
  `restart()` (the latter requires a `streamFactory`). Exposes a
  `StreamingState` enum (`idle`, `streaming`, `paused`, `completed`,
  `error`), live `currentText` / `chunkCount`, an `onStateChanged` and
  `onCompleted` callback, and a `speedMultiplier` that compresses or
  stretches the effective rebuild debounce.
- **`StreamingTextConfig` and `StreamingPresets`**: bundle the rebuild
  debounce and fade settings into a single value. Named presets:
  `chatGPT`, `claude`, `instant`, `typewriter`, `gentle`, `fast`. Supply a
  preset directly:

  ```dart
  MarkdownStream(stream: s, config: StreamingPresets.claude)
  ```
- **Trailing-fade effect**: opt-in via `config.fadeInEnabled`. A bottom-edge
  gradient softens newly-arriving content while streaming and animates
  away over `fadeInDuration` on `onDone`.
- **LaTeX support**: supply a `latexBuilder` to `MarkdownStream` to render
  inline (`$…$`) and block (`$$…$$`) math expressions via your preferred
  renderer (e.g. `flutter_math_fork`). No math dependency is added to the
  package — bring your own. Includes `LaTeXBlockSyntax`,
  `LaTeXInlineSyntax`, `LaTeXElementBuilder`, and a new `latexEnabled`
  flag on `SafeMarkdownParser.sanitize()` for delimiter balancing during
  streaming.
- **RTL / `textDirection`**: wrap rendered output in a `Directionality`
  when `textDirection` is set, enabling Arabic, Hebrew, and similar
  right-to-left scripts without external widgets.

All additions are non-breaking and opt-in. No new pub dependencies.

## 0.2.0

- **Breaking**: Migrated from the discontinued `flutter_markdown` to
  `flutter_markdown_plus` (the official successor maintained by Foresight Mobile).
  - `sizedImageBuilder` parameter renamed to `imageBuilder`.
  - `MarkdownSizedImageBuilder` typedef replaced by `MarkdownImageBuilder`
    (signature changed from `(Uri, MarkdownImageConfig)` to `(Uri, String?, String?)`).
- Shortened package description to comply with pub.dev 60–180 character guideline.

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
