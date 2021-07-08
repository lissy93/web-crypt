import 'dart:typed_data';

import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/crypto_jobs.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/runner/runner_stub.dart'
    if (dart.library.io) 'package:web_crypt/crypto/runner/runner_io.dart'
    if (dart.library.js_interop) 'package:web_crypt/crypto/runner/runner_web.dart';

class SizeLimits {
  const SizeLimits._();

  static const message = 1024 * 1024;
  static const webWarn = 200 * 1024 * 1024;
  static const webMax = 1024 * 1024 * 1024;
}

class DecryptOutcome {
  const DecryptOutcome({
    required this.bytes,
    required this.format,
    required this.metadata,
  });

  final Uint8List bytes;
  final CryptoFormatKind format;
  final DecryptMetadata metadata;
}

/// the only door between the UI and the crypto libraries
class CryptoService {
  const CryptoService();

  bool get canStreamFiles => supportsFileJobs;

  int? get maxInputBytes => supportsFileJobs ? null : SizeLimits.webMax;

  int? get warnInputBytes => supportsFileJobs ? null : SizeLimits.webWarn;

  Future<Uint8List> encryptBytes({
    required CryptoFormatKind format,
    required Uint8List input,
    required EncryptOptions options,
  }) async {
    _checkSize(input.length);
    final result = await runCryptoJob(
      EncryptBytesJob(format: format, input: input, options: options),
    );
    return result.bytes ?? Uint8List(0);
  }

  Future<DecryptOutcome> decryptBytes({
    required Uint8List input,
    String? passphrase,
    List<Identity> identities = const [],
    List<Recipient> verificationKeys = const [],
  }) async {
    _checkSize(input.length);
    final result = await runCryptoJob(
      DecryptBytesJob(
        input: input,
        passphrase: passphrase,
        identities: identities,
        verificationKeys: verificationKeys,
      ),
    );
    return DecryptOutcome(
      bytes: result.bytes ?? Uint8List(0),
      format: result.format ?? CryptoFormatKind.age,
      metadata: result.metadata,
    );
  }

  /// generated off the UI thread wherever the platform has somewhere else to
  /// put it
  Future<GeneratedKey> generateKey({
    required CryptoFormatKind format,
    String name = '',
    String email = '',
    String? passphrase,
    Duration? expiry,
  }) async {
    final result = await runCryptoJob(
      GenerateKeyJob(
        format: format,
        name: name,
        email: email,
        passphrase: passphrase,
        expiry: expiry,
      ),
    );
    final key = result.key;
    if (key == null) throw const CryptoFailed();
    return key;
  }

  /// desktop only. age streams source to target, PGP still buffers because
  /// the library cannot stream
  Future<void> encryptFile({
    required CryptoFormatKind format,
    required String sourcePath,
    required String targetPath,
    required EncryptOptions options,
    void Function(int processed)? onProgress,
  }) async {
    if (!supportsFileJobs) throw const FileAccessFailed();
    await runCryptoJob(
      EncryptFileJob(
        format: format,
        sourcePath: sourcePath,
        targetPath: targetPath,
        options: options,
      ),
      onProgress: onProgress,
    );
  }

  Future<DecryptMetadata> decryptFile({
    required String sourcePath,
    required String targetPath,
    String? passphrase,
    List<Identity> identities = const [],
    List<Recipient> verificationKeys = const [],
    void Function(int processed)? onProgress,
  }) async {
    if (!supportsFileJobs) throw const FileAccessFailed();
    final result = await runCryptoJob(
      DecryptFileJob(
        sourcePath: sourcePath,
        targetPath: targetPath,
        passphrase: passphrase,
        identities: identities,
        verificationKeys: verificationKeys,
      ),
      onProgress: onProgress,
    );
    return result.metadata;
  }

  void _checkSize(int length) {
    final max = maxInputBytes;
    if (max != null && length > max) throw InputTooLarge(max);
  }
}
