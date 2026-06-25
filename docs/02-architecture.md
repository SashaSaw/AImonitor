# 02 — Architecture

Three layers:

```
 ┌─────────────────────────────────────────────────────────────┐
 │  AGENTS              claude code (×N)        codex (×N)       │
 │  emit lifecycle      via hooks               via notify/hooks │
 └───────────┬───────────────────────────────────┬─────────────┘
             │ tiny hook script writes an event    │
             ▼                                     ▼
 ┌─────────────────────────────────────────────────────────────┐
 │  CHANNEL   per-session status  (files  or  localhost socket)  │
 │            ~/.aimonitor/sessions/<id>.json   |  POST :PORT    │
 └───────────────────────────────┬─────────────────────────────┘
                                  │ watch (FSEvents) / receive (push)
                                  ▼
 ┌─────────────────────────────────────────────────────────────┐
 │  OVERLAY   SwiftUI floating panel  •  dots + labels  •  badge │
 │            click → focus terminal   •   (v2) send work        │
 └─────────────────────────────────────────────────────────────┘
```

---

## Layer 1 — Emitting status from each agent

Each agent already has a hook system. We register one small script per relevant
event; the script's only job is to record a status update (see Layer 2 format).

### Claude Code hooks → state  <a id="statusmapping"></a>

Claude Code exposes lifecycle hooks; each receives a JSON payload on **stdin**
(includes `session_id`, `cwd`, `hook_event_name`, transcript info). Mapping:

| Hook event        | Sets state | Notes |
|-------------------|-----------|-------|
| `SessionStart`    | `idle`    | register session: id, cwd, agent="claude", title from cwd |
| `UserPromptSubmit`| `thinking`| a turn began |
| `PreToolUse`      | `working` | about to run a tool; can carry tool name as detail |
| `PostToolUse`     | `working` | still in turn (heartbeat) |
| `Notification`    | `waiting` | **fires when Claude needs permission / is idle waiting for input → the attention state** |
| `Stop`            | `done`    | turn finished naturally |
| `SubagentStop`    | (detail)  | optional: show subagent activity |
| `SessionEnd`      | remove    | drop the row |

Configured in `~/.claude/settings.json` under `hooks`. Each entry runs our
script; the script reads stdin JSON and emits the update. Hooks must be fast and
must exit 0 (so they never block the agent) — do the write, exit.

