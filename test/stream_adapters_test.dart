import 'dart:convert';

import 'package:streaming_markdown/streaming_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamAdapters.utf8Bytes', () {
    test('decodes a UTF-8 byte stream', () async {
      final bytes = Stream<List<int>>.fromIterable([
        utf8.encode('héllo '),
        utf8.encode('wörld'),
      ]);
      final out = await StreamAdapters.utf8Bytes(bytes).join();
      expect(out, 'héllo wörld');
    });

    test('handles multi-byte characters split across chunks', () async {
      // 'é' is 0xC3 0xA9 in UTF-8. Split between chunks.
      final first = <int>[0x68, 0xC3]; // 'h' + first byte of é
      final second = <int>[0xA9, 0x6C, 0x6C, 0x6F]; // second byte + 'llo'
      final bytes = Stream<List<int>>.fromIterable([first, second]);
      final out = await StreamAdapters.utf8Bytes(bytes).join();
      expect(out, 'héllo');
    });
  });

  group('StreamAdapters.serverSentEvents', () {
    test('extracts data: lines', () async {
      final src = Stream<String>.fromIterable(const [
        'data: hello\n',
        'data: world\n',
        'data: [DONE]\n',
      ]);
      final out = await StreamAdapters.serverSentEvents(src).toList();
      expect(out, ['hello', 'world']);
    });

    test('buffers lines split across chunks', () async {
      final src = Stream<String>.fromIterable(const [
        'data: hel',
        'lo\ndata: wor',
        'ld\n',
      ]);
      final out = await StreamAdapters.serverSentEvents(src).toList();
      expect(out, ['hello', 'world']);
    });

    test('stops at [DONE] sentinel', () async {
      final src = Stream<String>.fromIterable(const [
        'data: a\ndata: [DONE]\ndata: b\n',
      ]);
      final out = await StreamAdapters.serverSentEvents(src).toList();
      expect(out, ['a']);
    });

    test('ignores event:, id:, comments, blank lines', () async {
      final src = Stream<String>.fromIterable(const [
        'event: message\n',
        'data: x\n',
        ': comment\n',
        '\n',
        'id: 1\n',
        'data: y\n',
      ]);
      final out = await StreamAdapters.serverSentEvents(src).toList();
      expect(out, ['x', 'y']);
    });

    test('flushes trailing unterminated data line', () async {
      final src = Stream<String>.fromIterable(const ['data: partial']);
      final out = await StreamAdapters.serverSentEvents(src).toList();
      expect(out, ['partial']);
    });

    test('honours custom sentinel', () async {
      final src = Stream<String>.fromIterable(const [
        'data: a\ndata: END\ndata: b\n',
      ]);
      final out = await StreamAdapters.serverSentEvents(
        src,
        doneSentinel: 'END',
      ).toList();
      expect(out, ['a']);
    });
  });

  group('StreamAdapters.jsonField', () {
    test('extracts nested field (OpenAI shape)', () async {
      final src = Stream<String>.fromIterable([
        jsonEncode({
          'choices': [
            {
              'delta': {'content': 'Hello'},
            },
          ],
        }),
        jsonEncode({
          'choices': [
            {
              'delta': {'content': ' world'},
            },
          ],
        }),
      ]);
      final out = await StreamAdapters.jsonField(
        src,
        <Object>['choices', 0, 'delta', 'content'],
      ).toList();
      expect(out, ['Hello', ' world']);
    });

    test('silently skips malformed JSON', () async {
      final src = Stream<String>.fromIterable([
        jsonEncode({
          'delta': {'text': 'ok'},
        }),
        'not json at all',
        jsonEncode({
          'delta': {'text': 'again'},
        }),
      ]);
      final out = await StreamAdapters.jsonField(
        src,
        <Object>['delta', 'text'],
      ).toList();
      expect(out, ['ok', 'again']);
    });

    test('silently skips missing fields', () async {
      final src = Stream<String>.fromIterable([
        jsonEncode({
          'delta': {'text': 'hi'},
        }),
        jsonEncode({'delta': <String, Object?>{}}), // missing 'text'
      ]);
      final out = await StreamAdapters.jsonField(
        src,
        <Object>['delta', 'text'],
      ).toList();
      expect(out, ['hi']);
    });

    test('skips non-string field values', () async {
      final src = Stream<String>.fromIterable([
        jsonEncode({'n': 42}),
        jsonEncode({'n': 'text'}),
      ]);
      final out = await StreamAdapters.jsonField(src, <Object>['n']).toList();
      expect(out, ['text']);
    });
  });
}
