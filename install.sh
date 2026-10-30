#!/bin/sh
# Anvaya installer.
#
#   curl -fsSL https://get.anvayahq.com/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/NaMan6122/Anvaya/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --component anv
#
# Layout (the same idea as Claude Code / Codex):
#
#   ~/.anvaya/versions/<version>/{anv,mind-daemon,bundle.json}   real files
#   ~/.local/bin/anv          -> ~/.anvaya/versions/<version>/anv
#   ~/.local/bin/mind-daemon  -> ~/.anvaya/versions/<version>/mind-daemon
#
# An upgrade flips the symlinks, so it is atomic and the previous version stays
# on disk for rollback. anv and mind-daemon are always linked side by side.
#
# Components:
#   all   bundle: anv + mind-daemon (default, the tested pair)
#   anv   CLI only
#   mind  Mind daemon only
#
# Environment:
#   ANV_INSTALL_DIR       directory that receives the symlinks (default ~/.local/bin)
#   ANV_STATE_DIR         state directory (default ~/.anvaya)
#   ANV_CHANNEL           release channel (default beta)
#   ANV_CHANNEL_URL       channel pointer URL
#   ANV_CHANNEL_FALLBACK  raw GitHub channel used while the custom domain is down
#   ANV_CHANNEL_FILE      local channel TSV (testing / offline)
#   ANV_RELEASE_REPO      GitHub repo that hosts releases (default NaMan6122/Anvaya)
#   ANV_SKIP_PLATFORM_CHECK=1   skip the glibc check on Linux
set -eu

RELEASE_REPO="${ANV_RELEASE_REPO:-NaMan6122/Anvaya}"
CHANNEL="${ANV_CHANNEL:-beta}"
CHANNEL_URL="${ANV_CHANNEL_URL:-https://get.anvayahq.com/channels/$CHANNEL.tsv}"
CHANNEL_FALLBACK="${ANV_CHANNEL_FALLBACK:-https://raw.githubusercontent.com/$RELEASE_REPO/main/channels/$CHANNEL.tsv}"
CHANNEL_FILE="${ANV_CHANNEL_FILE:-}"
COMPONENT=all
WANT_VERSION=""
BIN_DIR="${ANV_INSTALL_DIR:-$HOME/.local/bin}"
STATE_DIR="${ANV_STATE_DIR:-$HOME/.anvaya}"
LEGACY_BIN="$HOME/.anvaya/bin"
MODIFY_PATH=true
DRY_RUN=false
UNINSTALL=false
PURGE=false

# Linux builds link against glibc symbols that need at least this release
# (the bundled ONNX Runtime requires 2.39, i.e. Ubuntu 24.04+).
MIN_GLIBC_MAJOR=2
MIN_GLIBC_MINOR=39

usage() {
  cat <<'USAGE'
Anvaya installer

Usage:
  install.sh [--component all|anv|mind] [--version V] [--prefix DIR]
             [--no-modify-path] [--dry-run] [--uninstall [--purge]]

Components:
  all   bundle with anv and mind-daemon (default)
  anv   CLI only; Mind is not installed
  mind  Mind daemon only

Options:
  --prefix DIR        directory that receives the anv / mind-daemon symlinks
                      (default ~/.local/bin)
  --no-modify-path    never edit a shell profile; only print the PATH line
  --uninstall         remove the symlinks (configuration and sessions are kept)
  --purge             with --uninstall, also delete downloaded versions

Environment:
  ANV_INSTALL_DIR   same as --prefix
  ANV_STATE_DIR     state directory (default ~/.anvaya)
  ANV_CHANNEL       release channel (default beta)
  ANV_CHANNEL_FILE  local channel TSV (skips the network)
USAGE
}

fail() { printf 'install: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --component)      COMPONENT="${2:-}"; shift 2 ;;
    --version)        WANT_VERSION="${2:-}"; shift 2 ;;
    --prefix)         BIN_DIR="${2:-}"; shift 2 ;;
    --no-modify-path) MODIFY_PATH=false; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --uninstall)      UNINSTALL=true; shift ;;
    --purge)          PURGE=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                fail "unknown argument: $1" ;;
  esac
done

