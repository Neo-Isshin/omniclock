import SwiftUI
import AppKit

enum NormalQuotaRingPalette {
    static func concentricColor(layer: Int, contrast: Color) -> Color {
        let ink = NSColor(contrast).usingColorSpace(.sRGB) ?? .black
        let lightInk = 0.2126 * ink.redComponent + 0.7152 * ink.greenComponent + 0.0722 * ink.blueComponent > 0.55
        if layer == 1 {
            return lightInk ? Color(red: 0.35, green: 0.82, blue: 0.78) : Color(red: 0, green: 0.36, blue: 0.43)
        }
        return lightInk ? Color(red: 0.98, green: 0.74, blue: 0.35) : Color(red: 0.57, green: 0.28, blue: 0.06)
    }
}

/// Normal keeps its static theme palette, with the same three-pool spacing as Glass.
struct NormalQuotaRingGeometry {
    let size: CGFloat
    let lineWidth: CGFloat
    let hasThirdRing: Bool
    var scale: CGFloat { size / 30 }
    var outerRadius: CGFloat { (size - lineWidth) / 2 }
    var innerInset: CGFloat { hasThirdRing ? size / 2 - outerRadius * 0.76 : 5.25 * scale }
    var thirdInset: CGFloat { size / 2 - outerRadius * 0.55 }
    var innerLineWidth: CGFloat { 1.7 * scale }
    var thirdLineWidth: CGFloat { 1.2 * scale }
}

struct NormalQuotaRingView: View {
    let indicator: DialQuotaIndicator
    let theme: ClockFaceTheme
    let primary: Color
    let secondary: Color
    let size: CGFloat
    let lineWidth: CGFloat
    let fontSize: CGFloat

    var body: some View {
        let outer = min(100, max(0, indicator.outerRemainingPercent))
        let geometry = NormalQuotaRingGeometry(size: size, lineWidth: lineWidth,
            hasThirdRing: indicator.thirdRemainingPercent != nil)
        let accent = theme.dialQuotaColor(for: indicator.provider, contrastColor: primary)
        let center = QuotaCenterLabel(remaining: indicator.outerRemainingPercent)
        ZStack {
            Circle().fill(surfaceColor)
                .shadow(color: Color.black.opacity(theme == .glass ? 0.02 : 0.14),
                    radius: 1.6 * geometry.scale, y: 0.8 * geometry.scale)
            Circle().strokeBorder(theme == .glass ? primary.opacity(0.12) : secondary.opacity(0.16), lineWidth: lineWidth)
            Circle().trim(from: 0, to: outer / 100)
                .stroke(accent.opacity(0.82), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(lineWidth / 2)
            if let value = indicator.innerRemainingPercent {
                Circle().inset(by: geometry.innerInset)
                    .stroke(secondary.opacity(0.10), lineWidth: geometry.innerLineWidth)
                Circle().inset(by: geometry.innerInset).trim(from: 0, to: min(100, max(0, value)) / 100)
                    .stroke(indicator.thirdRemainingPercent == nil ? accent.opacity(0.52) : NormalQuotaRingPalette.concentricColor(layer: 1, contrast: primary).opacity(0.9),
                        style: StrokeStyle(lineWidth: geometry.innerLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let value = indicator.thirdRemainingPercent {
                Circle().inset(by: geometry.thirdInset)
                    .stroke(NormalQuotaRingPalette.concentricColor(layer: 2, contrast: primary).opacity(0.14), lineWidth: geometry.thirdLineWidth)
                Circle().inset(by: geometry.thirdInset).trim(from: 0, to: min(100, max(0, value)) / 100)
                    .stroke(NormalQuotaRingPalette.concentricColor(layer: 2, contrast: primary).opacity(0.9), style: StrokeStyle(lineWidth: geometry.thirdLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(center.text).font(.system(size: fontSize, weight: .bold, design: .rounded))
                if center.showsPercent {
                    Text("%").font(.system(size: fontSize * 0.7, weight: .regular, design: .rounded))
                }
            }
            .foregroundColor(outer <= 15 ? .red : outer <= 35 ? .orange : primary)
            .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(width: size, height: size)
    }

    private var surfaceColor: Color {
        switch theme {
        case .glass: return primary.opacity(0.025)
        case .midnight, .luxe: return Color.black.opacity(0.12)
        case .sky: return Color.white.opacity(0.16)
        case .custom: return primary.opacity(0.035)
        default: return Color.white.opacity(0.32)
        }
    }
}
