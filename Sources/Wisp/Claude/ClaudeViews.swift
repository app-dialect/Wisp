import SwiftUI

/// The Claude tab: sessions on the left, the selected one's steps, files and reply on the right.
struct ClaudePanel: View {
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared
    @State private var section = 0
    @State private var openFile: String?

    var body: some View {
        let sessions = hub.ordered
        if sessions.isEmpty {
            empty
        } else {
            HStack(spacing: 10) {
                list(sessions).frame(width: 168)
                if let s = hub.selected { detail(s) }
            }
        }
    }

    private var empty: some View {
        HStack(spacing: 16) {
            MascotView(size: 72, showCaption: true)
            VStack(alignment: .leading, spacing: 6) {
                if ClaudeConnector.status() == .connected {
                    Text("No sessions yet").font(.system(size: 15, weight: .semibold))
                    Text("Run `claude` in any terminal. Every step, file and permission shows up here.")
                        .font(.system(size: 12)).foregroundStyle(look.theme.secondary)
                } else {
                    Text("Connect Claude Code").font(.system(size: 15, weight: .semibold))
                    Text("Wisp adds a small hook to ~/.claude/settings.json. You'll see exactly what changes first.")
                        .font(.system(size: 12)).foregroundStyle(look.theme.secondary)
                    Button("Connect…") { AppDelegate.shared?.openSettings(page: .claude) }.controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ sessions: [Session]) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(sessions) { s in
                    let on = hub.selected?.id == s.id
                    Button { hub.selectedID = s.id } label: {
                        HStack(spacing: 7) {
                            PhaseDot(phase: s.phase)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(s.activity).font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? look.theme.surface : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detail(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(s.project).font(.system(size: 14, weight: .semibold))
                Text(Date.now.timeIntervalSince(s.startedAt).short + " · \(s.toolCount) tools" + (s.tokensOut > 0 ? " · \((s.tokensIn + s.tokensOut).compact) tok" : ""))
                    .font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                Spacer()
                Picker("", selection: $section) {
                    Text("Steps").tag(0)
                    Text("Files \(s.files.count)").tag(1)
                    Text("Reply").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.mini).frame(width: 180)
                Menu {
                    Button("Open terminal") { hub.focusTerminal(s.id) }
                    Menu("Snooze alerts") {
                        Button("30 minutes") { hub.snooze(minutes: 30) }
                        Button("1 hour") { hub.snooze(minutes: 60) }
                        Button("Until I turn it back on") { hub.snooze(minutes: 60 * 24 * 365) }
                        if hub.snoozedUntil != nil { Button("Stop snoozing") { hub.snooze(minutes: nil) } }
                    }
                    Divider()
                    Button("Clear finished sessions") { hub.clearFinished() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            }
            Group {
                switch section {
                case 0: steps(s)
                case 1: files(s)
                default: reply(s)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(look.theme.surface))
        }
    }

    private func steps(_ s: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(s.steps.suffix(60).reversed()) { step in
                    HStack(spacing: 7) {
                        Image(systemName: step.symbol).frame(width: 14).foregroundStyle(color(step.status))
                        Text(step.text).font(.system(size: 11, design: step.tool == "Bash" ? .monospaced : prefs.c.font)).lineLimit(1)
                        Spacer(minLength: 0)
                        if step.status == .running { ProgressView().controlSize(.mini) }
                        Text(step.time, format: .dateTime.hour().minute().second())
                            .font(.system(size: 9)).foregroundStyle(look.theme.secondary).monospacedDigit()
                    }
                }
            }
            .padding(10)
        }
    }

    private func files(_ s: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if s.files.isEmpty {
                    Text("No files changed yet").font(.system(size: 11)).foregroundStyle(look.theme.secondary)
                }
                ForEach(s.sortedFiles) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        Button { openFile = openFile == f.path ? nil : f.path } label: {
                            HStack {
                                Image(systemName: openFile == f.path ? "chevron.down" : "chevron.right").font(.system(size: 8))
                                Text(URL(fileURLWithPath: f.path).lastPathComponent).font(.system(size: 11, weight: .medium))
                                Text(Paths.pretty(URL(fileURLWithPath: f.path).deletingLastPathComponent().path))
                                    .font(.system(size: 9)).foregroundStyle(look.theme.secondary).lineLimit(1).truncationMode(.head)
                                Spacer()
                                Text("+\(f.added)").foregroundStyle(.green).font(.system(size: 10, design: .monospaced))
                                Text("−\(f.removed)").foregroundStyle(.red).font(.system(size: 10, design: .monospaced))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: f.path)) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
                        }
                        if openFile == f.path && prefs.c.showDiffs { DiffView(lines: f.lastDiff) }
                    }
                }
            }
            .padding(10)
        }
    }

