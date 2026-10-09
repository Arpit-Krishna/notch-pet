import SwiftUI

/// A lingering cloud of swirling potion particles around the notch, one color per alert type.
struct PotionEffect: Identifiable, Equatable {
    enum Kind: Equatable {
        case luck       // a turn finished: emerald green
        case glowing    // an agent needs you: gold, lingers until answered
        case harming    // an error: dark red
        case speed      // a new turn started: light blue, brief

        var name: String {
            switch self {
            case .luck: return "Luck"
            case .glowing: return "Glowing"
            case .harming: return "Harming"
            case .speed: return "Speed"
            }
        }
        var colors: [Color] {
            switch self {
            case .luck: return [Color(red: 0.35, green: 0.95, blue: 0.45), Color(red: 0.6, green: 1.0, blue: 0.55), Color(red: 0.2, green: 0.75, blue: 0.35)]
            case .glowing: return [Color(red: 1.0, green: 0.85, blue: 0.25), Color(red: 1.0, green: 0.95, blue: 0.6), Color(red: 0.95, green: 0.65, blue: 0.15)]
            case .harming: return [Color(red: 0.75, green: 0.08, blue: 0.12), Color(red: 0.45, green: 0.05, blue: 0.08), Color(red: 1.0, green: 0.3, blue: 0.25)]
            case .speed: return [Color(red: 0.5, green: 0.8, blue: 1.0), Color(red: 0.75, green: 0.92, blue: 1.0)]
            }
        }
        var density: Int { self == .speed ? 18 : 42 }
    }

    let id = UUID()
    let kind: Kind
    let start: Date
    var until: Date

    /// 0...1 strength: quick fade-in, slow fade-out over the last 1.5 s.
    func strength(at now: Date) -> Double {
        let fadeIn = min(1, now.timeIntervalSince(start) / 0.3)
        let fadeOut = min(1, max(0, until.timeIntervalSince(now) / 1.5))
        return fadeIn * fadeOut
    }
}

struct PotionParticles: View {
    let effects: [PotionEffect]
    /// Size of the black shape, so particles rise off its edges.
    let shapeWidth: CGFloat
    let shapeHeight: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        if effects.isEmpty {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                Canvas { ctx, sz in
                    draw(ctx, sz, now: tl.date)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func draw(_ ctx: GraphicsContext, _ sz: CGSize, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let cx = Double(sz.width) / 2
        let w = Double(shapeWidth), h = Double(shapeHeight), nh = Double(notchHeight)
        for (ei, e) in effects.enumerated() {
            let strength = e.strength(at: now)
            guard strength > 0 else { continue }
            for k in 0..<e.kind.density {
                let seed = Double(pixelNoise(k, ei * 31 + 7, 1000)) / 1000
                let life = 2.0 + seed * 1.4
                let phase = fmod(t / life + Double(k) * 0.618 + Double(ei) * 0.37, 1)
                let swirl = sin(phase * 9 + Double(k)) * 5
                var x = cx + swirl
                var y = 0.0
                // Swirls rise off the sides of the black shape and spill from its bottom edge.
                if k % 3 == 0 {
                    x += (seed - 0.5) * w * 0.9
                    y = h + 2 + phase * 30
                } else {
                    let side: Double = k % 2 == 0 ? -1 : 1
                    let drift = phase * 34 * (0.4 + seed)
                    x += side * (w / 2 + 3 + drift)
                    y = nh * 0.3 + phase * (h - nh * 0.3 + 26)
                }
                let alpha = strength * sin(phase * .pi) * 0.9
                let c = e.kind.colors[k % e.kind.colors.count].opacity(alpha)
                let s = 1.8 + seed * 1.6
                // Potion swirls are little plus shapes.
                ctx.fill(Path(CGRect(x: x - s / 2, y: y - s * 1.5, width: s, height: s * 3)), with: .color(c))
                ctx.fill(Path(CGRect(x: x - s * 1.5, y: y - s / 2, width: s * 3, height: s)), with: .color(c))
            }
        }
    }
}
