import AppKit
import EventKit
import IOKit.ps
import IOKit.pwr_mgt
import SwiftUI

// MARK: - Calendar

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    struct Meeting: Equatable {
        var title: String
        var start: Date
        var end: Date
        var color: Color
        var joinURL: URL?
    }

    @Published private(set) var next: Meeting?
    @Published private(set) var later: [Meeting] = []
    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var timer: Timer?

    var hasAccess: Bool { access == .fullAccess }

    func setActive(_ on: Bool) {
        if on, timer == nil {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .EKEventStoreChanged, object: store)
        } else if !on {
            timer?.invalidate()
            timer = nil
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.access = EKEventStore.authorizationStatus(for: .event)
                self?.refresh()
            }
        }
    }

    @objc private func changed() { DispatchQueue.main.async { self.refresh() } }

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { return }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-30 * 60), end: now.addingTimeInterval(16 * 3600), calendars: nil)
        let events = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
        let meetings = events.map { e in
            Meeting(title: e.title ?? "Event", start: e.startDate, end: e.endDate,
                    color: Color(cgColor: e.calendar.cgColor), joinURL: Self.joinLink(e))
        }
        next = meetings.first
        later = Array(meetings.dropFirst().prefix(3))
    }

    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|around\.co|meet\.jit\.si|facetime\.apple\.com)[^\s<>"]*"#,
        options: [.caseInsensitive])

    static func joinLink(_ e: EKEvent) -> URL? {
        let text = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard let m = linkPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        return URL(string: String(text[r]))
    }
}

// MARK: - Weather (Open-Meteo, no key, no account)

final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    struct Now: Equatable {
        var temp: Double
        var high: Double
        var low: Double
        var code: Int
        var isDay: Bool
        var place: String
    }

    @Published private(set) var now: Now?
    @Published private(set) var error: String?
    private var timer: Timer?

    func setActive(_ on: Bool) {
        if on, timer == nil {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        } else if !on {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Looks a city up and saves its coordinates.
    func setCity(_ name: String) {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?count=1&name=\(q)") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (obj["results"] as? [[String: Any]])?.first,
                  let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
                DispatchQueue.main.async { self?.error = "Couldn't find \(name)" }
                return
            }
            DispatchQueue.main.async {
                Prefs.shared.c.city = first["name"] as? String ?? name
                Prefs.shared.c.latitude = lat
                Prefs.shared.c.longitude = lon
                self?.error = nil
                self?.refresh()
            }
        }.resume()
    }

    func refresh() {
        let c = Prefs.shared.c
        guard !c.city.isEmpty else { now = nil; return }
        let unit = c.fahrenheit ? "&temperature_unit=fahrenheit" : ""
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto\(unit)"
        guard let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any], let daily = obj["daily"] as? [String: Any] else { return }
            let n = Now(temp: cur["temperature_2m"] as? Double ?? 0,
                        high: (daily["temperature_2m_max"] as? [Double])?.first ?? 0,
                        low: (daily["temperature_2m_min"] as? [Double])?.first ?? 0,
                        code: cur["weather_code"] as? Int ?? 0, isDay: (cur["is_day"] as? Int ?? 1) == 1, place: c.city)
            DispatchQueue.main.async { self?.now = n }
        }.resume()
    }

    static func symbol(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func words(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Storm"
        default: "Cloudy"
        }
    }
}

// MARK: - CPU, memory, battery

final class SystemStats: ObservableObject {
    static let shared = SystemStats()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 24)

    private var timer: Timer?
    private var lastTicks: (used: UInt64, total: UInt64)?

    func setActive(_ on: Bool) {
        if on, timer == nil {
            sample()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.sample() }
        } else if !on {
            timer?.invalidate()
            timer = nil
        }
    }

    private func sample() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if r == KERN_SUCCESS {
            let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
            let used = user + sys + nice, total = used + idle
            if let last = lastTicks, total > last.total {
                cpu = Double(used - last.used) / Double(total - last.total)
                cpuHistory = Array((cpuHistory + [cpu]).suffix(24))
            }
            lastTicks = (used, total)
        }

        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if vr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let used = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
            memory = Double(used) / Double(ProcessInfo.processInfo.physicalMemory)
        }

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {
            battery = desc[kIOPSCurrentCapacityKey] as? Int
            charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        } else {
            battery = nil
        }
    }
}

// MARK: - Clipboard history

final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    @Published private(set) var items: [String] = []
    private var timer: Timer?
    private var lastCount = NSPasteboard.general.changeCount

    func setActive(_ on: Bool) {
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.check() }
        } else if !on {
            timer?.invalidate()
            timer = nil
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastCount = NSPasteboard.general.changeCount
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
    }

    func clear() { items.removeAll() }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        // Respect password managers that mark their copies as concealed or transient.
        let types = pb.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            || types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return }
        guard let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }
    }
}

// MARK: - Focus timer

final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    enum Mode { case focus, rest }

    @Published private(set) var mode: Mode = .focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var running = false
    @Published private(set) var finishedAt: Date?
    @Published private(set) var rounds = 0

    var onFinish: ((Mode) -> Void)?
    private var timer: Timer?
    private var endsAt: Date?

    var total: TimeInterval {
        let c = Prefs.shared.c
        return Double(mode == .focus ? c.focusMinutes : c.breakMinutes) * 60
    }
    var progress: Double { total > 0 ? 1 - remaining / total : 0 }
    var label: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func toggle() { running ? pause() : start() }

    func start() {
        if remaining <= 0 { remaining = total }
        endsAt = Date().addingTimeInterval(remaining)
        running = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        mode = .focus
        remaining = total
    }

    func skip() {
        pause()
        mode = mode == .focus ? .rest : .focus
        remaining = total
    }

    private func tick() {
        guard let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)
        guard remaining <= 0 else { return }
        let finished = mode
        if finished == .focus { rounds += 1 }
        finishedAt = .now
        skip()
        onFinish?(finished)
    }
}

// MARK: - Small system switches

enum SystemSwitches {
    private static var awakeID: IOPMAssertionID = 0

    static var keepingAwake: Bool { awakeID != 0 }

    static func keepAwake(_ on: Bool) {
        if on, awakeID == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Wisp keep awake" as CFString, &awakeID)
        } else if !on, awakeID != 0 {
            IOPMAssertionRelease(awakeID)
            awakeID = 0
        }
    }

    static var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Needs Automation permission for System Events; macOS asks the first time.
    static func toggleDarkMode() {
        DispatchQueue.global().async {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")?
                .executeAndReturnError(&err)
        }
    }

    static func haptic() {
        guard Prefs.shared.c.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
