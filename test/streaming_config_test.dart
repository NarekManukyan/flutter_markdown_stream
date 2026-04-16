import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingTextConfig', () {
    test('default values', () {
      const c = StreamingTextConfig();
      expect(c.rebuildDebounce, const Duration(milliseconds: 16));
      expect(c.fadeInEnabled, isFalse);
      expect(c.fadeInDuration, const Duration(milliseconds: 300));
      expect(c.fadeInCurve, Curves.easeOut);
      expect(c.trailingFadeHeight, 40);
    });

    test('is const-constructible', () {
      const c1 = StreamingTextConfig();
      const c2 = StreamingTextConfig();
      expect(identical(c1, c2), isTrue);
    });

    test('copyWith replaces fields', () {
      const base = StreamingTextConfig();
      final next = base.copyWith(
        rebuildDebounce: const Duration(milliseconds: 99),
        fadeInEnabled: true,
      );
      expect(next.rebuildDebounce, const Duration(milliseconds: 99));
      expect(next.fadeInEnabled, isTrue);
      // Unchanged fields preserved.
      expect(next.fadeInDuration, base.fadeInDuration);
      expect(next.fadeInCurve, base.fadeInCurve);
    });

    test('equality and hashCode follow value semantics', () {
      const a = StreamingTextConfig(fadeInEnabled: true);
      const b = StreamingTextConfig(fadeInEnabled: true);
      const c = StreamingTextConfig(fadeInEnabled: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString is informative', () {
      const c = StreamingTextConfig(fadeInEnabled: true);
      expect(c.toString(), contains('fadeInEnabled: true'));
    });
  });

  group('StreamingPresets', () {
    test('chatGPT preset values', () {
      const p = StreamingPresets.chatGPT;
      expect(p.rebuildDebounce, const Duration(milliseconds: 15));
      expect(p.fadeInEnabled, isTrue);
    });

    test('claude preset values', () {
      const p = StreamingPresets.claude;
      expect(p.rebuildDebounce, const Duration(milliseconds: 80));
      expect(p.fadeInEnabled, isTrue);
      expect(p.fadeInCurve, Curves.easeInOutCubic);
    });

    test('instant preset has zero debounce and no fade', () {
      const p = StreamingPresets.instant;
      expect(p.rebuildDebounce, Duration.zero);
      expect(p.fadeInEnabled, isFalse);
    });

    test('typewriter preset has 50ms debounce and no fade', () {
      const p = StreamingPresets.typewriter;
      expect(p.rebuildDebounce, const Duration(milliseconds: 50));
      expect(p.fadeInEnabled, isFalse);
    });

    test('gentle and fast presets both enable fade', () {
      expect(StreamingPresets.gentle.fadeInEnabled, isTrue);
      expect(StreamingPresets.fast.fadeInEnabled, isTrue);
    });
  });
}
