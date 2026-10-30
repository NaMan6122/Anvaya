#!/bin/sh
# Anvaya installer.
#
#   curl -fsSL https://get.anvayahq.com/install.sh | sh
#   curl -fsSL https://get.anvayahq.com/install.sh | sh -s -- --component anv
#
# Components:
#   all   bundle: anv + mind-daemon (default)
#   anv   CLI only
#   mind  Mind daemon only
#
# Environment:
#   ANV_INSTALL_DIR   default $HOME/.anvaya/bin
#   ANV_STATE_DIR     default $HOME/.anvaya
#   ANV_CHANNEL_URL   default https://get.anvayahq.com/channels/beta.tsv
#   ANV_CHANNEL_FILE  local channel TSV for testing/offline
set -eu

CHANNEL_URL="${ANV_CHANNEL_URL:-https://get.anvayahq.com/channels/beta.tsv}"
CHANNEL_FILE="${ANV_CHANNEL_FILE:-}"
COMPONENT=all
WANT_VERSION=""
PREFIX="${ANV_INSTALL_DIR:-$HOME/.anvaya/bin}"
STATE_DIR="${ANV_STATE_DIR:-$HOME/.anvaya}"
SHOW_PATH_HINT=true
DRY_RUN=false
UNINSTALL=false

usage() {
  cat <<'USAGE'
Anvaya installer

Usage:
  install.sh [--component all|anv|mind] [--version V] [--prefix DIR]
             [--no-modify-path] [--dry-run] [--uninstall]

Components:
  all   bundle with anv and mind-daemon (default)
  anv   CLI only; Mind is not installed
  mind  Mind daemon only

Environment:
  ANV_INSTALL_DIR   install directory (default ~/.anvaya/bin)
  ANV_STATE_DIR     state directory (default ~/.anvaya)
  ANV_CHANNEL_URL   channel pointer URL
  ANV_CHANNEL_FILE  local channel TSV (skips the network)
USAGE
}

fail() { printf 'install: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --component)      COMPONENT="${2:-}"; shift 2 ;;
    --version)        WANT_VERSION="${2:-}"; shift 2 ;;
    --prefix)         PREFIX="${2:-}"; shift 2 ;;
    --no-modify-path) SHOW_PATH_HINT=false; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --uninstall)      UNINSTALL=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                fail "unknown argument: $1" ;;
  esac
done

case "$COMPONENT" in
  all|anv|mind) ;;
  *) fail "--component must be all, anv or mind (got '$COMPONENT')" ;;
esac

if [ "$UNINSTALL" = true ]; then
  case "$COMPONENT" in
    all)
      targets="$PREFIX/anv $PREFIX/mind-daemon $STATE_DIR/components/bundle.json $STATE_DIR/components/anv.json $STATE_DIR/components/mind-daemon.json"
      ;;
    anv)
      targets="$PREFIX/anv $STATE_DIR/components/anv.json"
      ;;
    mind)
      targets="$PREFIX/mind-daemon $STATE_DIR/components/mind-daemon.json"
      ;;
  esac
  if [ "$DRY_RUN" = true ]; then
    for path in $targets; do
      [ -e "$path" ] && printf 'would remove %s\n' "$path"
    done
    printf 'dry-run: nothing removed\n'
    exit 0
  fi
  for path in $targets; do
    if [ -e "$path" ]; then
      rm -f "$path"
      printf 'removed %s\n' "$path"
    fi
  done
  printf 'uninstalled %s (configuration and sessions are untouched)\n' "$COMPONENT"
  exit 0
fi

os="$(uname -s 2>/dev/null || echo unknown)"
arch="$(uname -m 2>/dev/null || echo unknown)"
case "$os:$arch" in
  Darwin:arm64) TARGET=aarch64-apple-darwin ;;
  Linux:x86_64|Linux:amd64) TARGET=x86_64-unknown-linux-gnu ;;
  Linux:aarch64|Linux:arm64) TARGET=aarch64-unknown-linux-gnu ;;
  *)
    printf 'install: no Anvaya build for %s %s yet.\n' "$os" "$arch" >&2
    printf 'Supported: macOS arm64, Linux x86_64, Linux arm64.\n' >&2
    exit 0
    ;;
esac

case "$COMPONENT" in
  all) WANT_KIND=bundle ;;
  *)   WANT_KIND="$COMPONENT" ;;
esac

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/anv-install.XXXXXX")"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT HUP INT TERM

channel="$CHANNEL_FILE"
if [ -z "$channel" ]; then
  channel="$tmpdir/channel.tsv"
  curl -fsSL "$CHANNEL_URL?cb=$(date +%s 2>/dev/null || echo 0)" -o "$channel" \
    || fail "could not fetch $CHANNEL_URL"
fi
[ -f "$channel" ] || fail "channel file not found: $channel"
channel_dir="$(cd "$(dirname "$channel")" && pwd)"

row_version=""
row_sha=""
row_size=""
row_url=""
while IFS="$(printf '\t')" read -r kind target version sha size url; do
  case "$kind" in
    ''|'#'*) continue ;;
  esac
  [ "$target" = "$TARGET" ] || continue
  [ "$kind" = "$WANT_KIND" ] || continue
  row_version="$version"
  row_sha="$sha"
  row_size="$size"
  row_url="$url"
  break
