import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';

Uint8List bytesOf(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  group('FormatDetector', () {
    test('age binary by its version line', () {
      expect(
        FormatDetector.detect(bytesOf('age-encryption.org/v1\n-> scrypt ')),
        DetectedFormat.ageBinary,
      );
    });

    test('age armored', () {
      expect(
        FormatDetector.detect(
          bytesOf('-----BEGIN AGE ENCRYPTED FILE-----\nYWdl'),
        ),
        DetectedFormat.ageArmored,
      );
    });

    test('PGP armored message', () {
      expect(
        FormatDetector.detect(bytesOf('-----BEGIN PGP MESSAGE-----\n\nhQ')),
        DetectedFormat.pgpArmoredMessage,
      );
    });

    test('PGP public and private key blocks', () {
      expect(
        FormatDetector.detect(bytesOf('-----BEGIN PGP PUBLIC KEY BLOCK-----')),
        DetectedFormat.pgpPublicKey,
      );
      expect(
        FormatDetector.detect(bytesOf('-----BEGIN PGP PRIVATE KEY BLOCK-----')),
        DetectedFormat.pgpPrivateKey,
      );
    });

    test('age identity, including a real identity file with comments', () {
      expect(
        FormatDetector.detect(
          bytesOf('AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQ'),
        ),
        DetectedFormat.ageIdentity,
      );
      // a file from `age-keygen` leads with comment lines, so it reads as
      // plain text. the key import path handles that, not the sniffer
      expect(
        FormatDetector.detect(
          bytesOf(
            '# created: 2024-01-01\n# public key: age1abc\n'
            'AGE-SECRET-KEY-1QQQ\n',
          ),
        ),
        DetectedFormat.unknown,
      );
    });

    test('age recipient only when it is the whole token', () {
      expect(
        FormatDetector.detect(bytesOf('age1qqqqqqqqqqqqqqqqqqq')),
        DetectedFormat.ageRecipient,
      );
      expect(
        FormatDetector.detect(bytesOf('  age1qqqqqqq  \n')),
        DetectedFormat.ageRecipient,
      );
      expect(
        FormatDetector.detect(bytesOf('age1qqq and some other words')),
        DetectedFormat.unknown,
      );
    });

    test('leading whitespace does not hide a header', () {
      expect(
        FormatDetector.detect(bytesOf('\n\n  -----BEGIN PGP MESSAGE-----\n')),
        DetectedFormat.pgpArmoredMessage,
      );
    });

    test('binary PGP packets', () {
      // new format SKESK: tag 3, length, v4, AES-256, iterated S2K
      expect(
        FormatDetector.detect(
          Uint8List.fromList([0xc3, 0x2e, 0x04, 0x09, 0x03, 0x08]),
        ),
        DetectedFormat.pgpBinary,
      );
      // new format SEIPD: tag 18, length, v1
      expect(
        FormatDetector.detect(Uint8List.fromList([0xd2, 0x4f, 0x01, 0x00])),
        DetectedFormat.pgpBinary,
      );
      // old format PKESK: tag 1, two byte length, v3, key id, ECDH
      expect(
        FormatDetector.detect(
          Uint8List.fromList([
            0x85, 0x00, 0x0c, // header, length
            0x03, // version
            1, 2, 3, 4, 5, 6, 7, 8, // key id
            18, // ECDH
          ]),
        ),
        DetectedFormat.pgpBinary,
      );
    });

    test('a plausible tag with an implausible body is not PGP', () {
      // tag 18 with a version byte of 0x77 is not a real SEIPD packet
      expect(
        FormatDetector.detect(Uint8List.fromList([0xd2, 0x4f, 0x77, 0x00])),
        DetectedFormat.unknown,
      );
      // tag 3 v4 with a symmetric algorithm id that does not exist
      expect(
        FormatDetector.detect(
          Uint8List.fromList([0xc3, 0x2e, 0x04, 0x63, 0x03]),
        ),
        DetectedFormat.unknown,
      );
      // tag 1 v3 with a public key algorithm id that does not exist
      expect(
        FormatDetector.detect(
          Uint8List.fromList([
            0x85,
            0x00,
            0x0c,
            0x03,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            99,
          ]),
        ),
        DetectedFormat.unknown,
      );
    });

    test('almost never claims random noise is a message', () {
      // a false positive is harmless, since decryption then fails the same
      // way, what matters is that it stays rare
      final random = Random(20240101);
      var falsePositives = 0;
      const samples = 20000;
      for (var i = 0; i < samples; i++) {
        final noise = Uint8List.fromList(
          List.generate(64, (_) => random.nextInt(256)),
        );
        if (FormatDetector.detect(noise) != DetectedFormat.unknown) {
          falsePositives++;
        }
      }
      expect(falsePositives / samples, lessThan(0.001));
    });

    test('survives garbage', () {
      expect(FormatDetector.detect(const []), DetectedFormat.unknown);
      expect(FormatDetector.detect(const [0]), DetectedFormat.unknown);
      expect(FormatDetector.detect(const [0xff]), DetectedFormat.unknown);
      expect(FormatDetector.detect(bytesOf('')), DetectedFormat.unknown);
      expect(
        FormatDetector.detect(bytesOf('hello world')),
        DetectedFormat.unknown,
      );
      expect(
        FormatDetector.detect(bytesOf('-----BEGIN AGE ENCRYPTED')),
        DetectedFormat.unknown,
      );
      expect(
        FormatDetector.detect(bytesOf('age-encryption.org/v2')),
        DetectedFormat.unknown,
      );
    });

    test('truncated headers do not crash', () {
      const full = '-----BEGIN PGP PUBLIC KEY BLOCK-----';
      for (var i = 0; i < full.length; i++) {
        expect(
          () => FormatDetector.detect(bytesOf(full.substring(0, i))),
          returnsNormally,
        );
      }
    });

    test('classification helpers agree with the format', () {
      expect(DetectedFormat.ageBinary.formatKind, CryptoFormatKind.age);
      expect(DetectedFormat.pgpBinary.formatKind, CryptoFormatKind.pgp);
      expect(DetectedFormat.unknown.formatKind, isNull);
      expect(DetectedFormat.ageArmored.isMessage, isTrue);
      expect(DetectedFormat.ageRecipient.isMessage, isFalse);
      expect(DetectedFormat.ageRecipient.isKey, isTrue);
      expect(DetectedFormat.pgpArmoredMessage.isArmored, isTrue);
      expect(DetectedFormat.pgpBinary.isArmored, isFalse);
    });
  });

  group('AgeHeaderPeek', () {
    test('spots a passphrase file', () {
      final peek = AgeHeaderPeek.read(
        bytesOf('age-encryption.org/v1\n-> scrypt abcd 18\nbody\n--- mac\n'),
      );
      expect(peek, isNotNull);
      expect(peek!.needsPassphrase, isTrue);
      expect(peek.needsIdentity, isFalse);
    });

    test('spots a recipient file', () {
      final peek = AgeHeaderPeek.read(
        bytesOf('age-encryption.org/v1\n-> X25519 abcd\nbody\n--- mac\n'),
      );
      expect(peek!.needsIdentity, isTrue);
      expect(peek.needsPassphrase, isFalse);
    });

    test('returns null for anything that is not an age header', () {
      expect(AgeHeaderPeek.read(bytesOf('hello')), isNull);
      expect(AgeHeaderPeek.read(const []), isNull);
      expect(AgeHeaderPeek.read(bytesOf('age-encryption.org/v1\n')), isNull);
    });
  });
}
