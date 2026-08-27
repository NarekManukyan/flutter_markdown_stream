import 'package:flutter/material.dart';
import 'package:flutter_markdown_stream/src/auto_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [ChangeNotifier] subclass that exposes [hasListeners] publicly, used
/// to assert that [AutoScroll] removes its trigger listener on dispose.
class _ListenerProbe extends ChangeNotifier {
  /// Whether anything is currently listening to this notifier.
  bool get isListened => hasListeners;
}

/// Builds a fixed-height (300px) [AutoScroll] harness with [itemCount]
/// 60px-tall tiles, wired to [controller].
Widget _harness({
  required StickToBottomController controller,
  required int itemCount,
  Listenable? trigger,
  bool enabled = true,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 300,
      child: AutoScroll(
        controller: controller,
        trigger: trigger,
        enabled: enabled,
        child: Column(
          children: List<Widget>.generate(
            itemCount,
            (i) => SizedBox(height: 60, child: Text('item $i')),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('StickToBottomController (unit)', () {
    test('defaults', () {
      final controller = StickToBottomController();
      expect(controller.isPinnedToBottom, isTrue);
      expect(controller.enabled, isTrue);
      expect(controller.showScrollToBottomButtonListenable.value, isFalse);
      controller.dispose();
    });

    test(
      'creates and disposes its own ScrollController when none supplied',
      () {
        final controller = StickToBottomController();
        final scrollController = controller.scrollController;
        expect(scrollController.hasClients, isFalse);
        controller.dispose();
        // The controller-owned ScrollController must be disposed too.
        expect(
          () => scrollController.addListener(() {}),
          throwsA(isA<FlutterError>()),
        );
      },
    );

    test('does not dispose an externally-supplied ScrollController', () {
      final externalScrollController = ScrollController();
      final controller = StickToBottomController(
        scrollController: externalScrollController,
      );
      controller.dispose();
      expect(
        () => externalScrollController.addListener(() {}),
        returnsNormally,
      );
      externalScrollController.dispose();
    });

    test('jumpToBottom/animateToBottom are no-ops without an attached '
        'position', () async {
      final controller = StickToBottomController();
      expect(controller.jumpToBottom, returnsNormally);
      await controller.animateToBottom();
      controller.dispose();
    });

    test('enabled setter is a no-op after dispose', () {
      final controller = StickToBottomController();
      controller.dispose();
      expect(() => controller.enabled = false, returnsNormally);
    });
  });

  group('AutoScroll (widget)', () {
    testWidgets('stays pinned to the bottom as content grows', (tester) async {
      final controller = StickToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();

      expect(controller.isPinnedToBottom, isTrue);
      var position = controller.scrollController.position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

      // Grow the content — more messages arrive.
      await tester.pumpWidget(_harness(controller: controller, itemCount: 15));
      await tester.pumpAndSettle();

      expect(controller.isPinnedToBottom, isTrue);
      position = controller.scrollController.position;
      expect(position.maxScrollExtent, greaterThan(300));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    });

    testWidgets(
      'scrolling up disengages pinning; new content does not force-scroll',
      (tester) async {
        final controller = StickToBottomController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _harness(controller: controller, itemCount: 10),
        );
        await tester.pumpAndSettle();
        expect(controller.isPinnedToBottom, isTrue);

        // Drag the finger down: reveals earlier content, moving away from
        // the bottom edge.
        await tester.drag(find.byType(AutoScroll), const Offset(0, 200));
        await tester.pumpAndSettle();

        expect(controller.isPinnedToBottom, isFalse);
        expect(controller.showScrollToBottomButtonListenable.value, isTrue);
        final pixelsAfterScrollUp = controller.scrollController.position.pixels;
        expect(
          pixelsAfterScrollUp,
          lessThan(controller.scrollController.position.maxScrollExtent),
        );

        // New content arrives — must not yank the view back down.
        await tester.pumpWidget(
          _harness(controller: controller, itemCount: 15),
        );
        await tester.pumpAndSettle();

        expect(controller.isPinnedToBottom, isFalse);
        expect(
          controller.scrollController.position.pixels,
          closeTo(pixelsAfterScrollUp, 0.5),
        );
      },
    );

    testWidgets('returning to the bottom re-pins and resumes following', (
      tester,
    ) async {
      final controller = StickToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(AutoScroll), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(controller.isPinnedToBottom, isFalse);

      // Drag back up (toward the bottom), far enough to hit the clamp.
      await tester.drag(find.byType(AutoScroll), const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(controller.isPinnedToBottom, isTrue);
      expect(controller.showScrollToBottomButtonListenable.value, isFalse);

      // Following resumes: new content pulls the view back down.
      await tester.pumpWidget(_harness(controller: controller, itemCount: 15));
      await tester.pumpAndSettle();

      expect(controller.isPinnedToBottom, isTrue);
      final position = controller.scrollController.position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    });

    testWidgets('auto-follows content growing INSIDE child, no trigger, without '
        'AutoScroll itself rebuilding', (tester) async {
      final controller = StickToBottomController();
      addTearDown(controller.dispose);
      final growing = ValueNotifier<double>(400);
      addTearDown(growing.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: AutoScroll(
                controller: controller,
                // No `trigger:` supplied.
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 400, child: Text('head')),
                    // Only THIS subtree rebuilds when `growing` changes;
                    // AutoScroll's didUpdateWidget never runs.
                    ValueListenableBuilder<double>(
                      valueListenable: growing,
                      builder: (_, h, __) =>
                          SizedBox(height: h, child: const Text('tail')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.isPinnedToBottom, isTrue);

      // Grow only the inner box. This changes maxScrollExtent and fires a
      // ScrollMetricsNotification — which is what AutoScroll follows.
      growing.value = 900;
      await tester.pumpAndSettle();

      final position = controller.scrollController.position;
      expect(controller.isPinnedToBottom, isTrue);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    });

    testWidgets('enabled=false stops following and preserves the manual scroll '
        'position; re-enabling resumes following', (tester) async {
      final controller = StickToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();
      expect(controller.isPinnedToBottom, isTrue);

      // Disable mid-stream.
      await tester.pumpWidget(
        _harness(controller: controller, itemCount: 10, enabled: false),
      );
      await tester.pumpAndSettle();
      expect(controller.enabled, isFalse);

      // The user scrolls away by hand while disabled.
      await tester.drag(find.byType(AutoScroll), const Offset(0, 200));
      await tester.pumpAndSettle();
      final manualPixels = controller.scrollController.position.pixels;
      expect(
        controller.scrollController.position.maxScrollExtent - manualPixels,
        greaterThan(32),
      );
      // No affordance is shown while disabled, even though the position
      // is far from the bottom.
      expect(controller.showScrollToBottomButtonListenable.value, isFalse);

      // Growing content while disabled must not move the scroll position.
      await tester.pumpWidget(
        _harness(controller: controller, itemCount: 15, enabled: false),
      );
      await tester.pumpAndSettle();
      expect(
        controller.scrollController.position.pixels,
        closeTo(manualPixels, 0.5),
      );

      // The user scrolls back to the bottom by hand, then the app
      // re-enables auto-scroll: it re-pins without forcing a jump, and
      // subsequent growth is followed again.
      await tester.drag(find.byType(AutoScroll), const Offset(0, -1000));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _harness(controller: controller, itemCount: 15, enabled: true),
      );
      await tester.pumpAndSettle();
      expect(controller.enabled, isTrue);
      expect(controller.isPinnedToBottom, isTrue);

      await tester.pumpWidget(
        _harness(controller: controller, itemCount: 20, enabled: true),
      );
      await tester.pumpAndSettle();
      final position = controller.scrollController.position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    });

    testWidgets('a disabled controller never shows the jump-to-bottom '
        'affordance', (tester) async {
      final controller = StickToBottomController(enabled: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(controller: controller, itemCount: 15, enabled: false),
      );
      await tester.pumpAndSettle();

      // A disabled controller does NOT auto-scroll to the bottom on mount, so
      // drive it to the bottom explicitly (imperative jump is not gated by
      // `enabled`) before scrolling away — otherwise the view starts at the
      // top and a further up-drag cannot change the pinned state.
      controller.jumpToBottom();
      await tester.pumpAndSettle();

      await tester.drag(find.byType(AutoScroll), const Offset(0, 200));
      await tester.pumpAndSettle();

      // Genuinely scrolled away from the bottom now...
      expect(controller.isPinnedToBottom, isFalse);
      // ...yet the affordance stays hidden because the controller is disabled.
      expect(controller.showScrollToBottomButtonListenable.value, isFalse);
    });

    testWidgets('dispose does not throw and removes the trigger listener', (
      tester,
    ) async {
      final controller = StickToBottomController();
      final probe = _ListenerProbe();

      await tester.pumpWidget(
        _harness(controller: controller, itemCount: 10, trigger: probe),
      );
      await tester.pumpAndSettle();
      expect(probe.isListened, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(probe.isListened, isFalse);
      expect(controller.dispose, returnsNormally);
      expect(controller.dispose, returnsNormally); // idempotent
      expect(probe.dispose, returnsNormally);
    });

    testWidgets(
      'disposes an internally-owned controller cleanly when unmounted',
      (tester) async {
        final key = GlobalKey<AutoScrollState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: AutoScroll(
                  key: key,
                  child: Column(
                    children: List<Widget>.generate(
                      10,
                      (i) => SizedBox(height: 60, child: Text('item $i')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(key.currentState!.controller.isPinnedToBottom, isTrue);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