    private func reply(_ s: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let p = s.prompt {
                    Text("You: " + p).font(.system(size: 11)).foregroundStyle(look.theme.secondary).lineLimit(3)
                }
                if let m = s.lastMessage {
                    Text((try? AttributedString(markdown: m, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m))
                        .font(.system(size: 12)).textSelection(.enabled)
                } else {
                    Text(s.isLive ? "Claude is still working…" : "No reply yet").font(.system(size: 11)).foregroundStyle(look.theme.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(_ st: Step.Status) -> Color {
        switch st {
        case .running: look.accent
        case .ok: .green
        case .failed: .red
        case .auto: .teal
        case .info: look.theme.secondary
        }
    }
}

struct PhaseDot: View {
    let phase: SessionPhase
    var body: some View {
        let c: Color = switch phase {
        case .waiting: Mood.attention.color
        case .working, .thinking, .starting: Mood.thinking.color
        case .done: Mood.happy.color
        case .failed: Mood.sad.color
        case .ended: .gray
        }
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !(phase == .working || phase == .thinking || phase == .waiting))) { tl in
            let pulse = phase == .done || phase == .ended ? 1 : 0.55 + 0.45 * sin(tl.date.timeIntervalSinceReferenceDate * 4)
            Circle().fill(c).frame(width: 8, height: 8).opacity(pulse)
        }
    }
}

struct DiffView: View {
    let lines: [DiffLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.prefix(80)) { l in
                Text((l.kind == .add ? "+ " : l.kind == .remove ? "− " : "  ") + l.text)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(l.kind == .add ? Color.green.opacity(0.16) : l.kind == .remove ? Color.red.opacity(0.16) : .clear)
                    .opacity(l.kind == .same ? 0.6 : 1)
            }
            if lines.count > 80 {
                Text("… \(lines.count - 80) more lines").font(.system(size: 9)).padding(4).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Covers the island while Claude Code waits for a yes or no.
struct PermissionCard: View {
    let request: PendingPermission
    let queued: Int
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @State private var denyNote = ""
    @State private var showNote = false

    var body: some View {
        let hub = ClaudeHub.shared
        let c = prefs.c
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MascotView(size: 40, mood: .attention)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.project) wants to use \(request.tool)").font(.system(size: 14, weight: .semibold))
                    Text(queued > 1 ? "1 of \(queued) waiting" : "Claude Code is waiting for you")
                        .font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                    let total = request.deadline.timeIntervalSince(request.created)
                    let left = max(0, request.deadline.timeIntervalSince(tl.date))
                    ZStack {
                        Ring(progress: left / total, color: Mood.attention.color, line: 2.5)
                        Text("\(Int(left))").font(.system(size: 9, weight: .medium)).monospacedDigit()
                    }
                    .frame(width: 26, height: 26)
                    .help("After this, Claude Code asks in the terminal instead")
                }
            }
            ScrollView {
                Text(request.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(look.theme.text.opacity(0.07)))

            if showNote {
                TextField("Tell Claude what to do instead", text: $denyNote)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(look.theme.text.opacity(0.08)))
                    .onSubmit { hub.answer(request.id, .deny(denyNote.isEmpty ? nil : denyNote)) }
            }
            HStack(spacing: 8) {
                Button { hub.answer(request.id, .terminal) } label: { Image(systemName: "terminal") }
                    .buttonStyle(IslandButton())
                    .help("Answer in the terminal")
                Button(showNote ? "Send" : "Deny") {
                    if showNote { hub.answer(request.id, .deny(denyNote.isEmpty ? nil : denyNote)) }
                    else { hub.answer(request.id, .deny(nil)) }
                }
                .buttonStyle(IslandButton())
                .help(c.combo(.deny)?.display ?? "")
                Button { showNote.toggle() } label: { Image(systemName: "text.bubble") }
                    .buttonStyle(IslandButton(active: showNote))
                    .help("Deny and tell Claude why")
                Spacer()
                Button("Always") { hub.answer(request.id, .always) }
                    .buttonStyle(IslandButton())
                    .help("Allow \(request.tool) from now on · " + (c.combo(.always)?.display ?? ""))
                Button { hub.answer(request.id, .allow) } label: {
                    HStack(spacing: 6) {
                        Text("Allow").fontWeight(.semibold)
                        if let k = c.combo(.allow)?.display { Text(k).font(.system(size: 10)).opacity(0.6) }
                    }
                }
                .buttonStyle(IslandButton(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.theme.surface).shadow(color: .black.opacity(0.3), radius: 10))
        .foregroundStyle(look.theme.text)
    }
}

/// Claude's multiple-choice questions, answered without leaving what you're doing.
struct QuestionCard: View {
    let request: PendingQuestion
    @Environment(\.look) private var look
    @State private var picks: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MascotView(size: 34, mood: .attention)
                Text("\(request.project) has a question").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { ClaudeHub.shared.answer(question: request.id, nil) } label: { Label("Terminal", systemImage: "terminal") }
                    .buttonStyle(IslandButton())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(request.questions) { q in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                if !q.header.isEmpty {
                                    Text(q.header.uppercased()).font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(look.accent.opacity(0.25)))
                                }
                                Text(q.text).font(.system(size: 12, weight: .medium))
                                if q.multiSelect { Text("pick any").font(.system(size: 9)).foregroundStyle(look.theme.secondary) }
                            }
                            FlowRow(spacing: 6) {
                                ForEach(q.options, id: \.self) { o in
                                    let on = picks[q.text, default: []].contains(o.label)
                                    Button { toggle(q, o.label) } label: {
                                        Text(o.label).font(.system(size: 11, weight: on ? .semibold : .regular))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(on ? look.accent : look.theme.text.opacity(0.08)))
                                            .foregroundStyle(on ? Color.black : look.theme.text)
                                    }
                                    .buttonStyle(.plain)
                                    .help(o.description)
                                }
                                TextField("Other…", text: Binding(get: { other[q.text, default: ""] }, set: { other[q.text] = $0 }))
                                    .textFieldStyle(.plain).font(.system(size: 11))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().strokeBorder(look.theme.text.opacity(0.2)))
                                    .frame(width: 130)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Send answers") { send() }
                    .buttonStyle(IslandButton(prominent: true))
                    .disabled(!complete)
                    .opacity(complete ? 1 : 0.5)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.theme.surface).shadow(color: .black.opacity(0.3), radius: 10))
        .foregroundStyle(look.theme.text)
    }

    private var complete: Bool {
        request.questions.allSatisfy { !(picks[$0.text] ?? []).isEmpty || !(other[$0.text] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func toggle(_ q: PendingQuestion.Question, _ label: String) {
        var set = picks[q.text, default: []]
        if set.contains(label) { set.remove(label) } else {
            if !q.multiSelect { set.removeAll() }
            set.insert(label)
        }
        picks[q.text] = set
        // A single question with a single answer goes straight back to Claude.
        if request.questions.count == 1 && !q.multiSelect { send() }
    }

    private func send() {
        var answers: [String: String] = [:]
        for q in request.questions {
            var chosen = q.options.map(\.label).filter { picks[q.text, default: []].contains($0) }
            let typed = other[q.text, default: ""].trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty { chosen.append(typed) }
            answers[q.text] = chosen.joined(separator: ", ")
        }
        ClaudeHub.shared.answer(question: request.id, answers)
    }
}

/// Wraps its children onto new lines when they run out of room.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(width, widest), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

/// Buttons that look the same whether or not the island window is key.
struct IslandButton: ButtonStyle {
    var prominent = false
    var active = false
    @Environment(\.look) private var look

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: prominent ? .semibold : .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(prominent ? look.accent : look.theme.text.opacity(active ? 0.22 : 0.1)))
            .foregroundStyle(prominent ? (look.accent.isLight ? Color.black : .white) : look.theme.text)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

extension Color {
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return true }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
    }
}
