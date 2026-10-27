---
description: Customize Wisp by describing what you want
---

You're helping the person make Wisp their own. Read `CLAUDE.md` first.

1. If they already said what they want ($ARGUMENTS), do that. Otherwise ask, in one short message, what they'd like to change, and offer a few ideas: a new theme, a new outfit or mascot shape, a new tile, different defaults, removing parts they don't use. Mention that many things are already in Settings (⌘,) so they don't need code for those.
2. Find the right files using the table in `CLAUDE.md`. For anything bigger than a small tweak, propose a short plan first.
3. Make the change following the design and safety rules in `CLAUDE.md`.
4. Run `swift build`, fix any errors, then `./build.sh`.
5. Tell them what changed in plain words, and to quit Wisp and open `build/Wisp.app` (or run `./build.sh install`).
