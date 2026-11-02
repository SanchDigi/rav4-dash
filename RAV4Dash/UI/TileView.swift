import SwiftUI

/// One dashboard tile. Pure display: everything it shows is passed in.
struct TileView: View {
    let tile: Tile
    let value: Double?
    let history: [Double]
    var alerting = false
    var supported = true
    var caption: String?

    var body: some View {
        let info = tile.metric.info
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let big = max(min(h * 0.30, w * 0.24), 14)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(info.label).techLabel(alerting ? Theme.dangerText : Theme.label)
                    Spacer(minLength: 4)
                    if alerting {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dangerText)
                    }
                    Text(info.unit.uppercased()).techLabel(alerting ? Theme.dangerText : Theme.label)
                }
                content(info: info, w: w, h: h, big: big)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(alerting ? Theme.dangerGround : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(alerting ? Theme.danger : Theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.name) \(supported ? info.format(value) : "not available") \(info.unit)")
    }

    private var valueText: String {
        supported ? tile.metric.info.format(value) : "N/A"
    }

    private var valueColor: Color {
        if alerting { return Theme.dangerText }
        if !supported || value == nil { return Theme.faint }
        return Theme.text
    }

    private func number(_ size: CGFloat) -> some View {
        Text(valueText)
            .font(.gauge(size))
            .foregroundStyle(valueColor)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }

    private var captionView: some View {
        Text(supported ? (caption ?? " ") : "Not reported by this car")
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func content(info: MetricInfo, w: CGFloat, h: CGFloat, big: CGFloat) -> some View {
        let color = alerting ? Theme.danger : Theme.tint(for: tile.metric)
        let fraction = value.map { info.fraction($0) } ?? 0
        let lineWidth = max(6, min(w, h) * 0.05)

        if tile.metric == .driveMode {
            DriveModeBadge(isEV: (value ?? 1) >= 0.5, hasValue: value != nil && supported, size: big * 1.2)
        } else {
            switch tile.style {
            case .ring:
                ZStack {
                    RingGauge(fraction: fraction, color: color, lineWidth: lineWidth,
                              showTicks: tile.size == .large,
                              zone: tile.metric == .hybridBattery ? 0...0.125 : nil)
                    VStack(spacing: 4) {
                        number(big * (tile.size == .large ? 1.0 : 0.75))
                        if tile.size == .large {
                            Text(info.label).techLabel(size: 12)
                        }
                    }
                    .padding(.horizontal, lineWidth * 2.5)
                    if tile.size == .large {
                        VStack {
                            Spacer()
                            captionView
                        }
                    }
                }

            case .arc:
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        ArcGauge(fraction: fraction, color: color, lineWidth: lineWidth)
                        number(big * 0.8)
                    }
                    captionView
                }

            case .bar:
                VStack(alignment: .leading, spacing: 8) {
                    Spacer(minLength: 0)
                    number(big)
                    Spacer(minLength: 0)
                    SegmentBar(fraction: fraction, color: color, count: tile.size == .small ? 16 : 28,
                               height: max(10, h * 0.07))
                    captionView
                }

            case .digital:
                VStack(alignment: .leading, spacing: 4) {
                    Spacer(minLength: 0)
                    number(big * 1.1)
                    Spacer(minLength: 0)
                    captionView
                }

            case .graph:
                VStack(alignment: .leading, spacing: 6) {
                    number(big * 0.85)
                    Sparkline(values: history, color: color)
                }
            }
        }
    }
}
