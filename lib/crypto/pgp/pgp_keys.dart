import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart';
import 'package:web_crypt/core/errors/app_exception.dart';

class PgpKeyPairStrings {
  const PgpKeyPairStrings({
    required this.publicKey,
    required this.privateKey,
    required this.fingerprint,
    required this.userId,
    required this.isProtected,
  });

  final String publicKey;
  final String privateKey;
  final String fingerprint;
  final String userId;
  final bool isProtected;
}

/// Ed25519 primary with a Curve25519 encryption subkey, which GnuPG 2.2 and
/// up read without complaint
PgpKeyPairStrings generatePgpKeyPair({
  String name = '',
  String email = '',
  String? passphrase,
  Duration? expiry,
}) {
  final userId = _formatUserId(name: name, email: email);
  if (userId.isEmpty) throw const InvalidKeyMaterial();

  // dart_pg will not generate an unprotected key, so unlock a throwaway one
  final wanted = passphrase != null && passphrase.isNotEmpty;
  final buildPassphrase = wanted ? passphrase : _throwawayPassphrase();
  final generated = OpenPGP.generateKey(
    [userId],
    buildPassphrase,
    type: KeyType.ecc,
    curve: Ecc.ed25519,
    keyExpiry: expiry?.inSeconds ?? 0,
  );
  final key = wanted
      ? generated
      : (generated.decrypt(buildPassphrase) as PrivateKey).unprotect();
  return PgpKeyPairStrings(
    publicKey: key.publicKey.armor(),
    privateKey: key.armor(),
    fingerprint: fingerprintOf(key),
    userId: userId,
    isProtected: wanted,
  );
}

String _formatUserId({required String name, required String email}) {
  final trimmedName = name.trim();
  final trimmedEmail = email.trim();
  if (trimmedName.isEmpty && trimmedEmail.isEmpty) return '';
  if (trimmedEmail.isEmpty) return trimmedName;
  if (trimmedName.isEmpty) return trimmedEmail;
  return '$trimmedName <$trimmedEmail>';
}

String fingerprintOf(KeyInterface key) =>
    key.fingerprint.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String keyIdHex(Uint8List keyId) =>
    keyId.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

KeyInterface parsePgpPublicKey(String armored) {
  try {
    return OpenPGP.readPublicKey(armored.trim());
  } on Object {
    throw const InvalidKeyMaterial();
  }
}

PrivateKeyInterface parsePgpPrivateKey(String armored) {
  try {
    return OpenPGP.readPrivateKey(armored.trim());
  } on Object {
    throw const InvalidKeyMaterial();
  }
}

PrivateKeyInterface unlockPgpPrivateKey(
  PrivateKeyInterface key,
  String? passphrase,
) {
  if (key.isDecrypted) return key;
  if (passphrase == null || passphrase.isEmpty) throw const KeyLocked();
  try {
    return key.decrypt(passphrase);
  } on Object {
    throw const WrongPassphrase();
  }
}

String primaryUserId(KeyInterface key) =>
    key.users.isEmpty ? '' : key.users.first.userID;

/// only there to satisfy dart_pg's mandatory generation passphrase, then
/// thrown away. `Random.secure()` is the platform CSPRNG, not `Random()`
String _throwawayPassphrase() {
  final random = Random.secure();
  return base64Url.encode(
    Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
  );
}
