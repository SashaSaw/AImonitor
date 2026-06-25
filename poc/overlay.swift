// AImonitor — overlay POC (v2: send-to-agent + selection + quit menu)
//
// A non-activating floating panel that sits above every Space and full-screen
// window, reading per-session status files from ~/.aimonitor/sessions/*.json.
// Click a row to jump to that agent's tmux pane; type in the box to send a
// prompt to the selected agent via `tmux send-keys`.
//
// Build:  swiftc -O overlay.swift -o aimonitor-overlay
// Run:    ./aimonitor-overlay      (or build the .app with package.sh)

import AppKit
import ServiceManagement

// MARK: - Model

struct Session {
    var id: String
    var agent: String
    var title: String
    var state: String
    var detail: String
    var tmux: String
    var tty: String
    var updatedAt: Double
    var needsAttention: Bool
}

let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".aimonitor/sessions")

func loadSessions() -> [Session] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return [] }
    var result: [Session] = []
    for f in files where f.hasSuffix(".json") {
        let path = (sessionsDir as NSString).appendingPathComponent(f)
        guard let data = fm.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        result.append(Session(
            id: obj["id"] as? String ?? f,
            agent: obj["agent"] as? String ?? "?",
            title: obj["title"] as? String ?? "",
            state: obj["state"] as? String ?? "idle",
            detail: obj["detail"] as? String ?? "",
            tmux: obj["tmux"] as? String ?? "",
            tty: obj["tty"] as? String ?? "",
            updatedAt: (obj["updated_at"] as? Double) ?? 0,
            needsAttention: (obj["needs_attention"] as? Bool) ?? false
        ))
    }
    // stable sort by id; the controller imposes the real display order
    return result.sorted { $0.id < $1.id }
}

func color(for state: String) -> NSColor {
    switch state {
    case "thinking": return .systemBlue
    case "working":  return .systemOrange
    case "waiting":  return .systemRed
    case "done":     return .systemGreen
    case "error":    return .systemRed
    default:         return .systemGray   // idle
    }
}

let stoppedStates: Set<String> = ["waiting", "done"]

// Per-agent icon. Priority:
//   1. a file you drop in ~/.aimonitor/icons/<agent>.{png,jpg,jpeg,pdf,tiff}
//   2. a built-in tinted SF Symbol
// Custom files are re-read when their modification date changes (no restart).
let iconsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".aimonitor/icons")

private var symbolCache: [String: NSImage?] = [:]
private struct CachedFileIcon { var mtime: TimeInterval; var image: NSImage? }
private var fileIconCache: [String: CachedFileIcon] = [:]

func customIconURL(_ agent: String) -> URL? {
    for ext in ["png", "jpg", "jpeg", "pdf", "tiff"] {
        let p = (iconsDir as NSString).appendingPathComponent("\(agent).\(ext)")
        if FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
    }
    return nil
}

func agentIcon(_ agent: String) -> NSImage? {
    // 1. user-supplied file
    if let url = customIconURL(agent) {
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date)?
            .timeIntervalSince1970 ?? 0
        if let c = fileIconCache[agent], c.mtime == mtime { return c.image ?? builtinIcon(agent) }
        let img = NSImage(contentsOf: url)
        fileIconCache[agent] = CachedFileIcon(mtime: mtime, image: img)
        if img != nil { return img }
    } else {
        fileIconCache[agent] = nil
    }
    // 2. built-in SF Symbol
    return builtinIcon(agent)
}

func builtinIcon(_ agent: String) -> NSImage? {
    if let cached = symbolCache[agent] { return cached }
    let spec: (String, NSColor)?
    switch agent {
    case "claude": spec = ("sparkle", NSColor(srgbRed: 0.85, green: 0.44, blue: 0.30, alpha: 1))   // coral
    case "codex":  spec = ("chevron.left.forwardslash.chevron.right",
                           NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1))               // teal/green
    default:       spec = nil
    }
    guard let (name, color) = spec else { symbolCache[agent] = .some(nil); return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
    let img = NSImage(systemSymbolName: name, accessibilityDescription: agent)?.withSymbolConfiguration(cfg)
    symbolCache[agent] = img
    return img
}

// MARK: - Rows view

final class OverlayView: NSView {
    var sessions: [Session] = []
    var selectedID: String?
    var phase: CGFloat = 0
    let rowH: CGFloat = 28
    let headerH: CGFloat = 24
    let pad: CGFloat = 12

