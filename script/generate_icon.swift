import AppKit
import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func icon(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    NSGradient(starting: NSColor(red: 0.16, green: 0.075, blue: 0.25, alpha: 1), ending: NSColor(red: 0.025, green: 0.022, blue: 0.06, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: 270)
    let orange = NSColor(red: 1, green: 0.43, blue: 0.09, alpha: 1)
    for radius in stride(from: 390, through: 240, by: -15) { orange.withAlphaComponent(0.012).setFill(); NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2)).fill() }
    let ghost = NSBezierPath()
    ghost.move(to: NSPoint(x: 236, y: 200)); ghost.line(to: NSPoint(x: 236, y: 566))
    ghost.curve(to: NSPoint(x: 788, y: 566), controlPoint1: NSPoint(x: 236, y: 938), controlPoint2: NSPoint(x: 788, y: 938))
    ghost.line(to: NSPoint(x: 788, y: 200))
    for (x,y) in [(677,285),(589,157),(494,285),(399,157),(313,285)] { ghost.line(to: NSPoint(x: x, y: y)) }; ghost.close()
    NSGraphicsContext.current!.saveGraphicsState(); ghost.addClip()
    NSGradient(starting: NSColor(red: 0.61, green: 0.51, blue: 0.83, alpha: 1), ending: .white)!.draw(in: NSRect(x: 200, y: 150, width: 640, height: 730), angle: 90)
    NSGraphicsContext.current!.restoreGraphicsState()
    let eyes = NSBezierPath()
    for polygon in [[(340,625),(467,576),(433,472),(340,507)],[(684,625),(557,576),(591,472),(684,507)]] { eyes.move(to: NSPoint(x: polygon[0].0, y: polygon[0].1)); for (x,y) in polygon.dropFirst() { eyes.line(to: NSPoint(x:x,y:y)) }; eyes.close() }
    orange.setFill(); eyes.fill()
    NSColor(red: 0.08, green: 0.03, blue: 0.14, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 460, y: 315, width: 104, height: 145)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16,32,64,128,256,512,1024] { try icon(size).write(to: folder.appendingPathComponent("icon-\(size).png")) }
