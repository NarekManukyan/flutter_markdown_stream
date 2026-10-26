/// Line-by-line tracking of fenced code blocks, shared by the sanitizer and
/// the incremental splitter so both agree on where code blocks start and end.
library;

/// Tracks whether a stream of Markdown lines is currently inside a fenced
/// code block.
///
/// Follows the CommonMark rules that matter for streaming:
///
/// * A fence is a run of 3+ backticks or 3+ tildes. Any indentation is
///   accepted so fences nested inside list items (indented 4+ spaces) are
///   recognised.
/// * A backtick fence's info string may not contain a backtick, so a line
///   like ```` ```js const a``` ```` is not a fence.
/// * A closing fence uses the opening character, is at least as long as the
///   opening fence, and carries no info string. A line such as ```` ```python ````
///   inside an open block is code content, not a closer.
final class FenceTracker {
  static final RegExp _fenceLine = RegExp(r'^([ \t]*)(`{3,}|~{3,})(.*)$');

  String? _char;
  var _length = 0;
  var _indent = '';

  /// The leading whitespace of the open block's opening fence, so a
  /// synthetic closer can be placed at the same indentation (and so stay
  /// inside the same list item).
  String get openIndent => _indent;

  /// Whether the lines fed so far end inside an unclosed fenced code block.
  bool get isOpen => _char != null;

  /// The fence character (`` ` `` or `~`) of the open block, or `null`.
  String? get openChar => _char;

  /// The fence length of the open block, or `0`.
  int get openLength => _length;

  /// Feeds one line (without its trailing newline) and returns `true` when
  /// the line opened or closed a fenced code block.
  bool addLine(String line) {
    final m = _fenceLine.firstMatch(line);
    if (m == null) return false;
    final indent = m.group(1)!;
    final run = m.group(2)!;
    final rest = m.group(3)!;
    final ch = run[0];
    if (_char == null) {
      if (ch == '`' && rest.contains('`')) return false;
      _char = ch;
      _length = run.length;
      _indent = indent;
      return true;
    }
    if (ch == _char && run.length >= _length && rest.trim().isEmpty) {
      _char = null;
      _length = 0;
      _indent = '';
      return true;
    }
    return false;
  }
}

/// Returns [input] with every fenced code block, fence lines included,
/// replaced by [mask] characters. Line breaks and length are kept, so an
/// offset in the result is the same offset in [input].
String maskFencedCode(String input, String mask) {
  final out = StringBuffer();
  final fences = FenceTracker();
  final lines = input.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final wasOpen = fences.isOpen;
    // A CRLF line keeps its `\r` here; the fence pattern does not match it.
    final isFence = fences.addLine(
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    );
    out.write(wasOpen || isFence ? mask * line.length : line);
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}
