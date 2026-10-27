import AppKit
import Combine

/// Keeps every Claude Code session Wisp has heard about, plus the permission queue.
final class ClaudeHub: ObservableObject {
    static let shared = ClaudeHub()

    @Published private(set) var sessions: [String: Session] = [:]
    @Published private(set) var pending: [PendingPermission] = []
    @Published private(set) var questions: [PendingQuestion] = []
    @Published private(set) var stats = DayStats(day: DayStats.today())
    /// The last 60 days, oldest first, today excluded (that's `stats`).
    @Published private(set) var history: [DayStats] = []
    @Published private(set) var lastDone: (project: String, at: Date)?
    @Published private(set) var lastFailure: Date?
    @Published private(set) var lastActivity = Date()
    @Published private(set) var usage = PlanUsage()
    @Published var selectedID: String?
    @Published var snoozedUntil: Date?

    /// Hooks for the island: a permission needs you, a turn finished, a tool failed.
    var onAttention: (() -> Void)?
    var onDone: ((Session) -> Void)?
    var onFailure: ((Session) -> Void)?
    /// A short heads-up for the wings: text, SF Symbol, mood for the color.
    var onNotice: ((String, String, Mood) -> Void)?

    private var usageAlerted: Set<String> = []
    private var contextAlerted: Set<String> = []

    private let server = HookServer(path: Paths.socket)
    private var timers: [String: Timer] = [:]
    private var prefs: Config { Prefs.shared.c }

    private init() {
        loadStats()
        server.onEvent = { [weak self] json, reply in self?.handle(json, reply: reply) }
        server.onHangup = { [weak self] token in self?.drop(token) }
    }

    func start() { server.start() }
    var needsYou: Bool { !pending.isEmpty || !questions.isEmpty }

    func stop() {
        for p in pending { p.reply(["behavior": "ask"]) }
        for q in questions { q.reply(["behavior": "ask"]) }
        server.stop()
    }

    // MARK: - Reading

    var ordered: [Session] {
        sessions.values
            .filter { $0.phase != .ended || Date().timeIntervalSince($0.lastEvent) < 600 }
            .sorted { ($0.isLive ? 0 : 1, -$0.lastEvent.timeIntervalSince1970) < ($1.isLive ? 0 : 1, -$1.lastEvent.timeIntervalSince1970) }
    }
    var live: [Session] { ordered.filter(\.isLive) }
    var selected: Session? { selectedID.flatMap { sessions[$0] } ?? ordered.first }
    var isSnoozed: Bool { (snoozedUntil ?? .distantPast) > .now || prefs.isQuietNow() }

    /// One line for the wing next to the camera.
    var headline: (text: String, symbol: String, phase: SessionPhase)? {
        if let p = pending.first { return ("\(p.tool): \(p.summary)", "hand.raised.fill", .waiting) }
        if let q = questions.first { return (q.questions.first?.header ?? "A question", "questionmark.bubble.fill", .waiting) }
        if let s = live.first { return (s.activity, s.phase == .thinking ? "sparkle" : "bolt.fill", s.phase) }
        if let d = lastDone, Date().timeIntervalSince(d.at) < 12 { return ("\(d.project) is done", "checkmark.circle.fill", .done) }
        return nil
    }

    // MARK: - Answering permissions

