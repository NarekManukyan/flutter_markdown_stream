import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';

void main() => runApp(const ExampleApp());

/// Demo app for `flutter_markdown_stream`.
///
/// The screens double as an end-to-end test surface: every screen exposes
/// stable, distinctive `Text` markers (prefixed `MRK_`) and buttons with fixed
/// labels so a Maestro flow can drive and assert against them deterministically
/// without depending on Flutter's rich-text semantics.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_markdown_stream example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// The markdown a demo stream emits, split into small chunks to mimic an LLM
/// token stream. Contains a heading, prose, a list, and a fenced code block.
const List<String> _demoChunks = <String>[
  '# Maestro ',
  'Streaming ',
  'Demo\n\n',
  'The quick ',
  'brown fox ',
  '**jumps** over ',
  'the lazy dog.\n\n',
  '- one\n- two\n- three\n\n',
  'Here is code:\n\n',
  '```dart\n',
  "void main() => print('maestro');\n",
  '```\n\n',
  'Streaming complete.',
];

/// A very long markdown body used by the auto-scroll demo so the content
/// clearly overflows the viewport by many screens — following-to-bottom is
/// then obvious, and the first line genuinely scrolls off the top.
///
/// `MRK_TOP_START` and `MRK_TAIL_REACHED` are their own paragraphs so a test
/// can assert the top has scrolled away while the tail is reached.
List<String> _longChunks() => <String>[
  'MRK_TOP_START\n\n',
  '# Long Answer\n\n',
  for (var i = 1; i <= 60; i++)
    'Paragraph number $i. Lorem ipsum dolor sit amet, consectetur adipiscing '
        'elit, sed do eiusmod tempor incididunt ut labore et dolore magna '
        'aliqua. Ut enim ad minim veniam, quis nostrud exercitation.\n\n',
  'MRK_TAIL_REACHED',
];

Stream<String> _emit(List<String> chunks, {Duration gap = const Duration(milliseconds: 90)}) async* {
  for (final c in chunks) {
    await Future<void>.delayed(gap);
    yield c;
  }
}

