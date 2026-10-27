import SwiftUI

final class IslandModel: ObservableObject {
    enum Tab: String { case home, claude }

    struct Peek: Equatable {
        var id = UUID()
        var text: String
        var symbol: String
        var color: Color
    }

    @Published var expanded = false
    @Published var tab: Tab = .home
    @Published var editing = false
    @Published var pinned = false
    @Published var dropTargeted = false
    @Published var peek: Peek?
    @Published var confettiAt: Date?

    /// The camera housing on this screen, or a pretend one on screens without a notch.
    @Published var notch = CGSize(width: 196, height: 32)
    @Published var hasNotch = false
    @Published var menuBarHeight: CGFloat = 24

    var openSettings: (() -> Void)?
    private var peekTimer: Timer?

    func show(peek: Peek, for seconds: Double = 4.5) {
        self.peek = peek
        peekTimer?.invalidate()
        peekTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.peek = nil
        }
    }

    func celebrate() { confettiAt = .now }

    // MARK: Geometry

    func headerHeight(_ c: Config) -> CGFloat { c.style == .notch ? max(notch.height, 30) : 34 }

    func topOffset(_ c: Config) -> CGFloat { c.style == .notch ? 0 : menuBarHeight + 6 }

    func expandedSize(_ c: Config) -> CGSize {
        // Grow a little while Claude is waiting on a card, so questions and commands fit.
        let extra: CGFloat = ClaudeHub.shared.needsYou ? 84 : 0
        return CGSize(width: max(c.islandWidth, notch.width + 260), height: c.islandHeight + headerHeight(c) + extra)
    }

    func collapsedSize(_ c: Config, wings: Bool) -> CGSize {
        let extra: CGFloat = peek != nil ? 70 : 0
        switch c.style {
        case .notch:
            return wings ? CGSize(width: notch.width + 2 * c.wingWidth + extra, height: notch.height)
                         : CGSize(width: notch.width, height: notch.height)
        case .floating:
            return wings ? CGSize(width: 2 * c.wingWidth + 70 + extra, height: 34) : CGSize(width: 72, height: 8)
        }
    }

    /// The largest the island ever gets, so the window can be sized once.
    func maxSize(_ c: Config) -> CGSize {
        let e = expandedSize(c)
        let tall = e.height + (ClaudeHub.shared.needsYou ? 0 : 84)
        let w = collapsedSize(c, wings: true)
        return CGSize(width: max(e.width, w.width + 70), height: tall + topOffset(c))
    }
}
