import AppKit
import QuartzCore
import SwiftUI

enum Layout {
    /// Transparent room around the visible card, so the corner hanko can overlap
    /// the card's edge without macOS clipping it at the window bounds.
    ///
    /// Derived from the largest overhang any size produces rather than hardcoded:
    /// a hand-maintained constant silently clips the seal the moment someone adds
    /// a bigger SizeOption.
    static let stampMargin: CGFloat =
        (SizeOption.allCases.map { Sizing($0).hankoOverhang }.max() ?? 20) + 2
    /// Gap between the menu bar and the top of the card.
    static let dropGap: CGFloat = 2
    /// Closest the card may come to the screen edge.
    static let screenMargin: CGFloat = 8

}

/// Turns a stream of scroll deltas into discrete page steps.
///
/// Pulled out of the view so it can be tested without synthesising NSEvents.
/// A trackpad sends many small precise deltas, so those accumulate against a
/// threshold; a mouse wheel sends one coarse delta per notch, so each notch is
/// a step on its own.
struct ScrollAccumulator {
    static let threshold: CGFloat = 24
    private var accumulated: CGFloat = 0

    mutating func reset() { accumulated = 0 }

    /// Negative delta pages forward, matching "scroll down to go later".
    mutating func steps(delta: CGFloat, precise: Bool) -> Int {
        guard delta != 0 else { return 0 }
        guard precise else { return delta < 0 ? 1 : -1 }

        accumulated += delta
        var n = 0
        while abs(accumulated) >= Self.threshold {
            n += accumulated < 0 ? 1 : -1
            accumulated -= accumulated < 0 ? -Self.threshold : Self.threshold
        }
        return n
    }
}

/// Hosting view that pages the calendar on scroll.
final class ScrollingHostingView<Content: View>: NSHostingView<Content> {
    var onStep: ((Int) -> Void)?
    var onKey: ((PanelKey) -> Void)?
    private var accumulator = ScrollAccumulator()

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let key = PanelKey(event: event) { onKey?(key); return }
        super.keyDown(with: event)
    }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("not used") }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { accumulator.reset() }
        // Ignore momentum, or one flick sails through a decade.
        guard event.momentumPhase == [] else { return }

        var dy = event.scrollingDeltaY
        var dx = event.scrollingDeltaX
        if event.isDirectionInvertedFromDevice { dy = -dy; dx = -dx }

        // Whichever axis dominates, so a horizontal two-finger swipe works too.
        let delta = abs(dy) >= abs(dx) ? dy : dx
        let steps = accumulator.steps(delta: delta, precise: event.hasPreciseScrollingDeltas)
        if steps != 0 { onStep?(steps) }
    }
}

/// Non-activating panel that drops from the status item.
///
/// Deliberately not `MenuBarExtra`: that draws its own window background, which we
/// can't reliably clear, and the corner hanko needs a transparent margin around the
/// card. This also leaves the door open for pinning.
final class MundanePanel: NSPanel {
    private weak var anchorButton: NSStatusBarButton?
    private var resizeObserver: NSObjectProtocol?
    private let state: ViewState

    init(state: ViewState) {
        self.state = state
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 300),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let host = ScrollingHostingView(rootView: PanelContent(state: state))
        // page() already chooses the unit per view: months in the month and
        // 3-month views, years in the year view.
        host.onStep = { [weak state] steps in state?.page(steps) }
        host.onKey = { [weak self] key in self?.handle(key) }
        contentView = host
        setContentSize(host.fittingSize)

        resizeObserver = NotificationCenter.default.addObserver(
            // queue: nil, not .main. A non-nil queue enqueues the block, so the
            // reposition would land a run-loop turn after the resize and paint one
            // frame with the card hanging off the screen.
            forName: NSWindow.didResizeNotification, object: self, queue: nil
        ) { [weak self] _ in
            self?.repositionAfterResize()
        }
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    override var canBecomeKey: Bool { true }

    override func orderOut(_ sender: Any?) {
        // SwiftUI delivers no mouse-exit when the window disappears, so a hovered
        // arrow or chip would stay highlighted on the next open.
        state.hovered = nil
        super.orderOut(sender)
    }

