import SwiftUI

enum Mood: String, CaseIterable {
    case idle, thinking, attention, happy, sad, sleeping, vibing, poked, dizzy

    var color: Color {
        switch self {
        case .idle: .hex("#7CC4FF")
        case .thinking: .hex("#A78BFA")
        case .attention: .hex("#FFB020")
        case .happy: .hex("#4ADE80")
        case .sad: .hex("#F87171")
        case .sleeping: .hex("#7B8BA3")
        case .vibing: .hex("#F472B6")
        case .poked: .hex("#FB923C")
        case .dizzy: .hex("#C084FC")
        }
    }

    var speed: Double {
        switch self {
        case .thinking: 1.8
        case .attention: 2.2
        case .happy: 1.5
        case .sleeping: 0.35
        case .vibing: 1.2
        case .dizzy: 2.5
        default: 1
        }
    }

    var caption: String {
        switch self {
        case .idle: "Hi there"
        case .thinking: "On it…"
        case .attention: "Need you!"
        case .happy: "All done ✨"
        case .sad: "Oops"
        case .sleeping: "zz…"
        case .vibing: "♪ ♫"
        case .poked: "Hey!"
        case .dizzy: "@_@ stop it"
        }
    }
}

/// When anyone last touched the island; keeps the wisp awake.
enum Activity {
    static var lastInteraction = Date()
    static var greetUntil = Date.distantPast
    private static var pokes: [Date] = []
    private(set) static var pokedAt = Date.distantPast
    private(set) static var dizzyUntil = Date.distantPast

    /// Poke once and the wisp grumbles; five quick pokes and it gets dizzy.
    static func poke() {
        guard Prefs.shared.c.pokeable else { return }
        let now = Date()
        lastInteraction = now
        pokedAt = now
        pokes = pokes.filter { now.timeIntervalSince($0) < 3 } + [now]
        if pokes.count >= 5 {
            dizzyUntil = now.addingTimeInterval(3.5)
            pokes.removeAll()
        }
        SystemSwitches.haptic()
    }
}

enum MoodEngine {
    static func current(_ now: Date = .now) -> Mood {
        let hub = ClaudeHub.shared
        if hub.needsYou { return .attention }
        if now < Activity.dizzyUntil { return .dizzy }
        if now.timeIntervalSince(Activity.pokedAt) < 1.2 { return .poked }
        if now < Activity.greetUntil { return .happy }
        if let f = hub.lastFailure, now.timeIntervalSince(f) < 4 { return .sad }
        if let d = hub.lastDone, now.timeIntervalSince(d.at) < 8 { return .happy }
        if let t = FocusTimer.shared.finishedAt, now.timeIntervalSince(t) < 6 { return .happy }
        if !hub.live.isEmpty { return .thinking }
        if MusicService.shared.isPlaying { return .vibing }
        let last = max(hub.lastActivity, Activity.lastInteraction)
        if now.timeIntervalSince(last) > Prefs.shared.c.personality.dozeAfter { return .sleeping }
        return .idle
    }
}

/// The wisp. Drawn every frame in a Canvas, so any size stays crisp.
struct MascotView: View {
    var size: CGFloat
    var mood: Mood? = nil
    var style: MascotStyle? = nil
    var outfit: Outfit? = nil
    var showCaption = false

    @EnvironmentObject private var prefs: Prefs
    @ObservedObject private var music = MusicService.shared
    @State private var locator = ViewLocator()

