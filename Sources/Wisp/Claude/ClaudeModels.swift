import Foundation

enum SessionPhase: Equatable {
    case starting, thinking, working, waiting, done, failed, ended
}

struct Step: Identifiable, Equatable {
    enum Status: Equatable { case running, ok, failed, auto, info }
    let id = UUID()
    let time: Date
    let tool: String
    let symbol: String
    let text: String
    var status: Status
    var toolUseID: String?
}

struct FileChange: Identifiable, Equatable {
    var id: String { path }
    let path: String
    var added = 0
    var removed = 0
    var lastDiff: [DiffLine] = []
}

struct DiffLine: Identifiable, Equatable {
    enum Kind { case same, add, remove }
    let id = UUID()
    let kind: Kind
    let text: String
}

struct Session: Identifiable, Equatable {
    let id: String
    var cwd: String
    var startedAt: Date
    var lastEvent: Date
    var phase: SessionPhase = .starting
    var activity = "Starting"
    var prompt: String?
    var lastMessage: String?
    var steps: [Step] = []
    var files: [String: FileChange] = [:]
    var tokensIn = 0
    var tokensOut = 0
    var toolCount = 0
    var appBundle: String = ""
    var transcriptPath: String?
    var turnStarted: Date?
    var agent = ""

    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? (agent.isEmpty ? "Claude" : agent) : name
    }
    var isLive: Bool { phase == .thinking || phase == .working || phase == .waiting || phase == .starting }
    var sortedFiles: [FileChange] { files.values.sorted { $0.path < $1.path } }
}

/// Claude's AskUserQuestion tool: up to four multiple-choice questions.
struct PendingQuestion: Identifiable {
    struct Option: Hashable { let label: String; let description: String }
    struct Question: Identifiable {
        var id: String { text }
        let text: String
        let header: String
        let multiSelect: Bool
        let options: [Option]
    }
    let id: String
    let sessionID: String
    let project: String
    let questions: [Question]
    let created: Date
    let deadline: Date
    let reply: ([String: Any]) -> Void

    static func parse(_ input: [String: Any]) -> [Question] {
        (input["questions"] as? [[String: Any]] ?? []).compactMap { q in
            guard let text = q["question"] as? String else { return nil }
            let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> Option? in
                guard let label = o["label"] as? String else { return nil }
                return Option(label: label, description: o["description"] as? String ?? "")
            }
            return Question(text: text, header: q["header"] as? String ?? "", multiSelect: q["multiSelect"] as? Bool ?? false, options: options)
        }
    }
}

struct PendingPermission: Identifiable {
    let id: String          // the hook's token
    let sessionID: String
    let project: String
    let cwd: String
    let tool: String
    let summary: String
    let detail: String
    let symbol: String
    let canRemember: Bool
    let created: Date
    let deadline: Date
    let reply: ([String: Any]) -> Void
}

/// Turns a tool call into words, an SF Symbol and a one-line summary.
enum ToolText {
    static func symbol(_ tool: String) -> String {
        switch tool {
        case "Bash", "BashOutput", "KillShell": "terminal"
        case "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Write": "square.and.pencil"
        case "Read": "doc.text"
        case "Glob": "folder"
        case "Grep": "magnifyingglass"
        case "WebFetch": "globe"
        case "WebSearch": "network"
        case "Task", "Agent": "person.2"
        case "TodoWrite": "checklist"
        case "AskUserQuestion": "questionmark.bubble"
        case "ExitPlanMode": "map"
        default: tool.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }

    static func summary(_ tool: String, _ input: [String: Any]) -> String {
        func str(_ k: String) -> String? { input[k] as? String }
        func file(_ k: String) -> String? { str(k).map { URL(fileURLWithPath: $0).lastPathComponent } }
        switch tool {
        case "Bash": return str("command").map { firstLine($0) } ?? "a command"
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit": return file("file_path") ?? file("notebook_path") ?? "a file"
        case "Glob", "Grep": return str("pattern") ?? ""
        case "WebFetch": return str("url").flatMap { URL(string: $0)?.host } ?? "the web"
        case "WebSearch": return str("query") ?? ""
        case "Task", "Agent": return str("description") ?? str("subagent_type") ?? "a subagent"
        case "TodoWrite": return "the plan"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                return parts.dropFirst().joined(separator: " · ")
            }
            return tool
        }
    }

