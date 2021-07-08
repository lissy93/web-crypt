import 'dart:convert';

import 'package:web_crypt/crypto/format.dart';

enum DetectedFormat {
  ageBinary,
  ageArmored,
  pgpArmoredMessage,
  pgpBinary,
  pgpPublicKey,
  pgpPrivateKey,
  ageIdentity,
  ageRecipient,
  unknown;

  bool get isMessage => const {
    DetectedFormat.ageBinary,
    DetectedFormat.ageArmored,
    DetectedFormat.pgpArmoredMessage,
    DetectedFormat.pgpBinary,
  }.contains(this);

  bool get isKey => const {
    DetectedFormat.pgpPublicKey,
    DetectedFormat.pgpPrivateKey,
    DetectedFormat.ageIdentity,
    DetectedFormat.ageRecipient,
  }.contains(this);

  bool get isArmored => const {
    DetectedFormat.ageArmored,
    DetectedFormat.pgpArmoredMessage,
    DetectedFormat.pgpPublicKey,
    DetectedFormat.pgpPrivateKey,
  }.contains(this);

  CryptoFormatKind? get formatKind => switch (this) {
    DetectedFormat.ageBinary ||
    DetectedFormat.ageArmored ||
    DetectedFormat.ageIdentity ||
    DetectedFormat.ageRecipient => CryptoFormatKind.age,
    DetectedFormat.pgpArmoredMessage ||
    DetectedFormat.pgpBinary ||
    DetectedFormat.pgpPublicKey ||
    DetectedFormat.pgpPrivateKey => CryptoFormatKind.pgp,
    DetectedFormat.unknown => null,
  };

  String get describe => switch (this) {
    DetectedFormat.ageBinary => 'age encrypted file',
    DetectedFormat.ageArmored => 'age encrypted message',
    DetectedFormat.pgpArmoredMessage => 'PGP message',
    DetectedFormat.pgpBinary => 'PGP encrypted file',
    DetectedFormat.pgpPublicKey => 'PGP public key',
    DetectedFormat.pgpPrivateKey => 'PGP private key',
    DetectedFormat.ageIdentity => 'age identity (private key)',
    DetectedFormat.ageRecipient => 'age recipient (public key)',
    DetectedFormat.unknown => 'unrecognised',
  };
}

const _ageMagic = 'age-encryption.org/v1';
const _ageArmorHeader = '-----BEGIN AGE ENCRYPTED FILE-----';
const _pgpMessageHeader = '-----BEGIN PGP MESSAGE-----';
const _pgpPublicHeader = '-----BEGIN PGP PUBLIC KEY BLOCK-----';
const _pgpPrivateHeader = '-----BEGIN PGP PRIVATE KEY BLOCK-----';
const _ageIdentityPrefix = 'AGE-SECRET-KEY-1';
const _ageRecipientPrefix = 'age1';

/// enough leading bytes to decide: armor headers plus a little slack
const detectionHeadSize = 512;

/// tags plausible at the start of a binary PGP file: PKESK, SKESK,
/// compressed data, SEIPD
const _plausiblePgpTags = {1, 3, 8, 18};

class FormatDetector {
  const FormatDetector._();

  /// never throws, garbage in gives [DetectedFormat.unknown] out
  static DetectedFormat detect(List<int> head) {
    if (head.isEmpty) return DetectedFormat.unknown;

    final text = _asText(head);
    if (text != null) {
      final trimmed = text.trimLeft();
      if (trimmed.startsWith(_ageMagic)) return DetectedFormat.ageBinary;
      if (trimmed.startsWith(_ageArmorHeader)) return DetectedFormat.ageArmored;
      if (trimmed.startsWith(_pgpMessageHeader)) {
        return DetectedFormat.pgpArmoredMessage;
      }
      if (trimmed.startsWith(_pgpPublicHeader)) {
        return DetectedFormat.pgpPublicKey;
      }
      if (trimmed.startsWith(_pgpPrivateHeader)) {
        return DetectedFormat.pgpPrivateKey;
      }
      final token = text.trim();
      if (token.startsWith(_ageIdentityPrefix)) {
        return DetectedFormat.ageIdentity;
      }
      if (token.startsWith(_ageRecipientPrefix) && !_hasWhitespace(token)) {
        return DetectedFormat.ageRecipient;
      }
    }

    if (_looksLikePgpPacket(head)) return DetectedFormat.pgpBinary;
    return DetectedFormat.unknown;
  }

  /// decodes only enough to compare against ASCII markers, and returns null
  /// when the head is clearly not text
  static String? _asText(List<int> head) {
    final limit = head.length < detectionHeadSize
        ? head.length
        : detectionHeadSize;
    final buffer = StringBuffer();
    for (var i = 0; i < limit; i++) {
      final byte = head[i];
      if (byte == 0 || byte > 0x7e) {
        return buffer.isEmpty ? null : buffer.toString();
      }
      if (byte < 0x20 && byte != 0x09 && byte != 0x0a && byte != 0x0d) {
        return buffer.isEmpty ? null : buffer.toString();
      }
      buffer.writeCharCode(byte);
    }
    return buffer.toString();
  }

