import AppKit
import SwiftUI

// MARK: - Claude

struct ClaudeTile: View {
    let span: Int
    @EnvironmentObject private var model: IslandModel
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared

    var body: some View {
        Button { model.tab = .claude } label: {
            HStack(spacing: 10) {
                MascotView(size: span == 1 ? 50 : 58)
                if span > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        TileTitle(text: "Claude Code", symbol: "sparkles")
                        if let h = hub.headline {
                            Text(h.text).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        } else {
                            Text(hub.ordered.isEmpty ? "Waiting for a session" : "All quiet").font(.system(size: 13)).foregroundStyle(look.theme.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("Today · \(hub.stats.prompts) prompts · \(hub.stats.edits) edits · \(hub.stats.tokens.compact) tok")
                            .font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Music

struct MusicTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @ObservedObject private var music = MusicService.shared

    var body: some View {
        if let t = music.track {
            HStack(spacing: 10) {
                artwork.frame(width: span == 1 ? nil : 70)
                if span > 1 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(t.artist).font(.system(size: 11)).foregroundStyle(look.theme.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                            if let line = LyricsService.shared.current(at: tl.date) {
                                Text(line).font(.system(size: 11, weight: .medium)).foregroundStyle(tint).lineLimit(1)
                                    .id(line).transition(.opacity)
                            }
                        }
                        ProgressView(value: min(t.position, t.duration), total: t.duration)
                            .progressViewStyle(.linear).tint(tint).controlSize(.mini)
                        controls
                    }
                }
            }
            .overlay(alignment: .bottom) { if span == 1 { controls.padding(4).background(.ultraThinMaterial, in: Capsule()) } }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 22, weight: .light))
                Text("Play something in Spotify or Music").font(.system(size: 10)).multilineTextAlignment(.center)
            }
            .foregroundStyle(look.theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tint: Color { prefs.c.tintFromArtwork ? (music.tint ?? look.accent) : look.accent }

    @ViewBuilder private var artwork: some View {
        if let img = music.artwork {
            Image(nsImage: img).resizable().aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.25))
                .aspectRatio(1, contentMode: .fit)
                .overlay(Image(systemName: "music.note").foregroundStyle(tint))
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { music.previous() } label: { Image(systemName: "backward.fill") }
            Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15)) }
            Button { music.next() } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }
}

// MARK: - Calendar

struct CalendarTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var cal = CalendarService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TileTitle(text: "Next", symbol: "calendar")
            if !cal.hasAccess {
                Spacer(minLength: 0)
                Button("Allow calendar") { cal.requestAccess() }.buttonStyle(IslandButton(prominent: true))
                Text("Wisp reads events only on this Mac.").font(.system(size: 9)).foregroundStyle(look.theme.secondary)
            } else if let m = cal.next {
                HStack(spacing: 6) {
                    Capsule().fill(m.color).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Text(when(m)).font(.system(size: 11)).foregroundStyle(look.theme.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if span > 2 {
                    ForEach(cal.later, id: \.start) { e in
                        Text("\(e.start.formatted(date: .omitted, time: .shortened))  \(e.title)")
                            .font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let url = m.joinURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Join", systemImage: "video.fill").font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(look.accent))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Spacer(minLength: 0)
                Text("Nothing else today 🎉").font(.system(size: 12)).foregroundStyle(look.theme.secondary)
                Spacer(minLength: 0)
            }
        }
        .onAppear { cal.refresh() }
    }

    private func when(_ m: CalendarService.Meeting) -> String {
        let time = m.start.formatted(date: .omitted, time: .shortened)
        if m.start <= .now { return "Now · until \(m.end.formatted(date: .omitted, time: .shortened))" }
        return "\(time) · in \(m.start.timeIntervalSinceNow.short)"
    }
}

// MARK: - Weather

struct WeatherTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @ObservedObject private var weather = WeatherService.shared
    @State private var city = ""

    var body: some View {
        if let w = weather.now, !prefs.c.city.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                TileTitle(text: w.place, symbol: "location.fill")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: WeatherService.symbol(w.code, day: w.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 22))
                    Text("\(Int(w.temp.rounded()))°").font(.system(size: 28, weight: .light))
                }
                Text(span > 1 ? "\(WeatherService.words(w.code)) · H \(Int(w.high.rounded()))° L \(Int(w.low.rounded()))°" : WeatherService.words(w.code))
                    .font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                TileTitle(text: "Weather", symbol: "cloud.sun")
                Spacer(minLength: 0)
                TextField("Your city", text: $city)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .onSubmit { weather.setCity(city) }
                Text(weather.error ?? "Press Return").font(.system(size: 9)).foregroundStyle(look.theme.secondary)
            }
        }
    }
}

