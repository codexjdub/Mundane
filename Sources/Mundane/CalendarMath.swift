import Foundation

/// One cell of a 7-wide month grid, including the greyed neighbours that fill
/// out the first and last weeks.
struct DayCell: Identifiable {
    let id: Int
    let day: Int
    let inMonth: Bool
    /// The real weekday, not the column — which column Sunday sits in depends
    /// on which day the week starts.
    let weekday: Int
    let date: Date
}

/// Weekdays as `Calendar` numbers them, 1 = Sunday … 7 = Saturday. These are
/// absolute — Sunday is 1 however the week is laid out — so anything coloured by
/// day keys off these, never off a column.
enum Weekday {
    static let sunday = 1
    static let monday = 2
    static let saturday = 7

    /// The weekday shown in `column` of a grid whose week starts on `weekStart`.
    static func at(column: Int, weekStart: Int) -> Int {
        (weekStart - 1 + column) % 7 + 1
    }

    /// All seven weekdays in column order. The header, the weekend band and the
    /// cells all read this rather than doing column arithmetic of their own, so
    /// none of them can drift back to keying off a column.
    static func columns(weekStart: Int) -> [Int] {
        (0 ..< 7).map { at(column: $0, weekStart: weekStart) }
    }

    /// Sunday and Saturday: the days drawn in red and blue, and shaded.
    static func isWeekend(_ weekday: Int) -> Bool {
        weekday == sunday || weekday == saturday
    }

    /// Header letter for a weekday. English whatever the locale: the system's
    /// own symbols would put 日月火… on a Japanese Mac, and the design has no
    /// kanji headers.
    static func letter(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }
}

/// Everything the grid and the ribbon need to know about a month.
struct MonthMeta {
    let year: Int
    let month: Int
    /// First day of the week, 1 = Sunday … 7 = Saturday.
    let weekStart: Int
    /// Column of the 1st, counted from the first day of the week.
    let firstColumn: Int
    let dayCount: Int
    let rowCount: Int
    /// Column of the last day of the month.
    let lastColumn: Int

    /// Its own `firstWeekday` is deliberately left alone: the only component
    /// read from it is `.weekday`, which counts from Sunday regardless, and grid
    /// columns come from `weekStart`.
    /// `timeZone` is explicitly autoupdating. A plain `Calendar(identifier:)`
    /// snapshots `TimeZone.current` at first access and keeps it forever, which
    /// made the grid resolve "today" in the old zone after travel while the menu
    /// bar (which uses `.autoupdatingCurrent`) had already moved on.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    /// `weekStart` has no default on purpose: a call site that forgot it would
    /// silently lay out Sunday-first for everyone, which is the bug this fixes.
    init(year: Int, month: Int, weekStart: Int) {
        self.year = year
        self.month = month
        self.weekStart = weekStart
        let cal = Self.calendar
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        self.firstColumn = (cal.component(.weekday, from: first) - weekStart + 7) % 7
        self.dayCount = cal.range(of: .day, in: .month, for: first)!.count
        self.rowCount = Int((Double(firstColumn + dayCount) / 7.0).rounded(.up))
        self.lastColumn = (firstColumn + dayCount - 1) % 7
    }

    init(containing date: Date, weekStart: Int) {
        let c = Self.calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 2026, month: c.month ?? 1, weekStart: weekStart)
    }

    var firstDay: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// Day numbers are derived arithmetically rather than asked of `Calendar`
    /// per cell — the grid is a contiguous run of integers, and the ICU round
    /// trip was the second largest cost in a year render.
    var cells: [DayCell] {
        let cal = Self.calendar
        let first = firstDay
        let previousDayCount = cal.range(of: .day, in: .month,
                                         for: cal.date(byAdding: .month, value: -1,
                                                       to: first) ?? first)?.count ?? 30
        let weekdays = Weekday.columns(weekStart: weekStart)
        return (0 ..< rowCount * 7).map { i in
            let offset = i - firstColumn
            let day: Int
            if offset < 0            { day = previousDayCount + offset + 1 }
            else if offset < dayCount { day = offset + 1 }
            else                      { day = offset - dayCount + 1 }

            return DayCell(id: i,
                           day: day,
                           inMonth: offset >= 0 && offset < dayCount,
                           weekday: weekdays[i % 7],
                           date: cal.date(byAdding: .day, value: offset, to: first)!)
        }
    }
}

/// 干支 for the date's *sexagenary* year.
///
/// This flips on the lunisolar new year (17 Feb 2026), not 1 January — so in
/// January it still reads the previous year's pair. Foundation's Chinese calendar
/// handles the boundary, which is why there is no 60-year table here.
/// Do not "simplify" this to ((year - 4) % 60) off the Gregorian year.
enum Ganzhi {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .chinese)
        // Locale picks the script, not the value. Without a CJK locale this
        // renders "bing-wu" on an en_US system, which would break the hanko — it
        // stacks exactly two characters. Which CJK locale is arbitrary: ja_JP,
        // zh_TW, zh_CN, zh_Hant and zh_Hans give byte-identical output for all 60
        // years of the cycle, so there is nothing to gain by changing it.
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "U"
        return f
    }()

    static func string(for date: Date) -> String {
        formatter.string(from: date)
    }
}

/// How far through the calendar year a date sits.
struct YearProgress {
    let dayOfYear: Int
    let totalDays: Int

    /// Completed days over total, so 31 December reads 364/365 rather than
    /// hitting exactly 1.0 with a day still to run.
    var fraction: Double {
        totalDays > 0 ? Double(dayOfYear - 1) / Double(totalDays) : 0
    }

    /// Days not yet completed, today included — exactly the empty part of the
    /// bar, so the two always add up to the year. 31 December reads 1, not 0:
    /// by the same reasoning as `fraction`, that day is still to run.
    var daysLeft: Int { totalDays - dayOfYear + 1 }

    init(for date: Date) {
        let cal = MonthMeta.calendar
        let year = cal.component(.year, from: date)
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let next = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        self.dayOfYear = (cal.dateComponents([.day], from: start, to: date).day ?? 0) + 1
        self.totalDays = cal.dateComponents([.day], from: start, to: next).day ?? 365
    }
}

/// Progress through an assumed lifespan.
///
/// Deliberately coarse: only a birth year is collected, so the start is taken as
/// 1 January of that year and the figure is right to within a year.
struct LifeProgress {
    static let assumedSpan = 80
    static let earliestYear = 1900

    /// Whole years elapsed.
    let years: Int
    let fraction: Double

    init?(birthYear: Int, on date: Date) {
        let cal = MonthMeta.calendar
        let thisYear = cal.component(.year, from: date)
        guard birthYear >= Self.earliestYear, birthYear <= thisYear else { return nil }

        let elapsed = Double(thisYear - birthYear) + YearProgress(for: date).fraction
        years = max(0, Int(elapsed))
        fraction = min(1, max(0, elapsed / Double(Self.assumedSpan)))
    }
}
