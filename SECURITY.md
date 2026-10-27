# Security Policy

## Supported versions

Wisp is in beta. Security fixes land in the latest release only.

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Use GitHub's private reporting instead: go to the **Security** tab of this repository and click **Report a vulnerability**. Include steps to reproduce and the Wisp and macOS versions.

You'll get an acknowledgement within a few days. Once a fix ships, we're happy to credit you in the release notes.

## What we care about most

- The hook socket (`~/Library/Application Support/Wisp/wisp.sock`): anything that lets another process approve Claude Code permissions, or read what Claude is doing.
- Changes to `~/.claude/settings.json` beyond Wisp's own hook entries.
- Unexpected network traffic or data leaving the Mac beyond what the README documents.
