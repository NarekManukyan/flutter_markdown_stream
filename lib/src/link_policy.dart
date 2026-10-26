/// Which link and image destinations a `MarkdownStream` renders as live links
/// and images. Model output is untrusted input, so by default only web and
/// mail links and web images are allowed.
library;

import 'package:flutter/foundation.dart';

import 'fence_tracker.dart';

/// Decides which link and image destinations are allowed.
///
/// A blocked link renders as its label in plain text and never reaches
/// `onTapLink`. A blocked image renders as its alt text. This stops output
/// like `[click](javascript:...)`, `![x](file:///etc/hosts)` or a `data:`
/// image from doing anything when the user taps or scrolls.
///
/// ```dart
/// MarkdownStream(
///   stream: llmStream,
///   // Also allow your app's deep links.
///   linkPolicy: const LinkPolicy(
///     linkSchemes: {'http', 'https', 'mailto', 'myapp'},
///   ),
/// );
/// ```
///
/// Pass `linkPolicy: null` to `MarkdownStream` to turn filtering off.
@immutable
class LinkPolicy {
  /// Creates a policy. The defaults allow `http`, `https` and `mailto` links,
  /// relative links such as `#section`, and `http`/`https` images.
  const LinkPolicy({
    this.linkSchemes = const <String>{'http', 'https', 'mailto'},
    this.imageSchemes = const <String>{'http', 'https'},
    this.allowRelativeLinks = true,
    this.allowRelativeImages = false,
  });

  /// Lower-case URL schemes allowed for links.
  final Set<String> linkSchemes;

  /// Lower-case URL schemes allowed for images.
  final Set<String> imageSchemes;

  /// Whether links without a scheme (`#notes`, `/docs`, `page.html`) are
  /// allowed. They are passed to `onTapLink` unchanged, so your handler
  /// decides what they mean.
  final bool allowRelativeLinks;

  /// Whether images without a scheme are allowed. Off by default because
  /// `MarkdownBody` loads such paths from the local file system.
  /// `MarkdownStream` turns this on when you set `imageDirectory`.
  final bool allowRelativeImages;

  /// Whether a link to [href] may be shown and tapped.
  bool allowsLink(String? href) {
    if (href == null) return true;
    final scheme = schemeOf(href);
    return scheme == null ? allowRelativeLinks : linkSchemes.contains(scheme);
  }

  /// Whether an image at [src] may be loaded.
  bool allowsImage(String src) {
    final scheme = schemeOf(src);
    return scheme == null ? allowRelativeImages : imageSchemes.contains(scheme);
  }

  /// The lower-case scheme of [destination] as a URL parser would read it,
  /// or `null` for a relative destination.
  ///
  /// Undoes the tricks that hide a scheme from a naive check: character
  /// references (`javascript&#58;`), backslash escapes (`javascript\:`), and
  /// whitespace or control characters inside the scheme (`java\tscript:`).
  static String? schemeOf(String destination) {
    var d = destination.trim();
    if (d.startsWith('<') && d.endsWith('>') && d.length >= 2) {
      d = d.substring(1, d.length - 1);
    }
    d = d
        .replaceAllMapped(_entity, _decodeEntity)
        .replaceAll(_escape, '')
        .replaceAll(_ignored, '');
    return _scheme.firstMatch(d)?.group(1)!.toLowerCase();
  }

  /// Rewrites [markdown] so blocked inline links show only their label,
  /// blocked inline images only their alt text, blocked autolinks
  /// (`<javascript:...>`) their plain text, and link reference definitions
  /// with a blocked destination are removed. Code spans and fenced code are
  /// left alone.
  String apply(String markdown) {
    if (!markdown.contains('](') &&
        !markdown.contains('<') &&
        !markdown.contains(']:')) {
      return markdown;
    }
    return _rewrite(markdown);
  }

