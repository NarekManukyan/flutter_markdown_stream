/// A stick-to-bottom auto-scroll helper for streaming chat content.
///
/// [StickToBottomController] attaches to a [ScrollController] and keeps it
/// pinned to the bottom while new content is appended — unless the user has
/// scrolled away to read earlier messages, in which case it stops following
/// until they scroll back down (or tap a "jump to bottom" affordance).
/// [AutoScroll] wraps that behaviour in a ready-to-use [StatefulWidget].
///
/// Nothing in this package auto-scrolls on its own. [MarkdownStream] stays
/// entirely scroll-agnostic; auto-scroll only happens where a caller opts in
/// by wrapping content in [AutoScroll] or attaching a
/// [StickToBottomController] to their own [ScrollController].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A controller that keeps a [ScrollController] pinned to the bottom while
/// content grows, and stops following the instant the user scrolls away to
/// read earlier content.
///
/// This solves the common "stick to bottom" problem in streaming chat UIs:
/// attach the controller to your scrollable's [ScrollController] (or let it
/// create one for you), call [follow] every time new content is appended,
/// and the scroll position tracks the bottom edge — unless the user has
/// manually scrolled up, in which case it backs off until they return to
/// the bottom (via [jumpToBottom], [animateToBottom], or their own drag).
///
/// ```dart
/// final controller = StickToBottomController();
///
/// SingleChildScrollView(
///   controller: controller.scrollController,
///   child: Column(children: messages),
/// );
///
/// // Whenever a message grows or a new one arrives:
/// controller.follow();
/// ```
///
/// [isPinnedToBottom] reports whether the current scroll position is within
/// [threshold] pixels of the bottom edge; [pinnedToBottomListenable] and
/// [showScrollToBottomButtonListenable] let a consumer react to that state
/// (e.g. to render their own "jump to bottom" button — this package does
/// not ship one).
///
/// Set [enabled] to `false` to turn the controller into a transparent
/// passthrough: it stops following new content, stops scheduling any
/// post-frame scrolling, and [showScrollToBottomButtonListenable] reports
/// `false` regardless of scroll position. [enabled] is runtime-changeable —
/// flipping it live never forces a scroll in either direction; it simply
/// starts or stops the automatic behaviour from that point on.
///
/// The controller **owns** [scrollController] only when it created it
/// itself (i.e. no `scrollController` was supplied to the constructor);
/// [dispose] disposes it in that case only, so it is always safe to pass in
/// a [ScrollController] you already own and manage its lifecycle yourself.
class StickToBottomController {
  /// Creates a stick-to-bottom controller.
  ///
  /// Attaches to [scrollController] if supplied; otherwise creates (and
  /// later disposes) its own.
  StickToBottomController({
    ScrollController? scrollController,
    this.threshold = 32.0,
    this.autoScrollDuration = const Duration(milliseconds: 150),
    this.autoScrollCurve = Curves.easeOut,
    bool enabled = true,
  }) : scrollController = scrollController ?? ScrollController(),
       _ownsScrollController = scrollController == null,
       _enabled = enabled {
    this.scrollController.addListener(_handleScrollChanged);
  }

  /// The scroll controller this instance is pinning to the bottom.
  final ScrollController scrollController;

  /// Distance from the bottom edge, in logical pixels, within which the
  /// current scroll position still counts as "pinned".
  final double threshold;

  /// Duration used by [animateToBottom] when no explicit `duration` is
  /// supplied.
  final Duration autoScrollDuration;

  /// Curve used by [animateToBottom] when no explicit `curve` is supplied.
  final Curve autoScrollCurve;

  final bool _ownsScrollController;
  bool _disposed = false;
  bool _followScheduled = false;
  double? _lastPixels;

  final ValueNotifier<bool> _isPinnedToBottom = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _showScrollToBottomButton = ValueNotifier<bool>(
    false,
  );

  bool _enabled;

