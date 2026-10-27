import SwiftUI
import AppKit

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let surface: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let isDark: Bool
    /// Optional wash painted behind the tiles.
    let wash: [Color]

    static let all: [Theme] = [
        Theme(id: "obsidian", name: "Obsidian", background: .hex("#0B0B0C"), surface: .hex("#1A1A1C"),
              text: .hex("#F4F4F5"), secondary: .hex("#8E8E93"), accent: .hex("#FF8A3D"), isDark: true, wash: []),
        Theme(id: "paper", name: "Paper", background: .hex("#F5F2EB"), surface: .hex("#FFFFFF"),
              text: .hex("#1C1B19"), secondary: .hex("#7A766D"), accent: .hex("#D9663A"), isDark: false, wash: []),
        Theme(id: "aurora", name: "Aurora", background: .hex("#070B1C"), surface: .hex("#121A33"),
              text: .hex("#EAF2FF"), secondary: .hex("#8090B5"), accent: .hex("#7CC4FF"), isDark: true,
              wash: [.hex("#1B3A5C").opacity(0.55), .hex("#2E1B5C").opacity(0.4), .clear]),
        Theme(id: "synthwave", name: "Synthwave", background: .hex("#140822"), surface: .hex("#231238"),
              text: .hex("#FFE9FB"), secondary: .hex("#A884B8"), accent: .hex("#FF4FD8"), isDark: true,
              wash: [.hex("#FF4FD8").opacity(0.18), .hex("#3B1E8C").opacity(0.35), .clear]),
        Theme(id: "matcha", name: "Matcha", background: .hex("#0D1610"), surface: .hex("#17241B"),
              text: .hex("#EAF5E4"), secondary: .hex("#86A08A"), accent: .hex("#9BE37A"), isDark: true, wash: []),
        Theme(id: "terminal", name: "Terminal", background: .hex("#000000"), surface: .hex("#0A140C"),
              text: .hex("#B8FFC6"), secondary: .hex("#3F8F52"), accent: .hex("#33FF66"), isDark: true, wash: []),
        Theme(id: "ocean", name: "Deep Ocean", background: .hex("#031A22"), surface: .hex("#0A2A35"),
              text: .hex("#E2FBFF"), secondary: .hex("#6FA5B2"), accent: .hex("#3FD0D4"), isDark: true,
              wash: [.hex("#0E4D5C").opacity(0.5), .clear]),
        Theme(id: "rose", name: "Rosewood", background: .hex("#1E0E12"), surface: .hex("#2E161C"),
              text: .hex("#FFEFF2"), secondary: .hex("#B48690"), accent: .hex("#FF7A9A"), isDark: true, wash: []),
        Theme(id: "sand", name: "Desert", background: .hex("#EFE4D2"), surface: .hex("#FBF5EA"),
              text: .hex("#2B2118"), secondary: .hex("#8C7A64"), accent: .hex("#C2410C"), isDark: false, wash: []),
        Theme(id: "mono", name: "Mono", background: .hex("#101010"), surface: .hex("#1E1E1E"),
              text: .hex("#FFFFFF"), secondary: .hex("#8A8A8A"), accent: .hex("#FFFFFF"), isDark: true, wash: []),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }
}

extension Config {
    var theme: Theme { Theme.named(themeID) }
    var accent: Color { useCustomAccent ? .hex(customAccent) : theme.accent }
    var font: Font.Design { fontStyle.design }

    /// A short, pasteable code with only the look of the island in it.
    var themeCode: String {
        let look: [String: Any] = [
            "themeID": themeID, "useCustomAccent": useCustomAccent, "customAccent": customAccent,
            "fontStyle": fontStyle.rawValue, "glass": glass, "style": style.rawValue,
            "cornerRadius": cornerRadius, "glow": glow, "mascotStyle": mascotStyle.rawValue,
            "mascotColor": mascotColor.rawValue, "mascotHex": mascotHex, "personality": personality.rawValue,
            "soundPack": soundPack.rawValue, "motion": motion.rawValue,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: look, options: [.sortedKeys])) ?? Data()
        return "wisp-look:" + data.base64EncodedString()
    }

    /// Applies a code made by `themeCode`. Returns false when the text isn't one.
    mutating func apply(themeCode code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("wisp-look:"),
              let data = Data(base64Encoded: String(trimmed.dropFirst("wisp-look:".count))),
              let look = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var mine = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any]
        else { return false }
        mine.merge(look) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: mine),
              let next = try? JSONDecoder().decode(Config.self, from: merged) else { return false }
        self = next
        return true
    }
}

extension Color {
    static func hex(_ string: String) -> Color { Color(nsColor: NSColor(hex: string) ?? .systemOrange) }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Environment plumbing so every view reads the same look.
struct Look {
    var theme: Theme
    var accent: Color
    var font: Font.Design
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look(theme: Theme.all[0], accent: Theme.all[0].accent, font: .rounded)
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}

extension Config {
    var look: Look { Look(theme: theme, accent: accent, font: font) }
}
