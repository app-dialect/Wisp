import SwiftUI

// Every user-facing choice lives in one Codable struct. It is stored as JSON in
// UserDefaults, so "Export settings" and "Share theme" are just this struct on disk.

enum ScreenChoice: String, Codable, CaseIterable, Identifiable {
    case main, builtin, mouse
    var id: String { rawValue }
    var label: String {
        switch self {
        case .main: "Main display"
        case .builtin: "Built-in display"
        case .mouse: "Display with the pointer"
        }
    }
}

enum OpenTrigger: String, Codable, CaseIterable, Identifiable {
    case hover, click
    var id: String { rawValue }
    var label: String { self == .hover ? "Hover" : "Click" }
}

enum IslandStyle: String, Codable, CaseIterable, Identifiable {
    case notch, floating
    var id: String { rawValue }
    var label: String { self == .notch ? "Notch" : "Floating island" }
}

enum Motion: String, Codable, CaseIterable, Identifiable {
    case snappy, smooth, bouncy, calm
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var animation: Animation {
        switch self {
        case .snappy: .spring(response: 0.26, dampingFraction: 0.86)
        case .smooth: .spring(response: 0.4, dampingFraction: 0.88)
        case .bouncy: .spring(response: 0.46, dampingFraction: 0.62)
        case .calm: .easeInOut(duration: 0.5)
        }
    }
}

enum FontStyle: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, mono, serif
    var id: String { rawValue }
    var label: String { self == .mono ? "Monospaced" : rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .mono: .monospaced
        case .serif: .serif
        }
    }
}

enum WingMode: String, Codable, CaseIterable, Identifiable {
    case auto, always, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "When something is live"
        case .always: "Always"
        case .never: "Never"
        }
    }
}

enum WingContent: String, Codable, CaseIterable, Identifiable {
    case none, mascot, claude, usage, music, lyrics, timer, clock, battery, cpu, meeting
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Nothing"
        case .mascot: "Your wisp"
        case .claude: "Claude status"
        case .usage: "Claude plan usage"
        case .music: "Music"
        case .lyrics: "Synced lyrics"
        case .timer: "Focus timer"
        case .clock: "Clock"
        case .battery: "Battery"
        case .cpu: "CPU"
        case .meeting: "Next meeting"
        }
    }
}

enum MascotStyle: String, Codable, CaseIterable, Identifiable {
    case flame, orb, ghost, pixel, cat, star
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum MascotColor: String, Codable, CaseIterable, Identifiable {
    case mood, accent, rainbow, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mood: "Follows its mood"
        case .accent: "Theme accent"
        case .rainbow: "Rainbow"
        case .custom: "Custom"
        }
    }
}

enum Outfit: String, Codable, CaseIterable, Identifiable {
    case seasonal, none, partyHat, beanie, crown, witchHat, santaHat, headphones, sunglasses, bow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .seasonal: "Dress for the season"
        case .none: "Nothing"
        case .partyHat: "Party hat"
        case .beanie: "Beanie"
        case .crown: "Crown"
        case .witchHat: "Witch hat"
        case .santaHat: "Santa hat"
        case .headphones: "Headphones"
        case .sunglasses: "Sunglasses"
        case .bow: "Bow"
        }
    }

    /// What "seasonal" resolves to today: spooky in late October, festive in December,
    /// party for New Year, headphones whenever music plays.
    static func resolved(_ o: Outfit, musicPlaying: Bool, date: Date = .now) -> Outfit {
        guard o == .seasonal else { return o }
        let d = Calendar.current.dateComponents([.month, .day], from: date)
        switch (d.month ?? 0, d.day ?? 0) {
        case (12, 31), (1, 1): return .partyHat
        case (10, 20...31): return .witchHat
        case (12, 1...26): return .santaHat
        default: return musicPlaying ? .headphones : .none
        }
    }
}

enum Personality: String, Codable, CaseIterable, Identifiable {
    case calm, lively, sleepy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Animation speed multiplier.
    var speed: Double { switch self { case .calm: 0.7; case .lively: 1.35; case .sleepy: 0.45 } }
    /// Seconds of idleness before the wisp dozes off.
    var dozeAfter: Double { switch self { case .calm: 180; case .lively: 600; case .sleepy: 30 } }
}

enum SoundPack: String, Codable, CaseIterable, Identifiable {
    case chime, glass, wood, retro, bubble, off
    var id: String { rawValue }
    var label: String { self == .retro ? "Retro 8-bit" : rawValue.capitalized }
}

enum AlwaysTarget: String, Codable, CaseIterable, Identifiable {
    case claude, wisp
    var id: String { rawValue }
    var label: String { self == .claude ? "Claude Code's own rules" : "Wisp's rules" }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case toggleIsland, claudeTab, allow, deny, always, focusTimer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .toggleIsland: "Open or close the island"
        case .claudeTab: "Show Claude sessions"
        case .allow: "Allow a permission"
        case .deny: "Deny a permission"
        case .always: "Always allow"
        case .focusTimer: "Start or pause the focus timer"
        }
    }
    /// Permission keys are only grabbed while a request is waiting, so they never steal shortcuts from other apps.
    var onlyWhilePending: Bool { self == .allow || self == .deny || self == .always }
}

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    // Carbon modifier bits: cmd 256, shift 512, option 2048, control 4096.
    static let defaults: [String: KeyCombo] = [
        HotkeyAction.toggleIsland.rawValue: KeyCombo(keyCode: 49, carbonModifiers: 4096 | 2048, display: "⌃⌥Space"),
        HotkeyAction.claudeTab.rawValue: KeyCombo(keyCode: 8, carbonModifiers: 4096 | 2048, display: "⌃⌥C"),
        HotkeyAction.allow.rawValue: KeyCombo(keyCode: 16, carbonModifiers: 4096 | 2048, display: "⌃⌥Y"),
        HotkeyAction.deny.rawValue: KeyCombo(keyCode: 45, carbonModifiers: 4096 | 2048, display: "⌃⌥N"),
        HotkeyAction.always.rawValue: KeyCombo(keyCode: 0, carbonModifiers: 4096 | 2048, display: "⌃⌥A"),
        HotkeyAction.focusTimer.rawValue: KeyCombo(keyCode: 17, carbonModifiers: 4096 | 2048, display: "⌃⌥T"),
    ]
}