  /// Whether auto-scroll behaviour is active.
  ///
  /// When `false`, this controller is a transparent passthrough: [follow]
  /// is a no-op, no post-frame scrolling is scheduled, and
  /// [showScrollToBottomButtonListenable] reports `false` regardless of the
  /// actual scroll position. [isPinnedToBottom] keeps tracking the real
  /// position throughout, so behaviour resumes accurately the moment this
  /// is set back to `true` — without forcing a scroll in either direction.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    // Refresh the derived affordance state for the new mode. Never scroll
    // here — flipping `enabled` must never fight the user's position.
    _setPinned(_isPinnedToBottom.value);
  }

  /// Whether the current scroll position is within [threshold] pixels of
  /// [ScrollPosition.maxScrollExtent].
  ///
  /// Tracked continuously from real scroll-position changes regardless of
  /// [enabled], so it always reflects reality.
  bool get isPinnedToBottom => _isPinnedToBottom.value;

  /// Notifies whenever [isPinnedToBottom] changes.
  ValueListenable<bool> get pinnedToBottomListenable => _isPinnedToBottom;

  /// Whether a "jump to bottom" affordance should be shown, i.e. [enabled]
  /// is `true` and [isPinnedToBottom] is `false`.
  ///
  /// Always `false` while [enabled] is `false`. This package does not ship
  /// a button widget — listen to this and render your own.
  ValueListenable<bool> get showScrollToBottomButtonListenable =>
      _showScrollToBottomButton;

  bool get _hasValidPosition =>
      scrollController.hasClients &&
      scrollController.position.hasContentDimensions;

  void _handleScrollChanged() {
    if (_disposed || !_hasValidPosition) return;
    final position = scrollController.position;
    final pixels = position.pixels;
    if (_lastPixels == pixels) {
      // Dimensions changed (e.g. new content appended) but the scroll
      // offset itself did not move — not a real scroll, ignore. Otherwise
      // a content-growth notification firing before our own post-frame
      // scroll runs would spuriously flip `isPinnedToBottom` to `false`.
      return;
    }
    _lastPixels = pixels;
    _setPinned((position.maxScrollExtent - pixels) <= threshold);
  }

  void _setPinned(bool pinned) {
    if (_disposed) return;
    if (_isPinnedToBottom.value != pinned) {
      _isPinnedToBottom.value = pinned;
    }
    final showButton = _enabled && !pinned;
    if (_showScrollToBottomButton.value != showButton) {
      _showScrollToBottomButton.value = showButton;
    }
  }

  /// Requests a scroll-to-bottom after the next frame, but only if
  /// [enabled] and [isPinnedToBottom] are both currently `true`.
  ///
  /// Call this every time new content is appended (e.g. from a
  /// [Listenable] that fires on stream chunks). Scheduling happens via
  /// [WidgetsBinding.addPostFrameCallback] so the scroll targets the
  /// **new** `maxScrollExtent` after layout has caught up with the content
  /// change.
  ///
  /// No-op if disabled, if the user has scrolled away from the bottom, if a
  /// follow is already scheduled for the current frame, or after [dispose].
  void follow({bool animate = true}) {
    if (_disposed || !_enabled || !isPinnedToBottom || _followScheduled) {
      return;
    }
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (_disposed || !_enabled || !isPinnedToBottom) return;
      if (animate) {
        unawaited(animateToBottom());
      } else {
        jumpToBottom();
      }
    });
  }

  /// Immediately scrolls to the bottom, with no animation, and re-pins
  /// (sets [isPinnedToBottom] to `true`).
  ///
  /// Not gated by [enabled] — this is an explicit, imperative action (e.g.
  /// wired up to a "jump to bottom" button tap), unlike the passive
  /// following performed by [follow].
  ///
  /// Safe to call even when [scrollController] is not yet attached to a
  /// scrollable, or has no content dimensions — it is then a no-op.
  void jumpToBottom() {
    if (_disposed || !_hasValidPosition) return;
    final position = scrollController.position;
    scrollController.jumpTo(position.maxScrollExtent);
    _setPinned(true);
  }

  /// Animates to the bottom over [duration] (defaults to
  /// [autoScrollDuration]) using [curve] (defaults to [autoScrollCurve]),
  /// and re-pins (sets [isPinnedToBottom] to `true`) once the animation
  /// settles.
  ///
  /// Not gated by [enabled] — this is an explicit, imperative action (e.g.
  /// wired up to a "jump to bottom" button tap), unlike the passive
  /// following performed by [follow].
  ///
  /// Safe to call even when [scrollController] is not yet attached to a
  /// scrollable, or has no content dimensions — it is then a no-op. Returns
  /// the underlying [ScrollController.animateTo] future.
  Future<void> animateToBottom({Duration? duration, Curve? curve}) async {
    if (_disposed || !_hasValidPosition) return;
    final position = scrollController.position;
    await scrollController.animateTo(
      position.maxScrollExtent,
      duration: duration ?? autoScrollDuration,
      curve: curve ?? autoScrollCurve,
    );
    // The animation may have been interrupted (the user grabbed the list
    // mid-scroll), so reflect the ACTUAL position rather than assuming we
    // reached the bottom.
    if (_disposed || !_hasValidPosition) return;
    final settled = scrollController.position;
    _setPinned((settled.maxScrollExtent - settled.pixels) <= threshold);
  }

  /// Detaches from [scrollController] and disposes internal listenables.
  ///
  /// Disposes [scrollController] itself only if this controller created it
  /// (i.e. no `scrollController` was supplied to the constructor). Safe to
  /// call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scrollController.removeListener(_handleScrollChanged);
    if (_ownsScrollController) {
      scrollController.dispose();
    }
    _isPinnedToBottom.dispose();
    _showScrollToBottomButton.dispose();
  }
}

