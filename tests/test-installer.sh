#!/bin/bash
# Behaviour tests for install.sh. Runs on macOS and Linux (CI runs it on both).
#
#   scripts/test-installer.sh            offline tests with fake archives
#   scripts/test-installer.sh --live     also install the real published bundle
#
# Everything happens under a throwaway HOME; nothing touches the real one.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${INSTALL_SH:-$HERE/install.sh}"
LIVE=false
[ "${1:-}" = "--live" ] && LIVE=true

case "$(uname -s):$(uname -m)" in
  Darwin:arm64)         TARGET=aarch64-apple-darwin ;;
  Linux:x86_64)         TARGET=x86_64-unknown-linux-gnu ;;
  Linux:aarch64|Linux:arm64) TARGET=aarch64-unknown-linux-gnu ;;
  *) echo "unsupported test host $(uname -sm)"; exit 2 ;;
esac

S="$(mktemp -d "${TMPDIR:-/tmp}/anv-installer-test.XXXXXX")"
trap 'rm -rf "$S"' EXIT
export HOME="$S/home" SHELL=/bin/zsh
mkdir -p "$HOME"
BIN="$HOME/.local/bin"
VERS="$HOME/.anvaya/versions"

pass=0; fails=0
ok()  { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
run() { sh "$INSTALL" "$@" 2>&1; }

# A fake bundle whose binaries print a version, so no network is needed.
make_bundle() {  # make_bundle <version> <exit-code-of-binaries> -> sets CH to a channel file
  v="$1"; code="$2"; d="$S/b-$v"
  rm -rf "$d"; mkdir -p "$d/anvaya-$v/bin"
  for n in anv mind-daemon; do
    printf '#!/bin/sh\necho "%s %s"\nexit %s\n' "$n" "$v" "$code" > "$d/anvaya-$v/bin/$n"
    chmod +x "$d/anvaya-$v/bin/$n"
  done
  printf '{"bundle_version":"%s"}\n' "$v" > "$d/anvaya-$v/bundle.json"
  tar -czf "$d/bundle.tar.gz" -C "$d" "anvaya-$v"
  if command -v shasum >/dev/null 2>&1; then sha="$(shasum -a 256 "$d/bundle.tar.gz" | awk '{print $1}')"
  else sha="$(sha256sum "$d/bundle.tar.gz" | awk '{print $1}')"; fi
  printf 'bundle\t%s\t%s\t%s\t1\t%s\n' "$TARGET" "$v" "$sha" "$d/bundle.tar.gz" > "$d/channel.tsv"
  CH="$d/channel.tsv"
}

# 1. fresh install
make_bundle 1.0.0 0
ANV_CHANNEL_FILE="$CH" run >/dev/null
[ -L "$BIN/anv" ] && [ -L "$BIN/mind-daemon" ] && ok "fresh install links anv and mind-daemon" || bad "fresh install"
[ "$("$BIN/anv" --version)" = "anv 1.0.0" ] && ok "anv runs through the symlink" || bad "anv through symlink"
[ "$(dirname "$(readlink "$BIN/anv")")" = "$(dirname "$(readlink "$BIN/mind-daemon")")" ] \
  && ok "both links resolve into one versions/<v> directory" || bad "link directories differ"
grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$HOME/.zshrc" && ok "PATH block written with \$HOME" || bad "PATH block"

# 2. reinstall is idempotent
ANV_CHANNEL_FILE="$CH" run >/dev/null
[ "$(grep -c '>>> anvaya >>>' "$HOME/.zshrc")" = 1 ] && ok "reinstall keeps a single PATH block" || bad "PATH block duplicated"
[ "$(ls "$VERS" | wc -l | tr -d ' ')" = 1 ] && ok "reinstall leaves no stray directories" || bad "stray directories"

# 3. legacy ~/.anvaya/bin real files are converted, never left to shadow
rm -rf "$HOME/.anvaya" "$BIN"; mkdir -p "$HOME/.anvaya/bin"
printf '#!/bin/sh\necho legacy\n' > "$HOME/.anvaya/bin/anv"; cp "$HOME/.anvaya/bin/anv" "$HOME/.anvaya/bin/mind-daemon"; chmod +x "$HOME/.anvaya/bin/"*
cp "$HOME/.anvaya/bin/anv" "$HOME/.anvaya/bin/anv.previous"
ANV_CHANNEL_FILE="$CH" run >/dev/null
[ -L "$HOME/.anvaya/bin/anv" ] && [ ! -e "$HOME/.anvaya/bin/anv.previous" ] && "$HOME/.anvaya/bin/anv" --version | grep -q 1.0.0 \
  && ok "legacy ~/.anvaya/bin copies replaced by links" || bad "legacy migration"

# 4. tampered archive is rejected and nothing changes
before="$(readlink "$BIN/anv")"
make_bundle 1.0.1 0
echo corrupt >> "$S/b-1.0.1/bundle.tar.gz"
out="$(ANV_CHANNEL_FILE="$CH" run)"
echo "$out" | grep -q "checksum mismatch" && [ "$(readlink "$BIN/anv")" = "$before" ] \
  && ok "tampered archive rejected, links untouched" || { bad "tamper"; echo "$out"; }

# 5. a binary that does not run triggers rollback AND is deleted
make_bundle 2.0.0 3
out="$(ANV_CHANNEL_FILE="$CH" run)"
echo "$out" | grep -q "restored the previous" && [ "$(readlink "$BIN/anv")" = "$before" ] \
  && ok "broken new version rolls back to the previous one" || { bad "rollback"; echo "$out"; }
[ ! -d "$VERS/2.0.0" ] && ok "failed version directory removed" || bad "failed version left behind"

# 6. upgrades keep the current version and the one it replaced, prune the rest
for v in 3.0.0 3.0.1 3.0.2; do make_bundle "$v" 0; ANV_CHANNEL_FILE="$CH" run >/dev/null; done
got="$(ls "$VERS" | tr '\n' ' ')"
[ "$got" = "3.0.1 3.0.2 " ] && ok "kept current + previous only ($got)" || bad "prune kept: $got"

# 7. --version and --component handling
out="$(ANV_CHANNEL_FILE="$CH" run --dry-run --version 9.9.9)"
echo "$out" | grep -qE "not found|requested|no '" && ok "unknown --version fails clearly" || bad "--version 9.9.9"
out="$(run --component nope)"; echo "$out" | grep -q "must be all" && ok "bad --component rejected" || bad "--component"

# 8. uninstall only removes what we installed
mkdir -p "$S/foreign"; printf '#!/bin/sh\necho foreign\n' > "$S/foreign/anv"; chmod +x "$S/foreign/anv"
run --uninstall --prefix "$S/foreign" >/dev/null
[ -f "$S/foreign/anv" ] && ok "uninstall leaves a foreign anv alone" || bad "uninstall deleted foreign anv"
run --uninstall >/dev/null
[ ! -e "$BIN/anv" ] && [ ! -e "$BIN/mind-daemon" ] && [ -d "$VERS" ] && ok "uninstall removes links, keeps versions" || bad "uninstall"
run --uninstall --purge >/dev/null
[ ! -d "$VERS" ] && ok "--uninstall --purge removes versions" || bad "purge"

# 9. --no-modify-path never touches the profile
rm -f "$HOME/.zshrc"
out="$(ANV_CHANNEL_FILE="$CH" run --no-modify-path)"
[ ! -f "$HOME/.zshrc" ] && echo "$out" | grep -q "Add Anvaya to your PATH" && ok "--no-modify-path leaves the profile alone" || bad "--no-modify-path"

# 10. platform guards
if [ "$(uname -s)" = Linux ]; then
  out="$(ANV_CHANNEL_FILE="$CH" run --dry-run)"
  echo "$out" | grep -q "target:     $TARGET" && ok "Linux target detected: $TARGET" || bad "Linux target"
else
  out="$(ANV_CHANNEL_FILE="$CH" run --dry-run)"
  echo "$out" | grep -q "target:     aarch64-apple-darwin" && ok "macOS target detected" || bad "macOS target"
fi

# 11. live: the real published bundle, end to end
if [ "$LIVE" = true ]; then
  rm -rf "$HOME/.anvaya" "$BIN"
  out="$(run)"; echo "$out" | tail -4
  "$BIN/anv" --version >/dev/null 2>&1 && "$BIN/mind-daemon" --version >/dev/null 2>&1 \
    && ok "live bundle installs and both binaries run" || bad "live install"
fi

echo; echo "passed=$pass failed=$fails"
[ "$fails" -eq 0 ]
