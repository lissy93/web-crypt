/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'dart:typed_data';

import '../common/extensions.dart';
import '../enum/packet_type.dart';
import '../type/packet.dart';

export '../enum/packet_type.dart';
export 'aead_encrypted_data.dart';
export 'compressed_data.dart';
export 'literal_data.dart';
export 'marker.dart';
export 'one_pass_signature.dart';
export 'packet_list.dart';
export 'packet_reader.dart';
export 'padding.dart';
export 'public_key.dart';
export 'public_key_encrypted_session_key.dart';
export 'public_subkey.dart';
export 'secret_key.dart';
export 'secret_subkey.dart';
export 'signature.dart';
export 'signature_subpacket.dart';
export 'sym_encrypted_data.dart';
export 'sym_encrypted_integrity_protected_data.dart';
export 'sym_encrypted_session_key.dart';
export 'trust.dart';
export 'user_attribute.dart';
export 'user_id.dart';

/// Base abstract packet class
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
abstract class BasePacket implements PacketInterface {
  static const partialMinSize = 512;
  static const partialMaxSize = 1024;

  @override
  final PacketType type;

  BasePacket(this.type);

  /// A definite length header, since the size is known up front.
  @override
  encode() {
    final body = data;
    final builder = BytesBuilder(copy: false)
      ..addByte(type.value | 0xc0)
      ..add(_simpleLength(body.length))
      ..add(body);
    return builder.takeBytes();
  }

  Uint8List _simpleLength(int length) {
    if (length < 192) {
      return Uint8List.fromList([length]);
    } else if (length < 8384) {
      return Uint8List.fromList(
        [(((length - 192) >> 8) & 0xff) + 192, length - 192],
      );
    } else {
      if (length > 0xffffffff) {
        throw ArgumentError('Packet body is too large for a definite length.');
      }
      return Uint8List.fromList([0xff, ...length.pack32()]);
    }
  }
}
