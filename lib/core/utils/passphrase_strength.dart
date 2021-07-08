import 'dart:math';

enum PassphraseLevel { weak, fair, good, strong }

class PassphraseScore {
  const PassphraseScore({
    required this.level,
    required this.bits,
    required this.label,
    required this.advice,
  });

  final PassphraseLevel level;
  final double bits;
  final String label;
  final String advice;
}

/// local entropy estimate: character classes, discounted for repeats and
/// runs. no wordlists, no network, no library
PassphraseScore scorePassphrase(String passphrase) {
  if (passphrase.isEmpty) {
    return const PassphraseScore(
      level: PassphraseLevel.weak,
      bits: 0,
      label: 'Empty',
      advice: 'Type something.',
    );
  }

  final bits = _entropyBits(passphrase);
  final level = switch (bits) {
    < 40 => PassphraseLevel.weak,
    < 60 => PassphraseLevel.fair,
    < 80 => PassphraseLevel.good,
    _ => PassphraseLevel.strong,
  };
  return PassphraseScore(
    level: level,
    bits: bits,
    label: switch (level) {
      PassphraseLevel.weak => 'Weak',
      PassphraseLevel.fair => 'Fair',
      PassphraseLevel.good => 'Good',
      PassphraseLevel.strong => 'Strong',
    },
    advice: switch (level) {
      PassphraseLevel.weak =>
        'Anyone with your file could guess this. Try four or more unrelated words.',
      PassphraseLevel.fair =>
        'Longer would be better. Try adding another word.',
      PassphraseLevel.good => 'Reasonable.',
      PassphraseLevel.strong => 'Hard to guess.',
    },
  );
}

double _entropyBits(String passphrase) {
  final codes = passphrase.codeUnits;
  var alphabet = 0;
  if (codes.any((c) => c >= 0x61 && c <= 0x7a)) alphabet += 26;
  if (codes.any((c) => c >= 0x41 && c <= 0x5a)) alphabet += 26;
  if (codes.any((c) => c >= 0x30 && c <= 0x39)) alphabet += 10;
  if (codes.any(
    (c) =>
        c < 0x30 ||
        (c > 0x39 && c < 0x41) ||
        (c > 0x5a && c < 0x61) ||
        (c > 0x7a && c < 0x80),
  )) {
    alphabet += 32;
  }
  if (codes.any((c) => c >= 0x80)) alphabet += 100;
  if (alphabet == 0) alphabet = 26;

  // repeated or sequential characters carry much less information
  var effective = 0.0;
  final seen = <int>{};
  for (var i = 0; i < codes.length; i++) {
    final code = codes[i];
    final repeated = i > 0 && codes[i - 1] == code;
    final sequential = i > 0 && (code - codes[i - 1]).abs() == 1;
    if (repeated || sequential) {
      effective += 0.25;
    } else if (!seen.add(code)) {
      effective += 0.6;
    } else {
      effective += 1;
    }
  }

  final distinct = seen.length;
  // a long string of two characters is not a long passphrase
  final variety = min(1.0, distinct / 8);
  return effective * (log(alphabet) / ln2) * (0.55 + 0.45 * variety);
}