    var body: some View {
        let c = prefs.c
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !c.mascotEnabled)) { tl in
            let m = mood ?? MoodEngine.current(tl.date)
            let t = tl.date.timeIntervalSinceReferenceDate
            VStack(spacing: 4) {
                Canvas { ctx, sz in
                    MascotPainter(t: t * c.personality.speed * m.speed, rawTime: t, mood: m,
                                  style: style ?? c.mascotStyle, color: color(c, m, t),
                                  outfit: Outfit.resolved(outfit ?? c.outfit, musicPlaying: music.isPlaying, date: tl.date),
                                  gaze: c.eyesFollowCursor ? locator.gaze() : .zero).draw(ctx, sz)
                }
                .frame(width: size, height: size)
                .background(LocatorView(locator: locator))
                if showCaption && c.mascotSpeaks {
                    Text(m.caption).font(.system(size: max(10, size * 0.14), design: c.font)).foregroundStyle(.secondary)
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded { Activity.poke() })
    }

    private func color(_ c: Config, _ m: Mood, _ t: Double) -> Color {
        switch c.mascotColor {
        case .accent: return c.accent
        case .custom: return .hex(c.mascotHex)
        case .rainbow: return Color(hue: (t * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 1)
        case .mood: return m == .vibing ? (music.tint ?? m.color) : m.color
        }
    }
}

/// Finds where the wisp is on screen so its eyes can follow the pointer.
final class ViewLocator {
    weak var view: NSView?

    /// -1...1 in each direction, toward the pointer.
    func gaze() -> CGVector {
        guard let view, let window = view.window else { return .zero }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        let m = NSEvent.mouseLocation
        let dx = m.x - frame.midX, dy = frame.midY - m.y
        let dist = max(1, hypot(dx, dy))
        let reach = min(1, dist / 260)
        return CGVector(dx: dx / dist * reach, dy: dy / dist * reach)
    }
}

private struct LocatorView: NSViewRepresentable {
    let locator: ViewLocator
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        locator.view = v
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { locator.view = v }
}

struct MascotPainter {
    let t: Double
    let rawTime: Double
    let mood: Mood
    let style: MascotStyle
    let color: Color
    var outfit: Outfit = .none
    var gaze: CGVector = .zero

    func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let s = min(size.width, size.height) * 0.84
        var bob = sin(t * 2) * s * 0.03
        switch mood {
        case .attention: bob = -abs(sin(t * 5)) * s * 0.1
        case .happy: bob = -abs(sin(t * 4)) * s * 0.06
        case .vibing: bob = sin(t * 5.2) * s * 0.05
        case .sleeping: bob = sin(t * 1.2) * s * 0.02
        case .poked: bob = -s * 0.05 * max(0, 1 - (rawTime.truncatingRemainder(dividingBy: 1.2)) * 3)
        default: break
        }
        let wobble = mood == .dizzy ? sin(t * 3) * s * 0.06 : 0
        let ox = (size.width - s) / 2 + wobble
        let oy = (size.height - s) / 2 + bob + s * 0.04
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        // Soft glow behind the body.
        var glow = ctx
        glow.addFilter(.blur(radius: s * 0.12))
        glow.opacity = mood == .sleeping ? 0.25 : 0.55 + 0.15 * sin(t * 3)
        glow.fill(Path(ellipseIn: CGRect(origin: p(0.18, 0.3), size: CGSize(width: s * 0.64, height: s * 0.64))), with: .color(color))

        let body = bodyPath(p, s)
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [color.opacity(0.85), color, lighter(color)]),
            startPoint: p(0.5, 0.05), endPoint: p(0.5, 0.95)))

        if style == .flame {
            // A brighter core that flickers.
            let sw = sin(t * 3.1) * 0.03
            var core = Path()
            core.move(to: p(0.5 + sw, 0.42))
            core.addCurve(to: p(0.66, 0.78), control1: p(0.56 + sw, 0.55), control2: p(0.68, 0.64))
            core.addCurve(to: p(0.34, 0.78), control1: p(0.64, 0.92), control2: p(0.36, 0.92))
            core.addCurve(to: p(0.5 + sw, 0.42), control1: p(0.32, 0.64), control2: p(0.44 + sw, 0.55))
            ctx.fill(core, with: .color(.white.opacity(0.28)))
        }
        if style == .orb {
            let a = t * 1.6
            let dot = p(0.5 + cos(a) * 0.46, 0.58 + sin(a) * 0.16)
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - s * 0.045, y: dot.y - s * 0.045, width: s * 0.09, height: s * 0.09)), with: .color(color.opacity(0.9)))
        }
        if style == .cat {
            var whiskers = Path()
            for (y, dy) in [(0.72, -0.03), (0.76, 0.02)] {
                whiskers.move(to: p(0.27, y)); whiskers.addLine(to: p(0.08, y + dy))
                whiskers.move(to: p(0.73, y)); whiskers.addLine(to: p(0.92, y + dy))
            }
            ctx.stroke(whiskers, with: .color(.black.opacity(0.35)), lineWidth: max(0.6, s * 0.015))
        }

        if style == .pixel { pixelFace(ctx, p, s) } else { face(ctx, p, s) }
        wear(ctx, p, s)
        extras(ctx, p, s)
    }

    // MARK: Bodies

    private func bodyPath(_ p: (Double, Double) -> CGPoint, _ s: Double) -> Path {
        var path = Path()
        switch style {
        case .flame:
            let sw = sin(t * 2.3) * 0.05 + sin(t * 5.7) * 0.015
            path.move(to: p(0.5 + sw, 0.04))
            path.addCurve(to: p(0.82, 0.64), control1: p(0.58 + sw, 0.22), control2: p(0.84, 0.42))
            path.addCurve(to: p(0.5, 0.96), control1: p(0.82, 0.83), control2: p(0.68, 0.96))
            path.addCurve(to: p(0.18, 0.64), control1: p(0.32, 0.96), control2: p(0.18, 0.83))
            path.addCurve(to: p(0.5 + sw, 0.04), control1: p(0.16, 0.42), control2: p(0.42 + sw, 0.22))
        case .orb:
            let breathe = 0.36 + sin(t * 2) * 0.012
            let c = p(0.5, 0.6)
            path.addEllipse(in: CGRect(x: c.x - breathe * s, y: c.y - breathe * s, width: 2 * breathe * s, height: 2 * breathe * s))
        case .ghost:
            path.move(to: p(0.16, 0.92))
            path.addLine(to: p(0.16, 0.52))
            path.addCurve(to: p(0.84, 0.52), control1: p(0.16, 0.08), control2: p(0.84, 0.08))
            path.addLine(to: p(0.84, 0.92))
            let bumps = 4
            for i in 0..<bumps {
                let x0 = 0.84 - Double(i) * 0.68 / Double(bumps)
                let x1 = x0 - 0.68 / Double(bumps)
                let wave = sin(t * 3 + Double(i)) * 0.03
                path.addQuadCurve(to: p(x1, 0.92), control: p((x0 + x1) / 2, (i % 2 == 0 ? 0.8 : 1.02) + wave))
            }
            path.closeSubpath()
        case .pixel:
            let rows = [
                "..XXXX..",
                ".XXXXXX.",
                "XXXXXXXX",
                "XXXXXXXX",
                "XXXXXXXX",
                "XXXXXXXX",
                "XX.XX.XX",
                Int(t * 2) % 2 == 0 ? "X..X..X." : ".X..X..X",
            ]
            let cell = 0.8 / 8
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() where ch == "X" {
                    let o = p(0.1 + Double(c) * cell, 0.16 + Double(r) * cell)
                    path.addRect(CGRect(x: o.x, y: o.y, width: cell * s + 0.5, height: cell * s + 0.5))
                }
            }
        case .cat:
            let c = p(0.5, 0.64)
            path.addEllipse(in: CGRect(x: c.x - 0.33 * s, y: c.y - 0.3 * s, width: 0.66 * s, height: 0.6 * s))
            let twitch = sin(t * 1.3) > 0.97 ? 0.04 : 0
            path.move(to: p(0.2, 0.5)); path.addLine(to: p(0.22 - twitch, 0.14)); path.addLine(to: p(0.44, 0.38)); path.closeSubpath()
            path.move(to: p(0.8, 0.5)); path.addLine(to: p(0.78, 0.14)); path.addLine(to: p(0.56, 0.38)); path.closeSubpath()
        case .star:
            let center = p(0.5, 0.58)
            let rot = sin(t * 0.8) * 0.25
            for i in 0..<10 {
                let r = (i % 2 == 0 ? 0.44 : 0.2) * s
                let a = Double(i) * .pi / 5 - .pi / 2 + rot
                let pt = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
        }
        return path
    }

    // MARK: Faces

    private var eyeY: Double {
        switch style {
        case .flame: 0.64
        case .orb: 0.58
        case .ghost: 0.5
        case .cat: 0.62
        case .star: 0.56
        case .pixel: 0.5
        }
    }

    private func face(_ ctx: GraphicsContext, _ p: (Double, Double) -> CGPoint, _ s: Double) {
        let ink = Color.black.opacity(0.78)
        let line = max(1, s * 0.05)
        let spread = style == .star ? 0.09 : 0.12
        let look = mood == .thinking ? sin(t * 1.4) * 0.035 : gaze.dx * 0.035
        let y = eyeY + (mood == .thinking ? 0 : gaze.dy * 0.025)
        let blink = (rawTime.truncatingRemainder(dividingBy: 3.7)) < 0.13

        for side in [-1.0, 1.0] {
            let x = 0.5 + side * spread + look
            switch mood {
            case .dizzy:
                var spiral = Path()
                let c = p(x, y)
                for k in 0..<18 {
                    let a = Double(k) * 0.7 + rawTime * 9 * side
                    let r = 0.004 * s + Double(k) * 0.0028 * s
                    let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    k == 0 ? spiral.move(to: pt) : spiral.addLine(to: pt)
                }
                ctx.stroke(spiral, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.6, lineCap: .round))
            case .poked:
                var squint = Path()
                squint.move(to: p(x - side * 0.045, y - 0.04))
                squint.addLine(to: p(x + side * 0.03, y))
                squint.addLine(to: p(x - side * 0.045, y + 0.04))
                ctx.stroke(squint, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round, lineJoin: .round))
            case .happy:
                var arc = Path()
                arc.move(to: p(x - 0.05, y + 0.02))
                arc.addQuadCurve(to: p(x + 0.05, y + 0.02), control: p(x, y - 0.07))
                ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
            case .sleeping:
                var dash = Path()
                dash.move(to: p(x - 0.045, y + 0.01))
                dash.addQuadCurve(to: p(x + 0.045, y + 0.01), control: p(x, y + 0.05))
                ctx.stroke(dash, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
            case .sad:
                let h = blink ? 0.015 : 0.08
                ctx.fill(Path(ellipseIn: CGRect(origin: p(x - 0.035, y - h / 2 + 0.02), size: CGSize(width: 0.07 * s, height: h * s))), with: .color(ink))
                var brow = Path()
                brow.move(to: p(x - side * 0.06, y - 0.09)); brow.addLine(to: p(x + side * 0.03, y - 0.06))
                ctx.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round))
            default:
                let wide = mood == .attention ? 1.25 : 1
                let h = blink ? 0.015 : 0.11 * wide
                let w = 0.068 * wide
                ctx.fill(Path(ellipseIn: CGRect(origin: p(x - w / 2, y - h / 2), size: CGSize(width: w * s, height: h * s))), with: .color(ink))
                if !blink {
                    ctx.fill(Path(ellipseIn: CGRect(origin: p(x - w / 6, y - h / 3), size: CGSize(width: w * 0.35 * s, height: w * 0.35 * s))), with: .color(.white.opacity(0.85)))
                }
            }
        }

        // Mouth
        var mouth = Path()
        let my = y + 0.12
        switch mood {
        case .happy, .vibing:
            mouth.move(to: p(0.45, my)); mouth.addQuadCurve(to: p(0.55, my), control: p(0.5, my + 0.07))
            ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
        case .sad, .poked:
            mouth.move(to: p(0.45, my + 0.04)); mouth.addQuadCurve(to: p(0.55, my + 0.04), control: p(0.5, my - 0.02))
            ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
        case .dizzy:
            mouth.move(to: p(0.44, my + 0.02))
            mouth.addCurve(to: p(0.56, my + 0.02), control1: p(0.48, my - 0.03), control2: p(0.52, my + 0.07))
            ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round))
        case .attention:
            ctx.fill(Path(ellipseIn: CGRect(origin: p(0.47, my - 0.01), size: CGSize(width: 0.06 * s, height: 0.07 * s))), with: .color(ink))
        default:
            break
        }

        // Blush when happy.
        if mood == .happy || mood == .vibing {
            for side in [-1.0, 1.0] {
                let c = p(0.5 + side * 0.22, y + 0.08)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.045, y: c.y - s * 0.022, width: s * 0.09, height: s * 0.044)), with: .color(.pink.opacity(0.5)))
            }
        }
    }

    private func pixelFace(_ ctx: GraphicsContext, _ p: (Double, Double) -> CGPoint, _ s: Double) {
        let cell = 0.1
        let blink = (rawTime.truncatingRemainder(dividingBy: 3.7)) < 0.13 || mood == .sleeping
        let look = mood == .thinking ? (Int(t) % 2 == 0 ? -1.0 : 1.0) * cell * 0.5 : (gaze.dx * 2).rounded() * cell * 0.25
        for col in [2.0, 5.0] {
            let o = p(0.1 + col * cell + look, 0.16 + 2 * cell)
            let h = blink ? cell * 0.35 : cell * (mood == .happy ? 0.5 : 2)
            ctx.fill(Path(CGRect(x: o.x, y: o.y + (blink ? cell : 0), width: cell * s, height: h * s)), with: .color(.black.opacity(0.8)))
        }
    }

    // MARK: Wardrobe

    private var headTop: Double {
        switch style {
        case .flame: 0.2
        case .orb: 0.25
        case .ghost: 0.17
        case .pixel: 0.17
        case .cat: 0.3
        case .star: 0.18
        }
    }

    private func wear(_ ctx: GraphicsContext, _ p: (Double, Double) -> CGPoint, _ s: Double) {
        let top = headTop
        let line = max(0.8, s * 0.035)
        switch outfit {
        case .none, .seasonal:
            break
        case .partyHat:
            var cone = Path()
            cone.move(to: p(0.37, top + 0.06)); cone.addLine(to: p(0.5, top - 0.24)); cone.addLine(to: p(0.63, top + 0.06)); cone.closeSubpath()
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [.hex("#F472B6"), .hex("#FACC15")]), startPoint: p(0.4, top), endPoint: p(0.6, top - 0.2)))
            for k in 1...2 {
                let y = top + 0.06 - Double(k) * 0.1
                let half = 0.13 * (1 - Double(k) * 0.33)
                var stripe = Path(); stripe.move(to: p(0.5 - half, y)); stripe.addLine(to: p(0.5 + half, y))
                ctx.stroke(stripe, with: .color(.white.opacity(0.8)), lineWidth: line)
            }
            ctx.fill(Path(ellipseIn: CGRect(origin: p(0.47, top - 0.28), size: CGSize(width: s * 0.06, height: s * 0.06))), with: .color(.white))
        case .beanie:
            var cap = Path()
            cap.move(to: p(0.3, top + 0.06))
            cap.addCurve(to: p(0.7, top + 0.06), control1: p(0.3, top - 0.2), control2: p(0.7, top - 0.2))
            cap.closeSubpath()
            ctx.fill(cap, with: .color(.hex("#38BDF8")))
            ctx.fill(Path(roundedRect: CGRect(origin: p(0.28, top + 0.02), size: CGSize(width: s * 0.44, height: s * 0.07)), cornerRadius: s * 0.03), with: .color(.hex("#0EA5E9")))
            ctx.fill(Path(ellipseIn: CGRect(origin: p(0.46, top - 0.19), size: CGSize(width: s * 0.08, height: s * 0.08))), with: .color(.white))
        case .crown:
            var crown = Path()
            crown.move(to: p(0.34, top + 0.05)); crown.addLine(to: p(0.34, top - 0.08)); crown.addLine(to: p(0.42, top - 0.02))
            crown.addLine(to: p(0.5, top - 0.12)); crown.addLine(to: p(0.58, top - 0.02)); crown.addLine(to: p(0.66, top - 0.08))
            crown.addLine(to: p(0.66, top + 0.05)); crown.closeSubpath()
            ctx.fill(crown, with: .linearGradient(Gradient(colors: [.hex("#FDE68A"), .hex("#F59E0B")]), startPoint: p(0.5, top - 0.12), endPoint: p(0.5, top + 0.05)))
            ctx.fill(Path(ellipseIn: CGRect(origin: p(0.48, top - 0.03), size: CGSize(width: s * 0.04, height: s * 0.04))), with: .color(.red))
        case .witchHat:
            ctx.fill(Path(ellipseIn: CGRect(origin: p(0.22, top - 0.01), size: CGSize(width: s * 0.56, height: s * 0.09))), with: .color(.hex("#2E1065")))
            var cone = Path()
            cone.move(to: p(0.36, top + 0.03))
            cone.addQuadCurve(to: p(0.62, top - 0.3), control: p(0.42, top - 0.2))
            cone.addQuadCurve(to: p(0.64, top + 0.03), control: p(0.58, top - 0.12))
            cone.closeSubpath()
            ctx.fill(cone, with: .color(.hex("#4C1D95")))
            ctx.fill(Path(CGRect(origin: p(0.37, top - 0.03), size: CGSize(width: s * 0.27, height: s * 0.04))), with: .color(.hex("#F97316")))
        case .santaHat:
            var cone = Path()
            cone.move(to: p(0.32, top + 0.04))
            cone.addQuadCurve(to: p(0.74, top - 0.06), control: p(0.48, top - 0.3))
            cone.addQuadCurve(to: p(0.68, top + 0.04), control: p(0.62, top - 0.08))
            cone.closeSubpath()
            ctx.fill(cone, with: .color(.hex("#DC2626")))
            ctx.fill(Path(roundedRect: CGRect(origin: p(0.29, top + 0.01), size: CGSize(width: s * 0.42, height: s * 0.07)), cornerRadius: s * 0.035), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(origin: p(0.71, top - 0.1), size: CGSize(width: s * 0.08, height: s * 0.08))), with: .color(.white))
        case .headphones:
            var band = Path()
            band.move(to: p(0.17, eyeY))
            band.addCurve(to: p(0.83, eyeY), control1: p(0.17, top - 0.16), control2: p(0.83, top - 0.16))
            ctx.stroke(band, with: .color(.hex("#1F2937")), style: StrokeStyle(lineWidth: line * 1.4, lineCap: .round))
            for x in [0.1, 0.8] {
                ctx.fill(Path(roundedRect: CGRect(origin: p(x, eyeY - 0.07), size: CGSize(width: s * 0.1, height: s * 0.16)), cornerRadius: s * 0.04), with: .color(.hex("#111827")))
                ctx.fill(Path(roundedRect: CGRect(origin: p(x + 0.02, eyeY - 0.04), size: CGSize(width: s * 0.06, height: s * 0.1)), cornerRadius: s * 0.02), with: .color(color.opacity(0.8)))
            }
        case .sunglasses:
            for side in [-1.0, 1.0] {
                let x = 0.5 + side * 0.12
                ctx.fill(Path(roundedRect: CGRect(origin: p(x - 0.08, eyeY - 0.05), size: CGSize(width: s * 0.16, height: s * 0.1)), cornerRadius: s * 0.03), with: .color(.black.opacity(0.92)))
                ctx.fill(Path(roundedRect: CGRect(origin: p(x - 0.06, eyeY - 0.04), size: CGSize(width: s * 0.05, height: s * 0.02)), cornerRadius: s * 0.01), with: .color(.white.opacity(0.5)))
            }
            var bridge = Path(); bridge.move(to: p(0.46, eyeY - 0.02)); bridge.addLine(to: p(0.54, eyeY - 0.02))
            ctx.stroke(bridge, with: .color(.black), lineWidth: line)
        case .bow:
            let c = p(0.68, top + 0.04)
            for side in [-1.0, 1.0] {
                var wing = Path()
                wing.move(to: c)
                wing.addLine(to: CGPoint(x: c.x + side * s * 0.11, y: c.y - s * 0.06))
                wing.addLine(to: CGPoint(x: c.x + side * s * 0.11, y: c.y + s * 0.06))
                wing.closeSubpath()
                ctx.fill(wing, with: .color(.hex("#EC4899")))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.03, y: c.y - s * 0.03, width: s * 0.06, height: s * 0.06)), with: .color(.hex("#BE185D")))
        }
    }

    // MARK: Extras (sparkles, z's, exclamation, notes)

    private func extras(_ ctx: GraphicsContext, _ p: (Double, Double) -> CGPoint, _ s: Double) {
        switch mood {
        case .happy:
            for i in 0..<3 {
                let phase = rawTime * 2 + Double(i) * 2.1
                let twinkle = (sin(phase) + 1) / 2
                let pos = [p(0.08, 0.2), p(0.9, 0.3), p(0.86, 0.04)][i]
                sparkle(ctx, at: pos, r: s * 0.09 * twinkle, color: .yellow)
            }
        case .sleeping:
            let k = (rawTime * 0.5).truncatingRemainder(dividingBy: 1)
            var z = ctx
            z.opacity = 1 - k
            z.draw(Text("z").font(.system(size: max(6, s * 0.28), weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.8)),
                   at: p(0.82 + k * 0.1, 0.18 - k * 0.2))
        case .attention:
            var mark = ctx
            mark.opacity = 0.6 + 0.4 * sin(rawTime * 8)
            mark.draw(Text("!").font(.system(size: max(7, s * 0.34), weight: .black, design: .rounded)).foregroundColor(color),
                      at: p(0.9, 0.12))
        case .dizzy:
            for i in 0..<3 {
                let a = rawTime * 4 + Double(i) * 2.09
                sparkle(ctx, at: p(0.5 + cos(a) * 0.36, 0.1 + sin(a) * 0.07), r: s * 0.06, color: .yellow)
            }
        case .poked:
            var mark = ctx
            mark.draw(Text("#").font(.system(size: max(6, s * 0.22), weight: .black, design: .rounded)).foregroundColor(.red.opacity(0.8)),
                      at: p(0.84, 0.2))
        case .vibing:
            let k = (rawTime * 0.6).truncatingRemainder(dividingBy: 1)
            var note = ctx
            note.opacity = 1 - k
            note.draw(Text("♪").font(.system(size: max(6, s * 0.26))).foregroundColor(color),
                      at: p(0.1 - k * 0.06, 0.24 - k * 0.2))
        default:
            break
        }
    }

    private func sparkle(_ ctx: GraphicsContext, at c: CGPoint, r: Double, color: Color) {
        guard r > 0.3 else { return }
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        ctx.fill(path, with: .color(color))
    }

    private func lighter(_ c: Color) -> Color {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return c }
        return Color(nsColor: n.blended(withFraction: 0.45, of: .white) ?? n)
    }
}
