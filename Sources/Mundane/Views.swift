import SwiftUI

// MARK: - Grid

struct DayCellView: View {
    let cell: DayCell
    let metrics: GridMetrics
    let isToday: Bool

    var body: some View {
        Text("\(cell.day)")
            .font(Typeface.maru(metrics.fontSize))
            .foregroundStyle(tint)
            .frame(width: metrics.markSize, height: metrics.markSize)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: metrics.markRadius, style: .continuous)
                        .fill(Palette.shu)
                }
            }
            .frame(width: metrics.cell.width, height: metrics.cell.height)
    }

    private var tint: Color {
        if isToday { return Palette.paper }
        if !cell.inMonth { return Palette.soft.opacity(0.5) }
        switch cell.column {
        case 0: return Palette.sunday
        case 6: return Palette.saturday
        default: return Palette.ink
        }
    }
}

struct WeekdayHeader: View {
    let metrics: GridMetrics
    private let letters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { i, letter in
                Text(letter)
                    .font(Typeface.maru(metrics.fontSize - 2))
                    .foregroundStyle(i == 0 ? Palette.sunday : (i == 6 ? Palette.saturday : Palette.soft))
                    .frame(width: metrics.cell.width)
            }
        }
    }
}

struct MonthGrid: View {
    let meta: MonthMeta
    let metrics: GridMetrics
    let showsRibbon: Bool
    let today: Date

    var body: some View {
        let cells = meta.cells
        // Resolved once per grid. Calling Calendar.isDate per cell meant 427 ICU
        // round trips for a year render, the single largest cost in it.
        let now = MonthMeta.calendar.dateComponents([.year, .month, .day], from: today)
        ZStack(alignment: .topLeading) {
            // Shading the weekends rather than the weekdays: two bands instead of
            // five, and it reinforces the red and blue instead of inverting which
            // days are the exception. Behind the cells so the ribbon still reads.
            HStack(spacing: 0) {
                ForEach(0 ..< 7, id: \.self) { column in
                    Rectangle()
                        .fill(column == 0 || column == 6 ? Palette.band : Color.clear)
                        .frame(width: metrics.cell.width)
                }
            }
            VStack(spacing: 0) {
                ForEach(0 ..< meta.rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(cells[row * 7 ..< row * 7 + 7]) { cell in
                            DayCellView(cell: cell,
                                        metrics: metrics,
                                        isToday: cell.inMonth
                                            && meta.year == now.year
                                            && meta.month == now.month
                                            && cell.day == now.day)
                        }
                    }
                }
            }
            if showsRibbon {
                Ribbon.path(meta: meta, cell: metrics.cell, radius: metrics.cornerRadius)
                    .stroke(Palette.ribbon, lineWidth: metrics.ribbonWidth)
            }
        }
        .frame(width: metrics.width,
               height: metrics.cell.height * CGFloat(meta.rowCount))
    }

}

// MARK: - Chrome

struct NavHeader<Title: View>: View {
    let state: ViewState
    let z: Sizing
    let onPrev: () -> Void
    let onNext: () -> Void
    @ViewBuilder let title: Title

    var body: some View {
        HStack(spacing: 0) {
            Arrow(id: "prev", glyph: "◀", state: state, z: z, action: onPrev)
            Spacer(minLength: z.arrowHPad)
            HStack(spacing: z.titleGap) {
                title
                if !state.isShowingToday { TodayChip(state: state, z: z) }
            }
            Spacer(minLength: z.arrowHPad)
            Arrow(id: "next", glyph: "▶", state: state, z: z, action: onNext)
        }
        .padding(.bottom, z.headerBottom)
    }

    /// Only appears once you have paged away, so it doubles as the signal that
    /// you are not looking at the current period.
    private struct TodayChip: View {
        let state: ViewState
        let z: Sizing

        var body: some View {
            let hovering = state.hovered == "today"
            Text("→ today")
                .font(Typeface.maru(z.chipLabel))
                .foregroundStyle(Palette.shu)
                .padding(.horizontal, z.chipHPad).padding(.vertical, z.chipVPad)
                .background {
                    RoundedRectangle(cornerRadius: z.chipRadius, style: .continuous)
                        .fill(hovering ? Palette.shu.opacity(0.12) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: z.chipRadius, style: .continuous)
                            .strokeBorder(Palette.shu.opacity(hovering ? 0.9 : 0.55), lineWidth: 1))
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { state.hovered = "today" }
                    else if state.hovered == "today" { state.hovered = nil }
                }
                .onTapGesture { state.goToToday() }
        }
    }

    private struct Arrow: View {
        let id: String
        let glyph: String
        let state: ViewState
        let z: Sizing
        let action: () -> Void

        var body: some View {
            let hovering = state.hovered == id
            Text(glyph)
                .font(.system(size: z.arrowGlyph))
                .foregroundStyle(hovering ? Palette.ink : Palette.soft)
                .padding(.horizontal, z.arrowHPad).padding(.vertical, z.arrowVPad)
                .background {
                    if hovering {
                        RoundedRectangle(cornerRadius: z.arrowRadius, style: .continuous)
                            .fill(Palette.tint)
                    }
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { state.hovered = id }
                    else if state.hovered == id { state.hovered = nil }
                }
                .onTapGesture(perform: action)
        }
    }
}

