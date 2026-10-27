import AppKit

/// Finds the exact terminal tab a session runs in, and can type into it.
/// Terminal and iTerm2 are matched by tty through AppleScript; other apps are brought to the front.
enum TerminalBridge {
    static func focus(_ s: Session) {
        let bundle = s.appBundle.isEmpty ? "com.apple.Terminal" : s.appBundle
        if !s.tty.isEmpty {
            switch bundle {
            case "com.apple.Terminal":
                if run(terminalSelect(s.tty)) { return }
            case "com.googlecode.iterm2":
                if run(itermSelect(s.tty)) { return }
            default:
                break
            }
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.activate()
    }

    /// Only Terminal and iTerm2 can be typed into reliably.
    static func canSend(_ s: Session) -> Bool {
        !s.tty.isEmpty && ["com.apple.Terminal", "com.googlecode.iterm2"].contains(s.appBundle.isEmpty ? "com.apple.Terminal" : s.appBundle)
    }

    /// Types a message into the session's tab and presses Return.
    @discardableResult
    static func send(_ text: String, to s: Session) -> Bool {
        guard canSend(s) else { return false }
        let t = escape(text)
        if s.appBundle == "com.googlecode.iterm2" {
            return run("""
            tell application "iTerm2"
                repeat with w in windows
                    repeat with tb in tabs of w
                        repeat with ss in sessions of tb
                            if tty of ss is "\(s.tty)" then
                                tell ss to write text "\(t)"
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """)
        }
        // Terminal.app has no "write text": select the tab, then paste and press Return through System Events.
        guard run(terminalSelect(s.tty)) else { return false }
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ok = run("""
        delay 0.2
        tell application "System Events"
            keystroke "v" using command down
            delay 0.1
            key code 36
        end tell
        return true
        """)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
        return ok
    }

    private static func terminalSelect(_ tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func itermSelect(_ tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with tb in tabs of w
                    repeat with ss in sessions of tb
                        if tty of ss is "\(tty)" then
                            select w
                            tell tb to select
                            tell ss to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    private static func run(_ source: String) -> Bool {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil && (result?.booleanValue ?? false)
    }
}
