import SwiftUI
import TideKit

/// A rounded Liquid Glass panel for grouped content.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 16
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        if let tint { return .regular.tint(tint.opacity(0.18)) }
        return .regular
    }
}

/// A circular progress ring. Overflows past 100% wrap in the warning color.
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.75), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 4)
        }
        .animation(.spring(duration: 0.8, bounce: 0.2), value: progress)
    }
}

/// A horizontal progress capsule.
struct ProgressCapsule: View {
    var progress: Double
    var color: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(1, max(0, progress))))
                    .shadow(color: color.opacity(0.5), radius: 6)
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.8, bounce: 0.2), value: progress)
    }
}

/// A category icon in a softly tinted circle.
struct IconBadge: View {
    var systemName: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: .circle)
    }
}

/// A member's initial in their color.
struct MemberAvatar: View {
    var member: Member?
    var size: CGFloat = 22

    var body: some View {
        Text(member?.initial ?? "?")
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background((member?.color ?? .gray).gradient, in: .circle)
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
    }
}

/// An amount whose digits roll when it changes.
struct AmountText: View {
    var money: Money
    var cents: Bool = true
    var signed: Bool = false

    var body: some View {
        Text(money.formatted(cents: cents, signed: signed))
            .monospacedDigit()
            .contentTransition(.numericText(value: money.amount.doubleValue))
            .animation(.snappy, value: money.amount)
    }
}

/// A section title above glass content.
struct SectionHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}
