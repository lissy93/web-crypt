import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart';
import 'package:dart_pg/src/enum/aead_algorithm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_format.dart';

/// AEAD payloads are cut into chunks, each carrying its own tag, so a chunk of
/// ciphertext is longer than the plaintext inside it. gpg writes these
/// whenever the recipient advertises AEAD, which every key we generate does.
///
/// `pgp-aead-chunked.gpg` is from GnuPG 2.4.4 at its smallest chunk size, so
/// 500 bytes of payload span five chunks
void main() {
  test('a gpg message spanning several AEAD chunks opens', () async {
    // the fill the fixture was made from
    final plain = Uint8List.fromList([
      for (var i = 0; i < 500; i++) (i * 7 + 11) % 251,
    ]);
    final opened = await collectBytes(
      const PgpFormat().decrypt(
        Stream.value(
          File('test/fixtures/pgp-aead-chunked.gpg').readAsBytesSync(),
        ),
        const DecryptOptions(passphrase: 'chunk-test'),
      ),
    );
    expect(opened, plain);
  });

  // 262144 is exactly one chunk at the default size, either side of it is
  // where the offset arithmetic goes wrong
  for (final size in [100, 262144, 300000]) {
    test('$size bytes round trip through both AEAD packet types', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final body = Uint8List.fromList([
        for (var i = 0; i < size; i++) (i * 31 + 7) % 251,
      ]);

      for (final aead in [AeadAlgorithm.ocb, AeadAlgorithm.gcm]) {
        final sealed = AeadEncryptedDataPacket.encryptPackets(
          key,
          PacketList([LiteralDataPacket(body)]),
          aead: aead,
        );
        expect(
          sealed
              .decrypt(key)
              .packets!
              .whereType<LiteralDataPacket>()
              .first
              .binary,
          body,
          reason: 'tag 20, $aead',
        );

        final sealedV2 =
            SymEncryptedIntegrityProtectedDataPacket.encryptPackets(
              key,
              PacketList([LiteralDataPacket(body)]),
              aead: aead,
            );
        expect(
          sealedV2
              .decrypt(key)
              .packets!
              .whereType<LiteralDataPacket>()
              .first
              .binary,
          body,
          reason: 'seipd 2, $aead',
        );
      }
    });
  }
}
