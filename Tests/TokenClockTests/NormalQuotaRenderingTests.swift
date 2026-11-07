#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import TokenClock

@MainActor final class NormalQuotaRenderingTests: XCTestCase {
    func testRenderedRingBoundsAndNativeHoverHitsMatchAcrossSizesAndCounts() throws {
        for size in ClockSize.allCases {
            for count in [1, 2] {
                let layout = ClockQuotaLayout(diameter: size.diameter, count: count, scale: size.scale)
                let regions = (0..<count).map { ClockTooltipRegion(rect: layout.appKitHitFrame(at: $0), text: "Pool \($0)") }
                var lastHover: String?
                let view = ClockInteractionNSView(onClick: {}, onTooltipHover: { lastHover = $0 }, tooltipRegions: regions)
                view.frame = NSRect(x: 0, y: 0, width: size.diameter, height: size.diameter)
                for index in 0..<count {
                    let render = layout.frame(at: index)
                    let native = layout.appKitHitFrame(at: index)
                    XCTAssertEqual(native.midY, size.diameter - render.midY, accuracy: 0.001)
                    // This newly enlarged left edge was outside the obsolete 35/29 pt hover regions.
                    let point = NSPoint(x: native.minX + size.scale, y: native.midY)
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                        timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
                    view.mouseMoved(with: event)
                    XCTAssertEqual(lastHover, "Pool \(index)")
                    XCTAssertGreaterThanOrEqual(native.width, render.width)
                }
                if count == 2 { XCTAssertFalse(regions[0].rect.intersects(regions[1].rect)) }
            }
        }
    }

    func testThreeRingsLeaveSeparateTracksAndMoreReadableCenterSpace() {
        for size in ClockSize.allCases {
            for count in [1, 2] {
                let layout = ClockQuotaLayout(diameter: size.diameter, count: count, scale: size.scale)
                let geometry = NormalQuotaRingGeometry(size: layout.ringSize, lineWidth: (count == 1 ? 3 : 2.5) * size.scale, hasThirdRing: true)
                let middle = layout.ringSize / 2 - geometry.innerInset
                let inner = layout.ringSize / 2 - geometry.thirdInset
                XCTAssertGreaterThan(geometry.outerRadius - geometry.lineWidth / 2, middle + geometry.innerLineWidth / 2)
                XCTAssertGreaterThan(middle - geometry.innerLineWidth / 2, inner + geometry.thirdLineWidth / 2)
                XCTAssertGreaterThan(inner - geometry.thirdLineWidth / 2, (layout.ringSize / 2 - 9 * geometry.scale) - geometry.thirdLineWidth / 2)
            }
        }
    }

    func testConcentricTracksKeepGraphicContrastOnLightDarkAndColoredThemes() throws {
        func rgb(_ color: Color) throws -> NSColor { try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB)) }
        func luminance(_ components: [CGFloat]) -> Double {
            let linear = components.map { value in value <= 0.04045 ? Double(value) / 12.92 : pow((Double(value) + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        for theme in ClockFaceTheme.allCases where theme != .custom {
            let bg = try rgb(theme.dialColor)
            let background = [bg.redComponent, bg.greenComponent, bg.blueComponent]
            for layer in [1, 2] {
                let color = try rgb(NormalQuotaRingPalette.concentricColor(layer: layer, contrast: theme.textPrimaryColor))
                let foreground = [color.redComponent, color.greenComponent, color.blueComponent]
                let rendered = zip(foreground, background).map { $0 * 0.9 + $1 * 0.1 }
                let a = luminance(rendered), b = luminance(background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 3, "\(theme.rawValue) layer \(layer)")
            }
        }
    }

    func testNormalRingsRenderOnEveryBuiltInThemeWithOneTwoAndThreePools() throws {
        _ = NSApplication.shared
        for theme in ClockFaceTheme.allCases where theme != .custom {
            let indicators = [
                DialQuotaIndicator(provider: .codex, outerRemainingPercent: 100, innerRemainingPercent: nil, details: []),
                .init(provider: .cursor, outerRemainingPercent: 99, innerRemainingPercent: 65, details: []),
                .init(provider: .antigravity, outerRemainingPercent: 83, innerRemainingPercent: 65, thirdRemainingPercent: 40, details: [])
            ]
            let root = HStack(spacing: 18) {
                ForEach(indicators) { indicator in
                    VStack(spacing: 12) {
                        NormalQuotaRingView(indicator: indicator, theme: theme, primary: theme.textPrimaryColor,
                            secondary: theme.textSecondaryColor, size: 42, lineWidth: 3, fontSize: 11)
                        NormalQuotaRingView(indicator: indicator, theme: theme, primary: theme.textPrimaryColor,
                            secondary: theme.textSecondaryColor, size: 36, lineWidth: 2.5, fontSize: 9.5)
                    }
                }
            }.padding(18).background(theme.dialColor).environment(\.colorScheme, theme.dropdownColorScheme)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 210, height: 132)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let output = ProcessInfo.processInfo.environment["TOKENCLOCK_NORMAL_PARITY_ARTIFACTS"] {
                let url = URL(fileURLWithPath: output).appendingPathComponent("rings-\(theme.rawValue).png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            }
        }
    }
}
#endif
