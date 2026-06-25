#!/usr/bin/env python3
"""Idempotently add AImonitor's status emitter to Claude + Codex hook configs,
without touching existing hooks. Safe to re-run. Re-run with `--remove` to undo."""
import json, os, sys

HOME = os.path.expanduser("~")
PY = "/opt/miniconda3/bin/python3"
SCRIPT = "/Users/alexandersaw/Projects/AImonitor/poc/agent_status.py"

CLAUDE = os.path.join(HOME, ".claude/settings.json")
CODEX = os.path.join(HOME, ".codex/hooks.json")

# (agent, [events]) per config
CLAUDE_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse",
                 "PostToolUse", "Notification", "Stop", "SessionEnd"]
CODEX_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                "PermissionRequest", "SubagentStart", "SubagentStop", "Stop"]

MARK = "agent_status.py"
REMOVE = "--remove" in sys.argv

def cmd(agent, event):
    # Debug-log Codex calls while we learn its exact payload (harmless; remove later).
    dbg = "AIMONITOR_DEBUG=1 " if agent == "codex" else ""
    return "%s%s %s --agent %s --event %s" % (dbg, PY, SCRIPT, agent, event)

def has_mark(entry):
    for h in entry.get("hooks", []):
        if MARK in h.get("command", ""):
            return True
    return False

def wire(path, agent, events):
    if not os.path.exists(path):
        print("  skip (not found):", path); return
    with open(path) as f:
        cfg = json.load(f)
    hooks = cfg.setdefault("hooks", {})
    changed = 0
    for ev in events:
        lst = hooks.setdefault(ev, [])
        # drop any of ours first (handles remove + de-dupe)
        before = len(lst)
        lst[:] = [e for e in lst if not has_mark(e)]
        changed += before - len(lst)
        if not REMOVE:
            lst.append({"matcher": "", "hooks": [{"type": "command", "command": cmd(agent, ev)}]})
            changed += 1
        if not lst:
            del hooks[ev]
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("  %s: %s (%d edits) -> %s" % (agent, "removed" if REMOVE else "wired", changed, path))

print("AImonitor hook wiring", "(REMOVE)" if REMOVE else "")
os.makedirs(os.path.join(HOME, ".aimonitor/sessions"), exist_ok=True)
wire(CLAUDE, "claude", CLAUDE_EVENTS)
wire(CODEX, "codex", CODEX_EVENTS)
print("done.")
