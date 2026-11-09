library age.src;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'keypair.dart';
import 'passphrase_provider.dart';
import 'encoding.dart';
import 'plugin/plugin.dart';

abstract class AgeStanza {
  const AgeStanza();

  static Future<AgeStanza> parse(String content,
      {PassphraseProvider passphraseProvider =
          const PassphraseProvider()}) async {
    final lines = content.split('\n');
    final arguments = lines[0].replaceFirst('-> ', '').split(' ');
    if (arguments.any((arg) => arg.isEmpty)) {
      throw Exception('Argument for stanza is empty!');
    }
    final body = lines.sublist(1).join('').replaceAll('\n', '');
    return AgePlugin.stanzaParse(
        arguments, base64RawDecode(body), passphraseProvider);
  }

  Future<String> serialize();

  Future<Uint8List> decryptedFileKey(AgeKeyPair? keyPair);

  static Future<Uint8List> wrap(
      List<int> symmetricFileKey, SecretKey derivedKey) async {
    final wrappingAlgorithm = Chacha20.poly1305Aead();
    final body = await wrappingAlgorithm.encrypt(symmetricFileKey,
        secretKey: derivedKey, nonce: List.generate(12, (index) => 0x00));
    return body.concatenation(nonce: false);
  }

  static Future<Uint8List> unwrap(
      List<int> wrappedKey, SecretKey derivedKey) async {
    final wrappingAlgorithm = Chacha20.poly1305Aead();
    final secretBox = SecretBox.fromConcatenation(
        List.generate(12, (index) => 0x00) + wrappedKey,
        macLength: 16,
        nonceLength: 12);
    try {
      return Uint8List.fromList(
          await wrappingAlgorithm.decrypt(secretBox, secretKey: derivedKey));
    } on SecretBoxAuthenticationError {
      // Distinct from a payload auth failure: this one means the passphrase or
      // identity was wrong, not that the file was tampered with.
      throw const StanzaUnwrapException();
    }
  }
}

class StanzaUnwrapException implements Exception {
  const StanzaUnwrapException();

  @override
  String toString() => 'Stanza file key could not be unwrapped';
}

class UnknownStanza extends AgeStanza {
  final List<String> _arguments;
  final List<int> _body;

  UnknownStanza(this._arguments, this._body);

  @override
  Future<Uint8List> decryptedFileKey(AgeKeyPair? keyPair) {
    throw Exception('Decryption not supported for this stanza!');
  }

  @override
  Future<String> serialize() async {
    return '-> ${_arguments.join(' ')}\n${_wrapped(base64Encode(_body))}';
  }

  String _wrapped(String str) {
    if (str.isEmpty) {
      return str;
    }
    if (str.length > 64) {
      return '${str.substring(0, 64)}\n${_wrapped(str.substring(64))}';
    }
    return '$str\n';
  }
}
