import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

/// OpenPGP, over the vendored `dart_pg` fork
///
/// dart_pg works on whole messages rather than streams, so unlike age this
/// holds the payload in memory. that is what the size limits in the crypto
/// service are for
class PgpFormat implements CryptoFormat {
  const PgpFormat();

  static const _symmetric = SymmetricAlgorithm.aes256;

  @override
  Stream<List<int>> encrypt(
    Stream<List<int>> input,
    EncryptOptions opts,
  ) async* {
    final plaintext = await collectBytes(input);
    final message = OpenPGP.createLiteralMessage(
      plaintext,
      filename: opts.filename ?? '',
    );

    final EncryptedMessageInterface encrypted;
    try {
      encrypted = switch (opts.mode) {
        EncryptMode.passphrase => OpenPGP.encrypt(
          message,
          passwords: [_requirePassphrase(opts.passphrase)],
          symmetric: _symmetric,
        ),
        EncryptMode.recipients => OpenPGP.encrypt(
          message,
          encryptionKeys: _parseRecipients(opts.recipients),
          symmetric: _symmetric,
        ),
      };
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw _classifyEncrypt(error);
    }

    yield opts.armor
        ? utf8.encode(encrypted.armor())
        : encrypted.packetList.encode();
  }

  @override
  Stream<List<int>> decrypt(
    Stream<List<int>> input,
    DecryptOptions opts,
  ) async* {
    final bytes = await collectBytes(input);
    final packets = _readPackets(bytes);

    final passwordSlots = packets.whereType<SymEncryptedSessionKeyPacket>();
    final keySlots = packets.whereType<PublicKeyEncryptedSessionKeyPacket>();
    if (passwordSlots.isEmpty && keySlots.isEmpty) {
      throw const NotEncryptedData();
    }

    final message = EncryptedMessage(packets);
    LiteralMessageInterface? opened;

    if (keySlots.isNotEmpty) {
      final keys = _matchingKeys(keySlots, opts.identities);
      if (keys.isNotEmpty) {
        opened = _attempt(() => message.decrypt(decryptionKeys: keys));
      } else if (passwordSlots.isEmpty) {
        throw const NoMatchingKey();
      }
    }

    if (opened == null && passwordSlots.isNotEmpty) {
      final passphrase = opts.passphrase;
      if (passphrase == null || passphrase.isEmpty) {
        throw const WrongPassphrase();
      }
      opened = _attempt(() => message.decrypt(passwords: [passphrase]));
      if (opened == null) throw const WrongPassphrase();
    }

    if (opened == null) throw const NoMatchingKey();

    final literal = opened.literalData;
    opts.onMetadata?.call(
      DecryptMetadata(
        filename: literal.filename.isEmpty ? null : literal.filename,
        signatures: _signatures(opened, opts.verificationKeys),
      ),
    );
    yield literal.binary;
  }

  /// what a PGP message will ask for, without decrypting anything, so the
  /// decrypt screen can show the right prompt straight away
  static PgpPeek? peek(Uint8List bytes) {
    try {
      final packets = _readPackets(bytes);
      return PgpPeek(
        needsPassphrase: packets
            .whereType<SymEncryptedSessionKeyPacket>()
            .isNotEmpty,
        needsKey: packets
            .whereType<PublicKeyEncryptedSessionKeyPacket>()
            .isNotEmpty,
      );
    } on Object {
      return null;
    }
  }

  static PacketListInterface _readPackets(Uint8List bytes) {
    try {
      final detected = FormatDetector.detect(bytes);
      if (detected == DetectedFormat.pgpArmoredMessage) {
        return OpenPGP.readEncryptedMessage(
          utf8.decode(bytes, allowMalformed: true),
        ).packetList;
      }
      return PacketList.decode(bytes);
    } on Object {
      throw const NotEncryptedData();
    }
  }

  /// dart_pg throws `Error` subclasses on a bad session key, the same path as
  /// a wrong passphrase, so the caller decides what it meant
  static LiteralMessageInterface? _attempt(
    LiteralMessageInterface Function() body,
  ) {
    try {
      return body();
    } on Object catch (error) {
      if (_looksTampered(error)) throw const DataTampered();
      return null;
    }
  }

  static bool _looksTampered(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('modification detected') ||
        text.contains('integrity') ||
        text.contains('authentication tag');
  }

  static List<PrivateKeyInterface> _matchingKeys(
    Iterable<PublicKeyEncryptedSessionKeyPacket> slots,
    List<Identity> identities,
  ) {
    final wanted = slots.map((slot) => keyIdHex(slot.keyID)).toSet();
    // a zero key id means "try every key"
    final anonymous = wanted.contains('0000000000000000');
    final matches = <PrivateKeyInterface>[];
    for (final identity in identities) {
      if (identity.format != CryptoFormatKind.pgp) continue;
      final PrivateKeyInterface key;
      try {
        key = parsePgpPrivateKey(identity.material);
      } on AppException {
        continue;
      }
      final decryptionKey = key.getDecryptionKeyPacket();
      if (decryptionKey == null) continue;
      if (!anonymous && !wanted.contains(keyIdHex(decryptionKey.keyID))) {
        continue;
      }
      matches.add(unlockPgpPrivateKey(key, identity.passphrase));
    }
    return matches;
  }

  static List<SignatureInfo> _signatures(
    LiteralMessageInterface message,
    List<Recipient> verificationKeys,
  ) {
    final signatures = message.packetList
        .whereType<SignaturePacketInterface>()
        .toList(growable: false);
    if (signatures.isEmpty) return const [];

    final keys = <KeyInterface>[];
    for (final recipient in verificationKeys) {
      if (recipient.format != CryptoFormatKind.pgp) continue;
      try {
        keys.add(parsePgpPublicKey(recipient.material));
      } on AppException {
        continue;
      }
    }

    if (keys.isEmpty) {
      return [
        for (final signature in signatures)
          SignatureInfo(
            keyId: keyIdHex(signature.issuerKeyID),
            verdict: SignatureVerdict.unknownSigner,
          ),
      ];
    }

    try {
      return [
        for (final result in message.verify(keys))
          SignatureInfo(
            keyId: keyIdHex(result.keyID),
            verdict: result.isVerified
                ? SignatureVerdict.valid
                : SignatureVerdict.invalid,
          ),
      ];
    } on Object {
      return [
        for (final signature in signatures)
          SignatureInfo(
            keyId: keyIdHex(signature.issuerKeyID),
            verdict: SignatureVerdict.unknownSigner,
          ),
      ];
    }
  }

  static List<KeyInterface> _parseRecipients(List<Recipient> recipients) {
    if (recipients.isEmpty) throw const NoRecipients();
    if (recipients.any((r) => r.format != CryptoFormatKind.pgp)) {
      throw const RecipientFormatMismatch();
    }
    final keys = [
      for (final recipient in recipients) parsePgpPublicKey(recipient.material),
    ];
    // a sign-only key has no encryption subkey, and dart_pg fails obscurely
    if (keys.any((key) => key.getEncryptionKeyPacket() == null)) {
      throw const KeyCannotEncrypt();
    }
    return keys;
  }

  static String _requirePassphrase(String? passphrase) {
    if (passphrase == null || passphrase.isEmpty) throw const WrongPassphrase();
    return passphrase;
  }

  static AppException _classifyEncrypt(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('encryption key') || text.contains('key packet')) {
      return const InvalidKeyMaterial();
    }
    return const CryptoFailed();
  }
}

class PgpPeek {
  const PgpPeek({required this.needsPassphrase, required this.needsKey});

  final bool needsPassphrase;
  final bool needsKey;
}
