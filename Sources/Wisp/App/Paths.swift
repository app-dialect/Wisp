import Foundation

enum Paths {
    /// ~/Library/Application Support/Wisp. Everything Wisp writes lives here.
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Wisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var socket: String { support.appendingPathComponent("wisp.sock").path }
    static var hookScript: URL { support.appendingPathComponent("wisp-hook.py") }
    static var stats: URL { support.appendingPathComponent("stats.json") }
    static var shelf: URL {
        let dir = support.appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Replaces the home folder with ~ for display.
    static func pretty(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

extension TimeInterval {
    /// 5s, 3m, 1h 20m
    var short: String {
        let s = Int(self)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        let m = (s % 3600) / 60
        return m == 0 ? "\(s / 3600)h" : "\(s / 3600)h \(m)m"
    }
}

extension Int {
    /// 950, 12.4k, 1.2M
    var compact: String {
        let d = Double(self)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fk", d / 1_000) }
        return "\(self)"
    }
}
