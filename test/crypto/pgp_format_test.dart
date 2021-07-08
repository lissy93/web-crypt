import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_format.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

const _format = PgpFormat();

Future<Uint8List> encrypt(Uint8List input, EncryptOptions options) =>
    collectBytes(_format.encrypt(Stream.value(input), options));

Future<Uint8List> decrypt(Uint8List input, DecryptOptions options) =>
    collectBytes(_format.decrypt(Stream.value(input), options));

Uint8List pattern(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 17 + 3) % 256));

void main() {
  late PgpKeyPairStrings alice;
  late PgpKeyPairStrings bob;
  late PgpKeyPairStrings locked;

  setUpAll(() {
    alice = generatePgpKeyPair(name: 'Alice', email: 'alice@example.com');
    bob = generatePgpKeyPair(name: 'Bob', email: 'bob@example.com');
    locked = generatePgpKeyPair(
      name: 'Locked',
      email: 'locked@example.com',
      passphrase: 'key-passphrase',
    );
  });

  Recipient recipientOf(PgpKeyPairStrings pair) => Recipient(
    format: CryptoFormatKind.pgp,
    material: pair.publicKey,
    label: pair.userId,
  );

  Identity identityOf(PgpKeyPairStrings pair, {String? passphrase}) => Identity(
    format: CryptoFormatKind.pgp,
    material: pair.privateKey,
    passphrase: passphrase,
  );

  group('key generation', () {
    test('produces an armored pair with a fingerprint', () {
      expect(
        alice.publicKey,
        startsWith('-----BEGIN PGP PUBLIC KEY BLOCK-----'),
      );
      expect(
        alice.privateKey,
        startsWith('-----BEGIN PGP PRIVATE KEY BLOCK-----'),
      );
      expect(alice.fingerprint, hasLength(40));
      expect(alice.userId, 'Alice <alice@example.com>');
      expect(alice.isProtected, isFalse);
    });

    test('an unprotected key really is unprotected', () {
      final key = parsePgpPrivateKey(alice.privateKey);
      expect(key.isDecrypted, isTrue);
      expect(key.isEncrypted, isFalse);
    });

    test('a protected key needs its passphrase', () {
      final key = parsePgpPrivateKey(locked.privateKey);
      expect(locked.isProtected, isTrue);
      expect(key.isDecrypted, isFalse);
      expect(() => unlockPgpPrivateKey(key, null), throwsA(isA<KeyLocked>()));
      expect(
        () => unlockPgpPrivateKey(key, 'nope'),
        throwsA(isA<WrongPassphrase>()),
      );
      expect(unlockPgpPrivateKey(key, 'key-passphrase').isDecrypted, isTrue);
    });

    test('name or email is required', () {
      expect(
        () => generatePgpKeyPair(name: '  ', email: '  '),
        throwsA(isA<InvalidKeyMaterial>()),
      );
      expect(
        generatePgpKeyPair(email: 'only@example.com').userId,
        'only@example.com',
      );
      expect(generatePgpKeyPair(name: 'Only Name').userId, 'Only Name');
    });

    test('expiry is recorded on the key', () {
      final expiring = generatePgpKeyPair(
        name: 'Expiring',
        expiry: const Duration(days: 30),
      );
      final key = parsePgpPublicKey(expiring.publicKey);
      expect(key.expirationTime, isNotNull);
      expect(key.expirationTime!.isAfter(DateTime.now()), isTrue);
    });
  });

  group('passphrase mode', () {
    test('round trips, binary and armored', () async {
      final plaintext = Uint8List.fromList(utf8.encode('hello pgp 🔐'));
      for (final armor in [false, true]) {
        final sealed = await encrypt(
          plaintext,
          EncryptOptions.withPassphrase('pw', armor: armor),
        );
        expect(
          FormatDetector.detect(sealed),
          armor ? DetectedFormat.pgpArmoredMessage : DetectedFormat.pgpBinary,
        );
        final opened = await decrypt(
          sealed,
          const DecryptOptions(passphrase: 'pw'),
        );
        expect(opened, plaintext);
      }
    });

    test('wrong passphrase is rejected', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('x')),
        const EncryptOptions.withPassphrase('right'),
      );
      await expectLater(
        decrypt(sealed, const DecryptOptions(passphrase: 'wrong')),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test('no passphrase asks for one', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('x')),
        const EncryptOptions.withPassphrase('right'),
      );
      await expectLater(
        decrypt(sealed, const DecryptOptions()),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test('the original filename survives', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('x')),
        const EncryptOptions(
          mode: EncryptMode.passphrase,
          passphrase: 'pw',
          filename: 'report.pdf',
        ),
      );
      DecryptMetadata? metadata;
      await collectBytes(
        _format.decrypt(
          Stream.value(sealed),
          DecryptOptions(
            passphrase: 'pw',
            onMetadata: (value) => metadata = value,
          ),
        ),
      );
      expect(metadata?.filename, 'report.pdf');
    });
  });

  group('recipient mode', () {
    test('round trips to one recipient', () async {
      final plaintext = pattern(4096);
      final sealed = await encrypt(
        plaintext,
        EncryptOptions.forRecipients([recipientOf(alice)]),
      );
      final opened = await decrypt(
        sealed,
        DecryptOptions(identities: [identityOf(alice)]),
      );
      expect(opened, plaintext);
    });

    test('either of two recipients can open it', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('for both')),
        EncryptOptions.forRecipients([recipientOf(alice), recipientOf(bob)]),
      );
      for (final pair in [alice, bob]) {
        final opened = await decrypt(
          sealed,
          DecryptOptions(identities: [identityOf(pair)]),
        );
        expect(utf8.decode(opened), 'for both');
      }
    });

    test('a stranger cannot open it', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('private')),
        EncryptOptions.forRecipients([recipientOf(alice)]),
      );
      await expectLater(
        decrypt(sealed, DecryptOptions(identities: [identityOf(bob)])),
        throwsA(isA<NoMatchingKey>()),
      );
    });

    test('a protected key opens it once unlocked', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('locked away')),
        EncryptOptions.forRecipients([recipientOf(locked)]),
      );
      final opened = await decrypt(
        sealed,
        DecryptOptions(
          identities: [identityOf(locked, passphrase: 'key-passphrase')],
        ),
      );
      expect(utf8.decode(opened), 'locked away');

      await expectLater(
        decrypt(sealed, DecryptOptions(identities: [identityOf(locked)])),
        throwsA(isA<KeyLocked>()),
      );
      await expectLater(
        decrypt(
          sealed,
          DecryptOptions(identities: [identityOf(locked, passphrase: 'nope')]),
        ),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test('no recipients is refused', () async {
      await expectLater(
        encrypt(
          Uint8List.fromList(utf8.encode('x')),
          const EncryptOptions.forRecipients([]),
        ),
        throwsA(isA<NoRecipients>()),
      );
    });

    test('an age recipient is refused by the PGP format', () async {
      await expectLater(
        encrypt(
          Uint8List.fromList(utf8.encode('x')),
          const EncryptOptions.forRecipients([
            Recipient(
              format: CryptoFormatKind.age,
              material: 'age1whatever',
              label: 'x',
            ),
          ]),
        ),
        throwsA(isA<RecipientFormatMismatch>()),
      );
    });
  });

  group('peeking', () {
    test('tells passphrase and key messages apart', () async {
      final passworded = await encrypt(
        Uint8List.fromList(utf8.encode('x')),
        const EncryptOptions.withPassphrase('pw'),
      );
      final keyed = await encrypt(
        Uint8List.fromList(utf8.encode('x')),
        EncryptOptions.forRecipients([recipientOf(alice)]),
      );
      expect(PgpFormat.peek(passworded)!.needsPassphrase, isTrue);
      expect(PgpFormat.peek(passworded)!.needsKey, isFalse);
      expect(PgpFormat.peek(keyed)!.needsKey, isTrue);
      expect(PgpFormat.peek(keyed)!.needsPassphrase, isFalse);
      expect(PgpFormat.peek(pattern(64)), isNull);
    });
  });

  group('rejecting things that are not PGP messages', () {
    test('random bytes', () async {
      await expectLater(
        decrypt(pattern(512), const DecryptOptions(passphrase: 'pw')),
        throwsA(isA<NotEncryptedData>()),
      );
    });

    test('empty input', () async {
      await expectLater(
        decrypt(Uint8List(0), const DecryptOptions(passphrase: 'pw')),
        throwsA(isA<NotEncryptedData>()),
      );
    });

    test('a key block is not a message', () async {
      await expectLater(
        decrypt(
          Uint8List.fromList(utf8.encode(alice.publicKey)),
          const DecryptOptions(passphrase: 'pw'),
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('key parsing', () {
    test('rubbish is refused', () {
      expect(
        () => parsePgpPublicKey('not a key'),
        throwsA(isA<InvalidKeyMaterial>()),
      );
      expect(
        () => parsePgpPrivateKey('-----BEGIN PGP PRIVATE KEY BLOCK-----\nxx\n'),
        throwsA(isA<InvalidKeyMaterial>()),
      );
    });

    test('a key with no encryption subkey cannot be encrypted to', () async {
      // a real sign-only key: primary, user id and self-signature, with the
      // encryption subkey dropped
      final signOnly = File(
        'test/fixtures/pgp-sign-only.asc',
      ).readAsStringSync();
      expect(parsePgpPublicKey(signOnly).getEncryptionKeyPacket(), isNull);

      await expectLater(
        encrypt(
          Uint8List.fromList(utf8.encode('x')),
          EncryptOptions.forRecipients([
            Recipient(
              format: CryptoFormatKind.pgp,
              material: signOnly,
              label: 'sign only',
            ),
          ]),
        ),
        throwsA(isA<KeyCannotEncrypt>()),
      );
    });
  });
}