struct AllowRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var tool: String
    /// Empty matches any input; otherwise the summary (command, path, URL) must start with it.
    var pattern: String = ""
    /// Empty matches every project.
    var project: String = ""
}

struct TileConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TileKind
    var span: Int

    static let defaults: [TileConfig] = [
        TileConfig(kind: .claude, span: 2),
        TileConfig(kind: .music, span: 2),
        TileConfig(kind: .timer, span: 1),
        TileConfig(kind: .calendar, span: 2),
        TileConfig(kind: .shelf, span: 1),
    ]
}

struct Config: Codable, Equatable {
    // General
    var screen: ScreenChoice = .main
    var trigger: OpenTrigger = .hover
    var hoverDelay: Double = 0.12
    var closeDelay: Double = 0.35
    var haptics = true
    var showMenuBarIcon = true
    var onboarded = false

    // Look
    var themeID = "obsidian"
    var useCustomAccent = false
    var customAccent = "#FF8A3D"
    var fontStyle: FontStyle = .rounded
    var glass = false
    var style: IslandStyle = .notch
    var cornerRadius: Double = 24
    var islandWidth: Double = 640
    var islandHeight: Double = 196
    var motion: Motion = .smooth
    var fakeNotchWidth: Double = 196
    var glow = true
    var shadow = true
    var tintFromArtwork = true
    var jiggleInEditMode = true

    // Wings (the bits either side of the camera)
    var wingMode: WingMode = .auto
    var leftWing: WingContent = .mascot
    var rightWing: WingContent = .claude
    var wingWidth: Double = 78

    // The wisp
    var mascotEnabled = true
    var mascotName = "Wisp"
    var mascotStyle: MascotStyle = .flame
    var mascotColor: MascotColor = .mood
    var mascotHex = "#7CC4FF"
    var personality: Personality = .lively
    var mascotSpeaks = true
    var outfit: Outfit = .seasonal
    var eyesFollowCursor = true
    var pokeable = true
    var desktopBuddy = false
    var buddyX: Double = -1
    var buddyY: Double = -1
    var greetOnLaunch = true

    // Claude Code
    var claudeEnabled = true
    var openOnPermission = true
    var permissionTimeout: Double = 90
    var showDiffs = true
    var celebrate = true
    var peekOnDone = true
    var autoAllowReadOnly = false
    var alwaysTarget: AlwaysTarget = .claude
    var rules: [AllowRule] = []
    var riskGuard = true
    var usageWarn = 80
    var contextWarn = 85
    var quietHours = false
    var quietStart = 22
    var quietEnd = 8

    // Tiles
    var tiles: [TileConfig] = TileConfig.defaults
    var city = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var fahrenheit = false
    var zones: [String] = ["America/Los_Angeles", "Europe/London", "Asia/Kolkata"]
    var focusMinutes = 25
    var breakMinutes = 5
    var meetingLead = 5
    var shortcuts: [String] = []
    var lyrics = true
    var powerAlerts = true
    var downloadAlerts = false
    var downloadsToShelf = true
    var hideInFullScreen = true
    var todos: [TodoItem] = []

    // Sound
    var soundPack: SoundPack = .chime
    var volume: Double = 0.55
    var soundOnPermission = true
    var soundOnDone = true
    var soundOnError = true
    var soundOnTimer = true

    // Shortcuts
    var hotkeys: [String: KeyCombo] = KeyCombo.defaults

    func combo(_ action: HotkeyAction) -> KeyCombo? { hotkeys[action.rawValue] }

    func uses(_ kind: TileKind) -> Bool { tiles.contains { $0.kind == kind } }
    func uses(_ wing: WingContent) -> Bool { leftWing == wing || rightWing == wing }

    func isQuietNow(_ date: Date = .now) -> Bool {
        guard quietHours else { return false }
        let h = Calendar.current.component(.hour, from: date)
        return quietStart <= quietEnd ? (h >= quietStart && h < quietEnd) : (h >= quietStart || h < quietEnd)
    }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private static let key = "wisp.config.v1"

    @Published var c: Config {
        didSet { if c != oldValue { save() } }
    }

    private init() {
        c = Prefs.load(from: UserDefaults.standard.data(forKey: Prefs.key)) ?? Config()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: Prefs.key)
        }
    }

    /// Decodes stored JSON on top of the defaults, so settings added in a newer version
    /// don't throw away everything the user already chose.
    static func load(from data: Data?) -> Config? {
        guard let data,
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as? [String: Any]
        else { return nil }
        let merged = base.merging(stored) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: mergedData)
    }

    func exportData() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(c)
    }

    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard var imported = Prefs.load(from: data) else { return false }
        imported.onboarded = true
        c = imported
        return true
    }

    func reset() {
        var fresh = Config()
        fresh.onboarded = true
        c = fresh
    }
}
