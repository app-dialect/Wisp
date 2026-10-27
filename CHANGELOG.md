# Changelog

All notable changes to Wisp are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Wisp uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0-beta] - 2026-10-27

### Added
- Plan review: approve Claude's plan from rendered Markdown, or send it back with feedback.
- Risk guard for destructive commands and sensitive files: warning banner, press-and-hold to allow, never auto-allowed.
- Allow for this session, trust a session (revocable), and allow all safe requests at once.
- Plan usage (5-hour and weekly limits), model, context and cost through a status line bridge that keeps an existing status line; warnings near limits and full context.
- Jump to the exact Terminal or iTerm2 tab, and reply to a finished session from the notch.
- Codex support through `~/.codex/hooks.json`.
- Synced lyrics, charging and low-battery peeks, download alerts, mic mute, full-screen hiding.
- Plan Usage, Dev Servers, Shortcuts and Mirror tiles.
- The island: grows out of the notch (or floats under the menu bar), opens on hover or click, configurable wings beside the camera, peeks, confetti.
- Claude Code: live sessions, step timeline, files changed with diffs, last reply, tokens, jump to terminal.
- Permissions from the notch: Allow, Always (saved to Claude Code or Wisp), Deny, Deny with a note, answer in terminal, countdown with terminal fallback.
- Claude's `AskUserQuestion` prompts answered from the notch.
- One-click connect with a preview and a dated backup of `~/.claude/settings.json`.
- The wisp: 6 shapes, 9 moods, 10 outfits with seasonal dressing, 3 personalities, eyes that follow the pointer, poke and dizzy reactions, desktop buddy mode.
- 18 tiles with an in-island edit mode.
- 10 themes, custom accent, frosted glass, 4 typefaces, motion presets, shareable look codes, settings import and export.
- 5 synthesized sound packs and custom sound files.
- Re-recordable global shortcuts.
- Weekly recap with a shareable image.
- `Wisp --demo <scene>` fills the island with made-up sessions for screenshots, using its own data folder.
