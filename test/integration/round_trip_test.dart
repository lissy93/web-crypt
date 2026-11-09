import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

/// full flows through the service layer, the same door the UI uses. covers
/// every format and mode, plus generate to export to import to use
void main() {
  const service = CryptoService();

  Uint8List binaryFixture(int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 2654435761) % 256));

  String checksum(List<int> bytes) => sha256.convert(bytes).toString();

  group('message round trips', () {
    const message = 'Meet me at the usual place. 🕰️ Bring the αβγ files.';

    for (final format in CryptoFormatKind.values) {
      test('${format.label}, passphrase mode', () async {
        final sealed = await service.encryptBytes(
          format: format,
          input: Uint8List.fromList(utf8.encode(message)),
          options: const EncryptOptions.withPassphrase(
            'a b c d e',
            armor: true,
          ),
        );
        final outcome = await service.decryptBytes(
          input: sealed,
          passphrase: 'a b c d e',
        );
        expect(utf8.decode(outcome.bytes), message);
        expect(outcome.format, format);
      });

      test('${format.label}, recipient mode', () async {
        final recipient = await _recipientFor(format);
        final sealed = await service.encryptBytes(
          format: format,
          input: Uint8List.fromList(utf8.encode(message)),
          options: EncryptOptions.forRecipients([
            recipient.recipient,
          ], armor: true),
        );
        final outcome = await service.decryptBytes(
          input: sealed,
          identities: [recipient.identity],
        );
        expect(utf8.decode(outcome.bytes), message);
        expect(outcome.format, format);
      });
    }
  });

  group('binary round trips are byte identical', () {
    for (final format in CryptoFormatKind.values) {
      for (final size in [1, 1024, 64 * 1024, 300 * 1024]) {
        test('${format.label}, $size bytes', () async {
          final original = binaryFixture(size);
          final before = checksum(original);
          final sealed = await service.encryptBytes(
            format: format,
            input: original,
            options: const EncryptOptions.withPassphrase('pw'),
          );
          final outcome = await service.decryptBytes(
            input: sealed,
            passphrase: 'pw',
          );
          expect(checksum(outcome.bytes), before);
          expect(outcome.bytes.length, size);
        });
      }
    }
  });

  group('generate, export, import, use', () {
    test('an age key survives a trip through its export format', () async {
      final generated = await generateAgeKeyPair();
      final exported = ageIdentityFile(
        generated.identity,
        generated.recipient,
        DateTime.now(),
      );

      final imported = await parseKeyMaterial(
        exported,
        id: 'imported',
        now: DateTime.now(),
      );
      expect(imported.isPrivate, isTrue);
      expect(imported.entry.publicMaterial, generated.recipient);

      final sealed = await service.encryptBytes(
        format: CryptoFormatKind.age,
        input: Uint8List.fromList(utf8.encode('round trip')),
        options: EncryptOptions.forRecipients([imported.entry.asRecipient]),
      );
      final outcome = await service.decryptBytes(
        input: sealed,
        identities: [
          Identity(
            format: CryptoFormatKind.age,
            material: imported.privateMaterial!,
          ),
        ],
      );
      expect(utf8.decode(outcome.bytes), 'round trip');
    });

    test('a PGP key survives a trip through its armor', () async {
      final generated = generatePgpKeyPair(
        name: 'Round Trip',
        email: 'round@example.com',
      );

      final publicSide = await parseKeyMaterial(
        generated.publicKey,
        id: 'pub',
        now: DateTime.now(),
      );
      final privateSide = await parseKeyMaterial(
        generated.privateKey,
        id: 'priv',
        now: DateTime.now(),
      );
      expect(publicSide.entry.fingerprint, generated.fingerprint);
      expect(privateSide.entry.fingerprint, generated.fingerprint);

      final sealed = await service.encryptBytes(
        format: CryptoFormatKind.pgp,
        input: Uint8List.fromList(utf8.encode('round trip')),
        options: EncryptOptions.forRecipients([publicSide.entry.asRecipient]),
      );
      final outcome = await service.decryptBytes(
        input: sealed,
        identities: [
          Identity(
            format: CryptoFormatKind.pgp,
            material: privateSide.privateMaterial!,
          ),
        ],
      );
      expect(utf8.decode(outcome.bytes), 'round trip');
    });
  });

  group('format detection drives decryption', () {
    test('no format has to be named on the way back in', () async {
      for (final format in CryptoFormatKind.values) {
        for (final armor in [false, true]) {
          final sealed = await service.encryptBytes(
            format: format,
            input: Uint8List.fromList(utf8.encode('detect me')),
            options: EncryptOptions.withPassphrase('pw', armor: armor),
          );
          final outcome = await service.decryptBytes(
            input: sealed,
            passphrase: 'pw',
          );
          expect(outcome.format, format);
          expect(utf8.decode(outcome.bytes), 'detect me');
        }
      }
    });

    test('something that is not a message is refused early', () async {
      await expectLater(
        service.decryptBytes(input: binaryFixture(512), passphrase: 'pw'),
        throwsA(isA<NotEncryptedData>()),
      );
    });
  });

  test('native picks the streaming runner, with no size cap', () {
    // guards the conditional import: web gets the capped in-memory runner,
    // desktop and the test host get the dart:io one
    expect(service.canStreamFiles, isTrue);
    expect(service.maxInputBytes, isNull);
  });
}

class _Pair {
  const _Pair(this.recipient, this.identity);

  final Recipient recipient;
  final Identity identity;
}

Future<_Pair> _recipientFor(CryptoFormatKind format) async {
  if (format == CryptoFormatKind.age) {
    final pair = await generateAgeKeyPair();
    return _Pair(
      Recipient(
        format: format,
        material: pair.recipient,
        label: 'age test key',
      ),
      Identity(format: format, material: pair.identity),
    );
  }
  final pair = generatePgpKeyPair(name: 'PGP Test', email: 'pgp@example.com');
  return _Pair(
    Recipient(format: format, material: pair.publicKey, label: 'pgp test key'),
    Identity(format: format, material: pair.privateKey),
  );
}
