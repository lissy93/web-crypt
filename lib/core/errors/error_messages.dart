import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/formatters.dart';

class ErrorMessage {
  const ErrorMessage(this.title, [this.hint]);

  final String title;
  final String? hint;
}

/// the single place an exception turns into words a person reads
ErrorMessage messageFor(Object error) {
  if (error is! AppException) return const ErrorMessage(_unexpected);
  return switch (error) {
    WrongPassphrase() => const ErrorMessage(
      'That passphrase did not match.',
      'Check for typos or a different keyboard layout, then try again.',
    ),
    NoMatchingKey() => const ErrorMessage(
      'None of your keys can open this.',
      'Add the private key it was encrypted to, then try again.',
    ),
    KeyLocked() => const ErrorMessage(
      'That private key is locked.',
      'Enter the passphrase that protects the key.',
    ),
    DataTampered() => const ErrorMessage(
      'This data failed verification and was not decrypted.',
      'It was changed or damaged after it was encrypted.',
    ),
    NotEncryptedData() => const ErrorMessage(
      "This doesn't look like an encrypted file or message.",
      'Paste an age or PGP message, or drop an encrypted file.',
    ),
    InvalidKeyMaterial() => const ErrorMessage(
      'That is not a key we recognise.',
      'Expected an age recipient or identity, or an armored PGP key.',
    ),
    DuplicateKey() => const ErrorMessage(
      'That key is already in your keyring.',
    ),
    KeyCannotEncrypt() => const ErrorMessage(
      'That PGP key cannot be encrypted to.',
      'It has no encryption subkey. Ask its owner for one that does.',
    ),
    KeyringLocked() => const ErrorMessage(
      'Your keyring is locked.',
      'Unlock it with your master password to use your private keys.',
    ),
    WrongMasterPassword() => const ErrorMessage(
      'That master password did not match.',
    ),
    KeyringCorrupt() => const ErrorMessage(
      'Your stored keyring could not be read.',
      'It may have been edited or partly written. Restore a backup, or clear local data to start over.',
    ),
    InputTooLarge(:final limitBytes) => ErrorMessage(
      'That is bigger than this build can handle.',
      'The limit here is ${formatBytes(limitBytes)}. The desktop app has no limit.',
    ),
    NoRecipients() => const ErrorMessage('Add at least one recipient first.'),
    RecipientFormatMismatch() => const ErrorMessage(
      'Those recipients do not match the chosen format.',
      'age encrypts to age recipients, PGP encrypts to PGP public keys.',
    ),
    FileAccessFailed() => const ErrorMessage(
      'That file could not be read or written.',
    ),
    CryptoFailed() => const ErrorMessage(_unexpected),
  };
}

const _unexpected = 'Something went wrong and nothing was changed.';
