import Foundation

/// One cell of a 7-wide month grid, including the greyed neighbours that fill
/// out the first and last weeks.
struct DayCell: Identifiable {
    let id: Int
    let day: Int
    let inMonth: Bool
    let column: Int
    let date: Date
}

/// Everything the grid and the ribbon need to know about a month.
struct MonthMeta {
    let year: Int
    let month: Int
    /// Column of the 1st, 0 = Sunday.
    let firstWeekday: Int
    let dayCount: Int
    let rowCount: Int
    /// Column of the last day of the month.
    let lastColumn: Int

    /// Sunday-first, to match the designed S M T W T F S header.
    /// TODO: make the first day of week a setting.
    /// `timeZone` is explicitly autoupdating. A plain `Calendar(identifier:)`
    /// snapshots `TimeZone.current` at first access and keeps it forever, which
    /// made the grid resolve "today" in the old zone after travel while the menu
    /// bar (which uses `.autoupdatingCurrent`) had already moved on.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
        let cal = Self.calendar
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        self.firstWeekday = cal.component(.weekday, from: first) - 1
        self.dayCount = cal.range(of: .day, in: .month, for: first)!.count
        self.rowCount = Int((Double(firstWeekday + dayCount) / 7.0).rounded(.up))
        self.lastColumn = (firstWeekday + dayCount - 1) % 7
    }

    init(containing date: Date) {
        let c = Self.calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 2026, month: c.month ?? 1)
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
        return (0 ..< rowCount * 7).map { i in
            let offset = i - firstWeekday
            let day: Int
            if offset < 0            { day = previousDayCount + offset + 1 }
            else if offset < dayCount { day = offset + 1 }
            else                      { day = offset - dayCount + 1 }

            return DayCell(id: i,
                           day: day,
                           inMonth: offset >= 0 && offset < dayCount,
                           column: i % 7,
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
    /// hitting exactly 1.0 with a day still to run. `dayOfYear` stays 1-based
    /// because the label counts the day you are in.
    var fraction: Double {
        totalDays > 0 ? Double(dayOfYear - 1) / Double(totalDays) : 0
    }

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
