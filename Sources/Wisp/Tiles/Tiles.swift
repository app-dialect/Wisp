import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TileKind: String, Codable, CaseIterable, Identifiable {
    case claude, usage, music, calendar, weather, timer, clipboard, shelf, todo, worldClock, system, progress, toggles, fortune, recap, devServers, shortcuts, camera
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .music: "Now Playing"
        case .calendar: "Next Meeting"
        case .weather: "Weather"
        case .timer: "Focus Timer"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .todo: "To-do"
        case .worldClock: "World Clock"
        case .system: "System"
        case .progress: "Day Progress"
        case .toggles: "Switches"
        case .fortune: "Wisp Says"
        case .recap: "Week with Claude"
        case .usage: "Plan Usage"
        case .devServers: "Dev Servers"
        case .shortcuts: "Shortcuts"
        case .camera: "Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .music: "music.note"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .timer: "timer"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray"
        case .todo: "checklist"
        case .worldClock: "globe"
        case .system: "cpu"
        case .progress: "chart.bar"
        case .toggles: "switch.2"
        case .fortune: "quote.bubble"
        case .recap: "chart.bar.xaxis"
        case .usage: "gauge.with.dots.needle.33percent"
        case .devServers: "server.rack"
        case .shortcuts: "square.stack.3d.up"
        case .camera: "camera"
        }
    }

    var defaultSpan: Int {
        switch self {
        case .claude, .music, .calendar, .clipboard, .todo, .worldClock, .recap, .usage, .devServers, .shortcuts: 2
        default: 1
        }
    }
}

enum TileMetrics {
    static let cell: CGFloat = 100
    static let gap: CGFloat = 8
    static func width(_ span: Int) -> CGFloat { CGFloat(span) * cell + CGFloat(span - 1) * gap }
}

/// The tile row on the Home tab, with an edit mode for adding, removing, resizing and moving.
struct HomeView: View {
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel
    @Environment(\.look) private var look

    var body: some View {
        let tiles = prefs.c.tiles
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TileMetrics.gap) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    TileFrame(config: tile, index: index, count: tiles.count)
                }
                if model.editing || tiles.isEmpty { addTile }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(look.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(RoundedRectangle(cornerRadius: 18).fill(look.accent.opacity(0.12)))
                    .overlay(Label("Drop to put it on the shelf", systemImage: "tray.and.arrow.down").foregroundStyle(look.theme.text))
            }
        }
    }

    private var addTile: some View {
        Menu {
            ForEach(TileKind.allCases) { kind in
                Button { prefs.c.tiles.append(TileConfig(kind: kind, span: kind.defaultSpan)) } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 20, weight: .light))
                Text("Add tile").font(.system(size: 11))
            }
            .frame(width: TileMetrics.cell, height: nil)
            .frame(maxHeight: .infinity)
            .foregroundStyle(look.theme.secondary)
            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(look.theme.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: TileMetrics.cell)
    }
}

private struct TileFrame: View {
    let config: TileConfig
    let index: Int
    let count: Int
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel
    @Environment(\.look) private var look

    var body: some View {
        TileContent(kind: config.kind, span: config.span)
            .padding(10)
            .frame(width: TileMetrics.width(config.span))
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(look.theme.surface))
            .foregroundStyle(look.theme.text)
            .overlay { if model.editing { editOverlay } }
            .modifier(Jiggle(active: model.editing && prefs.c.jiggleInEditMode))
    }

    private var editOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.35))
            VStack(spacing: 6) {
                Text(config.kind.title).font(.system(size: 11, weight: .semibold))
                HStack(spacing: 4) {
                    pill("chevron.left", enabled: index > 0) { move(-1) }
                    pill("minus", enabled: config.span > 1) { resize(-1) }
                    pill("plus", enabled: config.span < 3) { resize(1) }
                    pill("chevron.right", enabled: index < count - 1) { move(1) }
                }
            }
            .foregroundStyle(.white)
        }
        .overlay(alignment: .topLeading) {
            Button { prefs.c.tiles.removeAll { $0.id == config.id } } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .red)
            }
            .buttonStyle(.plain)
            .offset(x: -4, y: -4)
        }
    }

    private func pill(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func move(_ d: Int) {
        var t = prefs.c.tiles
        guard let i = t.firstIndex(where: { $0.id == config.id }), t.indices.contains(i + d) else { return }
        t.swapAt(i, i + d)
        withAnimation(prefs.c.motion.animation) { prefs.c.tiles = t }
    }

    private func resize(_ d: Int) {
        guard let i = prefs.c.tiles.firstIndex(where: { $0.id == config.id }) else { return }
        withAnimation(prefs.c.motion.animation) {
            prefs.c.tiles[i].span = min(3, max(1, prefs.c.tiles[i].span + d))
        }
    }
}

struct TileContent: View {
    let kind: TileKind
    let span: Int

    var body: some View {
        switch kind {
        case .claude: ClaudeTile(span: span)
        case .music: MusicTile(span: span)
        case .calendar: CalendarTile(span: span)
        case .weather: WeatherTile(span: span)
        case .timer: TimerTile(span: span)
        case .clipboard: ClipboardTile(span: span)
        case .shelf: ShelfTile(span: span)
        case .todo: TodoTile(span: span)
        case .worldClock: WorldClockTile(span: span)
        case .system: SystemTile(span: span)
        case .progress: ProgressTile(span: span)
        case .toggles: TogglesTile(span: span)
        case .fortune: FortuneTile(span: span)
        case .recap: RecapTile(span: span)
        case .usage: UsageTile(span: span)
        case .devServers: DevServersTile(span: span)
        case .shortcuts: ShortcutsTile(span: span)
        case .camera: CameraTile(span: span)
        }
    }
}

/// Small caption at the top of a tile.
struct TileTitle: View {
    let text: String
    let symbol: String
    @Environment(\.look) private var look
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(look.theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shelf storage

/// Files dropped on the notch. Wisp keeps references, not copies.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    private static let key = "wisp.shelf"

    @Published private(set) var files: [URL] = []

    private init() {
        files = (UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func accept(_ providers: [NSItemProvider]) {
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self.add(url) }
            }
        }
    }

    func add(_ url: URL) {
        files.removeAll { $0 == url }
        files.insert(url, at: 0)
        save()
        Sounds.shared.play(.pop)
    }

    func remove(_ url: URL) { files.removeAll { $0 == url }; save() }
    func clear() { files.removeAll(); save() }

    private func save() { UserDefaults.standard.set(files.map(\.path), forKey: Self.key) }
}
