import SwiftUI
import UniformTypeIdentifiers

struct IslandRoot: View {
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel
    @ObservedObject private var hub = ClaudeHub.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var timer = FocusTimer.shared
    @ObservedObject private var calendar = CalendarService.shared

    var body: some View {
        let c = prefs.c
        let wings = WingLogic.visible(c, model: model)
        let size = model.expanded ? model.expandedSize(c) : model.collapsedSize(c, wings: wings)
        VStack(spacing: 0) {
            IslandBody(size: size, wings: wings)
                .frame(width: size.width, height: size.height)
                .padding(.top, model.topOffset(c))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.look, c.look)
        .font(.system(size: 12, design: c.font))
        .animation(c.motion.animation, value: model.expanded)
        .animation(c.motion.animation, value: wings)
        .animation(c.motion.animation, value: model.peek)
        .animation(c.motion.animation, value: hub.pending.count)
        .animation(c.motion.animation, value: hub.questions.count)
        .animation(c.motion.animation, value: model.tab)
    }
}

private struct IslandBody: View {
    let size: CGSize
    let wings: Bool
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared

    var body: some View {
        let c = prefs.c
        let floating = c.style == .floating
        let shape = IslandShape(
            top: floating ? 0 : (model.expanded ? 14 : 6),
            bottom: model.expanded ? c.cornerRadius : (floating ? size.height / 2 : min(12, size.height / 2.4)),
            floating: floating)

        ZStack(alignment: .top) {
            background(c, floating: floating)
            if model.expanded {
                ExpandedView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                CollapsedView(wings: wings)
                    .transition(.opacity)
            }
            if let at = model.confettiAt, c.celebrate {
                Confetti(start: at).allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .background(alignment: .top) { glow(shape, c) }
        .shadow(color: .black.opacity(c.shadow && model.expanded ? 0.45 : 0), radius: 18, y: 8)
        .contentShape(shape)
        .onTapGesture { if !model.expanded && c.trigger == .click { model.expanded = true } }
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            ShelfStore.shared.accept(providers)
            return true
        }
    }

    @ViewBuilder
    private func background(_ c: Config, floating: Bool) -> some View {
        let band = model.headerHeight(c)
        ZStack(alignment: .top) {
            if !floating && !model.expanded {
                Color.black
            } else {
                look.theme.background
                if c.glass { GlassView(dark: look.theme.isDark).opacity(0.92) }
                if !look.theme.wash.isEmpty {
                    LinearGradient(colors: look.theme.wash, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                if !floating {
                    // The strip next to the camera stays black so the island grows out of the notch.
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                           .init(color: .black.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: band + 10)
                }
            }
        }
    }

    @ViewBuilder
    private func glow(_ shape: IslandShape, _ c: Config) -> some View {
        if c.glow, let headline = hub.headline {
            let color = headline.phase == .waiting ? Mood.attention.color : (headline.phase == .done ? Mood.happy.color : c.accent)
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let pulse = 0.45 + 0.35 * sin(tl.date.timeIntervalSinceReferenceDate * (headline.phase == .waiting ? 5 : 2.2))
                shape.fill(color)
                    .blur(radius: 12)
                    .opacity(pulse)
                    .offset(y: 3)
            }
        }
    }
}

// MARK: - Collapsed

struct CollapsedView: View {
    let wings: Bool
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel

    var body: some View {
        let c = prefs.c
        let gap = c.style == .notch ? model.notch.width : 70
        let lyricExtra: CGFloat = MusicService.shared.isPlaying && !LyricsService.shared.lines.isEmpty ? 120 : 0
        HStack(spacing: 0) {
            if wings {
                WingView(content: c.leftWing, edge: .leading)
                    .frame(width: c.wingWidth + (c.leftWing == .lyrics ? lyricExtra : 0))
                Spacer(minLength: gap)
                if let peek = model.peek {
                    PeekView(peek: peek).frame(width: c.wingWidth + 150)
                } else {
                    WingView(content: c.rightWing, edge: .trailing)
                        .frame(width: c.wingWidth + (c.rightWing == .lyrics ? lyricExtra : 0))
                }
            } else if c.style == .floating {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

struct PeekView: View {
    let peek: IslandModel.Peek
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: peek.symbol).foregroundStyle(peek.color)
            Text(peek.text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel
    @Environment(\.look) private var look
    @ObservedObject private var hub = ClaudeHub.shared

    var body: some View {
        let c = prefs.c
        VStack(spacing: 0) {
            header(c)
                .frame(height: model.headerHeight(c))
            ZStack {
                switch model.tab {
                case .home: HomeView()
                case .claude: ClaudePanel()
                }
                if let p = hub.pending.first {
                    PermissionCard(request: p, queued: hub.pending.count)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let q = hub.questions.first {
                    QuestionCard(request: q)
                        .id(q.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
    }

    private func header(_ c: Config) -> some View {
        let ink: Color = c.style == .notch ? .white : look.theme.text
        let gap = c.style == .notch ? model.notch.width + 16 : 0
        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                tabButton(.home, "square.grid.2x2", "Home", ink)
                tabButton(.claude, "sparkles", hub.live.isEmpty ? "Claude" : "Claude · \(hub.live.count)", ink)
            }
            Spacer(minLength: gap)
            HStack(spacing: 2) {
                if c.mascotEnabled { MascotView(size: 22).padding(.trailing, 4) }
                iconButton(model.editing ? "checkmark" : "slider.horizontal.3", ink, help: "Edit tiles") {
                    model.tab = .home
                    model.editing.toggle()
                }
                iconButton(model.pinned ? "pin.fill" : "pin", ink, help: "Keep open") { model.pinned.toggle() }
                iconButton("gearshape", ink, help: "Settings") { model.openSettings?() }
            }
        }
        .padding(.horizontal, 16)
    }

    private func tabButton(_ tab: IslandModel.Tab, _ symbol: String, _ title: String, _ ink: Color) -> some View {
        let on = model.tab == tab
        return Button { model.tab = tab } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: on ? .semibold : .regular))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(on ? ink.opacity(0.16) : .clear))
            .foregroundStyle(on ? ink : ink.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, _ ink: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
                .foregroundStyle(ink.opacity(0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Effects

struct Confetti: View {
    let start: Date
    private static let pieces: [(x: Double, vx: Double, vy: Double, spin: Double, hue: Double, w: Double)] = (0..<48).map { _ in
        (Double.random(in: 0.3...0.7), Double.random(in: -0.6...0.6), Double.random(in: 0.2...1.0),
         Double.random(in: -8...8), Double.random(in: 0...1), Double.random(in: 4...8))
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t < 2.4 else { return }
                for p in Self.pieces {
                    let x = (p.x + p.vx * t * 0.5) * size.width
                    let y = (-0.1 + p.vy * t * 0.7 + 0.5 * t * t * 0.6) * size.height
                    var c = ctx
                    c.opacity = max(0, 1 - t / 2.4)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * t))
                    c.fill(Path(CGRect(x: -p.w / 2, y: -2, width: p.w, height: 4)),
                           with: .color(Color(hue: p.hue, saturation: 0.75, brightness: 1)))
                }
            }
        }
    }
}

struct Jiggle: ViewModifier {
    let active: Bool
    @State private var on = false
    private let delay = Double.random(in: 0...0.2)

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (on ? 1.3 : -1.3) : 0))
            .onAppear { start() }
            .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active else { on = false; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { on.toggle() }
        }
    }
}
