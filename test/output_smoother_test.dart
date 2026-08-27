import 'package:fake_async/fake_async.dart';
import 'package:flutter_markdown_stream/src/output_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutputSmoother pacing', () {
    test('reveals ~half at 500ms and all by ~1s for 100 chars @ 100 cps', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(charsPerSecond: 100);
        final String target = 'a' * 100;

        smoother.push(target);
        async.elapse(const Duration(milliseconds: 500));
        expect(smoother.value.length, closeTo(50, 10));
        expect(target.startsWith(smoother.value), isTrue);

        async.elapse(const Duration(milliseconds: 600));
        expect(smoother.value, target);

        smoother.dispose();
      });
    });

    test('does not reveal anything before the first tick fires', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(charsPerSecond: 100);
        smoother.push('hello world');
        expect(smoother.value, isEmpty);
        smoother.dispose();
      });
    });

    test('streams growing prefixes via revealed', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(
          charsPerSecond: 100,
          tickInterval: const Duration(milliseconds: 10),
        );
        final events = <String>[];
        smoother.revealed.listen(events.add);
        final String target = 'b' * 20;

        smoother.push(target);
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        expect(events, isNotEmpty);
        for (int i = 1; i < events.length; i++) {
          expect(events[i].length, greaterThanOrEqualTo(events[i - 1].length));
          expect(target.startsWith(events[i]), isTrue);
        }
        expect(events.last, target);

        smoother.dispose();
      });
    });
  });

  group('OutputSmoother.complete', () {
    test('flushes remaining backlog within finishDuration then closes', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(
          charsPerSecond: 5,
          finishDuration: const Duration(milliseconds: 200),
        );
        final String target = 'c' * 300;
        bool done = false;
        smoother.revealed.listen(null, onDone: () => done = true);

        smoother.push(target);
        async.elapse(const Duration(milliseconds: 50));
        expect(smoother.value.length, lessThan(target.length));

        smoother.complete();
        // Elapse well past finishDuration to absorb tick quantization.
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        expect(smoother.value, target);
        expect(done, isTrue);
      });
    });

    test('closes immediately when there is no backlog', () {
      fakeAsync((async) {
        final smoother = OutputSmoother();
        bool done = false;
        smoother.revealed.listen(null, onDone: () => done = true);

        smoother.complete();
        async.flushMicrotasks();

        expect(done, isTrue);
      });
    });
  });

  group('OutputSmoother.snapToEnd', () {
    test('reveals everything synchronously without elapsing time', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(charsPerSecond: 10);
        final String target = 'd' * 500;

        smoother.push(target);
        expect(smoother.value, isEmpty);

        smoother.snapToEnd();
        expect(smoother.value, target);

        smoother.dispose();
      });
    });
  });

  group('OutputSmoother backlog catch-up', () {
    test('accelerates once backlog exceeds maxBacklogChars', () {
      fakeAsync((async) {
        // A very high cap means catch-up never triggers: flat charsPerSecond.
        final baseline = OutputSmoother(
          charsPerSecond: 100,
          maxBacklogChars: 1000000,
        )..push('e' * 2000);
        async.elapse(const Duration(milliseconds: 500));
        final int baselineRevealed = baseline.value.length;
        baseline.dispose();

        final accelerated = OutputSmoother(
          charsPerSecond: 100,
          maxBacklogChars: 200,
          catchUpMultiplier: 5,
        )..push('e' * 2000);
        async.elapse(const Duration(milliseconds: 500));
        final int acceleratedRevealed = accelerated.value.length;
        accelerated.dispose();

        expect(acceleratedRevealed, greaterThan(baselineRevealed * 2));
      });
    });
  });

  group('OutputSmoother reset', () {
    test('resets to empty and reveals a shorter target after push', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(charsPerSecond: 100);

        smoother.push('f' * 50);
        async.elapse(const Duration(milliseconds: 100));
        expect(smoother.value, isNotEmpty);
        expect(smoother.value.length, lessThan(50));

        final String shorterTarget = 'g' * 10;
        smoother.push(shorterTarget);
        expect(smoother.value, isEmpty);

        async.elapse(const Duration(milliseconds: 300));
        expect(smoother.value, shorterTarget);
        expect(smoother.value.length, lessThanOrEqualTo(10));

        smoother.dispose();
      });
    });
  });

  group('OutputSmoother.dispose', () {
    test('stops further emissions and ignores subsequent calls', () {
      fakeAsync((async) {
        final smoother = OutputSmoother(charsPerSecond: 100);
        bool done = false;
        smoother.revealed.listen(null, onDone: () => done = true);

        smoother.push('h' * 100);
        async.elapse(const Duration(milliseconds: 100));
        final String snapshot = smoother.value;
        expect(snapshot, isNotEmpty);

        smoother.dispose();
        async.flushMicrotasks();
        expect(done, isTrue);

        async.elapse(const Duration(milliseconds: 500));
        expect(smoother.value, snapshot);

        smoother.push('h' * 200);
        expect(smoother.value, snapshot);

        smoother.complete();
        smoother.snapToEnd();
        expect(smoother.value, snapshot);
      });
    });
  });
}
