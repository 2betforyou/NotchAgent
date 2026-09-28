import AppKit

// App icon: a dark squircle with the notch hanging from its top edge and a bold mint `>_`.
// Everything is drawn on a 1024-point canvas and scaled to each iconset size.
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

let mint = NSColor(srgbRed: 0.66, green: 0.96, blue: 0.75, alpha: 1)

func drawIcon() {
    let body = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 206, yRadius: 206)
    NSGraphicsContext.saveGraphicsState()
    NSGradient(starting: NSColor(white: 0.18, alpha: 1), ending: NSColor(white: 0.04, alpha: 1))!.draw(in: body, angle: -90)
    body.addClip() // the notch is cut by the icon shape instead of poking out of it
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 332, y: 832, width: 360, height: 210), xRadius: 58, yRadius: 58).fill()
    // Prompt: chevron and cursor bar, heavy enough to read at 16 px.
    let origin = NSPoint(x: 262, y: 330), size: CGFloat = 260, weight: CGFloat = 64
    mint.setStroke(); mint.setFill()
    let chevron = NSBezierPath(); chevron.lineWidth = weight; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: origin.x, y: origin.y + size))
    chevron.line(to: NSPoint(x: origin.x + size * 0.62, y: origin.y + size / 2))
    chevron.line(to: origin)
    chevron.stroke()
    let bar = NSRect(x: origin.x + size * 0.9, y: origin.y - weight / 2, width: size * 0.95, height: weight)
    NSBezierPath(roundedRect: bar, xRadius: weight / 2, yRadius: weight / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0.3, alpha: 1).setStroke(); body.lineWidth = 3; body.stroke()
}

for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    (AffineTransform(scale: CGFloat(size) / 1024) as NSAffineTransform).concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination + "/" + name + ".png"))
}
