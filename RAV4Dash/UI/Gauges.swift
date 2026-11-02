import SwiftUI

/// 270° ring that fills clockwise from the lower left.
struct RingGauge: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat
    var showTicks = false
    /// Optional zone (0...1) tinted in a warning color, like a low-battery band.
    var zone: ClosedRange<Double>?
    var zoneColor: Color = Theme.warn

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let ring = size - lineWidth * (showTicks ? 3.2 : 1.2)
            ZStack {
                Group {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: lineWidth))
                    if let zone {
                        Circle()
                            .trim(from: 0.75 * zone.lowerBound, to: 0.75 * zone.upperBound)
                            .stroke(zoneColor.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth))
                    }
                    Circle()
                        .trim(from: 0, to: 0.75 * min(max(fraction, 0), 1))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth))
                        .animation(.easeOut(duration: 0.4), value: fraction)
                }
                .rotationEffect(.degrees(135))
                .frame(width: ring, height: ring)

                if showTicks {
                    ForEach(0..<9, id: \.self) { i in
                        Capsule()
                            .fill(Theme.faint)
                            .frame(width: 1.5, height: lineWidth * 0.7)
                            .offset(y: -(ring / 2 + lineWidth * 1.1))
                            .rotationEffect(.degrees(-135 + Double(i) * 33.75))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 180° arc across the top.
struct ArcGauge: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let d = max(min(geo.size.width, geo.size.height * 2) - lineWidth, 10)
            ZStack {
                Circle()
                    .trim(from: 0.5, to: 1)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: lineWidth))
                Circle()
                    .trim(from: 0.5, to: 0.5 + 0.5 * min(max(fraction, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
            .frame(width: d, height: d)
            .position(x: geo.size.width / 2, y: geo.size.height - lineWidth / 2)
        }
    }
}

/// Row of segments that light up left to right.
struct SegmentBar: View {
    var fraction: Double
    var color: Color
    var count = 20
    var height: CGFloat = 14

    var body: some View {
        let lit = Int((min(max(fraction, 0), 1) * Double(count)).rounded())
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < lit ? color : Theme.line)
            }
        }
        .frame(height: height)
    }
}

/// Line graph of recent values.
struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            ZStack {
                Path { p in
                    let y = geo.size.height - 1
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                if values.count > 1 {
                    Path { p in
                        for (i, v) in values.enumerated() {
                            let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                            let y = geo.size.height * (1 - CGFloat((v - lo) / span)) * 0.85 + geo.size.height * 0.075
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
    }
}

/// "EV" or "ENGINE" readout for the drive mode tile.
struct DriveModeBadge: View {
    var isEV: Bool
    var hasValue: Bool
    var size: CGFloat

    var body: some View {
        let color = !hasValue ? Theme.faint : (isEV ? Theme.ev : Theme.warn)
        VStack(spacing: size * 0.15) {
            Image(systemName: isEV ? "bolt.fill" : "engine.combustion.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
            Text(hasValue ? (isEV ? "EV" : "ENGINE") : "--")
                .font(.gauge(size * (isEV ? 0.9 : 0.6)))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(color)
    }
}
