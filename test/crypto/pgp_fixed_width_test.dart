import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_format.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

/// OpenPGP stores fixed-width values as MPIs, which drop leading zero bytes,
/// and anything that forgets to pad them back derives the wrong key.
///
/// `pgp-short-seed.asc` is a real key whose Ed25519 seed is a byte short.
/// short values in keys from elsewhere are covered by the gpg half of
/// `tool/interop`
void main() {
  final shortSeedKey = File(
    'test/fixtures/pgp-short-seed.asc',
  ).readAsStringSync();

  test('a key whose seed lost a leading zero still reads back', () {
    final key = parsePgpPrivateKey(shortSeedKey);
    // an unpadded seed derives a different Ed25519 public key, so the
    // fingerprint moves and the self-signature stops verifying
    expect(fingerprintOf(key), 'eb6787fd2d94909fea4c40dc16c32261d68b7b83');
    expect(parsePgpPublicKey(key.publicKey.armor()).verify(), isTrue);
  });

  test('and it can still be encrypted to and opened', () async {
    final key = parsePgpPrivateKey(shortSeedKey);
    final sealed = await collectBytes(
      const PgpFormat().encrypt(
        Stream.value(Uint8List.fromList(utf8.encode('short seed'))),
        EncryptOptions.forRecipients([
          Recipient(
            format: CryptoFormatKind.pgp,
            material: key.publicKey.armor(),
            label: 'fixture',
          ),
        ]),
      ),
    );
    final opened = await collectBytes(
      const PgpFormat().decrypt(
        Stream.value(sealed),
        DecryptOptions(
          identities: [
            Identity(format: CryptoFormatKind.pgp, material: shortSeedKey),
          ],
        ),
      ),
    );
    expect(utf8.decode(opened), 'short seed');
  });

  test('freshly generated keys read back too', () {
    // cheap cover for generation itself changing, the fixture above is what
    // pins the padding
    for (var i = 0; i < 10; i++) {
      final pair = generatePgpKeyPair(name: 'Fresh $i');
      expect(parsePgpPublicKey(pair.publicKey).verify(), isTrue);
      expect(parsePgpPrivateKey(pair.privateKey).isDecrypted, isTrue);
    }
  });
}
