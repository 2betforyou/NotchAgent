import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(size) / 1024); (transform as NSAffineTransform).concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 206, yRadius: 206)
    NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.035, alpha: 1))!.draw(in: base, angle: -90)
    NSColor(white: 0.25, alpha: 1).setStroke(); base.lineWidth = 3; base.stroke()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 316, y: 775, width: 392, height: 250), xRadius: 70, yRadius: 70).fill()
    let mint = NSColor(srgbRed: 0.66, green: 0.96, blue: 0.75, alpha: 1)
    mint.setStroke()
    let prompt = NSBezierPath(); prompt.lineWidth = 52; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round
    prompt.move(to: NSPoint(x: 280, y: 610)); prompt.line(to: NSPoint(x: 420, y: 480)); prompt.line(to: NSPoint(x: 280, y: 350)); prompt.stroke()
    let line = NSBezierPath(); line.lineWidth = 48; line.lineCapStyle = .round
    line.move(to: NSPoint(x: 520, y: 350)); line.line(to: NSPoint(x: 730, y: 350)); line.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination + "/" + name + ".png"))
}
