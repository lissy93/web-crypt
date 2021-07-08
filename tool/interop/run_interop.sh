#!/usr/bin/env bash
# round trips every format and mode against the reference tools, and a
# failure here is a failed build
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
export GNUPGHOME="$WORK/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

PASS='correct horse battery staple ✨'
KEYPASS='key-protect-me'
PASSES=0
FAILS=0

cleanup() {
  gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

HARNESS="$WORK/harness"
printf 'building harness...\n'
dart compile exe "$ROOT/tool/interop/harness.dart" -o "$HARNESS" >/dev/null || {
  printf 'harness failed to build\n'
  exit 1
}

harness() { "$HARNESS" "$@"; }
gpgb() { gpg --batch --yes --pinentry-mode loopback --trust-model always "$@"; }
# age only reads a passphrase from a terminal, so give it one
onpty() { script -qec "$1" /dev/null; }

ok() {
  PASSES=$((PASSES + 1))
  printf '  \033[32mPASS\033[0m  %s\n' "$1"
}

fail() {
  FAILS=$((FAILS + 1))
  printf '  \033[31mFAIL\033[0m  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$(echo "$2" | head -3)"
  return 0
}

# clears the target first, so a failed encrypt cannot be scored against a
# leftover file
encrypt_to() {
  local target="$1"
  shift
  rm -f "$target"
  if ! harness encrypt --out "$target" "$@" >/dev/null 2>"$WORK/encerr"; then
    return 1
  fi
  [ -s "$target" ]
}

check() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected '$3', got '$2'"; fi
}

same() {
  local label="$1" a="$2" b="$3"
  if [ ! -f "$b" ]; then
    fail "$label" "no output produced"
    return
  fi
  if [ "$(sha256sum <"$a" | cut -d' ' -f1)" = "$(sha256sum <"$b" | cut -d' ' -f1)" ]; then
    ok "$label"
  else
    fail "$label" "checksum mismatch"
  fi
}

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

printf 'hello from web-crypt, with unicode: αβγ 🔐\n' >"$WORK/text.txt"
head -c 65536 /dev/urandom >"$WORK/small.bin"
head -c 10485760 /dev/urandom >"$WORK/large.bin"
FIXTURES="text.txt small.bin large.bin"

section "toolchain"
printf '  %s\n  %s\n' "age $(age --version)" "$(gpg --version | head -1)"

section "age keys"
harness gen-age-key --out "$WORK/id.txt" >"$WORK/agekey.json"
AGE_RECIPIENT=$(python3 -c "import json;print(json.load(open('$WORK/agekey.json'))['recipient'])")
if [ -z "$AGE_RECIPIENT" ]; then fail "the age key has a recipient" "empty"; fi
check "age-keygen -y agrees with the generated recipient" \
  "$(age-keygen -y "$WORK/id.txt" 2>/dev/null)" "$AGE_RECIPIENT"

age-keygen -o "$WORK/cli-id.txt" 2>/dev/null
CLI_RECIPIENT=$(age-keygen -y "$WORK/cli-id.txt")
if harness decrypt --in /dev/null --out /dev/null --age-identity "@$WORK/cli-id.txt" >/dev/null 2>&1; then
  fail "empty input is refused"
else
  ok "empty input is refused"
fi

section "age: web-crypt encrypts, age CLI decrypts"
for fixture in $FIXTURES; do
  for armor in "" "--armor"; do
    suffix=${armor:+ armored}
    rm -f "$WORK/back"
    if ! encrypt_to "$WORK/out.age" --format age --mode rcpt \
      --recipient "$CLI_RECIPIENT" --in "$WORK/$fixture" $armor; then
      fail "recipient mode, $fixture$suffix" "$(cat "$WORK/encerr")"
    elif age -d -i "$WORK/cli-id.txt" -o "$WORK/back" "$WORK/out.age" 2>"$WORK/err"; then
      same "recipient mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "recipient mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi

    rm -f "$WORK/back"
    if ! encrypt_to "$WORK/out.age" --format age --mode pass --pass "$PASS" \
      --in "$WORK/$fixture" $armor; then
      fail "passphrase mode, $fixture$suffix" "$(cat "$WORK/encerr")"
    elif printf '%s\n' "$PASS" |
      onpty "age -d -o '$WORK/back' '$WORK/out.age'" >"$WORK/err" 2>&1; then
      same "passphrase mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "passphrase mode, $fixture$suffix" "$(grep -a error "$WORK/err")"
    fi
  done
done

