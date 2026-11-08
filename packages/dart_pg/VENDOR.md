# vendored fork of dart_pg

Modified copy of [dart_pg 2.1.0](https://pub.dev/packages/dart_pg),
BSD-3-Clause, copyright 2024-present the Dart Privacy Guard project. This is
not the upstream release and is not endorsed by its authors. The licence terms
are unchanged, and `LICENSE` and `CONTRIBUTORS` are kept as they shipped.

Cut from `github.com/web-of-trust/dart-pg` at tag `2.1.0`, commit
`c071b383ad685c6eb4c4b2a8446fa50f1e5cc0e3`. Upstream drift since then is a plain
diff against that commit.

Upstream reaches for `dart:io` to decompress, so it cannot build for web. No
cryptographic primitive is modified.

## changed

- `src/packet/compressed_data.dart` uses `package:archive` rather than
  `dart:io`'s `ZLibCodec`, which is the one thing that blocked a web build
- `secret_key.dart`, `secret_subkey.dart` and `key/private_key.dart` gain
  `unprotect()`, so a key generated without a passphrase writes out unlocked
  rather than sealed under a throwaway nobody can supply
- `key/private_key.dart` lets `getDecryptionKeyPacket` return null as its
  interface says, rather than throwing a cast error for a key with no
  encryption subkey
- the eddsa legacy and ecdh key materials and `common/extensions.dart` pad
  fixed-width values back to 32 bytes, which MPI storage truncates, and
  `verify` locates the second half of a signature by its stored length
- `packet/signature.dart` treats a missing expiry as never expires and allows
  five minutes of clock skew on the creation time, as GnuPG does
- `packet/padding.dart` writes tag 21 rather than tag 10, which GnuPG reported
  as an invalid marker packet
- `cryptor/symmetric/buffered_cipher.dart` runs each block through a one-block
  scratch buffer, turning quadratic CFB into linear
- `packet/aead_encrypted_data.dart` and the AEAD half of
  `sym_encrypted_integrity_protected_data.dart` track the output offset per
  chunk, which is what a message past one chunk needs, and gpg 2.4 writes those
  to any key advertising AEAD
- `packet/base_packet.dart` writes definite lengths for the data packets, and
  throws past 4 GiB instead of wrapping; it, `packet_list.dart`,
  `literal_data.dart` and `sym_encrypted_integrity_protected_data.dart` build
  bytes with `BytesBuilder`
- `message/literal_message.dart` lets recipient features only narrow AEAD,
  never enable it, so GnuPG 2.2 can read a message encrypted to a web-crypt key
- `enum/symmetric_algorithm.dart` orders `preferredSymmetrics` strongest
  first, so recipient mode lands on AES-256
- the barrel exports the `type/` interfaces the public API returns
- `archive` added, `faker` dropped, `lints` and `test` bumped
- upstream `test/`, `example/`, `README.md`, `CHANGELOG.md` and `pubspec.lock`
  removed
