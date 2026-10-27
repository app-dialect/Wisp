import AppKit
import Carbon

/// Global shortcuts through Carbon's RegisterEventHotKey: no Accessibility permission needed.
final class Hotkeys {
    static let shared = Hotkeys()

    var handler: ((HotkeyAction) -> Void)?

    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var installed = false
    private var pendingActive = false
    private var suspended = false

    private init() {}

    func reload() {
        installIfNeeded()
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        guard !suspended else { return }
        let c = Prefs.shared.c
        for (index, action) in HotkeyAction.allCases.enumerated() {
            if action.onlyWhilePending && !pendingActive { continue }
            guard let combo = c.combo(action) else { continue }
            var ref: EventHotKeyRef?
            let hotID = EventHotKeyID(signature: OSType(0x5749_5350), id: UInt32(index)) // 'WISP'
            if RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs[action] = ref
            }
        }
    }

    /// Permission shortcuts exist only while a request is on screen.
    func refreshPending(_ active: Bool) {
        guard active != pendingActive else { return }
        pendingActive = active
        reload()
    }

    /// Lets the shortcut recorder hear keys that are already registered.
    func suspend(_ on: Bool) {
        suspended = on
        reload()
    }

    fileprivate func fire(_ id: UInt32) {
        let all = HotkeyAction.allCases
        guard Int(id) < all.count else { return }
        let action = all[Int(id)]
        DispatchQueue.main.async { self.handler?(action) }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            Hotkeys.shared.fire(hk.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    // MARK: - Turning NSEvents into combos

    static func combo(from event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        var text = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); text += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); text += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); text += "⌘" }
        guard mods != 0 else { return nil }
        text += keyName(event)
        return KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: mods, display: text)
    }

    private static func keyName(_ e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