section "age: age CLI encrypts, web-crypt decrypts"
for fixture in $FIXTURES; do
  for armor in "" "-a"; do
    suffix=${armor:+ armored}
    age -r "$AGE_RECIPIENT" $armor -o "$WORK/cli.age" "$WORK/$fixture"
    rm -f "$WORK/back"
    if harness decrypt --in "$WORK/cli.age" --out "$WORK/back" \
      --age-identity "@$WORK/id.txt" >/dev/null 2>"$WORK/err"; then
      same "recipient mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "recipient mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi

    printf '%s\n%s\n' "$PASS" "$PASS" |
      onpty "age -p $armor -o '$WORK/cli.age' '$WORK/$fixture'" >/dev/null 2>&1
    rm -f "$WORK/back"
    if harness decrypt --in "$WORK/cli.age" --out "$WORK/back" \
      --pass "$PASS" >/dev/null 2>"$WORK/err"; then
      same "passphrase mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "passphrase mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi
  done
done

section "PGP keys"
harness gen-pgp-key --name "Interop Tester" --email "interop@example.com" \
  --public-out "$WORK/pgp-pub.asc" --private-out "$WORK/pgp-priv.asc" >/dev/null
if gpgb --import "$WORK/pgp-priv.asc" 2>"$WORK/err"; then
  ok "gpg --import accepts a web-crypt private key"
else
  fail "gpg --import accepts a web-crypt private key" "$(cat "$WORK/err")"
fi

harness gen-pgp-key --name "Protected Tester" --email "protected@example.com" \
  --passphrase "$KEYPASS" --expiry-days 30 \
  --public-out "$WORK/pgp-prot-pub.asc" --private-out "$WORK/pgp-prot-priv.asc" >/dev/null
if gpgb --import "$WORK/pgp-prot-pub.asc" 2>"$WORK/err"; then
  ok "gpg --import accepts a protected key's public half"
else
  fail "gpg --import accepts a protected key's public half" "$(cat "$WORK/err")"
fi

# gpg only gives a quick-generated key an encryption subkey if asked, and the
# agent can be slow to come up on a cold homedir
gpg_key() {
  local uid="$1" primary="$2" sub="$3" out="$4" attempt fpr
  gpg-connect-agent /bye >/dev/null 2>&1 || true
  for attempt in 1 2 3; do
    gpgb --passphrase '' --quick-generate-key "$uid" "$primary" cert never \
      >/dev/null 2>"$WORK/err" || {
      sleep 1
      continue
    }
    fpr=$(gpg --batch --with-colons --list-keys "$uid" 2>/dev/null |
      awk -F: '/^fpr/{print $10; exit}')
    [ -n "$fpr" ] || {
      sleep 1
      continue
    }
    gpgb --passphrase '' --quick-add-key "$fpr" "$sub" encr never \
      >/dev/null 2>"$WORK/err" || {
      sleep 1
      continue
    }
    gpgb --armor --export "$uid" >"$out" 2>/dev/null
    [ -s "$out" ] && return 0
    sleep 1
  done
  fail "gpg generates $primary + $sub for $uid" "$(cat "$WORK/err")"
  return 1
}

gpg_key "GnuPG Tester <gnupg@example.com>" ed25519 cv25519 "$WORK/gpg-pub.asc" &&
  ok "gpg generates an ed25519 key with a cv25519 subkey"
gpg_key "GnuPG RSA <rsa@example.com>" rsa3072 rsa3072 "$WORK/gpg-rsa-pub.asc" &&
  ok "gpg generates an RSA key with an RSA subkey"

if [ ! -s "$WORK/gpg-pub.asc" ]; then
  printf '\ngpg could not produce a usable key, so the PGP checks below would\n'
  printf 'all fail for that reason alone. Stopping here.\n'
  printf '\n\033[31m%d passed, %d failed\033[0m\n' "$PASSES" "$FAILS"
  exit 1
fi

section "PGP: web-crypt encrypts, gpg decrypts"
for fixture in $FIXTURES; do
  for armor in "" "--armor"; do
    suffix=${armor:+ armored}
    rm -f "$WORK/back"
    if ! encrypt_to "$WORK/out.gpg" --format pgp --mode rcpt \
      --recipient "@$WORK/gpg-pub.asc" --in "$WORK/$fixture" $armor; then
      fail "recipient mode, $fixture$suffix" "$(cat "$WORK/encerr")"
    elif gpgb -d -o "$WORK/back" "$WORK/out.gpg" 2>"$WORK/err"; then
      same "recipient mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "recipient mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi

    rm -f "$WORK/back"
    if ! encrypt_to "$WORK/out.gpg" --format pgp --mode pass --pass "$PASS" \
      --in "$WORK/$fixture" $armor; then
      fail "passphrase mode, $fixture$suffix" "$(cat "$WORK/encerr")"
    elif gpgb --passphrase "$PASS" -d -o "$WORK/back" "$WORK/out.gpg" 2>"$WORK/err"; then
      same "passphrase mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "passphrase mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi
  done
done

