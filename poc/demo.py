#!/usr/bin/env python3
"""Fake some agents so you can SEE the overlay without wiring real hooks yet.
Writes 4 sessions that cycle through states. Ctrl-C cleans them up."""
import os, json, time, random

d = os.path.expanduser("~/.aimonitor/sessions")
os.makedirs(d, exist_ok=True)

AGENTS = [
    {"id": "demo-1", "agent": "claude", "title": "api-refactor", "tmux": "%1"},
    {"id": "demo-2", "agent": "claude", "title": "web-ui",       "tmux": "%2"},
    {"id": "demo-3", "agent": "codex",  "title": "flaky-tests",  "tmux": "%3"},
    {"id": "demo-4", "agent": "codex",  "title": "migrate-db",   "tmux": "%4"},
]
CYCLE = ["thinking", "working", "working", "waiting", "working", "done", "idle"]
pos = {a["id"]: random.randint(0, len(CYCLE) - 1) for a in AGENTS}

def write(a, state):
    rec = {"id": a["id"], "agent": a["agent"], "title": a["title"], "state": state,
           "detail": "", "cwd": "/Users/demo/" + a["title"], "tmux": a["tmux"],
           "updated_at": time.time(), "needs_attention": state in ("waiting", "done")}
    p = os.path.join(d, a["id"] + ".json")
    open(p + ".tmp", "w").write(json.dumps(rec))
    os.replace(p + ".tmp", p)

print("Writing demo sessions to", d, "— Ctrl-C to stop")
try:
    while True:
        for a in AGENTS:
            write(a, CYCLE[pos[a["id"]] % len(CYCLE)])
            if random.random() < 0.5:
                pos[a["id"]] += 1
        time.sleep(1.5)
except KeyboardInterrupt:
    for a in AGENTS:
        try:
            os.remove(os.path.join(d, a["id"] + ".json"))
        except OSError:
            pass
    print("\ncleaned up demo sessions")
