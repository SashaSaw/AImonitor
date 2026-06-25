// Generates the app icon master PNG (1024x1024): a dark rounded tile with three
// status rows (blue / orange / green dots) echoing the overlay's look.
// Usage: swiftc make_icon.swift -o /tmp/makeicon && /tmp/makeicon icon_1024.png
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let inset: CGFloat = 78
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
bg.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.17, green: 0.21, blue: 0.29, alpha: 1),
                    NSColor(srgbRed: 0.07, green: 0.08, blue: 0.13, alpha: 1)])!
    .draw(in: rect, angle: -90)

let barW: CGFloat = 560, barH: CGFloat = 96, gap: CGFloat = 52
let totalH = 3 * barH + 2 * gap
let barX = (size - barW) / 2
let topY = (size + totalH) / 2 - barH
let dotColors = [NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),   // blue
                 NSColor(srgbRed: 0.96, green: 0.62, blue: 0.07, alpha: 1),   // orange
                 NSColor(srgbRed: 0.13, green: 0.77, blue: 0.37, alpha: 1)]   // green
for i in 0..<3 {
    let by = topY - CGFloat(i) * (barH + gap)
    NSColor.white.withAlphaComponent(0.13).setFill()
    NSBezierPath(roundedRect: NSRect(x: barX, y: by, width: barW, height: barH),
                 xRadius: barH / 2, yRadius: barH / 2).fill()
    let dotR: CGFloat = 27
    let cx = barX + 60, cy = by + barH / 2
    dotColors[i].setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()
}

img.unlockFocus()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
