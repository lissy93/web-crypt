/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'dart:typed_data';
import 'package:pointycastle/api.dart';

/// Buffered cipher.
///
/// Every block goes through a pair of one block scratch buffers. That looks
/// like an extra copy, but PointyCastle's CFB mode calls `sublist(offset)` on
/// whatever buffers it is handed, once per block, so passing it the whole
/// payload made encryption quadratic: a megabyte took about twenty seconds
/// instead of sixty milliseconds. The scratch buffers keep that copy at one
/// block. Same output, same cipher, no crypto changed.
///
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
final class BufferedCipher {
  final BlockCipher _underlyingCipher;

  final Uint8List _buffer;
  final Uint8List _inBlock;
  final Uint8List _outBlock;

  int _bufOff = 0;

  BufferedCipher(this._underlyingCipher)
      : _buffer = Uint8List(_underlyingCipher.blockSize),
        _inBlock = Uint8List(_underlyingCipher.blockSize),
        _outBlock = Uint8List(_underlyingCipher.blockSize);

  BlockCipher get underlyingCipher => _underlyingCipher;

  String get algorithmName => _underlyingCipher.algorithmName;

  /// return the size of the output buffer required for an update
  /// an input of len bytes.
  int getUpdateOutputSize(int length) {
    final total = length + _bufOff;
    final leftOver = total % _buffer.length;
    return total - leftOver;
  }

  /// return the size of the output buffer required for an update plus a
  /// doFinal with an input of 'length' bytes.
  int getOutputSize(int length) {
    return length + _bufOff;
  }

  /// initialise the cipher.
  void init(final bool forEncryption, final CipherParameters? params) {
    reset();
    _underlyingCipher.init(forEncryption, params);
  }

  Uint8List process(Uint8List input) {
    final output = Uint8List(input.length);
    doFinal(output, processBytes(input, 0, input.length, output, 0));
    return output;
  }

  /// process an array of bytes, producing output if necessary.
  int processBytes(
    Uint8List input,
    int inOff,
    int length,
    Uint8List output,
    int outOff,
  ) {
    if (length < 1) {
      if (length < 0) {
        throw ArgumentError("Can't have a negative input length!");
      }
      return 0;
    }

    final blockSize = _underlyingCipher.blockSize;
    final outLength = getUpdateOutputSize(length);
    if (outLength > 0 && ((outOff + outLength) > output.length)) {
      throw ArgumentError('output buffer too short');
    }

    var resultLen = 0;
    final gapLen = _buffer.length - _bufOff;
    if (length > gapLen) {
      _buffer.setRange(_bufOff, _bufOff + gapLen, input, inOff);
      resultLen += _processOneBlock(_buffer, 0, output, outOff);

      _bufOff = 0;
      length -= gapLen;
      inOff += gapLen;

      while (length > _buffer.length) {
        resultLen += _processOneBlock(input, inOff, output, outOff + resultLen);
        length -= blockSize;
        inOff += blockSize;
      }
    }

    _buffer.setRange(_bufOff, _bufOff + length, input, inOff);
    _bufOff += length;

    if (_bufOff == _buffer.length) {
      resultLen += _processOneBlock(_buffer, 0, output, outOff + resultLen);
      _bufOff = 0;
    }

    return resultLen;
  }

  /// Process the last block in the buffer.
  int doFinal(Uint8List output, int outOff) {
    if (outOff + _bufOff > output.length) {
      throw ArgumentError('output buffer too short for doFinal()');
    }

    var resultLen = 0;
    if (_bufOff != 0) {
      _processOneBlock(_buffer, 0, _buffer, 0);
      resultLen = _bufOff;
      _bufOff = 0;
      output.setRange(outOff, outOff + resultLen, _buffer);
    }

    reset();
    return resultLen;
  }

  int _processOneBlock(
    Uint8List input,
    int inOff,
    Uint8List output,
    int outOff,
  ) {
    final size = _inBlock.length;
    _inBlock.setRange(0, size, input, inOff);
    final produced = _underlyingCipher.processBlock(_inBlock, 0, _outBlock, 0);
    output.setRange(outOff, outOff + size, _outBlock);
    return produced;
  }

  /// Reset the buffer and cipher. After resetting the object is in the same
  /// state as it was after the last init (if there was one).
  void reset() {
    _buffer.fillRange(0, _buffer.length, 0);
    _inBlock.fillRange(0, _inBlock.length, 0);
    _outBlock.fillRange(0, _outBlock.length, 0);

    _bufOff = 0;
    _underlyingCipher.reset();
  }
}