/// The default "smooth" feel: paces bursty tokens into an even flow. The
/// bottom-edge (per-line) fade is intentionally left OFF here.
const StreamingTextConfig _smoothConfig = StreamingTextConfig(
  smoothingEnabled: true,
  charsPerSecond: 130,
);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(String, Widget)>[
      ('Streaming basics', const StreamingBasicsScreen()),
      ('Smoothing', const SmoothingScreen()),
      ('Auto scroll', const AutoScrollScreen()),
      ('Code block', const CodeBlockScreen()),
      ('Cursors', const CursorsScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Markdown Stream Demo')),
      body: ListView(
        children: [
          for (final (label, screen) in items)
            ListTile(
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared status line + start button used by the streaming demos.
class _StreamScaffold extends StatefulWidget {
  const _StreamScaffold({
    required this.title,
    required this.buildStream,
    this.config,
    this.incremental = false,
    this.codeBuilder,
  });

  final String title;
  final List<String> Function() buildStream;
  final StreamingTextConfig? config;
  final bool incremental;
  final CodeBlockBuilder? codeBuilder;

  @override
  State<_StreamScaffold> createState() => _StreamScaffoldState();
}

class _StreamScaffoldState extends State<_StreamScaffold> {
  final StickToBottomController _stick = StickToBottomController();
  Stream<String>? _stream;
  String _status = 'IDLE';

  @override
  void dispose() {
    _stick.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _status = 'STREAMING';
      _stream = _emit(widget.buildStream());
    });
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    // Default to the smooth (paced + fade) feel; a screen may override it.
    final config = widget.config ?? _smoothConfig;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton(
                  onPressed: _start,
                  child: Text(stream == null ? 'Start' : 'Restart'),
                ),
                const SizedBox(width: 16),
                Text('MRK_STATUS_$_status'),
              ],
            ),
            const Divider(),
            Expanded(
              child: stream == null
                  ? const Text('Press Start to stream.')
                  // AutoScroll keeps the newest (fading-in) text pinned to the
                  // bottom edge, so streaming reads as a smooth flow.
                  : AutoScroll(
                      controller: _stick,
                      child: MarkdownStream(
                        key: ValueKey<int>(stream.hashCode),
                        stream: stream,
                        config: config,
                        incrementalParsing: widget.incremental,
                        wordFadeIn: true,
                        // Fill the viewport width so full-width blocks (e.g. the
                        // code card) align to the message edges.
                        fitContent: false,
                        codeBuilder: widget.codeBuilder,
                        cursorWidget: const BlinkingCursor(
                          semanticLabel: 'Assistant is typing',
                        ),
                        onDone: (_) => setState(() => _status = 'DONE'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class StreamingBasicsScreen extends StatelessWidget {
  const StreamingBasicsScreen({super.key});
  @override
  Widget build(BuildContext context) => _StreamScaffold(
        title: 'Streaming basics',
        buildStream: () => _demoChunks,
      );
}

class SmoothingScreen extends StatelessWidget {
  const SmoothingScreen({super.key});
  @override
  Widget build(BuildContext context) => _StreamScaffold(
        title: 'Smoothing',
        buildStream: () => _demoChunks,
        config: const StreamingTextConfig(
          smoothingEnabled: true,
          charsPerSecond: 90,
        ),
      );
}

class CodeBlockScreen extends StatelessWidget {
  const CodeBlockScreen({super.key});
  @override
  Widget build(BuildContext context) => _StreamScaffold(
        title: 'Code block',
        buildStream: () => _demoChunks,
        incremental: true,
        codeBuilder: CodeBlockView.builder(highlightBuilder: _demoHighlight),
      );
}

/// A tiny, dependency-free highlighter used only to demonstrate
/// `CodeBlockView.highlightBuilder`. Real apps would plug in a proper
/// tokenizer such as `package:highlight` / `package:flutter_highlight`.
InlineSpan _demoHighlight(String code, String language, TextStyle base) {
  const keywords = <String>{
    'void', 'main', 'final', 'const', 'class', 'extends', 'return', 'if',
    'else', 'for', 'while', 'import', 'var', 'true', 'false', 'null', 'new',
    'async', 'await', 'print',
  };
  final keyword =
      base.copyWith(color: const Color(0xFFB388FF), fontWeight: FontWeight.w600);
  final string = base.copyWith(color: const Color(0xFF80CBC4));
  final comment =
      base.copyWith(color: const Color(0xFF9E9E9E), fontStyle: FontStyle.italic);
  final number = base.copyWith(color: const Color(0xFFFFB74D));
  final token = RegExp(
    r'''//[^\n]*|'[^']*'|"[^"]*"|\b\d+(?:\.\d+)?\b|[A-Za-z_]\w*|\s+|[^\w\s]''',
  );
  final spans = <TextSpan>[
    for (final m in token.allMatches(code))
      TextSpan(text: m.group(0), style: _styleFor(m.group(0)!, base, keywords,
          keyword: keyword, string: string, comment: comment, number: number)),
  ];
  return TextSpan(children: spans);
}

TextStyle _styleFor(
  String t,
  TextStyle base,
  Set<String> keywords, {
  required TextStyle keyword,
  required TextStyle string,
  required TextStyle comment,
  required TextStyle number,
}) {
  if (t.startsWith('//')) return comment;
  if (t.startsWith("'") || t.startsWith('"')) return string;
  if (RegExp(r'^\d').hasMatch(t)) return number;
  if (keywords.contains(t)) return keyword;
  return base;
}

class CursorsScreen extends StatelessWidget {
  const CursorsScreen({super.key});
  @override
  Widget build(BuildContext context) => _StreamScaffold(
        title: 'Cursors',
        buildStream: () => _demoChunks,
      );
}

/// Auto-scroll demo: a long stream inside an [AutoScroll]. The final line
/// (`MRK_TAIL_REACHED`) starts off-screen and only becomes visible if
/// following-to-bottom works.
class AutoScrollScreen extends StatefulWidget {
  const AutoScrollScreen({super.key});
  @override
  State<AutoScrollScreen> createState() => _AutoScrollScreenState();
}

class _AutoScrollScreenState extends State<AutoScrollScreen> {
  final StickToBottomController _stick = StickToBottomController();
  Stream<String>? _stream;
  String _status = 'IDLE';

  @override
  void dispose() {
    _stick.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _status = 'STREAMING';
      _stream = _emit(_longChunks(), gap: const Duration(milliseconds: 60));
    });
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto scroll')),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _stick.showScrollToBottomButtonListenable,
        builder: (context, show, _) => show
            ? FloatingActionButton.small(
                // A user tap animates (smooth); the automatic streaming-follow
                // jumps (tight). Two different intents, two different calls.
                onPressed: () => _stick.animateToBottom(),
                child: const Icon(Icons.arrow_downward),
              )
            : const SizedBox.shrink(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton(
                  onPressed: _start,
                  child: Text(stream == null ? 'Start' : 'Restart'),
                ),
                const SizedBox(width: 16),
                Text('MRK_STATUS_$_status'),
              ],
            ),
            const Divider(),
            Expanded(
              child: stream == null
                  ? const Text('Press Start to stream.')
                  : AutoScroll(
                      controller: _stick,
                      child: MarkdownStream(
                        key: ValueKey<int>(stream.hashCode),
                        stream: stream,
                        onDone: (_) => setState(() => _status = 'DONE'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
