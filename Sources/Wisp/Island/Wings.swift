import SwiftUI

/// What sits either side of the camera when the island is closed.
struct WingView: View {
    let content: WingContent
    let edge: HorizontalEdge

    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var model: IslandModel
    @ObservedObject private var hub = ClaudeHub.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var timer = FocusTimer.shared
    @ObservedObject private var stats = SystemStats.shared
    @ObservedObject private var calendar = CalendarService.shared

    var body: some View {
        let h = model.notch.height
        Group {
            switch content {
            case .none: Color.clear
            case .mascot: MascotView(size: min(h * 0.92, 30))
            case .claude: claude
            case .music: musicWing(h)
            case .timer: timerWing
            case .clock: clock
            case .battery: battery
            case .cpu: cpu
            case .meeting: meeting
            }
        }
        .font(.system(size: 11, weight: .medium, design: prefs.c.font))
        .padding(edge == .leading ? .leading : .trailing, 10)
        .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
    }

    @ViewBuilder private var claude: some View {
        if let p = hub.pending.first {
            Label { Text(p.tool) } icon: { Image(systemName: "hand.raised.fill").foregroundStyle(Mood.attention.color) }
                .lineLimit(1)
        } else if let s = hub.live.first {
            HStack(spacing: 4) {
                ThinkingDots(color: prefs.c.accent)
                Text(Date.now.timeIntervalSince(s.turnStarted ?? s.startedAt).short)
                    .monospacedDigit()
            }
        } else if let d = hub.lastDone, Date.now.timeIntervalSince(d.at) < 12 {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Mood.happy.color)
        } else {
            Image(systemName: "sparkles").opacity(0.5)
        }
    }

    @ViewBuilder private func musicWing(_ h: CGFloat) -> some View {
        if let t = music.track, t.playing {
            HStack(spacing: 5) {
                if edge == .leading, let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: h * 0.62, height: h * 0.62).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Equalizer(color: prefs.c.tintFromArtwork ? (music.tint ?? prefs.c.accent) : prefs.c.accent)
                    .frame(width: 18, height: h * 0.42)
            }
        } else {
            Image(systemName: "music.note").opacity(0.4)
        }
    }

    @ViewBuilder private var timerWing: some View {
        HStack(spacing: 4) {
            Ring(progress: timer.progress, color: timer.mode == .focus ? prefs.c.accent : Mood.happy.color, line: 2.5)
                .frame(width: 12, height: 12)
            Text(timer.label).monospacedDigit()
        }
        .opacity(timer.running ? 1 : 0.5)
    }

    private var clock: some View {
        TimelineView(.everyMinute) { tl in
            Text(tl.date, format: .dateTime.hour().minute()).monospacedDigit()
        }
    }

    @ViewBuilder private var battery: some View {
        if let b = stats.battery {
            HStack(spacing: 3) {
                Image(systemName: stats.charging ? "battery.100.bolt" : (b > 60 ? "battery.75" : b > 25 ? "battery.50" : "battery.25"))
                    .foregroundStyle(b <= 20 && !stats.charging ? .red : .white)
                Text("\(b)%").monospacedDigit()
            }
        } else {
            Image(systemName: "powerplug").opacity(0.5)
        }
    }

    private var cpu: some View {
        HStack(spacing: 4) {
            Sparkline(values: stats.cpuHistory, color: prefs.c.accent).frame(width: 24, height: 12)
            Text("\(Int(stats.cpu * 100))%").monospacedDigit()
        }
    }

    @ViewBuilder private var meeting: some View {
        if let m = calendar.next {
            HStack(spacing: 4) {
                Circle().fill(m.color).frame(width: 6, height: 6)
                Text(m.start > .now ? "in \(m.start.timeIntervalSinceNow.short)" : "now").monospacedDigit()
            }
        } else {
            Image(systemName: "calendar").opacity(0.4)
        }
    }
}

// MARK: - Little animated pieces

struct Equalizer: View {
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let v = 0.3 + 0.7 * abs(sin(t * (3.1 + Double(i) * 1.37) + Double(i)))
                    Capsule().fill(color).frame(width: 2.5).frame(height: nil).scaleEffect(y: v, anchor: .bottom)
                }
            }
        }
    }
}

struct ThinkingDots: View {
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(color)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 5 - Double(i) * 0.8)))
                }
            }
        }
    }
}

struct Ring: View {
    var progress: Double
    var color: Color
    var line: CGFloat = 4
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                let step = g.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: g.size.height * (1 - CGFloat(min(1, max(0, v)))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}