    func answer(_ id: String, _ choice: Choice) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let p = pending.remove(at: i)
        timers.removeValue(forKey: id)?.invalidate()
        switch choice {
        case .allow:
            p.reply(["behavior": "allow"])
            stats.approvals += 1
            addStep(p.sessionID, tool: p.tool, text: "Allowed \(p.summary)", status: .ok)
        case .always:
            if prefs.alwaysTarget == .wisp || !p.canRemember {
                Prefs.shared.c.rules.append(AllowRule(tool: p.tool, pattern: p.tool == "Bash" ? p.detail : "", project: p.cwd))
                p.reply(["behavior": "allow"])
            } else {
                p.reply(["behavior": "allow", "always": true])
            }
            stats.approvals += 1
            addStep(p.sessionID, tool: p.tool, text: "Always allowed \(p.tool)", status: .ok)
        case .session:
            sessions[p.sessionID]?.sessionAllowed.insert(p.tool)
            p.reply(["behavior": "allow"])
            stats.approvals += 1
            addStep(p.sessionID, tool: p.tool, text: "Allowed \(p.tool) for this session", status: .ok)
        case .trust:
            sessions[p.sessionID]?.trusted = true
            p.reply(["behavior": "allow"])
            stats.approvals += 1
            addStep(p.sessionID, tool: p.tool, text: "Trusted this session: everything is allowed", status: .ok)
            // Everything else already waiting from this session goes through too.
            for other in pending where other.sessionID == p.sessionID && other.risk == nil { answer(other.id, .allow) }
        case .deny(let message):
            p.reply(["behavior": "deny", "message": message ?? ""])
            addStep(p.sessionID, tool: p.tool, text: message.map { "Denied: \($0)" } ?? "Denied \(p.summary)", status: .failed)
        case .terminal:
            p.reply(["behavior": "ask"])
            focusTerminal(p.sessionID)
        }
        saveStats()
        refreshPhase(p.sessionID)
        Hotkeys.shared.refreshPending(!pending.isEmpty)
    }

    enum Choice { case allow, always, session, trust, deny(String?), terminal }

    /// `answers` maps each question's text to the chosen label(s); nil hands it to the terminal.
    func answer(question id: String, _ answers: [String: String]?) {
        guard let i = questions.firstIndex(where: { $0.id == id }) else { return }
        let q = questions.remove(at: i)
        timers.removeValue(forKey: id)?.invalidate()
        if let answers {
            q.reply(["answers": answers])
            addStep(q.sessionID, tool: "AskUserQuestion", text: "You answered: " + answers.values.joined(separator: " · "), status: .ok)
        } else {
            q.reply(["behavior": "ask"])
            focusTerminal(q.sessionID)
        }
        refreshPhase(q.sessionID)
    }

    func focusTerminal(_ sessionID: String) {
        guard let s = sessions[sessionID] else { return }
        DispatchQueue.global(qos: .userInitiated).async { TerminalBridge.focus(s) }
    }

    /// Types a reply into the session's terminal tab.
    func send(_ text: String, to sessionID: String) {
        guard let s = sessions[sessionID], !text.isEmpty else { return }
        addStep(sessionID, tool: "You", text: "Sent: " + ToolText.firstLine(text), status: .info)
        DispatchQueue.global(qos: .userInitiated).async { TerminalBridge.send(text, to: s) }
    }

    /// Stops auto-allowing for a session that was trusted or had per-session tools.
    func revokeTrust(_ sessionID: String) {
        sessions[sessionID]?.trusted = false
        sessions[sessionID]?.sessionAllowed.removeAll()
    }

    /// Allows every waiting request that isn't risky.
    func allowAllSafe() {
        for p in pending where p.risk == nil { answer(p.id, .allow) }
    }

    func clearFinished() {
        sessions = sessions.filter { $0.value.isLive }
    }

    func snooze(minutes: Int?) {
        snoozedUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    // MARK: - Events

    private func handle(_ e: [String: Any], reply: HookServer.Reply?) {
        guard prefs.claudeEnabled else { reply?(["behavior": "ask"]); return }
        let name = e["hook_event_name"] as? String ?? ""
        let id = e["session_id"] as? String ?? "unknown"
        let tool = e["tool_name"] as? String ?? ""
        let input = e["tool_input"] as? [String: Any] ?? [:]
        let now = Date()
        lastActivity = now
        rollStatsIfNeeded()

        var s = sessions[id] ?? Session(id: id, cwd: e["cwd"] as? String ?? "", startedAt: now, lastEvent: now)
        if let cwd = e["cwd"] as? String, !cwd.isEmpty { s.cwd = cwd }
        if let meta = e["_wisp"] as? [String: Any] {
            if let b = meta["bundle"] as? String, !b.isEmpty { s.appBundle = b }
            else if s.appBundle.isEmpty, let t = meta["term"] as? String { s.appBundle = Self.bundle(forTerm: t) }
        }
        if let t = e["transcript_path"] as? String { s.transcriptPath = t }
        if let meta = e["_wisp"] as? [String: Any] {
            if let a = meta["agent"] as? String, !a.isEmpty { s.agent = a }
            if let t = meta["tty"] as? String, !t.isEmpty { s.tty = t }
            if let p = meta["tmux"] as? String, !p.isEmpty { s.tmuxPane = p }
        }
        let isNew = sessions[id] == nil
        s.lastEvent = now

        if ((e["_wisp"] as? [String: Any])?["ask"] as? Bool) == true {
            sessions[id] = s
            handleQuestion(e, session: s, input: input, reply: reply)
            return
        }

        switch name {
        case "StatusLine":
            readStatusLine(e, into: &s)
            sessions[id] = s
            return
        case "SessionStart":
            s.phase = .starting
            s.activity = "Ready"
            stats.sessions += 1
        case "UserPromptSubmit":
            if isNew { stats.sessions += 1 }
            let prompt = (e["prompt"] as? String) ?? ""
            s.prompt = prompt
            s.phase = .thinking
            s.activity = "Thinking"
            s.turnStarted = now
            s.steps.append(Step(time: now, tool: "You", symbol: "person.fill", text: ToolText.firstLine(prompt), status: .info))
            stats.prompts += 1
        case "PreToolUse":
            s.phase = .working
            s.activity = ToolText.activity(tool, input)
            s.steps.append(Step(time: now, tool: tool, symbol: ToolText.symbol(tool), text: s.activity, status: .running,
                                toolUseID: e["tool_use_id"] as? String))
        case "PostToolUse", "PostToolUseFailure":
            let failed = name == "PostToolUseFailure"
            let useID = e["tool_use_id"] as? String
            if let i = s.steps.lastIndex(where: { $0.status == .running && ($0.toolUseID == useID || $0.tool == tool) }) {
                s.steps[i].status = failed ? .failed : .ok
            }
            s.toolCount += 1
            stats.tools += 1
            if tool == "Bash" { stats.commands += 1 }
            if ["Edit", "MultiEdit", "Write"].contains(tool) {
                stats.edits += 1
                recordEdit(&s, tool: tool, input: input)
            }
            s.phase = .thinking
            s.activity = "Thinking"
            if failed {
                lastFailure = now
                if prefs.soundOnError, !isSnoozed { Sounds.shared.play(.error) }
                onFailure?(s)
            }
        case "PermissionRequest":
            sessions[id] = s
            handlePermission(e, session: s, tool: tool, input: input, reply: reply)
            return
        case "Notification":
            let message = e["message"] as? String ?? ""
            s.steps.append(Step(time: now, tool: "Claude", symbol: "bell", text: message, status: .info))
            if message.localizedCaseInsensitiveContains("waiting for your input") {
                s.activity = "Waiting for you"
            }
        case "Stop":
            s.phase = .done
            s.activity = "Done"
            for i in s.steps.indices where s.steps[i].status == .running { s.steps[i].status = .ok }
            if let m = e["last_assistant_message"] as? String, !m.isEmpty { s.lastMessage = m }
            finish(s)
        case "SubagentStop":
            s.steps.append(Step(time: now, tool: "Agent", symbol: "person.2", text: "A subagent finished", status: .ok))
        case "PreCompact":
            s.steps.append(Step(time: now, tool: "Claude", symbol: "arrow.down.right.and.arrow.up.left", text: "Compacting the conversation", status: .info))
        case "SessionEnd":
            s.phase = .ended
            s.activity = "Session ended"
            for p in pending where p.sessionID == id { drop(p.id) }
            for q in questions where q.sessionID == id { drop(q.id) }
        default:
            break
        }
        if s.steps.count > 300 { s.steps.removeFirst(s.steps.count - 300) }
        sessions[id] = s
        if selectedID == nil || sessions[selectedID ?? ""]?.isLive != true, s.isLive { selectedID = id }
        saveStats()
    }

    private func handlePermission(_ e: [String: Any], session s: Session, tool: String, input: [String: Any], reply: HookServer.Reply?) {
        guard let reply else { return }
        let match = ToolText.matchText(tool, input)
        let ruled = prefs.rules.contains { r in
            (r.tool == tool || r.tool == "*") && (r.project.isEmpty || r.project == s.cwd)
                && (r.pattern.isEmpty || match.hasPrefix(r.pattern))
        }
        let risk = prefs.riskGuard ? RiskCheck.check(tool, input) : nil
        let sessionOK = s.trusted || s.sessionAllowed.contains(tool)
        if risk == nil && (ruled || sessionOK || (prefs.autoAllowReadOnly && ToolText.isReadOnly(tool))) {
            reply(["behavior": "allow"])
            addStep(s.id, tool: tool, text: "Auto-allowed \(ToolText.summary(tool, input))", status: .auto)
            return
        }

        let token = e["_wisp_token"] as? String ?? UUID().uuidString
        let suggestions = e["permission_suggestions"] as? [Any] ?? []
        let timeout = max(10, prefs.permissionTimeout)
        let p = PendingPermission(
            id: token, sessionID: s.id, project: s.project, cwd: s.cwd, tool: tool,
            summary: ToolText.summary(tool, input), detail: ToolText.detail(tool, input),
            symbol: ToolText.symbol(tool), canRemember: !suggestions.isEmpty,
            risk: risk, plan: tool == "ExitPlanMode" ? input["plan"] as? String : nil,
            created: .now, deadline: Date().addingTimeInterval(timeout), reply: reply)
        pending.append(p)
        sessions[s.id]?.phase = .waiting
        sessions[s.id]?.activity = "Needs you: \(tool)"
        selectedID = s.id
        timers[token] = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.answer(token, .terminal)
        }
        Hotkeys.shared.refreshPending(true)
        if !isSnoozed {
            if prefs.soundOnPermission { Sounds.shared.play(.attention) }
            onAttention?()
        }
    }

    private func readStatusLine(_ e: [String: Any], into s: inout Session) {
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        if let m = (e["model"] as? [String: Any])?["display_name"] as? String { s.model = m }
        if let ctx = num((e["context_window"] as? [String: Any])?["used_percentage"]) {
            s.contextPercent = ctx
            if ctx >= Double(prefs.contextWarn), contextAlerted.insert(s.id).inserted {
                onNotice?("\(s.project): context \(Int(ctx))% full", "gauge.with.dots.needle.67percent", .attention)
            } else if ctx < Double(prefs.contextWarn) - 20 {
                contextAlerted.remove(s.id)   // compacted, warn again next time
            }
        }
        if let cost = num((e["cost"] as? [String: Any])?["total_cost_usd"]) { s.costUSD = cost }

        guard let limits = e["rate_limits"] as? [String: Any] else { return }
        var u = usage
        func window(_ key: String) -> PlanUsage.Window? {
            guard let w = limits[key] as? [String: Any], let pct = num(w["used_percentage"]) else { return nil }
            return PlanUsage.Window(percent: pct, resetsAt: num(w["resets_at"]).map { Date(timeIntervalSince1970: $0) })
        }
        u.fiveHour = window("five_hour") ?? u.fiveHour
        u.sevenDay = window("seven_day") ?? u.sevenDay
        u.updated = .now
        usage = u
        for (label, w) in [("5-hour", u.fiveHour), ("weekly", u.sevenDay)] {
            guard let w else { continue }
            for threshold in [prefs.usageWarn, 95] where w.percent >= Double(threshold) {
                let key = "\(label)-\(threshold)-\(Int(w.resetsAt?.timeIntervalSince1970 ?? 0))"
                if usageAlerted.insert(key).inserted {
                    let reset = w.resetsAt.map { " · resets in \($0.timeIntervalSinceNow.short)" } ?? ""
                    onNotice?("\(Int(w.percent))% of your \(label) limit\(reset)", "gauge.with.dots.needle.100percent", threshold >= 95 ? .sad : .attention)
                }
            }
        }
    }

    private func handleQuestion(_ e: [String: Any], session s: Session, input: [String: Any], reply: HookServer.Reply?) {
        guard let reply else { return }
        let parsed = PendingQuestion.parse(input)
        guard !parsed.isEmpty else { reply(["behavior": "ask"]); return }
        let token = e["_wisp_token"] as? String ?? UUID().uuidString
        let timeout = max(10, prefs.permissionTimeout) * 2
        questions.append(PendingQuestion(id: token, sessionID: s.id, project: s.project, questions: parsed,
                                         created: .now, deadline: Date().addingTimeInterval(timeout), reply: reply))
        sessions[s.id]?.phase = .waiting
        sessions[s.id]?.activity = "Asking you something"
        selectedID = s.id
        timers[token] = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.answer(question: token, nil)
        }
        if !isSnoozed {
            if prefs.soundOnPermission { Sounds.shared.play(.attention) }
            onAttention?()
        }
    }

    /// The hook went away (Claude Code timed it out, or it was answered in the terminal).
    private func drop(_ token: String) {
        if let q = questions.firstIndex(where: { $0.id == token }) {
            let removed = questions.remove(at: q)
            timers.removeValue(forKey: token)?.invalidate()
            refreshPhase(removed.sessionID)
            return
        }
        guard let i = pending.firstIndex(where: { $0.id == token }) else { return }
        let p = pending.remove(at: i)
        timers.removeValue(forKey: token)?.invalidate()
        refreshPhase(p.sessionID)
        Hotkeys.shared.refreshPending(!pending.isEmpty)
    }

    private func refreshPhase(_ id: String) {
        guard var s = sessions[id], s.phase == .waiting, !pending.contains(where: { $0.sessionID == id }),
              !questions.contains(where: { $0.sessionID == id }) else { return }
        s.phase = .working
        s.activity = "Working"
        sessions[id] = s
    }

    private func finish(_ s: Session) {
        lastDone = (s.project, .now)
        if prefs.soundOnDone, !isSnoozed { Sounds.shared.play(.success) }
        onDone?(s)
        guard let path = s.transcriptPath else { return }
        let id = s.id
        DispatchQueue.global(qos: .utility).async {
            guard let sum = Transcript.summarize(path: path) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, var cur = self.sessions[id] else { return }
                let delta = max(0, sum.tokensIn + sum.tokensOut - (cur.tokensIn + cur.tokensOut))
                cur.tokensIn = sum.tokensIn
                cur.tokensOut = sum.tokensOut
                cur.lastMessage = sum.lastText
                self.sessions[id] = cur
                self.stats.tokens += delta
                self.saveStats()
            }
        }
    }

    private func recordEdit(_ s: inout Session, tool: String, input: [String: Any]) {
        guard let path = input["file_path"] as? String else { return }
        var change = s.files[path] ?? FileChange(path: path)
        var lines: [DiffLine] = []
        switch tool {
        case "Edit":
            lines = LineDiff.diff(old: input["old_string"] as? String ?? "", new: input["new_string"] as? String ?? "")
        case "MultiEdit":
            for edit in input["edits"] as? [[String: Any]] ?? [] {
                lines += LineDiff.diff(old: edit["old_string"] as? String ?? "", new: edit["new_string"] as? String ?? "")
            }
        default:
            lines = LineDiff.diff(old: "", new: input["content"] as? String ?? "")
        }
        change.added += lines.filter { $0.kind == .add }.count
        change.removed += lines.filter { $0.kind == .remove }.count
        change.lastDiff = lines
        s.files[path] = change
    }

    private func addStep(_ id: String, tool: String, text: String, status: Step.Status) {
        sessions[id]?.steps.append(Step(time: .now, tool: tool, symbol: ToolText.symbol(tool), text: text, status: status))
    }

    static func bundle(forTerm term: String) -> String {
        switch term {
        case "iTerm.app": "com.googlecode.iterm2"
        case "vscode": "com.microsoft.VSCode"
        case "WarpTerminal": "dev.warp.Warp-Stable"
        case "ghostty": "com.mitchellh.ghostty"
        case "WezTerm": "com.github.wez.wezterm"
        case "zed": "dev.zed.Zed"
        default: "com.apple.Terminal"
        }
    }

    // MARK: - Daily stats

    private struct StatsFile: Codable { var today: DayStats; var history: [DayStats] }

    /// The last seven days including today, oldest first, with empty days filled in.
    var week: [DayStats] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let all = history + [stats]
        return (0..<7).reversed().map { back in
            let day = f.string(from: Calendar.current.date(byAdding: .day, value: -back, to: .now) ?? .now)
            return all.first { $0.day == day } ?? DayStats(day: day)
        }
    }

    private func rollStatsIfNeeded() {
        let today = DayStats.today()
        guard stats.day != today else { return }
        if stats.prompts + stats.tools > 0 { history = Array((history + [stats]).suffix(60)) }
        stats = DayStats(day: today)
    }

    private func loadStats() {
        guard let data = try? Data(contentsOf: Paths.stats) else { return }
        if let file = try? JSONDecoder().decode(StatsFile.self, from: data) {
            history = file.history
            stats = file.today
        } else if let s = try? JSONDecoder().decode(DayStats.self, from: data) {
            stats = s
        }
        rollStatsIfNeeded()
    }

    private func saveStats() {
        if let data = try? JSONEncoder().encode(StatsFile(today: stats, history: history)) {
            try? data.write(to: Paths.stats, options: .atomic)
        }
    }
}
