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

    // a failure to unlock means the wrong key or passphrase, not changed data
    final keys = keySlots.isEmpty
        ? const <PrivateKeyInterface>[]
        : _matchingKeys(keySlots, opts.identities);
    final keyed = keys.isEmpty ? null : _openKeySlots(packets, keys);
    var opened = keyed == null ? null : _open(message, keyed);
    final passphrase = opts.passphrase ?? '';
    if (opened == null && passphrase.isNotEmpty) {
      for (final key in _openPasswordSlots(passwordSlots, passphrase)) {
        opened = _open(message, key, guessed: true);
        if (opened != null) break;
      }
    }
    if (opened == null) {
      throw passwordSlots.isEmpty
          ? const NoMatchingKey()
          : const WrongPassphrase();
    }

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

  /// null when none of [keys] opens a key slot
  static SessionKeyInterface? _openKeySlots(
    PacketListInterface packets,
    List<PrivateKeyInterface> keys,
  ) {
    try {
      return EncryptedMessage.decryptSessionKey(packets, decryptionKeys: keys);
    } on Object {
      return null;
    }
  }

  /// keys the passphrase unlocks, skipping any the wrong size for its cipher
  static Iterable<SessionKeyInterface> _openPasswordSlots(
    Iterable<SymEncryptedSessionKeyPacket> slots,
    String passphrase,
  ) sync* {
    for (final slot in slots) {
      final SessionKeyInterface? key;
      try {
        key = slot.decrypt(passphrase).sessionKey;
      } on Object {
        continue;
      }
      if (key == null) continue;
      final fits =
          key.symmetric != SymmetricAlgorithm.plaintext &&
          key.encryptionKey.length == key.symmetric.keySizeInByte;
      if (slot.aead != null || fits) yield key;
    }
  }

  /// null when a guessed key fails the quick check, meaning a wrong passphrase
  static LiteralMessage? _open(
    EncryptedMessageInterface message,
    SessionKeyInterface key, {
    bool guessed = false,
  }) {
    try {
      return LiteralMessage(
        message.encryptedPacket
            .decrypt(key.encryptionKey, key.symmetric)
            .packets!,
      );
    } on QuickCheckError {
      if (guessed) return null;
      throw const DataTampered();
    } on UnsupportedError {
      throw const UnsupportedFeature();
    } on Object {
      throw const DataTampered();
    }
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

  /// a verdict for each signature, compressed or not, known signer or not
  static List<SignatureInfo> _signatures(
    LiteralMessage message,
    List<Recipient> verificationKeys,
  ) {
    final signatures = message.signature.packets;
    if (signatures.isEmpty) return const [];
    final signers = _signers(verificationKeys);
    final data = message.literalData.signBytes;
    return [
      for (final signature in signatures) _check(signature, signers, data),
    ];
  }

  /// anything short of a clean check by a key that can vouch is invalid
  static SignatureInfo _check(
    SignaturePacketInterface signature,
    Map<String, KeyPacketInterface?> signers,
    Uint8List data,
  ) {
    var keyId = '';
    var verdict = SignatureVerdict.invalid;
    try {
      keyId = keyIdHex(signature.issuerKeyID);
      final key = signers[keyId];
      if (key != null && signature.verify(key, data)) {
        verdict = SignatureVerdict.valid;
      } else if (!signers.containsKey(keyId)) {
        verdict = SignatureVerdict.unknownSigner;
      }
    } on Object {
      // malformed, so it stays invalid
    }
    return SignatureInfo(keyId: keyId, verdict: verdict);
  }

  /// key packets by id, null for a held key that can't vouch for anything
  static Map<String, KeyPacketInterface?> _signers(List<Recipient> recipients) {
    final signers = <String, KeyPacketInterface?>{};
    // a usable copy of a key wins over an unusable one
    void hold(Uint8List id, KeyPacketInterface? packet) => signers.update(
      keyIdHex(id),
      (held) => held ?? packet,
      ifAbsent: () => packet,
    );
    for (final recipient in recipients) {
      if (recipient.format != CryptoFormatKind.pgp) continue;
      try {
        final key = parsePgpPublicKey(recipient.material);
        final live = !key.isRevoked();
        final primary = key.keyPacket;
        hold(primary.keyID, live && primary.isSigningKey ? primary : null);
        for (final subkey in key.subkeys) {
          final fit = live && !subkey.isRevoked() && subkey.isSigningKey;
          hold(subkey.keyID, fit ? subkey.keyPacket : null);
        }
      } on Object {
        // one broken key shouldn't stop the rest
      }
    }
    return signers;
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
