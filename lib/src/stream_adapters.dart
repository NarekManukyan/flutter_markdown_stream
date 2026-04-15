/// Ready-made converters for turning typed data streams into the
/// `Stream<String>` that `MarkdownStream` consumes.
///
/// Three adapters cover most real-world cases:
///
/// * [StreamAdapters.utf8Bytes] — decode a raw byte stream (HTTP body, file)
///   as UTF-8, safely handling multi-byte code points split across chunks.
/// * [StreamAdapters.serverSentEvents] — parse an OpenAI / Anthropic /
///   any-vendor SSE stream, buffering incomplete lines across chunks and
///   honouring a `[DONE]` sentinel.
/// * [StreamAdapters.jsonField] — extract a (possibly nested) string field
///   from each JSON chunk. Malformed chunks are silently dropped.
///
/// For anything else, just call [Stream.map] directly — nothing magical
/// happens in these adapters that you can't do inline.
library;

import 'dart:async';
import 'dart:convert';

/// Utilities for converting typed data streams into the `Stream<String>`
/// expected by `MarkdownStream`.
final class StreamAdapters {
  const StreamAdapters._();

  /// Decodes a byte stream as UTF-8, preserving multi-byte characters that
  /// straddle chunk boundaries.
  static Stream<String> utf8Bytes(Stream<List<int>> source) =>
      source.transform(utf8.decoder);

  /// Parses a Server-Sent Events stream and yields each event's `data:`
  /// payload as a separate event.
  ///
  /// * Input must already be decoded strings (use [utf8Bytes] first if
  ///   you're starting from bytes).
  /// * Lines that span chunk boundaries are buffered correctly.
  /// * When a payload equals [doneSentinel] (default `[DONE]`, per the
  ///   OpenAI convention), the output stream closes.
  /// * Non-`data:` lines (`event:`, `id:`, comments, blank lines) are
  ///   ignored. If you need them, roll your own.
  ///
  /// Typical pipeline for an OpenAI-style HTTP stream:
  ///
  /// ```dart
  /// final text = StreamAdapters.jsonField(
  ///   StreamAdapters.serverSentEvents(
  ///     StreamAdapters.utf8Bytes(response.stream),
  ///   ),
  ///   <Object>['choices', 0, 'delta', 'content'],
  /// );
  /// MarkdownStream(stream: text, ...);
  /// ```
  static Stream<String> serverSentEvents(
    Stream<String> source, {
    String doneSentinel = '[DONE]',
  }) async* {
    final buffer = StringBuffer();
    await for (final chunk in source) {
      buffer.write(chunk);
      final text = buffer.toString();
      final lastNewline = text.lastIndexOf('\n');
      if (lastNewline < 0) continue;
      final complete = text.substring(0, lastNewline);
      final leftover = text.substring(lastNewline + 1);
      buffer
        ..clear()
        ..write(leftover);
      for (final line in const LineSplitter().convert(complete)) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == doneSentinel) return;
        yield data;
      }
    }
    // Flush any trailing `data:` line that wasn't newline-terminated.
    final tail = buffer.toString().trim();
    if (tail.startsWith('data:')) {
      final data = tail.substring(5).trim();
      if (data.isNotEmpty && data != doneSentinel) yield data;
    }
  }

  /// Extracts a (possibly nested) JSON field from each string chunk.
  ///
  /// * [path] is a list of [String] map keys and/or [int] list indices.
  /// * Malformed JSON chunks are silently skipped so one bad event does
  ///   not tear down the whole stream.
  /// * Non-string or missing fields are skipped.
  ///
  /// ```dart
  /// // OpenAI chat completion: choices[0].delta.content
  /// StreamAdapters.jsonField(sseStream, ['choices', 0, 'delta', 'content']);
  ///
  /// // Anthropic messages API: delta.text
  /// StreamAdapters.jsonField(sseStream, ['delta', 'text']);
  /// ```
  static Stream<String> jsonField(
    Stream<String> source,
    List<Object> path,
  ) async* {
    await for (final chunk in source) {
      Object? obj;
      try {
        obj = jsonDecode(chunk);
      } catch (_) {
        continue;
      }
      for (final p in path) {
        if (obj is Map && p is String) {
          obj = obj[p];
        } else if (obj is List && p is int && p >= 0 && p < obj.length) {
          obj = obj[p];
        } else {
          obj = null;
          break;
        }
      }
      if (obj is String && obj.isNotEmpty) yield obj;
    }
  }
}
