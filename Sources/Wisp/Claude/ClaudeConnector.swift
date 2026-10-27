import Foundation

/// Adds and removes Wisp's hook in ~/.claude/settings.json. Nothing is written until
/// the person has seen the preview, and a dated backup is kept every time.
enum ClaudeConnector {
    static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 5), ("UserPromptSubmit", 5), ("PreToolUse", 5), ("PostToolUse", 5),
        ("PostToolUseFailure", 5), ("PermissionRequest", 900), ("Notification", 5), ("Stop", 5),
        ("SubagentStop", 5), ("PreCompact", 5), ("SessionEnd", 5),
    ]
    static let marker = "Wisp/wisp-hook.py"
    static var command: String { "/usr/bin/python3 \"$HOME/Library/Application Support/Wisp/wisp-hook.py\"" }

    enum Status: Equatable { case connected, partial, disconnected }

    static func status() -> Status {
        let root = read()
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let found = events.filter { ev in hasWisp(hooks[ev.name]) }.count
        if found == events.count && FileManager.default.fileExists(atPath: Paths.hookScript.path) { return .connected }
        return found == 0 ? .disconnected : .partial
    }

    /// What the hooks section will look like after connecting, for the preview sheet.
    static func preview(connect: Bool) -> String {
        let root = transformed(connect: connect)
        let hooks = root["hooks"] ?? [String: Any]()
        guard let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Installs the script and rewrites settings.json. Returns the backup path.
    @discardableResult
    static func apply(connect: Bool) throws -> URL? {
        if connect { try installScript() }
        let fm = FileManager.default
        let url = Paths.claudeSettings
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fm.fileExists(atPath: url.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let b = url.deletingLastPathComponent().appendingPathComponent("settings.json.wisp-backup-\(f.string(from: .now))")
            try fm.copyItem(at: url, to: b)
            backup = b
        }
        let data = try JSONSerialization.data(withJSONObject: transformed(connect: connect), options: [.prettyPrinted, .withoutEscapingSlashes])
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

    // MARK: -

    private static func read() -> [String: Any] {
        guard let data = try? Data(contentsOf: Paths.claudeSettings),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private static func hasWisp(_ value: Any?) -> Bool {
        guard let groups = value as? [[String: Any]] else { return false }
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
        }
    }

    private static func transformed(connect: Bool) -> [String: Any] {
        var root = read()
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
            for ev in events {
                var groups = hooks[ev.name] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": command, "timeout": ev.timeout]]])
                if ev.name == "PreToolUse" {
                    // Claude's multiple-choice questions, answered from the notch.
                    groups.append(["matcher": "AskUserQuestion",
                                   "hooks": [["type": "command", "command": command + " --ask", "timeout": 900]]])
                }
                hooks[ev.name] = groups
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }
}
