import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/format.dart';

/// the official C2SP CCTV age testkit, shipped with the vendored dage fork.
/// every "success" vector must decrypt to the stated payload hash, and every
/// failure vector must fail without producing plaintext
void main() {
  final directory = Directory(p.join('packages', 'dage', 'testkit'));
  final vectors =
      directory
          .listSync()
          .whereType<File>()
          .map(_Vector.parse)
          .toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));

  test('the testkit is actually present', () {
    expect(vectors.length, greaterThanOrEqualTo(100));
    expect(vectors.where((v) => v.expect == 'success').length, greaterThan(10));
  });

  for (final vector in vectors) {
    test('${vector.expect}: ${vector.name}', () async {
      final options = DecryptOptions(
        passphrase: vector.passphrase,
        identities: [
          if (vector.identity != null)
            Identity(format: CryptoFormatKind.age, material: vector.identity!),
        ],
      );

      if (vector.expect == 'success') {
        final plaintext = await collectBytes(
          const AgeFormat().decrypt(Stream.value(vector.body), options),
        );
        expect(
          sha256.convert(plaintext).toString(),
          vector.payloadHash,
          reason: 'decrypted payload did not match the expected hash',
        );
        return;
      }

      // everything else must fail as a typed error, rather than escaping as
      // a raw library exception
      Object? thrown;
      try {
        await collectBytes(
          const AgeFormat().decrypt(Stream.value(vector.body), options),
        );
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull, reason: 'expected ${vector.expect}');
      expect(
        thrown,
        isA<AppException>(),
        reason: 'failures must be typed, got ${thrown.runtimeType}',
      );
    });
  }
}

class _Vector {
  const _Vector({
    required this.name,
    required this.expect,
    required this.body,
    this.payloadHash,
    this.identity,
    this.passphrase,
  });

  factory _Vector.parse(File file) {
    final data = file.readAsBytesSync();
    final separator = _indexOfBlankLine(data);
    final header = utf8.decode(
      data.sublist(0, separator),
      allowMalformed: true,
    );
    final fields = <String, String>{};
    for (final line in const LineSplitter().convert(header)) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      fields[line.substring(0, colon).trim()] = line
          .substring(colon + 1)
          .trim();
    }
    return _Vector(
      name: p.basename(file.path),
      expect: fields['expect'] ?? 'unknown',
      payloadHash: fields['payload'],
      identity: fields['identity'],
      passphrase: fields['passphrase'],
      body: Uint8List.sublistView(data, separator + 2),
    );
  }

  final String name;
  final String expect;
  final String? payloadHash;
  final String? identity;
  final String? passphrase;
  final Uint8List body;

  static int _indexOfBlankLine(Uint8List data) {
    for (var i = 0; i < data.length - 1; i++) {
      if (data[i] == 0x0a && data[i + 1] == 0x0a) return i;
    }
    throw StateError('vector has no header separator');
  }
}