struct ProgressStrip: View {
    let fraction: Double
    let label: String
    let z: Sizing
    var topPadding: CGFloat

    var body: some View {
        HStack(spacing: z.stripGap) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.tint)
                    Capsule().fill(Palette.shu)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: z.stripHeight)
            Text(label)
                .font(Typeface.maru(z.stripLabel))
                .foregroundStyle(Palette.soft)
                .fixedSize()
        }
        .padding(.top, topPadding)
    }
}

struct ViewSwitcher: View {
    @Bindable var state: ViewState
    let z: Sizing

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                let on = state.mode == mode
                Text(mode.label)
                    .font(Typeface.maru(z.switcherLabel))
                    .foregroundStyle(on ? Palette.ink : Palette.soft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, z.switcherVPad)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: z.switcherRadius, style: .continuous)
                                .fill(Palette.paper)
                                .overlay(RoundedRectangle(cornerRadius: z.switcherRadius,
                                                          style: .continuous)
                                    .strokeBorder(Palette.edge, lineWidth: 0.5))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { state.mode = mode }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: z.switcherOuter, style: .continuous)
            .fill(Palette.tint))
        .frame(maxWidth: z.switcherMaxWidth)
        .padding(.top, z.switcherTop)
    }
}

/// The shortcuts, spelled out under the view they apply to.
///
/// Held to one line and allowed to shrink rather than grow: at Small the card is
/// only ~180pt of content wide, and a hint wider than the grid would drag the
/// whole panel out with it.
struct KeyboardHint: View {
    let unit: String
    let z: Sizing

    var body: some View {
        Text("←→: \(unit)   space: today   tab: view   esc: close")
            .font(Typeface.maru(z.hintLabel))
            .foregroundStyle(Palette.soft)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.top, z.hintTop)
    }
}

struct Hanko: View {
    let text: String
    let z: Sizing

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(Typeface.maru(z.hankoGlyph))
                    .foregroundStyle(Palette.shu)
            }
        }
        .frame(width: z.hankoSize, height: z.hankoSize)
        .background(RoundedRectangle(cornerRadius: z.hankoRadius, style: .continuous)
            .fill(Palette.paper))
        .overlay(RoundedRectangle(cornerRadius: z.hankoRadius, style: .continuous)
            .strokeBorder(Palette.shu, lineWidth: z.hankoStroke))
    }
}

// MARK: - Views

/// Pinned to the grid's calendar. A bare DateFormatter inherits the locale's
/// calendar, so a Mac set to a non-Gregorian calendar rendered those month names
/// over Gregorian grids.
private let monthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = MonthMeta.calendar
    return f
}()
private let monthNames = monthFormatter.monthSymbols ?? []
private let shortMonths = monthFormatter.shortMonthSymbols ?? []

struct MonthView: View {
    let state: ViewState
    let z: Sizing

    var body: some View {
        let meta = MonthMeta(containing: state.anchor)
        VStack(spacing: 0) {
            NavHeader(state: state, z: z,
                      onPrev: { state.page(-1) }, onNext: { state.page(1) }) {
                HStack(spacing: 4) {
                    Text(monthNames[meta.month - 1]).foregroundStyle(Palette.ink)
                    Text(String(meta.year)).foregroundStyle(Palette.soft)
                }
                .font(Typeface.maru(z.title))
            }
            WeekdayHeader(metrics: z.monthGrid)
            MonthGrid(meta: meta, metrics: z.monthGrid, showsRibbon: true, today: state.today)
        }
        .frame(width: z.monthGrid.width)
    }
}

struct ThreeMonthView: View {
    let state: ViewState
    let z: Sizing

    var body: some View {
        let cal = MonthMeta.calendar
        let months = (-1 ... 1).map {
            MonthMeta(containing: cal.date(byAdding: .month, value: $0, to: state.anchor)!)
        }
        VStack(spacing: 0) {
            NavHeader(state: state, z: z,
                      onPrev: { state.page(-1) }, onNext: { state.page(1) }) {
                HStack(spacing: 4) {
                    if months[0].year == months[2].year {
                        Text("\(shortMonths[months[0].month - 1]) – \(shortMonths[months[2].month - 1])")
                            .foregroundStyle(Palette.ink)
                        Text(String(months[0].year)).foregroundStyle(Palette.soft)
                    } else {
                        // Straddling a year boundary. Printing only the middle
                        // month's year rendered "Nov – Jan 2026" for a January
                        // that is actually 2027.
                        Text("\(shortMonths[months[0].month - 1]) \(String(months[0].year))")
                            .foregroundStyle(Palette.ink)
                        Text("–").foregroundStyle(Palette.soft)
                        Text("\(shortMonths[months[2].month - 1]) \(String(months[2].year))")
                            .foregroundStyle(Palette.ink)
                    }
                }
                .font(Typeface.maru(z.title))
            }
            HStack(alignment: .top, spacing: z.trioSpacing) {
                ForEach(Array(months.enumerated()), id: \.offset) { i, meta in
                    let current = i == 1
                    VStack(spacing: 4) {
                        Text(shortMonths[meta.month - 1])
                            .font(Typeface.maru(z.monthLabel))
                            .foregroundStyle(current ? Palette.ink : Palette.soft)
                        WeekdayHeader(metrics: z.threeGrid)
                        MonthGrid(meta: meta, metrics: z.threeGrid,
                                  showsRibbon: current, today: state.today)
                    }
                    .opacity(current ? 1 : 0.62)
                }
            }
        }
    }
}

