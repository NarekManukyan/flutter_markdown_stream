/// Named animation presets and a configuration bundle for [MarkdownStream].
///
/// Use one of the [StreamingPresets] for a one-line switch between common
/// streaming styles (ChatGPT-fast, Claude-smooth, typewriter, instant, …),
/// or build a custom [StreamingTextConfig] for full control.
library;

import 'package:flutter/widgets.dart';

/// Immutable bundle of streaming-animation settings.
///
/// Supplying a [StreamingTextConfig] to [MarkdownStream] is equivalent to
/// setting each of its constituent fields individually, but lets you swap
/// a whole "style" with a single assignment (e.g. `StreamingPresets.claude`).
///
/// When both a [StreamingTextConfig] and the equivalent individual parameters
/// are supplied to [MarkdownStream], the config wins.
@immutable
class StreamingTextConfig {
  /// Creates a streaming-animation configuration.
  const StreamingTextConfig({
    this.rebuildDebounce = const Duration(milliseconds: 16),
    this.fadeInEnabled = false,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeInCurve = Curves.easeOut,
    this.trailingFadeHeight = 40,
  });

  /// Minimum time between rebuilds. Bursts of tokens inside a debounce window
  /// produce at most one rebuild. Defaults to one frame (16 ms).
  ///
  /// Lower values feel snappier but cost more CPU. Set to [Duration.zero] to
  /// rebuild on every chunk (useful for tests).
  final Duration rebuildDebounce;

  /// Whether a trailing-gradient fade is drawn over the bottom edge of the
  /// rendered Markdown while the stream is still emitting. The fade animates
  /// away over [fadeInDuration] when the stream completes.
  final bool fadeInEnabled;

  /// Duration of the fade-out transition when the stream completes. Ignored
  /// when [fadeInEnabled] is `false`.
  final Duration fadeInDuration;

  /// Curve applied to the fade-out transition. Ignored when [fadeInEnabled]
  /// is `false`.
  final Curve fadeInCurve;

  /// Height, in logical pixels, of the trailing fade region at the bottom of
  /// the content. The top of this region is fully opaque; the bottom is fully
  /// transparent. Ignored when [fadeInEnabled] is `false`.
  final double trailingFadeHeight;

  /// Returns a copy of this config with the given fields replaced.
  StreamingTextConfig copyWith({
    Duration? rebuildDebounce,
    bool? fadeInEnabled,
    Duration? fadeInDuration,
    Curve? fadeInCurve,
    double? trailingFadeHeight,
  }) =>
      StreamingTextConfig(
        rebuildDebounce: rebuildDebounce ?? this.rebuildDebounce,
        fadeInEnabled: fadeInEnabled ?? this.fadeInEnabled,
        fadeInDuration: fadeInDuration ?? this.fadeInDuration,
        fadeInCurve: fadeInCurve ?? this.fadeInCurve,
        trailingFadeHeight: trailingFadeHeight ?? this.trailingFadeHeight,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreamingTextConfig &&
          other.rebuildDebounce == rebuildDebounce &&
          other.fadeInEnabled == fadeInEnabled &&
          other.fadeInDuration == fadeInDuration &&
          other.fadeInCurve == fadeInCurve &&
          other.trailingFadeHeight == trailingFadeHeight);

  @override
  int get hashCode => Object.hash(
        rebuildDebounce,
        fadeInEnabled,
        fadeInDuration,
        fadeInCurve,
        trailingFadeHeight,
      );

  @override
  String toString() => 'StreamingTextConfig('
      'rebuildDebounce: $rebuildDebounce, '
      'fadeInEnabled: $fadeInEnabled, '
      'fadeInDuration: $fadeInDuration, '
      'fadeInCurve: $fadeInCurve, '
      'trailingFadeHeight: $trailingFadeHeight)';
}

/// Named [StreamingTextConfig] presets for common streaming styles.
///
/// Drop any of these directly into [MarkdownStream]:
///
/// ```dart
/// MarkdownStream(
///   stream: llmStream,
///   config: StreamingPresets.chatGPT,
/// )
/// ```
abstract final class StreamingPresets {
  /// Fast, character-level feel with a subtle fade — approximates ChatGPT.
  static const StreamingTextConfig chatGPT = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 15),
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 200),
  );

  /// Smoother, paced rebuilds with a longer fade — approximates Claude.
  static const StreamingTextConfig claude = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 80),
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 400),
    fadeInCurve: Curves.easeInOutCubic,
  );

  /// Zero-latency rendering, no fade. Useful for deterministic tests or
  /// when you already control pacing upstream.
  static const StreamingTextConfig instant = StreamingTextConfig(
    rebuildDebounce: Duration.zero,
  );

  /// Steady, mechanical pacing without fade — a "typewriter" cadence.
  static const StreamingTextConfig typewriter = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 50),
  );

  /// Slow, graceful pacing with a gentle fade.
  static const StreamingTextConfig gentle = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 100),
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 500),
    fadeInCurve: Curves.easeInOut,
  );

  /// Fast rebuilds with a short fade — good for long responses.
  static const StreamingTextConfig fast = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 30),
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 150),
  );
}
