import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:dage/dage.dart' as dage;
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';

/// age-encryption.org/v1, over the vendored `dage` fork
class AgeFormat implements CryptoFormat {
  const AgeFormat();

  /// errors arrive on the returned stream rather than at the call site, so a
  /// caller can handle both the same way
  @override
  Stream<List<int>> encrypt(
    Stream<List<int>> input,
    EncryptOptions opts,
  ) async* {
    final raw = switch (opts.mode) {
      EncryptMode.passphrase => dage.encryptWithPassphrase(
        input,
        passphraseProvider: dage.StaticPassphraseProvider(
          _requirePassphrase(opts.passphrase),
        ),
      ),
      EncryptMode.recipients => dage.encrypt(
        input,
        _parseRecipients(opts.recipients),
      ),
    };
    yield* opts.armor ? _armor(raw, opts.mode) : _mapErrors(raw, opts.mode);
  }

  @override
  Stream<List<int>> decrypt(
    Stream<List<int>> input,
    DecryptOptions opts,
  ) async* {
    opts.onMetadata?.call(const DecryptMetadata());

    final peeked = await peekHead(input, detectionHeadSize);
    final detected = FormatDetector.detect(peeked.head);
    final body = detected == DetectedFormat.ageArmored
        ? Stream.value(_dearmor(await collectBytes(peeked.stream)))
        : peeked.stream;

    final headed = await peekHead(body, detectionHeadSize);
    final header = AgeHeaderPeek.read(headed.head);
    if (header == null) throw const NotEncryptedData();

    if (header.needsPassphrase) {
      if (opts.passphrase == null || opts.passphrase!.isEmpty) {
        throw const WrongPassphrase();
      }
      yield* _mapErrors(
        dage.decryptWithPassphrase(
          headed.stream,
          passphraseProvider: dage.StaticPassphraseProvider(opts.passphrase!),
        ),
        EncryptMode.passphrase,
      );
      return;
    }

    final keyPairs = <dage.AgeKeyPair>[];
    for (final identity in opts.identities) {
      if (identity.format != CryptoFormatKind.age) continue;
      final pair = await tryParseAgeIdentity(identity.material);
      if (pair != null) keyPairs.add(pair);
    }
    if (keyPairs.isEmpty) throw const NoMatchingKey();
    yield* _mapErrors(
      dage.decrypt(headed.stream, keyPairs),
      EncryptMode.recipients,
    );
  }

  /// what an age file will ask for, without decrypting anything. handles the
  /// armored shape too, so the decrypt screen can prompt straight away
  static AgeHeaderPeek? peekHeader(Uint8List bytes) {
    try {
      final body = FormatDetector.detect(bytes) == DetectedFormat.ageArmored
          ? _dearmor(bytes)
          : bytes;
      return AgeHeaderPeek.read(body);
    } on Object {
      return null;
    }
  }

  Stream<List<int>> _armor(Stream<List<int>> raw, EncryptMode mode) async* {
    final bytes = await collectBytes(_mapErrors(raw, mode));
    yield utf8.encode(dage.AgeArmorEncoder().convert(bytes));
  }

  static List<int> _dearmor(List<int> bytes) {
    try {
      return dage.AgeArmorDecoder().convert(
        utf8.decode(bytes, allowMalformed: true),
      );
    } on Object {
      throw const NotEncryptedData();
    }
  }

  static List<dage.AgeRecipient> _parseRecipients(List<Recipient> recipients) {
    if (recipients.isEmpty) throw const NoRecipients();
    if (recipients.any((r) => r.format != CryptoFormatKind.age)) {
      throw const RecipientFormatMismatch();
    }
    return [
      for (final recipient in recipients) parseAgeRecipient(recipient.material),
    ];
  }

  static String _requirePassphrase(String? passphrase) {
    if (passphrase == null || passphrase.isEmpty) throw const WrongPassphrase();
    return passphrase;
  }

  /// dage reports most problems as a bare `Exception`, so a few of these fall
  /// back to matching text. none of that text ever reaches the UI
  static Stream<List<int>> _mapErrors(
    Stream<List<int>> source,
    EncryptMode mode,
  ) {
    return source.handleError((Object error) {
      throw _classify(error, mode);
    });
  }

  static AppException _classify(Object error, EncryptMode mode) {
    if (error is AppException) return error;
    if (error is dage.StanzaUnwrapException) {
      return mode == EncryptMode.passphrase
          ? const WrongPassphrase()
          : const NoMatchingKey();
    }
    if (error is SecretBoxAuthenticationError) return const DataTampered();
    final text = error.toString().toLowerCase();
    if (text.contains('recipient not found')) return const NoMatchingKey();
    if (text.contains('could not encrypt to any recipient')) {
      return const NoRecipients();
    }
    if (text.contains('mac')) return const DataTampered();
    if (text.contains('unsupported version') ||
        text.contains('stanza') ||
        text.contains('chunk size') ||
        text.contains('payload')) {
      return const NotEncryptedData();
    }
    return const CryptoFailed();
  }
}
