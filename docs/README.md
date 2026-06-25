# AImonitor — Agent Status Overlay

A tiny, always-on-top macOS overlay that shows the live status of the terminal
coding agents (Claude Code, Codex) you have running — thinking, working, waiting
for an answer, or done — and nudges you with a small badge/notification when one
needs you.

These are **concept docs only**. No implementation yet.

## Documents

1. [`01-concept.md`](./01-concept.md) — What it is, the requirements, the UX, the
   status model.
2. [`02-architecture.md`](./02-architecture.md) — How it works: the overlay
   window, how it learns each agent's status, click-to-focus, sending work to
   agents.
3. [`03-prior-art.md`](./03-prior-art.md) — Existing apps/tools to study or
   borrow from, with links, validated June 2026.

## The one-paragraph version

Each agent already emits lifecycle events through its own hook system (Claude
Code **hooks**, Codex **notify/hooks**). We attach a tiny script to those events
that writes a per-session status update to a shared channel. A lightweight native
SwiftUI app reads that channel and paints one compact "dot + label" row per
agent in a floating panel configured to sit above every Space and full-screen
window. A red dot / native banner fires when an agent finishes or asks a
question; clicking a row jumps you to that terminal.

## Key decisions still open (see end of 01-concept.md)

- Native Swift vs cross-platform (Tauri/Electron)?
- Is **tmux** an acceptable substrate? (It makes click-to-focus and
  send-to-agent dramatically more reliable.)
- Monitor-only for v1, or also dispatch work to agents from the overlay?
- Which terminals must be supported (Terminal.app, iTerm2, Ghostty, WezTerm…)?
