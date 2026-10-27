# Wisp: map for Claude

You are helping someone change Wisp, a macOS notch app (Swift, AppKit + SwiftUI, SwiftPM, no Xcode project). Read this first, then the files it points to.

## Build and check
- `swift build` to type-check fast; `./build.sh` to make `build/Wisp.app` (icon included); `./build.sh install` to copy it to /Applications and launch it.
- Needs macOS 14+ and the Command Line Tools. New `.swift` files under `Sources/Wisp/` compile automatically.
- After every change, build and fix errors before saying you're done. Then tell the person to quit Wisp and open the new build.
- `Wisp --render-icon <dir.iconset>` renders the icon from the mascot code (`App/IconRenderer.swift`).

## Where things are
| You want to change | Look in |
|---|---|
| Any saved setting | `App/Config.swift`: add a field with a default to `Config`. Old saved settings still load (missing keys fall back to defaults). Read with `Prefs.shared.c`, bind with `$prefs.c.field` |
| Themes and colors | `App/Theme.swift`: `Theme.all`. Views read `@Environment(\.look)` (theme, accent, font) |
| The notch window, hover, open/close, which screen | `Island/IslandController.swift` |
| Sizes of the island and wings | `Island/IslandModel.swift` (`expandedSize`, `collapsedSize`) |
| The notch silhouette | `Island/IslandShape.swift` |
| Expanded layout, header, tabs | `Island/IslandView.swift` |
| What sits beside the camera | `Island/Wings.swift` + `WingContent` in `Config.swift` |
| Tiles | `Tiles/Tiles.swift` (`TileKind`, edit mode), views in `Tiles/TileViews.swift`, recap in `Tiles/Recap.swift` |
| The mascot (shapes, faces, moods, outfits) | `Mascot/Mascot.swift`: `MascotPainter` draws in a Canvas in a 0…1 unit square; `MoodEngine` picks the mood |
| Desktop buddy | `Mascot/DesktopBuddy.swift` |
| Claude Code events, sessions, permissions, questions, stats | `Claude/ClaudeHub.swift` |
| Tool names → words and icons, diffs, transcript parsing | `Claude/ClaudeModels.swift` |
| Claude panel, permission card, question card | `Claude/ClaudeViews.swift` |
| Writing `~/.claude/settings.json` | `Claude/ClaudeConnector.swift` |
| The hook (Python, stdlib only) | `Resources/wisp-hook.py`; socket server in `Claude/HookServer.swift` |
| Music, calendar, weather, CPU/battery, clipboard, focus timer | `Services/Music.swift`, `Services/LiveData.swift` |
| Sounds (synthesized) | `Services/Sounds.swift` |
| Global shortcuts | `Services/Hotkeys.swift` + `HotkeyAction` in `Config.swift` |
| Settings window, onboarding | `Settings/SettingsView.swift`, `Settings/Onboarding.swift` |
| Menu bar menu, app start, wiring | `App/AppDelegate.swift` |

## How to add a tile (the most common request)
1. Add a case to `TileKind` in `Tiles/Tiles.swift` and fill in `title`, `symbol`, `defaultSpan`.
2. Write `struct MyTile: View { let span: Int ... }` in `Tiles/TileViews.swift` (copy `ProgressTile` or `WeatherTile`). Use `TileTitle`, `look.theme.*` and `look.accent`.
3. Add it to the `switch` in `TileContent`.
4. If it needs a service that polls, add `setActive` and switch it on in `AppDelegate.apply(_:)` only when the tile is used.

## How to add an outfit
Add a case to `Outfit` in `Config.swift` (and its `label`), then draw it in `MascotPainter.wear(_:_:_:)`. Coordinates are 0…1; `headTop` and `eyeY` tell you where the head and eyes are for each shape.

## Design rules
- Colors come from the theme (`look.theme.*`, `look.accent`) or a `Mood` color. Don't hard-code new ones.
- One typeface family, chosen by the person (`look.font`).
- In notch style, the strip beside the camera stays black so the island grows out of the notch.
- Buttons inside the island use `IslandButton` (system buttons look disabled in a non-key panel).
- Short labels. Plain words.

## Safety rules
- Ask before adding a dependency, a network call or a new macOS permission. Wisp asks for permissions only when a feature needs one.
- Never write outside Wisp's data folder without showing the change first and keeping a backup (see `ClaudeConnector`).
- Keep the hook's fallback: if Wisp is closed or doesn't answer, the hook must exit quietly so Claude Code asks in the terminal.
