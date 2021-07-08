import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/errors/error_messages.dart';
import 'package:web_crypt/core/utils/formatters.dart';
import 'package:web_crypt/core/utils/passphrase_strength.dart';
import 'package:web_crypt/core/utils/streams.dart';

void main() {
  group('formatBytes', () {
    test('scales through the units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1 MB');
      expect(formatBytes(200 * 1024 * 1024), '200 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1 GB');
    });
  });

  group('fingerprints', () {
    test('groups into fours', () {
      expect(groupFingerprint('aabbccdd'), 'AABB CCDD');
      expect(groupFingerprint('aabbccddee'), 'AABB CCDD EE');
      expect(groupFingerprint(''), '');
    });

    test('shortens to the last sixteen', () {
      expect(
        shortFingerprint('0123456789abcdef0123456789abcdef'),
        '0123456789abcdef',
      );
      expect(shortFingerprint('short'), 'short');
    });
  });

  test('ellipsise keeps both ends', () {
    expect(ellipsise('short', 20), 'short');
    final long = ellipsise('a' * 40 + 'z' * 40, 21);
    expect(long.length, lessThanOrEqualTo(21));
    expect(long, startsWith('a'));
    expect(long, endsWith('z'));
    expect(long, contains('…'));
  });

  test('formatDate is stable', () {
    expect(formatDate(DateTime(2024, 3, 4)), '2024-03-04');
    expect(formatDate(DateTime(2024, 12, 25)), '2024-12-25');
  });

  group('scorePassphrase', () {
    test('rates obviously weak ones weak', () {
      for (final weak in ['', 'a', 'abc', '1234', 'aaaaaaaa', 'password']) {
        expect(
          scorePassphrase(weak).level,
          PassphraseLevel.weak,
          reason: 'rated "$weak" too highly',
        );
      }
    });

    test('rates a real passphrase strong', () {
      expect(
        scorePassphrase('correct horse battery staple').level,
        PassphraseLevel.strong,
      );
      expect(
        scorePassphrase('Tr0ub4dor&3xKcd!Zq').level.index,
        greaterThanOrEqualTo(PassphraseLevel.good.index),
      );
    });

    test('length alone does not make a passphrase strong', () {
      expect(
        scorePassphrase('abababababababababab').level.index,
        lessThan(PassphraseLevel.strong.index),
      );
    });

    test('even an empty passphrase has something to show the user', () {
      final score = scorePassphrase('');
      expect(score.label, isNotEmpty);
      expect(score.advice, isNotEmpty);
    });
  });

  group('error messages', () {
    test('every exception has copy, and none of it is a type name', () {
      const exceptions = <AppException>[
        WrongPassphrase(),
        NoMatchingKey(),
        KeyLocked(),
        DataTampered(),
        NotEncryptedData(),
        InvalidKeyMaterial(),
        DuplicateKey(),
        KeyCannotEncrypt(),
        KeyringLocked(),
        WrongMasterPassword(),
        KeyringCorrupt(),
        InputTooLarge(1024),
        NoRecipients(),
        RecipientFormatMismatch(),
        FileAccessFailed(),
        CryptoFailed(),
      ];
      for (final exception in exceptions) {
        final message = messageFor(exception);
        expect(message.title, isNotEmpty);
        expect(message.title, isNot(contains('Exception')));
        expect(
          message.title,
          isNot(contains(exception.runtimeType.toString())),
        );
      }
    });

    test('a stray non-AppException still gets calm words', () {
      final message = messageFor(StateError('internal detail'));
      expect(message.title, isNot(contains('internal detail')));
      expect(message.title, isNotEmpty);
    });

    test('the size limit is spelled out', () {
      expect(
        messageFor(const InputTooLarge(200 * 1024 * 1024)).hint,
        contains('200 MB'),
      );
    });
  });

  group('peekHead', () {
    Stream<List<int>> chunked(List<int> data, int size) async* {
      for (var i = 0; i < data.length; i += size) {
        yield data.sublist(i, (i + size).clamp(0, data.length));
      }
    }

    test(
      'gives back the head and a stream that still starts at zero',
      () async {
        final data = List.generate(1000, (i) => i % 256);
        final headed = await peekHead(chunked(data, 64), 100);
        expect(headed.head, data.sublist(0, 100));
        expect(await collectBytes(headed.stream), data);
      },
    );

    test('copes when the stream is shorter than the head', () async {
      final data = List.generate(10, (i) => i);
      final headed = await peekHead(chunked(data, 4), 100);
      expect(headed.head, data);
      expect(await collectBytes(headed.stream), data);
    });

    test('copes with an empty stream', () async {
      final headed = await peekHead(const Stream<List<int>>.empty(), 100);
      expect(headed.head, isEmpty);
      expect(await collectBytes(headed.stream), isEmpty);
    });

    test('a chunk straddling the boundary is split correctly', () async {
      final data = List.generate(300, (i) => i % 256);
      final headed = await peekHead(chunked(data, 128), 100);
      expect(headed.head, data.sublist(0, 100));
      expect(await collectBytes(headed.stream), data);
    });

    test('errors reach the consumer', () async {
      final headed = await peekHead(
        Stream<List<int>>.error(const FileAccessFailed()),
        100,
      );
      await expectLater(
        collectBytes(headed.stream),
        throwsA(isA<FileAccessFailed>()),
      );
    });
  });

  test('collectBytes joins chunks', () async {
    final result = await collectBytes(
      Stream.fromIterable([
        [1, 2],
        [3],
        <int>[],
        [4, 5],
      ]),
    );
    expect(result, Uint8List.fromList([1, 2, 3, 4, 5]));
  });
}
