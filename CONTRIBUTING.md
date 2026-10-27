# Contributing to Wisp

Thanks for wanting to help! Bug reports, ideas, outfits, themes and pull requests are all welcome.

## Build

```bash
swift build          # quick type-check
./build.sh           # build/Wisp.app
./build.sh install   # copy to /Applications and launch
```

macOS 14+ and the Xcode Command Line Tools. No Xcode project, no dependencies.

## Add a tile in 5 steps

1. Add a case to `TileKind` in `Sources/Wisp/Tiles/Tiles.swift`, with a `title`, an SF Symbol and a default width.
2. Write a `View` with `let span: Int` in `Sources/Wisp/Tiles/TileViews.swift`. Copy `ProgressTile` for the shape.
3. Add it to the `switch` in `TileContent`.
4. If it polls something, give its service a `setActive(_:)` and switch it on in `AppDelegate.apply(_:)` only when the tile is in use.
5. `./build.sh`, add the tile from the island's edit mode, and open a PR with a screenshot. `.build/debug/Wisp --demo home` gives you made-up data, so nothing personal ends up in it.

## Guidelines

- Read [`CLAUDE.md`](CLAUDE.md): it maps the code and lists the design and safety rules.
- Colors come from the theme. Buttons inside the island use `IslandButton`.
- New network calls or macOS permissions need a line in the README's Privacy section.
- The hook must always fail quietly: Claude Code has to keep working when Wisp is closed.
- Keep pull requests focused, one change each.

## Using Claude Code

Open the folder in Claude Code and describe what you want. `/make-it-mine` walks you through it.
