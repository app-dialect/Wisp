import AppKit
import SwiftUI

/// Spotify and Apple Music through AppleScript. Wisp only talks to a player that is
/// already running, so it never launches one by asking.
final class MusicService: ObservableObject {
    static let shared = MusicService()

    enum Player: String { case spotify = "Spotify", music = "Music" }

    struct Track: Equatable {
        var title = ""
        var artist = ""
        var album = ""
        var position: Double = 0
        var duration: Double = 1
        var playing = false
        var player: Player = .music
        var artURL: String = ""
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var tint: Color?

    var isPlaying: Bool { track?.playing == true }

    private let queue = DispatchQueue(label: "wisp.music")
    private var timer: Timer?
    private var lastKey = ""

    func setActive(_ on: Bool) {
        if on, timer == nil {
            poll()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        } else if !on {
            timer?.invalidate()
            timer = nil
            track = nil
        }
    }

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private var runningPlayer: Player? {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Prefer whichever is actually playing; Spotify wins a tie.
        if ids.contains("com.spotify.client") { return .spotify }
        if ids.contains("com.apple.Music") { return .music }
        return nil
    }

    private func send(_ command: String) {
        guard let p = track?.player ?? runningPlayer else { return }
        queue.async { [weak self] in
            _ = Self.run("tell application \"\(p.rawValue)\" to \(command)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.poll() }
        }
    }

    private func poll() {
        guard let p = runningPlayer else {
            if track != nil { track = nil; artwork = nil; tint = nil }
            return
        }
        let art = p == .spotify ? "artwork url of current track" : "\"\""
        let script = """
        tell application "\(p.rawValue)"
            if player state is stopped then return "stopped"
            set s to (player state as text)
            set d to duration of current track
            return s & "\u{1F}" & (name of current track) & "\u{1F}" & (artist of current track) & "\u{1F}" & (album of current track) & "\u{1F}" & (player position as text) & "\u{1F}" & (d as text) & "\u{1F}" & \(art)
        end tell
        """
        queue.async { [weak self] in
            guard let out = Self.run(script)?.stringValue, out != "stopped" else {
                DispatchQueue.main.async { self?.track = nil }
                return
            }
            let parts = out.components(separatedBy: "\u{1F}")
            guard parts.count >= 7 else { return }
            var t = Track()
            t.playing = parts[0] == "playing"
            t.title = parts[1]
            t.artist = parts[2]
            t.album = parts[3]
            t.position = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            var d = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 1
            if p == .spotify { d /= 1000 }   // Spotify reports milliseconds
            t.duration = max(1, d)
            t.player = p
            t.artURL = parts[6]
            DispatchQueue.main.async { self?.update(t) }
        }
    }

    private func update(_ t: Track) {
        track = t
        let key = "\(t.player)\(t.title)\(t.album)"
        guard key != lastKey else { return }
        lastKey = key
        loadArtwork(t)
    }

    private func loadArtwork(_ t: Track) {
        if t.player == .spotify, let url = URL(string: t.artURL) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.setArtwork(img) }
            }.resume()
        } else {
            queue.async { [weak self] in
                let d = Self.run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data
                let img = d.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { self?.setArtwork(img) }
            }
        }
    }

    private func setArtwork(_ img: NSImage?) {
        artwork = img
        tint = img.flatMap(Self.averageColor)
    }

    /// Average color of the cover, brightened so it reads on a dark island.
    static func averageColor(_ image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let c = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(hue: h, saturation: min(1, s * 1.3 + 0.15), brightness: max(0.75, b), alpha: 1))
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&err)
    }
}