  String _rewrite(String input) {
    final masked = _maskCode(input);
    final out = StringBuffer();
    var copied = 0;
    var i = 0;

    while (i < masked.length) {
      final c = masked.codeUnitAt(i);

      // Link reference definition at the start of a line.
      if (c == _lbracket && _atLineStart(masked, i)) {
        final def = _definition(masked, i);
        if (def != null && !_allowsEither(input.substring(def.$2, def.$3))) {
          out.write(input.substring(copied, i));
          copied = def.$1;
          i = def.$1;
          continue;
        }
      }

      if (c == _lbracket && !_escaped(input, i)) {
        final isImage = i > 0 && masked[i - 1] == '!' && !_escaped(input, i - 1);
        final link = _inlineLink(masked, i);
        if (link != null) {
          final (labelEnd, destStart, destEnd, end) = link;
          final dest = input.substring(destStart, destEnd);
          final allowed = isImage ? allowsImage(dest) : allowsLink(dest);
          if (!allowed) {
            final start = isImage ? i - 1 : i;
            out
              ..write(input.substring(copied, start))
              ..write(_rewrite(input.substring(i + 1, labelEnd)));
            copied = end;
            i = end;
            continue;
          }
        }
      }

      if (c == _lt) {
        final close = masked.indexOf('>', i + 1);
        if (close != -1) {
          final inner = input.substring(i + 1, close);
          final scheme = _autolinkScheme(inner);
          if (scheme != null && !linkSchemes.contains(scheme)) {
            out
              ..write(input.substring(copied, i))
              ..write(inner);
            copied = close + 1;
            i = close + 1;
            continue;
          }
        }
      }

      i++;
    }

    if (copied == 0) return input;
    out.write(input.substring(copied));
    return out.toString();
  }

  // A definition is used by both links and images, so it stays only when
  // both kinds would accept it.
  bool _allowsEither(String dest) => allowsLink(dest) && allowsImage(dest);

  @override
  bool operator ==(Object other) =>
      other is LinkPolicy &&
      setEquals(other.linkSchemes, linkSchemes) &&
      setEquals(other.imageSchemes, imageSchemes) &&
      other.allowRelativeLinks == allowRelativeLinks &&
      other.allowRelativeImages == allowRelativeImages;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(linkSchemes),
        Object.hashAllUnordered(imageSchemes),
        allowRelativeLinks,
        allowRelativeImages,
      );

  @override
  String toString() => 'LinkPolicy(links: $linkSchemes, images: $imageSchemes, '
      'relativeLinks: $allowRelativeLinks, '
      'relativeImages: $allowRelativeImages)';
}

const int _lbracket = 0x5B; // [
const int _lt = 0x3C; // <
const String _mask = '\u0001';

final RegExp _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');
final RegExp _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|colon);?');
final RegExp _escape = RegExp(r'\\(?=[!-/:-@\[-`{-~])');
final RegExp _ignored = RegExp(r'[\u0000-\u0020\u007F-\u009F]');
final RegExp _email = RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$');
final RegExp _autolinkUri = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]{1,31}:[^\s<>]*$');

String _decodeEntity(Match m) {
  final body = m.group(1)!;
  if (body == 'colon') return ':';
  final code = body.startsWith('#x') || body.startsWith('#X')
      ? int.tryParse(body.substring(2), radix: 16)
      : int.tryParse(body.substring(1));
  if (code == null || code > 0x10FFFF) return m.group(0)!;
  return String.fromCharCode(code);
}

/// The scheme of an autolink body (`https://x.com`, `a@b.com`), or `null`
/// when `<...>` is not an autolink.
String? _autolinkScheme(String inner) {
  if (_autolinkUri.hasMatch(inner)) return LinkPolicy.schemeOf(inner);
  if (_email.hasMatch(inner)) return 'mailto';
  return null;
}

bool _escaped(String s, int i) {
  var n = 0;
  for (var k = i - 1; k >= 0 && s[k] == r'\'; k--) {
    n++;
  }
  return n.isOdd;
}

bool _atLineStart(String s, int i) {
  var k = i - 1;
  var spaces = 0;
  while (k >= 0 && s[k] == ' ') {
    k--;
    spaces++;
  }
  return spaces <= 3 && (k < 0 || s[k] == '\n');
}

