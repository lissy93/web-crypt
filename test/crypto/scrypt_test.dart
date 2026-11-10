import 'dart:async';
import 'dart:convert';

import 'package:dage/src/scrypt.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// the test vectors from RFC 7914, bar the last one which needs a gigabyte
void main() {
  test('empty password and salt', () async {
    final key = await scrypt([], [], n: 16, r: 1, length: 64);
    expect(
      hex(key),
      '77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442'
      'fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906',
    );
  });

  test('several blocks in parallel', () async {
    final key = await scrypt(
      utf8.encode('password'),
      utf8.encode('NaCl'),
      n: 1024,
      p: 16,
      length: 64,
    );
    expect(
      hex(key),
      'fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162'
      '2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640',
    );
  });

  test('the shape age uses', () async {
    final key = await scrypt(
      utf8.encode('pleaseletmein'),
      utf8.encode('SodiumChloride'),
      n: 16384,
      length: 64,
    );
    expect(
      hex(key),
      '7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2'
      'd5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887',
    );
  });

  // on the web this is what keeps the page painting
  test('lets timers run while it works', () async {
    var ticks = 0;
    final timer = Timer.periodic(Duration.zero, (_) => ticks++);
    await scrypt([1], [2], n: 1 << 16);
    timer.cancel();
    expect(ticks, greaterThan(0));
  });

  test('refuses a cost that is not a power of two', () {
    expect(scrypt([], [], n: 1000), throwsArgumentError);
  });
}
