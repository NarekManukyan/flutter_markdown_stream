/// Tells cursors when the streamed text changes, so a blinking caret can stay
/// solid while text is arriving and only blink while the stream waits, the
/// way a text editor's caret behaves while you type.
library;

import 'package:flutter/widgets.dart';

/// Provides a [Listenable] that fires every time `MarkdownStream` renders
/// new text. Internal to the package.
class CursorActivity extends InheritedWidget {
  /// Creates the scope.
  const CursorActivity({
    super.key,
    required this.changes,
    required super.child,
  });

  /// Fires on every rendered-text change.
  final Listenable changes;

  /// The nearest activity source, or `null` outside a `MarkdownStream`.
  static Listenable? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CursorActivity>()?.changes;

  @override
  bool updateShouldNotify(CursorActivity oldWidget) =>
      oldWidget.changes != changes;
}

/// For blinking cursors: restarts the blink at its visible phase whenever the
/// streamed text changes, so the caret stays solid while text is arriving.
mixin SolidWhileTyping<T extends StatefulWidget> on State<T> {
  /// The controller whose `value < 0.5` is the visible half of the blink.
  AnimationController get blinkController;

  Listenable? _activity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CursorActivity.maybeOf(context);
    if (next == _activity) return;
    _activity?.removeListener(_restartBlink);
    _activity = next;
    _activity?.addListener(_restartBlink);
  }

  void _restartBlink() {
    blinkController
      ..value = 0
      ..repeat();
  }

  @override
  void dispose() {
    _activity?.removeListener(_restartBlink);
    super.dispose();
  }
}