/// Same-length copy of [s] with fenced code and code spans masked, so their
/// brackets and angle brackets are never read as syntax.
String _maskCode(String s) {
  final chars = maskFencedCode(s, _mask).split('');
  var i = 0;
  while (i < chars.length) {
    if (chars[i] != '`') {
      i++;
      continue;
    }
    var j = i;
    while (j < chars.length && chars[j] == '`') {
      j++;
    }
    final len = j - i;
    var k = j;
    var closeAt = -1;
    while (k < chars.length) {
      if (chars[k] != '`') {
        k++;
        continue;
      }
      var r = k;
      while (r < chars.length && chars[r] == '`') {
        r++;
      }
      if (r - k == len) {
        closeAt = k;
        break;
      }
      k = r;
    }
    if (closeAt == -1) {
      i = j;
      continue;
    }
    for (var m = i; m < closeAt + len; m++) {
      if (chars[m] != '\n') chars[m] = _mask;
    }
    i = closeAt + len;
  }
  return chars.join();
}

/// Index of the `]` matching the `[` at [open], or -1. Gives up at a blank
/// line, where the paragraph (and any link) ends.
int _closingBracket(String s, int open) {
  var depth = 0;
  for (var k = open + 1; k < s.length; k++) {
    final c = s[k];
    if (c == r'\') {
      k++;
    } else if (c == '[') {
      depth++;
    } else if (c == ']') {
      if (depth == 0) return k;
      depth--;
    } else if (c == '\n' && _blankLineFollows(s, k)) {
      return -1;
    }
  }
  return -1;
}

bool _blankLineFollows(String s, int newline) {
  for (var k = newline + 1; k < s.length; k++) {
    final c = s[k];
    if (c == '\n') return true;
    if (c != ' ' && c != '\t') return false;
  }
  return true;
}

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n';

/// Parses an inline link or image starting at the `[` at [open]:
/// `[label](dest "title")`. Returns the label end (the `]`), the destination
/// range and the index after the closing `)`, or `null`.
(int, int, int, int)? _inlineLink(String s, int open) {
  final labelEnd = _closingBracket(s, open);
  if (labelEnd == -1 || labelEnd + 1 >= s.length || s[labelEnd + 1] != '(') {
    return null;
  }
  var j = labelEnd + 2;
  while (j < s.length && _isSpace(s[j])) {
    j++;
  }
  int destStart;
  int destEnd;
  if (j < s.length && s[j] == '<') {
    final close = s.indexOf('>', j + 1);
    final lineEnd = s.indexOf('\n', j);
    if (close == -1 || (lineEnd != -1 && lineEnd < close)) return null;
    destStart = j + 1;
    destEnd = close;
    j = close + 1;
  } else {
    destStart = j;
    var depth = 0;
    while (j < s.length) {
      final c = s[j];
      if (c == r'\') {
        j += 2;
        continue;
      }
      if (_isSpace(c)) break;
      if (c == '(') depth++;
      if (c == ')') {
        if (depth == 0) break;
        depth--;
      }
      j++;
    }
    if (j > s.length) j = s.length;
    destEnd = j;
  }
  while (j < s.length && _isSpace(s[j])) {
    j++;
  }
  if (j < s.length && (s[j] == '"' || s[j] == "'" || s[j] == '(')) {
    final closer = s[j] == '(' ? ')' : s[j];
    final close = s.indexOf(closer, j + 1);
    if (close == -1) return null;
    j = close + 1;
    while (j < s.length && _isSpace(s[j])) {
      j++;
    }
  }
  if (j >= s.length || s[j] != ')') return null;
  return (labelEnd, destStart, destEnd, j + 1);
}

/// Parses a link reference definition (`[label]: dest`) starting at the `[`
/// at [open]. Returns the index after the line and the destination range,
/// or `null`.
(int, int, int)? _definition(String s, int open) {
  final labelEnd = _closingBracket(s, open);
  if (labelEnd == -1 ||
      labelEnd + 1 >= s.length ||
      s[labelEnd + 1] != ':' ||
      labelEnd == open + 1) {
    return null;
  }
  var j = labelEnd + 2;
  while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
    j++;
  }
  if (j < s.length && s[j] == '\n') j++;
  while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
    j++;
  }
  if (j >= s.length) return null;
  int destStart;
  int destEnd;
  if (s[j] == '<') {
    final close = s.indexOf('>', j + 1);
    if (close == -1) return null;
    destStart = j + 1;
    destEnd = close;
  } else {
    destStart = j;
    while (j < s.length && !_isSpace(s[j])) {
      j++;
    }
    destEnd = j;
  }
  if (destEnd == destStart) return null;
  final lineEnd = s.indexOf('\n', destEnd);
  return (lineEnd == -1 ? s.length : lineEnd, destStart, destEnd);
}
