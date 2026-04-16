/// Controller for programmatically driving a [MarkdownStream]'s playback.
library;

import 'package:flutter/foundation.dart';

/// High-level state of a [MarkdownStream]'s playback.
enum StreamingState {
  /// No stream has started yet (widget built but no chunks received).
  idle,

  /// A stream is actively emitting chunks.
  streaming,

  /// Rendering is paused; incoming chunks buffer but do not render.
  paused,

  /// The stream has emitted `done`, or [StreamingTextController.skipToEnd]
  /// / [StreamingTextController.stop] was called.
  completed,

  /// The stream surfaced an error.
  error,
}

/// Human-readable helpers for [StreamingState].
extension StreamingStateExtension on StreamingState {
  /// Whether the animation is actively running.
  bool get isActive => this == StreamingState.streaming;

  /// Whether the animation is finished (completed or errored).
  bool get isFinished =>
      this == StreamingState.completed || this == StreamingState.error;
}

/// Signature for state-change callbacks on [StreamingTextController].
typedef StreamingStateCallback = void Function(StreamingState state);

/// Internal command issued by a [StreamingTextController] to its attached
/// [MarkdownStream] state.
@immutable
class StreamingCommand {
  /// Creates a command of the given [kind].
  const StreamingCommand(this.kind);

  /// The kind of command to execute.
  final StreamingCommandKind kind;
}

/// The set of commands a [StreamingTextController] can issue.
enum StreamingCommandKind {
  /// Pause rendering; keep buffering.
  pause,

  /// Resume rendering.
  resume,

  /// Cancel the stream and render everything buffered so far.
  skipToEnd,

  /// Cancel the stream; keep the currently-rendered text as-is.
  stop,

  /// Clear state and re-subscribe to the stream (requires a stream factory).
  restart,
}

/// A controller that provides programmatic control over a [MarkdownStream]'s
/// playback: pause, resume, skip-to-end, stop, and restart.
///
/// Usage:
///
/// ```dart
/// final controller = StreamingTextController();
///
/// MarkdownStream(
///   stream: llmStream,
///   controller: controller,
/// );
///
/// controller.pause();
/// controller.resume();
/// controller.skipToEnd();
/// ```
///
/// The controller is **owned by the caller** — create it in `initState`,
/// pass it to one or more [MarkdownStream]s, and `dispose()` it in
/// `dispose()` alongside other controllers.
///
/// A [speedMultiplier] greater than 1 compresses the rebuild debounce
/// (`effective = base / multiplier`), making the UI feel snappier. A value
/// less than 1 stretches the debounce.
class StreamingTextController extends ChangeNotifier {
  /// Creates a streaming-text controller in the idle state.
  StreamingTextController({
    double speedMultiplier = 1.0,
    this.onStateChanged,
    this.onCompleted,
  })  : assert(speedMultiplier > 0, 'speedMultiplier must be > 0'),
        _speedMultiplier = speedMultiplier;

  /// Fires whenever [state] changes. Assign once, or supply in the
  /// constructor.
  StreamingStateCallback? onStateChanged;

  /// Fires exactly once when the stream enters [StreamingState.completed].
  VoidCallback? onCompleted;

  // -- observable state --------------------------------------------------------

  StreamingState _state = StreamingState.idle;

  /// Current playback state.
  StreamingState get state => _state;

  /// Whether rendering is in the streaming state and not paused.
  bool get isStreaming => _state == StreamingState.streaming;

  /// Whether rendering is paused.
  bool get isPaused => _state == StreamingState.paused;

  /// Whether the stream has completed.
  bool get isCompleted => _state == StreamingState.completed;

  String _currentText = '';

  /// The most recently-rendered text. Updated whenever the attached widget
  /// commits a new render.
  String get currentText => _currentText;

  int _chunkCount = 0;

  /// Number of chunks received so far on the active subscription.
  int get chunkCount => _chunkCount;

