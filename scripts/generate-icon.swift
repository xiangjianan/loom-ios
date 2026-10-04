import AppKit
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGradient(starting: NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.66, alpha: 1), ending: NSColor(calibratedRed: 0.56, green: 0.46, blue: 0.94, alpha: 1))!.draw(in: NSBezierPath(rect: NSRect(origin: .zero, size: size)), angle: 45)
for i in 0..<3 {
    let x = CGFloat(270 + i * 164)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: 740))
    path.curve(to: NSPoint(x: x + 95, y: 280), controlPoint1: NSPoint(x: x - 140, y: 530), controlPoint2: NSPoint(x: x + 235, y: 495))
    path.lineWidth = 68
    path.lineCapStyle = .round
    NSColor.white.withAlphaComponent(CGFloat(0.95 - Double(i) * 0.15)).setStroke()
    path.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
