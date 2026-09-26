import AppKit
import Testing
@testable import Mundane

// MARK: - Calendar maths

@Test func monthMetaRowCounts() {
    // Feb 2026 starts Sunday and ends Saturday — exactly four weeks.
    let feb = MonthMeta(year: 2026, month: 2, weekStart: Weekday.sunday)
    #expect(feb.rowCount == 4)
    #expect(feb.firstColumn == 0)
    #expect(feb.lastColumn == 6)

    // The same month in a Monday-first week: the 1st, a Sunday, moves to the
    // last column, so four weeks of days now span five rows.
    let febMonday = MonthMeta(year: 2026, month: 2, weekStart: Weekday.monday)
    #expect(febMonday.firstColumn == 6)
    #expect(febMonday.rowCount == 5)
    #expect(febMonday.lastColumn == 5)

    #expect(MonthMeta(year: 2026, month: 8, weekStart: Weekday.sunday).rowCount == 6)
    #expect(MonthMeta(year: 2026, month: 9, weekStart: Weekday.sunday).dayCount == 30)
    #expect(MonthMeta(year: 2024, month: 2, weekStart: Weekday.sunday).dayCount == 29)   // leap
}

@Test func cellsFillTheGridContiguously() {
    // Every week start, not just Sunday and Monday: a Saturday-first week
    // exercises the wrap in the column arithmetic hardest.
    for weekStart in 1 ... 7 {
        for month in 1 ... 12 {
            let meta = MonthMeta(year: 2026, month: month, weekStart: weekStart)
            let cells = meta.cells
            #expect(cells.count == meta.rowCount * 7)
            #expect(cells.filter(\.inMonth).count == meta.dayCount)
            // in-month days run 1...dayCount in order, with no gaps
            #expect(cells.filter(\.inMonth).map(\.day) == Array(1 ... meta.dayCount))
            // column 0 is the week start
            #expect(cells[0].weekday == weekStart)
            for cell in cells {
                // the arithmetically derived day numbers must equal Calendar's
                // answer, including the greyed neighbours either side
                #expect(cell.day == MonthMeta.calendar.component(.day, from: cell.date))
                // and so must the weekday that decides the red and the blue —
                // this is what fails if colours key off a column again
                #expect(cell.weekday == MonthMeta.calendar.component(.weekday, from: cell.date))
            }
            // every cell is one day after the previous one
            for (a, b) in zip(cells, cells.dropFirst()) {
                let gap = MonthMeta.calendar.dateComponents([.day], from: a.date, to: b.date).day
                #expect(gap == 1)
            }
        }
    }
}

@Test func headerAndBandFollowTheWeekStart() {
    // The header, the weekend band and the cells draw straight from these, with
    // no column arithmetic of their own — so this is what fails if any of them
    // is keyed off a column again.
    #expect(Weekday.columns(weekStart: Weekday.sunday) == [1, 2, 3, 4, 5, 6, 7])
    #expect(Weekday.columns(weekStart: Weekday.monday) == [2, 3, 4, 5, 6, 7, 1])
    #expect(Weekday.columns(weekStart: Weekday.sunday).map(Weekday.letter)
            == ["S", "M", "T", "W", "T", "F", "S"])
    #expect(Weekday.columns(weekStart: Weekday.monday).map(Weekday.letter)
            == ["M", "T", "W", "T", "F", "S", "S"])
    // Monday-first: one band across the last two columns, Saturday then Sunday,
    // rather than one at each edge.
    #expect(Weekday.columns(weekStart: Weekday.monday).map(Weekday.isWeekend)
            == [false, false, false, false, false, true, true])
    #expect(Weekday.columns(weekStart: Weekday.monday).suffix(2)
            == [Weekday.saturday, Weekday.sunday])
    for start in 1 ... 7 {
        let columns = Weekday.columns(weekStart: start)
        #expect(columns.first == start)
        #expect(Set(columns) == Set(1 ... 7))                  // each day once
        #expect(columns.filter(Weekday.isWeekend).count == 2)
    }
}

@Test func calendarFollowsTimeZoneChanges() {
    // A plain Calendar(identifier:) freezes TimeZone.current at first access,
    // which made the grid and the menu bar disagree after travel.
    #expect(MonthMeta.calendar.timeZone == TimeZone.autoupdatingCurrent)
}

