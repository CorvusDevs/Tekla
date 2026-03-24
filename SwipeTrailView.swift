import SwiftUI

/// Draws a fading, tapering trail following the cursor during swipe-to-type.
/// Uses Catmull-Rom spline smoothing and per-segment rendering with
/// smoothly varying opacity and width — no band boundaries or round-cap dots.
struct SwipeTrailView: View {
    let swipePath: [CGPoint]
    let isSwiping: Bool
    var maxTrailPoints: Int = 20

    private let dotDiameter: CGFloat = 10

    private var trailPoints: [CGPoint] {
        if swipePath.count <= maxTrailPoints {
            return swipePath
        }
        return Array(swipePath.suffix(maxTrailPoints))
    }

    var body: some View {
        Canvas { context, size in
            let points = trailPoints
            guard points.count >= 2, isSwiping else { return }

            // Smooth into a Catmull-Rom spline
            let smooth = catmullRomSpline(points: points, segmentsPerCurve: 4)
            guard smooth.count >= 2 else { return }

            let total = smooth.count - 1

            // Draw each segment with its own opacity and width.
            // Using .butt caps avoids the round dots at endpoints.
            // The spline generates dense points so segments overlap naturally.
            for i in 0..<total {
                // progress: 0 at tail → 1 at head
                let progress = Double(i) / Double(total)

                // Opacity: cubic ease-in for a gradual fade
                let opacity = progress * progress * progress * 0.5

                // Width: thin at tail, full dot diameter near head
                let width = 1.5 + progress * (dotDiameter - 1.5)

                var seg = Path()
                seg.move(to: smooth[i])
                seg.addLine(to: smooth[i + 1])

                context.stroke(
                    seg,
                    with: .color(.accentColor.opacity(opacity)),
                    style: StrokeStyle(lineWidth: width, lineCap: .butt)
                )
            }

            // Final segment with round cap to smoothly meet the dot
            if total >= 1 {
                var lastSeg = Path()
                lastSeg.move(to: smooth[total - 1])
                lastSeg.addLine(to: smooth[total])
                context.stroke(
                    lastSeg,
                    with: .color(.accentColor.opacity(0.5)),
                    style: StrokeStyle(lineWidth: dotDiameter, lineCap: .round)
                )
            }

            // Bright dot at the cursor
            if let head = smooth.last {
                let r = dotDiameter / 2
                context.fill(
                    Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r,
                                           width: dotDiameter, height: dotDiameter)),
                    with: .color(.accentColor.opacity(0.85))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Catmull-Rom Spline

    private func catmullRomSpline(points: [CGPoint], segmentsPerCurve: Int) -> [CGPoint] {
        guard points.count >= 2 else { return points }

        var padded = points
        let first = points[0], second = points[1]
        padded.insert(CGPoint(x: 2 * first.x - second.x,
                              y: 2 * first.y - second.y), at: 0)

        let last = points[points.count - 1]
        let secondLast = points[points.count - 2]
        padded.append(CGPoint(x: 2 * last.x - secondLast.x,
                              y: 2 * last.y - secondLast.y))

        var result: [CGPoint] = []

        for i in 1..<(padded.count - 2) {
            let p0 = padded[i - 1], p1 = padded[i]
            let p2 = padded[i + 1], p3 = padded[i + 2]

            for step in 0..<segmentsPerCurve {
                let t = CGFloat(step) / CGFloat(segmentsPerCurve)
                let t2 = t * t, t3 = t2 * t

                let x = 0.5 * ((2 * p1.x) +
                    (-p0.x + p2.x) * t +
                    (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                    (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)

                let y = 0.5 * ((2 * p1.y) +
                    (-p0.y + p2.y) * t +
                    (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                    (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

                result.append(CGPoint(x: x, y: y))
            }
        }

        if let last = points.last { result.append(last) }
        return result
    }
}
