// Renders the real SwiftUI views offscreen into docs/screenshot.png.
// Run: Scripts/make.sh screenshot
//
// Rendered rather than screen-captured so the image needs no Screen Recording
// permission, carries none of the desktop with it, and can be regenerated after
// any design change.
import AppKit
import SwiftUI

@MainActor
func makeScreenshot() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // Pinned, not Clock(): an unpinned clock renders whatever today is, so
    // regenerating rewrites both PNGs with a different month for no reason.
    // This is the day the committed images already show.
    let clock = Clock(pinnedTo: MonthMeta.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!)
    let settings = Settings()
    settings.birthYear = 1990          // so the life bar appears in the shot

    func render(_ mode: ViewMode, dark: Bool) -> NSImage {
        let state = ViewState(clock: clock, settings: settings)
        state.mode = mode
        // colorScheme, not NSApp.appearance: ImageRenderer renders the view in
        // isolation and SwiftUI resolves the NSColor-backed palette from the
        // environment, so setting it on the app has no effect here.
        let renderer = ImageRenderer(
            content: PanelContent(state: state)
                .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2

        return renderer.nsImage ?? NSImage(size: .zero)
    }

    let gap: CGFloat = 28
    let pad: CGFloat = 36

    /// One sheet: the given views as a light row above a dark row.
    ///
    /// Split across two files because the year view is roughly four times the
    /// height of the month view — putting all three in one sheet left the short
    /// ones floating in a lot of empty space.
    func sheet(_ modes: [ViewMode], to name: String) throws {
        let rows = [false, true].map { dark in modes.map { render($0, dark: dark) } }
        let rowWidths = rows.map {
            $0.reduce(0) { $0 + $1.size.width } + gap * CGFloat($0.count - 1)
        }
        let rowHeights = rows.map { $0.map(\.size.height).max() ?? 0 }

        let width = (rowWidths.max() ?? 0) + pad * 2
        let height = rowHeights.reduce(0, +) + pad * 2

        // Backing store at 2x with the rep's logical size left in points, so the
        // context scales for us and the panels keep the resolution ImageRenderer
        // produced. Sizing the bitmap in points instead threw that away.
        let scale: CGFloat = 2
        let canvas = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: Int(width * scale),
                                      pixelsHigh: Int(height * scale),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        canvas.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)

        var y = height
        for (index, row) in rows.enumerated() {
            let rowHeight = rowHeights[index] + pad
            (index == 0 ? nsColor(0xEDEDEA) : nsColor(0x2A2A28)).setFill()
            NSRect(x: 0, y: y - rowHeight, width: width, height: rowHeight).fill()

            var x = (width - rowWidths[index]) / 2
            for image in row {
                let centred = y - rowHeight + (rowHeight - image.size.height) / 2
                image.draw(at: NSPoint(x: x, y: centred),
                           from: .zero, operation: .sourceOver, fraction: 1)
                x += image.size.width + gap
            }
            y -= rowHeight
        }
        NSGraphicsContext.restoreGraphicsState()

        let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/\(name)")
        try canvas.representation(using: .png, properties: [:])!.write(to: out)
        print("wrote docs/\(name)  \(Int(width * scale))x\(Int(height * scale)) px")
    }

    try sheet([.month, .threeMonths], to: "screenshot.png")
    try sheet([.year], to: "screenshot-year.png")
}

MainActor.assumeIsolated { try? makeScreenshot() }
