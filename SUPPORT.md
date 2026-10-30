# Support

## Where to ask

- **Bugs and feature requests** — open an issue using the forms. Blank issues are
  disabled so the version and platform fields are always present.
- **Questions, workflows, show-and-tell** — Discussions.
- **Security** — [SECURITY.md](SECURITY.md) only. Never a public issue.

## What to include in a bug report

1. `anv --version`
2. `uname -sm`
3. Provider and model (for example `anthropic / claude-sonnet-5.5`)
4. What you ran, what happened, and what you expected
5. The smallest log that shows the failure, with secrets removed

Redact API keys, tokens, private repository paths, and customer names. If a log
is large, attach a trimmed excerpt rather than the whole session.

## Before filing

- Re-run on the newest beta; the issue may already be fixed.
- Try `anv --no-mind` to tell a Mind/daemon problem from a CLI problem.
- Check whether the issue reproduces in an empty project directory.

## Response expectations

The beta is maintained by a small team. Issues are triaged in batches; a
reproduction with a version and platform gets looked at first.
