import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the island window: where it sits, when it opens and closes, and click-through.
final class IslandController {
    let model = IslandModel()
    private let panel = IslandPanel()
    private var tracker: Timer?
    private var hoverStart: Date?
    private var leaveStart: Date?
    /// Opened by a shortcut or a permission request: stays open until the pointer has visited and left.
    private var sticky = false
    private var currentScreen: NSScreen?
    private var bag = Set<AnyCancellable>()
    private var keyMonitor: Any?

    private var prefs: Config { Prefs.shared.c }

    init() {
        let root = IslandRoot()
            .environmentObject(Prefs.shared)
            .environmentObject(model)
        let host = FirstMouseHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()

        tracker = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(tracker!, forMode: .common)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.layout()
        }
        Prefs.shared.$c
            .map { "\($0.islandWidth) \($0.islandHeight) \($0.fakeNotchWidth) \($0.wingWidth) \($0.style) \($0.screen)" }
            .removeDuplicates()
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &bag)

        ClaudeHub.shared.$pending.combineLatest(ClaudeHub.shared.$questions)
            .map { $0.isEmpty && $1.isEmpty }
            .removeDuplicates()
            .sink { [weak self] empty in
                guard let self, empty, self.sticky, self.model.expanded else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.collapse() }
            }
            .store(in: &bag)

        model.$dropTargeted.removeDuplicates().sink { [weak self] on in
            if on { self?.expand(tab: .home) }
        }.store(in: &bag)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            if e.keyCode == 53 { self.collapse(); return nil }   // Escape
            return e
        }
    }

    // MARK: Opening and closing

    func toggle() { model.expanded ? collapse() : expand(sticky: true) }

    func expand(tab: IslandModel.Tab? = nil, sticky: Bool = false) {
        if let tab { model.tab = tab }
        if sticky { self.sticky = true }
        guard !model.expanded else { return }
        Activity.lastInteraction = .now
        withAnimation(prefs.motion.animation) { model.expanded = true }
        SystemSwitches.haptic()
        if prefs.soundPack != .off && prefs.volume > 0 && !ClaudeHub.shared.isSnoozed {
            // A barely-there tick, only on hover opens.
            if !sticky { Sounds.shared.play(.open) }
        }
    }

    func collapse() {
        sticky = false
        guard model.expanded else { return }
        withAnimation(prefs.motion.animation) {
            model.expanded = false
            model.editing = false
        }
        if panel.isKeyWindow { panel.resignKey() }
    }

    /// A permission arrived: open if the person wants that, or at least wave from the wings.
    func attention() {
        if prefs.openOnPermission { expand(sticky: true) }
        else { model.show(peek: .init(text: "Claude needs you", symbol: "hand.raised.fill", color: Mood.attention.color)) }
    }

    // MARK: Layout

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        switch prefs.screen {
        case .main: return screens.first
        case .builtin:
            return screens.first { s in
                let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                return CGDisplayIsBuiltin(id) != 0
            } ?? screens.first
        case .mouse:
            let m = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(m, $0.frame, false) } ?? screens.first
        }
    }

    func layout() {
        guard let screen = targetScreen() else { return }
        currentScreen = screen
        let f = screen.frame
        let menuBar = max(f.maxY - screen.visibleFrame.maxY, 24)
        model.menuBarHeight = menuBar
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            model.hasNotch = true
            model.notch = CGSize(width: max(120, f.width - left - right), height: screen.safeAreaInsets.top)
        } else {
            model.hasNotch = false
            model.notch = CGSize(width: prefs.fakeNotchWidth, height: menuBar)
        }
        let size = model.maxSize(prefs)
        let w = size.width + 120   // room for the glow and shadow
        let h = size.height + 60
        panel.setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), display: true)
    }

    // MARK: Pointer tracking

    private func visibleRect() -> NSRect? {
        guard let screen = currentScreen else { return nil }
        let c = prefs
        let size = model.expanded ? model.expandedSize(c) : model.collapsedSize(c, wings: wingsShown())
        let top = screen.frame.maxY - model.topOffset(c)
        var r = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        if !model.expanded {
            // A slightly larger target while closed; floating mode also lets you aim at the empty top edge.
            r = r.insetBy(dx: -6, dy: -4)
            if c.style == .floating { r = r.union(NSRect(x: r.minX, y: r.minY, width: r.width, height: screen.frame.maxY - r.minY)) }
        }
        return r
    }

    func wingsShown() -> Bool {
        WingLogic.visible(Prefs.shared.c, model: model)
    }

    private func track() {
        if prefs.screen == .mouse, let s = currentScreen, !NSMouseInRect(NSEvent.mouseLocation, s.frame, false) {
            layout()
        }
        guard let rect = visibleRect() else { return }
        let mouse = NSEvent.mouseLocation
        let inside = rect.contains(mouse)
        panel.ignoresMouseEvents = !inside
        let now = Date()

        if !model.expanded {
            leaveStart = nil
            if inside && prefs.trigger == .hover && NSEvent.pressedMouseButtons == 0 {
                if let start = hoverStart {
                    if now.timeIntervalSince(start) >= prefs.hoverDelay { hoverStart = nil; expand() }
                } else { hoverStart = now }
            } else {
                hoverStart = nil
            }
            return
        }

        hoverStart = nil
        if inside {
            sticky = false
            leaveStart = nil
            Activity.lastInteraction = now
            return
        }
        if sticky || model.pinned || model.editing || model.dropTargeted { leaveStart = nil; return }
        if let start = leaveStart {
            if now.timeIntervalSince(start) >= prefs.closeDelay { collapse() }
        } else {
            leaveStart = now
        }
    }
}

enum WingLogic {
    static func visible(_ c: Config, model: IslandModel) -> Bool {
        switch c.wingMode {
        case .never: return model.peek != nil
        case .always: return true
        case .auto: return isLive(c, model: model)
        }
    }

    static func isLive(_ c: Config, model: IslandModel) -> Bool {
        if model.peek != nil { return true }
        let hub = ClaudeHub.shared
        if c.claudeEnabled && (hub.needsYou || hub.headline != nil) { return true }
        if (c.uses(TileKind.music) || c.uses(WingContent.music)) && MusicService.shared.isPlaying { return true }
        if (c.uses(TileKind.timer) || c.uses(WingContent.timer)) && FocusTimer.shared.running { return true }
        if c.uses(.meeting), let m = CalendarService.shared.next, m.start.timeIntervalSinceNow < Double(c.meetingLead) * 60, m.end > .now { return true }
        return false
    }
}