> Note: Claude Code now ships **Agent View** (press `\` inside a session) which
> lists active sessions and their status in-terminal. AImonitor's value-add is
> being a *global, always-on-top, cross-tool* overlay (Claude **and** Codex)
> that survives full-screen Spaces — not living inside one terminal.

### Codex CLI → state

Codex supports a `notify` program plus a newer **hooks** system. The `notify`
hook fires on:

| Codex event           | Sets state | Notes |
|-----------------------|-----------|-------|
| `approval-requested`  | `waiting` | blocked on you to approve a command — attention state |
| `agent-turn-complete` | `done`    | turn finished |

Configured in **user-level** `~/.codex/config.toml` (project configs can't
override `notify`, by design). The notify program receives the event as an
argument/JSON; our script maps it and emits an update. Codex gives us fewer
intermediate signals than Claude (no per-tool event via `notify`), so for Codex
`thinking`/`working` may be approximated (e.g. "active since last event") unless
the richer hooks system exposes more — to confirm against current docs at
implementation time.

### Coverage gaps

`notify`/hooks give us **edges** (turn start/end, approval). For a live
"thinking vs working" distinction and crash detection we add:

- a **heartbeat**: long-running tools refresh `last_update`; the overlay marks a
  session `stale` if it claims `working` but hasn't updated in N seconds.
- optional **process scan** (like c9watch) to discover sessions that have no
  hooks installed, shown as a coarse "running" state.

---

## Layer 2 — The shared channel

Two viable designs; start simple, upgrade if needed.

### Option A — Status files (recommended for v1)

Each session = one JSON file: `~/.aimonitor/sessions/<session_id>.json`

```json
{
  "id": "a1b2c3",
  "agent": "claude",
  "title": "api-refactor",
  "cwd": "/Users/you/Projects/api",
  "state": "waiting",
  "detail": "permission: Bash(git push)",
  "tmux": "main:3.1",
  "term": {"app": "iTerm2", "tty": "/dev/ttys004"},
  "updated_at": 1718900000.123,
  "needs_attention": true
}
```

- Hooks write/replace the file atomically (write temp + rename).
- Overlay watches the directory with **FSEvents** / `DispatchSource` and
  re-renders on change.
- Pros: no daemon, trivial, survives overlay restarts, easy to debug (`cat`).
- Cons: no true push for sub-second "thinking" animation (fine — we animate
  locally), and `done` files must be cleaned up (TTL / on SessionEnd).

This is exactly the pattern the **gmr/claude-status** app uses (watches Claude's
session files) — proven approach. See prior art.

### Option B — localhost endpoint (v2 upgrade)

Overlay runs a tiny local server (Unix domain socket or `http://127.0.0.1:PORT`);
hooks `POST` events. Gives instant push, lets the overlay reply (e.g. ack), and
is the natural place to host the **send-to-agent** API. Costs a long-running
listener inside the app. Recommendation: design the file schema first, add the
socket later without changing the schema.

---

## Layer 3 — The overlay window

Native macOS, SwiftUI. The defining trick is making one small window sit above
**every** Space and full-screen app without stealing focus.

### The always-on-top-everywhere recipe

A **non-activating floating `NSPanel`** hosting a SwiftUI view:

```
styleMask:           [.nonactivatingPanel, .fullSizeContentView]   // borderless-ish, no focus steal
isFloatingPanel:     true
level:               .statusBar  (or higher; .floating is the minimum)
collectionBehavior:  [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
hidesOnDeactivate:   false
```

- `.canJoinAllSpaces` → follows you to every Space.
- `.fullScreenAuxiliary` → **the key flag** that lets it appear on top of
  full-screen apps (validated as still required on Sonoma+/Tahoe).
- `.nonactivatingPanel` + non-key behavior → clicking it doesn't pull focus away
  from your terminal.
- App is an **accessory / agent app** (`LSUIElement = true` /
  `NSApp.setActivationPolicy(.accessory)`) → no Dock icon, no Cmd-Tab entry; it's
  pure HUD. Optionally also place a menu-bar item.
- Note: a window can be `.canJoinAllSpaces` **or** `.moveToActiveSpace`, not
  both — we want the former.

### Why native over Tauri/Electron

| | Native SwiftUI | Tauri | Electron |
|---|---|---|---|
| Above full-screen Spaces | first-class (NSPanel flags) | possible via plugin, fiddlier | `setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true})` works but heavier |
| Memory footprint for a tiny HUD | tiny | small | large (Chromium) |
| Native notifications / materials | first-class | bridged | bridged |
| Cross-platform | macOS only | yes | yes |

For an always-running, must-be-tiny HUD, **native SwiftUI** wins. Choose Tauri
only if Windows/Linux support becomes a requirement.

### Rendering

- One row per session; collapsed/expanded modes (see UX sketch in concept doc).
- Dot is a small SwiftUI shape whose color **and** form encode state
  (color-blind safe). `thinking` = pulsing animation driven locally.
- Liquid Glass background via `.regularMaterial` / `NSVisualEffectView`.
- Draggable; persist frame in `UserDefaults`.

---

## Click-to-focus (R4)

Clicking a row should raise that agent's terminal. Reliability depends on how the
session was launched — store enough locator info in the status file:

- **tmux (best):** store `session:window.pane`. Click →
  `tmux select-window -t … \; select-pane -t …`, then activate the terminal app.
  Works regardless of which GUI terminal hosts tmux.
- **iTerm2:** has a scripting API (AppleScript/Python) to select a session by id.
- **Terminal.app / others:** AppleScript can raise a window by tty/title;
  best-effort.
- **Fallback:** if we only know the tty, `lsof`/`ps` can map it to a terminal
  process to focus the app, without selecting the exact tab.

This is the main argument for recommending **tmux** as the substrate.

---

## Sending work to an agent (R6, stretch)

Overlay → terminal is the inverse direction and is genuinely harder. Options,
best first:

1. **tmux `send-keys`** — type a prompt into the agent's pane:
   `tmux send-keys -t session:win.pane "do X" Enter`. Reliable, scriptable, also
   lets the overlay **launch** new agents (`tmux new-window 'claude'`).
2. **Headless/print mode** — for fire-and-forget jobs, the overlay spawns
   `claude -p "…"` / codex equivalent itself and tracks the child directly (no
   interactive terminal). Good for "send off a task" dispatch.
3. **Terminal automation (AppleScript)** — type into iTerm2/Terminal sessions.
   Fragile; last resort.

Recommendation: if we adopt tmux, R6 is mostly free — a text field in the
expanded overlay that `send-keys` to the focused agent, plus a "+ new agent"
button. Defer to v2.

---

## Suggested build phases

- **Phase 0 — Plumbing:** define the status-file schema; write the Claude +
  Codex hook scripts; verify `~/.aimonitor/sessions/*.json` updates as agents run
  (test with `cat`/`tail`, no UI yet).
- **Phase 1 — Overlay MVP:** SwiftUI accessory app, floating NSPanel with the
  collection-behavior flags, watches the dir, renders dots + labels. Verify it
  stays visible across Spaces and over a full-screen app.
- **Phase 2 — Attention + focus:** red badges, native notifications, click-row →
  focus terminal (tmux first).
- **Phase 3 — Dispatch:** send-keys text field + "new agent" launcher.
