/// A family of streaming-cursor widgets suitable for use as the
/// `cursorWidget` parameter of [MarkdownStream].
///
/// Every cursor follows the same convention:
///
///   * `color` — visual colour; defaults to the ambient text colour.
///   * size knobs (varies by cursor: `size`, `width`, `height`, `dotSize`).
///   * `period` — one full animation cycle.
///
/// All cursors manage their own [AnimationController] and dispose it
/// cleanly.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

Color _resolveColor(BuildContext context, Color? explicit) =>
    explicit ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);

// -----------------------------------------------------------------------------
// BlinkingCursor
// -----------------------------------------------------------------------------

/// A simple blinking block cursor — the classic square-wave block.
///
/// Customise colour, size, and blink period if desired. The widget uses an
/// [AnimationController] internally and disposes it correctly.
class BlinkingCursor extends StatefulWidget {
  /// Creates a blinking cursor.
  const BlinkingCursor({
    super.key,
    this.color,
    this.width = 8,
    this.height = 16,
    this.period = const Duration(milliseconds: 900),
  });

  /// Cursor colour. Defaults to the ambient text colour.
  final Color? color;

  /// Cursor width, in logical pixels.
  final double width;

  /// Cursor height, in logical pixels.
  final double height;

  /// Full blink period (on + off).
  final Duration period;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, widget.color);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // Square wave: on for the first half of the period, off for the second.
        return Opacity(
          opacity: _c.value < 0.5 ? 1 : 0,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: color,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// BarCursor
// -----------------------------------------------------------------------------

/// A thin blinking I-beam, like a traditional text cursor.
class BarCursor extends StatefulWidget {
  /// Creates a bar (I-beam) cursor.
  const BarCursor({
    super.key,
    this.color,
    this.width = 2,
    this.height = 16,
    this.period = const Duration(milliseconds: 900),
  });

  /// Bar colour. Defaults to the ambient text colour.
  final Color? color;

  /// Bar width in logical pixels.
  final double width;

  /// Bar height in logical pixels.
  final double height;

  /// Full blink period (on + off).
  final Duration period;

  @override
  State<BarCursor> createState() => _BarCursorState();
}

class _BarCursorState extends State<BarCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, widget.color);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Opacity(
          opacity: _c.value < 0.5 ? 1 : 0,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: color,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// FadingCursor
// -----------------------------------------------------------------------------

/// A soft, sinusoidally-fading block cursor. Gentler than [BlinkingCursor]'s
/// square wave.
class FadingCursor extends StatefulWidget {
  /// Creates a fading cursor.
  const FadingCursor({
    super.key,
    this.color,
    this.width = 8,
    this.height = 16,
    this.period = const Duration(milliseconds: 1200),
  });

  /// Cursor colour.
  final Color? color;

  /// Cursor width.
  final double width;

  /// Cursor height.
  final double height;

  /// Full fade period (one in-out cycle).
  final Duration period;

  @override
  State<FadingCursor> createState() => _FadingCursorState();
}

class _FadingCursorState extends State<FadingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, widget.color);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // sin curve centred at 0.5 with amplitude 0.5 → [0, 1].
        final opacity = 0.5 + 0.5 * math.sin(_c.value * 2 * math.pi);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: color,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// PulsingCursor
// -----------------------------------------------------------------------------

/// A circular dot that breathes — scales in and out smoothly.
class PulsingCursor extends StatefulWidget {
  /// Creates a pulsing (breathing) circular dot cursor.
  const PulsingCursor({
    super.key,
    this.color,
    this.size = 10,
    this.period = const Duration(milliseconds: 1200),
    this.minScale = 0.6,
    this.maxScale = 1,
  }) : assert(
          minScale > 0 && minScale <= maxScale,
          'minScale must be > 0 and <= maxScale',
        );

  /// Dot colour.
  final Color? color;

  /// Dot diameter at max scale.
  final double size;

  /// One breath cycle (in + out).
  final Duration period;

  /// Scale at the quietest point of the breath.
  final double minScale;

  /// Scale at the loudest point of the breath.
  final double maxScale;

  @override
  State<PulsingCursor> createState() => _PulsingCursorState();
}

class _PulsingCursorState extends State<PulsingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, widget.color);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final scale = widget.minScale +
            (widget.maxScale - widget.minScale) *
                Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// TypingDotsCursor
// -----------------------------------------------------------------------------

