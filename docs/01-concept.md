# 01 — Concept & Requirements

## Problem

When you run several terminal coding agents at once (Claude Code, Codex), you
lose track of which one needs you. They bury their state inside terminal windows
that are hidden behind full-screen apps or on other Spaces. You want one glance —
a compact heads-up display floating over everything — that tells you the state of
each agent and pings you when one is done or is blocked on a question.

## Requirements (from the brief)

| # | Requirement | Notes |
|---|-------------|-------|
| R1 | Floats **above everything** — across Spaces and full-screen windows | The hard macOS bit; solved by window level + collection behavior (see arch doc) |
| R2 | One status per agent: **thinking / working / waiting / done** | Plus derived states: idle, error, stale |
| R3 | **Compact**, non-distracting | Collapsed = a single small pill; expand on hover/click |
| R4 | **Clickable** — act on a row | v1: jump to that terminal. v2: dispatch work |
| R5 | **On-screen attention cue** — small red dot per agent when done/blocked | In-overlay badge + optional native banner/sound |
| R6 | Send work to a terminal from the program | Stretch goal; see "Sending work" in arch doc |
| R7 | Works on the newest macOS (Tahoe 26, 2026) | Native SwiftUI + Liquid Glass materials |

## Status model (state machine)

Each tracked session is in exactly one state:

```
              user submits / turn starts
   idle ───────────────────────────────▶ thinking
     ▲                                       │ runs a tool
     │                                       ▼
     │                                    working
     │  turn ends (Stop)                     │ needs permission / asks a question
     │◀──────────── done ◀──── working ──────┤
     │                                       ▼
     │                                    waiting  ──(answered)──▶ thinking
     │
     └──────────────── error / stale (no heartbeat) ──────────────
```

- **idle** — session alive, no active turn. Neutral/grey dot.
- **thinking** — model is generating, no tool yet. Pulsing blue dot.
- **working** — executing a tool (edit, bash, etc.). Solid blue/green dot.
- **waiting** — blocked on you: a permission prompt or a question. **Amber dot,
  this is the "needs attention" state.**
- **done** — turn finished. **Green dot + the red attention badge** until you
  acknowledge (click / focus the terminal).
- **error / stale** — non-zero exit, or no event for N seconds while it claimed
  to be working. Red/grey dot.

The exact event→state mapping for each agent is in
[`02-architecture.md`](./02-architecture.md#statusmapping).

## UX sketch

Compact, draggable, remembers position. Two display modes:

**Collapsed (default, tiny):**
```
┌───────────────────────────┐
│ ● ● ●  3 agents   ● 1 ⏺   │   ← one dot per agent + a summary; red ⏺ = attention
└───────────────────────────┘
```

**Expanded (hover / click):**
```
┌──────────────────────────────────────┐
│  AImonitor                        ⌄   │
├──────────────────────────────────────┤
│ ⏺ claude   api-refactor      0:42  ● │  ← amber = waiting on you (red badge)
│ ● claude   web-ui            1:15    │  ← blue  = working
│ ● codex    flaky-tests       0:08    │  ← pulsing = thinking
│ ✓ codex    migrate-db        done  ● │  ← green + red badge = just finished
└──────────────────────────────────────┘
        click a row → jump to that terminal
```

Design language: translucent Liquid Glass panel (`NSVisualEffectView` /
`.regularMaterial`), small monospace-ish labels, color-blind-safe dot shapes
(circle / pulse / ring / check) so state reads without relying on color alone.

## Attention cues (R5)

Layered, least-intrusive first:

1. **In-overlay badge** — a small red dot on the agent's row + a count in the
   collapsed pill. Always present, zero interruption.
2. **Subtle motion** — the row pulses once when it transitions to `waiting` or
   `done`.
3. **Optional native banner + sound** — `UNUserNotificationCenter` notification
   ("codex · migrate-db finished"). User-toggleable per state.
4. **Optional menu-bar glyph flash** — if we also run a menu-bar item.

Acknowledging = clicking the row / focusing that terminal clears the red badge.

## Non-goals (v1)

- Not a terminal multiplexer or a replacement for the agents' own TUIs.
- Not a usage/quota/cost meter (that's ClaudeBar's job — see prior art).
- No remote/over-the-network monitoring; everything is local.

## Open decisions

1. **Stack** — Native SwiftUI (lightest, best full-screen overlay + notifications)
   vs Tauri (cross-platform, web UI) vs Electron (heaviest). Recommendation:
   **native SwiftUI**.
2. **tmux as substrate?** If agents run inside tmux, click-to-focus and
   send-to-agent become trivial and reliable. If not, we fall back to
   per-terminal AppleScript/automation which is fragile. Recommendation: **support
   tmux first**, best-effort for raw terminals.
3. **Scope of v1** — monitor-only, or also dispatch work (R6)? Recommendation:
   ship monitor + click-to-focus first; dispatch in v2.
4. **Discovery** — do hooks register sessions (push), or do we also scan
   processes like c9watch (zero-config but coarser)? Recommendation: hooks for
   accuracy, process-scan as a fallback to catch un-instrumented sessions.
