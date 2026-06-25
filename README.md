# AImonitor

A tiny, always-on-top macOS overlay that shows the live status of the terminal
coding agents (**Claude Code**, **Codex**) you have running — thinking, working,
waiting for input, or done — and nudges you with sound + a glow when one needs
you. It floats above every Space and full-screen window, stays out of the way,
and lets you **double-click an agent to jump straight to its terminal**.

```
 ┌───────────────────────────────┐
 │ AImonitor · 4 agents          │
 │ ✦ api-refactor      thinking  │  ← blue glow  (claude)
 │ </> flaky-tests     working   │  ← orange glow (codex)
 │ ✦ web-ui            waiting   │  ← solid red
 │ </> migrate-db      done      │  ← solid green
 └───────────────────────────────┘
```

---

## How it works

```
 agents (claude / codex)        a tiny hook script            the overlay
 emit lifecycle events  ──▶  writes one JSON file per   ──▶  reads the folder and
 via their hook systems       session in ~/.aimonitor/        draws a row per agent
                              sessions/<id>.json
```

- Each agent's hooks call **`poc/agent_status.py`**, which writes a per-session
  status file.
- **`poc/overlay.swift`** is a single-file native AppKit app: a non-activating
  floating `NSPanel` (`canJoinAllSpaces` + `fullScreenAuxiliary`) that reads
  those files and renders a compact row per agent, above everything, without
  stealing focus.

---

## Requirements

- macOS 13+ (built and tested on macOS 26)
- **Xcode command-line tools** — `xcode-select --install`
- **python3** (used by the hook script)
- **tmux** *(recommended)* — `brew install tmux`. Agents run inside tmux get the
  most precise click-to-focus and per-pane status. Non-tmux agents still work
  (keyed by their terminal tty). New to tmux? See [`poc/README.md`](poc/README.md)
  for a short primer.

---

## Getting started

### 1. Build the app

```bash
git clone https://github.com/SashaSaw/AImonitor.git
cd AImonitor/poc
./package.sh                 # builds AImonitor.app (double-clickable, no Dock icon)
open AImonitor.app           # the overlay appears top-right
# optional: keep it handy
mv AImonitor.app /Applications/
```

It runs as an **accessory app** — no Dock icon, no Cmd-Tab entry. **Quit** it via
right-click → Quit.

Want to see the UI immediately without wiring anything?

```bash
python3 demo.py              # fakes a few agents cycling through states
```

### 2. Wire it to your agents

This adds AImonitor's status hook **alongside** any hooks you already have (it
backs up your config files first):

```bash
python3 poc/wire_hooks.py            # apply
python3 poc/wire_hooks.py --remove   # cleanly undo
```

- **Claude Code** — works immediately on your next turn.
- **Codex** — restart Codex once and **approve its hook-trust prompt** (Codex
  only runs hooks it has trusted). After that it reports the full lifecycle.

Run your agents **inside tmux** (`tmux new -s work`, then `claude` / `codex`) for
the best experience.

### 3. Allow "jump to terminal" (one-time)

The first time you double-click a row, macOS will ask *"AImonitor wants to
control Terminal.app."* — click **Allow**. This lets it raise the exact terminal
tab. If you miss it, enable it later at **System Settings → Privacy & Security →
Automation → AImonitor → Terminal** (or iTerm).

---

## Using the app

### Reading the states

| State | Look | Meaning |
|-------|------|---------|
| **thinking** | blue glow (slow pulse) | model is generating a response |
| **working** | orange glow (slow pulse) | running a tool (edit, bash, …) |
| **waiting** | solid **red** | blocked on *you* — a question or permission |
| **done** | solid **green** | turn finished |
| **idle** | faint grey | session alive, between turns |

**Sounds (on stop only):** a *Ping* when an agent enters **waiting** (needs you)
and a *Glass* when it's **done**. Active states make no sound.

### Interactions

- **Double-click a row** → jump to that agent's terminal (the exact window/tab,
  and the right pane for tmux).
- **Drag a row** → reorder it. **Drag the header** → move the whole panel. Your
  order and position persist across restarts.
- **Right-click a row** → *Jump to…*, *Remove from list*, *Volume*, *Quit*.
  - **Volume**: Mute / 25 / 50 / 75 / 100% — plays a preview, persists.
  - **Remove from list**: dismiss a row you're done with (reappears only if that
    agent does something again).

### Custom agent icons

Drop a square PNG into `~/.aimonitor/icons/` named after the agent — it appears
within ~1 second, no rebuild:

```
~/.aimonitor/icons/claude.png
~/.aimonitor/icons/codex.png
```

Supports png/jpg/pdf/tiff. Without a file, a built-in tinted glyph is used
(coral ✦ for Claude, teal `</>` for Codex).

### Sessions clean themselves up

- **Claude** removes its row when you exit (via its `SessionEnd` hook).
- **Codex / crashes** — the overlay sweeps every ~2s and removes a session once
  its agent process is gone (tmux pane closed or reverted to a shell; no agent
  process left on its tty). Self-healing: if it ever guesses wrong, the next
  event re-creates the row.

---

## Troubleshooting

- **No rows appear** — confirm hooks are wired (`python3 poc/wire_hooks.py`) and,
  for Codex, that you restarted it and approved the trust prompt. Status files
  live in `~/.aimonitor/sessions/`.
- **Double-click goes to the wrong window** — grant the Automation permission
  (see step 3). Check `~/.aimonitor/focus.log`; lines should read
  `method=applescript:Terminal` (not `open`).
- **No sound** — check right-click → Volume isn't on Mute, and your system volume.
- **Two rows for the same project** — expected: each terminal/tmux session is
  distinct and tagged (e.g. `chivo-platform %1`).

---

## Uninstall

```bash
python3 poc/wire_hooks.py --remove     # remove our hooks (restores your configs)
rm -rf ~/.aimonitor                     # status files, icons, logs
# then delete AImonitor.app
```

---

## Project layout

- `poc/` — the working prototype (overlay app, hook script, wiring, demo)
- `docs/` — concept, architecture, and prior-art notes

## Status

Working prototype. macOS 13+. Not yet signed for distribution to other machines
(build it locally with `package.sh`).
