import SwiftUI
import TideKit

/// The slowly drifting gradient behind every screen. Its colors follow the
/// month's mood: blue-teal when calm, amber when spending runs ahead of the
/// month, coral when over budget. Liquid Glass refracts it.
struct TideBackground: View {
    var health: BudgetHealth

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: time),
                colors: colors
            )
        }
        .animation(.easeInOut(duration: 1.2), value: health)
        .ignoresSafeArea()
    }

    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time.truncatingRemainder(dividingBy: 3600))
        let drift = { (speed: Float, phase: Float, amount: Float) -> Float in
            sin(t * speed + phase) * amount
        }
        func p(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2<Float>(x, y) }
        let top = p(0.5 + drift(0.11, 0, 0.12), 0)
        let left = p(0, 0.45 + drift(0.09, 1, 0.1))
        let center = p(0.5 + drift(0.13, 2, 0.18), 0.5 + drift(0.07, 3, 0.15))
        let right = p(1, 0.55 + drift(0.1, 4, 0.1))
        let bottom = p(0.5 + drift(0.08, 5, 0.12), 1)
        return [p(0, 0), top, p(1, 0), left, center, right, p(0, 1), bottom, p(1, 1)]
    }

    private var colors: [Color] {
        let dark = colorScheme == .dark
        switch health {
        case .calm:
            return dark
                ? [hex(0x07122B), hex(0x0B2A4A), hex(0x0A1F3D),
                   hex(0x0C3B57), hex(0x0E6470), hex(0x103B6B),
                   hex(0x050B1C), hex(0x0B2C47), hex(0x07122B)]
                : [hex(0xDCEBFF), hex(0xCFF3F1), hex(0xE6EEFF),
                   hex(0xBFE6F2), hex(0x9EDDE0), hex(0xC9DAFF),
                   hex(0xEEF5FF), hex(0xD5F1EC), hex(0xE0E8FF)]
        case .watch:
            return dark
                ? [hex(0x1A1024), hex(0x3A2412), hex(0x161433),
                   hex(0x4A2A10), hex(0x7A4A12), hex(0x2B1C3F),
                   hex(0x0E0A18), hex(0x3D2712), hex(0x15102A)]
                : [hex(0xFFF1DC), hex(0xFFE3BA), hex(0xF5E9FF),
                   hex(0xFFD9A0), hex(0xFFC97A), hex(0xEFE0FF),
                   hex(0xFFF6EA), hex(0xFFE6C4), hex(0xF8EEFF)]
        case .over:
            return dark
                ? [hex(0x1C0B16), hex(0x3D1220), hex(0x1A1030),
                   hex(0x52161F), hex(0x7F2A2A), hex(0x2E1238),
                   hex(0x10060E), hex(0x421420), hex(0x170C22)]
                : [hex(0xFFE5E3), hex(0xFFD0CC), hex(0xF5E6FF),
                   hex(0xFFC1B8), hex(0xFFA89E), hex(0xF0DCFF),
                   hex(0xFFF0EE), hex(0xFFD8D2), hex(0xF8EBFF)]
        }
    }

    private func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

extension View {
    /// Puts the Tide gradient behind a screen.
    func tideBackground(_ health: BudgetHealth) -> some View {
        background { TideBackground(health: health) }
    }
}

#Preview {
    TideBackground(health: .calm)
}
