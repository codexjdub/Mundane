import AppKit
import Foundation
import Observation

/// Tracks the current day, and the first day of the week, without ever polling.
///
/// A menu bar app is open forever, so a repeating `Timer` here would wake the CPU
/// every tick for the ~364 days a year nothing happens. These notifications cover
/// every way either can actually change:
///
///   - `NSCalendarDayChanged`  — midnight rolled over while we were awake
///   - `NSSystemClockDidChange` — the clock or time zone was changed under us
///   - `didWakeNotification`   — the machine slept through midnight and the other
///                               two never fired
///   - `currentLocaleDidChange` — the first day of the week was changed in
///                               System Settings → Language & Region
///
/// Idle cost between them is zero.
@Observable
final class Clock {
    private(set) var today: Date = Date()

    /// First day of the week as `Calendar` numbers it, 1 = Sunday … 7 = Saturday.
    /// Read from the system rather than offered as a setting: anyone who starts
    /// their week on Monday has already said so in System Settings.
    private(set) var weekStart: Int

    /// Where `weekStart` comes from: the system setting, except in a test, which
    /// substitutes its own so it can change the answer and post the notification.
    private let weekStartSource: () -> Int

    /// Called on the main thread whenever `today` moves to a different day.
    @ObservationIgnored var onDayChange: (() -> Void)?

    @ObservationIgnored private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// A clock pinned to one day and one week start, for reproducible offscreen
    /// rendering.
    ///
    /// Registers no observers: nothing should ever move it. The screenshot tool
    /// uses this so regenerating the README images does not rewrite them with
    /// whatever month it happens to be, or whichever week start that Mac has.
    init(pinnedTo day: Date, weekStart: Int = Weekday.sunday) {
        today = day
        self.weekStart = weekStart
        weekStartSource = { weekStart }
    }

    init(weekStartSource: @escaping () -> Int = { Calendar.autoupdatingCurrent.firstWeekday }) {
        self.weekStartSource = weekStartSource
        weekStart = weekStartSource()

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        observe(center, .NSCalendarDayChanged)
        observe(center, .NSSystemClockDidChange)
        observe(workspace, NSWorkspace.didWakeNotification)
        observe(center, NSLocale.currentLocaleDidChangeNotification)
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
        // Only on a real change, like `today` below, so a wake or a midnight
        // does not invalidate every grid for nothing.
        let start = weekStartSource()
        if start != weekStart { weekStart = start }

        let now = Date()
        // autoupdatingCurrent so a time zone change is reflected immediately.
        guard !Calendar.autoupdatingCurrent.isDate(now, inSameDayAs: today) else { return }
        today = now
        onDayChange?()
    }
}
