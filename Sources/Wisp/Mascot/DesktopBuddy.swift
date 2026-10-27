import AppKit
import SwiftUI

/// Lets the wisp leave the notch and float on the desktop. Drag it anywhere; it remembers.
final class DesktopBuddy: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    var onOpenIsland: (() -> Void)?

    func setVisible(_ on: Bool) {
        if on, panel == nil { show() } else if !on { panel?.close(); panel = nil }
    }

    private func show() {
        let size = NSSize(width: 150, height: 170)
        let c = Prefs.shared.c
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        let origin = c.buddyX >= 0 ? NSPoint(x: c.buddyX, y: c.buddyY) : NSPoint(x: screen.maxX - size.width - 40, y: screen.minY + 60)
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        let view = BuddyView(open: { [weak self] in self?.onOpenIsland?() }, home: { Prefs.shared.c.desktopBuddy = false })
            .environmentObject(Prefs.shared)
        p.contentView = FirstMouseHostingView(rootView: AnyView(view))
        p.orderFrontRegardless()
        panel = p
    }

    func windowDidMove(_ notification: Notification) {
        guard let f = panel?.frame else { return }
        Prefs.shared.c.buddyX = f.minX
        Prefs.shared.c.buddyY = f.minY
    }
}

private struct BuddyView: View {
    let open: () -> Void
    let home: () -> Void
    @EnvironmentObject private var prefs: Prefs

    var body: some View {
        MascotView(size: 120, showCaption: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open() }
            .contextMenu {
                Button("Open the island") { open() }
                Menu("Outfit") {
                    ForEach(Outfit.allCases) { o in
                        Button { prefs.c.outfit = o } label: {
                            if prefs.c.outfit == o { Label(o.label, systemImage: "checkmark") } else { Text(o.label) }
                        }
                    }
                }
                Menu("Shape") {
                    ForEach(MascotStyle.allCases) { s in Button(s.label) { prefs.c.mascotStyle = s } }
                }
                Divider()
                Button("Go back to the notch") { home() }
            }
            .environment(\.look, prefs.c.look)
    }
}
