#!/usr/bin/env python3
"""Wisp hook for Claude Code (and Codex).

Claude Code runs this script on every hook event and pipes the event JSON to stdin.
The script forwards it to Wisp over a Unix socket in Wisp's data folder.

- Most events are fire-and-forget: send, close, exit 0.
- PermissionRequest waits for your answer in the notch and prints Claude Code's
  decision JSON. If Wisp says "ask" (it timed out, or you picked "Answer in the
  terminal"), the script prints nothing and Claude Code asks in the terminal as usual.
- With --ask (registered for the AskUserQuestion tool), the script waits for your
  picks in the notch and hands them to Claude Code as the tool's answers.
- With --agent NAME, sessions are labeled NAME instead of Claude (Wisp passes
  --agent Codex for Codex, which uses the same hook format).
- With --statusline, the script is Claude Code's status line: it tells Wisp the
  model, context, cost and plan limits, then prints a short line. --wrap-b64 keeps
  a status line you already had: Wisp runs it and prints its output instead.
- If Wisp isn't running, the connect fails in a few milliseconds and the script exits
  quietly, so Claude Code always keeps working without it.

Standard library only, compatible with the /usr/bin/python3 that ships with macOS.
"""
import base64
import json
import os
import socket
import subprocess
import sys

SOCKET_PATH = os.path.expanduser("~/Library/Application Support/Wisp/wisp.sock")
WAIT_SECONDS = 900  # Wisp enforces its own, shorter timeout and answers "ask".
# Events where it's worth finding the terminal tab the session runs in.
FIND_TTY = {"SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "Notification"}


def talk(payload, wait):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.4)
    s.connect(SOCKET_PATH)
    s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    if not wait:
        s.close()
        return None
    s.settimeout(WAIT_SECONDS)
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.decode("utf-8") or "{}")


def find_tty():
    """Walks up from this script to the first ancestor with a terminal, e.g. /dev/ttys004."""
    pid = os.getppid()
    for _ in range(6):
        try:
            out = subprocess.run(["ps", "-o", "tty=,ppid=", "-p", str(pid)],
                                 capture_output=True, text=True, timeout=1).stdout.split()
        except Exception:
            return ""
        if len(out) < 2:
            return ""
        tty, parent = out[0], out[1]
        if tty not in ("??", "-", ""):
            return "/dev/" + tty
        pid = int(parent)
        if pid <= 1:
            return ""
    return ""


def statusline(args, raw):
    try:
        data = json.loads(raw or "{}")
    except Exception:
        data = {}
    payload = dict(data)
    payload["hook_event_name"] = "StatusLine"
    try:
        talk(payload, False)
    except Exception:
        pass

    if "--wrap-b64" in args[:-1]:
        try:
            original = json.loads(base64.b64decode(args[args.index("--wrap-b64") + 1]).decode("utf-8"))
            out = subprocess.run(original.get("command", ""), shell=True, input=raw,
                                 capture_output=True, text=True, timeout=10).stdout
            sys.stdout.write(out)
            return 0
        except Exception:
            pass

    parts = []
    model = (data.get("model") or {}).get("display_name")
    if model:
        parts.append(model)
    ctx = (data.get("context_window") or {}).get("used_percentage")
    if isinstance(ctx, (int, float)):
        parts.append("ctx %d%%" % ctx)
    limits = data.get("rate_limits") or {}
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        pct = (limits.get(key) or {}).get("used_percentage")
        if isinstance(pct, (int, float)):
            parts.append("%s %d%%" % (label, pct))
    cost = (data.get("cost") or {}).get("total_cost_usd")
    if isinstance(cost, (int, float)) and cost > 0:
        parts.append("$%.2f" % cost)
    print("🔥 " + " · ".join(parts) if parts else "🔥 Wisp")
    return 0


def main():
    args = sys.argv[1:]
    if "--statusline" in args:
        return statusline(args, sys.stdin.read())
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0
    ask = "--ask" in args
    agent = args[args.index("--agent") + 1] if "--agent" in args[:-1] else ""
    name = event.get("hook_event_name", "")
    event["_wisp"] = {
        "bundle": os.environ.get("__CFBundleIdentifier", ""),
        "term": os.environ.get("TERM_PROGRAM", ""),
        "tmux": os.environ.get("TMUX_PANE", ""),
        "tty": find_tty() if name in FIND_TTY else "",
        "ask": ask,
        "agent": agent,
    }
    waits = name == "PermissionRequest" or ask
    try:
        reply = talk(event, waits)
    except Exception:
        return 0
    if not waits or not isinstance(reply, dict):
        return 0

    if ask:
        answers = reply.get("answers")
        if not isinstance(answers, dict):
            return 0
        questions = event.get("tool_input", {}).get("questions", [])
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {"questions": questions, "answers": answers},
        }}))
        return 0

    behavior = reply.get("behavior")
    if behavior not in ("allow", "deny"):
        return 0
    decision = {"behavior": behavior}
    if behavior == "allow" and event.get("tool_name") == "ExitPlanMode":
        # Claude Code ignores an allow for ExitPlanMode unless the plan comes back with it.
        decision["updatedInput"] = event.get("tool_input", {})
    if behavior == "allow" and reply.get("always") and event.get("permission_suggestions"):
        # Same as choosing "Yes, and don't ask again" in the terminal.
        decision["updatedPermissions"] = event["permission_suggestions"]
    if behavior == "deny":
        decision["message"] = reply.get("message") or "The user denied this from Wisp."
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