case "$COMPONENT" in
  all|anv|mind) ;;
  *) fail "--component must be all, anv or mind (got '$COMPONENT')" ;;
esac
[ -n "$BIN_DIR" ] || fail "--prefix needs a directory"

VERSIONS="$STATE_DIR/versions"

# True when $1 is a symlink into our versions tree, or a legacy real binary
# that an older installer dropped in ~/.anvaya/bin. We only ever delete these,
# never an unrelated `anv` the user put on their PATH.
is_ours() {
  p="$1"
  if [ -L "$p" ]; then
    case "$(readlink "$p")" in
      "$VERSIONS"/*|"$STATE_DIR"/versions/*) return 0 ;;
    esac
    return 1
  fi
  [ -f "$p" ] && [ "$(dirname "$p")" = "$LEGACY_BIN" ]
}

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" = true ]; then
  case "$COMPONENT" in
    all)  names="anv mind-daemon" ;;
    anv)  names="anv" ;;
    mind) names="mind-daemon" ;;
  esac
  for dir in "$BIN_DIR" "$LEGACY_BIN"; do
    for n in $names; do
      for p in "$dir/$n" "$dir/$n.previous"; do
        if [ -e "$p" ] || [ -L "$p" ]; then
          if is_ours "$p" || [ "${p%.previous}" != "$p" ]; then
            if [ "$DRY_RUN" = true ]; then note "would remove $p"; else rm -f "$p"; note "removed $p"; fi
          else
            note "kept $p (not installed by Anvaya)"
          fi
        fi
      done
    done
  done
  for f in bundle anv mind-daemon; do
    case "$COMPONENT:$f" in
      all:*|anv:anv|anv:bundle|mind:mind-daemon|mind:bundle) ;;
      *) continue ;;
    esac
    [ -e "$STATE_DIR/components/$f.json" ] || continue
    if [ "$DRY_RUN" = true ]; then note "would remove $STATE_DIR/components/$f.json"; else rm -f "$STATE_DIR/components/$f.json"; fi
  done
  if [ "$PURGE" = true ] && [ -d "$VERSIONS" ]; then
    if [ "$DRY_RUN" = true ]; then note "would remove $VERSIONS"; else rm -rf "$VERSIONS"; note "removed $VERSIONS"; fi
  fi
  [ "$DRY_RUN" = true ] && { note "dry-run: nothing removed"; exit 0; }
  note "uninstalled $COMPONENT (configuration and sessions are untouched)"
  note "If you added Anvaya to your PATH, the '# >>> anvaya >>>' block in your shell profile can be deleted."
  exit 0
fi

# ----------------------------------------------------------------- platform
os="$(uname -s 2>/dev/null || echo unknown)"
arch="$(uname -m 2>/dev/null || echo unknown)"

glibc_ok() {
  [ "${ANV_SKIP_PLATFORM_CHECK:-}" = 1 ] && return 0
  if ldd --version 2>&1 | head -2 | grep -qi musl; then
    fail "this is a musl system (e.g. Alpine). Anvaya's Linux builds need glibc ${MIN_GLIBC_MAJOR}.${MIN_GLIBC_MINOR}+ (Ubuntu 24.04 or newer, Debian 13+, Fedora 40+)."
  fi
  v="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
  [ -n "$v" ] || return 0   # cannot tell; let the post-install self-check decide
  maj="${v%%.*}"; rest="${v#*.}"; min="${rest%%.*}"
  case "$maj$min" in *[!0-9]*|'') return 0 ;; esac
  if [ "$maj" -lt "$MIN_GLIBC_MAJOR" ] || { [ "$maj" -eq "$MIN_GLIBC_MAJOR" ] && [ "$min" -lt "$MIN_GLIBC_MINOR" ]; }; then
    fail "glibc $v is too old. Anvaya's Linux builds need glibc ${MIN_GLIBC_MAJOR}.${MIN_GLIBC_MINOR}+ (Ubuntu 24.04 or newer, Debian 13+, Fedora 40+). Set ANV_SKIP_PLATFORM_CHECK=1 to try anyway."
  fi
}

case "$os" in
  Darwin)
    case "$arch" in
      arm64) TARGET=aarch64-apple-darwin ;;
      x86_64)
        # A shell running under Rosetta reports x86_64 on an Apple Silicon Mac.
        if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
          TARGET=aarch64-apple-darwin
          note "note: Rosetta shell detected; installing the native Apple Silicon build."
        else
          fail "Intel Macs are not supported yet. Supported: macOS on Apple Silicon, Linux x86_64 and arm64."
        fi
        ;;
      *) fail "no Anvaya build for macOS $arch. Supported: macOS on Apple Silicon, Linux x86_64 and arm64." ;;
    esac
    ;;
  Linux)
    case "$arch" in
      x86_64|amd64)  TARGET=x86_64-unknown-linux-gnu ;;
      aarch64|arm64) TARGET=aarch64-unknown-linux-gnu ;;
      *) fail "no Anvaya build for Linux $arch. Supported: x86_64 and arm64." ;;
    esac
    glibc_ok
    ;;
  *)
    fail "no Anvaya build for $os. Supported: macOS on Apple Silicon, Linux x86_64 and arm64 (Windows: use WSL)."
    ;;
esac

case "$COMPONENT" in
  all) WANT_KIND=bundle ;;
  *)   WANT_KIND="$COMPONENT" ;;
esac

# ---------------------------------------------------------------- downloads
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL --connect-timeout 10 "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -T 10 -O "$2" "$1"; }
else
  fail "need curl or wget"
fi

if command -v shasum >/dev/null 2>&1; then
  sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | awk '{print $1}'; }
else
  fail "need shasum or sha256sum"
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/anv-install.XXXXXX")"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT HUP INT TERM

stamp="$(date +%s 2>/dev/null || echo 0)"
channel="$CHANNEL_FILE"
if [ -z "$channel" ]; then
  channel="$tmpdir/channel.tsv"
  if ! fetch "$CHANNEL_URL?cb=$stamp" "$channel" 2>/dev/null; then
    printf 'install: %s unreachable; using %s\n' "$CHANNEL_URL" "$CHANNEL_FALLBACK" >&2
    fetch "$CHANNEL_FALLBACK?cb=$stamp" "$channel" || fail "could not fetch a channel pointer"
  fi
fi
[ -f "$channel" ] || fail "channel file not found: $channel"
channel_dir="$(cd "$(dirname "$channel")" && pwd)"

row_version=""; row_sha=""; row_size=""; row_url=""
while IFS="$(printf '\t')" read -r kind target version sha size url; do
  case "$kind" in ''|'#'*) continue ;; esac
  [ "$target" = "$TARGET" ] || continue
  [ "$kind" = "$WANT_KIND" ] || continue
  row_version="$version"; row_sha="$sha"; row_size="$size"; row_url="$url"
  break
done < "$channel"
[ -n "$row_url" ] || fail "no '$WANT_KIND' artifact for $TARGET in $channel"

# --version V that is not the channel's current release: resolve it from that
# release's own SHA256SUMS instead of the channel pointer.
if [ -n "$WANT_VERSION" ] && [ "$row_version" != "$WANT_VERSION" ]; then
  case "$WANT_KIND" in
    bundle) prefix="anvaya-$WANT_VERSION-" ;;
    anv)    prefix="anv-$WANT_VERSION-" ;;
    mind)   prefix="mind-daemon-" ;;
  esac
  base="https://github.com/$RELEASE_REPO/releases/download/v$WANT_VERSION"
  fetch "$base/SHA256SUMS" "$tmpdir/SHA256SUMS" 2>/dev/null \
    || fail "channel has $WANT_KIND $row_version; release v$WANT_VERSION was not found"
  line="$(grep -F "  ./$TARGET/$prefix" "$tmpdir/SHA256SUMS" | head -1 || true)"
  [ -n "$line" ] || fail "release v$WANT_VERSION has no '$WANT_KIND' artifact for $TARGET"
  row_sha="$(printf '%s' "$line" | awk '{print $1}')"
  row_url="$base/$(basename "$(printf '%s' "$line" | awk '{print $2}')")"
  row_version="$WANT_VERSION"
  row_size="unknown"
fi

case "$WANT_KIND" in
  mind) dir_name="mind-$row_version" ;;
  *)    dir_name="$row_version" ;;
esac

if [ "$DRY_RUN" = true ]; then
  note "target:     $TARGET"
  note "component:  $COMPONENT ($WANT_KIND)"
  note "version:    $row_version"
  note "sha256:     $row_sha"
  note "size:       $row_size"
  note "url:        $row_url"
  note "versions:   $VERSIONS/$dir_name"
  note "links in:   $BIN_DIR"
  note "state:      $STATE_DIR"
  note "dry-run: nothing installed"
  exit 0
fi

# ------------------------------------------------------------ fetch + verify
artifact="$tmpdir/artifact.tar.gz"
case "$row_url" in
  file://*) cp "${row_url#file://}" "$artifact" ;;
  http://*|https://*) fetch "$row_url" "$artifact" || fail "download failed: $row_url" ;;
  *)
    if [ -f "$channel_dir/$row_url" ]; then cp "$channel_dir/$row_url" "$artifact"
    elif [ -f "$row_url" ]; then cp "$row_url" "$artifact"
    else fail "cannot resolve artifact URL: $row_url"; fi
    ;;
esac

actual="$(sha256_of "$artifact")"
[ "$actual" = "$row_sha" ] || fail "checksum mismatch for $row_url (expected $row_sha, got $actual)"

mkdir -p "$tmpdir/x"
tar -xzf "$artifact" -C "$tmpdir/x" || fail "cannot extract $row_url"
top="$(find "$tmpdir/x" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "$top" ] || fail "archive has no top-level directory"

case "$COMPONENT" in
  all)  need="anv mind-daemon" ;;
  anv)  need="anv" ;;
  mind) need="mind-daemon" ;;
esac
for n in $need; do
  [ -f "$top/bin/$n" ] || fail "archive is missing bin/$n"
done

# ------------------------------------------------------------------ install
mkdir -p "$VERSIONS" "$BIN_DIR" "$STATE_DIR/components"
stage="$VERSIONS/$dir_name.partial"
rm -rf "$stage"
mkdir -p "$stage"
for n in $need; do
  cp "$top/bin/$n" "$stage/$n"
  chmod 755 "$stage/$n"
done
for meta in bundle.json component.json; do
  [ -f "$top/$meta" ] && cp "$top/$meta" "$stage/$meta"
done

if [ "$os" = Darwin ]; then
  # curl never sets com.apple.quarantine, but be explicit: a quarantined binary
  # would trip Gatekeeper because these builds are ad-hoc signed, not notarized.
  xattr -dr com.apple.quarantine "$stage" 2>/dev/null || true
  if command -v codesign >/dev/null 2>&1; then
    for n in $need; do codesign --force --sign - "$stage/$n" >/dev/null 2>&1 || true; done
  fi
fi

dest="$VERSIONS/$dir_name"
rm -rf "$dest.old"
[ -d "$dest" ] && mv "$dest" "$dest.old"
mv "$stage" "$dest"
rm -rf "$dest.old"

# Remember what each link pointed at so a failed self-check can roll back.
prev_anv="$(readlink "$BIN_DIR/anv" 2>/dev/null || true)"
prev_mind="$(readlink "$BIN_DIR/mind-daemon" 2>/dev/null || true)"

link_one() {  # link_one <name> <dir-holding-links>
  ln -s "$dest/$1" "$2/$1.new" && mv -f "$2/$1.new" "$2/$1"
}
for n in $need; do
  link_one "$n" "$BIN_DIR"
  # An older installer put real copies in ~/.anvaya/bin. They would shadow the
  # new links on any PATH that lists that directory first, so point them at the
  # same version instead of leaving stale binaries behind.
  if [ "$BIN_DIR" != "$LEGACY_BIN" ] && [ -f "$LEGACY_BIN/$n" ] && [ ! -L "$LEGACY_BIN/$n" ]; then
    link_one "$n" "$LEGACY_BIN"
    rm -f "$LEGACY_BIN/$n.previous"
  fi
done

rollback() {
  for pair in "anv:$prev_anv" "mind-daemon:$prev_mind"; do
    n="${pair%%:*}"; t="${pair#*:}"
    case " $need " in *" $n "*) ;; *) continue ;; esac
    if [ -n "$t" ]; then ln -s "$t" "$BIN_DIR/$n.new" && mv -f "$BIN_DIR/$n.new" "$BIN_DIR/$n"
    else rm -f "$BIN_DIR/$n"; fi
  done
  # Do not leave the broken version behind to be mistaken for a rollback target.
  case "$prev_anv $prev_mind" in
    *"/$dir_name/"*) ;;
    *) rm -rf "$dest" ;;
  esac
}

for n in $need; do
  if ! "$BIN_DIR/$n" --version >/dev/null 2>&1; then
    rollback
    fail "installed $n does not run on this machine; restored the previous version"
  fi
done

case "$COMPONENT" in
  all)
    [ -f "$dest/bundle.json" ] && cp "$dest/bundle.json" "$STATE_DIR/components/bundle.json"
    rm -f "$STATE_DIR/components/anv.json" "$STATE_DIR/components/mind-daemon.json"
    ;;
  anv)
    [ -f "$dest/component.json" ] && cp "$dest/component.json" "$STATE_DIR/components/anv.json"
    rm -f "$STATE_DIR/components/bundle.json"
    ;;
  mind)
    [ -f "$dest/component.json" ] && cp "$dest/component.json" "$STATE_DIR/components/mind-daemon.json"
    rm -f "$STATE_DIR/components/bundle.json"
    ;;
esac

# Keep what is linked now (either component) and the version that was linked
# before this install, for rollback; delete everything else.
keepers="$(readlink "$BIN_DIR/anv" 2>/dev/null || true) $(readlink "$BIN_DIR/mind-daemon" 2>/dev/null || true) $prev_anv $prev_mind"
for d in $(ls "$VERSIONS" 2>/dev/null); do
  case "$d" in *.partial|*.old) rm -rf "${VERSIONS:?}/$d"; continue ;; esac
  [ "$d" = "$dir_name" ] && continue
  case "$keepers" in *"/$d/"*) continue ;; esac
  rm -rf "${VERSIONS:?}/$d"
done

note "installed $COMPONENT $row_version"
note "  files:  $dest"
for n in $need; do note "  link:   $BIN_DIR/$n -> $dest/$n"; done
"$BIN_DIR/anv" --version 2>/dev/null || true

if command -v pgrep >/dev/null 2>&1 && pgrep -x mind-daemon >/dev/null 2>&1; then
  note ""
  note "A mind-daemon is running; restart it to pick up the new version."
fi

if [ "$COMPONENT" = anv ]; then
  note ""
  note "Mind is not installed. anv will run without memory."
  note "Install it with:  curl -fsSL https://get.anvayahq.com/install.sh | sh -s -- --component mind"
fi

# --------------------------------------------------------------------- PATH
on_path=false
case ":${PATH:-}:" in *":$BIN_DIR:"*) on_path=true ;; esac

if [ "$on_path" = false ]; then
  shown="$BIN_DIR"
  case "$BIN_DIR" in "$HOME"/*) shown="\$HOME/${BIN_DIR#"$HOME"/}" ;; esac
  line="export PATH=\"$shown:\$PATH\""
  profile=""
  case "$(basename "${SHELL:-sh}")" in
    zsh)  profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash) if [ "$os" = Darwin ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.bashrc"; fi ;;
    fish) profile="$HOME/.config/fish/conf.d/anvaya.fish"; line="fish_add_path \"$shown\"" ;;
  esac
  note ""
  if [ "$MODIFY_PATH" = true ] && [ -n "$profile" ]; then
    mkdir -p "$(dirname "$profile")"
    if [ -f "$profile" ] && grep -q '>>> anvaya >>>' "$profile" 2>/dev/null; then
      note "PATH: $profile already has an Anvaya block."
    else
      { printf '\n# >>> anvaya >>>\n%s\n# <<< anvaya <<<\n' "$line"; } >> "$profile"
      note "PATH: added $BIN_DIR to $profile"
    fi
    note "Open a new terminal, or run:  $line"
  else
    note "Add Anvaya to your PATH:"
    note "  $line"
  fi
fi

if [ -x "$BIN_DIR/anv" ] && [ "$COMPONENT" != mind ]; then
  note ""
  note "Done. Run: anv"
else
  note ""
  note "Done. Install the CLI with --component anv or --component all."
fi
