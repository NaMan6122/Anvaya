# Anvaya

Anvaya is an agentic terminal coding assistant. This repository is the public
distribution and issue tracker for the beta.

The source is private during the beta. Binaries are published here, and every
release ships with checksums and release notes.

## Install

Pick one. Each installs **both** halves together: the `anv` CLI and the
`mind-daemon` memory daemon that `anv` starts on demand.

### curl (macOS and Linux)

```sh
curl -fsSL https://get.anvayahq.com/install.sh | sh
```

The installer detects your platform, verifies the SHA-256 of the download, adds
`anv` to your `PATH`, and prints what it did. Open a new terminal afterwards and run:

```sh
anv --version
```

`get.anvayahq.com` is served from this repository by GitHub Pages. If it is ever
unreachable, the identical script is at
`https://raw.githubusercontent.com/NaMan6122/Anvaya/main/install.sh`, and the
installer itself falls back to GitHub for its channel pointer.

### Homebrew (macOS and Linux)

```sh
brew install NaMan6122/tap/anvaya
```

Upgrade with `brew upgrade anvaya`. The formula follows the same release channel
as the curl installer, so both install identical binaries.

## Supported platforms

| Platform | curl | Homebrew |
|---|---|---|
| macOS, Apple Silicon (arm64) | yes | yes |
| Linux x86_64, glibc 2.39+ | yes | yes |
| Linux arm64, glibc 2.39+ | yes | yes |
| macOS, Intel | not yet | not yet |
| Windows | use WSL | use WSL |

Linux needs glibc 2.39 or newer (Ubuntu 24.04+, Debian 13+, Fedora 40+) because
of the bundled ONNX Runtime. Alpine (musl) is not supported. The installer checks
this first and tells you if your system is too old.

## What gets installed (curl)

```
~/.anvaya/versions/<version>/anv            the real files
~/.anvaya/versions/<version>/mind-daemon
~/.local/bin/anv          -> ~/.anvaya/versions/<version>/anv
~/.local/bin/mind-daemon  -> ~/.anvaya/versions/<version>/mind-daemon
```

- An upgrade switches the links, so it is atomic. The previous version stays on
  disk for rollback; older ones are removed.
- If the new binary does not run on your machine, the installer restores the
  previous links and removes the broken version.
- `anv` and `mind-daemon` always link side by side. Do not move one without the
  other.
- If `~/.local/bin` is not on your `PATH`, the installer appends one marked
  block to your shell profile (`~/.zshrc`, `~/.bashrc` or `~/.bash_profile`, or
  a fish conf.d file). Use `--no-modify-path` to opt out and get the line to
  paste instead.

### Options

```sh
curl -fsSL https://raw.githubusercontent.com/NaMan6122/Anvaya/main/install.sh | sh -s -- --help
```

| Option | Effect |
|---|---|
| `--component anv` / `mind` | install only the CLI / only the daemon (the bundle is the tested pair) |
| `--version X` | install a specific release instead of the channel's current one |
| `--prefix DIR` | put the links in `DIR` instead of `~/.local/bin` |
| `--no-modify-path` | never edit a shell profile |
| `--dry-run` | show what would be installed, change nothing |
| `--uninstall` | remove the links (your configuration and sessions are kept) |
| `--uninstall --purge` | also delete the downloaded versions |

## Updating

| Installed with | Update with |
|---|---|
| curl | re-run the install command (it upgrades in place and keeps the previous version for rollback) |
| Homebrew | `brew upgrade anvaya` |

From the first release after `0.1.0-beta.1`, `anv update` does the curl-style
update for you, for `anv` and `mind-daemon` together:

```sh
anv update --check     # is a newer release out? (exit 10 = yes, 0 = current)
anv update             # update both halves
anv update --version X # install a specific release
```

`anv update` refuses to touch an `anv` that Homebrew or `cargo` installed, and
tells you the right command instead. Restart any running `mind-daemon` after an
update so it picks up the new binary.

## Beta status

- Expect breaking changes between beta releases.
- Binaries are ad-hoc signed, not notarized by Apple yet. The curl installer and
  Homebrew do not set the macOS quarantine flag, so they run without a Gatekeeper
  prompt. An archive downloaded in a browser **is** quarantined. If macOS says it
  cannot verify the binary, clear the flag on the unpacked files:

  ```sh
  xattr -dr com.apple.quarantine /path/to/unpacked/anvaya-*
  ```

## Verify a download

Every release publishes `release.json` and `SHA256SUMS` next to the archives.
The installer verifies SHA-256 before installing. To check by hand:

```sh
shasum -a 256 anvaya-<version>-<target>.tar.gz
```

The current channel pointer is
[`channels/beta.json`](channels/beta.json), with a tab-separated mirror at
[`channels/beta.tsv`](channels/beta.tsv) for the installer.

## Reporting

- Bugs and feature requests: open an issue. Use the forms; they ask for the
  version and platform we need to reproduce.
- Questions: Discussions.
- Security: follow [SECURITY.md](SECURITY.md). Never open a public issue for a
  vulnerability.

Never paste API keys, tokens, or private paths into an issue.

## License

Anvaya is proprietary software, licensed rather than sold. The terms are in the
[Anvaya Beta License](LICENSE) that ships inside every release archive: you may
download, install and run it for any purpose, including at work; you may not
redistribute it as part of your own product, modify it, or reverse engineer it.
Pre-release builds come with no warranty.

The archives also contain `THIRD-PARTY-NOTICES`, which reproduces the license of
every open-source component compiled into `anv` and `mind-daemon`. Those
components stay under their own licenses and are unaffected by the terms above.
