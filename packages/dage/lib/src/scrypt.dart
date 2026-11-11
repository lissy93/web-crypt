import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'pacer.dart';
import 'salsa_words.dart' if (dart.library.js_interop) 'salsa_words_web.dart';

/// scrypt from RFC 7914, quick enough for the web and pausing as it goes
Future<Uint8List> scrypt(
  List<int> password,
  List<int> salt, {
  required int n,
  int r = 8,
  int p = 1,
  int length = 32,
}) async {
  if (n < 2 || (n & (n - 1)) != 0) throw ArgumentError.value(n, 'n');
  final bytes = _pbkdf2(password, salt, 128 * r * p);
  final data = ByteData.sublistView(bytes);
  final words = Uint32List(bytes.length ~/ 4);
  for (var i = 0; i < words.length; i++) {
    words[i] = data.getUint32(i * 4, Endian.little);
  }
  final mixer = _Mixer(n, r);
  final size = 32 * r;
  for (var i = 0; i < p; i++) {
    await mixer.mix(Uint32List.sublistView(words, i * size, (i + 1) * size));
  }
  for (var i = 0; i < words.length; i++) {
    data.setUint32(i * 4, words[i], Endian.little);
  }
  return _pbkdf2(password, bytes, length);
}

Uint8List _pbkdf2(List<int> password, List<int> salt, int length) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), 1, length));
  return kdf.process(Uint8List.fromList(password));
}

/// ROMix, with its scratch space made once rather than per block
class _Mixer {
  _Mixer(this._n, int r)
      : _v = Uint32List(32 * r * _n),
        _x = Uint32List(32 * r),
        _y = Uint32List(32 * r);

  final int _n;
  final Uint32List _v;
  final Uint32List _x;
  final Uint32List _y;
  // which int list salsa runs fastest on depends on the platform
  final _t = SalsaWords(16);
  final _s = SalsaWords(16);
  final _pacer = Pacer();

  Future<void> mix(Uint32List block) async {
    final size = _x.length;
    _x.setAll(0, block);
    for (var i = 0; i < _n; i++) {
      _v.setRange(i * size, (i + 1) * size, _x);
      _blockMix();
      if (_pacer.due) await _pacer.rest();
    }
    for (var i = 0; i < _n; i++) {
      final j = (_x[size - 16] & (_n - 1)) * size;
      for (var k = 0; k < size; k++) {
        _x[k] ^= _v[j + k];
      }
      _blockMix();
      if (_pacer.due) await _pacer.rest();
    }
    block.setAll(0, _x);
  }

  void _blockMix() {
    final half = _x.length ~/ 2;
    _t.setRange(0, 16, _x, _x.length - 16);
    for (var i = 0; i < _x.length ~/ 16; i++) {
      for (var k = 0; k < 16; k++) {
        _t[k] ^= _x[i * 16 + k];
      }
      _salsa8();
      // even blocks go to the first half, odd ones to the second
      final at = (i.isEven ? 0 : half) + (i >> 1) * 16;
      _y.setRange(at, at + 16, _t);
    }
    _x.setAll(0, _y);
  }

  void _salsa8() {
    final s = _s..setAll(0, _t);
    for (var i = 0; i < 4; i++) {
      _quarter(s, 0, 4, 8, 12);
      _quarter(s, 5, 9, 13, 1);
      _quarter(s, 10, 14, 2, 6);
      _quarter(s, 15, 3, 7, 11);
      _quarter(s, 0, 1, 2, 3);
      _quarter(s, 5, 6, 7, 4);
      _quarter(s, 10, 11, 8, 9);
      _quarter(s, 15, 12, 13, 14);
    }
    for (var k = 0; k < 16; k++) {
      _t[k] += s[k];
    }
  }
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
void _quarter(SalsaWords s, int a, int b, int c, int d) {
  s[b] ^= _rotl(s[a] + s[d], 7);
  s[c] ^= _rotl(s[b] + s[a], 9);
  s[d] ^= _rotl(s[c] + s[b], 13);
  s[a] ^= _rotl(s[d] + s[c], 18);
}

@pragma('vm:prefer-inline')
@pragma('dart2js:tryInline')
int _rotl(int v, int n) => (v << n) | ((v & 0xffffffff) >>> (32 - n));
