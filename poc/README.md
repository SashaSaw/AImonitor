# AImonitor POC

A working prototype: a floating overlay that shows the status of your terminal
agents, stays on top across Spaces/full-screen, and lets you click a row to jump
to that agent.

---

## Part 1 — What is tmux, and how is it different from Terminal.app?

**Terminal.app (or iTerm2)** is a *window* program. Each tab is one shell. If you
close the window or the laptop sleeps weirdly, that shell and whatever was
running in it is gone. Nothing else can "see into" that tab.

**tmux** ("terminal multiplexer") is a program that runs *inside* a terminal and
manages many shells for you. Think of it as a layer between the terminal window
and your shells:

```
  Terminal.app window
   └── tmux  (one program, always running in the background)
        ├── window "work"
        │     ├── pane %1   ← claude running here
        │     └── pane %2   ← codex running here
        └── window "logs"
              └── pane %3   ← a dev server
```

Key differences that matter for this project:

| | Terminal.app alone | with tmux |
|---|---|---|
| Sessions survive closing the window | ✗ | ✓ (`tmux attach` reconnects) |
| Other programs can address a specific shell | ✗ (no stable handle) | ✓ every pane has an id like `%1` |
| Jump to a specific agent programmatically | hard (fragile AppleScript) | one command: `tmux select-pane -t %1` |
| Type a command into a specific agent | hard | one command: `tmux send-keys -t %1 "..." Enter` |
| Split-screen many agents at once | manual windows | built-in panes |

Those last three rows are *why* we chose tmux. The overlay identifies each agent
by its tmux pane id, so clicking a row can reliably bring that agent to the front
(and later, send it work). Without tmux there's no stable "handle" to an agent.

You still use Terminal.app — you just run `tmux` inside it.

### The 8 tmux commands you actually need

```bash
brew install tmux          # one-time install

tmux                       # start tmux (you're now "inside" it)
tmux new -s work           # start a named session "work"
tmux attach -t work        # re-enter a session later (survives closed windows)
tmux ls                    # list sessions

# Inside tmux, the "prefix" key is Ctrl-b. Press it, release, then the key:
#   Ctrl-b  c     -> new window
#   Ctrl-b  "     -> split current pane top/bottom
#   Ctrl-b  %     -> split current pane left/right
#   Ctrl-b  o     -> move to next pane
#   Ctrl-b  d     -> "detach" (leave tmux running in the background)
#   Ctrl-b  [     -> scroll mode (q to quit scrolling)
```

That's enough. Everything else is optional polish.

---

## Part 2 — Run the prototype

You need Xcode command-line tools once: `xcode-select --install`.

### Build the app

```bash
cd poc
./package.sh                 # builds AImonitor.app (double-clickable, no Dock icon)
open AImonitor.app           # or double-click it in Finder
mv AImonitor.app /Applications/   # optional: keep it handy
```

- It's an **accessory app**: no Dock icon, no Cmd-Tab entry — just the floating
  panel, top-right of your screen.
- **Quit** it with **right-click on the panel → Quit AImonitor**.
- (For quick iteration you can still `./build.sh && ./aimonitor-overlay &`.)

### See it immediately with fake agents

```bash
python3 demo.py              # fakes 4 agents cycling through states
```

Colored dots: **blue (pulsing)** = thinking, **green** = working, **orange** =
waiting on you, **green + red dot** = just finished. A soft sound plays whenever
an agent job finishes. Drag the panel anywhere; switch Spaces / full-screen an app
— it stays on top. `Ctrl-C` the demo to clean up.

### Use it: click + send

- **Click a row** → jumps to that agent's tmux pane *and* selects it as the send
  target (and clears its red badge).
- **Type in the box → Enter** → sends that text to the selected agent via
  `tmux send-keys` (works for any text; sent literally + Return).

---

## Part 3 — Wiring to your real agents (already done)

`wire_hooks.py` has been run, so your agents now report status. It:

- **Claude** (`~/.claude/settings.json`) — added our emitter to `SessionStart,
  UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop, SessionEnd`,
  *alongside* your existing remote-monitor hooks (untouched).
- **Codex** (`~/.codex/hooks.json`) — added it to `SessionStart, PostToolUse,
  SubagentStart, SubagentStop, Stop`. (Your `notify` is occupied by Computer-Use,
  and only one is allowed, so we use the non-conflicting hooks file instead.)

Backups: `~/.claude/settings.json.aimonitor-bak`, `~/.codex/hooks.json.aimonitor-bak`.

```bash
python3 wire_hooks.py            # re-apply / de-dupe (idempotent)
python3 wire_hooks.py --remove   # cleanly remove our hooks, keep everything else
```

### Two things to know

1. **Agents must run inside tmux** for status keying, click-to-focus, and send to
   work — each agent is identified by its `$TMUX_PANE`. Start one with
   `tmux new -s work`, then run `claude` / `codex` in panes (`Ctrl-b "` to split).
   Outside tmux they fall back to a pid key and lose click/send.
2. **Codex** may show a **one-time hook-trust prompt** on next launch (we changed
   `hooks.json`); approve it. Also, because `notify` is taken, Codex won't report
   the "waiting for approval" state — it shows idle / working / done. Claude
   reports the full lifecycle including `waiting`.

---

## What this POC does and doesn't do

**Does:** floating panel above all Spaces/full-screen, per-agent dots + states,
red attention badge + completion sound, drag to move, **click → focus pane**,
**type → send to agent**, atomic status files from real Claude + Codex hooks,
packaged `.app`.

**Doesn't yet (next steps):** native notification banners, FSEvents push (polls
every 0.25s), collapsed/expanded modes, process-scan fallback for non-tmux
sessions, launch-at-login, app icon. See `../docs/02-architecture.md`.

## Files

- `overlay.swift` — the floating panel app (single file, no Xcode project)
- `agent_status.py` — hook script: agent event → status file
- `wire_hooks.py` — idempotently add/remove our hooks in Claude + Codex configs
- `demo.py` — fake agents for instant visual testing
- `Info.plist` / `package.sh` — build `AImonitor.app`
- `build.sh` — bare `swiftc` compile (for quick iteration)
