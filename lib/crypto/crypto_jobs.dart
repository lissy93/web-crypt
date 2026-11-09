import 'dart:typed_data';

import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_format.dart';

/// plain data so they can cross an isolate boundary, so nothing here may
/// hold a closure
sealed class CryptoJob {
  const CryptoJob();
}

class EncryptBytesJob extends CryptoJob {
  const EncryptBytesJob({
    required this.format,
    required this.input,
    required this.options,
  });

  final CryptoFormatKind format;
  final Uint8List input;
  final EncryptOptions options;
}

class DecryptBytesJob extends CryptoJob {
  const DecryptBytesJob({
    required this.input,
    required this.passphrase,
    required this.identities,
    required this.verificationKeys,
  });

  final Uint8List input;
  final String? passphrase;
  final List<Identity> identities;
  final List<Recipient> verificationKeys;
}

class EncryptFileJob extends CryptoJob {
  const EncryptFileJob({
    required this.format,
    required this.sourcePath,
    required this.targetPath,
    required this.options,
  });

  final CryptoFormatKind format;
  final String sourcePath;
  final String targetPath;
  final EncryptOptions options;
}

class DecryptFileJob extends CryptoJob {
  const DecryptFileJob({
    required this.sourcePath,
    required this.targetPath,
    required this.passphrase,
    required this.identities,
    required this.verificationKeys,
  });

  final String sourcePath;
  final String targetPath;
  final String? passphrase;
  final List<Identity> identities;
  final List<Recipient> verificationKeys;
}

/// goes through the runner like every other job, since PGP keygen is the
/// heaviest thing here. [name], [email] and [expiry] are ignored for age
class GenerateKeyJob extends CryptoJob {
  const GenerateKeyJob({
    required this.format,
    this.name = '',
    this.email = '',
    this.passphrase,
    this.expiry,
  });

  final CryptoFormatKind format;
  final String name;
  final String email;
  final String? passphrase;
  final Duration? expiry;
}

class GeneratedKey {
  const GeneratedKey({
    required this.publicMaterial,
    required this.privateMaterial,
    required this.fingerprint,
    this.userId = '',
    this.isProtected = false,
  });

  final String publicMaterial;
  final String privateMaterial;

  /// the age recipient, or the hex PGP primary key fingerprint
  final String fingerprint;
  final String userId;
  final bool isProtected;
}

class CryptoJobResult {
  const CryptoJobResult({
    this.bytes,
    this.metadata = const DecryptMetadata(),
    this.format,
    this.key,
  });

  final Uint8List? bytes;
  final DecryptMetadata metadata;
  final CryptoFormatKind? format;
  final GeneratedKey? key;
}

CryptoFormat formatFor(CryptoFormatKind kind) => switch (kind) {
  CryptoFormatKind.age => const AgeFormat(),
  CryptoFormatKind.pgp => const PgpFormat(),
};

/// picks the container by sniffing, so nobody has to say which it is
CryptoFormatKind formatForInput(List<int> head) {
  final detected = FormatDetector.detect(head);
  final kind = detected.formatKind;
  if (kind == null || !detected.isMessage) throw const NotEncryptedData();
  return kind;
}