/// Three dots that fade in and out in sequence — the classic "AI is typing"
/// indicator.
class TypingDotsCursor extends StatefulWidget {
  /// Creates a typing-dots cursor.
  const TypingDotsCursor({
    super.key,
    this.color,
    this.dotSize = 6,
    this.gap = 4,
    this.period = const Duration(milliseconds: 1200),
  });

  /// Dot colour.
  final Color? color;

  /// Individual dot diameter.
  final double dotSize;

  /// Spacing between dots.
  final double gap;

  /// Full cycle duration across all three dots.
  final Duration period;

  @override
  State<TypingDotsCursor> createState() => _TypingDotsCursorState();
}

class _TypingDotsCursorState extends State<TypingDotsCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _dotOpacity(double t, int i) {
    // Each dot peaks at t == phase, where phase is 0.0, 0.33, 0.66.
    final phase = i / 3;
    // Distance on the unit circle (wrap-around).
    var d = (t - phase).abs();
    if (d > 0.5) d = 1 - d;
    // At d == 0: full; at d >= 0.33: min.
    final k = (1 - (d / 0.33)).clamp(0.2, 1.0);
    return k;
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, widget.color);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : widget.gap),
              child: Opacity(
                opacity: _dotOpacity(_c.value, i),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// WaveDotsCursor
// -----------------------------------------------------------------------------

/// Three dots bouncing vertically in a wave pattern.
class WaveDotsCursor extends StatefulWidget {
  /// Creates a wave-dots cursor.
  const WaveDotsCursor({
    super.key,
    this.color,
    this.dotSize = 6,
    this.gap = 4,
    this.amplitude = 4,
    this.period = const Duration(milliseconds: 900),
  });

  /// Dot colour.
  final Color? color;

  /// Individual dot diameter.
  final double dotSize;

  /// Spacing between dots.
  final double gap;

  /// Vertical travel distance, in logical pixels.
  final double amplitude;

  /// Full wave cycle.
  final Duration period;

  @override
  State<WaveDotsCursor> createState() => _WaveDotsCursorState();
}

class _WaveDotsCursorState extends State<WaveDotsCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _dy(double t, int i) {
    final phase = i / 3;
    // sin with stagger → in range [-1, 1].
    final s = math.sin((t - phase) * 2 * math.pi);
    return -s * widget.amplitude; // negative: rising looks up
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, widget.color);
    final totalHeight = widget.dotSize + 2 * widget.amplitude;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return SizedBox(
          height: totalHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List<Widget>.generate(3, (i) {
              return Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : widget.gap),
                child: Transform.translate(
                  offset: Offset(0, _dy(_c.value, i)),
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// SpinnerCursor
// -----------------------------------------------------------------------------

/// A small circular spinner. Backed by [CircularProgressIndicator] so it
/// respects platform conventions on iOS/Android.
class SpinnerCursor extends StatelessWidget {
  /// Creates a spinner cursor.
  const SpinnerCursor({
    super.key,
    this.color,
    this.size = 14,
    this.strokeWidth = 2,
  });

  /// Spinner colour.
  final Color? color;

  /// Outer diameter.
  final double size;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context, this.color);
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ShimmerCursor
// -----------------------------------------------------------------------------

/// A horizontal bar with a highlight that slides across it. Good for
/// "thinking…" placeholders at the end of a response.
class ShimmerCursor extends StatefulWidget {
  /// Creates a shimmer cursor.
  const ShimmerCursor({
    super.key,
    this.baseColor,
    this.highlightColor,
    this.width = 40,
    this.height = 10,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.period = const Duration(milliseconds: 1400),
  });

  /// Bar background colour. Defaults to 20% opacity of ambient text colour.
  final Color? baseColor;

  /// Moving highlight colour. Defaults to 50% opacity of ambient text colour.
  final Color? highlightColor;

  /// Bar width.
  final double width;

  /// Bar height.
  final double height;

  /// Corner radius.
  final BorderRadiusGeometry borderRadius;

  /// One full sweep.
  final Duration period;

  @override
  State<ShimmerCursor> createState() => _ShimmerCursorState();
}

class _ShimmerCursorState extends State<ShimmerCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambient = _resolveColor(context, null);
    final base = widget.baseColor ?? ambient.withValues(alpha: 0.20);
    final highlight = widget.highlightColor ?? ambient.withValues(alpha: 0.50);
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            // Sweep from -1 → 2 so highlight enters and exits fully.
            final stop = -1 + 3 * _c.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: base,
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[base, highlight, base],
                  stops: <double>[
                    (stop - 0.2).clamp(0.0, 1.0),
                    stop.clamp(0.0, 1.0),
                    (stop + 0.2).clamp(0.0, 1.0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