section "PGP: encrypting to a web-crypt key"
# every check above encrypts to a gpg-made key, this one uses a web-crypt key,
# which advertises different features and picks its own cipher
gpgb --import "$WORK/pgp-priv.asc" >/dev/null 2>&1
harness encrypt --format pgp --mode rcpt --recipient "@$WORK/pgp-pub.asc" \
  --in "$WORK/text.txt" --out "$WORK/own.gpg" >/dev/null
rm -f "$WORK/back"
if gpgb -v -d -o "$WORK/back" "$WORK/own.gpg" 2>"$WORK/err"; then
  same "gpg opens a message encrypted to a web-crypt key" "$WORK/text.txt" "$WORK/back"
else
  fail "gpg opens a message encrypted to a web-crypt key" "$(cat "$WORK/err")"
fi
if grep -q 'AES256' "$WORK/err"; then
  ok "the session cipher is AES-256"
else
  fail "the session cipher is AES-256" "$(grep -i 'encrypted data' "$WORK/err")"
fi

section "PGP: gpg encrypts, web-crypt decrypts"
for fixture in $FIXTURES; do
  for armor in "" "-a"; do
    suffix=${armor:+ armored}
    gpgb -e $armor -r "interop@example.com" -o "$WORK/cli.gpg" "$WORK/$fixture"
    rm -f "$WORK/back"
    if harness decrypt --in "$WORK/cli.gpg" --out "$WORK/back" \
      --pgp-identity "@$WORK/pgp-priv.asc" >/dev/null 2>"$WORK/err"; then
      same "recipient mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "recipient mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi

    gpgb --passphrase "$PASS" -c $armor -o "$WORK/cli.gpg" "$WORK/$fixture"
    rm -f "$WORK/back"
    if harness decrypt --in "$WORK/cli.gpg" --out "$WORK/back" \
      --pass "$PASS" >/dev/null 2>"$WORK/err"; then
      same "passphrase mode, $fixture$suffix" "$WORK/$fixture" "$WORK/back"
    else
      fail "passphrase mode, $fixture$suffix" "$(cat "$WORK/err")"
    fi
  done
done

section "PGP: protected key"
gpgb -e -a -r "protected@example.com" -o "$WORK/prot.asc" "$WORK/text.txt"
rm -f "$WORK/back"
if harness decrypt --in "$WORK/prot.asc" --out "$WORK/back" \
  --pgp-identity "@$WORK/pgp-prot-priv.asc" --key-pass "$KEYPASS" \
  >/dev/null 2>"$WORK/err"; then
  same "gpg encrypts to it, web-crypt opens it" "$WORK/text.txt" "$WORK/back"
else
  fail "gpg encrypts to it, web-crypt opens it" "$(cat "$WORK/err")"
fi

rm -f "$WORK/back"
if harness decrypt --in "$WORK/prot.asc" --out "$WORK/back" \
  --pgp-identity "@$WORK/pgp-prot-priv.asc" --key-pass "wrong" >/dev/null 2>&1; then
  fail "wrong key passphrase is refused"
else
  ok "wrong key passphrase is refused"
fi

section "PGP: other key shapes"
harness encrypt --format pgp --mode rcpt --armor --recipient "@$WORK/gpg-rsa-pub.asc" \
  --in "$WORK/text.txt" --out "$WORK/rsa.asc" >/dev/null 2>"$WORK/err"
rm -f "$WORK/back"
gpgb -d -o "$WORK/back" "$WORK/rsa.asc" 2>/dev/null
same "gpg decrypts what web-crypt encrypts to an RSA key" "$WORK/text.txt" "$WORK/back"

gpgb --passphrase '' --quick-generate-key "Sign Only <signonly@example.com>" \
  ed25519 cert never >/dev/null 2>&1
gpgb --armor --export "signonly@example.com" >"$WORK/signonly.asc"
if harness encrypt --format pgp --mode rcpt --recipient "@$WORK/signonly.asc" \
  --in "$WORK/text.txt" --out "$WORK/nope.gpg" >/dev/null 2>&1; then
  fail "a key with no encryption subkey is refused"
else
  ok "a key with no encryption subkey is refused"
fi

section "multiple recipients"
harness encrypt --format age --mode rcpt \
  --recipient "$CLI_RECIPIENT" --recipient "$AGE_RECIPIENT" \
  --in "$WORK/text.txt" --out "$WORK/multi.age" >/dev/null
rm -f "$WORK/back"
age -d -i "$WORK/cli-id.txt" -o "$WORK/back" "$WORK/multi.age" 2>/dev/null
same "age, the CLI's recipient opens it" "$WORK/text.txt" "$WORK/back"
rm -f "$WORK/back"
harness decrypt --in "$WORK/multi.age" --out "$WORK/back" \
  --age-identity "@$WORK/id.txt" >/dev/null 2>&1
same "age, the web-crypt recipient opens it" "$WORK/text.txt" "$WORK/back"

