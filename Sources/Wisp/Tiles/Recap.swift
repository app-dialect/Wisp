import AppKit
import SwiftUI

/// Seven days of you and Claude, as a tile and as a picture you can share.
struct RecapTile: View {
    let span: Int
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared

    var body: some View {
        let week = hub.week
        let top = max(1, week.map(\.prompts).max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TileTitle(text: "This week", symbol: "chart.bar.xaxis")
                Button { RecapExport.save() } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(look.theme.secondary).help("Save as an image")
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(week) { d in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(d.day == DayStats.today() ? look.accent : look.accent.opacity(0.45))
                            .frame(height: max(3, CGFloat(d.prompts) / CGFloat(top) * 52))
                        Text(RecapExport.weekday(d.day)).font(.system(size: 8)).foregroundStyle(look.theme.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            let total = RecapExport.total(week)
            Text("\(total.prompts) prompts · \(total.edits) edits · \(total.tokens.compact) tok")
                .font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
        }
    }
}

struct RecapCard: View {
    let week: [DayStats]
    let look: Look
    let name: String

    var body: some View {
        let total = RecapExport.total(week)
        let top = max(1, week.map(\.prompts).max() ?? 1)
        let busiest = week.max { $0.prompts < $1.prompts }
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 18) {
                MascotView(size: 120, mood: .happy)
                VStack(alignment: .leading, spacing: 6) {
                    Text("My week with Claude").font(.system(size: 44, weight: .bold, design: look.font))
                    Text("as seen by \(name), the wisp in my notch").font(.system(size: 22, design: look.font)).foregroundStyle(look.theme.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(week) { d in
                    VStack(spacing: 8) {
                        Text("\(d.prompts)").font(.system(size: 18, weight: .medium)).foregroundStyle(look.theme.secondary)
                        RoundedRectangle(cornerRadius: 12).fill(look.accent)
                            .frame(width: 84, height: max(10, CGFloat(d.prompts) / CGFloat(top) * 420))
                        Text(RecapExport.weekday(d.day)).font(.system(size: 20))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                stat("\(total.prompts)", "prompts")
                stat("\(total.tools)", "tool calls")
                stat("\(total.edits)", "file edits")
                stat("\(total.commands)", "commands")
                stat("\(total.approvals)", "approvals")
                stat(total.tokens.compact, "tokens")
            }
            if let b = busiest, b.prompts > 0 {
                Text("Busiest day: \(RecapExport.weekday(b.day, long: true))").font(.system(size: 22, design: look.font))
            }
            Spacer(minLength: 0)
            Text("Wisp · a little spirit for Claude Code").font(.system(size: 18)).foregroundStyle(look.theme.secondary)
        }
        .padding(70)
        .frame(width: 1080, height: 1350)
        .background(ZStack { look.theme.background; LinearGradient(colors: look.theme.wash.isEmpty ? [look.accent.opacity(0.18), .clear] : look.theme.wash, startPoint: .topLeading, endPoint: .bottomTrailing) })
        .foregroundStyle(look.theme.text)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 48, weight: .semibold, design: look.font)).foregroundStyle(look.accent)
            Text(label).font(.system(size: 20)).foregroundStyle(look.theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum RecapExport {
    static func total(_ week: [DayStats]) -> DayStats {
        week.reduce(into: DayStats(day: "week")) { t, d in
            t.sessions += d.sessions; t.prompts += d.prompts; t.tools += d.tools; t.edits += d.edits
            t.commands += d.commands; t.tokens += d.tokens; t.approvals += d.approvals
        }
    }

    static func weekday(_ day: String, long: Bool = false) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return "" }
        f.dateFormat = long ? "EEEE" : "EEEEE"
        return f.string(from: d)
    }

    @MainActor static func save() {
        let c = Prefs.shared.c
        let card = RecapCard(week: ClaudeHub.shared.week, look: c.look, name: c.mascotName)
            .environmentObject(Prefs.shared)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My week with Claude.png"
        panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
