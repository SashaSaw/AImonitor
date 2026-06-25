#!/usr/bin/env python3
"""AImonitor status emitter — the bridge between an agent and the overlay.

Wired to an agent's lifecycle hooks. On each event it writes/updates one JSON
file at ~/.aimonitor/sessions/<id>.json that the overlay reads.

Claude Code: passes the event JSON on STDIN.   Call: ... --agent claude --event <Name>
Codex CLI:   passes the event JSON as the final ARG, or via its own fields.
             Call (hooks.json): ... --agent codex --event <Name>
             Call (notify):     ... --agent codex          (event from payload "type")

Session key priority (so multiple terminals on one project stay distinct):
  1. $TMUX_PANE        — stable + doubles as the click/send target
  2. the agent's own session id (from payload or env)
  3. the controlling terminal's TTY  — unique per Terminal/iTerm tab
  4. parent pid         — last resort

Set AIMONITOR_DEBUG=1 to append a diagnostic line per call to
~/.aimonitor/debug.log (used to learn exactly what Codex sends).
"""
import sys, os, json, time, re, subprocess

BASE = os.path.expanduser("~/.aimonitor")

def arg(flag, default=""):
    a = sys.argv[1:]
    return a[a.index(flag) + 1] if flag in a and a.index(flag) + 1 < len(a) else default

def read_payload():
    raw = ""
    try:
        if not sys.stdin.isatty():
            raw = sys.stdin.read()
    except Exception:
        raw = ""
    if not raw.strip():  # Codex notify-style: JSON passed as a trailing argument
        for a in reversed(sys.argv[1:]):
            if a.strip().startswith("{"):
                raw = a
                break
    try:
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}

def get_tty():
    """Controlling terminal device of the process tree (e.g. 'ttys006').
    Stable + unique per terminal tab; used for keying and click-to-focus."""
    try:
        out = subprocess.check_output(["ps", "-o", "tty=", "-p", str(os.getppid())],
                                      stderr=subprocess.DEVNULL).decode().strip()
        if out and out not in ("??", "?", "-"):
            return out  # e.g. "ttys006"
    except Exception:
        pass
    return ""

STATE_MAP = {
    # Claude Code hook events
    "SessionStart": "idle", "UserPromptSubmit": "thinking",
    "PreToolUse": "working", "PostToolUse": "working",
    "Notification": "waiting",        # Claude: waiting for input/permission
    "PermissionRequest": "waiting",   # Codex: about to ask for approval
    "Stop": "done",
    "SubagentStart": "working", "SubagentStop": "working",
    "SessionEnd": "_remove",
    # Codex notify / hook event types
    "task-started": "thinking", "task_started": "thinking",
    "approval-requested": "waiting", "approval_requested": "waiting",
    "agent-turn-complete": "done", "agent_turn_complete": "done",
}

def debug(line):
    if os.environ.get("AIMONITOR_DEBUG") != "1":
        return
    try:
        p = os.path.join(BASE, "debug.log")
        if os.path.exists(p) and os.path.getsize(p) > 1_000_000:
            os.remove(p)
        with open(p, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def main():
    agent = arg("--agent", "claude")
    data = read_payload()
    event = arg("--event") or data.get("hook_event_name") or data.get("type") or ""
    state = STATE_MAP.get(event, "working")

    tmux = os.environ.get("TMUX_PANE", "")
    session_id = (data.get("session_id") or data.get("sessionId") or data.get("session-id")
                  or data.get("conversation_id") or data.get("conversationId")
                  or os.environ.get("CODEX_SESSION_ID") or os.environ.get("CLAUDE_SESSION_ID") or "")
    tty = get_tty()
    sid = tmux or session_id or (("tty-" + tty) if tty else "") or ("pid-%s" % os.getppid())

    cwd = data.get("cwd") or os.environ.get("PWD") or os.getcwd()
    base = os.path.basename(cwd.rstrip("/")) or cwd
    # short, unique-per-terminal tag so two rows on the same project differ
    tag = tmux or (("…" + session_id[-4:]) if session_id else "") or tty
    title = (base + " " + tag).strip() if tag else base

    debug("%s agent=%s event=%s state=%s sid=%s tmux=%s tty=%s keys=%s argv=%s" % (
        time.strftime("%H:%M:%S"), agent, event, state, sid, tmux, tty,
        list(data.keys()), sys.argv[1:]))

    sdir = os.path.join(BASE, "sessions")
    os.makedirs(sdir, exist_ok=True)
    path = os.path.join(sdir, re.sub(r"[^A-Za-z0-9_.-]", "_", sid) + ".json")

    if state == "_remove":
        try:
            os.remove(path)
        except OSError:
            pass
        return

    detail = data.get("tool_name", "") if "ToolUse" in event else data.get("message", "")
    rec = {
        "id": sid, "agent": agent, "title": title, "state": state,
        "detail": detail, "cwd": cwd, "tmux": tmux, "tty": tty,
        "updated_at": time.time(),
        "needs_attention": state in ("waiting", "done"),
    }
    tmp = "%s.tmp.%d" % (path, os.getpid())   # unique per process: no concurrent-hook race
    with open(tmp, "w") as f:
        json.dump(rec, f)
    os.replace(tmp, path)  # atomic

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # a status hook must never fail (or block) the agent
