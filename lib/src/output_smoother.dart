/// Paces the reveal of a monotonically-growing text buffer at a target
/// characters-per-second rate.
library;

import 'dart:async';

/// Smooths bursty stream delivery into a fluid, paced character reveal.
///
/// The widget's `rebuildDebounce` only *coalesces* bursty tokens — it caps
/// how often a rebuild happens, but a rebuild still jumps straight to
/// whatever text has accumulated. Networks deliver LLM tokens in lumpy
/// bursts, so that alone still reads as jerky chunks of text popping in.
///
/// [OutputSmoother] instead *paces* the reveal: feed it the full
/// accumulated text as it grows via [push], and it emits a steadily-growing
/// visible prefix on [revealed] (or synchronously via [value]) at a target
/// [charsPerSecond] — this is what makes ChatGPT/Claude-style output feel
/// fluid rather than bursty.
///
/// Reveal always proceeds strictly by character count over the current
/// target string — text is never reordered. If the unrevealed backlog
/// (`target.length - value.length`) grows past [maxBacklogChars] (for
/// example because the underlying stream went quiet or has already
/// finished), the reveal rate accelerates by up to [catchUpMultiplier] so
/// the visible text never drifts arbitrarily far behind.
///
/// This class has no dependency on a `Ticker`/vsync — it is driven by a
/// plain [Timer], so it is fully unit-testable (e.g. with
/// `package:fake_async`) without a widget test harness.
final class OutputSmoother {
  /// Creates a smoother that reveals text at [charsPerSecond] characters
  /// per second on average.
  ///
  /// Once the unrevealed backlog exceeds [maxBacklogChars], the effective
  /// rate accelerates up to `charsPerSecond * catchUpMultiplier` to avoid
  /// lagging arbitrarily far behind. [tickInterval] controls how often the
  /// internal timer advances the revealed prefix. [finishDuration] bounds
  /// how long [complete] is allowed to take to flush any remaining
  /// backlog.
  OutputSmoother({
    this.charsPerSecond = 120,
    this.maxBacklogChars = 400,
    this.catchUpMultiplier = 4.0,
    this.tickInterval = const Duration(milliseconds: 16),
    this.finishDuration = const Duration(milliseconds: 250),
  }) : assert(charsPerSecond > 0, 'charsPerSecond must be > 0'),
       assert(maxBacklogChars > 0, 'maxBacklogChars must be > 0'),
       assert(catchUpMultiplier >= 1, 'catchUpMultiplier must be >= 1'),
       assert(tickInterval > Duration.zero, 'tickInterval must be > 0');

  /// Target steady-state reveal rate, in characters per second.
  final double charsPerSecond;

  /// Once the unrevealed backlog exceeds this many characters, the reveal
  /// rate accelerates (up to [catchUpMultiplier]x) so the visible text
  /// catches back up to a stream that has gone quiet or finished.
  final int maxBacklogChars;

  /// Maximum multiple of [charsPerSecond] applied once the backlog exceeds
  /// [maxBacklogChars].
  final double catchUpMultiplier;

  /// How often the internal timer ticks to advance the revealed prefix.
  final Duration tickInterval;

  /// Upper bound on how long [complete] takes to flush the remaining
  /// backlog once called.
  final Duration finishDuration;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Emits the growing visible prefix of the most recently [push]ed text,
  /// one paced tick at a time.
  ///
  /// Emits an empty string when [push] resets to a new (shorter) target.
  /// Closes after [complete] finishes flushing, or after [dispose].
  Stream<String> get revealed => _controller.stream;

  String _target = '';
  String _visible = '';
  double _fractionalChars = 0;
  double _completionRate = 0;
  Timer? _timer;
  bool _completing = false;
  bool _disposed = false;

  /// The most recently revealed prefix.
  ///
  /// Updated synchronously by [push], [snapToEnd], and each internal tick,
  /// so it reflects the current reveal state without waiting for a
  /// [revealed] listener to process an event.
  String get value => _visible;

  /// Number of characters of the current target that have not yet been
  /// revealed.
  int get backlog => _target.length - _visible.length;

  /// Feeds the current full accumulated text.
  ///
  /// [fullTextSoFar] is expected to grow monotonically (new tokens
  /// appended to what was pushed before). If it is shorter than the
  /// previous target, or does not extend the currently-revealed prefix,
  /// this is treated as a new message: the smoother resets and reveals
  /// [fullTextSoFar] from scratch.
  void push(String fullTextSoFar) {
    if (_disposed || _controller.isClosed) return;
    final bool isNewMessage =
        fullTextSoFar.length < _target.length ||
        !fullTextSoFar.startsWith(_visible);
    _target = fullTextSoFar;
    if (isNewMessage) {
      _visible = '';
      _fractionalChars = 0;
      _completing = false;
      _emit();
    }
    if (_visible.length < _target.length) {
      _ensureTimer();
    }
  }

  /// Signals that the underlying stream has ended.
  ///
  /// Any remaining backlog is flushed at an accelerated rate so it
  /// finishes within roughly [finishDuration], then [revealed] is closed.
  /// No-op if already completed or [dispose]d.
  void complete() {
    if (_disposed || _controller.isClosed || _completing) return;
    _completing = true;
    final int remaining = backlog;
    if (remaining <= 0) {
      _finish();
      return;
    }
    final double seconds =
        finishDuration.inMicroseconds / Duration.microsecondsPerSecond;
    _completionRate = seconds > 0 ? remaining / seconds : remaining.toDouble();
    if (seconds <= 0) {
      // No finish budget: reveal the remainder immediately.
      _visible = _target;
      _emit();
      _finish();
      return;
    }
    _ensureTimer();
  }

  /// Immediately reveals the entire current target, skipping any pacing.
  ///
  /// Use for a "skip to end" action. Does not close [revealed]; call
  /// [complete] or [dispose] separately if the stream is also done.
  void snapToEnd() {
    if (_disposed || _controller.isClosed) return;
    _pauseTimer();
    _fractionalChars = 0;
    _visible = _target;
    _emit();
  }

  /// Cancels timers and closes [revealed]. Further calls to [push],
  /// [complete], and [snapToEnd] become no-ops.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pauseTimer();
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(tickInterval, _onTick);
  }

  void _pauseTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick(Timer timer) {
    if (_disposed || _controller.isClosed) {
      _pauseTimer();
      return;
    }
    final int remaining = backlog;
    if (remaining <= 0) {
      if (_completing) {
        _finish();
      } else {
        _pauseTimer();
      }
      return;
    }

    final double rate = _completing ? _completionRate : _currentRate();
    final double deltaSeconds =
        tickInterval.inMicroseconds / Duration.microsecondsPerSecond;
    _fractionalChars += rate * deltaSeconds;
    int charsToReveal = _fractionalChars.floor();
    if (charsToReveal <= 0) return;
    _fractionalChars -= charsToReveal;
    if (charsToReveal > remaining) charsToReveal = remaining;

    _visible = _target.substring(0, _visible.length + charsToReveal);
    _emit();

    if (_completing && backlog <= 0) {
      _finish();
    }
  }

  double _currentRate() => backlog > maxBacklogChars
      ? charsPerSecond * catchUpMultiplier
      : charsPerSecond;

  void _finish() {
    _pauseTimer();
    _completing = false;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_visible);
    }
  }
}
