#!/usr/bin/env python3
"""Wisp hook for Claude Code.

Claude Code runs this script on every hook event and pipes the event JSON to stdin.
The script forwards it to Wisp over a Unix socket in Wisp's data folder.

- Most events are fire-and-forget: send, close, exit 0.
- PermissionRequest waits for your answer in the notch and prints Claude Code's
  decision JSON. If Wisp says "ask" (it timed out, or you picked "Answer in the
  terminal"), the script prints nothing and Claude Code asks in the terminal as usual.
- With --ask (registered for the AskUserQuestion tool), the script waits for your
  picks in the notch and hands them to Claude Code as the tool's answers.
- With --agent NAME, sessions are labeled NAME instead of Claude, so other agents
  that speak the same hook format get their own label.
- If Wisp isn't running, the connect fails in a few milliseconds and the script exits
  quietly, so Claude Code always keeps working without it.

Standard library only, compatible with the /usr/bin/python3 that ships with macOS.
"""
import json
import os
import socket
import sys

SOCKET_PATH = os.path.expanduser("~/Library/Application Support/Wisp/wisp.sock")
WAIT_SECONDS = 900  # Wisp enforces its own, shorter timeout and answers "ask".


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


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0
    args = sys.argv[1:]
    ask = "--ask" in args
    agent = args[args.index("--agent") + 1] if "--agent" in args[:-1] else ""
    name = event.get("hook_event_name", "")
    event["_wisp"] = {
        "bundle": os.environ.get("__CFBundleIdentifier", ""),
        "term": os.environ.get("TERM_PROGRAM", ""),
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
