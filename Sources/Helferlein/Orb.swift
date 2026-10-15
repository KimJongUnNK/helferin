import SwiftUI

/// Animierte Kugel: atmet im Ruhezustand, pulsiert mit der Stimme beim Zuhören,
/// schwingt beim Sprechen, dreht beim Nachdenken.
struct Orb: View {
    let phase: Assistant.Phase
    let level: Float
    var size: CGFloat = 46

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let s = scale(t)
            ZStack {
                Circle()
                    .fill(gradient(t))
                    .blur(radius: size * 0.22)
                    .opacity(0.55)
                    .scaleEffect(s * 1.25)
                Circle()
                    .fill(gradient(t))
                    .scaleEffect(s)
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.45), Color.clear],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.55))
                    .scaleEffect(s)
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func scale(_ t: Double) -> CGFloat {
        switch phase {
        case .listening: return 1 + CGFloat(level) * 0.3 + 0.02 * CGFloat(sin(t * 3))
        case .speaking: return 1 + 0.07 * CGFloat(sin(t * 7)) + 0.03 * CGFloat(sin(t * 13))
        case .thinking: return 1 + 0.03 * CGFloat(sin(t * 2.5))
        case .idle: return 1 + 0.02 * CGFloat(sin(t * 1.3))
        }
    }

    private func gradient(_ t: Double) -> AngularGradient {
        let speed: Double = phase == .thinking ? 220 : 35
        return AngularGradient(colors: colors + [colors[0]], center: .center,
                               angle: .degrees((t * speed).truncatingRemainder(dividingBy: 360)))
    }

    private var colors: [Color] {
        switch phase {
        case .listening: return [Color(red: 1.0, green: 0.36, blue: 0.48), Color(red: 1.0, green: 0.62, blue: 0.35), Color(red: 0.93, green: 0.25, blue: 0.55)]
        case .speaking: return [Color(red: 0.62, green: 0.38, blue: 1.0), Color(red: 0.98, green: 0.45, blue: 0.72), Color(red: 0.42, green: 0.45, blue: 1.0)]
        case .thinking: return [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.2, green: 0.8, blue: 0.85)]
        case .idle: return [Color(red: 0.45, green: 0.42, blue: 0.95), Color(red: 0.7, green: 0.45, blue: 0.95), Color(red: 0.35, green: 0.6, blue: 0.95)]
        }
    }

    private var icon: String {
        switch phase {
        case .listening: return "mic.fill"
        case .speaking: return "waveform"
        case .thinking: return "ellipsis"
        case .idle: return "sparkles"
        }
    }
}
