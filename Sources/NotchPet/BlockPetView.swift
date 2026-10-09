import SwiftUI

/// Minecraft-flavoured Pip: a little grass block with a face, drawn on a 16x16 pixel grid.
/// It mines with a pickaxe while agents work, turns into primed TNT when one needs you,
/// sheds XP orbs when a turn finishes, and goes cobblestone-grey on errors.
struct BlockPetView: View {
    let mood: Mood
    let look: CGPoint
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: mood == .sleeping ? 1.0 / 6 : 1.0 / 24)) { tl in
            Canvas { ctx, sz in
                draw(ctx, sz, t: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    private static let grass = [rgb(0.36, 0.62, 0.20), rgb(0.45, 0.74, 0.27), rgb(0.30, 0.52, 0.16)]
    private static let dirt = [rgb(0.53, 0.38, 0.24), rgb(0.45, 0.31, 0.19), rgb(0.62, 0.45, 0.30)]
    private static let tnt = [rgb(0.86, 0.18, 0.12), rgb(0.70, 0.12, 0.09)]
    private static let stone = [rgb(0.50, 0.50, 0.50), rgb(0.40, 0.40, 0.42), rgb(0.60, 0.60, 0.60)]
    private static let ink = rgb(0.10, 0.08, 0.08)

    /// Stable per-pixel noise so textures don't flicker.
    private func noise(_ x: Int, _ y: Int, _ n: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 73856093 ^ y &* 19349663)
        h ^= h >> 13; h &*= 0x5bd1e995; h ^= h >> 15
        return Int(h % UInt32(n))
    }

    private func draw(_ ctx: GraphicsContext, _ sz: CGSize, t: Double) {
        let u = sz.width / 16
        var hop = 0.0, shake = 0.0
        switch mood {
        case .busy: hop = Int(t * 6) % 2 == 0 ? 0 : -1
        case .happy: hop = [0.0, -1, -2, -1][Int(t * 8) % 4]
        case .alert: shake = Int(t * 18) % 2 == 0 ? -0.5 : 0.5
        case .awake: hop = Int(t * 1.5) % 4 == 0 ? -1 : 0
        default: break
        }

        func px(_ x: Double, _ y: Double, _ c: Color, w: Double = 1, h: Double = 1, in g: GraphicsContext? = nil) {
            (g ?? ctx).fill(Path(CGRect(x: x * u, y: y * u, width: w * u + 0.3, height: h * u + 0.3)), with: .color(c))
        }

        let x0 = 2.0 + shake, y0 = 4.0 + hop

        // Shadow.
        px(2.5, 14.3, .black.opacity(mood == .happy ? 0.25 : 0.4), w: 9, h: 1)

        // The block.
        for cy in 0..<10 {
            for cx in 0..<10 {
                let c: Color
                switch mood {
                case .alert:
                    if cy >= 4 && cy <= 5 { c = noise(cx, cy, 5) == 0 ? Self.ink : .white }   // the label band
                    else { c = Self.tnt[cx % 2] }
                case .sad:
                    c = Self.stone[noise(cx, cy, 3)]
                default:
                    let drip = noise(cx, 99, 3) == 0 ? 1 : 0
                    c = cy < 3 + drip ? Self.grass[noise(cx, cy, 3)] : Self.dirt[noise(cx, cy, 3)]
                }
                px(x0 + Double(cx), y0 + Double(cy), c)
            }
        }
        if mood == .alert && Int(t * 4) % 2 == 0 {
            px(x0, y0, .white.opacity(0.45), w: 10, h: 10)   // primed TNT flash
        }
        if mood == .sleeping {
            px(x0, y0, .black.opacity(0.28), w: 10, h: 10)   // night time
        }

        // Face.
        let ex = (look.x > 0.35 ? 1.0 : look.x < -0.35 ? -1.0 : 0.0)
        let ey = look.y > 0.5 ? 1.0 : 0.0
        let eyeY = y0 + (mood == .alert ? 6.5 : 4.5) + (mood == .alert ? 0 : ey)
        let blink = fmod(t, 3.9) < 0.15
        for side in [0.0, 1.0] {
            let bx = x0 + 2 + side * 4 + (mood == .sleeping || mood == .happy || mood == .sad ? 0 : ex)
            switch mood {
            case .sleeping:
                px(bx, eyeY + 1, Self.ink, w: 2)
            case .happy:
                px(bx - 0.5, eyeY + 1, Self.ink); px(bx + 0.5, eyeY, Self.ink); px(bx + 1.5, eyeY + 1, Self.ink)
            case .sad:
                px(bx - 0.5, eyeY, Self.ink); px(bx + 1.5, eyeY, Self.ink)
                px(bx + 0.5, eyeY + 1, Self.ink)
                px(bx - 0.5, eyeY + 2, Self.ink); px(bx + 1.5, eyeY + 2, Self.ink)
            default:
                if blink {
                    px(bx, eyeY + 1, Self.ink, w: 2)
                } else {
                    px(bx, eyeY, Self.ink, w: 2, h: 2)
                    px(bx, eyeY, .white.opacity(0.9))
                }
            }
        }
        let my = mood == .alert ? y0 + 8.5 : y0 + 7.5
        switch mood {
        case .happy:
            px(x0 + 3, my - 1, Self.ink); px(x0 + 4, my, Self.ink, w: 2); px(x0 + 6, my - 1, Self.ink)
        case .alert:
            px(x0 + 4, my - 0.5, Self.ink, w: 2, h: 1.5)
        case .sad:
            px(x0 + 4, my, Self.ink, w: 2); px(x0 + 3, my + 1, Self.ink); px(x0 + 6, my + 1, Self.ink)
            px(x0 + 2.5, eyeY + 3 + fmod(t * 3, 2), Self.rgb(0.4, 0.6, 1.0).opacity(0.9))   // tear
        case .sleeping:
            px(x0 + 4.5, my, Self.ink)
        default:
            px(x0 + 4, my, Self.ink, w: 2)
        }

        PixelExtras.draw(ctx, u: u, mood: mood, t: t, x0: x0, y0: y0, pickaxe: true)
    }
}