@Test func yearProgressCountsCompletedDays() {
    let cal = MonthMeta.calendar
    func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    let newYear = YearProgress(for: at(2026, 1, 1))
    #expect(newYear.dayOfYear == 1)
    #expect(newYear.fraction == 0)              // no days completed yet
    #expect(newYear.daysLeft == 365)            // the whole year still to run

    let lastDay = YearProgress(for: at(2026, 12, 31))
    #expect(lastDay.dayOfYear == 365)
    #expect(lastDay.fraction < 1.0)             // the bar is not full early
    #expect(lastDay.daysLeft == 1)              // and today still counts as left

    // The day the README screenshots are pinned to.
    #expect(YearProgress(for: at(2026, 9, 22)).daysLeft == 101)

    #expect(YearProgress(for: at(2024, 12, 31)).totalDays == 366)

    // The label is the empty part of the bar on every day, leap year included.
    for year in [2024, 2026] {
        var day = at(year, 1, 1)
        while cal.component(.year, from: day) == year {
            let p = YearProgress(for: day)
            #expect((p.dayOfYear - 1) + p.daysLeft == p.totalDays)
            #expect(abs(p.fraction + Double(p.daysLeft) / Double(p.totalDays) - 1) < 1e-12)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
    }
}

@Test func lifeProgressRejectsAndClamps() {
    let cal = MonthMeta.calendar
    let today = cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!

    #expect(LifeProgress(birthYear: 1899, on: today) == nil)
    #expect(LifeProgress(birthYear: 2027, on: today) == nil)
    #expect(LifeProgress(birthYear: 0, on: today) == nil)

    // 31 December must not tip the age a year early.
    #expect(LifeProgress(birthYear: 1990, on: today)?.years == 36)
    // Beyond the assumed span the bar saturates rather than overflowing.
    #expect(LifeProgress(birthYear: 1920, on: today)?.fraction == 1.0)
}

@Test func ganzhiFlipsOnTheLunisolarNewYear() {
    let cal = MonthMeta.calendar
    func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    // Not 1 January: 2026 stays 乙巳 until Chinese New Year.
    #expect(Ganzhi.string(for: at(2026, 1, 20)) == "乙巳")
    #expect(Ganzhi.string(for: at(2026, 9, 21)) == "丙午")
    // A CJK locale is required, or this renders romanised pinyin.
    #expect(Ganzhi.string(for: at(2026, 9, 21)).count == 2)
}

// MARK: - Ribbon geometry

@Test func ribbonCollapsesOnDegenerateMonths() {
    let cell = CGSize(width: 31, height: 29)
    for weekStart in 1 ... 7 {
        for month in 1 ... 12 {
            let meta = MonthMeta(year: 2026, month: month, weekStart: weekStart)
            let path = Ribbon.path(meta: meta, cell: cell, radius: 11.6)
            #expect(!path.isEmpty)

            var corners = 0
            path.forEach { if case .quadCurve = $0 { corners += 1 } }

            // 8 corners normally; a month starting in the first column or
            // ending in the last drops 2.
            var expected = 8
            if meta.firstColumn == 0 { expected -= 2 }
            if meta.lastColumn == 6 { expected -= 2 }
            #expect(corners == expected)

            // The stroke must stay inside the grid on all four sides.
            let box = path.boundingRect
            #expect(box.minX >= 0)
            #expect(box.minY >= 0)
            #expect(box.maxX <= 7 * cell.width)
            #expect(box.maxY <= CGFloat(meta.rowCount) * cell.height)
        }
    }
}

// MARK: - Panel positioning

@Test func panelStaysOnScreenIncludingTheSeal() {
    let screens = [
        NSRect(x: 47, y: 0, width: 3393, height: 1410),
        NSRect(x: 0, y: 0, width: 1512, height: 944),
        NSRect(x: 0, y: 0, width: 1280, height: 775),
    ]
    let views: [CGSize] = [
        CGSize(width: 261, height: 330),
        CGSize(width: 723, height: 330),
        CGSize(width: 638, height: 800),
    ]
    for visible in screens {
        for option in SizeOption.allCases {
            let overhang = Sizing(option).hankoOverhang
            for fraction in [0.02, 0.25, 0.5, 0.75, 1.0] {
                let midX = visible.minX + visible.width * fraction
                let item = NSRect(x: midX - 27.5, y: visible.maxY, width: 55, height: 24)
                for size in views {
                    let origin = MundanePanel.cardOrigin(itemRect: item, visible: visible,
                                                         size: size, overhang: overhang)
                    let left = origin.x + Layout.stampMargin
                    let right = left + size.width - 2 * Layout.stampMargin
                    #expect(left >= visible.minX)
                    #expect(right + overhang <= visible.maxX)
                    #expect(origin.y + Layout.stampMargin >= visible.minY)
                }
            }
        }
    }
}

@Test func transparentMarginAlwaysClearsTheSeal() {
    // If this fails, a new SizeOption has made the hanko wider than the window's
    // transparent border and macOS will clip it.
    for option in SizeOption.allCases {
        #expect(Sizing(option).hankoOverhang < Layout.stampMargin)
    }
}

// MARK: - Input

@Test func scrollAccumulatorStepsAndCarries() {
    var wheel = ScrollAccumulator()
    #expect(wheel.steps(delta: -3, precise: false) == 1)     // one notch, one step
    #expect(wheel.steps(delta: 3, precise: false) == -1)
    #expect(wheel.steps(delta: -120, precise: false) == 1)   // magnitude irrelevant

    var pad = ScrollAccumulator()
    let total = (0 ..< 5).reduce(0) { sum, _ in sum + pad.steps(delta: -5, precise: true) }
    #expect(total == 1)                                       // -25 crosses 24
    #expect(pad.steps(delta: -100, precise: true) == 4)       // carries the remainder

    var reset = ScrollAccumulator()
    _ = reset.steps(delta: -20, precise: true)
    reset.reset()
    #expect(reset.steps(delta: -20, precise: true) == 0)      // carry cleared
}

@Test func onlyBareKeysAct() {
    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil, characters: "",
                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    // Arrows always carry .function/.numericPad, so those must not disqualify them.
    #expect(PanelKey(event: key(123, [.function, .numericPad])) != nil)
    #expect(PanelKey(event: key(49, [])) != nil)

    #expect(PanelKey(event: key(123, [.command, .function])) == nil)
    #expect(PanelKey(event: key(48, [.shift])) == nil)
    #expect(PanelKey(event: key(49, [.option])) == nil)
    #expect(PanelKey(keyCode: 0) == nil)                      // unmapped key
}

@Test func persistedHotkeyMustCarryAModifier() throws {
    let bare = #"{"keyCode":49,"modifiers":0,"display":"Space"}"#.data(using: .utf8)!
    #expect((try? JSONDecoder().decode(HotkeyCombo.self, from: bare)) == nil)

    let valid = #"{"keyCode":49,"modifiers":256,"display":"⌘Space"}"#.data(using: .utf8)!
    let combo = try JSONDecoder().decode(HotkeyCombo.self, from: valid)
    #expect(combo.keyCode == 49)
    #expect(combo.modifiers == 256)
}

// MARK: - Menu bar width

@Test func menuBarWidthOnlyChangesWithTheDigitCount() {
    // The item is sized to the date, so it moves its neighbours whenever its
    // width changes. Monospaced digits keep that to the days it gains or loses a
    // digit; with proportional ones "11" and "18" differ and it would shift on
    // most days of the month. Every date with the same number of digits must
    // measure exactly the same.
    func width(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: StatusItemController.font]).width
    }
    let cal = MonthMeta.calendar
    for style in DateStyle.allCases {
        var byDigits: [Int: CGFloat] = [:]
        for month in 1 ... 12 {
            let first = cal.date(from: DateComponents(year: 2026, month: month, day: 1))!
            for day in cal.range(of: .day, in: .month, for: first)! {
                let text = style.string(for: cal.date(from:
                    DateComponents(year: 2026, month: month, day: day, hour: 12))!)
                let digits = text.filter(\.isNumber).count
                if let seen = byDigits[digits] {
                    #expect(width(text) == seen, "\(style) \(text)")
                } else {
                    byDigits[digits] = width(text)
                }
            }
        }
        #expect(byDigits.count >= 2)    // both digit counts actually occurred
    }
}

// MARK: - Clock

/// Stands in for the system setting, so a test can change it.
private final class WeekStartSetting {
    var value = Weekday.sunday
}

@Test @MainActor func weekStartFollowsLocaleChanges() async {
    let setting = WeekStartSetting()
    let clock = Clock(weekStartSource: { setting.value })
    #expect(clock.weekStart == Weekday.sunday)

    // What changing it in System Settings amounts to: the preference changes,
    // then the locale notification arrives. The app is never relaunched, so
    // this is the only way an open panel learns about it.
    setting.value = Weekday.monday
    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification,
                                    object: nil)
    // The observer runs on the main queue; let it drain before looking.
    await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    #expect(clock.weekStart == Weekday.monday)
}
