# vendored fork of dage

Modified copy of [dage 1.0.10](https://pub.dev/packages/dage), BSD-3-Clause,
copyright 2022 Producement OÜ. This is not the upstream release and is not
endorsed by its authors. The licence terms are unchanged and `LICENSE` is kept
as it shipped.

Cut from `github.com/Producement/dage` at tag `v1.0.10`, commit
`12c14fdfd21008e6a30020d1174e0edee3b419f3`. Upstream drift since then is a plain
diff against that commit.

Upstream stopped in February 2024 and does not compile for web. The
primitives still come from `cryptography` and `pointycastle`, except scrypt's
mixing step, which is our own and checked against RFC 7914.

## changed

- `src/encrypt.dart` reads one chunk ahead, so a payload that is an exact
  multiple of 64 KiB no longer ends with the empty final chunk the age spec
  forbids and the `age` CLI rejects
- `src/plugin/scrypt.dart` derives the scrypt key from UTF-8 rather than
  `codeUnits`, so a non-ASCII passphrase produces a file other age
  implementations can open
- `src/scrypt.dart` replaces pointycastle's scrypt, which ran in one go and
  froze the web page for seconds. this one is as quick or quicker, and pauses
  as it goes
- `src/plugin/scrypt.dart` caps the work factor at 20, where pointycastle
  stopped too. upstream allowed 22, which asks for 4 GiB
- `src/pacer.dart` gives the page a turn during scrypt and between payload
  chunks, so the web app keeps painting through a long job
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
