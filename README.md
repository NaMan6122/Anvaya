# Anvaya

Anvaya is an agentic terminal coding assistant. This repository is the public
distribution and issue tracker for the beta.

The source is private during the beta. Binaries are published here, and every
release ships with checksums and release notes.

## Install (macOS, Apple Silicon)

```sh
curl -fsSL https://get.anvaya.dev/install.sh | sh
export PATH="$HOME/.anvaya/bin:$PATH"
anv --version
```

The installer places `anv` and `mind-daemon` side by side in `~/.anvaya/bin`.
Both are required: `anv` starts the daemon on first use. Do not move one without
the other.

## Beta status

- Expect breaking changes between beta releases.
- `aarch64-apple-darwin` is the first supported target. Linux targets follow.
- Binaries are ad-hoc signed, not notarized. The curl installer avoids macOS
  quarantine; a tarball downloaded in a browser carries it. If macOS blocks the
  first run, clear the attribute:

  ```sh
  xattr -d com.apple.quarantine ~/.anvaya/bin/anv ~/.anvaya/bin/mind-daemon
  ```

## Verify a download

Every release publishes `release.json` and `SHA256SUMS` next to the archives.
The installer verifies SHA-256 before installing. To check by hand:

```sh
shasum -a 256 anv-<version>-<target>.tar.gz
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

The beta distribution license has not been finalized. Nothing in this
repository grants redistribution rights beyond downloading and running the
published binaries.
