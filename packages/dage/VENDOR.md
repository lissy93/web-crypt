# vendored fork of dage

Modified copy of [dage 1.0.10](https://pub.dev/packages/dage), BSD-3-Clause,
copyright 2022 Producement OÜ. This is not the upstream release and is not
endorsed by its authors. The licence terms are unchanged and `LICENSE` is kept
as it shipped.

Cut from `github.com/Producement/dage` at tag `v1.0.10`, commit
`12c14fdfd21008e6a30020d1174e0edee3b419f3`. Upstream drift since then is a plain
diff against that commit.

Upstream stopped in February 2024 and does not compile for web. No
cryptographic primitive is modified: those still come from `cryptography` and
`pointycastle`.

## changed

- `src/encrypt.dart` reads one chunk ahead, so a payload that is an exact
  multiple of 64 KiB no longer ends with the empty final chunk the age spec
  forbids and the `age` CLI rejects
- `src/plugin/scrypt.dart` derives the scrypt key from UTF-8 rather than
  `codeUnits`, so a non-ASCII passphrase produces a file other age
  implementations can open
- `src/stanza.dart` adds `StanzaUnwrapException`, which separates a wrong
  passphrase from a tampered payload
- `src/passphrase_provider.dart` takes the passphrase from the caller instead
  of stdin or `/dev/tty`, dropping `dart:io`
- `src/armor.dart` drops an unused `isArmored(File)` helper and a stray print
- `src/stream.dart` closes the header at the MAC line and passes pause and
  resume through to the source, rather than buffering the whole payload
- the barrel exports `X25519AgePlugin`, `ScryptPlugin` and the stanza types
- `pointycastle` and `petitparser` constraints raised to match the app
- `bin/` and the upstream `README.md`, `CHANGELOG.md`, `dart_test.yaml` and
  `pubspec.lock` removed
- `testkit/` is untouched, being the official C2SP CCTV age vectors