struct YearView: View {
    let state: ViewState
    let z: Sizing

    var body: some View {
        let year = MonthMeta.calendar.component(.year, from: state.anchor)
        let currentMonth = MonthMeta(containing: state.today)
        VStack(spacing: 0) {
            NavHeader(state: state, z: z,
                      onPrev: { state.page(-1) }, onNext: { state.page(1) }) {
                Text(String(year))
                    .font(Typeface.maru(z.yearTitle))
                    .foregroundStyle(Palette.ink)
            }
            // .top, not the default .center: months differ in row count (Feb 2026
            // is exactly four weeks), and centring drops the short ones so the
            // month labels no longer line up across a row.
            Grid(alignment: .top,
                 horizontalSpacing: z.yearColSpacing, verticalSpacing: z.yearRowSpacing) {
                ForEach(0 ..< 4, id: \.self) { row in
                    GridRow {
                        ForEach(0 ..< 3, id: \.self) { col in
                            let month = row * 3 + col + 1
                            let meta = MonthMeta(year: year, month: month)
                            let isCurrent = year == currentMonth.year && month == currentMonth.month
                            VStack(spacing: 2) {
                                Text(shortMonths[month - 1])
                                    .font(Typeface.maru(z.yearMonthLabel))
                                    .foregroundStyle(isCurrent ? Palette.shu : Palette.soft)
                                MonthGrid(meta: meta, metrics: z.yearGrid,
                                          showsRibbon: isCurrent, today: state.today)
                            }
                            .padding(.horizontal, z.yearCellPadH)
                            .padding(.vertical, z.yearCellPadV)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Root

struct PanelContent: View {
    @Bindable var state: ViewState

    var body: some View {
        let z = Sizing(state.settings.size)
        card(z)
            // Overlay rather than a ZStack sibling: overlays don't contribute to
            // the measured size, so the seal can hang off the edge without
            // feeding back into the panel's content size.
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    Hanko(text: Ganzhi.string(for: state.today), z: z)
                        .offset(x: geo.size.width - z.hankoSize + z.hankoOverhang,
                                y: geo.size.height / 8 - z.hankoSize / 2)
                }
            }
            .padding(Layout.stampMargin)
            .fixedSize()
    }

    /// Width of the widest row above the strips, so the hint can be pinned to it.
    private func contentWidth(_ z: Sizing) -> CGFloat {
        switch state.mode {
        case .month:       z.monthGrid.width
        case .threeMonths: 3 * z.threeGrid.width + 2 * z.trioSpacing
        case .year:        3 * (z.yearGrid.width + 2 * z.yearCellPadH) + 2 * z.yearColSpacing
        }
    }

    private func card(_ z: Sizing) -> some View {
        VStack(spacing: 0) {
            switch state.mode {
            case .month:       MonthView(state: state, z: z)
            case .threeMonths: ThreeMonthView(state: state, z: z)
            case .year:        YearView(state: state, z: z)
            }

            let year = YearProgress(for: state.today)
            ProgressStrip(fraction: year.fraction, label: "\(year.dayOfYear)日",
                          z: z, topPadding: z.stripTop)

            if let birthYear = state.settings.birthYear,
               let life = LifeProgress(birthYear: birthYear, on: state.today) {
                ProgressStrip(fraction: life.fraction, label: "\(life.years)年",
                              z: z, topPadding: z.lifeStripTop)
            }

            ViewSwitcher(state: state, z: z)
            // Given an explicit width the hint's minimumScaleFactor finally has
            // something to scale against. Under the root .fixedSize() alone the
            // proposal is nil, so Text reported its full ideal width and could
            // drag the card wider than the grid — the opposite of the intent.
            KeyboardHint(unit: state.mode == .year ? "year" : "month", z: z)
                .frame(width: contentWidth(z))
        }
        .padding(.horizontal, z.cardPadH)
        .padding(.top, z.cardPadTop)
        .padding(.bottom, z.cardPadBottom)
        .background {
            RoundedRectangle(cornerRadius: z.cardRadius, style: .continuous)
                .fill(Palette.paper)
                .overlay(RoundedRectangle(cornerRadius: z.cardRadius, style: .continuous)
                    .strokeBorder(Palette.edge, lineWidth: 0.5))
        }
    }
}
