import AppKit
import Foundation

// Original geometric icon source. No Formula 1 logo or third-party image assets.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let canvas = NSSize(width: pixels, height: pixels)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let inset = CGFloat(pixels) * 0.08
        let frame = NSRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
        let background = NSBezierPath(roundedRect: frame, xRadius: CGFloat(pixels) * 0.19, yRadius: CGFloat(pixels) * 0.19)
        NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 1).setFill()
        background.fill()
        let stripe = NSBezierPath(roundedRect: NSRect(x: CGFloat(pixels) * 0.23, y: CGFloat(pixels) * 0.2, width: CGFloat(pixels) * 0.54, height: CGFloat(pixels) * 0.055), xRadius: CGFloat(pixels) * 0.02, yRadius: CGFloat(pixels) * 0.02)
        NSColor(calibratedRed: 0.90, green: 0.27, blue: 0.21, alpha: 1).setFill()
        stripe.fill()
        let pole = NSBezierPath(roundedRect: NSRect(x: CGFloat(pixels) * 0.25, y: CGFloat(pixels) * 0.32, width: CGFloat(pixels) * 0.035, height: CGFloat(pixels) * 0.42), xRadius: CGFloat(pixels) * 0.015, yRadius: CGFloat(pixels) * 0.015)
        NSColor.white.setFill()
        pole.fill()
        let cell = CGFloat(pixels) * 0.115
        for row in 0..<3 {
            for column in 0..<4 {
                ((row + column).isMultiple(of: 2) ? NSColor.white : NSColor(calibratedWhite: 0.36, alpha: 1)).setFill()
                NSRect(x: CGFloat(pixels) * 0.285 + CGFloat(column) * cell, y: CGFloat(pixels) * 0.395 + CGFloat(row) * cell, width: cell, height: cell).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
