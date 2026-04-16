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
  late final TabController _tab = TabController(length: 3, vsync: this);

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
            Tab(text: 'Playback'),
            Tab(text: 'Cursors'),
            Tab(text: 'LaTeX + RTL'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _PlaybackDemo(),
          _CursorGallery(),
          _LatexAndRtlDemo(),
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
// Preset picker
// -----------------------------------------------------------------------------

enum _Preset {
  chatGPT('ChatGPT (fast + fade)'),
  claude('Claude (smooth + fade)'),
  typewriter('Typewriter'),
  gentle('Gentle'),
  fast('Fast'),
  instant('Instant');

  const _Preset(this.label);
  final String label;

  StreamingTextConfig get config => switch (this) {
        _Preset.chatGPT => StreamingPresets.chatGPT,
        _Preset.claude => StreamingPresets.claude,
        _Preset.typewriter => StreamingPresets.typewriter,
        _Preset.gentle => StreamingPresets.gentle,
        _Preset.fast => StreamingPresets.fast,
        _Preset.instant => StreamingPresets.instant,
      };
}

// -----------------------------------------------------------------------------
// Playback demo — showcases StreamingTextController + presets + fade
// -----------------------------------------------------------------------------

class _PlaybackDemo extends StatefulWidget {
  const _PlaybackDemo();

  @override
  State<_PlaybackDemo> createState() => _PlaybackDemoState();
}

class _PlaybackDemoState extends State<_PlaybackDemo> {
  final StreamingTextController _controller = StreamingTextController();
  Stream<String>? _stream;
  int _runId = 0;
  _CursorStyle _style = _CursorStyle.blinking;
  _Preset _preset = _Preset.chatGPT;
  double _speed = 1;

  static const _sample = '''
# Streaming Markdown demo

This whole document is streaming in token-by-token. Try **Pause**, **Resume**,
**Skip to end**, and **Restart** in the toolbar above.

## Features on display

- `StreamingTextController` — pause/resume/skip/restart/stop
- `StreamingPresets` — ChatGPT-style, Claude-style, typewriter, …
- **Trailing-fade effect** — the bottom of the text fades softly while
  streaming and animates away when done
- Speed multiplier — drag the slider to compress or stretch the debounce

## Code block

```dart
void main() {
  print('Hello, stream!');
  for (var i = 0; i < 3; i++) {
    print('tick \$i');
  }
}
```

## Links and emphasis

- first item
- second item with [a link](https://pub.dev)
- third item with ~~strikethrough~~

That's all, folks!
''';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Stream<String> _buildStream() {
    final id = ++_runId;
    final ctl = StreamController<String>();
    Future<void> pump() async {
      final rand = DateTime.now().microsecondsSinceEpoch;
      var i = 0;
      while (i < _sample.length) {
        if (id != _runId) return;
        final step = 1 + (rand + i) % 3;
        final end = (i + step).clamp(0, _sample.length);
        ctl.add(_sample.substring(i, end));
        i = end;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await ctl.close();
    }

    unawaited(pump());
    return ctl.stream;
  }

  void _start() {
    setState(() {
      _stream = _buildStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Listenable-scoped rebuild: only the control bar and status pill
          // rebuild when the controller state changes — not the stream view.
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final state = _controller.state;
              final canPause = state == StreamingState.streaming;
              final canResume = state == StreamingState.paused;
              final isActive = _stream != null &&
                  state != StreamingState.completed &&
                  state != StreamingState.error;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
                      OutlinedButton.icon(
                        onPressed: canPause ? _controller.pause : null,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                      ),
                      OutlinedButton.icon(
                        onPressed: canResume ? _controller.resume : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Resume'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isActive ? _controller.skipToEnd : null,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Skip to end'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isActive ? _controller.stop : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      DropdownButton<_Preset>(
                        value: _preset,
                        items: [
                          for (final p in _Preset.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (v) => setState(() => _preset = v!),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Speed '),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.25,
                          max: 4,
                          divisions: 15,
                          label: '${_speed.toStringAsFixed(2)}x',
                          onChanged: (v) {
                            setState(() => _speed = v);
                            _controller.speedMultiplier = v;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${_speed.toStringAsFixed(2)}x'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _StatusPill(
                    state: state,
                    chunks: _controller.chunkCount,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _stream == null
                ? const Center(child: Text('Press Start to begin streaming.'))
                : SingleChildScrollView(
                    child: MarkdownStream(
                      stream: _stream!,
                      controller: _controller,
                      config: _preset.config,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.chunks});
  final StreamingState state;
  final int chunks;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      StreamingState.idle => Colors.grey,
      StreamingState.streaming => Colors.green,
      StreamingState.paused => Colors.orange,
      StreamingState.completed => Colors.blue,
      StreamingState.error => Colors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text('${state.name}  •  $chunks chunks'),
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

// -----------------------------------------------------------------------------
// LaTeX + RTL demo
// -----------------------------------------------------------------------------
//
// The package adds no dependency on a math renderer. This demo uses a simple
// placeholder renderer that formats LaTeX expressions distinctly; in a real
// app you'd plug in a package like `flutter_math_fork` here.

class _LatexAndRtlDemo extends StatefulWidget {
  const _LatexAndRtlDemo();

  @override
  State<_LatexAndRtlDemo> createState() => _LatexAndRtlDemoState();
}

class _LatexAndRtlDemoState extends State<_LatexAndRtlDemo> {
  Stream<String>? _stream;
  int _runId = 0;
  bool _rtl = false;

  static const _english = r'''
# Math, streamed safely

Euler's identity: $e^{i\pi} + 1 = 0$ — arguably the most beautiful formula
in mathematics.

A block expression:

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

The **LaTeX** delimiters are detected mid-stream, so partially-typed
`$formula` fragments do not break the layout.
''';

  static const _arabic = '''
# عرض باللغة العربية

هذه فقرة تُبثّ حرفاً بحرف من اليمين إلى اليسار. تعمل خصائص **التأكيد**
و *المائل* بشكل صحيح مع التخطيط العربي.

- عنصر أول
- عنصر ثانٍ
- عنصر ثالث

انتهى العرض.
''';

  void _start() {
    final id = ++_runId;
    final ctl = StreamController<String>();
    final text = _rtl ? _arabic : _english;
    setState(() => _stream = ctl.stream);

    Future<void> pump() async {
      var i = 0;
      while (i < text.length) {
        if (id != _runId) return;
        final end = (i + 2).clamp(0, text.length);
        ctl.add(text.substring(i, end));
        i = end;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await ctl.close();
    }

    unawaited(pump());
  }

  Widget _renderLatex(String latex, {required bool displayMode}) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontFamily: 'monospace',
          color: scheme.primary,
          fontWeight: FontWeight.w500,
        );
    final rendered = displayMode
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(latex, style: style),
            ),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(latex, style: style),
          );
    return rendered;
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
              FilterChip(
                label: const Text('RTL (Arabic sample)'),
                selected: _rtl,
                onSelected: (v) => setState(() {
                  _rtl = v;
                  _stream = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _rtl
                ? 'textDirection: TextDirection.rtl'
                : 'latexBuilder: inline \$…\$ and block \$\$…\$\$',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _stream == null
                ? const Center(child: Text('Press Stream to start.'))
                : SingleChildScrollView(
                    child: MarkdownStream(
                      stream: _stream!,
                      config: StreamingPresets.claude,
                      cursorWidget: const BarCursor(),
                      selectable: true,
                      latexBuilder: _rtl ? null : _renderLatex,
                      textDirection: _rtl ? TextDirection.rtl : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
