# flutter_markdown_stream

[![pub package](https://img.shields.io/pub/v/flutter_markdown_stream.svg)](https://pub.dev/packages/flutter_markdown_stream)
[![license](https://img.shields.io/github/license/NarekManukyan/flutter_markdown_stream.svg)](LICENSE)

Flicker-free, crash-safe streaming Markdown widget for Flutter. Drop it into your chat UI, point it at a `Stream<String>` of LLM token chunks, and get smooth, progressive Markdown rendering — even when the syntax is half-typed.

## Demo

<p align="center">
  <img src="https://raw.githubusercontent.com/NarekManukyan/flutter_markdown_stream/main/demo/demo.gif"
       alt="A chat answer streaming in: a Thinking placeholder, a thinking section that folds away, then a heading, a list, a table and a code block fading in word by word"
       width="420" />
</p>

*From the example app (`example/`, "Chat features"). The earlier message at the top is `MarkdownStream.text` with its thinking section folded. The new answer shows a placeholder until the first token, streams its thinking section, folds it to "Thought for 6s" when the answer starts, and fades the answer in word by word. The `javascript:` link on the last line renders as plain text.*

## What's new in 0.6.0

- [`MarkdownStream.text`](#earlier-messages-markdownstreamtext) renders earlier messages with the same look as a finished stream, and `initialText` resumes an interrupted answer.
- A [thinking section](#thinking-section) for the `<think>` output of reasoning models, with a "Thinking…" header that becomes "Thought for 6s".
- A [placeholder](#placeholder-before-the-first-token) until the first token arrives, and `ShimmerText` to use as one.
- A [link policy](#safe-links-and-images) that keeps `javascript:`, `data:` and `file:` links and images out of model output.
- Wide tables and display math scroll sideways instead of overflowing, and a single `~` in `20~25` stays a tilde.
- Calmer motion: each word fades in over 300ms with a strong ease-out, the cursor stays solid while text arrives, and with reduce motion on the fades, the shimmer and the auto-scroll animation are off.

Upgrading from 0.5.x? Read the [migration notes](CHANGELOG.md#migrating-from-05x) first. Links with custom schemes and responses that start with `<think>` render differently by default.

## Why?

`flutter_markdown_plus` parses each rebuild from scratch. When an LLM emits `**bold` before the closing `**`, or opens a ` ```dart ` fence before the rest of the code arrives, the widget either throws, flashes, or renders the remainder of your document as code until the closing token appears.

`flutter_markdown_stream` fixes that with a small sanitizer that projects the *current buffer* into a syntactically-safe form at render time, then falls back to the raw buffer once the stream completes.

## Features

- Handles unclosed bold, italic, strikethrough, inline code, fenced code blocks, autolinks, inline links, **incomplete GFM tables**, and LaTeX delimiters mid-stream — with CommonMark-correct flanking rules, so bullet lists, thematic breaks, and stray `*`/`$` in prose are never mangled.
- One-frame debounce coalesces bursts of tokens into a single rebuild, plus optional **output smoothing** that paces bursty tokens into an even, ChatGPT/Claude-style flow.
- **Opt-in `AutoScroll`** stick-to-bottom for chat UIs, modelled on Claude mobile (follows the bottom, disengages when you scroll up, never yanks).
- Ready-made **`CodeBlockView`** with a language label and copy button, or bring your own `codeBuilder`.
- **Chat essentials:** `MarkdownStream.text` for earlier messages, a collapsible **thinking section** for `<think>` output from reasoning models, a **placeholder** until the first token, and a **link policy** that keeps `javascript:`, `data:` and `file:` links out of model output.
- Optional **incremental parsing** for long answers — settled blocks are parsed once, not re-parsed every frame.
- Eight cursor widgets, all screen-reader friendly (`ExcludeSemantics` + optional `semanticLabel`).
- `onTextChanged` for live progress, and a `StreamingTextController` for pause / resume / skip / restart.
- Pure Dart sanitizer — fully unit-tested, zero platform channels.

## Install

```yaml
dependencies:
  flutter_markdown_stream: ^0.6.0
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.stream});
  final Stream<String> stream;

  @override
  Widget build(BuildContext context) {
    return MarkdownStream(
      stream: stream,
      onDone: (fullText) => debugPrint('Finished: $fullText'),
      cursorWidget: const BlinkingCursor(),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
      codeBuilder: (code, language) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          code,
          style: const TextStyle(
            color: Colors.greenAccent,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
```

### Keep the stream instance stable

`MarkdownStream` restarts whenever it gets a different `stream` object: it
cancels the old subscription, clears the text and listens to the new stream.
Creating the stream inside `build` therefore starts the request again on
every rebuild:

```dart
// Wrong: a rebuild (theme change, keyboard, parent setState) re-subscribes
// and the answer starts over.
Widget build(BuildContext context) =>
    MarkdownStream(stream: api.streamAnswer(prompt));
```

Create the stream once, for example in `initState` or in your state
management layer, and pass the same instance on every build. A
`StreamController.broadcast()` or a stored `Stream` both work. To restart on
purpose, pass a new stream (or use `StreamingTextController.restart()` with a
`streamFactory`).

## Chat messages (0.6.0)

### Earlier messages: `MarkdownStream.text`

Render a finished message with the same widget, styling and block spacing
as the answer that just streamed in, without a fake one-event stream:

```dart
MarkdownStream.text(data: message.content, styleSheet: sheet)
```

To resume an interrupted answer, pass what you already have as
`initialText` and stream the rest. It shows at once, without pacing:

```dart
MarkdownStream(stream: resumedStream, initialText: partialAnswer)
```

### Thinking section

Reasoning models (DeepSeek R1, Qwen, QwQ and others) stream a
`<think>…</think>` section before the answer. `MarkdownStream` shows it as a
"Thinking…" header over the thinking text, open while the model thinks. When
the answer starts it folds to "Thought for 12s", and a tap opens it again.
Half-typed tags never show up as text.

<p align="center">
  <img src="https://raw.githubusercontent.com/NarekManukyan/flutter_markdown_stream/main/demo/thinking.gif"
       alt="A shimmering Thinking placeholder, then the thinking text streaming under a Thinking header, which folds to Thought for 6s when the answer starts"
       width="480" />
</p>

```dart
MarkdownStream(stream: llmStream); // on by default

// Your own container; `state.content` is the rendered thinking text.
MarkdownStream(
  stream: llmStream,
  thinkingBuilder: (context, state) => MyThoughts(
    active: state.isActive,
    elapsed: state.elapsed,
    child: state.content,
  ),
);

MarkdownStream(stream: llmStream, parseThinking: false); // leave the tags in
```

### Placeholder before the first token

```dart
MarkdownStream(
  stream: llmStream,
  placeholder: const ShimmerText('Thinking…'),
  cursorWidget: const BlinkingCursor(),
);
```

The placeholder cross-fades to the text when the first chunk arrives.
`ShimmerText` sweeps a soft highlight across its text and stays still when
reduce motion is on.

### Safe links and images

Model output is untrusted input. By default only `http`, `https` and
`mailto` links, relative links, and `http`/`https` images are rendered. A
`javascript:`, `data:` or `file:` link shows as its label in plain text and
never reaches `onTapLink`; a blocked image shows its alt text. Tricks like
`javascript&#58;` or `java\tscript:` are caught too.

```dart
// Also allow your own deep links:
MarkdownStream(
  stream: llmStream,
  linkPolicy: const LinkPolicy(linkSchemes: {'http', 'https', 'myapp'}),
);

MarkdownStream(stream: llmStream, linkPolicy: null); // no filtering
```

Relative image paths are blocked unless you set `imageDirectory`, because
`MarkdownBody` loads them from the local file system.

## Streaming feel & chat-UI helpers (0.5.0)

### Smooth by default

Since 0.5.0, `MarkdownStream` **smooths and word-fades out of the box** — the
ChatGPT/Claude feel with no configuration. For instant, un-animated text:

```dart
MarkdownStream(
  stream: llmStream,
  wordFadeIn: false,
  config: StreamingPresets.instant,
);
```

### Per-word fade-in (`wordFadeIn`)

The words in the paragraph currently being streamed fade in (opacity only, no
blur) as they arrive. Each word fades over `wordFadeDuration` (300ms) with a
strong ease-out, so words finish fading even while the stream pauses. A
finished paragraph, and the last one when the stream completes, keeps fading
until its last word is opaque before it settles. With reduce motion on, words
appear at full opacity.

```dart
MarkdownStream(stream: llmStream);                 // on by default
MarkdownStream(
  stream: llmStream,
  wordFadeDuration: const Duration(milliseconds: 450), // slower fade
);
// The 0.5 position-based ramp (the last `wordFadeWindow` words stay faded):
MarkdownStream(stream: llmStream, wordFadeDuration: null, wordFadeWindow: 6);
```

`BlinkingCursor` and `BarCursor` stay solid while text arrives and blink only
while the stream waits.

It applies to prose (with inline bold/italic/code/links); code blocks, tables,
lists, headings, and blockquotes stream without a fade.

### Output smoothing

Debounce only *coalesces* bursty tokens; smoothing *paces* them, so text flows
at a steady rate no matter how lumpy the network delivery is. It's on by
default; tune or swap the feel with a config or preset:

```dart
MarkdownStream(stream: llmStream, config: StreamingPresets.claude); // or .chatGPT / .smooth
MarkdownStream(
  stream: llmStream,
  config: const StreamingTextConfig(smoothingEnabled: true, charsPerSecond: 140),
);
```

### Auto-scroll (opt-in, Claude-mobile behaviour)

Nothing scrolls unless you ask. Wrap your streaming content in `AutoScroll` and
it follows the bottom while you're already there, disengages the instant you
scroll up to read, and re-engages when you return — it never yanks you down.

Following is **automatic**: `AutoScroll` watches the scrollable's
`ScrollMetricsNotification`, so it re-follows every time the content grows —
including while a `MarkdownStream` streams tokens inside it. You do **not** wire
up a trigger.

```dart
AutoScroll(
  child: Column(
    children: [
      for (final message in messages) MessageBubble(message),
      MarkdownStream(stream: llmStream), // grows → AutoScroll follows
    ],
  ),
);
```

Set `enabled: false` at any time to freeze following without unwrapping.

#### `StickToBottomController`

`AutoScroll` owns its scroll + stick-to-bottom controllers internally. Supply
your own `StickToBottomController` when you need to read its state or drive it
from elsewhere in the tree — e.g. to render a "jump to latest" button:

```dart
final stick = StickToBottomController();

AutoScroll(controller: stick, child: messageColumn);

// Elsewhere: show a button only while the user has scrolled away.
ValueListenableBuilder<bool>(
  valueListenable: stick.showScrollToBottomButtonListenable,
  builder: (context, show, _) => show
      ? FloatingActionButton.small(
          onPressed: stick.jumpToBottom, // not gated by `enabled`
          child: const Icon(Icons.arrow_downward),
        )
      : const SizedBox.shrink(),
);
```

Key surface:

| Member | What it does |
|---|---|
| `bool get isPinnedToBottom` | Whether the view is within `threshold` (default 32px) of the bottom. Tracks reality even while `enabled == false`. |
| `pinnedToBottomListenable` | `ValueListenable<bool>` of the above. |
| `showScrollToBottomButtonListenable` | `ValueListenable<bool>` — `true` only when `enabled` and not pinned. Render your own button from it. |
| `follow({animate})` | Follow to the bottom **if** enabled and currently pinned. Called automatically on content growth. |
| `jumpToBottom()` / `animateToBottom()` | Imperative scroll to bottom and re-pin. **Not** gated by `enabled` (this is a user tapping "jump"). |
| `enabled` (get/set) | Runtime toggle. `false` = transparent passthrough: no following, no button state, never fights the user. |

You can also attach a `StickToBottomController` to your **own** `ScrollView`
(pass its `scrollController`) instead of using `AutoScroll`.

### Code blocks with a copy button

```dart
MarkdownStream(
  stream: llmStream,
  codeBuilder: CodeBlockView.builder(), // language label + copy button
);
```

For syntax highlighting, pass a `highlightBuilder` — bring your own tokenizer
(e.g. `package:highlight` / `package:flutter_highlight`) so this package stays
dependency-free:

```dart
CodeBlockView.builder(
  highlightBuilder: (code, language, baseStyle) {
    // return an InlineSpan (TextSpan tree) with per-token colours
    return myHighlighter.toTextSpan(code, language, baseStyle);
  },
);
```

Code blocks render full width (with the copy control at the top-right) when the
surrounding `MarkdownStream` fills its width — pass `fitContent: false` if your
layout otherwise shrink-wraps.

### Incremental parsing (long answers)

Re-parsing the whole buffer every frame is O(n²) over a long response. Turn on
incremental parsing to render each top-level block as its own keyed
`MarkdownBody`: a block is parsed once when it settles and only the block still
being written is re-parsed per frame. The output is identical; it's a pure
performance switch. (`wordFadeIn`, on by default, uses the same block split.)

```dart
MarkdownStream(stream: llmStream, incrementalParsing: true);
```

### Accessible cursors

```dart
MarkdownStream(
  stream: llmStream,
  cursorWidget: const TypingDotsCursor(semanticLabel: 'Assistant is typing'),
);
```

## Edge cases handled

| Case                              | Input mid-stream              | Rendered safely as     |
| --------------------------------- | ----------------------------- | ---------------------- |
| Unclosed bold                     | `This is **bold`              | `This is **bold**`     |
| Unclosed italic (`*` or `_`)      | `so *cool`                    | `so *cool*`            |
| Unclosed fenced code              | ` ```dart\nfinal x`           | ` ```dart\nfinal x\n``` ` |
| Unclosed inline code              | `run \`dart test`             | `run \`dart test\``    |
| Partial inline link               | `see [docs](ht`               | `see docs`             |
| Partial image                     | `see ![chart](ht`             | `see `                 |
| Partial autolink                  | `visit <https://exa`          | `visit `               |
| Unclosed strikethrough            | `gone ~~away`                 | `gone ~~away~~`        |
| Single `~` in a range             | `20~25 and 30~40`             | plain tildes, no strikethrough |
| Intra-word underscore             | `snake_case_var`              | left alone             |
| Delimiters in code / URLs         | `` `a*b` `` or `x.com/_id`    | left alone             |
| Escaped delimiters                | `\*not bold`                   | left alone             |
| Fence nested in a list            | `` - a\n\n    ```\n    code `` | closed at same indent  |
| CRLF / lone CR line endings       | `a\r\nb`                      | `a\nb`                 |

See `test/safe_markdown_parser_test.dart` for the exhaustive matrix.

## Architecture

The widget keeps two strings:

1. **Raw buffer** — the exact concatenation of every chunk received. This is what `onDone` reports and what's used for the final render once the stream closes.
2. **Rendered projection** — the sanitized form, produced by `SafeMarkdownParser.sanitize(raw)` on every debounced rebuild.

Sanitization is non-destructive: once the closing token (e.g. `**`) arrives in a later chunk, re-sanitizing the now-complete raw buffer naturally produces the correct Markdown, and the synthetic closer added on the previous frame disappears.

Rebuilds are throttled with a `Timer` set to `rebuildDebounce` (default one frame ≈ 16ms). This eliminates the flicker and layout jumps you'd otherwise see when dozens of tokens per second each trigger a rebuild.

## Cursor widgets

Eight built-in cursors, all with the same constructor shape
(`color`, size knobs, `period`) so you can swap them freely:

| Widget              | What it looks like                                      |
| ------------------- | ------------------------------------------------------- |
| `BlinkingCursor`    | Square-wave block; the classic.                         |
| `BarCursor`         | Thin I-beam (traditional text cursor).                  |
| `FadingCursor`      | Block that fades in/out sinusoidally — no hard edges.   |
| `PulsingCursor`     | Circular dot that breathes.                             |
| `TypingDotsCursor`  | Three dots activating in sequence (iMessage style).     |
| `WaveDotsCursor`    | Three dots bouncing in a wave.                          |
| `SpinnerCursor`     | Small circular spinner.                                 |
| `ShimmerCursor`     | Bar with a highlight sliding across it.                 |

```dart
MarkdownStream(
  stream: ...,
  cursorWidget: const PulsingCursor(color: Colors.indigo),
)
```

All cursors default to the ambient `DefaultTextStyle` colour so they match
your theme automatically. Each manages its own `AnimationController` and
disposes it cleanly on unmount — drop them anywhere, including inside
`ListView.builder` items.

You can also supply any custom widget — `cursorWidget` accepts anything.

## Non-string streams

`MarkdownStream` is generic over the chunk type. The common case is
`Stream<String>` — just pass it, no extractor needed:

```dart
MarkdownStream(stream: plainStringStream)
```

For any other chunk type, supply a `chunkToText` function. A few common
shapes:

### Typed SDK chunks (`openai_dart`, `anthropic_sdk_dart`, etc.)

```dart
MarkdownStream<CreateChatCompletionStreamResponse>(
  stream: client.createChatCompletionStream(request: ...),
  chunkToText: (chunk) => chunk.choices.first.delta?.content ?? '',
)
```

### Raw HTTP bytes → SSE → JSON delta

Chain the three `StreamAdapters` — they're composable:

```dart
final http.StreamedResponse response = await client.send(request);

final text = StreamAdapters.jsonField(
  StreamAdapters.serverSentEvents(
    StreamAdapters.utf8Bytes(response.stream),
  ),
  <Object>['choices', 0, 'delta', 'content'],
);

MarkdownStream(stream: text, cursorWidget: const BlinkingCursor())
```

### Anthropic Messages API

```dart
final text = StreamAdapters.jsonField(
  StreamAdapters.serverSentEvents(
    StreamAdapters.utf8Bytes(response.stream),
  ),
  <Object>['delta', 'text'],
);
```

### Pre-parsed JSON events

```dart
MarkdownStream<Map<String, dynamic>>(
  stream: jsonEventStream,
  chunkToText: (event) => event['delta']?['text'] as String? ?? '',
)
```

### What's in `StreamAdapters`

| Adapter              | Does                                                             |
| -------------------- | ---------------------------------------------------------------- |
| `utf8Bytes`          | Decodes `Stream<List<int>>` as UTF-8, safe across byte splits.   |
| `serverSentEvents`   | Parses SSE. Buffers lines across chunks. Honours `[DONE]`.       |
| `jsonField`          | Decodes each chunk as JSON and extracts a nested string path.    |

For anything else, `Stream.map()` is always the right tool.

## Customization

`MarkdownStream` is a **superset** of `flutter_markdown_plus`'s `MarkdownBody` —
every hook exposed by `MarkdownBody` is forwarded verbatim. If you can
style, theme, or customize it with `MarkdownBody`, you can do the same
thing with `MarkdownStream`.

### Stream-specific parameters

| Parameter         | Purpose                                              |
| ----------------- | ---------------------------------------------------- |
| `stream`          | `Stream<String>` of token chunks (required).         |
| `onDone`          | Called with the full raw text when the stream ends.  |
| `onError`         | Called when the stream emits an error.               |
| `errorBuilder`    | Widget shown below the text after a stream error.    |
| `cursorWidget`    | Shown inline after the last character while streaming. |
| `rebuildDebounce` | Coalesces bursts of tokens; default 16ms.             |
| `codeBuilder`     | Sugar for a block-code builder. See below.           |
| `initialText`     | Text shown at once before the stream, e.g. to resume an answer. |
| `placeholder`     | Shown until the first chunk arrives.                 |
| `parseThinking`   | Render a leading `<think>` section as a collapsible block (default on). |
| `thinkingBuilder` | Custom widget for the thinking section.              |
| `linkPolicy`      | Which link and image schemes are allowed.            |
| `tableColumnMaxWidth` | Tables scroll sideways; columns fit their content up to this width (default 320). `null` restores flex columns. |

### All `MarkdownBody` parameters, passed through

`styleSheet`, `styleSheetTheme`, `syntaxHighlighter`, `onTapLink`,
`onTapText`, `imageDirectory`, `blockSyntaxes`, `inlineSyntaxes`,
`extensionSet`, `imageBuilder`, `checkboxBuilder`, `bulletBuilder`,
`builders`, `paddingBuilders`, `listItemCrossAxisAlignment`,
`fitContent`, `shrinkWrap`, `softLineBreak`, `selectable`, `padding`.

### Heavily-customised example

```dart
MarkdownStream(
  stream: llmResponseStream,
  onDone: (text) => debugPrint('Done: $text'),
  cursorWidget: const BlinkingCursor(),
  rebuildDebounce: const Duration(milliseconds: 16),

  // Theming
  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    h1: Theme.of(context).textTheme.displaySmall,
    code: const TextStyle(fontFamily: 'FiraCode', backgroundColor: Colors.black12),
  ),

  // Custom code block (syntax highlighting, copy button, etc.)
  codeBuilder: (code, language) => MyCodeBlock(code: code, language: language),

  // Custom image loading (e.g. cached_network_image)
  imageBuilder: (uri, title, alt) => CachedNetworkImage(imageUrl: uri.toString()),

  // Custom checkbox for GFM task lists
  checkboxBuilder: (checked) => Icon(checked ? Icons.check_box : Icons.check_box_outline_blank),

  // Custom bullet rendering
  bulletBuilder: (params) => Text('→ ', style: TextStyle(color: Colors.teal)),

  // GFM extensions (tables, task lists, strikethrough)
  extensionSet: md.ExtensionSet.gitHubFlavored,

  // Full control for any element — takes precedence over codeBuilder
  builders: {
    'my-custom-tag': MyCustomElementBuilder(),
    'h1': MyH1Builder(),
  },

  // Per-tag padding overrides
  paddingBuilders: {
    'blockquote': MyBlockquotePaddingBuilder(),
  },

  // Layout knobs
  listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
  softLineBreak: true,
  shrinkWrap: true,
  selectable: true,
  padding: const EdgeInsets.all(16),
  onTapLink: (text, href, title) => launchUrl(Uri.parse(href!)),
)
```

### `codeBuilder` vs `builders['code']`

- `codeBuilder` is sugar — it fires only for *block* fenced code (elements
  with a `language-*` class), never for inline `` `code` ``.
- If you need to intercept inline code, element-level attributes, or any
  other tag, use `builders` directly. A `builders['code']` entry takes
  precedence over `codeBuilder`.

## License

MIT — see [LICENSE](LICENSE).
