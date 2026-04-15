import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_markdown_stream example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_markdown_stream'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Stream demo'),
            Tab(text: 'Cursor gallery'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _StreamDemo(),
          _CursorGallery(),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cursor styles (enum-based so DropdownButton equality behaves predictably).
// -----------------------------------------------------------------------------

enum _CursorStyle {
  blinking('Blinking'),
  bar('Bar'),
  fading('Fading'),
  pulsing('Pulsing'),
  typingDots('Typing dots'),
  waveDots('Wave dots'),
  spinner('Spinner'),
  shimmer('Shimmer');

  const _CursorStyle(this.label);
  final String label;

  Widget build() => switch (this) {
        _CursorStyle.blinking => const BlinkingCursor(),
        _CursorStyle.bar => const BarCursor(),
        _CursorStyle.fading => const FadingCursor(),
        _CursorStyle.pulsing => const PulsingCursor(),
        _CursorStyle.typingDots => const TypingDotsCursor(),
        _CursorStyle.waveDots => const WaveDotsCursor(),
        _CursorStyle.spinner => const SpinnerCursor(),
        _CursorStyle.shimmer => const ShimmerCursor(),
      };
}

// -----------------------------------------------------------------------------
// Stream demo
// -----------------------------------------------------------------------------

class _StreamDemo extends StatefulWidget {
  const _StreamDemo();

  @override
  State<_StreamDemo> createState() => _StreamDemoState();
}

class _StreamDemoState extends State<_StreamDemo> {
  Stream<String>? _stream;
  int _runId = 0;
  _CursorStyle _style = _CursorStyle.blinking;

  static const _sample = '''
# Streaming Markdown demo

Here is **bold text**, *italic text*, and `inline code` mid-sentence.

## Code block

```dart
void main() {
  print('Hello, stream!');
  for (var i = 0; i < 3; i++) {
    print('tick \$i');
  }
}
```

## List

- first item
- second item with [a link](https://pub.dev)
- third item with ~~strikethrough~~

That's all, folks!
''';

  void _start() {
    final id = ++_runId;
    final controller = StreamController<String>();
    setState(() => _stream = controller.stream);

    Future<void> pump() async {
      final rand = DateTime.now().microsecondsSinceEpoch;
      var i = 0;
      while (i < _sample.length) {
        if (id != _runId) return;
        final step = 1 + (rand + i) % 3;
        final end = (i + step).clamp(0, _sample.length);
        controller.add(_sample.substring(i, end));
        i = end;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await controller.close();
    }

    unawaited(pump());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Stream'),
              ),
              DropdownButton<_CursorStyle>(
                value: _style,
                items: [
                  for (final s in _CursorStyle.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _style = v!),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _stream == null
                ? const Center(child: Text('Press Stream to start.'))
                : SingleChildScrollView(
                    child: MarkdownStream(
                      stream: _stream!,
                      cursorWidget: _style.build(),
                      selectable: true,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cursor gallery
// -----------------------------------------------------------------------------

class _CursorGallery extends StatelessWidget {
  const _CursorGallery();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _CursorStyle.values.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final style = _CursorStyle.values[i];
        return Row(
          children: [
            SizedBox(
              width: 180,
              child: Text(
                style.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 40,
              child: Center(child: style.build()),
            ),
          ],
        );
      },
    );
  }
}
