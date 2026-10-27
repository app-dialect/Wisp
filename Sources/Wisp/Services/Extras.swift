import AppKit
import AVFoundation
import CoreAudio
import IOKit.ps
import SwiftUI

// MARK: - Synced lyrics (lrclib.net: free, no key)

final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    struct Line: Equatable { let time: Double; let text: String }

    @Published private(set) var lines: [Line] = []
    private var key = ""

    /// The line playing now, estimated between Music polls.
    func current(at date: Date = .now) -> String? {
        guard Prefs.shared.c.lyrics, let t = MusicService.shared.track, !lines.isEmpty else { return nil }
        let pos = t.position + (t.playing ? date.timeIntervalSince(t.sampledAt) : 0)
        return lines.last(where: { $0.time <= pos + 0.25 })?.text
    }

    func update(for track: MusicService.Track?) {
        guard Prefs.shared.c.lyrics, let t = track else { lines = []; key = ""; return }
        let k = "\(t.artist)|\(t.title)"
        guard k != key else { return }
        key = k
        lines = []
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "artist_name", value: t.artist),
            URLQueryItem(name: "track_name", value: t.title),
            URLQueryItem(name: "album_name", value: t.album),
            URLQueryItem(name: "duration", value: String(Int(t.duration))),
        ]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.setValue("Wisp (https://github.com/app-dialect/Wisp)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let synced = obj["syncedLyrics"] as? String else { return }
            let parsed = Self.parse(synced)
            DispatchQueue.main.async { if self?.key == k { self?.lines = parsed } }
        }.resume()
    }

    static func parse(_ lrc: String) -> [Line] {
        lrc.split(separator: "\n").compactMap { raw in
            let s = String(raw)
            guard s.hasPrefix("["), let close = s.firstIndex(of: "]") else { return nil }
            let stamp = s[s.index(after: s.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let sec = Double(stamp[1]) else { return nil }
            let text = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return Line(time: m * 60 + sec, text: text.isEmpty ? "♪" : text)
        }
    }
}

// MARK: - Charging and low battery

final class PowerWatcher {
    static let shared = PowerWatcher()
    var onChange: ((String, String, Mood) -> Void)?

    private var source: CFRunLoopSource?
    private var lastCharging: Bool?
    private var warned: Set<Int> = []

    func start() {
        guard source == nil else { return }
        let src = IOPSNotificationCreateRunLoopSource({ _ in PowerWatcher.shared.check() }, nil)?.takeRetainedValue()
        if let src { CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode); source = src }
        check(initial: true)
    }

    private func check(initial: Bool = false) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let d = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
              let level = d[kIOPSCurrentCapacityKey] as? Int else { return }
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        defer { lastCharging = charging }
        guard !initial, Prefs.shared.c.powerAlerts else { return }
        if let last = lastCharging, last != charging {
            onChange?(charging ? "Charging · \(level)%" : "On battery · \(level)%",
                      charging ? "bolt.fill" : "battery.75", charging ? .happy : .idle)
            if charging { warned.removeAll() }
        }
        if !charging {
            for threshold in [20, 10] where level <= threshold && warned.insert(threshold).inserted {
                onChange?("Battery at \(level)%", "battery.25", .sad)
            }
        }
    }
}

// MARK: - Finished downloads

final class DownloadWatcher {
    static let shared = DownloadWatcher()
    var onDownload: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private static let partial = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    func setActive(_ on: Bool) {
        if on, source == nil {
            known = Set(list())
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.scan() }
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        } else if !on {
            source?.cancel()
            source = nil
        }
    }

    private func list() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func scan() {
        let now = Set(list())
        let added = now.subtracting(known)
        known = now
        for name in added where !name.hasPrefix(".") && !Self.partial.contains((name as NSString).pathExtension.lowercased()) {
            onDownload?(folder.appendingPathComponent(name))
        }
    }
}

// MARK: - Apple Shortcuts

final class ShortcutsService: ObservableObject {
    static let shared = ShortcutsService()
    @Published private(set) var all: [String] = []
    @Published private(set) var running: String?

