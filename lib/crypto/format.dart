enum CryptoFormatKind {
  age('age'),
  pgp('PGP');

  const CryptoFormatKind(this.label);

  final String label;
}

enum EncryptMode {
  passphrase('Passphrase'),
  recipients('Recipients');

  const EncryptMode(this.label);

  final String label;
}

/// [material] is an `age1...` recipient or an armored PGP public key block
class Recipient {
  const Recipient({
    required this.format,
    required this.material,
    required this.label,
  });

  final CryptoFormatKind format;
  final String material;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is Recipient &&
      other.format == format &&
      other.material == material;

  @override
  int get hashCode => Object.hash(format, material);
}

/// [material] is an `AGE-SECRET-KEY-1...` identity or an armored PGP private
/// key block. [passphrase] unlocks a protected PGP key, and is unused for age
class Identity {
  const Identity({
    required this.format,
    required this.material,
    this.passphrase,
    this.label = '',
  });

  final CryptoFormatKind format;
  final String material;
  final String? passphrase;
  final String label;
}

class EncryptOptions {
  const EncryptOptions({
    required this.mode,
    this.passphrase,
    this.recipients = const [],
    this.armor = false,
    this.filename,
  });

  const EncryptOptions.withPassphrase(
    String this.passphrase, {
    this.armor = false,
    this.filename,
  }) : mode = EncryptMode.passphrase,
       recipients = const [];

  const EncryptOptions.forRecipients(
    this.recipients, {
    this.armor = false,
    this.filename,
  }) : mode = EncryptMode.recipients,
       passphrase = null;

  final EncryptMode mode;
  final String? passphrase;
  final List<Recipient> recipients;
  final bool armor;

  /// stored in the PGP literal data packet so `gpg -d` can suggest a name.
  /// age has no filename field, so it is ignored there
  final String? filename;
}

class DecryptOptions {
  const DecryptOptions({
    this.passphrase,
    this.identities = const [],
    this.verificationKeys = const [],
    this.onMetadata,
  });

  final String? passphrase;
  final List<Identity> identities;

  /// public keys used to check any signature the message carries
  final List<Recipient> verificationKeys;

  /// called once, before the payload stream finishes, with whatever the
  /// container carried besides the payload itself
  final void Function(DecryptMetadata metadata)? onMetadata;
}

class DecryptMetadata {
  const DecryptMetadata({this.filename, this.signatures = const []});

  final String? filename;
  final List<SignatureInfo> signatures;
}

enum SignatureVerdict { valid, invalid, unknownSigner }

class SignatureInfo {
  const SignatureInfo({required this.keyId, required this.verdict});

  final String keyId;
  final SignatureVerdict verdict;
}

abstract class CryptoFormat {
  Stream<List<int>> encrypt(Stream<List<int>> input, EncryptOptions opts);

  Stream<List<int>> decrypt(Stream<List<int>> input, DecryptOptions opts);
}
