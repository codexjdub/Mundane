import AppKit
import Testing
@testable import Mundane

// MARK: - Calendar maths

@Test func monthMetaRowCounts() {
    // Feb 2026 starts Sunday and ends Saturday — exactly four weeks.
    let feb = MonthMeta(year: 2026, month: 2)
    #expect(feb.rowCount == 4)
    #expect(feb.firstWeekday == 0)
    #expect(feb.lastColumn == 6)

    #expect(MonthMeta(year: 2026, month: 8).rowCount == 6)
    #expect(MonthMeta(year: 2026, month: 9).dayCount == 30)
    #expect(MonthMeta(year: 2024, month: 2).dayCount == 29)   // leap
}

@Test func cellsFillTheGridContiguously() {
    for month in 1 ... 12 {
        let meta = MonthMeta(year: 2026, month: month)
        let cells = meta.cells
        #expect(cells.count == meta.rowCount * 7)
        #expect(cells.filter(\.inMonth).count == meta.dayCount)
        // in-month days run 1...dayCount in order, with no gaps
        #expect(cells.filter(\.inMonth).map(\.day) == Array(1 ... meta.dayCount))
        // the arithmetically derived day numbers must equal Calendar's answer,
        // including the greyed neighbours either side
        for cell in cells {
            #expect(cell.day == MonthMeta.calendar.component(.day, from: cell.date))
        }
        // every cell is one day after the previous one
        for (a, b) in zip(cells, cells.dropFirst()) {
            let gap = MonthMeta.calendar.dateComponents([.day], from: a.date, to: b.date).day
            #expect(gap == 1)
        }
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

    let lastDay = YearProgress(for: at(2026, 12, 31))
    #expect(lastDay.dayOfYear == 365)           // label counts the day you are in
    #expect(lastDay.fraction < 1.0)             // but the bar is not full early

    #expect(YearProgress(for: at(2024, 12, 31)).totalDays == 366)
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
    for month in 1 ... 12 {
        let meta = MonthMeta(year: 2026, month: month)
        let path = Ribbon.path(meta: meta, cell: cell, radius: 11.6)
        #expect(!path.isEmpty)

        var corners = 0
        path.forEach { if case .quadCurve = $0 { corners += 1 } }

        // 8 corners normally; a month starting Sunday or ending Saturday drops 2.
        var expected = 8
        if meta.firstWeekday == 0 { expected -= 2 }
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

@Test func reservedWidthCoversEveryDateInAYear() {
    let menuFont = NSFont.menuBarFont(ofSize: 0)
    let font = NSFont.monospacedDigitSystemFont(ofSize: menuFont.pointSize, weight: .regular)
    func width(_ s: String) -> CGFloat {
        let probe = NSStatusBarButton()
        probe.font = font
        probe.title = s
        probe.sizeToFit()
        return probe.frame.width
    }
    let cal = MonthMeta.calendar
    for style in DateStyle.allCases {
        let reserved = width(style.widestSample)
        for month in 1 ... 12 {
            let first = cal.date(from: DateComponents(year: 2026, month: month, day: 1))!
            for day in cal.range(of: .day, in: .month, for: first)! {
                let date = cal.date(from: DateComponents(year: 2026, month: month, day: day))!
                #expect(width(style.string(for: date)) <= reserved)
            }
        }
    }
}
