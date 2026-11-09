import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart';
import 'package:dart_pg/src/enum/signature_type.dart';
import 'package:dart_pg/src/packet/key/session_key.dart';
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

    test('a sign-only key held alongside does not get in the way', () async {
      // gpg --quick-gen-key ... ed25519 sign, so no encryption subkey at all
      final signOnly = Identity(
        format: CryptoFormatKind.pgp,
        material: File(
          'test/fixtures/pgp-sign-only-private.asc',
        ).readAsStringSync(),
      );
      final sealed = await encrypt(
        Uint8List.fromList(utf8.encode('for alice')),
        EncryptOptions.forRecipients([recipientOf(alice)]),
      );
      final opened = await decrypt(
        sealed,
        DecryptOptions(identities: [signOnly, identityOf(alice)]),
      );
      expect(utf8.decode(opened), 'for alice');
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

  group('a wrong passphrase is not a changed message', () {
    // from gpg 2.2 `gpg -c`, where nothing checks the passphrase until the data
    final symmetric = File(
      'test/fixtures/pgp-symmetric-v4.gpg',
    ).readAsBytesSync();
    // from gpg 2.4.4, where the passphrase is checked straight away
    final aead = File('test/fixtures/pgp-aead-chunked.gpg').readAsBytesSync();

    Uint8List flipped(Uint8List bytes, int at) =>
        Uint8List.fromList(bytes)..[at] ^= 0x01;

    test('gpg -c opens with its passphrase', () async {
      final opened = await decrypt(
        symmetric,
        const DecryptOptions(passphrase: 'right horse'),
      );
      expect(utf8.decode(opened), 'made by gpg -c\n');
    });

    test('a wrong passphrase on gpg -c says so', () async {
      await expectLater(
        decrypt(symmetric, const DecryptOptions(passphrase: 'wrong horse')),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test('a changed gpg -c message says so', () async {
      // past the random prefix, so the quick check still passes
      await expectLater(
        decrypt(
          flipped(symmetric, 50),
          const DecryptOptions(passphrase: 'right horse'),
        ),
        throwsA(isA<DataTampered>()),
      );
    });

    test('a wrong passphrase on an AEAD message says so', () async {
      await expectLater(
        decrypt(aead, const DecryptOptions(passphrase: 'wrong')),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test('a changed AEAD message says so', () async {
      await expectLater(
        decrypt(
          flipped(aead, aead.length - 40),
          const DecryptOptions(passphrase: 'chunk-test'),
        ),
        throwsA(isA<DataTampered>()),
      );
    });

    test('a changed message to a key says so', () async {
      final sealed = await encrypt(
        pattern(4096),
        EncryptOptions.forRecipients([recipientOf(alice)]),
      );
      await expectLater(
        decrypt(
          flipped(sealed, sealed.length - 100),
          DecryptOptions(identities: [identityOf(alice)]),
        ),
        throwsA(isA<DataTampered>()),
      );
    });

    test('bzip2 is called unsupported, not changed', () async {
      await expectLater(
        decrypt(
          File('test/fixtures/pgp-bzip2.gpg').readAsBytesSync(),
          const DecryptOptions(passphrase: 'right horse'),
        ),
        throwsA(isA<UnsupportedFeature>()),
      );
    });

    // RFC 9580 lets a slot's cipher differ from the data's
    test('a v6 slot may wrap a key for another cipher', () async {
      final key = SessionKey.produceKey(SymmetricAlgorithm.aes256);
      final sealed = PacketList([
        SymEncryptedSessionKeyPacket.encryptSessionKey(
          'pw',
          symmetric: SymmetricAlgorithm.aes128,
          aead: AeadAlgorithm.ocb,
          sessionKey: key,
        ),
        SymEncryptedIntegrityProtectedDataPacket.encryptPackets(
          key.encryptionKey,
          PacketList([
            LiteralDataPacket(Uint8List.fromList([1, 2, 3])),
          ]),
          aead: AeadAlgorithm.ocb,
        ),
      ]).encode();
      expect(await decrypt(sealed, const DecryptOptions(passphrase: 'pw')), [
        1,
        2,
        3,
      ]);
    });

    test('each password slot is tried, not just the first', () async {
      final key = SessionKey.produceKey(SymmetricAlgorithm.aes256);
      final sealed = PacketList([
        for (final password in ['first', 'second'])
          SymEncryptedSessionKeyPacket.encryptSessionKey(
            password,
            sessionKey: key,
          ),
        SymEncryptedIntegrityProtectedDataPacket.encryptPackets(
          key.encryptionKey,
          PacketList([
            LiteralDataPacket(Uint8List.fromList([4, 5, 6])),
          ]),
        ),
      ]).encode();
      for (final password in ['first', 'second']) {
        expect(await decrypt(sealed, DecryptOptions(passphrase: password)), [
          4,
          5,
          6,
        ]);
      }
      await expectLater(
        decrypt(sealed, const DecryptOptions(passphrase: 'third')),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test(
      'wrong passphrases on our own messages never read as changed',
      () async {
        final sealed = await encrypt(
          pattern(64),
          const EncryptOptions.withPassphrase('right'),
        );
        for (var i = 0; i < 40; i++) {
          await expectLater(
            decrypt(sealed, DecryptOptions(passphrase: 'wrong $i')),
            throwsA(isA<WrongPassphrase>()),
          );
        }
      },
    );
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

  group('signatures', () {
    Future<List<SignatureInfo>> signaturesIn(
      Uint8List sealed, {
      required List<Recipient> known,
      String? passphrase,
    }) async {
      var found = const <SignatureInfo>[];
      await decrypt(
        sealed,
        DecryptOptions(
          passphrase: passphrase,
          identities: [identityOf(bob)],
          verificationKeys: known,
          onMetadata: (metadata) => found = metadata.signatures,
        ),
      );
      return found;
    }

    Uint8List toBob(LiteralMessageInterface message) => message
        .encrypt(encryptionKeys: [parsePgpPublicKey(bob.publicKey)])
        .packetList
        .encode();

    LiteralMessageInterface signedByAlice() => OpenPGP.createLiteralMessage(
      utf8.encode('hi bob'),
    ).sign([parsePgpPrivateKey(alice.privateKey)]);

    test('a good one checks out, compressed or not', () async {
      final signed = signedByAlice();
      for (final message in [
        signed,
        signed.compress(CompressionAlgorithm.zlib),
      ]) {
        final found = await signaturesIn(
          toBob(message),
          known: [recipientOf(alice)],
        );
        expect(found.single.verdict, SignatureVerdict.valid);
      }
    });

    test('one by a key not held still shows', () async {
      final found = await signaturesIn(
        toBob(signedByAlice()),
        known: [recipientOf(bob)],
      );
      expect(found.single.verdict, SignatureVerdict.unknownSigner);
    });

    test('one by a revoked key does not check out', () async {
      final key = parsePgpPrivateKey(alice.privateKey);
      final revocation = SignaturePacket.createSignature(
        key.secretKeyPacket,
        SignatureType.keyRevocation,
        key.publicKey.keyPacket.signBytes,
      );
      final [primary, ...rest] = key.publicKey.packetList.toList();
      final revoked = PublicKey(PacketList([primary, revocation, ...rest]));
      final found = await signaturesIn(
        toBob(signedByAlice()),
        known: [
          Recipient(
            format: CryptoFormatKind.pgp,
            material: revoked.armor(),
            label: 'Alice',
          ),
        ],
      );
      expect(found.single.verdict, SignatureVerdict.invalid);
    });

    test('one moved onto other text does not check out', () async {
      final moved = LiteralMessage(
        PacketList([
          LiteralDataPacket(Uint8List.fromList(utf8.encode('hi mallory'))),
          ...signedByAlice().packetList.whereType<SignaturePacketInterface>(),
        ]),
      );
      final found = await signaturesIn(
        toBob(moved),
        known: [recipientOf(alice)],
      );
      expect(found.single.verdict, SignatureVerdict.invalid);
    });

    // gpg 2.2, zlib compressed and signed by the [S] subkey of this key
    final signer = File(
      'test/fixtures/pgp-signing-subkey.asc',
    ).readAsStringSync();

    Future<SignatureInfo> gpgSignedFor(String key) async {
      final found = await signaturesIn(
        File('test/fixtures/pgp-signed-by-subkey.gpg').readAsBytesSync(),
        passphrase: 'right horse',
        known: [
          Recipient(format: CryptoFormatKind.pgp, material: key, label: 'K'),
        ],
      );
      return found.single;
    }

    test('gpg signing with a subkey checks out', () async {
      final found = await gpgSignedFor(signer);
      expect(found.keyId, 'E22C9887A9C1FA18');
      expect(found.verdict, SignatureVerdict.valid);
    });

    test('a revoked subkey does not check out', () async {
      final revoked = File(
        'test/fixtures/pgp-signing-subkey-revoked.asc',
      ).readAsStringSync();
      expect((await gpgSignedFor(revoked)).verdict, SignatureVerdict.invalid);
    });

    test('a subkey bound to the wrong key does not check out', () async {
      // bob claims the signing subkey, but it never signed back to him
      final theirs = parsePgpPublicKey(signer).subkeys.first.keyPacket;
      final bobs = parsePgpPrivateKey(bob.privateKey);
      final claimed = PublicKey(
        PacketList([
          ...bobs.publicKey.packetList,
          theirs,
          SignaturePacket.createSubkeyBinding(
            bobs.secretKeyPacket,
            theirs,
            forSigning: true,
          ),
        ]),
      ).armor();
      expect((await gpgSignedFor(claimed)).verdict, SignatureVerdict.invalid);
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