harness encrypt --format pgp --mode rcpt --armor \
  --recipient "@$WORK/gpg-pub.asc" --recipient "@$WORK/pgp-pub.asc" \
  --in "$WORK/text.txt" --out "$WORK/multi.gpg" >/dev/null
rm -f "$WORK/back"
gpgb -d -o "$WORK/back" "$WORK/multi.gpg" 2>/dev/null
same "PGP, gpg's recipient opens it" "$WORK/text.txt" "$WORK/back"
rm -f "$WORK/back"
harness decrypt --in "$WORK/multi.gpg" --out "$WORK/back" \
  --pgp-identity "@$WORK/pgp-priv.asc" >/dev/null 2>&1
same "PGP, the web-crypt recipient opens it" "$WORK/text.txt" "$WORK/back"

section "failure paths"
harness encrypt --format age --mode pass --pass "$PASS" \
  --in "$WORK/text.txt" --out "$WORK/pass.age" >/dev/null
if harness decrypt --in "$WORK/pass.age" --out "$WORK/back" \
  --pass "not the passphrase" >/dev/null 2>&1; then
  fail "age wrong passphrase is refused"
else
  ok "age wrong passphrase is refused"
fi

age -r "$AGE_RECIPIENT" -o "$WORK/rcpt.age" "$WORK/text.txt"
if harness decrypt --in "$WORK/rcpt.age" --out "$WORK/back" \
  --age-identity "@$WORK/cli-id.txt" >/dev/null 2>&1; then
  fail "age wrong identity is refused"
else
  ok "age wrong identity is refused"
fi

gpgb --passphrase "$PASS" -c -a -o "$WORK/pass.gpg" "$WORK/text.txt"
if harness decrypt --in "$WORK/pass.gpg" --out "$WORK/back" \
  --pass "not the passphrase" >/dev/null 2>&1; then
  fail "PGP wrong passphrase is refused"
else
  ok "PGP wrong passphrase is refused"
fi

for target in pass.age pass.gpg; do
  cp "$WORK/$target" "$WORK/tampered"
  python3 - "$WORK/tampered" <<'PY'
import sys
path = sys.argv[1]
data = bytearray(open(path, 'rb').read())
for i in range(1, min(40, len(data)) + 1):
    data[-i] ^= 0x5a
open(path, 'wb').write(data)
PY
  if harness decrypt --in "$WORK/tampered" --out "$WORK/back" \
    --pass "$PASS" >/dev/null 2>&1; then
    fail "tampered $target is refused"
  else
    ok "tampered $target is refused"
  fi
done

section "detection"
head -c 4096 /dev/urandom >"$WORK/garbage.bin"
printf 'just some words\n' >"$WORK/plain.txt"
check "random bytes" "$(harness detect --in "$WORK/garbage.bin")" "unknown"
check "plain text" "$(harness detect --in "$WORK/plain.txt")" "unknown"
check "age binary" "$(harness detect --in "$WORK/pass.age")" "ageBinary"
check "PGP armored message" "$(harness detect --in "$WORK/prot.asc")" "pgpArmoredMessage"
check "PGP public key" "$(harness detect --in "$WORK/gpg-pub.asc")" "pgpPublicKey"
check "PGP private key" "$(harness detect --in "$WORK/pgp-priv.asc")" "pgpPrivateKey"
check "age identity file" "$(harness detect --in "$WORK/id.txt")" "unknown"
printf '%s' "$AGE_RECIPIENT" >"$WORK/rcpt.txt"
check "age recipient" "$(harness detect --in "$WORK/rcpt.txt")" "ageRecipient"
harness encrypt --format age --mode pass --pass "$PASS" --armor \
  --in "$WORK/text.txt" --out "$WORK/armored.age" >/dev/null
check "age armored" "$(harness detect --in "$WORK/armored.age")" "ageArmored"
gpgb --passphrase "$PASS" -c -o "$WORK/binary.gpg" "$WORK/text.txt"
check "PGP binary" "$(harness detect --in "$WORK/binary.gpg")" "pgpBinary"

section "metadata"
harness encrypt --format pgp --mode pass --pass "$PASS" --filename "report.pdf" \
  --in "$WORK/text.txt" --out "$WORK/named.gpg" >/dev/null
NAME=$(harness decrypt --in "$WORK/named.gpg" --out "$WORK/back" --pass "$PASS" |
  python3 -c "import json,sys;print(json.load(sys.stdin)['filename'])")
check "PGP literal filename survives" "$NAME" "report.pdf"

printf '\n'
if [ "$FAILS" -eq 0 ]; then
  printf '\033[32m%d passed, 0 failed\033[0m\n' "$PASSES"
  exit 0
fi
printf '\033[31m%d passed, %d failed\033[0m\n' "$PASSES" "$FAILS"
exit 1
