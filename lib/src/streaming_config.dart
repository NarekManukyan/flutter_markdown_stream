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
    this.smoothingEnabled = false,
    this.charsPerSecond = 120,
    this.smoothingMaxBacklogChars = 400,
  })  : assert(charsPerSecond > 0, 'charsPerSecond must be positive'),
        assert(
          smoothingMaxBacklogChars > 0,
          'smoothingMaxBacklogChars must be positive',
        ),
        assert(trailingFadeHeight >= 0, 'trailingFadeHeight must be >= 0');

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

  /// Whether output is paced by a [OutputSmoother] instead of rendered as
  /// soon as tokens arrive.
  ///
  /// When `true`, incoming tokens fill a buffer that is revealed at a steady
  /// [charsPerSecond] rate, so bursty network delivery reads as a smooth,
  /// even flow of text (the "ChatGPT / Claude" feel). When `false` (the
  /// default), the widget renders each debounced batch immediately.
  final bool smoothingEnabled;

  /// Target reveal rate, in characters per second, when [smoothingEnabled]
  /// is `true`. Ignored otherwise.
  final double charsPerSecond;

  /// Backlog threshold, in characters, past which the smoother accelerates so
  /// a finished or stalled stream never leaves the UI arbitrarily behind.
  /// Ignored when [smoothingEnabled] is `false`.
  final int smoothingMaxBacklogChars;

  /// Returns a copy of this config with the given fields replaced.
  StreamingTextConfig copyWith({
    Duration? rebuildDebounce,
    bool? fadeInEnabled,
    Duration? fadeInDuration,
    Curve? fadeInCurve,
    double? trailingFadeHeight,
    bool? smoothingEnabled,
    double? charsPerSecond,
    int? smoothingMaxBacklogChars,
  }) =>
      StreamingTextConfig(
        rebuildDebounce: rebuildDebounce ?? this.rebuildDebounce,
        fadeInEnabled: fadeInEnabled ?? this.fadeInEnabled,
        fadeInDuration: fadeInDuration ?? this.fadeInDuration,
        fadeInCurve: fadeInCurve ?? this.fadeInCurve,
        trailingFadeHeight: trailingFadeHeight ?? this.trailingFadeHeight,
        smoothingEnabled: smoothingEnabled ?? this.smoothingEnabled,
        charsPerSecond: charsPerSecond ?? this.charsPerSecond,
        smoothingMaxBacklogChars:
            smoothingMaxBacklogChars ?? this.smoothingMaxBacklogChars,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreamingTextConfig &&
          other.rebuildDebounce == rebuildDebounce &&
          other.fadeInEnabled == fadeInEnabled &&
          other.fadeInDuration == fadeInDuration &&
          other.fadeInCurve == fadeInCurve &&
          other.trailingFadeHeight == trailingFadeHeight &&
          other.smoothingEnabled == smoothingEnabled &&
          other.charsPerSecond == charsPerSecond &&
          other.smoothingMaxBacklogChars == smoothingMaxBacklogChars);

  @override
  int get hashCode => Object.hash(
        rebuildDebounce,
        fadeInEnabled,
        fadeInDuration,
        fadeInCurve,
        trailingFadeHeight,
        smoothingEnabled,
        charsPerSecond,
        smoothingMaxBacklogChars,
      );

  @override
  String toString() => 'StreamingTextConfig('
      'rebuildDebounce: $rebuildDebounce, '
      'fadeInEnabled: $fadeInEnabled, '
      'fadeInDuration: $fadeInDuration, '
      'fadeInCurve: $fadeInCurve, '
      'trailingFadeHeight: $trailingFadeHeight, '
      'smoothingEnabled: $smoothingEnabled, '
      'charsPerSecond: $charsPerSecond, '
      'smoothingMaxBacklogChars: $smoothingMaxBacklogChars)';
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
  ///
  /// Since 0.5.0 this preset enables [StreamingTextConfig.smoothingEnabled] so
  /// bursty tokens are paced into an even flow. Opt out with
  /// `StreamingPresets.chatGPT.copyWith(smoothingEnabled: false)`.
  static const StreamingTextConfig chatGPT = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 15),
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 200),
    smoothingEnabled: true,
    charsPerSecond: 180,
  );

  /// Smoother, paced rebuilds with a longer fade — approximates Claude.
  ///
  /// Since 0.5.0 this preset enables [StreamingTextConfig.smoothingEnabled].
  /// Opt out with `StreamingPresets.claude.copyWith(smoothingEnabled: false)`.
  static const StreamingTextConfig claude = StreamingTextConfig(
    rebuildDebounce: Duration(milliseconds: 80),
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 400),
    fadeInCurve: Curves.easeInOutCubic,
    smoothingEnabled: true,
    charsPerSecond: 120,
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

  /// Explicit smoothing preset: paces output at a steady rate regardless of
  /// how bursty the underlying stream is. Use when you want the paced,
  /// even-flow feel without tying it to a specific vendor's cadence.
  static const StreamingTextConfig smooth = StreamingTextConfig(
    smoothingEnabled: true,
    charsPerSecond: 140,
    fadeInEnabled: true,
    fadeInDuration: Duration(milliseconds: 300),
    fadeInCurve: Curves.easeOut,
  );
}
