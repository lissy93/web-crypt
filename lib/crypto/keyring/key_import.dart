import 'dart:convert';

import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

class ParsedKey {
  const ParsedKey({required this.entry, this.privateMaterial});

  final KeyEntry entry;
  final String? privateMaterial;

  bool get isPrivate => privateMaterial != null;
}

/// works out what was pasted or dropped, and throws [InvalidKeyMaterial]
/// rather than guessing
Future<ParsedKey> parseKeyMaterial(
  String text, {
  required String id,
  required DateTime now,
  String label = '',
}) async {
  final detected = FormatDetector.detect(utf8.encode(text));
  return switch (detected) {
    DetectedFormat.ageRecipient => _ageRecipient(text, id, now, label),
    DetectedFormat.ageIdentity => _ageIdentity(text, id, now, label),
    DetectedFormat.pgpPublicKey => _pgpPublic(text, id, now, label),
    DetectedFormat.pgpPrivateKey => _pgpPrivate(text, id, now, label),
    // an age identity file opens with comments, so it sniffs as plain text
    _ => _fallback(text, id, now, label),
  };
}

Future<ParsedKey> _fallback(
  String text,
  String id,
  DateTime now,
  String label,
) async {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.toUpperCase().startsWith('AGE-SECRET-KEY-1')) {
      return _ageIdentity(trimmed, id, now, label);
    }
    if (trimmed.startsWith('age1') && !trimmed.contains(' ')) {
      return _ageRecipient(trimmed, id, now, label);
    }
  }
  throw const InvalidKeyMaterial();
}

Future<ParsedKey> _ageRecipient(
  String text,
  String id,
  DateTime now,
  String label,
) async {
  final recipient = parseAgeRecipient(text.trim()).toString();
  return ParsedKey(
    entry: KeyEntry(
      id: id,
      format: CryptoFormatKind.age,
      label: label,
      publicMaterial: recipient,
      fingerprint: recipient,
      createdAt: now,
    ),
  );
}

Future<ParsedKey> _ageIdentity(
  String text,
  String id,
  DateTime now,
  String label,
) async {
  final pair = await parseAgeIdentity(text);
  final recipient = pair.recipient.toString();
  final identity = _identityLine(text);
  return ParsedKey(
    entry: KeyEntry(
      id: id,
      format: CryptoFormatKind.age,
      label: label,
      publicMaterial: recipient,
      fingerprint: recipient,
      createdAt: now,
      hasPrivate: true,
    ),
    privateMaterial: identity,
  );
}

String _identityLine(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim().toUpperCase();
    if (trimmed.startsWith('AGE-SECRET-KEY-1')) return trimmed;
  }
  throw const InvalidKeyMaterial();
}

Future<ParsedKey> _pgpPublic(
  String text,
  String id,
  DateTime now,
  String label,
) async {
  final key = parsePgpPublicKey(text);
  return ParsedKey(
    entry: KeyEntry(
      id: id,
      format: CryptoFormatKind.pgp,
      label: label,
      publicMaterial: key.armor(),
      fingerprint: fingerprintOf(key),
      createdAt: now,
      userId: primaryUserId(key),
      expiresAt: key.expirationTime,
    ),
  );
}

Future<ParsedKey> _pgpPrivate(
  String text,
  String id,
  DateTime now,
  String label,
) async {
  final key = parsePgpPrivateKey(text);
  return ParsedKey(
    entry: KeyEntry(
      id: id,
      format: CryptoFormatKind.pgp,
      label: label,
      publicMaterial: key.publicKey.armor(),
      fingerprint: fingerprintOf(key),
      createdAt: now,
      hasPrivate: true,
      privateIsProtected: !key.isDecrypted,
      userId: primaryUserId(key),
      expiresAt: key.expirationTime,
    ),
    privateMaterial: key.armor(),
  );
}
