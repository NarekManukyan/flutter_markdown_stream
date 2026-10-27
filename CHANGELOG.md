# Changelog

## 0.6.1

Documentation only. No code changes.

- New README demo recorded from the example's "Chat features" screen, a
  "What's new in 0.6.0" summary, and a GIF of the thinking section.
- The README's media no longer ships in the package, so the download is
  smaller.
- The example's "Chat features" screen streams a longer answer with a table
  and a code block.

## 0.6.0

Chat-app essentials (static messages, thinking sections, a first-token
placeholder and a link policy), correctness and rendering fixes, per-block
rendering for long answers, and calmer streaming motion.

### Migrating from 0.5.x

No code changes are required for most apps. Check these if they apply:

- **Cursor position.** `cursorWidget` now renders inline after the last
  character instead of on its own line. A tall or wide custom cursor (for
  example a typing-dots row) now affects the height of the last text line. If
  you want it below the text, render it yourself under `MarkdownStream` while
  the stream is active and leave `cursorWidget` null.
- **Widget tests that count `MarkdownBody`.** With `wordFadeIn` (the default)
  or `incrementalParsing`, there is one `MarkdownBody` per top-level block,
  during streaming and after completion. `find.byType(MarkdownBody)` no
  longer finds exactly one widget for multi-block text. Finders on text
  (`find.text`, `find.textContaining`) are unaffected.
  `IncrementalMarkdownBody` always returns a `Column`, even for one block.
- **`StreamingTextController.restart()` without a `streamFactory`** no longer
  throws from the controller. The `StateError` goes to `FlutterError.onError`
  and the call does nothing. Code that caught the exception should pass a
  `streamFactory` instead.
- **Partial links** show their label while the URL is still streaming.
  Snapshot or golden tests that captured mid-stream frames with a half-typed
  link need updating.
- **Stream errors.** `onDone` still fires after an error, as before. The
  controller now ends in `StreamingState.error` rather than `completed`, so
  code that waits for `completed` after an error should also accept `error`
  (`StreamingState.isFinished` covers both).
- **Word fade timing.** Each word now fades in over `wordFadeDuration` (300ms)
  from the moment it arrives, instead of by its distance from the end of the
  text. Pass `wordFadeDuration: null` to keep the 0.5 behaviour.
- **Links and images are filtered.** The new `linkPolicy` allows `http`,
  `https` and `mailto` links, relative links and `http`/`https` images by
  default. Links with any other scheme (including custom app schemes) render
  as plain text and no longer reach `onTapLink`, and other images show their
  alt text. Relative image paths are blocked unless `imageDirectory` is set.
  Add your schemes with `LinkPolicy(linkSchemes: {...})`, or pass
  `linkPolicy: null` for the old behaviour.
- **`<think>` sections.** A response that starts with `<think>` or
  `<thinking>` now renders that part as a collapsible thinking section
  instead of text. Pass `parseThinking: false` to keep the tags as text.
- **Tables scroll sideways.** Columns now size to their content (up to
  `tableColumnMaxWidth`, 320 by default) and a wide table scrolls
  horizontally, so a narrow table no longer stretches to the full width. Pass
  `tableColumnMaxWidth: null`, or set `MarkdownStyleSheet.tableColumnWidth`,
  to keep the old flex columns.
- **Edge fade and word fade.** `StreamingTextConfig.fadeInEnabled` (used by
  the `chatGPT`, `claude`, `gentle`, `fast` and `smooth` presets) now only
  draws when `wordFadeIn` is `false`. With the word fade on, the edge mask
  greyed out the whole last line on top of it. Set `wordFadeIn: false` to keep
  the edge fade.
- **Default curves and presets.** `StreamingTextConfig.fadeInCurve` now
  defaults to a strong ease-out (`Cubic(0.23, 1, 0.32, 1)`), and the `claude`
  preset fades over 300ms instead of 400ms. Set `fadeInCurve` and
  `fadeInDuration` explicitly if you depend on the old values.

### Chat features

- `MarkdownStream.text(data: ...)` renders a finished message with the same
  widget tree and styling as a completed stream, for earlier messages in a
  chat. No fake stream needed.
- `initialText` shows text at once before the stream starts, for resuming an
  interrupted answer. The smoother treats it as already revealed.
- Thinking sections: a leading `<think>…</think>` (or `<thinking>`) renders
  as a `ThinkingBlock`, a "Thinking…" header that is open while the model
  thinks and folds to "Thought for 12s" when the answer starts. Half-typed
  tags are hidden while streaming. Customise it with `thinkingBuilder`, which
  gets a `ThinkingState` with the text, whether it is active, the elapsed time
  and the rendered content.
