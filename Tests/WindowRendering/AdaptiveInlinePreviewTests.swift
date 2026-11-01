import AppKit
import SwiftUI
import XCTest

@MainActor final class AdaptiveInlinePreviewTests: XCTestCase {
    func testVisibleItemCountGrowsShrinksAndRemovesOverflowContent() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AdaptiveInlinePreview(count: 8) { visible, compact in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<visible, id: \.self) { _ in
                        Color(red: 0, green: 1, blue: 0).frame(width: compact ? nil : 100, height: 20)
                    }
                }
                if visible < 8 { Color(red: 0, green: 0, blue: 1).frame(width: 40, height: 20) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.white))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        // Different widths exercise natural fitting, the minimum-item compact
        // fallback, all-items/no-overflow, and returning to the narrow layout.
        for (width, count) in [(320, 3), (540, 5), (900, 8), (220, 3), (320, 3)] {
            window.setContentSize(NSSize(width: width, height: 80))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var maximumItems = 0
            var hasOverflow = false
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                var previousGreen = false
                var items = 0
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    // Offscreen calibrated RGB values depend on the display profile.
                    // Identify the saturated marker by channel dominance rather
                    // than assuming exact sRGB zeroes after AppKit conversion.
                    let green = color.greenComponent > color.redComponent + 0.3 && color.greenComponent > color.blueComponent + 0.3
                    if green && !previousGreen { items += 1 }
                    previousGreen = green
                    if color.blueComponent > color.redComponent + 0.3 && color.blueComponent > color.greenComponent + 0.3 { hasOverflow = true }
                }
                maximumItems = max(maximumItems, items)
            }
            XCTAssertEqual(maximumItems, count, "Wrong visible item count at width \(width)")
            XCTAssertEqual(hasOverflow, count < 8, "Overflow controls must disappear when every item fits")
        }
    }
}
