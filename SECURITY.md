# Security Policy

## Supported versions

Only the newest published beta is supported. Older betas do not receive fixes.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:

**https://github.com/NaMan6122/Anvaya/security/advisories/new**

Do not open a public issue, discussion, or pull request for a suspected
vulnerability. Do not include exploit details in public channels.

Please include:

- the Anvaya version (`anv --version`) and platform (`uname -sm`);
- the provider and model in use, if relevant;
- impact and a minimal reproduction;
- whether the issue requires a malicious repository, a malicious tool output, or
  only local access.

We will acknowledge the report in the advisory thread and coordinate disclosure
after a fix ships. There is no bug bounty during the beta.

## Scope

The beta runs local tools with your permissions. Reports that matter most:

- sandbox or approval bypasses (a tool acting outside the configured policy);
- credential exposure in logs, transcripts, or model requests;
- command execution from untrusted repository content without approval;
- path traversal or writes outside the project root;
- supply-chain issues in a published binary.

Provider-side outages, model quality, and account billing are out of scope for
this repository.
