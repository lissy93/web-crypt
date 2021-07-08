/// everything the crypto and service layers throw. the UI never sees anything
/// else, or the message of an underlying library exception
sealed class AppException implements Exception {
  const AppException();
}

class WrongPassphrase extends AppException {
  const WrongPassphrase();
}

class NoMatchingKey extends AppException {
  const NoMatchingKey();
}

class KeyLocked extends AppException {
  const KeyLocked();
}

class DataTampered extends AppException {
  const DataTampered();
}

class NotEncryptedData extends AppException {
  const NotEncryptedData();
}

class InvalidKeyMaterial extends AppException {
  const InvalidKeyMaterial();
}

class DuplicateKey extends AppException {
  const DuplicateKey();
}

class KeyCannotEncrypt extends AppException {
  const KeyCannotEncrypt();
}

class KeyringLocked extends AppException {
  const KeyringLocked();
}

class WrongMasterPassword extends AppException {
  const WrongMasterPassword();
}

class KeyringCorrupt extends AppException {
  const KeyringCorrupt();
}

class InputTooLarge extends AppException {
  const InputTooLarge(this.limitBytes);

  final int limitBytes;
}

class NoRecipients extends AppException {
  const NoRecipients();
}

class RecipientFormatMismatch extends AppException {
  const RecipientFormatMismatch();
}

class FileAccessFailed extends AppException {
  const FileAccessFailed();
}

/// anything unclassified, and carries no library text on purpose
class CryptoFailed extends AppException {
  const CryptoFailed();
}