/// A thin scrollable wrapper that keeps [child] pinned to the bottom while
/// its content grows, and stops following the moment the user scrolls up.
///
/// Wrap a `Column` (or any non-scrolling widget) containing one or more
/// [MarkdownStream]s — or any other growing content — in an [AutoScroll]
/// instead of a bare [SingleChildScrollView]:
///
/// ```dart
/// AutoScroll(
///   child: Column(
///     children: [
///       for (final message in messages) MessageBubble(message),
///     ],
///   ),
/// )
/// ```
///
/// Following happens **automatically** as content grows — including while a
/// [MarkdownStream] streams new tokens inside [child] without [AutoScroll]
/// itself rebuilding. [AutoScroll] listens for the [ScrollMetricsNotification]
/// the scrollable emits when its `maxScrollExtent` changes, so you do **not**
/// have to notify it yourself. (The optional [trigger] remains for the rare
/// case where content resizes without emitting that notification.)
///
/// Auto-scroll is entirely opt-in at the package level: nothing scrolls
/// unless you use [AutoScroll] (or attach a [StickToBottomController]
/// yourself). Wrapping content in [AutoScroll] is itself the developer's
/// opt-in, so [enabled] defaults to `true`; set it to `false` — at any time,
/// it is runtime-changeable — to turn this into a transparent passthrough
/// that never scrolls and never fights the user's own scrolling.
///
/// [AutoScroll] owns its [ScrollController] and [StickToBottomController]
/// unless you supply your own via [controller] — do that if you need to
/// read [StickToBottomController.isPinnedToBottom],
/// [StickToBottomController.showScrollToBottomButtonListenable], or call
/// [StickToBottomController.jumpToBottom] from elsewhere in your widget
/// tree (e.g. to render your own "jump to bottom" button):
///
/// ```dart
/// final stickController = StickToBottomController();
///
/// AutoScroll(
///   controller: stickController,
///   child: messageColumn,
/// );
///
/// // Elsewhere in your tree:
/// ValueListenableBuilder<bool>(
///   valueListenable: stickController.showScrollToBottomButtonListenable,
///   builder: (context, show, _) => show
///       ? FloatingActionButton(
///           onPressed: stickController.jumpToBottom,
///           child: const Icon(Icons.arrow_downward),
///         )
///       : const SizedBox.shrink(),
/// );
/// ```
///
/// Content growth — whether from [AutoScroll] rebuilding with a bigger
/// [child] or from a [MarkdownStream] re-rendering via its own internal
/// `ValueListenableBuilder` — is detected automatically through the
/// scrollable's [ScrollMetricsNotification]. The optional [trigger] is a
/// belt-and-suspenders hook for content that resizes without emitting one.
class AutoScroll extends StatefulWidget {
  /// Creates an auto-scrolling wrapper around [child].
  const AutoScroll({
    super.key,
    required this.child,
    this.trigger,
    this.controller,
    this.enabled = true,
    this.threshold = 32.0,
    this.autoScrollDuration = const Duration(milliseconds: 150),
    this.autoScrollCurve = Curves.easeOut,
    this.padding,
    this.physics,
  });

  /// The scrollable content — typically a `Column` of chat messages, one or
  /// more of which may contain a [MarkdownStream].
  final Widget child;