    func load() {
        DispatchQueue.global().async {
            let names = Self.shell("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            DispatchQueue.main.async { self.all = names }
        }
    }

    func run(_ name: String) {
        running = name
        DispatchQueue.global().async {
            _ = Self.shell("/usr/bin/shortcuts", ["run", name])
            DispatchQueue.main.async { self.running = nil }
        }
    }

    static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Dev servers (listening TCP ports)

final class DevServers: ObservableObject {
    static let shared = DevServers()

    struct Server: Identifiable, Equatable {
        var id: String { "\(pid):\(port)" }
        let pid: Int32
        let command: String
        let port: Int
    }

    @Published private(set) var servers: [Server] = []
    private var timer: Timer?

    func setActive(_ on: Bool) {
        if on, timer == nil {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        } else if !on {
            timer?.invalidate()
            timer = nil
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let out = ShortcutsService.shell("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", NSUserName(), "-Fpcn"])
            var result: [Server] = []
            var pid: Int32 = 0
            var cmd = ""
            for line in out.split(separator: "\n") {
                guard let tag = line.first else { continue }
                let value = String(line.dropFirst())
                switch tag {
                case "p": pid = Int32(value) ?? 0
                case "c": cmd = value
                case "n":
                    if let port = value.split(separator: ":").last.flatMap({ Int($0) }), port >= 1024,
                       !result.contains(where: { $0.pid == pid && $0.port == port }) {
                        result.append(Server(pid: pid, command: cmd, port: port))
                    }
                default: break
                }
            }
            // Hide Wisp's own and well-known background helpers.
            let ignore = ["rapportd", "ControlCe", "Wisp", "identitys", "sharingd", "Spotify", "Dropbox", "Google", "com.apple"]
            result = result.filter { s in !ignore.contains { s.command.hasPrefix($0) } }.sorted { $0.port < $1.port }
            DispatchQueue.main.async { self.servers = result }
        }
    }

    func stop(_ s: Server) {
        kill(s.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }
}

// MARK: - Microphone mute (system-wide, default input)

enum MicMute {
    private static var savedVolume: Float32 = 1

    private static var input: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    static var isMuted: Bool {
        var addr = address(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(input, &addr), AudioObjectGetPropertyData(input, &addr, 0, nil, &size, &muted) == noErr {
            return muted == 1
        }
        var vAddr = address(kAudioDevicePropertyVolumeScalar)
        var v: Float32 = 1
        var vSize = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(input, &vAddr, 0, nil, &vSize, &v)
        return v == 0
    }

    static func set(_ mute: Bool) {
        let dev = input
        var addr = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &addr), AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue {
            var value: UInt32 = mute ? 1 : 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            return
        }
        // No mute switch on this device: turn the input volume down instead.
        var vAddr = address(kAudioDevicePropertyVolumeScalar)
        var size = UInt32(MemoryLayout<Float32>.size)
        if mute {
            AudioObjectGetPropertyData(dev, &vAddr, 0, nil, &size, &savedVolume)
            var zero: Float32 = 0
            AudioObjectSetPropertyData(dev, &vAddr, 0, nil, size, &zero)
        } else {
            var v = savedVolume > 0 ? savedVolume : 0.75
            AudioObjectSetPropertyData(dev, &vAddr, 0, nil, size, &v)
        }
    }
}

// MARK: - Full screen

enum FullScreen {
    /// True when the frontmost app covers the whole of `screen` (a full-screen video, game or slide show).
    static func isActive(on screen: NSScreen) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // CoreGraphics measures from the top-left of the main screen.
        let target = CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return abs(r.width - target.width) < 2 && abs(r.height - target.height) < 2 && abs(r.minX - target.minX) < 2 && abs(r.minY - target.minY) < 2
        }
    }
}

// MARK: - Camera mirror

final class CameraMirror: ObservableObject {
    static let shared = CameraMirror()
    let session = AVCaptureSession()
    @Published private(set) var denied = false
    private var users = 0
    private var configured = false

    func start() {
        users += 1
        guard users == 1 else { return }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                self.denied = !ok
                guard ok, self.users > 0 else { return }
                if !self.configured, let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.configured = true
                }
                DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: CameraMirror.shared.session)
        layer.videoGravity = .resizeAspectFill
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))   // a mirror, not a camera
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
