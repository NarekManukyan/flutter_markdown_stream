/// Shared motion values, so every animation in the package uses the same
/// curve and duration scale.
library;

import 'package:flutter/animation.dart';

/// Strong ease-out for things entering or settling: starts fast, so the
/// change is visible right away, then glides into place.
const Cubic kStreamEaseOut = Cubic(0.23, 1, 0.32, 1);

/// How long a newly streamed word takes to fade in.
const Duration kWordFadeDuration = Duration(milliseconds: 300);

/// Duration of small state swaps such as the code block's Copy → Copied.
const Duration kSwapDuration = Duration(milliseconds: 160);