  /// Optional extra signal to re-check the follow-to-bottom state.
  ///
  /// Usually unnecessary: content growth is detected automatically via the
  /// scrollable's [ScrollMetricsNotification]. Supply a [Listenable] here only
  /// for the rare case where [child] resizes without emitting that
  /// notification; [AutoScroll] schedules a follow after every notification it
  /// fires.
  final Listenable? trigger;

  /// Optional externally-owned controller.
  ///
  /// Supply your own [StickToBottomController] if you need to observe
  /// [StickToBottomController.isPinnedToBottom],
  /// [StickToBottomController.showScrollToBottomButtonListenable], or call
  /// [StickToBottomController.jumpToBottom] / `animateToBottom` from
  /// outside [AutoScroll] (e.g. to render your own "jump to bottom"
  /// button). When omitted, [AutoScroll] creates and disposes its own.
  final StickToBottomController? controller;

  /// Whether auto-scroll behaviour is active.
  ///
  /// Defaults to `true` — wrapping content in [AutoScroll] is itself the
  /// developer's opt-in. Set to `false` to turn this widget into a
  /// transparent passthrough: no following, no post-frame scrolling, no
  /// "jump to bottom" affordance, and the user's manual scroll position is
  /// never fought. Runtime-changeable; picked up on the next build via
  /// [StickToBottomController.enabled].
  final bool enabled;

  /// Distance from the bottom edge, in logical pixels, within which the
  /// view still counts as "pinned". Ignored when [controller] is supplied
  /// (the supplied controller's own threshold applies instead).
  final double threshold;

  /// Duration of the scroll-to-bottom animation. Ignored when [controller]
  /// is supplied.
  final Duration autoScrollDuration;

  /// Curve of the scroll-to-bottom animation. Ignored when [controller] is
  /// supplied.
  final Curve autoScrollCurve;

  /// See [SingleChildScrollView.padding].
  final EdgeInsetsGeometry? padding;

  /// See [SingleChildScrollView.physics].
  final ScrollPhysics? physics;

  @override
  State<AutoScroll> createState() => AutoScrollState();
}

/// State for [AutoScroll].
///
/// Public so a caller who did not supply [AutoScroll.controller] can still
/// reach the live [controller] via a `GlobalKey<AutoScrollState>`.
class AutoScrollState extends State<AutoScroll> {
  StickToBottomController? _ownedController;

  /// The [StickToBottomController] driving this [AutoScroll] — either
  /// [AutoScroll.controller], or one created and owned internally.
  StickToBottomController get controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _ensureController();
    controller.enabled = widget.enabled;
    widget.trigger?.addListener(_handleTrigger);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.enabled) controller.jumpToBottom();
    });
  }

  void _ensureController() {
    if (widget.controller != null) return;
    _ownedController = StickToBottomController(
      threshold: widget.threshold,
      autoScrollDuration: widget.autoScrollDuration,
      autoScrollCurve: widget.autoScrollCurve,
    );
  }

  void _handleTrigger() => controller.follow();

  @override
  void didUpdateWidget(covariant AutoScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      oldWidget.trigger?.removeListener(_handleTrigger);
      widget.trigger?.addListener(_handleTrigger);
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _ownedController?.dispose();
        _ownedController = null;
      }
      _ensureController();
    }
    controller.enabled = widget.enabled;
    controller.follow();
  }

  @override
  void dispose() {
    widget.trigger?.removeListener(_handleTrigger);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A ScrollMetricsNotification fires whenever the scrollable's metrics
    // change *without* a user scroll — most importantly when its content
    // grows and maxScrollExtent increases. Following on that notification is
    // what makes auto-scroll automatic: the caller does NOT have to bump a
    // trigger every time new text streams in. follow() is a no-op unless we
    // are enabled and still pinned to the bottom, so this never yanks a user
    // who has scrolled up to read.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        // Jump (don't animate) while content grows: an animated follow lags
        // behind a fast stream and never catches the newest line. Instant
        // tracking keeps the frontier pinned to the bottom edge, which is how
        // chat UIs stay glued during streaming.
        controller.follow(animate: false);
        return false;
      },
      child: SingleChildScrollView(
        controller: controller.scrollController,
        padding: widget.padding,
        physics: widget.physics,
        child: widget.child,
      ),
    );
  }
}