done < "$channel"

[ -n "$row_url" ] || fail "no '$WANT_KIND' artifact for $TARGET in $channel"
if [ -n "$WANT_VERSION" ] && [ "$row_version" != "$WANT_VERSION" ]; then
  fail "channel has $WANT_KIND $row_version, requested $WANT_VERSION"
fi

if [ "$DRY_RUN" = true ]; then
  printf 'target:     %s\n' "$TARGET"
  printf 'component:  %s (%s)\n' "$COMPONENT" "$WANT_KIND"
  printf 'version:    %s\n' "$row_version"
  printf 'sha256:     %s\n' "$row_sha"
  printf 'size:       %s\n' "$row_size"
  printf 'url:        %s\n' "$row_url"
  printf 'prefix:     %s\n' "$PREFIX"
  printf 'state:      %s\n' "$STATE_DIR"
  printf 'dry-run: nothing installed\n'
  exit 0
fi

artifact="$tmpdir/artifact.tar.gz"
case "$row_url" in
  file://*) cp "${row_url#file://}" "$artifact" ;;
  http://*|https://*) curl -fsSL "$row_url" -o "$artifact" || fail "download failed: $row_url" ;;
  *)
    if [ -f "$channel_dir/$row_url" ]; then
      cp "$channel_dir/$row_url" "$artifact"
    elif [ -f "$row_url" ]; then
      cp "$row_url" "$artifact"
    else
      fail "cannot resolve artifact URL: $row_url"
    fi
    ;;
esac

if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$artifact" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$artifact" | awk '{print $1}')"
else
  fail "need shasum or sha256sum"
fi
[ "$actual" = "$row_sha" ] || fail "checksum mismatch for $row_url (got $actual)"

tar -xzf "$artifact" -C "$tmpdir" || fail "cannot extract $row_url"
top="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "$top" ] || fail "archive has no top-level directory"

mkdir -p "$PREFIX" "$STATE_DIR/components"

install_bin() {
  src="$1"
  dst="$2"
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.previous"
  fi
  cp "$src" "$dst.new"
  chmod 755 "$dst.new"
  mv "$dst.new" "$dst"
}

case "$COMPONENT" in
  all)
    install_bin "$top/bin/anv" "$PREFIX/anv"
    install_bin "$top/bin/mind-daemon" "$PREFIX/mind-daemon"
    cp "$top/bundle.json" "$STATE_DIR/components/bundle.json"
    rm -f "$STATE_DIR/components/anv.json" "$STATE_DIR/components/mind-daemon.json"
    ;;
  anv)
    install_bin "$top/bin/anv" "$PREFIX/anv"
    cp "$top/component.json" "$STATE_DIR/components/anv.json"
    rm -f "$STATE_DIR/components/bundle.json"
    ;;
  mind)
    install_bin "$top/bin/mind-daemon" "$PREFIX/mind-daemon"
    cp "$top/component.json" "$STATE_DIR/components/mind-daemon.json"
    rm -f "$STATE_DIR/components/bundle.json"
    ;;
esac

# Copying is normally signature-preserving, but re-sign on macOS so a cp that
# strips the ad-hoc signature cannot leave a binary the kernel refuses to run.
if [ "$os" = Darwin ] && command -v codesign >/dev/null 2>&1; then
  [ -x "$PREFIX/anv" ] && codesign --force --sign - "$PREFIX/anv" >/dev/null 2>&1 || true
  [ -x "$PREFIX/mind-daemon" ] && codesign --force --sign - "$PREFIX/mind-daemon" >/dev/null 2>&1 || true
fi

printf 'installed %s %s into %s\n' "$COMPONENT" "$row_version" "$PREFIX"

if [ -x "$PREFIX/anv" ]; then
  if ! "$PREFIX/anv" --version; then
    if [ -f "$PREFIX/anv.previous" ]; then
      mv "$PREFIX/anv.previous" "$PREFIX/anv"
      printf 'install: restored the previous anv\n' >&2
    fi
    fail "installed anv does not run"
  fi
fi

if command -v pgrep >/dev/null 2>&1 && pgrep -x mind-daemon >/dev/null 2>&1; then
  printf '\nA mind-daemon is running; restart it to pick up the new binary.\n'
fi

if [ "$COMPONENT" = anv ]; then
  printf '\nMind is not installed. anv will run without memory.\n'
  printf 'Install it with:\n'
  printf '  curl -fsSL https://get.anvayahq.com/install.sh | sh -s -- --component mind\n'
fi

if [ "$COMPONENT" = mind ]; then
  printf '\nmind-daemon installed at %s/mind-daemon (run it with --version)\n' "$PREFIX"
fi

if [ "$SHOW_PATH_HINT" = true ]; then
  case ":${PATH:-}:" in
    *":$PREFIX:"*) ;;
    *)
      printf '\nAdd Anvaya to your PATH:\n'
      printf '  export PATH="%s:$PATH"\n' "$PREFIX"
      ;;
  esac
fi

if [ -x "$PREFIX/anv" ]; then
  printf '\nDone. Run: anv\n'
else
  printf '\nDone. Install the CLI with --component anv or --component all.\n'
fi