    /// Key events land on the window, not the hosting view: nothing ever makes
    /// the SwiftUI view first responder, so the window stays first responder and
    /// receives keyDown itself. Handling it here rather than only on the content
    /// view is what makes the keyboard work at all.
    override func keyDown(with event: NSEvent) {
        if let key = PanelKey(event: event) { handle(key); return }
        super.keyDown(with: event)
    }

    func handle(_ key: PanelKey) {
        switch key {
        case .dismiss:  orderOut(nil)
        case .prev:     state.page(-1)
        case .next:     state.page(1)
        case .today:    state.goToToday()
        case .nextView: state.cycleView()
        }
    }
    override var canBecomeMain: Bool { false }

    func show(under button: NSStatusBarButton) {
        anchorButton = button
        layoutIfNeeded()
        let size = contentView?.fittingSize ?? frame.size
        setFrame(NSRect(origin: origin(for: size), size: size), display: false)
        makeKeyAndOrderFront(nil)
    }

    /// Reposition whenever the window changes size.
    ///
    /// NSHostingView has an intrinsic content size, so AppKit resizes this window
    /// on its own when the content changes — but it keeps the bottom-left origin,
    /// growing the window rightward and straight off the screen. AppKit gets the
    /// size right; all we have to do is fix the origin afterwards.
    ///
    /// An earlier version tried to drive this from a SwiftUI size preference.
    /// That never worked: the preference fired once with .zero and never again.
    private func repositionAfterResize() {
        guard anchorButton != nil else { return }
        let target = origin(for: frame.size)
        guard abs(target.x - frame.minX) > 0.5 || abs(target.y - frame.minY) > 0.5 else { return }
        setFrameOrigin(target)
    }

    /// Bottom-left origin that centres the card under the status item, shifted in
    /// if it would overhang the screen. Clamps are in card coordinates, then
    /// converted back out through the transparent margin.
    private func origin(for size: CGSize) -> NSPoint {
        guard let button = anchorButton, let buttonWindow = button.window else {
            // macOS hides status items when the menu bar is full, leaving no
            // window to anchor to. Returning frame.origin skipped clamping
            // entirely — on a first open that is the init rect in the bottom-left
            // corner. Fall back to the top right of the main screen instead.
            let visible = NSScreen.main?.visibleFrame ?? .zero
            let fallback = NSRect(x: visible.maxX - 60, y: visible.maxY,
                                  width: 55, height: 24)
            return Self.cardOrigin(itemRect: fallback, visible: visible, size: size,
                                   overhang: Sizing(state.settings.size).hankoOverhang)
        }
        let itemRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return Self.cardOrigin(itemRect: itemRect, visible: visible, size: size,
                               overhang: Sizing(state.settings.size).hankoOverhang)
    }

    /// Pure so it can be tested without a window.
    ///
    /// Each view is centred under the status item on its own, and clamped if it
    /// would run off the screen. Views of different widths therefore clamp by
    /// different amounts near a screen edge, so the panel shifts horizontally when
    /// you switch between them. That is chosen behaviour: centring under the icon
    /// was preferred over holding one position.
    ///
    /// The right-hand clamp allows for the hanko, which hangs past the card's edge
    /// and would otherwise be the one thing left hanging off the screen.
    static func cardOrigin(itemRect: NSRect, visible: NSRect,
                           size: CGSize, overhang: CGFloat) -> NSPoint {
        let cardWidth = size.width - 2 * Layout.stampMargin

        var cardLeft = itemRect.midX - cardWidth / 2
        cardLeft = min(cardLeft,
                       visible.maxX - Layout.screenMargin - overhang - cardWidth)
        cardLeft = max(cardLeft, visible.minX + Layout.screenMargin)

        // Hang from the status item, but never off the bottom of the screen.
        // (Content taller than the screen still can't fit; nothing here can help
        // with that short of scrolling.)
        let windowTop = itemRect.minY - Layout.dropGap + Layout.stampMargin
        var windowBottom = windowTop - size.height
        windowBottom = max(windowBottom,
                           visible.minY + Layout.screenMargin - Layout.stampMargin)

        return NSPoint(x: cardLeft - Layout.stampMargin, y: windowBottom)
    }
}
