import SwiftUI

/// The Claude tab: sessions on the left, the selected one's steps, files and reply on the right.
struct ClaudePanel: View {
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared
    @State private var section = 0
    @State private var openFile: String?
    @State private var reply = ""

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
                                HStack(spacing: 4) {
                                Text(s.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                if !s.agent.isEmpty {
                                    Text(s.agent).font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(look.accent.opacity(0.25)))
                                }
                            }
                                Text(s.activity).font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
                                if let ctx = s.contextPercent {
                                    GeometryReader { g in
                                        Capsule().fill(look.theme.text.opacity(0.1)).overlay(alignment: .leading) {
                                            Capsule().fill(ctx >= Double(prefs.c.contextWarn) ? Mood.attention.color : look.accent.opacity(0.7))
                                                .frame(width: g.size.width * min(1, ctx / 100))
                                        }
                                    }
                                    .frame(height: 2.5)
                                    .help("Context \(Int(ctx))% full")
                                }
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
                Text(meta(s))
                    .font(.system(size: 10)).foregroundStyle(look.theme.secondary).lineLimit(1)
                if s.trusted {
                    Label("Trusted", systemImage: "checkmark.shield.fill").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Mood.attention.color).help("Everything is allowed in this session")
                }
                Spacer()
                Picker("", selection: $section) {
                    Text("Steps").tag(0)
                    Text("Files \(s.files.count)").tag(1)
                    Text("Reply").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.mini).frame(width: 180)
                Menu {
                    Button("Open terminal tab") { hub.focusTerminal(s.id) }
                    if s.trusted || !s.sessionAllowed.isEmpty {
                        Button("Stop auto-allowing in this session") { hub.revokeTrust(s.id) }
                    }
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
            if TerminalBridge.canSend(s) && !s.isLive {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left").foregroundStyle(look.theme.secondary)
                    TextField("Reply to \(s.agent.isEmpty ? "Claude" : s.agent)… (typed into its terminal)", text: $reply)
                        .textFieldStyle(.plain).font(.system(size: 12))
                        .onSubmit {
                            hub.send(reply, to: s.id)
                            reply = ""
                        }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(look.theme.surface))
            }
        }
    }

    private func meta(_ s: Session) -> String {
        var parts = [Date.now.timeIntervalSince(s.startedAt).short, "\(s.toolCount) tools"]
        if !s.model.isEmpty { parts.append(s.model) }
        if let ctx = s.contextPercent { parts.append("ctx \(Int(ctx))%") }
        if let cost = s.costUSD, cost > 0 { parts.append(String(format: "$%.2f", cost)) }
        else if s.tokensOut > 0 { parts.append("\((s.tokensIn + s.tokensOut).compact) tok") }
        return parts.joined(separator: " · ")
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
                    MarkdownBlock(text: m).textSelection(.enabled)
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
    @ObservedObject private var hub = ClaudeHub.shared
    @State private var denyNote = ""
    @State private var showNote = false

    private var isPlan: Bool { request.plan != nil }

    var body: some View {
        let c = prefs.c
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MascotView(size: 40, mood: request.risk == nil ? .attention : .sad)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPlan ? "\(request.project) has a plan for you" : "\(request.project) wants to use \(request.tool)")
                        .font(.system(size: 14, weight: .semibold))
                    Text(queued > 1 ? "1 of \(queued) waiting" : "Claude Code is waiting for you")
                        .font(.system(size: 10)).foregroundStyle(look.theme.secondary)
                }
                Spacer()
                if queued > 1 && hub.pending.contains(where: { $0.risk == nil }) {
                    Button("Allow all \(hub.pending.filter { $0.risk == nil }.count)") { hub.allowAllSafe() }
                        .buttonStyle(IslandButton())
                        .help("Allow every waiting request that isn't flagged as risky")
                }
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

            if let risk = request.risk {
                Label(risk, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Mood.sad.color.opacity(0.85)))
            }

            ScrollView {
                Group {
                    if let plan = request.plan {
                        MarkdownBlock(text: plan)
                    } else {
                        Text(request.detail).font(.system(size: 11, design: .monospaced))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(look.theme.text.opacity(0.07)))

            if showNote {
                TextField(isPlan ? "What should Claude change in the plan?" : "Tell Claude what to do instead", text: $denyNote)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(look.theme.text.opacity(0.08)))
                    .onSubmit { deny() }
            }
            HStack(spacing: 8) {
                Button { hub.answer(request.id, .terminal) } label: { Image(systemName: "terminal") }
                    .buttonStyle(IslandButton())
                    .help("Answer in the terminal")
                Button(showNote ? "Send" : (isPlan ? "Keep planning" : "Deny")) {
                    if isPlan && !showNote { showNote = true } else { deny() }
                }
                .buttonStyle(IslandButton())
                .help(c.combo(.deny)?.display ?? "")
                if !isPlan {
                    Button { showNote.toggle() } label: { Image(systemName: "text.bubble") }
                        .buttonStyle(IslandButton(active: showNote))
                        .help("Deny and tell Claude why")
                }
                Spacer()
                if request.risk == nil && !isPlan {
                    Menu {
                        Button("Allow \(request.tool) for this session") { hub.answer(request.id, .session) }
                        Button("Always allow (\(c.alwaysTarget.label))") { hub.answer(request.id, .always) }
                        Divider()
                        Button("Trust this session: allow everything") { hub.answer(request.id, .trust) }
                    } label: {
                        Text("More").font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(look.theme.text.opacity(0.1)))
                }
                if request.risk != nil {
                    HoldToAllow { hub.answer(request.id, .allow) }
                } else {
                    Button { hub.answer(request.id, .allow) } label: {
                        HStack(spacing: 6) {
                            Text(isPlan ? "Approve plan" : "Allow").fontWeight(.semibold)
                            if let k = c.combo(.allow)?.display { Text(k).font(.system(size: 10)).opacity(0.6) }
                        }
                    }
                    .buttonStyle(IslandButton(prominent: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.theme.surface).shadow(color: .black.opacity(0.3), radius: 10))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(request.risk == nil ? .clear : Mood.sad.color.opacity(0.7), lineWidth: 1.5))
        .foregroundStyle(look.theme.text)
    }

    private func deny() {
        let note = denyNote.trimmingCharacters(in: .whitespacesAndNewlines)
        hub.answer(request.id, .deny(note.isEmpty ? nil : note))
    }
}