// MARK: - Focus timer

struct TimerTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Ring(progress: timer.progress, color: timer.mode == .focus ? look.accent : Mood.happy.color, line: 5)
                VStack(spacing: 0) {
                    Text(timer.label).font(.system(size: 15, weight: .medium)).monospacedDigit()
                    Text(timer.mode == .focus ? "focus" : "break").font(.system(size: 9)).foregroundStyle(look.theme.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onTapGesture { timer.toggle() }
            if span > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Button(timer.running ? "Pause" : "Start") { timer.toggle() }
                        .buttonStyle(IslandButton(prominent: true))
                    HStack(spacing: 4) {
                        Button("Skip") { timer.skip() }
                        Button("Reset") { timer.reset() }
                    }
                    Text("\(timer.rounds) rounds today").font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                }
                .buttonStyle(IslandButton())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clipboard

struct ClipboardTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var clip = ClipboardService.shared
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TileTitle(text: "Clipboard", symbol: "doc.on.clipboard")
                if !clip.items.isEmpty {
                    Button { clip.clear() } label: { Image(systemName: "trash").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(look.theme.secondary)
                }
            }
            if clip.items.isEmpty {
                Spacer(minLength: 0)
                Text("Copy something and it shows up here").font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(clip.items.prefix(12), id: \.self) { item in
                            Button {
                                clip.copy(item)
                                copied = item
                            } label: {
                                Text(item.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11)).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 3).padding(.horizontal, 6)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(copied == item ? look.accent.opacity(0.3) : look.theme.text.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shelf

struct ShelfTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TileTitle(text: "Shelf", symbol: "tray")
                if !shelf.files.isEmpty {
                    Button { shelf.clear() } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(look.theme.secondary)
                }
            }
            if shelf.files.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 20, weight: .light))
                    Text("Drop files on the notch").font(.system(size: 9)).multilineTextAlignment(.center)
                }
                .foregroundStyle(look.theme.secondary).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.files, id: \.self) { url in
                            VStack(spacing: 2) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 40, height: 40)
                                Text(url.lastPathComponent).font(.system(size: 9)).lineLimit(1).frame(width: 52)
                            }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            .contextMenu {
                                Button("Open") { NSWorkspace.shared.open(url) }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button("AirDrop…") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) }
                                Divider()
                                Button("Remove from shelf") { shelf.remove(url) }
                            }
                            .help(Paths.pretty(url.path))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - To-do

struct TodoTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TileTitle(text: "To-do", symbol: "checklist")
                if prefs.c.todos.contains(where: \.done) {
                    Button { prefs.c.todos.removeAll(where: \.done) } label: {
                        if span > 1 { Text("Clear done") } else { Image(systemName: "trash") }
                    }
                    .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(look.theme.secondary).help("Clear done")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach($prefs.c.todos) { $item in
                        HStack(spacing: 6) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? look.accent : look.theme.secondary)
                                .onTapGesture { withAnimation { item.done.toggle() } }
                            Text(item.text).font(.system(size: 11)).strikethrough(item.done).opacity(item.done ? 0.5 : 1).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain).font(.system(size: 11))
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(look.theme.text.opacity(0.07)))
                .onSubmit {
                    let t = draft.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    prefs.c.todos.append(TodoItem(text: t))
                    draft = ""
                }
        }
    }
}

// MARK: - World clock

