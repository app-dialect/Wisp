import AppKit

let args = CommandLine.arguments
if args.count > 2, args[1] == "--render-icon" {
    MainActor.assumeIsolated { IconRenderer.render(to: args[2]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
