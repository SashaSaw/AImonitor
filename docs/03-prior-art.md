# 03 — Prior Art & Research

Validated June 2026. Grouped by what to borrow from each.

## Closest references — Claude Code session monitors

- **Claude Code Agent View (built in)** — Anthropic's own. Press `\` inside a
  session to list all active Claude Code sessions and what each is doing.
  *Borrow:* the status vocabulary; *differs:* lives inside one terminal, Claude
  only — not a global cross-tool overlay.
  https://code.claude.com/docs/en/agent-view
- **gmr/claude-status** — native macOS menu-bar + desktop widget that monitors
  Claude Code sessions by watching session files; menu-bar shows aggregate state
  (emoji or minimal colored dots), click to jump to a session. **This is the
  single closest reference for AImonitor's file-watch + dots approach.**
  https://github.com/gmr/claude-status
- **c9watch** — native menu-bar app that auto-discovers running Claude Code
  sessions by **scanning processes at the OS level** (works with any terminal/
  IDE, zero config). *Borrow:* the process-scan fallback discovery idea.
- **minchenlee — "I built a macOS menu bar app to monitor all my Claude Code
  sessions"** — DEV write-up of building exactly this; good for the gotchas.
  https://dev.to/minchenlee/i-built-a-macos-menu-bar-app-to-monitor-all-my-claude-code-sessions-heres-how-it-works-1kb7
- **hoangsonww/Claude-Code-Agent-Monitor** — heavier real-time dashboard (Node +
  React + WebSockets): sessions, tool usage, Kanban status board, notifications,
  native + web. *Borrow:* status-board UX ideas; *differs:* much larger scope.
  https://github.com/hoangsonww/Claude-Code-Agent-Monitor
- **AgentsRoom** — Electron + xterm.js GUI: agent cards in a grid, live terminal
  streams. *Borrow:* multi-agent card layout; *differs:* full GUI, not a HUD.
  https://agentsroom.dev/claude-code-gui

## Quota/usage monitors (adjacent, not our goal — but good menu-bar patterns)

- **ClaudeBar (tddworks)** — macOS menu-bar app tracking Claude/Codex/Gemini/
  Antigravity usage quotas at a glance. *Borrow:* multi-provider menu-bar UX.
  https://github.com/tddworks/ClaudeBar
- **rjwalters/claude-monitor** — menu-bar widget polling the API for quota/reset/
  usage trends. https://github.com/rjwalters/claude-monitor

## Hooks — the status source

- **Claude Code hooks reference** — the lifecycle events
  (SessionStart, UserPromptSubmit, Pre/PostToolUse, Notification, Stop,
  SubagentStop, SessionEnd), JSON-on-stdin payloads, exit-code semantics.
  https://code.claude.com/docs/en/hooks
- **disler/claude-code-hooks-mastery** — worked examples of every hook.
  https://github.com/disler/claude-code-hooks-mastery
- **alexop.dev — Claude Code notification hooks** — concrete "alert me when it
  finishes / needs input" recipes (Stop + Notification).
  https://alexop.dev/posts/claude-code-notification-hooks/
- **Codex CLI hooks** — https://developers.openai.com/codex/hooks
  and **notify** (`agent-turn-complete`, `approval-requested`) configured in
  `~/.codex/config.toml` — https://developers.openai.com/codex/cli/features

## Always-on-top overlay technique (macOS window behavior)

- **Fazm — SwiftUI Floating Panel: NSPanel patterns** — the non-activating
  NSPanel + NSHostingView recipe we're using.
  https://fazm.ai/blog/swiftui-floating-panel
- **Fazm — Menu Bar App With a Floating Window: best practices**
  https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices
- **Apple Developer Forums — "Window visible on all spaces (incl. full screen)"**
  — confirms `.canJoinAllSpaces` + `.fullScreenAuxiliary`.
  https://developer.apple.com/forums/thread/26677
- General-purpose "keep window on top" apps to feel the UX of: **Topit**,
  **OnTop**, **Helium** (floating browser). For desktop-widget HUDs: **Übersicht**,
  **SketchyBar**, **xbar**.

## Takeaways for AImonitor

1. The **file-watch + colored-dots menu-bar** pattern is proven (claude-status).
   AImonitor's novelty is: (a) a **floating overlay** above full-screen Spaces
   rather than a menu-bar dropdown, and (b) **multi-tool** (Claude + Codex) in
   one view.
2. **Hooks are the right status source**; process-scanning (c9watch) is a good
   zero-config fallback for un-instrumented sessions.
3. Nobody in this list combines *global overlay + cross-tool + click-to-focus +
   send-to-agent* — that's the gap this project fills.
