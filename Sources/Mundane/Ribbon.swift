import SwiftUI

/// The stepped outline that wraps day 1 through the last day of the month.
///
/// Because months start and end mid-week the region is an 8-cornered ribbon, two
/// of whose corners are concave. Rather than case-analysing the shapes (Itsycal
/// branches three ways), build the 8 points, throw away any that coincide or lie
/// on a straight line, and round whatever is left with a quadratic through the
/// vertex. That collapses correctly on its own when a month starts on a Sunday or
/// ends on a Saturday.
enum Ribbon {
    static func path(meta: MonthMeta,
                     cell: CGSize,
                     radius: CGFloat,
                     inset: CGFloat = 0.8) -> Path {
        let w = 7 * cell.width
        let rows = CGFloat(meta.rowCount)
        let s = CGFloat(meta.firstWeekday)
        let e = CGFloat(meta.lastColumn)

        let points = [
            CGPoint(x: s * cell.width,       y: 0),
            CGPoint(x: w,                    y: 0),
            CGPoint(x: w,                    y: (rows - 1) * cell.height),
            CGPoint(x: (e + 1) * cell.width, y: (rows - 1) * cell.height),
            CGPoint(x: (e + 1) * cell.width, y: rows * cell.height),
            CGPoint(x: 0,                    y: rows * cell.height),
            CGPoint(x: 0,                    y: cell.height),
            CGPoint(x: s * cell.width,       y: cell.height),
        ].map {
            // Keep the stroke inside the drawing bounds on all four sides. The
            // bottom was previously unclamped, so half the stroke width drew
            // outside the frame and bled into whatever sat below.
            CGPoint(x: min(max($0.x, inset), w - inset),
                    y: min(max($0.y, inset), rows * cell.height - inset))
        }

        return rounded(points, radius: radius)
    }

    static func rounded(_ raw: [CGPoint], radius: CGFloat) -> Path {
        let points = dropCollinear(dedupe(raw))
        guard points.count >= 3 else { return Path() }

        var path = Path()
        for i in points.indices {
            let c = points[i]
            let a = points[(i - 1 + points.count) % points.count]
            let b = points[(i + 1) % points.count]

            let v1 = CGPoint(x: a.x - c.x, y: a.y - c.y)
            let v2 = CGPoint(x: b.x - c.x, y: b.y - c.y)
            let l1 = hypot(v1.x, v1.y)
            let l2 = hypot(v2.x, v2.y)
            guard l1 > 0, l2 > 0 else { continue }

            let r = min(radius, l1 / 2, l2 / 2)
            let start = CGPoint(x: c.x + v1.x / l1 * r, y: c.y + v1.y / l1 * r)
            let end   = CGPoint(x: c.x + v2.x / l2 * r, y: c.y + v2.y / l2 * r)

            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: c)
        }
        path.closeSubpath()
        return path
    }

    private static func dedupe(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in pts {
            if let last = out.last, close(last, p) { continue }
            out.append(p)
        }
        if out.count > 1, close(out[0], out[out.count - 1]) { out.removeLast() }
        return out
    }

    private static func dropCollinear(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        return pts.indices.compactMap { i -> CGPoint? in
            let a = pts[(i - 1 + pts.count) % pts.count]
            let c = pts[i]
            let b = pts[(i + 1) % pts.count]
            let cross = (c.x - a.x) * (b.y - c.y) - (c.y - a.y) * (b.x - c.x)
            return abs(cross) > 0.01 ? c : nil
        }
    }

    private static func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01
    }
}
