/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'package:pinenacl/ed25519.dart';
import 'package:pointycastle/asn1.dart';

import '../../common/helpers.dart';
import '../../enum/hash_algorithm.dart';
import '../../type/verification_key_material.dart';
import 'ec_public_material.dart';

/// EdDSA legacy public key material
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
final class EdDSALegacyPublicMaterial extends ECPublicMaterial
    implements VerificationKeyMaterial {
  static const _halfLength = 32;

  EdDSALegacyPublicMaterial(super.oid, super.q);

  factory EdDSALegacyPublicMaterial.fromBytes(final Uint8List bytes) {
    final length = bytes[0];
    return EdDSALegacyPublicMaterial(
      ASN1ObjectIdentifier.fromBytes(
        Uint8List.fromList([0x06, length, ...bytes.sublist(1, 1 + length)]),
      ),
      Helper.readMPI(bytes.sublist(1 + length)),
    );
  }

  @override
  verify(
    final Uint8List message,
    final HashAlgorithm hash,
    final Uint8List signature,
  ) {
    // R and S are MPIs, which drop leading zeros, but Ed25519 wants 32 of each.
    var offset = 0;

    Uint8List readHalf() {
      final bitLength = signature.sublist(offset, offset + 2).unpack16();
      final byteLength = (bitLength + 7) >> 3;
      if (byteLength > _halfLength) {
        throw ArgumentError('EdDSA signature half is too long.');
      }
      final value = signature.sublist(offset + 2, offset + 2 + byteLength);
      offset += 2 + byteLength;
      return Uint8List(_halfLength)
        ..setRange(_halfLength - byteLength, _halfLength, value);
    }

    final r = readHalf();
    final s = readHalf();

    return VerifyKey(q.toUnsignedBytes().sublist(1)).verify(
      signature: Signature(Uint8List.fromList([...r, ...s])),
      message: Helper.hashDigest(message, hash),
    );
  }
}