/// Allow for risky requests: press and hold, so it can't happen by accident.
struct HoldToAllow: View {
    let action: () -> Void
    @Environment(\.look) private var look
    @State private var progress: Double = 0
    @State private var holding = false

    var body: some View {
        Text(holding ? "Keep holding…" : "Hold to allow")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                ZStack(alignment: .leading) {
                    Capsule().fill(Mood.sad.color.opacity(0.35))
                    GeometryReader { g in Capsule().fill(Mood.sad.color).frame(width: g.size.width * progress) }
                }
                .clipShape(Capsule())
            )
            .foregroundStyle(.white)
            .onLongPressGesture(minimumDuration: 1.0, perform: {
                SystemSwitches.haptic()
                action()
            }, onPressingChanged: { pressing in
                holding = pressing
                withAnimation(pressing ? .linear(duration: 1.0) : .easeOut(duration: 0.2)) { progress = pressing ? 1 : 0 }
            })
            .help("Flagged as risky: press and hold for a second to allow")
    }
}

/// Renders a plan or reply: headings, bullets and inline Markdown.
struct MarkdownBlock: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    let level = line.prefix(while: { $0 == "#" }).count
                    inline(String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
                        .font(.system(size: level == 1 ? 15 : level == 2 ? 13.5 : 12.5, weight: .semibold))
                        .padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        inline(String(line.dropFirst(2)))
                    }
                    .font(.system(size: 12))
                    .padding(.leading, CGFloat(raw.prefix(while: { $0 == " " }).count) * 4)
                } else if !line.isEmpty {
                    inline(line).font(.system(size: 12))
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
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
