import AppKit
import SwiftUI

// MARK: - Plan usage

struct UsageTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared

    var body: some View {
        let u = hub.usage
        VStack(alignment: .leading, spacing: 6) {
            TileTitle(text: "Claude plan", symbol: "gauge.with.dots.needle.33percent")
            if u.isKnown {
                HStack(spacing: 8) {
                    gauge("5 hours", u.fiveHour)
                    if span > 1 { gauge("Week", u.sevenDay) }
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
                Text(ClaudeConnector.statusLineConnected
                     ? "Shows up after Claude's next reply (Pro and Max plans)."
                     : "Reconnect Claude Code with plan usage on, in Settings.")
                    .font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func gauge(_ label: String, _ w: PlanUsage.Window?) -> some View {
        let pct = w?.percent ?? 0
        let color: Color = pct >= 95 ? Mood.sad.color : pct >= 80 ? Mood.attention.color : look.accent
        VStack(spacing: 4) {
            ZStack {
                Ring(progress: pct / 100, color: color, line: 5)
                Text(w == nil ? "–" : "\(Int(pct))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 48, height: 48)
            Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text(w?.resetsAt.map { "resets in \($0.timeIntervalSinceNow.short)" } ?? " ")
                .font(.system(size: 9)).foregroundStyle(look.theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dev servers

struct DevServersTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var dev = DevServers.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TileTitle(text: "Listening on localhost", symbol: "server.rack")
            if dev.servers.isEmpty {
                Spacer(minLength: 0)
                Text("No dev servers running").font(.system(size: 11)).foregroundStyle(look.theme.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(dev.servers) { s in
                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Button { NSWorkspace.shared.open(URL(string: "http://localhost:\(s.port)")!) } label: {
                                    Text(":\(s.port)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                                }
                                .buttonStyle(.plain)
                                .help("Open http://localhost:\(s.port)")
                                Text(s.command).font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                                Button { dev.stop(s) } label: { Image(systemName: "stop.circle").font(.system(size: 11)) }
                                    .buttonStyle(.plain).foregroundStyle(look.theme.secondary).help("Stop \(s.command)")
                            }
                        }
                    }
                }
            }
        }
        .onAppear { dev.setActive(true) }
        .onDisappear { dev.setActive(false) }
    }
}

// MARK: - Apple Shortcuts

struct ShortcutsTile: View {
    let span: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @ObservedObject private var shortcuts = ShortcutsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TileTitle(text: "Shortcuts", symbol: "square.stack.3d.up")
                Menu {
                    if shortcuts.all.isEmpty { Text("Loading your shortcuts…") }
                    ForEach(shortcuts.all, id: \.self) { name in
                        Button {
                            if prefs.c.shortcuts.contains(name) { prefs.c.shortcuts.removeAll { $0 == name } }
                            else { prefs.c.shortcuts.append(name) }
                        } label: {
                            if prefs.c.shortcuts.contains(name) { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                } label: { Image(systemName: "plus.circle").font(.system(size: 11)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
            }
            if prefs.c.shortcuts.isEmpty {
                Spacer(minLength: 0)
                Text("Pin shortcuts with +").font(.system(size: 11)).foregroundStyle(look.theme.secondary)
                Spacer(minLength: 0)
            } else {
                FlowRow(spacing: 5) {
                    ForEach(prefs.c.shortcuts, id: \.self) { name in
                        Button { shortcuts.run(name) } label: {
                            HStack(spacing: 4) {
                                if shortcuts.running == name { ProgressView().controlSize(.mini) }
                                Text(name).lineLimit(1)
                            }
                        }
                        .buttonStyle(IslandButton(active: shortcuts.running == name))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { if shortcuts.all.isEmpty { shortcuts.load() } }
    }
}

// MARK: - Camera mirror

struct CameraTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var camera = CameraMirror.shared

    var body: some View {
        ZStack {
            if camera.denied {
                VStack(spacing: 4) {
                    Image(systemName: "video.slash").font(.system(size: 18))
                    Text("Allow the camera in System Settings").font(.system(size: 9)).multilineTextAlignment(.center)
                }
                .foregroundStyle(look.theme.secondary)
            } else {
                CameraPreview().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(-4)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
