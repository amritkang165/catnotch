# Security policy

## Supported versions

Only the latest release gets security fixes. Version 1.0.x (the Electron app) is no longer maintained.

| Version | Supported |
|---|---|
| Latest 2.x | Yes |
| 1.0.x | No |

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use GitHub's private reporting: open the **Security** tab of this repository and choose **Report a vulnerability**. Include what you found, the steps to reproduce it, the CatNotch and macOS versions, and the impact you think it has.

CatNotch is a small project with one maintainer. Reports are handled on a best effort basis; I will acknowledge a report as soon as I can and tell you what I plan to do about it. Please give me a reasonable chance to ship a fix before you disclose publicly.

## What is worth reporting

CatNotch runs unsandboxed and touches a few sensitive places, so these areas matter most:

- **The Claude Code hook server.** It listens on a local port and CatNotch writes its entries into `~/.claude/settings.json`. Anything that lets another process or a web page on the same Mac answer or forge a permission prompt is in scope.
- **Credentials.** AI usage reads the Claude Code and Codex logins already on your Mac (including the Keychain) and sends them only to Anthropic and OpenAI. Any leak or misuse of those tokens is in scope.
- **The updater.** The in-app update downloads a release from this repository and replaces the app.
- **File handling.** The Shelf copies and opens dropped files and screenshots.

## Known limits (not vulnerabilities)

- Releases are ad hoc signed and not notarized, so macOS asks you to approve the first open. See the README.
- Now playing uses a private Apple interface (MediaRemote) through a vendored adapter. Apple can change it.

See [PRIVACY.md](PRIVACY.md) for what CatNotch reads and where data goes.
