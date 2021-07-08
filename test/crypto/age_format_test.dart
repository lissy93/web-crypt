import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';

const _format = AgeFormat();

Future<Uint8List> encrypt(Uint8List input, EncryptOptions options) =>
    collectBytes(_format.encrypt(Stream.value(input), options));

Future<Uint8List> decrypt(Uint8List input, DecryptOptions options) =>
    collectBytes(_format.decrypt(Stream.value(input), options));

Uint8List pattern(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) % 256));

void main() {
  group('AgeFormat passphrase mode', () {
    test('round trips text', () async {
      final plaintext = Uint8List.fromList(utf8.encode('hello 🔐 world'));
      final sealed = await encrypt(
        plaintext,
        const EncryptOptions.withPassphrase('a good passphrase'),
      );
      expect(FormatDetector.detect(sealed), DetectedFormat.ageBinary);
      final opened = await decrypt(
        sealed,
        const DecryptOptions(passphrase: 'a good passphrase'),
      );
      expect(opened, plaintext);
    });

    test('round trips armored', () async {
      final plaintext = Uint8List.fromList(utf8.encode('armored please'));
      final sealed = await encrypt(
        plaintext,
        const EncryptOptions.withPassphrase('pw', armor: true),
      );
      expect(FormatDetector.detect(sealed), DetectedFormat.ageArmored);
      expect(
        utf8.decode(sealed),
        startsWith('-----BEGIN AGE ENCRYPTED FILE-----'),
      );
      final opened = await decrypt(
        sealed,
        const DecryptOptions(passphrase: 'pw'),
      );
      expect(opened, plaintext);
    });

    test('a non-ASCII passphrase survives the round trip', () async {
      const passphrase = 'pässwörd ключ 密码 🔑';
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('unicode')),
        const EncryptOptions.withPassphrase(passphrase),
      );
      final opened = await decrypt(
        sealed,
        const DecryptOptions(passphrase: passphrase),
      );
      expect(utf8.decode(opened), 'unicode');
    });

    test('wrong passphrase is rejected as such', () async {
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        const EncryptOptions.withPassphrase('right'),
      );
      await expectLater(
        decrypt(sealed, const DecryptOptions(passphrase: 'wrong')),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test(
      'a missing passphrase asks for one rather than failing oddly',
      () async {
        final sealed = await encrypt(
          Uint8List.fromList(utf8.encode('secret')),
          const EncryptOptions.withPassphrase('right'),
        );
        await expectLater(
          decrypt(sealed, const DecryptOptions()),
          throwsA(isA<WrongPassphrase>()),
        );
      },
    );

    test('an empty passphrase is refused at encrypt time', () async {
      await expectLater(
        encrypt(
          Uint8List.fromList(utf8.encode('x')),
          const EncryptOptions.withPassphrase(''),
        ),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test(
      'a tampered payload is reported as tampering, not a bad passphrase',
      () async {
        final sealed = await encrypt(
          pattern(2048),
          const EncryptOptions.withPassphrase('pw'),
        );
        sealed[sealed.length - 1] ^= 0xff;
        await expectLater(
          decrypt(sealed, const DecryptOptions(passphrase: 'pw')),
          throwsA(isA<DataTampered>()),
        );
      },
    );
  });

  group('AgeFormat recipient mode', () {
    test('round trips through a generated keypair', () async {
      final pair = await generateAgeKeyPair();
      final plaintext = pattern(1000);
      final sealed = await encrypt(
        plaintext,
        EncryptOptions.forRecipients([
          Recipient(
            format: CryptoFormatKind.age,
            material: pair.recipient,
            label: 'me',
          ),
        ]),
      );
      final opened = await decrypt(
        sealed,
        DecryptOptions(
          identities: [
            Identity(format: CryptoFormatKind.age, material: pair.identity),
          ],
        ),
      );
      expect(opened, plaintext);
    });

    test('any one of several recipients can open it', () async {
      final first = await generateAgeKeyPair();
      final second = await generateAgeKeyPair();
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('for two')),
        EncryptOptions.forRecipients([
          Recipient(
            format: CryptoFormatKind.age,
            material: first.recipient,
            label: 'first',
          ),
          Recipient(
            format: CryptoFormatKind.age,
            material: second.recipient,
            label: 'second',
          ),
        ]),
      );
      for (final pair in [first, second]) {
        final opened = await decrypt(
          sealed,
          DecryptOptions(
            identities: [
              Identity(format: CryptoFormatKind.age, material: pair.identity),
            ],
          ),
        );
        expect(utf8.decode(opened), 'for two');
      }
    });

    test('the wrong identity cannot open it', () async {
      final mine = await generateAgeKeyPair();
      final theirs = await generateAgeKeyPair();
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('mine')),
        EncryptOptions.forRecipients([
          Recipient(
            format: CryptoFormatKind.age,
            material: mine.recipient,
            label: 'mine',
          ),
        ]),
      );
      await expectLater(
        decrypt(
          sealed,
          DecryptOptions(
            identities: [
              Identity(format: CryptoFormatKind.age, material: theirs.identity),
            ],
          ),
        ),
        throwsA(isA<NoMatchingKey>()),
      );
    });

    test('no identity at all is a no-matching-key, not a crash', () async {
      final pair = await generateAgeKeyPair();
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('x')),
        EncryptOptions.forRecipients([
          Recipient(
            format: CryptoFormatKind.age,
            material: pair.recipient,
            label: 'x',
          ),
        ]),
      );
      await expectLater(
        decrypt(sealed, const DecryptOptions()),
        throwsA(isA<NoMatchingKey>()),
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

    test('a PGP recipient is refused by the age format', () async {
      await expectLater(
        encrypt(
          Uint8List.fromList(utf8.encode('x')),
          const EncryptOptions.forRecipients([
            Recipient(
              format: CryptoFormatKind.pgp,
              material: 'not an age recipient',
              label: 'x',
            ),
          ]),
        ),
        throwsA(isA<RecipientFormatMismatch>()),
      );
    });
  });

  group('chunk boundaries', () {
    // STREAM forbids an empty final chunk, which is what an exact multiple
    // of the chunk size risks producing
    const chunk = 64 * 1024;
    for (final size in [
      0,
      1,
      chunk - 1,
      chunk,
      chunk + 1,
      chunk * 2,
      chunk * 2 + 5,
    ]) {
      test('$size bytes round trips', () async {
        final plaintext = pattern(size);
        final sealed = await encrypt(
          plaintext,
          const EncryptOptions.withPassphrase('pw'),
        );
        final opened = await decrypt(
          sealed,
          const DecryptOptions(passphrase: 'pw'),
        );
        expect(opened.length, size);
        expect(opened, plaintext);
      });
    }
  });

  group('rejecting things that are not age files', () {
    test('random bytes', () async {
      await expectLater(
        decrypt(pattern(256), const DecryptOptions(passphrase: 'pw')),
        throwsA(isA<NotEncryptedData>()),
      );
    });

    test('empty input', () async {
      await expectLater(
        decrypt(Uint8List(0), const DecryptOptions(passphrase: 'pw')),
        throwsA(isA<NotEncryptedData>()),
      );
    });

    test('broken armor', () async {
      final broken = Uint8List.fromList(
        utf8.encode('-----BEGIN AGE ENCRYPTED FILE-----\nnot base64!!!\n'),
      );
      await expectLater(
        decrypt(broken, const DecryptOptions(passphrase: 'pw')),
        throwsA(isA<NotEncryptedData>()),
      );
    });
  });

  group('age keys', () {
    test('a generated identity maps back to its recipient', () async {
      final pair = await generateAgeKeyPair();
      expect(pair.recipient, startsWith('age1'));
      expect(pair.identity, startsWith('AGE-SECRET-KEY-1'));
      expect(await recipientForIdentity(pair.identity), pair.recipient);
    });

    test('an identity file parses back', () async {
      final pair = await generateAgeKeyPair();
      final file = ageIdentityFile(
        pair.identity,
        pair.recipient,
        DateTime.utc(2024, 5, 1),
      );
      expect(file, contains('# public key: ${pair.recipient}'));
      final parsed = await parseAgeIdentity(file);
      expect(parsed.recipient.toString(), pair.recipient);
    });

    test('rubbish recipients are refused', () {
      expect(
        () => parseAgeRecipient('not a key'),
        throwsA(isA<InvalidKeyMaterial>()),
      );
      expect(
        () => parseAgeRecipient('age1'),
        throwsA(isA<InvalidKeyMaterial>()),
      );
      expect(() => parseAgeRecipient(''), throwsA(isA<InvalidKeyMaterial>()));
    });

    test('rubbish identities are refused', () async {
      await expectLater(
        parseAgeIdentity('AGE-SECRET-KEY-1NONSENSE'),
        throwsA(isA<InvalidKeyMaterial>()),
      );
      expect(await tryParseAgeIdentity('nothing here'), isNull);
    });
  });
}
