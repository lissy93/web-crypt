/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../common/config.dart';
import '../enum/compression_algorithm.dart';
import '../type/packet_list.dart';
import 'base_packet.dart';

/// Implementation of the Compressed Data (COMP) Packet - Type 11
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
final class CompressedDataPacket extends BasePacket {
  /// Default zip/zlib compression level, between 1 and 9
  static const deflateLevel = 6;

  static var _unpacking = false;

  final CompressionAlgorithm algorithm;

  /// Compressed packet data
  final Uint8List compressed;

  /// Decompressed packets contained within.
  final PacketListInterface packets;

  CompressedDataPacket(
    this.compressed,
    this.packets, {
    this.algorithm = CompressionAlgorithm.uncompressed,
  }) : super(PacketType.compressedData);

  factory CompressedDataPacket.fromBytes(final Uint8List bytes) {
    // only one layer is ever unwrapped, so a nested one can only be a bomb
    if (_unpacking) {
      throw UnsupportedError('Nested compressed data is unsupported.');
    }
    final algorithm = CompressionAlgorithm.values.firstWhere(
      (algo) => algo.value == bytes[0],
      orElse: () => CompressionAlgorithm.uncompressed,
    );
    final compressed = bytes.sublist(1);
    _unpacking = true;
    try {
      return CompressedDataPacket(
        compressed,
        _decompress(compressed, algorithm),
        algorithm: algorithm,
      );
    } finally {
      _unpacking = false;
    }
  }

  factory CompressedDataPacket.fromPacketList(
    final PacketListInterface packets, [
    final CompressionAlgorithm algorithm = CompressionAlgorithm.uncompressed,
  ]) =>
      CompressedDataPacket(
        _compress(packets, algorithm),
        packets,
        algorithm: algorithm,
      );

  @override
  get data => Uint8List.fromList([
        algorithm.value,
        ...compressed,
      ]);

  static Uint8List _compress(
    final PacketListInterface packets,
    final CompressionAlgorithm algorithm,
  ) =>
      switch (algorithm) {
        CompressionAlgorithm.zip => Deflate(
            packets.encode(),
            level: deflateLevel,
          ).getBytes(),
        CompressionAlgorithm.zlib => const ZLibEncoder().encodeBytes(
            packets.encode(),
            level: deflateLevel,
          ),
        CompressionAlgorithm.bzip2 => throw UnsupportedError(
            'Compression algorithm ${algorithm.name} is unsupported.',
          ),
        _ => packets.encode(),
      };

  static PacketList _decompress(
    final Uint8List compressed,
    final CompressionAlgorithm algorithm,
  ) =>
      switch (algorithm) {
        CompressionAlgorithm.zip => _inflate(compressed),
        // zlib is the same deflate behind a two byte header
        CompressionAlgorithm.zlib => _inflate(
            Uint8List.sublistView(compressed, 2),
          ),
        CompressionAlgorithm.bzip2 => throw UnsupportedError(
            'Compression algorithm ${algorithm.name} is unsupported.',
          ),
        _ => PacketList.decode(compressed),
      };

  static PacketList _inflate(final Uint8List deflated) {
    final output = _CappedOutput();
    Inflate(deflated, output: output);
    return PacketList.decode(output.getBytes());
  }
}

/// holds unpacked bytes, but never grows past [Config.maxDecompressedSize]
final class _CappedOutput extends OutputStream {
  _CappedOutput() : super(byteOrder: ByteOrder.littleEndian);

  var _buffer = Uint8List(0);

  @override
  var length = 0;

  @override
  void writeByte(final int value) {
    _reserve(1);
    _buffer[length++] = value;
  }

  @override
  void writeBytes(final List<int> bytes, {final int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _buffer.setRange(this.length, this.length + count, bytes);
    this.length += count;
  }

  @override
  void writeStream(final InputStream stream) =>
      writeBytes(stream.toUint8List());

  /// negative indexes count back from the end, as archive expects
  @override
  Uint8List subset(final int start, [final int? end]) => Uint8List.sublistView(
        _buffer,
        start < 0 ? length + start : start,
        end == null ? length : (end < 0 ? length + end : end),
      );

  @override
  void clear() => length = 0;

  @override
  void flush() {}

  void _reserve(final int count) {
    final needed = length + count;
    final limit = Config.maxDecompressedSize;
    if (needed > limit) {
      throw UnsupportedError('Compressed data unpacks too large.');
    }
    if (needed <= _buffer.length) return;
    _buffer = Uint8List(min(max(needed, _buffer.length * 2), limit))
      ..setRange(0, length, _buffer);
  }
}