    /// The full text a permission rule is matched against.
    static func matchText(_ tool: String, _ input: [String: Any]) -> String {
        (input["command"] as? String) ?? (input["file_path"] as? String) ?? (input["url"] as? String)
            ?? (input["pattern"] as? String) ?? (input["query"] as? String) ?? ""
    }

    static func verb(_ tool: String) -> String {
        switch tool {
        case "Bash": "Running"
        case "Edit", "MultiEdit", "NotebookEdit": "Editing"
        case "Write": "Writing"
        case "Read": "Reading"
        case "Glob": "Finding"
        case "Grep": "Searching"
        case "WebFetch": "Fetching"
        case "WebSearch": "Searching the web for"
        case "Task", "Agent": "Delegating"
        case "TodoWrite": "Updating"
        default: "Using"
        }
    }

    static func activity(_ tool: String, _ input: [String: Any]) -> String {
        let s = summary(tool, input)
        return s.isEmpty ? verb(tool) : "\(verb(tool)) \(s)"
    }

    static func detail(_ tool: String, _ input: [String: Any]) -> String {
        if let cmd = input["command"] as? String { return cmd }
        if let path = input["file_path"] as? String {
            var out = Paths.pretty(path)
            if let new = input["new_string"] as? String { out += "\n\n" + String(new.prefix(600)) }
            else if let content = input["content"] as? String { out += "\n\n" + String(content.prefix(600)) }
            return out
        }
        if let url = input["url"] as? String { return url }
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(1200))
    }

    static func isReadOnly(_ tool: String) -> Bool {
        ["Read", "Glob", "Grep", "LS", "WebSearch", "TodoWrite", "BashOutput"].contains(tool)
    }

    static func firstLine(_ s: String) -> String {
        let line = s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }
}

enum LineDiff {
    /// A plain LCS line diff, capped so a huge file can't stall the UI.
    static func diff(old: String, new: String, limit: Int = 400) -> [DiffLine] {
        let a = Array(old.split(separator: "\n", omittingEmptySubsequences: false).prefix(limit)).map(String.init)
        let b = Array(new.split(separator: "\n", omittingEmptySubsequences: false).prefix(limit)).map(String.init)
        if old.isEmpty { return b.map { DiffLine(kind: .add, text: $0) } }
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { out.append(DiffLine(kind: .same, text: a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { out.append(DiffLine(kind: .remove, text: a[i])); i += 1 }
            else { out.append(DiffLine(kind: .add, text: b[j])); j += 1 }
        }
        while i < a.count { out.append(DiffLine(kind: .remove, text: a[i])); i += 1 }
        while j < b.count { out.append(DiffLine(kind: .add, text: b[j])); j += 1 }
        return out
    }
}

/// Reads the session transcript for token totals and Claude's last words.
enum Transcript {
    struct Summary { var tokensIn = 0; var tokensOut = 0; var lastText: String? }

    static func summarize(path: String) -> Summary? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        var s = Summary()
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            guard line.contains("\"assistant\""),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any] else { continue }
            if let id = msg["id"] as? String, let usage = msg["usage"] as? [String: Any], seen.insert(id).inserted {
                let n = { (k: String) in (usage[k] as? Int) ?? 0 }
                s.tokensIn += n("input_tokens") + n("cache_creation_input_tokens") + n("cache_read_input_tokens")
                s.tokensOut += n("output_tokens")
            }
            if let content = msg["content"] as? [[String: Any]] {
                let texts = content.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
                if let last = texts.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    s.lastText = last
                }
            }
        }
        return s
    }
}

struct DayStats: Codable, Equatable, Identifiable {
    var id: String { day }
    var day: String
    var sessions = 0
    var prompts = 0
    var tools = 0
    var edits = 0
    var commands = 0
    var tokens = 0
    var approvals = 0

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