    var onClick: ((Session) -> Void)?
    var onDoubleClick: ((Session) -> Void)?   // jump to that agent's terminal
    var onMoveRow: ((Int, Int) -> Void)?      // live reorder: from -> to
    var onReorderEnd: (() -> Void)?           // commit/persist order
    var menuProvider: ((Session?) -> NSMenu?)?  // right-click menu for the row under the cursor

    private enum DragMode { case none, window, reorder }
    private var dragMode: DragMode = .none
    private var dragRow = -1
    private var movedDuringDrag = false
    private var downScreenPoint: NSPoint = .zero
    private var downOrigin: NSPoint = .zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let headerText = "AImonitor · \(sessions.count) agent\(sessions.count == 1 ? "" : "s")"
        headerText.draw(at: NSPoint(x: pad, y: 7), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])

        if sessions.isEmpty {
            "No agents running".draw(at: NSPoint(x: pad, y: headerH + 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
            ])
            return
        }

        var y = headerH
        for s in sessions {
            let cy = y + rowH / 2
            let stopped = stoppedStates.contains(s.state)
            let rowRect = NSRect(x: 4, y: y + 1, width: bounds.width - 8, height: rowH - 2)
            let c = color(for: s.state)
            let glowing = (s.state == "thinking" || s.state == "working")  // active = animated glow

            if glowing {
                // slow glow that breathes in and out (blue=thinking, orange=working)
                let g = 0.5 + 0.5 * sin(phase)            // 0…1
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = c.withAlphaComponent(0.15 + 0.55 * g)
                glow.shadowBlurRadius = 12
                glow.shadowOffset = .zero
                glow.set()
                c.withAlphaComponent(0.08 + 0.26 * g).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 6, yRadius: 6).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // steady highlight for every other state (waiting=red, done=green, idle=grey)
                c.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 6, yRadius: 6).fill()
            }

            let dotR: CGFloat = 5
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: pad, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()

            let labelX = pad + dotR * 2 + 9
            let box: CGFloat = 16
            if let icon = agentIcon(s.agent), icon.size.width > 0, icon.size.height > 0 {
                let scale = min(box / icon.size.width, box / icon.size.height)   // fit, keep aspect
                let w = icon.size.width * scale, h = icon.size.height * scale
                icon.draw(in: NSRect(x: labelX + (box - w) / 2, y: cy - h / 2, width: w, height: h))
            } else {
                (s.agent as NSString).draw(at: NSPoint(x: labelX, y: cy - 6), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                ])
            }
            let titleText = s.title.isEmpty ? s.state : s.title
            (titleText as NSString).draw(at: NSPoint(x: labelX + box + 8, y: cy - 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])

            let stateText = s.state
            let rAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: stopped ? .semibold : .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            let size = (stateText as NSString).size(withAttributes: rAttr)
            (stateText as NSString).draw(at: NSPoint(x: bounds.width - pad - size.width, y: cy - 6),
                                         withAttributes: rAttr)

            y += rowH
        }
    }

    private func rowIndex(at point: NSPoint) -> Int? {
        let y = point.y - headerH
        if y < 0 { return nil }
        let idx = Int(y / rowH)
        return idx >= 0 && idx < sessions.count ? idx : nil
    }

    // Header (title row) drags the whole window; a row drags to reorder.
    override func mouseDown(with event: NSEvent) {
        downScreenPoint = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        movedDuringDrag = false
        let p = convert(event.locationInWindow, from: nil)
        if let idx = rowIndex(at: p), !sessions.isEmpty {
            dragMode = .reorder
            dragRow = idx
        } else {
            dragMode = .window
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let cur = NSEvent.mouseLocation
        if hypot(cur.x - downScreenPoint.x, cur.y - downScreenPoint.y) >= 3 { movedDuringDrag = true }
        switch dragMode {
        case .window:
            window?.setFrameOrigin(NSPoint(x: downOrigin.x + (cur.x - downScreenPoint.x),
                                           y: downOrigin.y + (cur.y - downScreenPoint.y)))
        case .reorder:
            let p = convert(event.locationInWindow, from: nil)
            let target = max(0, min(sessions.count - 1, Int((p.y - headerH) / rowH)))
            if target != dragRow {
                onMoveRow?(dragRow, target)
                dragRow = target
            }
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode == .reorder && movedDuringDrag {
            onReorderEnd?()
        } else if !movedDuringDrag, let idx = rowIndex(at: convert(event.locationInWindow, from: nil)) {
            if event.clickCount >= 2 { onDoubleClick?(sessions[idx]) }
            else { onClick?(sessions[idx]) }
        }
        dragMode = .none
        dragRow = -1
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let s = rowIndex(at: convert(event.locationInWindow, from: nil)).map { sessions[$0] }
        return menuProvider?(s)
    }
}

// MARK: - Controller

final class Controller: NSObject, NSTextFieldDelegate, NSSoundDelegate {
    let panel: NSPanel
    let blur = NSVisualEffectView()
    let view = OverlayView()
    let field = NSTextField()
    let tmuxPath: String?
    var sessions: [Session] = []
    var lastStoppedTs: [String: Double] = [:]   // id -> updated_at of last stop we chimed for
    var soundSeeded = false                      // don't chime for sessions already stopped at launch
    var activeSounds: [NSSound] = []             // retain sounds until they finish playing
    var pruneCounter = 0                          // throttles the dead-session sweep
    var order: [String] = UserDefaults.standard.stringArray(forKey: "rowOrder") ?? []
    var soundVolume: Float = UserDefaults.standard.object(forKey: "soundVolume") != nil
        ? UserDefaults.standard.float(forKey: "soundVolume") : 1.0
    var volMenu: NSMenu?
    let fieldH: CGFloat = 24
    let width: CGFloat = 300
    let enableSend = false   // click-to-focus + send deferred for now

    override init() {
        tmuxPath = Controller.resolveTmux()
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 160),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered, defer: false)
        super.init()

        // --- always-on-top-everywhere recipe ---
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true   // lets the text field accept typing w/o activating the app
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        for b: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }

        panel.appearance = NSAppearance(named: .aqua)  // keep it light so black text reads
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        view.onClick = { [weak self] s in self?.select(s) }
        view.onDoubleClick = { [weak self] s in self?.focusTerminal(s) }
        view.onMoveRow = { [weak self] from, to in self?.moveRow(from, to) }
        view.onReorderEnd = { [weak self] in self?.saveOrder() }
        let vMenu = NSMenu()
        for (label, val) in [("Mute", 0), ("25%", 25), ("50%", 50), ("75%", 75), ("100%", 100)] {
            let it = NSMenuItem(title: label, action: #selector(setVolume(_:)), keyEquivalent: "")
            it.tag = val
            it.target = self
            vMenu.addItem(it)
        }
        volMenu = vMenu
        view.menuProvider = { [weak self] s in self?.buildMenu(for: s) }
        updateVolumeChecks()
        blur.addSubview(view)

        // send-to-agent input (deferred — only added when enableSend)
        if enableSend {
            field.placeholderString = "click an agent, then type to send…"
            field.font = NSFont.systemFont(ofSize: 11)
            field.bezelStyle = .roundedBezel
            field.focusRingType = .none
            field.isBordered = true
            field.drawsBackground = true
            field.target = self
            field.action = #selector(sendText)   // fires on Return
            field.delegate = self
            blur.addSubview(field)
        }

        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - width - 20, y: vf.maxY - 180))
        }
        panel.orderFrontRegardless()

        Timer.scheduledTimer(timeInterval: 0.25, target: self,
                             selector: #selector(tick), userInfo: nil, repeats: true)
        // smooth ~30fps glow animation, only redraws while something is thinking
        Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self,
                             selector: #selector(animTick), userInfo: nil, repeats: true)
        tick()
    }

    @objc func animTick() {
        guard sessions.contains(where: { $0.state == "thinking" || $0.state == "working" }) else { return }
        view.phase = (view.phase + 0.084).truncatingRemainder(dividingBy: 2 * .pi)  // ~2.5s/cycle
        view.needsDisplay = true
    }

    // MARK: tmux

    static func resolveTmux() -> String? {
        for c in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: c) { return c }
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-lc", "command -v tmux"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    func runTmux(_ args: [String]) {
        guard let tmux = tmuxPath else { return }
        let p = Process()
        p.launchPath = tmux
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // MARK: jump to terminal (double-click)

    func capture(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.launchPath = path
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func tmuxCapture(_ args: [String]) -> String {
        guard let t = tmuxPath else { return "" }
        return capture(t, args)
    }

    // walk a pid's ancestors until one lives inside a .app bundle; return that .app path
    func appPath(forPID start: Int) -> String? {
        var pid = start
        for _ in 0..<15 {
            let out = capture("/bin/ps", ["-p", "\(pid)", "-o", "ppid=,comm="])
            let line = out.trimmingCharacters(in: .whitespaces)
            guard let sp = line.firstIndex(of: " ") else { return nil }
            guard let ppid = Int(line[..<sp]) else { return nil }
            let path = String(line[line.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
            if let r = path.range(of: ".app/Contents/MacOS/") {
                return String(path[..<r.lowerBound]) + ".app"
            }
            if ppid <= 1 { return nil }
            pid = ppid
        }
        return nil
    }

    func focusLog(_ msg: String) {
        let p = (NSHomeDirectory() as NSString).appendingPathComponent(".aimonitor/focus.log")
        if let data = ("\(msg)\n").data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: p) { fh.seekToEndOfFile(); fh.write(data); try? fh.close() }
            else { try? data.write(to: URL(fileURLWithPath: p)) }
        }
    }

    func ttyDevice(_ t: String) -> String { t.hasPrefix("/dev/") ? String(t.dropFirst(5)) : t }
    func ttyPath(_ t: String) -> String { t.hasPrefix("/dev/") ? t : "/dev/" + t }

    func focusTerminal(_ s: Session) {
        // Decide the TERMINAL-WINDOW tty (not the agent's pane pty) and the owning app.
        var targetTTY = s.tty
        var appPathStr: String?

        if !s.tmux.isEmpty, tmuxPath != nil {
            runTmux(["select-window", "-t", s.tmux])   // switch tmux to the right pane
            runTmux(["select-pane", "-t", s.tmux])
            let session = tmuxCapture(["display-message", "-pt", s.tmux, "#{session_name}"])
            if !session.isEmpty {
                // the attached client's tty IS the terminal window hosting this tmux
                if let first = tmuxCapture(["list-clients", "-t", session, "-F", "#{client_tty}\t#{client_pid}"])
                    .split(whereSeparator: \.isNewline).first {
                    let parts = first.split(separator: "\t")
                    if parts.count >= 1 { targetTTY = String(parts[0]) }
                    if parts.count >= 2, let pid = Int(parts[1]) { appPathStr = appPath(forPID: pid) }
                }
            }
        }
        if appPathStr == nil, !targetTTY.isEmpty {
            let pids = capture("/bin/ps", ["-t", ttyDevice(targetTTY), "-o", "pid="])
                .split(whereSeparator: \.isNewline).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            for pid in pids { if let a = appPath(forPID: pid) { appPathStr = a; break } }
        }

        let appName = appPathStr.map { ($0 as NSString).lastPathComponent } ?? ""
        var method = "open"
        // Precisely raise the exact window/tab by tty where the app supports it.
        if !targetTTY.isEmpty, appName == "Terminal.app", raiseAppleTab(app: "Terminal", tty: targetTTY) {
            method = "applescript:Terminal"
        } else if !targetTTY.isEmpty, appName == "iTerm.app", raiseAppleTab(app: "iTerm", tty: targetTTY) {
            method = "applescript:iTerm"
        } else if let app = appPathStr {
            _ = capture("/usr/bin/open", [app])   // fallback: front the app (right window not guaranteed)
        } else {
            method = "none"
            NSSound.beep()
        }
        focusLog("dblclick id=\(s.id) tmux=\(s.tmux) tty=\(targetTTY) app=\(appName) method=\(method)")
    }

    // Bring the exact tab/window with this tty to the front (Terminal.app / iTerm).
    // Needs one-time Automation permission (System Settings ▸ Privacy ▸ Automation).
    func raiseAppleTab(app: String, tty: String) -> Bool {
        let dev = ttyPath(tty)
        let script: String
        if app == "iTerm" {
            script = """
            tell application "iTerm"
              repeat with w in windows
                try
                  repeat with t in tabs of w
                    repeat with ss in sessions of t
                      if tty of ss is "\(dev)" then
                        select w
                        tell t to select
                        tell ss to select
                        activate
                        return "ok"
                      end if
                    end repeat
                  end repeat
                end try
              end repeat
            end tell
            return "no"
            """
        } else {
            // `try` per window: some Terminal windows (Settings/inspector) have no
            // `tabs` and would otherwise abort the whole search with error -1728.
            script = """
            tell application "Terminal"
              activate
              repeat with w in windows
                try
                  repeat with t in tabs of w
                    if tty of t is "\(dev)" then
                      set selected of t to true
                      set frontmost of w to true
                      return "ok"
                    end if
                  end repeat
                end try
              end repeat
            end tell
            return "no"
            """
        }
        return capture("/usr/bin/osascript", ["-e", script]).contains("ok")
    }

    // MARK: actions

    func select(_ s: Session) {
        guard enableSend else { return }
        view.selectedID = s.id
        field.placeholderString = "→ send to \(s.title.isEmpty ? s.agent : s.title)…"
        if !s.tmux.isEmpty {                 // jump to the agent's pane
            runTmux(["select-window", "-t", s.tmux])
            runTmux(["select-pane", "-t", s.tmux])
        }
        view.needsDisplay = true
    }

    // MARK: ordering

    func moveRow(_ from: Int, _ to: Int) {
        guard from >= 0, from < order.count else { return }
        let id = order.remove(at: from)
        order.insert(id, at: min(max(to, 0), order.count))
        applyOrder()
        view.needsDisplay = true
    }

    func reconcileOrder() {
        let ids = sessions.map { $0.id }
        let present = Set(ids)
        let before = order
        order.removeAll { !present.contains($0) }
        for id in ids where !order.contains(id) { order.append(id) }  // new agents go to the bottom
        if order != before { saveOrder() }
    }

    func applyOrder() {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        sessions.sort { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
        view.sessions = sessions
    }

    func saveOrder() { UserDefaults.standard.set(order, forKey: "rowOrder") }

    // MARK: prune ended sessions
    // Claude deletes its own file via the SessionEnd hook. Codex has no such
    // event, and terminals can crash — so we also remove a session when its
    // agent process is no longer alive (tmux pane gone / reverted to a plain
    // shell, or no agent process left on its tty). Self-healing: if we're wrong,
    // the next hook event re-creates the file.
    func pruneDeadSessions() {
        let now = Date().timeIntervalSince1970
        let shells: Set<String> = ["zsh", "-zsh", "bash", "-bash", "sh", "fish", "-fish",
                                   "login", "tmux", "screen", "dash"]

        // tmux pane set — best-effort, only a fallback for sessions with no tty.
        var panes: Set<String> = []
        var havePanes = false
        if tmuxPath != nil {
            let out = tmuxCapture(["list-panes", "-a", "-F", "#{pane_id}"])
            if !out.isEmpty {
                havePanes = true
                panes = Set(out.split(whereSeparator: \.isNewline).map(String.init))
            }
        }

        for s in sessions {
            // Never prune a recently-active session: if it's still firing hooks
            // it's obviously alive. Also prevents any appear/disappear flicker.
            if now - s.updatedAt < 15 { continue }

            var dead = false
            if !s.tty.isEmpty {
                // `ps` reads the kernel proc table (no tmux socket needed), so this
                // is reliable even from a GUI/launchd app — and the tty is the pane
                // pty for tmux agents, so it covers both cases.
                let comms = capture("/bin/ps", ["-t", s.tty, "-o", "comm="])
                    .split(whereSeparator: \.isNewline)
                    .map { ($0 as NSString).lastPathComponent.lowercased() }
                dead = comms.isEmpty ? true : !comms.contains { !shells.contains($0) }
            } else if !s.tmux.isEmpty, havePanes {
                dead = !panes.contains(s.tmux)   // pane no longer exists
            }

            if dead {
                try? FileManager.default.removeItem(
                    atPath: (sessionsDir as NSString).appendingPathComponent(safeName(s.id) + ".json"))
            }
        }
    }

    func safeName(_ s: String) -> String {  // must match agent_status.py's sanitization
        String(s.map { $0.isLetter || $0.isNumber || "_.-".contains($0) ? $0 : "_" })
    }

    // MARK: context menu

    func buildMenu(for s: Session?) -> NSMenu {
        let m = NSMenu()
        if let s = s {
            let label = s.title.isEmpty ? s.agent : s.title
            let jump = NSMenuItem(title: "Jump to \(label)", action: #selector(menuJump(_:)), keyEquivalent: "")
            jump.target = self; jump.representedObject = s.id
            m.addItem(jump)
            let rem = NSMenuItem(title: "Remove \(label) from list", action: #selector(menuRemove(_:)), keyEquivalent: "")
            rem.target = self; rem.representedObject = s.id
            m.addItem(rem)
            m.addItem(.separator())
        }
        let volItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volItem.submenu = volMenu
        m.addItem(volItem)
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launch.target = self
        launch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(launch)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit AImonitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc func toggleLaunchAtLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = "\(error.localizedDescription)\n\nIf this keeps happening, move AImonitor.app to /Applications and try again."
            a.runModal()
        }
    }

    @objc func menuJump(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let s = sessions.first(where: { $0.id == id }) else { return }
        focusTerminal(s)
    }

    @objc func menuRemove(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        try? FileManager.default.removeItem(atPath: (sessionsDir as NSString).appendingPathComponent(safeName(id) + ".json"))
        order.removeAll { $0 == id }
        saveOrder()
        tick()   // refresh immediately
    }

    // MARK: sound volume

    @objc func setVolume(_ item: NSMenuItem) {
        soundVolume = Float(item.tag) / 100.0
        UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
        updateVolumeChecks()
        playSound("Glass")   // preview at the new level
    }

    func updateVolumeChecks() {
        let cur = Int((soundVolume * 100).rounded())
        volMenu?.items.forEach { $0.state = ($0.tag == cur) ? .on : .off }
    }

    func playSound(_ name: String) {
        // copy the shared named sound so each play is independent, and retain it
        // until didFinishPlaying — otherwise it deallocates mid-play and goes silent.
        guard soundVolume > 0, let snd = NSSound(named: name)?.copy() as? NSSound else { return }
        snd.volume = soundVolume
        snd.delegate = self
        activeSounds.append(snd)
        snd.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        activeSounds.removeAll { $0 === sound }
    }

    @objc func sendText() {
        let text = field.stringValue
        guard !text.isEmpty,
              let id = view.selectedID,
              let s = sessions.first(where: { $0.id == id }),
              !s.tmux.isEmpty else { NSSound.beep(); return }
        runTmux(["send-keys", "-t", s.tmux, "-l", text])  // -l = literal, safe for any text
        runTmux(["send-keys", "-t", s.tmux, "Enter"])
        field.stringValue = ""
    }

    @objc func tick() {
        sessions = loadSessions()
        reconcileOrder()
        applyOrder()                 // imposes stable / user-defined order
        playStopTones(for: sessions)

        pruneCounter += 1            // sweep for ended sessions ~every 2s
        if pruneCounter >= 8 { pruneCounter = 0; pruneDeadSessions() }

        let rows = max(sessions.count, 1)
        let rowsH = view.headerH + CGFloat(rows) * view.rowH + 12
        let total = rowsH + (enableSend ? fieldH + 14 : 8)
        var f = panel.frame
        if abs(f.height - total) > 0.5 {
            let top = f.maxY
            f.size.height = total
            f.origin.y = top - total
            panel.setFrame(f, display: true)
        }
        layout()
        view.needsDisplay = true
    }

    // Chime once for every *fresh* stop event (new updated_at), so a "done" never
    // gets missed — even on a fast turn, a repeat done, or a session first seen
    // already stopped. Two tones: Ping = waiting (needs you), Glass = done.
    func playStopTones(for sessions: [Session]) {
        let present = Set(sessions.map { $0.id })
        lastStoppedTs = lastStoppedTs.filter { present.contains($0.key) }

        // first pass: remember already-stopped sessions without chiming
        if !soundSeeded {
            for s in sessions where stoppedStates.contains(s.state) { lastStoppedTs[s.id] = s.updatedAt }
            soundSeeded = true
            return
        }

        for s in sessions where stoppedStates.contains(s.state) {
            if lastStoppedTs[s.id] != s.updatedAt {     // a new stop event for this agent
                lastStoppedTs[s.id] = s.updatedAt
                playSound(s.state == "waiting" ? "Ping" : "Glass")
            }
        }
    }

    func layout() {
        let b = blur.bounds
        if enableSend {
            field.frame = NSRect(x: 8, y: 7, width: b.width - 16, height: fieldH)
            view.frame = NSRect(x: 0, y: fieldH + 14, width: b.width, height: b.height - fieldH - 14)
        } else {
            view.frame = NSRect(x: 0, y: 4, width: b.width, height: b.height - 8)
        }
    }
}

// MARK: - main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Single instance: if another copy is already running (e.g. clicked again in the
// Dock, or login + manual launch), just exit so we don't stack overlays.
if let bid = NSRunningApplication.current.bundleIdentifier {
    let mypid = NSRunningApplication.current.processIdentifier
    let dupes = NSWorkspace.shared.runningApplications
        .filter { $0.bundleIdentifier == bid && $0.processIdentifier != mypid }
    if !dupes.isEmpty { exit(0) }
}

let controller = Controller()
app.run()
