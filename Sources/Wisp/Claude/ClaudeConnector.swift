import Foundation

/// Adds and removes Wisp's hook in an agent's settings file. Nothing is written until
/// the person has seen the preview, and a dated backup is kept every time.
enum ClaudeConnector {
    struct Target: Equatable {
        let name: String
        let file: URL
        let events: [(name: String, timeout: Int)]
        let agentFlag: String
        let asksQuestions: Bool
        let hasStatusLine: Bool

        static func == (a: Target, b: Target) -> Bool { a.name == b.name }

        static let claude = Target(
            name: "Claude Code",
            file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
            events: [("SessionStart", 5), ("UserPromptSubmit", 5), ("PreToolUse", 5), ("PostToolUse", 5),
                     ("PostToolUseFailure", 5), ("PermissionRequest", 900), ("Notification", 5), ("Stop", 5),
                     ("SubagentStop", 5), ("PreCompact", 5), ("SessionEnd", 5)],
            agentFlag: "", asksQuestions: true, hasStatusLine: true)

        /// Codex CLI speaks the same hook format, from ~/.codex/hooks.json.
        static let codex = Target(
            name: "Codex",
            file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json"),
            events: [("SessionStart", 5), ("UserPromptSubmit", 5), ("PreToolUse", 5), ("PostToolUse", 5),
                     ("PermissionRequest", 900), ("Stop", 5), ("SubagentStop", 5), ("PreCompact", 5), ("SessionEnd", 5)],
            agentFlag: " --agent Codex", asksQuestions: false, hasStatusLine: false)

        /// Codex only gets offered when it's installed.
        var isInstalled: Bool { FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path) }
    }

    static let marker = "Wisp/wisp-hook.py"
    static var command: String { "/usr/bin/python3 \"$HOME/Library/Application Support/Wisp/wisp-hook.py\"" }

    enum Status: Equatable { case connected, partial, disconnected }

    static func status(_ t: Target = .claude) -> Status {
        let hooks = read(t)["hooks"] as? [String: Any] ?? [:]
        let found = t.events.filter { ev in hasWisp(hooks[ev.name]) }.count
        if found == t.events.count && FileManager.default.fileExists(atPath: Paths.hookScript.path) { return .connected }
        return found == 0 ? .disconnected : .partial
    }

    /// True when Claude Code's status line goes through Wisp (for plan usage).
    static var statusLineConnected: Bool {
        ((read(.claude)["statusLine"] as? [String: Any])?["command"] as? String)?.contains(marker) == true
    }

    /// What will change, for the preview sheet.
    static func preview(_ t: Target, connect: Bool, statusLine: Bool) -> String {
        let root = transformed(t, connect: connect, statusLine: statusLine)
        var shown: [String: Any] = ["hooks": root["hooks"] ?? [String: Any]()]
        if t.hasStatusLine, let s = root["statusLine"] { shown["statusLine"] = s }
        guard let data = try? JSONSerialization.data(withJSONObject: shown, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Installs the script and rewrites the settings file. Returns the backup path.
    @discardableResult
    static func apply(_ t: Target, connect: Bool, statusLine: Bool) throws -> URL? {
        if connect { try installScript() }
        let fm = FileManager.default
        let url = t.file
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fm.fileExists(atPath: url.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let b = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).wisp-backup-\(f.string(from: .now))")
            try fm.copyItem(at: url, to: b)
            backup = b
        }
        let data = try JSONSerialization.data(withJSONObject: transformed(t, connect: connect, statusLine: statusLine),
                                              options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        return backup
    }

    static func installScript() throws {
        guard let bundled = Bundle.main.url(forResource: "wisp-hook", withExtension: "py") else {
            throw NSError(domain: "Wisp", code: 1, userInfo: [NSLocalizedDescriptionKey: "The hook script is missing from the app bundle. Rebuild with ./build.sh."])
        }
        let dest = Paths.hookScript
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: bundled, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    /// Keeps the installed script in step with the app after an update.
    static func refreshScriptIfConnected() {
        guard FileManager.default.fileExists(atPath: Paths.hookScript.path),
              let bundled = Bundle.main.url(forResource: "wisp-hook", withExtension: "py"),
              let a = try? Data(contentsOf: bundled), let b = try? Data(contentsOf: Paths.hookScript), a != b else { return }
        try? installScript()
    }

    // MARK: -

    private static func read(_ t: Target) -> [String: Any] {
        guard let data = try? Data(contentsOf: t.file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private static func hasWisp(_ value: Any?) -> Bool {
        guard let groups = value as? [[String: Any]] else { return false }
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
        }
    }

    private static func transformed(_ t: Target, connect: Bool, statusLine: Bool) -> [String: Any] {
        var root = read(t)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // Remove any earlier Wisp entries first, so connecting twice never duplicates them.
        for (name, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var g = group
                let inner = (g["hooks"] as? [[String: Any]] ?? []).filter { ($0["command"] as? String)?.contains(marker) != true }
                if inner.isEmpty { return nil }
                g["hooks"] = inner
                return g
            }
            hooks[name] = groups.isEmpty ? nil : groups
        }
        if connect {
            let cmd = command + t.agentFlag
            for ev in t.events {
                var groups = hooks[ev.name] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": cmd, "timeout": ev.timeout]]])
                if ev.name == "PreToolUse" && t.asksQuestions {
                    // Claude's multiple-choice questions, answered from the notch.
                    groups.append(["matcher": "AskUserQuestion",
                                   "hooks": [["type": "command", "command": cmd + " --ask", "timeout": 900]]])
                }
                hooks[ev.name] = groups
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks

        if t.hasStatusLine {
            let current = root["statusLine"] as? [String: Any]
            let ours = (current?["command"] as? String)?.contains(marker) == true
            // Unwrap: give back whatever status line the person had before Wisp.
            var original: [String: Any]? = current
            if ours, let cmd = current?["command"] as? String {
                original = unwrap(cmd)
            }
            if connect && statusLine {
                var line: [String: Any] = ["type": "command", "padding": 0]
                var cmd = command + " --statusline"
                if let original, let data = try? JSONSerialization.data(withJSONObject: original) {
                    cmd += " --wrap-b64 " + data.base64EncodedString()
                    if let pad = original["padding"] { line["padding"] = pad }
                }
                line["command"] = cmd
                root["statusLine"] = line
            } else {
                root["statusLine"] = original
            }
        }
        return root
    }

    private static func unwrap(_ cmd: String) -> [String: Any]? {
        guard let r = cmd.range(of: "--wrap-b64 ") else { return nil }
        let b64 = cmd[r.upperBound...].split(separator: " ").first.map(String.init) ?? ""
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
