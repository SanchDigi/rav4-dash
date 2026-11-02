import SwiftUI
import UIKit

/// Draws the small gauge pictures CarPlay shows on grid buttons and list rows.
@MainActor
enum CarPlayImages {
    static func gauge(metric: MetricID, value: Double?, alerting: Bool) -> UIImage {
        render(MiniGauge(metric: metric, value: value, alerting: alerting, showNumber: true)
            .frame(width: 120, height: 120))
    }

    static func listIcon(metric: MetricID, value: Double?) -> UIImage {
        render(MiniGauge(metric: metric, value: value, alerting: false, showNumber: false)
            .frame(width: 44, height: 44))
    }

    private static func render<V: View>(_ view: V) -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

struct MiniGauge: View {
    let metric: MetricID
    let value: Double?
    let alerting: Bool
    let showNumber: Bool

    var body: some View {
        let info = metric.info
        let color = alerting ? Theme.danger : Theme.tint(for: metric)
        ZStack {
            RoundedRectangle(cornerRadius: showNumber ? 22 : 10)
                .fill(Theme.panel)
            RoundedRectangle(cornerRadius: showNumber ? 22 : 10)
                .strokeBorder(alerting ? Theme.danger : Theme.line, lineWidth: 1)

            if metric == .driveMode {
                Image(systemName: (value ?? 1) >= 0.5 ? "bolt.fill" : "engine.combustion.fill")
                    .font(.system(size: showNumber ? 34 : 18, weight: .semibold))
                    .foregroundStyle(value == nil ? Theme.faint : ((value ?? 1) >= 0.5 ? Theme.ev : Theme.warn))
                    .offset(y: showNumber ? -10 : 0)
            } else {
                RingGauge(fraction: value.map { info.fraction($0) } ?? 0,
                          color: color,
                          lineWidth: showNumber ? 9 : 5)
                    .padding(showNumber ? 10 : 6)
            }

            if showNumber {
                VStack(spacing: 1) {
                    if metric != .driveMode {
                        Text(info.format(value))
                            .font(.gauge(24))
                            .foregroundStyle(alerting ? Theme.dangerText : Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 22)
                    }
                    Text(metric == .driveMode ? info.format(value) : info.unit)
                        .font(.system(size: metric == .driveMode ? 16 : 12, weight: .semibold))
                        .foregroundStyle(Theme.label)
                }
                .offset(y: metric == .driveMode ? 22 : 0)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
