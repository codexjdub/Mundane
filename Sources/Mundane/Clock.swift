import AppKit
import Foundation
import Observation

/// Tracks the current day without ever polling.
///
/// A menu bar app is open forever, so a repeating `Timer` here would wake the CPU
/// every tick for the ~364 days a year nothing happens. These three notifications
/// cover every way the day can actually change:
///
///   - `NSCalendarDayChanged`  — midnight rolled over while we were awake
///   - `NSSystemClockDidChange` — the clock or time zone was changed under us
///   - `didWakeNotification`   — the machine slept through midnight and the other
///                               two never fired
///
/// Idle cost between them is zero.
@Observable
final class Clock {
    private(set) var today: Date = Date()

    /// Called on the main thread whenever `today` moves to a different day.
    @ObservationIgnored var onDayChange: (() -> Void)?

    @ObservationIgnored private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// A clock pinned to one day, for reproducible offscreen rendering.
    ///
    /// Registers no observers: nothing should ever move it. The screenshot tool
    /// uses this so regenerating the README images does not rewrite them with
    /// whatever month it happens to be.
    init(pinnedTo day: Date) {
        today = day
    }

    init() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        observe(center, .NSCalendarDayChanged)
        observe(center, .NSSystemClockDidChange)
        observe(workspace, NSWorkspace.didWakeNotification)
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        tokens.append((center, token))
    }

    private func refresh() {
        let now = Date()
        // autoupdatingCurrent so a time zone change is reflected immediately.
        guard !Calendar.autoupdatingCurrent.isDate(now, inSameDayAs: today) else { return }
        today = now
        onDayChange?()
    }
}
