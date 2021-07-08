library age.src;

/// Supplies the passphrase for scrypt stanzas.
///
/// Supplied by the caller: there is no tty to read from on web.
class PassphraseProvider {
  const PassphraseProvider();

  Future<String> passphrase() async {
    throw StateError('No passphrase provider was supplied');
  }
}

class StaticPassphraseProvider extends PassphraseProvider {
  final String value;

  const StaticPassphraseProvider(this.value);

  @override
  Future<String> passphrase() async => value;
}
