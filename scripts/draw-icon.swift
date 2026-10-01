// Draws the 1024 × 1024 app icon: a sequence diagram on a macOS-style rounded tile.
// Usage: swift scripts/draw-icon.swift <output.png>
import AppKit

let canvas = 1024
guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8, samplesPerPixel: 4,
          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ) else {
    FileHandle.standardError.write(Data("usage: swift draw-icon.swift <output.png>\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// Apple's icon grid: an 824 pt tile centred on the canvas.
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.white.setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.96, alpha: 1),
    ending: NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.86, alpha: 1)
)!.draw(in: tile, angle: -90)

let ink = NSColor.white
let columns: [CGFloat] = [320, 704]

// Participants at the top and bottom, joined by dashed lifelines.
for x in columns {
    for y: CGFloat in [680, 236] {
        let box = NSBezierPath(roundedRect: NSRect(x: x - 104, y: y, width: 208, height: 104), xRadius: 26, yRadius: 26)
        ink.setFill()
        box.fill()
    }
    let lifeline = NSBezierPath()
    lifeline.move(to: NSPoint(x: x, y: 680))
    lifeline.line(to: NSPoint(x: x, y: 340))
    lifeline.lineWidth = 14
    lifeline.setLineDash([30, 22], count: 2, phase: 0)
    ink.withAlphaComponent(0.8).setStroke()
    lifeline.stroke()
}

/// A message arrow between the lifelines at height `y`.
func message(from start: CGFloat, to end: CGFloat, at y: CGFloat, dashed: Bool) {
    let direction: CGFloat = end > start ? 1 : -1
    let tip = end - direction * 14
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: start + direction * 14, y: y))
    shaft.line(to: NSPoint(x: tip - direction * 40, y: y))
    shaft.lineWidth = 24
    shaft.lineCapStyle = .round
    if dashed { shaft.setLineDash([34, 26], count: 2, phase: 0) }
    ink.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: tip, y: y))
    head.line(to: NSPoint(x: tip - direction * 70, y: y + 44))
    head.line(to: NSPoint(x: tip - direction * 70, y: y - 44))
    head.close()
    ink.setFill()
    head.fill()
}

message(from: columns[0], to: columns[1], at: 570, dashed: false)
message(from: columns[1], to: columns[0], at: 440, dashed: true)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