  static bool _hasWhitespace(String value) => value.codeUnits.any(
    (c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d,
  );

  /// reads the header and the first body byte, because a tag alone matches
  /// roughly one random byte in eight
  static bool _looksLikePgpPacket(List<int> head) {
    final first = head[0];
    if (first & 0x80 == 0) return false;
    final isNewFormat = first & 0x40 != 0;
    final tag = isNewFormat ? first & 0x3f : (first >> 2) & 0x0f;
    if (!_plausiblePgpTags.contains(tag)) return false;

    final bodyStart = _bodyOffset(head, isNewFormat: isNewFormat, first: first);
    if (bodyStart == null || bodyStart >= head.length) return false;
    return _plausibleBody(tag, head, bodyStart);
  }

  static int? _bodyOffset(
    List<int> head, {
    required bool isNewFormat,
    required int first,
  }) {
    if (head.length < 2) return null;
    if (isNewFormat) {
      final lengthByte = head[1];
      if (lengthByte < 192) return 2;
      if (lengthByte < 224) return 3;
      // a partial length only makes sense for the streaming data packets
      if (lengthByte < 255) {
        return _tagAllowsPartialLength(first & 0x3f) ? 2 : null;
      }
      return 6;
    }
    // old format, the low two bits pick the length field width
    return switch (first & 0x03) {
      0 => 2,
      1 => 3,
      2 => 5,
      _ => (first >> 2) & 0x0f == 8 ? 1 : null,
    };
  }

  static bool _tagAllowsPartialLength(int tag) =>
      tag == 8 || tag == 9 || tag == 11 || tag == 18;

  /// public key algorithm ids that appear in a session key packet
  static const _keyAlgorithms = {1, 2, 3, 16, 17, 18, 19, 22, 25, 26, 27, 28};

  /// symmetric cipher ids, IDEA through Camellia-256
  static const _symmetricAlgorithms = {1, 2, 3, 4, 7, 8, 9, 10, 11, 12, 13};

  /// reads a couple of bytes past the version, because a version byte alone
  /// still matches roughly one random header in three hundred
  static bool _plausibleBody(int tag, List<int> head, int start) {
    int? at(int offset) {
      final index = start + offset;
      return index < head.length ? head[index] : null;
    }

    final version = head[start];
    return switch (tag) {
      // PKESK v3 is version, 8 byte key id, then the algorithm
      1 => switch (version) {
        3 => _keyAlgorithms.contains(at(9) ?? -1),
        6 => true,
        _ => false,
      },
      // SKESK is version, symmetric cipher, then the S2K type
      3 => switch (version) {
        4 =>
          _symmetricAlgorithms.contains(at(1) ?? -1) &&
              const {0, 1, 3, 4}.contains(at(2) ?? -1),
        5 || 6 => _symmetricAlgorithms.contains(at(1) ?? -1),
        _ => false,
      },
      8 => version <= 3,
      // SEIPD v1 is followed by ciphertext, v2 by the cipher and AEAD ids
      18 => switch (version) {
        1 => true,
        2 => _symmetricAlgorithms.contains(at(1) ?? -1),
        _ => false,
      },
      _ => false,
    };
  }
}

/// which stanza types an age header carries, so the decrypt screen can say
/// "needs a passphrase" before anything is attempted
enum AgeStanzaKind { scrypt, x25519, other }

class AgeHeaderPeek {
  const AgeHeaderPeek(this.stanzas);

  final Set<AgeStanzaKind> stanzas;

  bool get needsPassphrase => stanzas.contains(AgeStanzaKind.scrypt);

  bool get needsIdentity => stanzas.contains(AgeStanzaKind.x25519);

  /// reads only the ASCII header of an unarmored age file
  static AgeHeaderPeek? read(List<int> head) {
    final found = <AgeStanzaKind>{};
    final text = _headerText(head);
    if (text == null) return null;
    for (final line in const LineSplitter().convert(text)) {
      if (!line.startsWith('-> ')) continue;
      final argument = line.substring(3).split(' ').first;
      found.add(switch (argument) {
        'scrypt' => AgeStanzaKind.scrypt,
        'X25519' => AgeStanzaKind.x25519,
        _ => AgeStanzaKind.other,
      });
    }
    return found.isEmpty ? null : AgeHeaderPeek(found);
  }

  static String? _headerText(List<int> head) {
    final buffer = StringBuffer();
    final limit = head.length < detectionHeadSize
        ? head.length
        : detectionHeadSize;
    var dashes = 0;
    var afterNewline = false;
    for (var i = 0; i < limit; i++) {
      final byte = head[i];
      if (byte == 0 || byte > 0x7e) break;
      buffer.writeCharCode(byte);
      // the header ends at the MAC line, which starts with `---`
      if (byte == 0x0a) {
        afterNewline = true;
        dashes = 0;
      } else if (afterNewline && byte == 0x2d) {
        if (++dashes == 3) break;
      } else {
        afterNewline = false;
        dashes = 0;
      }
    }
    final text = buffer.toString();
    return text.startsWith(_ageMagic) ? text : null;
  }
}
