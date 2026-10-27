import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, look, island, wisp, claude, tiles, sound, shortcuts, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .look: "Look"
        case .island: "Island & Wings"
        case .wisp: "Your Wisp"
        case .claude: "Claude Code"
        case .tiles: "Tiles"
        case .sound: "Sound"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .look: "paintpalette"
        case .island: "capsule.tophalf.filled"
        case .wisp: "flame"
        case .claude: "sparkles"
        case .tiles: "square.grid.2x2"
        case .sound: "speaker.wave.2"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

final class SettingsRouter: ObservableObject {
    @Published var page: SettingsPage = .general
}

struct SettingsView: View {
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $router.page) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch router.page {
                case .general: GeneralPage()
                case .look: LookPage()
                case .island: IslandPage()
                case .wisp: WispPage()
                case .claude: ClaudePage()
                case .tiles: TilesPage()
                case .sound: SoundPage()
                case .shortcuts: ShortcutsPage()
                case .about: AboutPage()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(router.page.title)
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - General

private struct GeneralPage: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Wisp when you log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { message = error.localizedDescription; launchAtLogin = !on }
                    }
                Toggle("Show the menu bar icon", isOn: $prefs.c.showMenuBarIcon)
                Picker("Show the island on", selection: $prefs.c.screen) {
                    ForEach(ScreenChoice.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Opening") {
                Picker("Open with", selection: $prefs.c.trigger) {
                    ForEach(OpenTrigger.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if prefs.c.trigger == .hover {
                    Slider(value: $prefs.c.hoverDelay, in: 0...1, step: 0.05) { Text("Hover delay") } minimumValueLabel: { Text("0s") } maximumValueLabel: { Text("1s") }
                }
                Slider(value: $prefs.c.closeDelay, in: 0.1...2, step: 0.05) { Text("Close after leaving") } minimumValueLabel: { Text("fast") } maximumValueLabel: { Text("slow") }
                Toggle("Trackpad haptics", isOn: $prefs.c.haptics)
                Toggle("Step aside for full-screen apps (unless an agent needs you)", isOn: $prefs.c.hideInFullScreen)
            }
            Section("Heads-ups") {
                Toggle("Charging and low battery", isOn: $prefs.c.powerAlerts)
                Toggle("Finished downloads", isOn: $prefs.c.downloadAlerts)
                if prefs.c.downloadAlerts {
                    Toggle("Put new downloads on the shelf", isOn: $prefs.c.downloadsToShelf)
                    Text("macOS asks once for access to your Downloads folder.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Your settings") {
                HStack {
                    Button("Export…") { export() }
                    Button("Import…") { importFile() }
                    Spacer()
                    Button("Reset everything", role: .destructive) { prefs.reset() }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Wisp Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = prefs.exportData() else { return }
        do { try data.write(to: url); message = "Saved to \(Paths.pretty(url.path))" } catch { message = error.localizedDescription }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        message = prefs.importData(data) ? "Imported \(url.lastPathComponent)" : "That file isn't a Wisp settings file."
    }
}

// MARK: - Look

private struct LookPage: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var codeMessage: String?

    var body: some View {
        Form {
            Section {
                IslandPreview().frame(height: 150).listRowInsets(EdgeInsets())
            }
            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(Theme.all) { t in ThemeSwatch(theme: t, selected: prefs.c.themeID == t.id) { prefs.c.themeID = t.id } }
                }
                .padding(.vertical, 4)
                Toggle("Use my own accent", isOn: $prefs.c.useCustomAccent)
                if prefs.c.useCustomAccent {
                    ColorPicker("Accent", selection: Binding(get: { .hex(prefs.c.customAccent) }, set: { prefs.c.customAccent = $0.hexString }), supportsOpacity: false)
                }
                Toggle("Frosted glass", isOn: $prefs.c.glass)
                Picker("Typeface", selection: $prefs.c.fontStyle) {
                    ForEach(FontStyle.allCases) { Text($0.label).font(.system(size: 12, design: $0.design)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Feel") {
                Picker("Motion", selection: $prefs.c.motion) {
                    ForEach(Motion.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Glow under the notch while Claude works", isOn: $prefs.c.glow)
                Toggle("Drop shadow", isOn: $prefs.c.shadow)
                Toggle("Tint music bits from the album art", isOn: $prefs.c.tintFromArtwork)
                Toggle("Tiles wiggle in edit mode", isOn: $prefs.c.jiggleInEditMode)
                Toggle("Confetti when Claude finishes", isOn: $prefs.c.celebrate)
            }
            Section("Share your look") {
                HStack {
                    Button("Copy look code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prefs.c.themeCode, forType: .string)
                        codeMessage = "Copied. Paste it anywhere — friends can apply it with “Paste look code”."
                    }
                    Button("Paste look code") {
                        let text = NSPasteboard.general.string(forType: .string) ?? ""
                        var c = prefs.c
                        if c.apply(themeCode: text) { prefs.c = c; codeMessage = "Look applied ✨" }
                        else { codeMessage = "The clipboard doesn't hold a wisp-look code." }
                    }
                }
                if let codeMessage { Text(codeMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(theme.background)
                    if !theme.wash.isEmpty { RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: theme.wash, startPoint: .topLeading, endPoint: .bottomTrailing)) }
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(theme.surface).frame(width: 16, height: 16)
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                    }
                }
                .frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? theme.accent : .gray.opacity(0.3), lineWidth: selected ? 2.5 : 1))
                Text(theme.name).font(.caption).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A live, scaled-down island so changes show up as you make them.
struct IslandPreview: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        let c = prefs.c
        let t = c.theme
        ZStack(alignment: .top) {
            LinearGradient(colors: [.hex("#4B6CB7"), .hex("#182848")], startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.black.opacity(0.25)).frame(height: 14)
            VStack(spacing: 0) {
                HStack {
                    Text("Home  ·  Claude").font(.system(size: 9, design: c.font)).foregroundStyle(.white.opacity(0.8))
                    Spacer(minLength: 70)
                    if c.mascotEnabled { MascotView(size: 16) }
                }
                .padding(.horizontal, 12).frame(height: 18)
                .background(c.style == .notch ? Color.black : .clear)
                HStack(spacing: 5) {
                    ForEach(c.tiles.prefix(4)) { tile in
                        RoundedRectangle(cornerRadius: 8).fill(t.surface)
                            .frame(width: CGFloat(tile.span) * 40 + CGFloat(tile.span - 1) * 5)
                            .overlay(Image(systemName: tile.kind.symbol).font(.system(size: 11)).foregroundStyle(c.accent))
                    }
                }
                .padding(8)
            }
            .frame(width: 300, height: 100)
            .background(ZStack { t.background; if !t.wash.isEmpty { LinearGradient(colors: t.wash, startPoint: .topLeading, endPoint: .bottomTrailing) } })
            .clipShape(IslandShape(top: c.style == .notch ? 6 : 0, bottom: c.cornerRadius * 0.5, floating: c.style == .floating))
            .shadow(color: c.glow ? c.accent.opacity(0.5) : .clear, radius: 10)
            .padding(.top, c.style == .floating ? 20 : 0)
            .font(.system(size: 10, design: c.font))
        }
        .environment(\.look, c.look)
    }
}

// MARK: - Island & wings

private struct IslandPage: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        Form {
            Section("Shape") {
                Picker("Style", selection: $prefs.c.style) {
                    ForEach(IslandStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(prefs.c.style == .notch ? "Grows out of the camera notch. On screens without one, Wisp draws a notch for you."
                                              : "Floats just under the menu bar, like a dynamic island.")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $prefs.c.islandWidth, in: 520...900, step: 10) { Text("Width \(Int(prefs.c.islandWidth))") }
                Slider(value: $prefs.c.islandHeight, in: 150...320, step: 2) { Text("Height \(Int(prefs.c.islandHeight))") }
                Slider(value: $prefs.c.cornerRadius, in: 8...40, step: 1) { Text("Corners \(Int(prefs.c.cornerRadius))") }
                Slider(value: $prefs.c.fakeNotchWidth, in: 120...320, step: 2) { Text("Pretend notch \(Int(prefs.c.fakeNotchWidth))") }
            }
            Section("Wings") {
                Picker("Show wings", selection: $prefs.c.wingMode) {
                    ForEach(WingMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Left of the camera", selection: $prefs.c.leftWing) {
                    ForEach(WingContent.allCases) { Text($0.label).tag($0) }
                }
                Picker("Right of the camera", selection: $prefs.c.rightWing) {
                    ForEach(WingContent.allCases) { Text($0.label).tag($0) }
                }
                Slider(value: $prefs.c.wingWidth, in: 50...140, step: 2) { Text("Wing width \(Int(prefs.c.wingWidth))") }
                Stepper("Meeting heads-up: \(prefs.c.meetingLead) min before", value: $prefs.c.meetingLead, in: 1...30)
            }
        }
    }
}

// MARK: - The wisp

private struct WispPage: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var previewMood: Mood?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 24) {
                    MascotView(size: 110, mood: previewMood, showCaption: true)
                        .frame(width: 140, height: 150)
                        .background(RoundedRectangle(cornerRadius: 20).fill(prefs.c.theme.background))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try a mood").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 6) {
                            Button("Live") { previewMood = nil }
                            ForEach(Mood.allCases, id: \.self) { m in Button(m.rawValue.capitalized) { previewMood = m } }
                        }
                    }
                }
            }
            Section("Who they are") {
                Toggle("Show your wisp", isOn: $prefs.c.mascotEnabled)
                TextField("Name", text: $prefs.c.mascotName)
                Picker("Shape", selection: $prefs.c.mascotStyle) {
                    ForEach(MascotStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Personality", selection: $prefs.c.personality) {
                    ForEach(Personality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(personalityNote).font(.caption).foregroundStyle(.secondary)
                Toggle("Little speech captions", isOn: $prefs.c.mascotSpeaks)
                Toggle("Eyes follow your pointer", isOn: $prefs.c.eyesFollowCursor)
                Toggle("Reacts when you poke it (try five quick clicks)", isOn: $prefs.c.pokeable)
                Toggle("Say hi when Wisp starts", isOn: $prefs.c.greetOnLaunch)
            }
            Section("Wardrobe") {
                Picker("Outfit", selection: $prefs.c.outfit) {
                    ForEach(Outfit.allCases) { Text($0.label).tag($0) }
                }
                if prefs.c.outfit == .seasonal {
                    Text("Today: \(Outfit.resolved(.seasonal, musicPlaying: MusicService.shared.isPlaying).label). Witch hat in late October, Santa hat in December, party hat for New Year, headphones while music plays.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(Outfit.allCases.filter { $0 != .seasonal }) { o in
                        Button { prefs.c.outfit = o } label: {
                            MascotView(size: 44, mood: .idle, outfit: o)
                                .padding(2)
                                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(prefs.c.outfit == o ? prefs.c.accent : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(o.label)
                    }
                }
            }
            Section("Out and about") {
                Toggle("Let \(prefs.c.mascotName) roam the desktop", isOn: $prefs.c.desktopBuddy)
                Text("A floating friend you can drag anywhere. Double-click it to open the island, right-click to change its outfit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Color") {
                Picker("Color", selection: $prefs.c.mascotColor) {
                    ForEach(MascotColor.allCases) { Text($0.label).tag($0) }
                }
                if prefs.c.mascotColor == .custom {
                    ColorPicker("Custom color", selection: Binding(get: { .hex(prefs.c.mascotHex) }, set: { prefs.c.mascotHex = $0.hexString }), supportsOpacity: false)
                }
            }
        }
    }

    private var personalityNote: String {
        switch prefs.c.personality {
        case .calm: "Moves slowly, naps after a few quiet minutes."
        case .lively: "Bouncy and quick, rarely sleeps."
        case .sleepy: "Dozes off after 30 seconds of quiet. Wakes up for Claude."
        }
    }
}

// MARK: - Claude Code

private struct ClaudePage: View {
    @EnvironmentObject private var prefs: Prefs
    @ObservedObject private var hub = ClaudeHub.shared
    @State private var refresh = 0
    @State private var sheet: ConnectChoice?
    @State private var message: String?
    @State private var newTool = "Bash"
    @State private var newPattern = ""

    var body: some View {
        Form {
            Section {
                AgentRow(target: .claude, refresh: refresh) { sheet = ConnectChoice(target: .claude, connect: $0) }
                if ClaudeConnector.Target.codex.isInstalled {
                    AgentRow(target: .codex, refresh: refresh) { sheet = ConnectChoice(target: .codex, connect: $0) }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Toggle("Listen to coding agents", isOn: $prefs.c.claudeEnabled)
                Text("If Wisp is closed, your agents just ask in the terminal as always.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Plan usage") {
                LabeledContent("Status line bridge", value: ClaudeConnector.statusLineConnected ? "On" : "Off (turn it on when you connect)")
                if let f = hub.usage.fiveHour { LabeledContent("5-hour window", value: "\(Int(f.percent))% used" + (f.resetsAt.map { " · resets in \($0.timeIntervalSinceNow.short)" } ?? "")) }
                if let w = hub.usage.sevenDay { LabeledContent("Weekly", value: "\(Int(w.percent))% used" + (w.resetsAt.map { " · resets in \($0.timeIntervalSinceNow.short)" } ?? "")) }
                Stepper("Warn me at \(prefs.c.usageWarn)% of a limit (and at 95%)", value: $prefs.c.usageWarn, in: 50...95, step: 5)
                Stepper("Warn when a session's context is \(prefs.c.contextWarn)% full", value: $prefs.c.contextWarn, in: 50...95, step: 5)
                Text("Claude Code hands the status line your 5-hour and weekly limits (Pro and Max plans), the model, context and cost. Wisp reads them there, on your Mac, and keeps any status line you already had.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                Toggle("Open the island when Claude needs you", isOn: $prefs.c.openOnPermission)
                Toggle("Guard risky commands (rm -rf, force-push, DROP TABLE, sudo…)", isOn: $prefs.c.riskGuard)
                Text("Risky requests are never auto-allowed, can't be approved with a shortcut, and need a press-and-hold on Allow.")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $prefs.c.permissionTimeout, in: 15...600, step: 15) {
                    Text("Hand back to the terminal after \(Int(prefs.c.permissionTimeout))s")
                }
                Picker("“Always” saves to", selection: $prefs.c.alwaysTarget) {
                    ForEach(AlwaysTarget.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Auto-allow read-only tools (Read, Grep, Glob…)", isOn: $prefs.c.autoAllowReadOnly)
            }
            Section("Wisp's allow rules") {
                if prefs.c.rules.isEmpty {
                    Text("None yet. “Always” adds one when it saves to Wisp.").foregroundStyle(.secondary)
                }
                ForEach(prefs.c.rules) { r in
                    HStack {
                        Text(r.tool).fontWeight(.medium)
                        Text(r.pattern.isEmpty ? "anything" : r.pattern).font(.system(.caption, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Text(r.project.isEmpty ? "all projects" : URL(fileURLWithPath: r.project).lastPathComponent).foregroundStyle(.secondary)
                        Button { prefs.c.rules.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Tool", text: $newTool).frame(width: 110)
                    TextField("Starts with (optional), e.g. npm test", text: $newPattern)
                    Button("Add") {
                        guard !newTool.isEmpty else { return }
                        prefs.c.rules.append(AllowRule(tool: newTool, pattern: newPattern))
                        newPattern = ""
                    }
                }
            }
            Section("While Claude works") {
                Toggle("Peek in the wings when a turn finishes", isOn: $prefs.c.peekOnDone)
                Toggle("Show diffs for edited files", isOn: $prefs.c.showDiffs)
                Toggle("Quiet hours (no sounds, no pop-ups)", isOn: $prefs.c.quietHours)
                if prefs.c.quietHours {
                    Stepper("From \(prefs.c.quietStart):00", value: $prefs.c.quietStart, in: 0...23)
                    Stepper("Until \(prefs.c.quietEnd):00", value: $prefs.c.quietEnd, in: 0...23)
                }
            }
        }
        .sheet(item: $sheet) { choice in
            ConnectSheet(target: choice.target, connect: choice.connect) { result in
                message = result
                refresh += 1
                sheet = nil
            }
        }
    }
}

private struct AgentRow: View {
    let target: ClaudeConnector.Target
    let refresh: Int
    let open: (Bool) -> Void
    var body: some View {
        let status = ClaudeConnector.status(target)
        HStack {
            Image(systemName: status == .connected ? "checkmark.seal.fill" : "bolt.horizontal.circle")
                .font(.title2).foregroundStyle(status == .connected ? .green : .orange)
            VStack(alignment: .leading) {
                Text("\(target.name): " + (status == .connected ? "connected" : status == .partial ? "partly connected" : "not connected")).font(.headline)
                Text("Hook in \(Paths.pretty(target.file.path))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status != .disconnected { Button("Disconnect…") { open(false) } }
            Button(status == .connected ? "Reconnect…" : "Connect…") { open(true) }.buttonStyle(.borderedProminent)
        }
        .id(refresh)
    }
}

private struct ConnectChoice: Identifiable {
    let target: ClaudeConnector.Target
    let connect: Bool
    var id: String { target.name + "\(connect)" }
}

private struct ConnectSheet: View {
    let target: ClaudeConnector.Target
    let connect: Bool
    let done: (String?) -> Void
    @State private var statusLine = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(connect ? "Connect \(target.name)" : "Disconnect \(target.name)").font(.title2.weight(.semibold))
            Text(connect
                 ? "Wisp will copy its hook script to ~/Library/Application Support/Wisp and add it to these events in \(Paths.pretty(target.file.path)). Your other settings stay as they are; a dated backup is saved next to the file. Key order and spacing in the file may change."
                 : "Wisp will remove only its own entries from \(Paths.pretty(target.file.path)) and give back any status line you had before. A dated backup is saved first.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if connect && target.hasStatusLine {
                Toggle("Also show plan usage, model, context and cost (routes the status line through Wisp; an existing one keeps working)", isOn: $statusLine)
            }
            Text("After this change:").font(.headline)
            ScrollView {
                Text(ClaudeConnector.preview(target, connect: connect, statusLine: statusLine))
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                Button(connect ? "Connect" : "Disconnect") {
                    do {
                        let backup = try ClaudeConnector.apply(target, connect: connect, statusLine: statusLine)
                        done((connect ? "Connected. " : "Disconnected. ") + (backup.map { "Backup: \(Paths.pretty($0.path))" } ?? "") + (connect ? " New \(target.name) sessions will show up in the notch." : ""))
                    } catch {
                        done("Couldn't write the file: \(error.localizedDescription)")
                    }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
    }
}

// MARK: - Tiles

private struct TilesPage: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var newZone = ""

    var body: some View {
        Form {
            Section {
                List {
                    ForEach($prefs.c.tiles) { $tile in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Label(tile.kind.title, systemImage: tile.kind.symbol)
                            Spacer()
                            Picker("", selection: $tile.span) {
                                Text("Small").tag(1); Text("Wide").tag(2); Text("Extra wide").tag(3)
                            }
                            .labelsHidden().frame(width: 120)
                            Button { prefs.c.tiles.removeAll { $0.id == tile.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                    }
                    .onMove { prefs.c.tiles.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 200)
                Menu("Add a tile") {
                    ForEach(TileKind.allCases) { k in
                        Button { prefs.c.tiles.append(TileConfig(kind: k, span: k.defaultSpan)) } label: { Label(k.title, systemImage: k.symbol) }
                    }
                }
                Text("Drag to reorder. You can also edit tiles right in the island with the sliders button.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Music") {
                Toggle("Synced lyrics", isOn: $prefs.c.lyrics)
                Text("Lyrics come from lrclib.net, which gets the song's title, artist, album and length. Pick “Synced lyrics” for a wing to see them beside the camera.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Focus timer") {
                Stepper("Focus: \(prefs.c.focusMinutes) min", value: $prefs.c.focusMinutes, in: 5...120, step: 5)
                Stepper("Break: \(prefs.c.breakMinutes) min", value: $prefs.c.breakMinutes, in: 1...60)
            }
            Section("Weather") {
                LabeledContent("City", value: prefs.c.city.isEmpty ? "Not set (type it in the tile)" : prefs.c.city)
                Toggle("Fahrenheit", isOn: $prefs.c.fahrenheit).onChange(of: prefs.c.fahrenheit) { _, _ in WeatherService.shared.refresh() }
                Text("Weather comes from open-meteo.com, which gets only the coordinates of your city.").font(.caption).foregroundStyle(.secondary)
            }
            Section("World clock") {
                ForEach(prefs.c.zones, id: \.self) { z in
                    HStack {
                        Text(WorldClockTile.city(z)); Text(z).foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button { prefs.c.zones.removeAll { $0 == z } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Time zone, e.g. Europe/Paris", text: $newZone)
                    Button("Add") {
                        if let match = TimeZone.knownTimeZoneIdentifiers.first(where: { $0.localizedCaseInsensitiveContains(newZone.replacingOccurrences(of: " ", with: "_")) }), !newZone.isEmpty {
                            prefs.c.zones.append(match); newZone = ""
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sound

private struct SoundPage: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        Form {
            Section("Pack") {
                Picker("Sounds", selection: $prefs.c.soundPack) {
                    ForEach(SoundPack.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Slider(value: $prefs.c.volume, in: 0...1) { Text("Volume") }
                HStack {
                    ForEach([("Needs you", Sounds.Cue.attention), ("Done", .success), ("Oops", .error), ("Timer", .timer), ("Drop", .pop)], id: \.0) { item in
                        Button(item.0) { Sounds.shared.play(item.1) }
                    }
                }
                Text("Every sound is synthesized on your Mac. No audio files ship with Wisp.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Use your own sounds") {
                Text("Drop files named needs-you, done, oops, timer, drop or open (.wav, .mp3, .aiff, .m4a) into the sounds folder. They replace the built-in ones.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open sounds folder") { NSWorkspace.shared.open(Sounds.folder) }
                    Button("Reload") { Sounds.shared.reloadCustom() }
                }
            }
            Section("Play a sound when") {
                Toggle("Claude needs permission", isOn: $prefs.c.soundOnPermission)
                Toggle("Claude finishes a turn", isOn: $prefs.c.soundOnDone)
                Toggle("A tool fails", isOn: $prefs.c.soundOnError)
                Toggle("The focus timer ends", isOn: $prefs.c.soundOnTimer)
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPage: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.label) {
                        ShortcutRecorder(combo: Binding(
                            get: { prefs.c.hotkeys[action.rawValue] },
                            set: { prefs.c.hotkeys[action.rawValue] = $0; Hotkeys.shared.reload() }))
                    }
                }
            } footer: {
                Text("Permission shortcuts only work while a request is on screen, so they never take keys from other apps. Shortcuts need at least one of ⌃ ⌥ ⇧ ⌘.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Restore defaults") { prefs.c.hotkeys = KeyCombo.defaults; Hotkeys.shared.reload() }
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? "Type a shortcut…" : (combo?.display ?? "None")) { recording ? stop() : start() }
                .frame(minWidth: 130)
            if combo != nil && !recording {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        Hotkeys.shared.suspend(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            if let c = Hotkeys.combo(from: e) { combo = c; stop() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Hotkeys.shared.suspend(false)
    }
}

// MARK: - About

private struct AboutPage: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        VStack(spacing: 14) {
            MascotView(size: 120, showCaption: true)
            Text("Wisp").font(.system(size: 30, weight: .semibold, design: prefs.c.font))
            Text("A little spirit that lives in your notch and keeps an eye on Claude Code.")
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show Wisp's data folder") { NSWorkspace.shared.open(Paths.support) }
                Button("Run the welcome again") { AppDelegate.shared?.showOnboarding() }
            }
            Text("No account, no analytics. The only network calls are weather (open-meteo.com) and Spotify cover art, and only if you use those tiles.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