  double _speedMultiplier;

  /// Multiplier applied to the rebuild debounce on the attached widget.
  ///
  /// `effective debounce = base / speedMultiplier`.
  ///
  /// Must be strictly positive.
  double get speedMultiplier => _speedMultiplier;
  set speedMultiplier(double value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'speedMultiplier', 'must be > 0');
    }
    if (value == _speedMultiplier) return;
    _speedMultiplier = value;
    notifyListeners();
  }

  // -- commands ---------------------------------------------------------------

  /// Command stream consumed by the attached widget. Exposed via
  /// [ChangeNotifier.notifyListeners]; each issued command sets
  /// [lastCommand] and notifies.
  StreamingCommand? _lastCommand;

  /// The most recent command issued by this controller, or `null` if none
  /// has been issued yet. Consumed by [MarkdownStream] after each notify.
  StreamingCommand? get lastCommand => _lastCommand;

  void _issue(StreamingCommandKind kind) {
    _lastCommand = StreamingCommand(kind);
    notifyListeners();
  }

  /// Pause rendering. Incoming chunks continue to buffer; they will render
  /// on [resume] or be dropped on [stop].
  ///
  /// No-op if the controller is not currently streaming.
  void pause() {
    if (_state != StreamingState.streaming) return;
    _issue(StreamingCommandKind.pause);
  }

  /// Resume rendering after [pause]. Triggers an immediate render of the
  /// full buffered text.
  ///
  /// No-op if the controller is not currently paused.
  void resume() {
    if (_state != StreamingState.paused) return;
    _issue(StreamingCommandKind.resume);
  }

  /// Cancel the underlying stream and render everything buffered so far,
  /// then fire `onDone` / [onCompleted].
  void skipToEnd() {
    if (_state.isFinished) return;
    _issue(StreamingCommandKind.skipToEnd);
  }

  /// Cancel the underlying stream and leave the currently-rendered text
  /// in place. [onCompleted] is not fired.
  void stop() {
    if (_state.isFinished) return;
    _issue(StreamingCommandKind.stop);
  }

  /// Clear all state and re-subscribe to the stream.
  ///
  /// Requires the attached [MarkdownStream] to have been created with a
  /// `streamFactory`. Throws a [StateError] otherwise (raised synchronously
  /// by the widget, not the controller).
  void restart() {
    _issue(StreamingCommandKind.restart);
  }

  // -- internal: widget → controller push -------------------------------------

  /// Used by [MarkdownStream]'s state to transition the controller.
  ///
  /// Not part of the public API.
  void internalSetState(StreamingState next) {
    if (_state == next) return;
    final wasFinished = _state.isFinished;
    _state = next;
    onStateChanged?.call(next);
    if (!wasFinished && next == StreamingState.completed) {
      onCompleted?.call();
    }
    notifyListeners();
  }

  /// Used by [MarkdownStream]'s state to commit the latest rendered text.
  ///
  /// Not part of the public API.
  void internalSetCurrentText(String text) {
    if (_currentText == text) return;
    _currentText = text;
    notifyListeners();
  }

  /// Used by [MarkdownStream]'s state to record a received chunk.
  ///
  /// Not part of the public API.
  void internalIncrementChunkCount() {
    _chunkCount++;
    // Chunk count change is noisy; do not notifyListeners to avoid
    // rebuilding UI on every single chunk.
  }

  /// Used by [MarkdownStream]'s state to reset on stream swap / restart.
  ///
  /// Not part of the public API.
  void internalReset() {
    _chunkCount = 0;
    _currentText = '';
    internalSetState(StreamingState.idle);
  }

  /// Called by [MarkdownStream]'s state after consuming [lastCommand].
  ///
  /// Not part of the public API.
  void internalClearCommand() {
    _lastCommand = null;
  }

  @override
  void dispose() {
    onStateChanged = null;
    onCompleted = null;
    _lastCommand = null;
    super.dispose();
  }
}
