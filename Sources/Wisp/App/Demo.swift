import AppKit

/// `Wisp --demo <scene>` fills the island with made-up sessions for screenshots.
/// It uses its own data folder and never saves settings, so a real Wisp setup is untouched.
enum Demo {
    static let scene: String? = {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--demo") else { return nil }
        return i + 1 < a.count ? a[i + 1] : "claude"
    }()
    static var isOn: Bool { scene != nil }

    static var config: Config {
        var c = Config()
        c.onboarded = true
        c.greetOnLaunch = false
        c.soundPack = .off
        c.outfit = .none
        c.eyesFollowCursor = false
        c.trigger = .click
        c.islandWidth = 700
        c.tiles = [
            TileConfig(kind: .claude, span: 2),
            TileConfig(kind: .usage, span: 2),
            TileConfig(kind: .timer, span: 1),
            TileConfig(kind: .todo, span: 1),
        ]
        c.todos = [
            TodoItem(text: "Ship the onboarding flow", done: true),
            TodoItem(text: "Review the API PR"),
            TodoItem(text: "Water the plants"),
        ]
        return c
    }

    static func run(_ island: IslandController) {
        guard let scene else { return }
        let hub = ClaudeHub.shared
        seed(hub)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            switch scene {
            case "home":
                island.expand(tab: .home, sticky: true)
            case "sessions":
                island.expand(tab: .claude, sticky: true)
            case "risk":
                permission(hub, "Bash", ["command": "git push --force origin main", "description": "Force-push the rebased branch"])
            case "plan":
                permission(hub, "ExitPlanMode", ["plan": plan])
            case "question":
                hub.handle(event("UserPromptSubmit", "s-rocket"), reply: nil)
                var e = event("PreToolUse", "s-rocket", tool: "AskUserQuestion", input: ["questions": [[
                    "question": "Which database should the new service use?",
                    "header": "Database",
                    "multiSelect": false,
                    "options": [
                        ["label": "Postgres", "description": "Matches the other services"],
                        ["label": "SQLite", "description": "Simplest to run locally"],
                        ["label": "DynamoDB", "description": "Serverless, pay per request"],
                    ],
                ]]])
                e["_wisp"] = ["ask": true]
                hub.handle(e, reply: { _ in })
                island.attention()
            case "peek":
                island.model.show(peek: .init(text: "rocket-app is done", symbol: "checkmark.circle.fill", color: Mood.happy.color), for: 600)
            default:
                permission(hub, "Bash", ["command": "npm run test -- --coverage", "description": "Run the test suite with coverage"])
            }
        }
    }

    private static func permission(_ hub: ClaudeHub, _ tool: String, _ input: [String: Any]) {
        var e = event("PermissionRequest", "s-rocket", tool: tool, input: input)
        e["permission_suggestions"] = [["type": "addRules"]]
        hub.handle(e, reply: { _ in })
    }

    private static func event(_ name: String, _ id: String, tool: String = "", input: [String: Any] = [:], extra: [String: Any] = [:]) -> [String: Any] {
        let cwd = ["s-rocket": "/Users/demo/rocket-app", "s-docs": "/Users/demo/docs-site", "s-api": "/Users/demo/billing-api"][id] ?? "/Users/demo/app"
        var e: [String: Any] = ["hook_event_name": name, "session_id": id, "cwd": cwd, "_wisp": ["bundle": "com.apple.Terminal"]]
        if !tool.isEmpty { e["tool_name"] = tool; e["tool_input"] = input; e["tool_use_id"] = UUID().uuidString }
        return e.merging(extra) { _, new in new }
    }

    private static func seed(_ hub: ClaudeHub) {
        let feed: [[String: Any]] = [
            event("SessionStart", "s-docs"),
            event("UserPromptSubmit", "s-docs", extra: ["prompt": "Fix the broken links on the pricing page"]),
            event("Stop", "s-docs", extra: ["last_assistant_message": "Fixed **3 broken links** on the pricing page and added a link check to CI."]),
            event("SessionStart", "s-api"),
            event("UserPromptSubmit", "s-api", extra: ["prompt": "Why are webhook retries doubling?"]),
            event("PreToolUse", "s-api", tool: "Grep", input: ["pattern": "retryWebhook"]),
            event("SessionStart", "s-rocket"),
            event("UserPromptSubmit", "s-rocket", extra: ["prompt": "Add dark mode to the settings screen"]),
            event("PreToolUse", "s-rocket", tool: "Read", input: ["file_path": "/Users/demo/rocket-app/src/Settings.tsx"]),
            event("PostToolUse", "s-rocket", tool: "Read", input: ["file_path": "/Users/demo/rocket-app/src/Settings.tsx"]),
            event("PreToolUse", "s-rocket", tool: "Edit", input: edit),
            event("PostToolUse", "s-rocket", tool: "Edit", input: edit),
            event("PreToolUse", "s-rocket", tool: "Write", input: ["file_path": "/Users/demo/rocket-app/src/theme.ts", "content": "export const dark = {\n  bg: '#0B0B10',\n  text: '#F4F4F8',\n}\n"]),
            event("PostToolUse", "s-rocket", tool: "Write", input: ["file_path": "/Users/demo/rocket-app/src/theme.ts", "content": "export const dark = {\n  bg: '#0B0B10',\n  text: '#F4F4F8',\n}\n"]),
            event("StatusLine", "s-rocket", extra: [
                "model": ["display_name": "Opus 5.5"],
                "context_window": ["used_percentage": 46],
                "cost": ["total_cost_usd": 0.84],
                "rate_limits": [
                    "five_hour": ["used_percentage": 62, "resets_at": Date().addingTimeInterval(2 * 3600 + 14 * 60).timeIntervalSince1970],
                    "seven_day": ["used_percentage": 38, "resets_at": Date().addingTimeInterval(3 * 86400).timeIntervalSince1970],
                ],
            ]),
        ]
        for e in feed { hub.handle(e, reply: nil) }
        hub.selectedID = "s-rocket"
    }

    private static let edit: [String: Any] = [
        "file_path": "/Users/demo/rocket-app/src/Settings.tsx",
        "old_string": "<Toggle label=\"Notifications\" />",
        "new_string": "<Toggle label=\"Notifications\" />\n<Toggle label=\"Dark mode\" value={dark} onChange={setDark} />",
    ]

    private static let plan = """
    ## Add dark mode

    1. Add a `dark` palette next to the light one in `theme.ts`
    2. Store the choice in `useSettings`, defaulting to the system setting
    3. Add a **Dark mode** toggle to the settings screen
    4. Update the snapshot tests

    Touches 4 files. No new dependencies.
    """
}
