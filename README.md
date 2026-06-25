# AImonitor

A tiny, always-on-top macOS overlay that shows the live status of the terminal
coding agents (Claude Code, Codex) you have running — thinking, working, waiting
for input, or done — and nudges you with sound + a glow when one needs you.

It floats above every Space and full-screen window, stays out of the way, and
lets you double-click an agent to jump straight to its terminal.

## How it works

```
 agents (claude / codex)        a tiny hook script           the overlay
 emit lifecycle events  ──▶  writes one JSON file per   ──▶  reads the folder,
 via their hook systems       session in ~/.aimonitor/        draws a row per agent
                              sessions/<id>.json
```

- **Status source** — each agent's hooks call `poc/agent_status.py`, which writes
  a per-session status file. Claude and Codex both report the full lifecycle
  (Codex's `PermissionRequest` maps to the "waiting" state).
- **Overlay** — `poc/overlay.swift` is a single-file native SwiftUI/AppKit app: a
  non-activating floating `NSPanel` with `canJoinAllSpaces` + `fullScreenAuxiliary`
  so it sits above everything without stealing focus.

## Features

- Per-agent row with a brand icon (custom logos via `~/.aimonitor/icons/<agent>.png`)
- State highlights: **thinking** = blue glow, **working** = orange glow,
  **waiting** = red, **done** = green
- Sound on stop only (Ping = needs you, Glass = done), with a Volume menu
- **Double-click a row → jump to that agent's terminal** (tmux pane or tty)
- Drag a row to reorder; drag the header to move the panel (order persists)
- Right-click a row → Jump / Remove from list / Volume / Quit
- Auto-removes sessions when the agent ends (Claude `SessionEnd`; liveness sweep
  for Codex and crashes)

## Quick start

```bash
cd poc
./package.sh            # builds AImonitor.app (double-clickable, no Dock icon)
open AImonitor.app
python3 demo.py         # optional: fake agents to preview the UI
```

Wire it to your real agents (adds hooks alongside any you already have; backs up
your configs first):

```bash
python3 poc/wire_hooks.py          # apply
python3 poc/wire_hooks.py --remove # undo
```

Run your agents inside **tmux** for the most reliable click-to-focus and per-pane
status. See [`poc/README.md`](poc/README.md) for the full guide (including a tmux
primer) and [`docs/`](docs/) for the concept and architecture write-ups.

## Layout

- `poc/` — the working prototype (overlay app, hook script, wiring, demo)
- `docs/` — concept, architecture, and prior-art notes

## Status

Working prototype. macOS 13+ (built/tested on macOS 26). Not yet packaged for
distribution or signed for other machines.
