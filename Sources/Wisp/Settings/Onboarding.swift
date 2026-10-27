import SwiftUI

/// First launch: meet your wisp, name it, dress it, pick a look, connect Claude Code.
struct OnboardingView: View {
    let done: () -> Void
    @EnvironmentObject private var prefs: Prefs
    @State private var step = 0

    var body: some View {
        let c = prefs.c
        VStack(spacing: 18) {
            MascotView(size: 130, mood: step == 0 ? .happy : nil, showCaption: step > 0)
                .frame(height: 160)
            switch step {
            case 0:
                Text("Hi! I'm a wisp.").font(.system(size: 30, weight: .semibold, design: c.font))
                Text("I live in your notch, keep an eye on Claude Code, and wave when it needs you.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextField("Give me a name", text: $prefs.c.mascotName)
                    .textFieldStyle(.roundedBorder).frame(width: 220).multilineTextAlignment(.center)
            case 1:
                Text("What do I look like?").font(.system(size: 24, weight: .semibold, design: c.font))
                Picker("Shape", selection: $prefs.c.mascotStyle) {
                    ForEach(MascotStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 420)
                Picker("Outfit", selection: $prefs.c.outfit) {
                    ForEach(Outfit.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 260)
                Picker("Personality", selection: $prefs.c.personality) {
                    ForEach(Personality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 300)
            case 2:
                Text("Pick a look").font(.system(size: 24, weight: .semibold, design: c.font))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(Theme.all) { t in ThemeSwatch(theme: t, selected: c.themeID == t.id) { prefs.c.themeID = t.id } }
                }
                .frame(width: 460)
                Picker("", selection: $prefs.c.style) {
                    ForEach(IslandStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            default:
                Text("Connect Claude Code").font(.system(size: 24, weight: .semibold, design: c.font))
                Text("Wisp adds a hook to ~/.claude/settings.json so it can see sessions and answer permissions. You'll see the exact change first, and a backup is kept.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(width: 440)
                Button("Open Claude Code settings") {
                    done()
                    AppDelegate.shared?.openSettings(page: .claude)
                }
                Text("Tip: hover the notch any time. Poke me if you're bored.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Back") { withAnimation { step -= 1 } } }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<4) { i in Circle().fill(i == step ? c.accent : .gray.opacity(0.3)).frame(width: 7, height: 7) }
                }
                Spacer()
                Button(step == 3 ? "Done" : "Next") { step == 3 ? done() : withAnimation { step += 1 } }
                    .buttonStyle(.borderedProminent).tint(c.accent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 520)
        .environment(\.look, c.look)
    }
}
