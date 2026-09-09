import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Shade.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(size)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92), xRadius: s * 0.20, yRadius: s * 0.20).fill()
        let circle = NSBezierPath(ovalIn: NSRect(x: s * 0.23, y: s * 0.23, width: s * 0.54, height: s * 0.54))
        NSColor(calibratedRed: 0.39, green: 0.53, blue: 0.46, alpha: 1).set()
        circle.lineWidth = s * 0.025
        circle.stroke()
        circle.addClip()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: s / 2, height: s)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
