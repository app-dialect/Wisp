import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private var island: IslandController!
    private let buddy = DesktopBuddy()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let router = SettingsRouter()
    private var bag = Set<AnyCancellable>()

    private var prefs: Prefs { Prefs.shared }

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        island = IslandController()
        island.model.openSettings = { [weak self] in self?.openSettings() }
        buddy.onOpenIsland = { [weak self] in self?.island.expand(sticky: true) }

        if !Demo.isOn { ClaudeConnector.refreshScriptIfConnected() }
        wireClaude()
        wireTimer()
        wireSystem()
        Hotkeys.shared.handler = { [weak self] action in self?.hotkey(action) }
        Hotkeys.shared.reload()
        ClaudeHub.shared.start()

        prefs.$c
            .removeDuplicates()
            .sink { [weak self] c in self?.apply(c) }
            .store(in: &bag)

        if !prefs.c.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showOnboarding() }
        } else if prefs.c.greetOnLaunch {
            greet()
        }
        Demo.run(island)
    }

    func applicationWillTerminate(_ note: Notification) {
        ClaudeHub.shared.stop()
        SystemSwitches.keepAwake(false)
    }

    /// Launching the app again while it runs opens Settings, so it's never unreachable.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: - Wiring

    private func wireClaude() {
        let hub = ClaudeHub.shared
        hub.onAttention = { [weak self] in self?.island.attention() }
        hub.onDone = { [weak self] s in
            guard let self, !hub.isSnoozed else { return }
            if self.prefs.c.peekOnDone && !self.island.model.expanded {
                self.island.model.show(peek: .init(text: "\(s.project) is done", symbol: "checkmark.circle.fill", color: Mood.happy.color))
            }
            if self.prefs.c.celebrate { self.island.model.celebrate() }
        }
        hub.onNotice = { [weak self] text, symbol, mood in
            guard let self, !hub.isSnoozed else { return }
            if mood == .sad || mood == .attention, self.prefs.c.soundOnPermission { Sounds.shared.play(.attention) }
            self.island.model.show(peek: .init(text: text, symbol: symbol, color: mood.color), for: 5)
        }
        hub.onFailure = { [weak self] s in
            guard let self, !hub.isSnoozed, !self.island.model.expanded else { return }
            self.island.model.show(peek: .init(text: "A tool failed in \(s.project)", symbol: "exclamationmark.triangle.fill", color: Mood.sad.color), for: 3)
        }
    }

    private func wireSystem() {
        PowerWatcher.shared.onChange = { [weak self] text, symbol, mood in
            self?.island.model.show(peek: .init(text: text, symbol: symbol, color: mood.color), for: 3)
        }
        PowerWatcher.shared.start()
        DownloadWatcher.shared.onDownload = { [weak self] url in
            guard let self else { return }
            if self.prefs.c.downloadsToShelf { ShelfStore.shared.add(url) }
            self.island.model.show(peek: .init(text: "Downloaded \(url.lastPathComponent)", symbol: "arrow.down.circle.fill", color: Mood.happy.color))
        }
    }

    private func wireTimer() {
        FocusTimer.shared.onFinish = { [weak self] mode in
            guard let self else { return }
            if self.prefs.c.soundOnTimer { Sounds.shared.play(.timer) }
            self.island.model.show(peek: .init(text: mode == .focus ? "Focus done. Take a break!" : "Break's over",
                                               symbol: mode == .focus ? "cup.and.saucer.fill" : "bolt.fill", color: Mood.happy.color))
            if mode == .focus && self.prefs.c.celebrate { self.island.model.celebrate() }
        }
    }

    private func greet() {
        Activity.greetUntil = Date().addingTimeInterval(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.island.model.show(peek: .init(text: "Hi, I'm \(self.prefs.c.mascotName)", symbol: "hand.wave.fill", color: self.prefs.c.accent), for: 3)
        }
    }

    /// Turns services on only while something on screen needs them.
    private func apply(_ c: Config) {
        MusicService.shared.setActive(c.uses(TileKind.music) || c.uses(WingContent.music) || c.mascotColor == .mood || c.outfit == .seasonal)
        CalendarService.shared.setActive(c.uses(TileKind.calendar) || c.uses(WingContent.meeting))
        WeatherService.shared.setActive(c.uses(TileKind.weather))
        SystemStats.shared.setActive(c.uses(TileKind.system) || c.uses(WingContent.battery) || c.uses(WingContent.cpu))
        ClipboardService.shared.setActive(c.uses(TileKind.clipboard))
        DownloadWatcher.shared.setActive(c.downloadAlerts)
        if !c.lyrics { LyricsService.shared.update(for: nil) } else { LyricsService.shared.update(for: MusicService.shared.track) }
        buddy.setVisible(c.desktopBuddy)
        updateStatusItem(c)
    }

    private func hotkey(_ action: HotkeyAction) {
        let hub = ClaudeHub.shared
        switch action {
        case .toggleIsland: island.toggle()
        case .claudeTab: island.model.expanded && island.model.tab == .claude ? island.collapse() : island.expand(tab: .claude, sticky: true)
        case .allow:
            guard let p = hub.pending.first else { return }
            if p.risk != nil {
                // Risky requests need the press-and-hold in the notch, never a shortcut.
                island.expand(tab: nil, sticky: true)
                island.model.show(peek: .init(text: "Hold Allow in the notch for this one", symbol: "hand.raised.fill", color: Mood.sad.color), for: 3)
            } else {
                hub.answer(p.id, .allow)
            }
        case .deny: if let p = hub.pending.first { hub.answer(p.id, .deny(nil)) }
        case .always: if let p = hub.pending.first, p.risk == nil { hub.answer(p.id, .always) }
        case .focusTimer: FocusTimer.shared.toggle()
        }
    }

    // MARK: - Menu bar

    private func updateStatusItem(_ c: Config) {
        if !c.showMenuBarIcon {
            if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Wisp")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hub = ClaudeHub.shared
        let header = NSMenuItem(title: hub.live.isEmpty ? "\(prefs.c.mascotName) is resting" : "\(hub.live.count) Claude session\(hub.live.count == 1 ? "" : "s") working", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for s in hub.ordered.prefix(5) {
            let i = NSMenuItem(title: "\(s.project) — \(s.activity)", action: #selector(focusSession(_:)), keyEquivalent: "")
            i.representedObject = s.id
            i.target = self
            menu.addItem(i)
        }
        menu.addItem(.separator())
        add(menu, "Open the island", #selector(openIsland))
        add(menu, "Claude sessions", #selector(openClaude))
        add(menu, FocusTimer.shared.running ? "Pause focus timer" : "Start focus timer", #selector(toggleTimer))
        add(menu, hub.isSnoozed ? "Stop snoozing" : "Snooze alerts for 30 min", #selector(toggleSnooze))
        add(menu, prefs.c.desktopBuddy ? "Bring \(prefs.c.mascotName) home" : "Let \(prefs.c.mascotName) roam the desktop", #selector(toggleBuddy))
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettingsAction), key: ",")
        add(menu, "Quit Wisp", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, key: String = "") {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
    }

    @objc private func focusSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ClaudeHub.shared.selectedID = id
        island.expand(tab: .claude, sticky: true)
    }
    @objc private func openIsland() { island.expand(sticky: true) }
    @objc private func openClaude() { island.expand(tab: .claude, sticky: true) }
    @objc private func toggleTimer() { FocusTimer.shared.toggle() }
    @objc private func toggleSnooze() { let h = ClaudeHub.shared; h.snooze(minutes: h.isSnoozed ? nil : 30) }
    @objc private func toggleBuddy() { prefs.c.desktopBuddy.toggle() }
    @objc private func openSettingsAction() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Windows

    func openSettings(page: SettingsPage? = nil) {
        if let page { router.page = page }
        island.collapse()
        if settingsWindow == nil {
            let view = SettingsView().environmentObject(prefs).environmentObject(router)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Wisp Settings"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("WispSettings")
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let view = OnboardingView { [weak self] in
            guard let self else { return }
            self.prefs.c.onboarded = true
            self.onboardingWindow?.close()
            self.greet()
        }
        .environmentObject(prefs)
        let w = onboardingWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.title = "Welcome to Wisp"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.center()
        onboardingWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