struct WorldClockTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.everyMinute) { tl in
            VStack(alignment: .leading, spacing: 5) {
                TileTitle(text: "World", symbol: "globe")
                Spacer(minLength: 0)
                ForEach(prefs.c.zones.prefix(span + 1), id: \.self) { id in
                    if let tz = TimeZone(identifier: id) {
                        HStack {
                            let hour = Calendar.current.dateComponents(in: tz, from: tl.date).hour ?? 12
                            Image(systemName: (7..<19).contains(hour) ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: 9)).foregroundStyle((7..<19).contains(hour) ? .yellow : look.theme.secondary)
                            Text(Self.city(id)).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text(Self.time(tl.date, tz)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    static func city(_ id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    static func time(_ date: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - System

struct SystemTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var stats = SystemStats.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TileTitle(text: "System", symbol: "cpu")
            Spacer(minLength: 0)
            bar("CPU", stats.cpu)
            bar("Memory", stats.memory)
            if let b = stats.battery {
                bar(stats.charging ? "Charging" : "Battery", Double(b) / 100)
            }
            if span > 1 {
                Sparkline(values: stats.cpuHistory, color: look.accent).frame(height: 18)
            }
        }
    }

    private func bar(_ label: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                Spacer()
                Text("\(Int(v * 100))%").font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
            GeometryReader { g in
                Capsule().fill(look.theme.text.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(v > 0.85 ? Color.red : look.accent).frame(width: g.size.width * min(1, max(0.02, v)))
                    }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Day progress

struct ProgressTile: View {
    let span: Int
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            VStack(alignment: .leading, spacing: 5) {
                TileTitle(text: "Progress", symbol: "chart.bar")
                Spacer(minLength: 0)
                row("Day", fraction(.day, tl.date))
                row("Week", fraction(.weekOfYear, tl.date))
                row("Month", fraction(.month, tl.date))
                row("Year", fraction(.year, tl.date))
            }
        }
    }

    private func row(_ label: String, _ v: Double) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9)).foregroundStyle(look.theme.secondary).frame(width: 30, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(look.theme.text.opacity(0.1))
                    .overlay(alignment: .leading) { Capsule().fill(look.accent).frame(width: g.size.width * v) }
            }
            .frame(height: 4)
            if span > 1 { Text("\(Int(v * 100))%").font(.system(size: 9)).monospacedDigit().frame(width: 28, alignment: .trailing) }
        }
    }

    private func fraction(_ unit: Calendar.Component, _ date: Date) -> Double {
        guard let interval = Calendar.current.dateInterval(of: unit, for: date) else { return 0 }
        return date.timeIntervalSince(interval.start) / interval.duration
    }
}

// MARK: - Switches

struct TogglesTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared
    @State private var awake = SystemSwitches.keepingAwake
    @State private var dark = SystemSwitches.isDarkMode
    @State private var micMuted = MicMute.isMuted

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: span == 1 ? 2 : span == 2 ? 4 : 5)
        LazyVGrid(columns: columns, spacing: 6) {
            toggle("cup.and.saucer.fill", "Awake", awake) { awake.toggle(); SystemSwitches.keepAwake(awake) }
            toggle("circle.lefthalf.filled", "Dark", dark) { dark.toggle(); SystemSwitches.toggleDarkMode() }
            toggle(micMuted ? "mic.slash.fill" : "mic.fill", "Mic", micMuted) { micMuted.toggle(); MicMute.set(micMuted) }
            toggle("moon.zzz.fill", "Snooze", hub.isSnoozed) { hub.snooze(minutes: hub.isSnoozed ? nil : 30) }
            toggle(prefs.c.soundPack == .off ? "speaker.slash.fill" : "speaker.wave.2.fill", "Sound", prefs.c.soundPack != .off) {
                prefs.c.soundPack = prefs.c.soundPack == .off ? .chime : .off
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func toggle(_ symbol: String, _ label: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(on ? look.accent : look.theme.text.opacity(0.1)))
                    .foregroundStyle(on ? Color.black : look.theme.text)
                Text(label).font(.system(size: 9)).foregroundStyle(look.theme.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wisp says

struct FortuneTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @State private var index = Int.random(in: 0..<FortuneTile.lines.count)

    static let lines = [
        "Small commits, big smiles.",
        "If it's hard to name, it's doing two things.",
        "Today's bug is tomorrow's test.",
        "Read the error message. Then read it again.",
        "Delete code with confidence: git remembers.",
        "Drink some water. Claude can wait a sec.",
        "The best code is the code you didn't write.",
        "Naming things is hard. Naming me was easy.",
        "Ship it, then make it shine.",
        "A walk fixes more bugs than a debugger.",
        "Write the README first. Future you says thanks.",
        "You can't refactor what you're afraid of. Add a test.",
        "Every expert was once stuck on a semicolon.",
        "Rubber duck busy? I'm a flame, I listen too.",
        "Ask Claude why, not just how.",
        "Close a tab. Feel lighter.",
        "Good logs are love letters to 3am you.",
        "Stretch your wrists. I'll keep the notch warm.",
    ]

    var body: some View {
        HStack(spacing: 8) {
            if span > 1 { MascotView(size: 44) }
            VStack(alignment: .leading, spacing: 4) {
                TileTitle(text: "\(prefs.c.mascotName) says", symbol: "quote.bubble")
                Spacer(minLength: 0)
                Text(Self.lines[index]).font(.system(size: span > 1 ? 13 : 11, weight: .medium)).lineLimit(4)
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { index = (index + 1) % Self.lines.count } }
    }
}
