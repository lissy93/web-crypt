import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/log.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/crypto_jobs.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

const _log = Log('crypto');

/// pure Dart, so the same code serves the app, the tests and the interop
/// harness
Future<CryptoJobResult> executeBytesJob(CryptoJob job) async {
  return switch (job) {
    EncryptBytesJob() => _encryptBytes(job),
    DecryptBytesJob() => _decryptBytes(job),
    GenerateKeyJob() => _generateKey(job),
    EncryptFileJob() || DecryptFileJob() => throw const FileAccessFailed(),
  };
}

Future<CryptoJobResult> _encryptBytes(EncryptBytesJob job) async {
  // sizes and shapes only, never the bytes or the passphrase
  _log.debug(
    'encrypt ${job.format.name} ${job.options.mode.name} '
    '${job.input.length}B armor=${job.options.armor}',
  );
  final bytes = await collectBytes(
    formatFor(job.format).encrypt(Stream.value(job.input), job.options),
  );
  return CryptoJobResult(bytes: bytes, format: job.format);
}

Future<CryptoJobResult> _decryptBytes(DecryptBytesJob job) async {
  final kind = formatForInput(job.input);
  _log.debug(
    'decrypt ${kind.name} ${job.input.length}B '
    'identities=${job.identities.length}',
  );
  var metadata = const DecryptMetadata();
  final bytes = await collectBytes(
    formatFor(kind).decrypt(
      Stream.value(job.input),
      DecryptOptions(
        passphrase: job.passphrase,
        identities: job.identities,
        verificationKeys: job.verificationKeys,
        onMetadata: (value) => metadata = value,
      ),
    ),
  );
  return CryptoJobResult(bytes: bytes, metadata: metadata, format: kind);
}

Future<CryptoJobResult> _generateKey(GenerateKeyJob job) async {
  _log.debug('generate ${job.format.name} expiry=${job.expiry != null}');
  return CryptoJobResult(
    format: job.format,
    key: switch (job.format) {
      CryptoFormatKind.age => await _generateAgeKey(),
      CryptoFormatKind.pgp => _generatePgpKey(job),
    },
  );
}

Future<GeneratedKey> _generateAgeKey() async {
  final pair = await generateAgeKeyPair();
  return GeneratedKey(
    publicMaterial: pair.recipient,
    privateMaterial: pair.identity,
    fingerprint: pair.recipient,
  );
}

GeneratedKey _generatePgpKey(GenerateKeyJob job) {
  final pair = generatePgpKeyPair(
    name: job.name,
    email: job.email,
    passphrase: job.passphrase,
    expiry: job.expiry,
  );
  return GeneratedKey(
    publicMaterial: pair.publicKey,
    privateMaterial: pair.privateKey,
    fingerprint: pair.fingerprint,
    userId: pair.userId,
    isProtected: pair.isProtected,
  );
}