- `placeholder` is shown until the first chunk arrives and cross-fades to the
  text. `ShimmerText` is a ready-made "Thinking…" line for it.
- `LinkPolicy` keeps `javascript:`, `data:`, `file:` and other unexpected
  links and images out of model output, including disguised schemes
  (`javascript&#58;`, `java\tscript:`) and reference-style definitions.

### Motion

- Words fade in on a frame-synced clock, so the last words of a chunk finish
  fading while the stream stalls instead of staying dim until more text comes.
- A paragraph that has just finished keeps its word fade until its last word
  is opaque, then swaps to `MarkdownBody`. The same happens when the stream
  completes. Both used to snap the remaining faint words to full opacity.
- `BlinkingCursor` and `BarCursor` stay solid while text is arriving and only
  blink while the stream waits, like a caret while you type.
- The code block's Copy button cross-fades its icon and label (with a slight
  scale on the icon) and animates its width, instead of swapping instantly.
- The trailing edge fade uses the mirrored curve when it fades out, so it
  eases out in both directions.
- With reduce motion turned on (`MediaQuery.disableAnimations`), the word fade,
  the trailing edge fade and the Copy button transitions are skipped, and
  `AutoScroll` jumps to the bottom instead of animating.
- The trailing edge fade is skipped while the word fade is on, so the two no
  longer stack.
- Presets no longer use ease-in-out curves: `gentle` keeps 500ms with the
  default ease-out, `smooth` and `claude` use the default curve.

### Fixed — sanitizer

- A single `~` between digits (`20~25 and 30~40`) is shown as a tilde instead
  of turning the text between two ranges into strikethrough. `~~` still
  strikes, and code, URLs and math are left alone.
- Delimiters inside inline code, backslash escapes, bare URLs and link
  destinations no longer get a stray closer appended (`` `a*b` ``,
  `https://x.com/_id`, `\*`, `` `$HOME` `` with LaTeX on).
