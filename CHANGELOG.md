# Changelog

All notable changes to Anvaya CLI.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0-beta.3] — 2026-11-10

A release-build fix. Linux binaries were shipping without their allocator
configuration, which made every Linux install idle at roughly three times its
real working set on an 8-core machine — and grow worse with core count.

### Fixed

- **Linux idle memory.** `.cargo/config.toml` bakes the arena ceiling
  (`narenas:4`) and `retain:false` into jemalloc, but the Linux build ran cargo
  with a working directory outside the checkout, where cargo never finds that
  file: it resolves `.cargo/config.toml` from the cwd and its ancestors, never
  from `--manifest-path`. Measured on the reporting host (8 threads, EndeavourOS,
  transparent huge pages forced on): idle TUI RSS **61–65 MB → 22–26 MB**.
- **RSS no longer scales with core count.** Uncapped, the binary idled at
  24.8 / 37.6 / 45.9 / 60.7 MB with 1 / 2 / 4 / 8 visible CPUs. The fixed build
  is flat at ~22–26 MB across the same set.
- **Huge pages no longer inflate Linux RSS.** The Linux triplets now ask jemalloc
  for `thp:never`; where a distro forces transparent huge pages on, a touched
  extent otherwise pulls a whole 2 MB page resident.
- **The release pipeline refuses to package an artifact whose allocator
  configuration did not compile in**, so this cannot ship silently again.

### Notes

- macOS is unaffected by the allocator fix — its binaries always carried the
  configured value. Measured on this tag: **20.5 MB RSS / 9.6 MB footprint**
  (beta.2) against **22.4 MB / 10.0 MB** (beta.3); the difference is code drift
  between the two cuts, not allocator configuration. Start-up is unchanged
  (6.5 ms vs 5.7 ms median) and idle CPU stays at ~0.1%.
- The allocator configuration is compiled in, so `MALLOC_CONF` no longer tunes a
  release binary at runtime.
- Defect record: `records/defect/defect-121-v1.md`.

---

## [0.1.0-beta.1] — 2026-10-19

First public beta.

### Supported platforms

| Platform | Status | Mind | Swarm |
|---|---|---|---|
| macOS arm64 | **Supported** — reference platform | yes | yes |
| Linux x86_64 | **Supported** | yes | yes |
| Linux arm64 | **Supported** | yes | yes |
| Android / Termux arm64 | Experimental | yes | yes |
| Windows x86_64 | **Preview — compile-verified only** | no | no |

Windows is built and linked but has not been runtime-tested, and Mind and swarm
are unavailable there because both use unix domain sockets. It is not
cross-compilation-clean by accident: see `records/platforms/CROSS_PLATFORM_BUILD.md`.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/NaMan6122/Anvaya-Cli/main/install.sh | sh
```

The installer places `anv`, `mind-daemon` and `anvd` in `~/.anvaya/bin`. **They must
stay together**: `anv` resolves `mind-daemon` as a sibling and `anvd` resolves `anv`
the same way. Separating them does not error — it silently disables memory.

### Added

- **Fullscreen TUI** with eight screens — Startup, Agent, Git, Monitor, MCP,
  Mind, Terminal, Swarm.
- **21 built-in tools** — file read/write/edit/patch, glob, grep, directory
  tree, shell execution, todos, sub-agents, LSP, web search/fetch, Mind queries,
  monitors.
- **Persistent project memory (Mind)** via the `mind-daemon` IPC bridge:
  queries, responses, file edits, test results and session lifecycle are
  recorded per project.
- **Kernel-enforced sandboxing** — Seatbelt on macOS, Landlock on Linux
  (ADR-032..037), applied at the shell choke point.
- **Multi-agent swarm** — `anvd` supervisor, fleet board, worktree placement.
- **Workspaces (Shadow Trees)** — delta-layer working trees for concurrent agents.
- **Code intelligence** — LSP sessions with diagnostic injection, plus a
  repository map.
- **Evaluation harness** — reproducible controlled experiments over agent behaviour.
- **Local-first default** — Ollama works with no API key; OpenAI and Anthropic
  are opt-in.
- **Headless mode** — `--no-tui` for scripted and CI use.
- **First-run honesty** — `anv init` now probes the Mind daemon and reports
  whether memory will actually be recorded, instead of failing silently.

### Known limitations

- **No auto-update.** Check `anv --version` against the releases page manually.
- **`MIND` and swarm are unix-only**, so Windows ships without both.
- **Source builds need a second repository.** `crates/anv-mind` path-depends on
  `../../../anvaya-mind-rs`, so the Mind repo must sit beside this checkout.
  Prebuilt binaries do not have this requirement.
- **No crates.io distribution.** The crate name `anv` is already taken by an
  unrelated project.
- **Windows needs the VC++ redistributable** unless built with `+crt-static`.

### Notes

- macOS binaries are ad-hoc signed. That is sufficient for installs through the
  shell installer or Homebrew, neither of which sets the browser quarantine
  flag. A binary downloaded directly through a browser will need
  `xattr -d com.apple.quarantine ./anv`.
- `mind-daemon` is stripped at packaging time because its own repository
  declares no release profile (~42 MB unstripped, ~31 MB stripped).

---

[0.1.0-beta.1]: https://github.com/NaMan6122/Anvaya-Cli/releases/tag/v0.1.0-beta.1
[0.1.0-beta.3]: https://github.com/NaMan6122/Anvaya-Cli/releases/tag/v0.1.0-beta.3
