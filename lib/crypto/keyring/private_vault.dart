import 'dart:convert';
import 'dart:typed_data';

import 'package:web_crypt/core/errors/app_exception.dart';

/// key id to private key material
///
/// sealed, this is a plain age file in passphrase mode under the master
/// password, so `age -d` opens it too. bump [_version] only alongside a
/// reader that still understands the old shape
class PrivateVault {
  const PrivateVault(this.materials);

  static const _version = 1;
  static const empty = PrivateVault({});

  final Map<String, String> materials;

  PrivateVault withKey(String id, String material) =>
      PrivateVault({...materials, id: material});

  PrivateVault without(String id) => PrivateVault({...materials}..remove(id));

  String? operator [](String id) => materials[id];

  bool get isEmpty => materials.isEmpty;

  Uint8List toBytes() =>
      utf8.encode(jsonEncode({'version': _version, 'keys': materials}));

  static PrivateVault fromBytes(List<int> plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, Object?>) throw const KeyringCorrupt();
      final version = decoded['version'];
      if (version is! int || version > _version) throw const KeyringCorrupt();
      final keys = decoded['keys'];
      if (keys is! Map) throw const KeyringCorrupt();
      return PrivateVault({
        for (final entry in keys.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      });
    } on AppException {
      rethrow;
    } on Object {
      throw const KeyringCorrupt();
    }
  }
}
