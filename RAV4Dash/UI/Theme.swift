import SwiftUI

enum Theme {
    static let ground = Color(hex: 0x06080B)
    static let panel = Color(hex: 0x0D1117)
    static let panelRaised = Color(hex: 0x111823)
    static let line = Color(hex: 0x1A222D)
    static let lineStrong = Color(hex: 0x2A3644)
    static let dashed = Color(hex: 0x3A4757)
    static let text = Color(hex: 0xE8EEF5)
    static let textDim = Color(hex: 0xB7C2D0)
    static let label = Color(hex: 0x8B98A9)
    static let faint = Color(hex: 0x5E6B7B)
    static let accent = Color(hex: 0x34D8FF)
    static let onAccent = Color(hex: 0x031016)
    static let ev = Color(hex: 0x3BE08A)
    static let warn = Color(hex: 0xFFB547)
    static let danger = Color(hex: 0xFF5A47)
    static let dangerText = Color(hex: 0xFF8F82)
    static let dangerGround = Color(hex: 0x1A0D0C)

    static func tint(for metric: MetricID) -> Color {
        switch metric {
        case .evShare, .driveMode: return ev
        case .fuelRate, .manifoldPressure: return warn
        default: return accent
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Big readout numbers.
    static func gauge(_ size: CGFloat) -> Font {
        .system(size: max(size, 10), weight: .bold).width(.expanded).monospacedDigit()
    }

    /// Small uppercase labels.
    static func tech(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold).width(.condensed)
    }
}

extension Text {
    func techLabel(_ color: Color = Theme.label, size: CGFloat = 13) -> some View {
        self.font(.tech(size))
            .tracking(1.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Capsule button used in the top bar.
struct ChipButtonStyle: ButtonStyle {
    var filled = false
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tech(15))
            .tracking(1.4)
            .foregroundStyle(filled ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(filled ? color : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(filled ? Color.clear : Theme.line, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
