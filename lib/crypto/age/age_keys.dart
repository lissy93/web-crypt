import 'package:dage/dage.dart' as dage;
import 'package:web_crypt/core/errors/app_exception.dart';

class AgeKeyPairStrings {
  const AgeKeyPairStrings({required this.recipient, required this.identity});

  final String recipient;
  final String identity;
}

/// keys come from the library's own CSPRNG
Future<AgeKeyPairStrings> generateAgeKeyPair() async {
  final pair = await dage.X25519AgePlugin.generateKeyPair();
  return AgeKeyPairStrings(
    recipient: pair.recipient.toString(),
    identity: dage.AgeIdentity(
      dage.X25519AgePlugin.privateKeyPrefix,
      pair.identityBytes!,
    ).toString(),
  );
}

dage.AgeRecipient parseAgeRecipient(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('age1')) throw const InvalidKeyMaterial();
  try {
    final recipient = dage.AgeRecipient.fromBech32(trimmed);
    if (recipient.prefix != dage.X25519AgePlugin.publicKeyPrefix ||
        recipient.bytes.length != 32) {
      throw const InvalidKeyMaterial();
    }
    return recipient;
  } on AppException {
    rethrow;
  } on Object {
    throw const InvalidKeyMaterial();
  }
}

Future<dage.AgeKeyPair> parseAgeIdentity(String value) async {
  final pair = await tryParseAgeIdentity(value);
  if (pair == null) throw const InvalidKeyMaterial();
  return pair;
}

Future<dage.AgeKeyPair?> tryParseAgeIdentity(String value) async {
  final trimmed = _identityToken(value);
  if (trimmed == null) return null;
  try {
    final identity = dage.AgeIdentity.fromBech32(trimmed);
    if (identity.bytes.length != 32) return null;
    return await const dage.X25519AgePlugin().identityToKeyPair(identity);
  } on Object {
    return null;
  }
}

/// age identity files carry `# comment` lines above the key
String? _identityToken(String value) {
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.toUpperCase().startsWith('AGE-SECRET-KEY-1')) {
      return trimmed.toUpperCase();
    }
  }
  return null;
}

/// the file `age -d -i` expects
String ageIdentityFile(String identity, String recipient, DateTime created) {
  final stamp = created.toUtc().toIso8601String();
  return '# created: $stamp\n# public key: $recipient\n$identity\n';
}

Future<String> recipientForIdentity(String identity) async {
  final pair = await parseAgeIdentity(identity);
  return pair.recipient.toString();
}