- Code spans of any backtick length are matched (``` ``foo`bar`` ```).
- An opener in an earlier, finished paragraph, list item or heading no longer
  gets a closer appended at the very end of the text.
- An unclosed emphasis run before a code block no longer corrupts the fence
  line below it.
- Closers are appended innermost-first (`~~a **b` → `~~a **b**~~`).
- Fences indented inside list items are recognised and closed at the same
  indentation. A fence line with an info string no longer closes a block.
- Emphasis characters inside LaTeX math are ignored.

### Changed

- A partially-typed link shows its label as plain text until the URL completes
  (`see [docs](ht` → `see docs`) instead of hiding it. Partial images,
  including `![alt` before the `](`, are still hidden.
- The cursor is now rendered **inline**, right after the last character. After
  a code block, table or rule it sits on its own line below.
- With `wordFadeIn` or `incrementalParsing`, the text is rendered as one keyed
  `MarkdownBody` per top-level block, and this structure is kept after the
  stream completes. Finishing no longer re-parses the whole response, and
  settled blocks are spaced with the style sheet's `blockSpacing`.
- Block splitting no longer separates items of a loose list or an indented
  continuation from its list item, and text with link-reference or footnote
  definitions is kept in one block.
- `StreamingTextController.restart()` without a `streamFactory` reports the
  error through `FlutterError.reportError` instead of throwing inside the
  controller's listener.

### Fixed — rendering

- Tables wider than the screen scroll horizontally instead of squeezing every
  column. Display math (`$$…$$`) from `latexBuilder` scrolls horizontally
  instead of overflowing.
- `AutoScroll` follows a `trigger` even when nothing else schedules a frame.
- Already-settled blocks now pick up a new `styleSheet` (e.g. a theme switch
  mid-stream).
- The word-faded paragraph uses the resolved style sheet for bold, italic,
  strikethrough and inline code, so it no longer changes look when it settles.
  It also parses GitHub-flavoured inline syntax (`~~`) like `MarkdownBody`.
- Paragraphs with links, URLs or images, LaTeX (when enabled), custom inline
  syntaxes or custom inline builders skip the word fade and render through
  `MarkdownBody`, so links stay tappable and custom rendering is not bypassed.
- A stream error now leaves the controller in `StreamingState.error` (it was
  overwritten with `completed`).
- Swapping `config: null` for an equivalent explicit smoothing config no
  longer restarts the smoother.

### Added

- `onError` callback and `errorBuilder` for stream errors.
- `WordFadeText.styleSheet`, `WordFadeText.trailing` and
  `WordFadeText.renderedTags`.
- `IncrementalMarkdownBody.blockSpacing`.
- `MarkdownStream.wordFadeDuration`, `WordFadeText.fadeDuration` and
  `WordFadeText.fadeCurve`.
- `MarkdownStream.text`, `MarkdownStream.initialText`,
  `MarkdownStream.placeholder`, `MarkdownStream.parseThinking`,
  `MarkdownStream.thinkingBuilder` and `MarkdownStream.linkPolicy`.
- `LinkPolicy`, `ThinkingBlock`, `ThinkingState`, `ThinkingBuilder` and
  `ShimmerText`.
- `OutputSmoother(initialText: ...)`.
- `MarkdownStream.tableColumnMaxWidth`.
- `SafeMarkdownParser.escapeSingleTildes`.
- `IncrementalMarkdownBody.settleDuration` and
  `IncrementalMarkdownBody.tailSettled`.

## 0.5.0

New streaming feel, chat-UI helpers, performance, and correctness fixes.

### Behaviour changes (defaults now animated)

- `MarkdownStream` now **smooths and word-fades by default**, for a
  ChatGPT/Claude-style feel out of the box:
  - **Output smoothing** is on when no `config` is supplied.
  - **`wordFadeIn` defaults to `true`.**
  - Opt back to instant text with
    `MarkdownStream(wordFadeIn: false, config: StreamingPresets.instant)`.
- `StreamingPresets.chatGPT` / `.claude` also enable smoothing.

### Streaming feel

- **Per-word fade-in (`wordFadeIn`)**: the words in the paragraph currently
  being streamed fade opacity 0→1 as they arrive (the calm, per-word effect
  used by ChatGPT/Claude — opacity only, no blur). Settled blocks render at
  full fidelity; everything is opaque once the stream completes. Tune with
  `wordFadeWindow`; `WordFadeText` is exported for standalone use.
- **Output smoothing (`OutputSmoother`)**: a paced character-reveal buffer that
  drains bursty token delivery at a steady rate. Configure via
  `StreamingTextConfig(smoothingEnabled: …, charsPerSecond: …)` or
  `StreamingPresets.smooth`. Backlog past `smoothingMaxBacklogChars`
  accelerates so a finished stream never lags.
- **Trailing fade** (`fadeInEnabled`) remains available as an opt-in bottom-edge
  gradient, separate from the per-word fade.

### Widgets

- **`AutoScroll` / `StickToBottomController`**: opt-in, runtime-toggleable
  stick-to-bottom scrolling modelled on Claude's mobile chat — follows the
  bottom only while the user is already there, disengages the moment they
  scroll up (never yanks back), and exposes a "jump to latest" state. Disabled
  by default at the package level; `MarkdownStream` never force-scrolls on its
  own.
  - **Auto-follows content growth automatically** via
    `ScrollMetricsNotification` — no `trigger` needed, even while a
    `MarkdownStream` streams inside it (`trigger` remains as an optional
    fallback).
  - Follows by **jumping** while content grows (an animated follow lags behind
    a fast stream); imperative `animateToBottom()` stays available for a
    user-tapped "jump to latest" button.
- **`CodeBlockView`** (+ `CodeBlockView.builder()`): a polished default fenced
  code block with a language label and copy-to-clipboard button, theme-aware
  and horizontally scrollable. Use as `MarkdownStream(codeBuilder:
  CodeBlockView.builder())`. Optional `highlightBuilder`
  (`CodeHighlightBuilder`) plugs in your own syntax highlighter without adding
  a dependency; the copy control carries a proper button + tap semantics.

### Performance

- **Incremental parsing** (`MarkdownStream(incrementalParsing: true)`,
  `IncrementalMarkdownBody`): settled blocks are parsed once and reused instead
  of re-parsed every frame, keeping per-frame cost proportional to the active
  block rather than the whole response. Off by default; settled output is
  identical.

### Sanitizer correctness

- Emphasis balancing is now **flanking-aware**: spaced asterisks (`a * b`),
  bullet markers (`* one`), thematic breaks (`***`), and arithmetic
  (`2 * 3 = 6`) are no longer given spurious trailing markers, while genuinely
  unclosed emphasis (`**bold`) is still closed.
- Strikethrough (`~~`) uses the same flanking discipline (`x ~~ y` is left
  alone).
- LaTeX currency fix: with `latexEnabled`, `costs $5 today` is no longer
  mis-paired into inline math; a `$` opens math only when followed by
  non-whitespace, non-digit.
- **GFM table repair**: an incomplete trailing table row is hidden from the
  projection until it completes, instead of rendering as a broken table.

### Accessibility & tooling

- All 8 cursors are wrapped in `ExcludeSemantics` and accept an optional
  `semanticLabel` (e.g. `'Assistant is typing'`) for a single announced node.
- New `onTextChanged` callback on `MarkdownStream` reports the current
  projected text each frame (drive auto-scroll triggers or counters without a
  controller).
- Bumped `flutter_lints` to `^5.0.0`.

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
