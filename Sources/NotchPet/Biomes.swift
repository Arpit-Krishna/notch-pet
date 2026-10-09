import SwiftUI

/// Where each pet lives. The open panel is painted as that place, in chunky pixels.
enum Biome {
    case plains, village, deepDark, night, nether, taiga, meadow, lushCaves, none

    var name: String {
        switch self {
        case .plains: return "Plains"
        case .village: return "Village"
        case .deepDark: return "Deep Dark"
        case .night: return "Night"
        case .nether: return "Nether"
        case .taiga: return "Snowy Taiga"
        case .meadow: return "Flower Meadow"
        case .lushCaves: return "Lush Caves"
        case .none: return ""
        }
    }

    /// Animated biomes (stars, lava, sculk) redraw a few times a second; the rest are still.
    var animated: Bool { [.deepDark, .night, .nether, .taiga, .lushCaves].contains(self) }
}

extension PetKind {
    var biome: Biome {
        switch self {
        case .grassBlock, .pig, .cow, .sheep, .chicken, .steve, .alex, .notch: return .plains
        case .villager, .cat: return .village
        case .warden: return .deepDark
        case .zombie, .creeper: return .night
        case .herobrine: return .nether
        case .wolf, .fox: return .taiga
        case .bee: return .meadow
        case .axolotl: return .lushCaves
        case .classic: return .none
        }
    }
}

struct BiomeView: View {
    let biome: Biome

    var body: some View {
        TimelineView(.animation(minimumInterval: biome.animated ? 1.0 / 8 : 60, paused: !biome.animated)) { tl in
            Canvas { ctx, sz in
                BiomePainter(ctx: ctx, size: sz, t: tl.date.timeIntervalSinceReferenceDate).paint(biome)
            }
        }
        .allowsHitTesting(false)
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

/// Draws on a grid of 6 pt "blocks".
private struct BiomePainter {
    let ctx: GraphicsContext
    let size: CGSize
    let t: Double
    let c: CGFloat = 6

    var cols: Int { Int(size.width / c) + 1 }
    var rows: Int { Int(size.height / c) + 1 }

    func cell(_ x: Int, _ y: Int, _ color: Color, w: Int = 1, h: Int = 1) {
        ctx.fill(Path(CGRect(x: CGFloat(x) * c, y: CGFloat(y) * c, width: CGFloat(w) * c + 0.4, height: CGFloat(h) * c + 0.4)), with: .color(color))
    }

    func pick(_ x: Int, _ y: Int, _ colors: [Color]) -> Color { colors[pixelNoise(x, y, colors.count)] }

    /// Stepped vertical gradient, like a sky in a block game.
    func sky(_ top: Color, _ bottom: Color, bands: Int = 6) {
        for i in 0..<bands {
            let y0 = Int(Double(rows) * Double(i) / Double(bands))
            let y1 = Int(Double(rows) * Double(i + 1) / Double(bands))
            let mix = Double(i) / Double(max(bands - 1, 1))
            cell(0, y0, Color(nsColor: top.mixed(with: bottom, by: mix)), w: cols, h: max(1, y1 - y0))
        }
    }

    /// Ground: a top layer and fill beneath, with a gentle hill line.
    func ground(top: [Color], fill: [Color], height: Int = 3) {
        for x in 0..<cols {
            let bump = pixelNoise(x / 4, 7, 3) == 0 ? 1 : 0
            let gy = rows - height - bump
            cell(x, gy, pick(x, gy, top))
            for y in (gy + 1)..<rows { cell(x, y, pick(x, y, fill)) }
        }
    }

    func readable() {
        // Darken so text on top stays easy to read.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.38)))
    }

    func paint(_ b: Biome) {
        switch b {
        case .plains: plains(flowers: false)
        case .meadow: plains(flowers: true)
        case .village: village()
        case .deepDark: deepDark()
        case .night: night()
        case .nether: nether()
        case .taiga: taiga()
        case .lushCaves: lushCaves()
        case .none: return
        }
        readable()
    }

    static let grassTop = [rgb(0.36, 0.62, 0.20), rgb(0.45, 0.74, 0.27), rgb(0.30, 0.52, 0.16)]
    static let dirt = [rgb(0.53, 0.38, 0.24), rgb(0.45, 0.31, 0.19), rgb(0.60, 0.44, 0.29)]

    func clouds() {
        for i in 0..<4 {
            let x = (pixelNoise(i, 3, cols) + i * cols / 4) % max(cols, 1)
            let y = 1 + pixelNoise(i, 9, 3)
            cell(x, y, .white.opacity(0.85), w: 5, h: 1)
            cell(x + 1, y - 1, .white.opacity(0.85), w: 3, h: 1)
        }
    }

    func plains(flowers: Bool) {
        sky(rgb(0.40, 0.60, 0.95), rgb(0.70, 0.84, 1.0))
        cell(cols - 6, 1, rgb(1.0, 0.95, 0.55), w: 3, h: 3)   // square sun
        clouds()
        ground(top: Self.grassTop, fill: Self.dirt)
        if flowers {
            let petals = [rgb(0.95, 0.25, 0.25), rgb(1.0, 0.85, 0.2), rgb(0.45, 0.55, 1.0), rgb(1.0, 0.6, 0.85), .white]
            for x in stride(from: 1, to: cols, by: 3) where pixelNoise(x, 5, 2) == 0 {
                let gy = rows - 4 - (pixelNoise(x / 4, 7, 3) == 0 ? 1 : 0)
                cell(x, gy, pick(x, 1, petals))
            }
            // A bee nest on a little oak tree.
            let tx = cols / 5
            let gy = rows - 4
            cell(tx, gy - 3, rgb(0.42, 0.30, 0.18), w: 1, h: 3)
            cell(tx - 2, gy - 6, rgb(0.25, 0.50, 0.18), w: 5, h: 3)
            cell(tx + 1, gy - 3, rgb(0.85, 0.65, 0.30))
            cell(tx + 1, gy - 3 + 0, rgb(0.55, 0.40, 0.15).opacity(0.6), w: 1, h: 1)
        }
    }

    func village() {
        sky(rgb(0.45, 0.62, 0.95), rgb(0.95, 0.75, 0.55))   // warm evening
        clouds()
        ground(top: Self.grassTop, fill: Self.dirt)
        let gy = rows - 4
        let planks = [rgb(0.62, 0.48, 0.30), rgb(0.58, 0.44, 0.27)]
        let roof = rgb(0.30, 0.20, 0.12)
        for (i, hx) in [cols / 6, cols / 2 - 2, cols - cols / 4].enumerated() {
            let w = 5 + i % 2, h = 3 + (i == 1 ? 1 : 0)
            for y in 0..<h { for x in 0..<w { cell(hx + x, gy - h + y, pick(hx + x, y, planks)) } }
            cell(hx - 1, gy - h - 1, roof, w: w + 2, h: 1)
            cell(hx, gy - h - 2, roof, w: w, h: 1)
            cell(hx + 1, gy - h - 3, roof, w: w - 2, h: 1)
            cell(hx + w / 2, gy - 2, rgb(0.35, 0.24, 0.14), w: 1, h: 2)                 // door
            cell(hx + 1, gy - h + 1, rgb(0.75, 0.88, 0.95).opacity(0.9))                 // window
            // Path to the door.
            cell(hx + w / 2, gy + 1, rgb(0.55, 0.45, 0.30), w: 1, h: 1)
        }
        // A bell post.
        cell(cols / 2 + 6, gy - 4, rgb(0.42, 0.30, 0.18), w: 1, h: 4)
        cell(cols / 2 + 6, gy - 3, rgb(0.95, 0.80, 0.25))
    }

    func deepDark() {
        sky(rgb(0.02, 0.05, 0.07), rgb(0.04, 0.09, 0.12))
        let sculk = [rgb(0.04, 0.14, 0.18), rgb(0.03, 0.10, 0.14), rgb(0.06, 0.20, 0.24)]
        ground(top: sculk, fill: [rgb(0.10, 0.10, 0.12), rgb(0.13, 0.13, 0.15)])
        // Sculk veins pulsing on the floor and walls.
        for i in 0..<40 {
            let x = pixelNoise(i, 1, cols), y = rows / 2 + pixelNoise(i, 2, rows / 2)
            let pulse = 0.35 + 0.65 * max(0, sin(t * 1.6 + Double(i)))
            cell(x, y, rgb(0.20, 0.85, 0.85).opacity(0.5 * pulse))
        }
        // Sculk sensors with glowing tendrils.
        for i in 0..<3 {
            let x = cols / 4 * (i + 1)
            let gy = rows - 4
            cell(x, gy, rgb(0.05, 0.25, 0.30), w: 2, h: 1)
            let glow = 0.5 + 0.5 * sin(t * 2 + Double(i))
            cell(x, gy - 1, rgb(0.30, 0.95, 0.90).opacity(glow))
            cell(x + 1, gy - 1, rgb(0.30, 0.95, 0.90).opacity(1 - glow))
        }
    }

    func night() {
        sky(rgb(0.02, 0.03, 0.10), rgb(0.08, 0.10, 0.25))
        for i in 0..<30 {
            let x = pixelNoise(i, 11, cols), y = pixelNoise(i, 12, max(rows - 6, 1))
            let tw = 0.4 + 0.6 * max(0, sin(t * 2.5 + Double(i) * 1.7))
            ctx.fill(Path(CGRect(x: CGFloat(x) * c + 2, y: CGFloat(y) * c + 2, width: 2, height: 2)), with: .color(.white.opacity(tw)))
        }
        cell(cols - 7, 1, rgb(0.92, 0.92, 0.85), w: 3, h: 3)    // square moon
        cell(cols - 6, 2, rgb(0.75, 0.75, 0.70))
        ground(top: [rgb(0.15, 0.28, 0.10), rgb(0.18, 0.32, 0.12)], fill: [rgb(0.25, 0.18, 0.11), rgb(0.21, 0.15, 0.09)])
        // Dark oak silhouettes.
        for i in 0..<3 {
            let x = cols / 6 + i * cols / 3
            let gy = rows - 4
            cell(x, gy - 3, rgb(0.12, 0.08, 0.05), w: 1, h: 3)
            cell(x - 2, gy - 7, rgb(0.06, 0.14, 0.06), w: 5, h: 4)
        }
    }

    func nether() {
        let rack = [rgb(0.45, 0.12, 0.12), rgb(0.38, 0.09, 0.10), rgb(0.52, 0.16, 0.14)]
        for y in 0..<rows { for x in 0..<cols { cell(x, y, pick(x, y, rack)) } }
        // Glowstone hanging from the ceiling.
        for i in 0..<4 {
            let x = pixelNoise(i, 21, cols)
            cell(x, 0, rgb(1.0, 0.85, 0.40), w: 2, h: 1 + pixelNoise(i, 22, 2))
        }
        // Lava sea with a shimmer.
        for x in 0..<cols {
            for y in (rows - 3)..<rows {
                let s = 0.5 + 0.5 * sin(t * 2 + Double(x) * 0.7 + Double(y))
                cell(x, y, Color(nsColor: rgb(1.0, 0.40, 0.05).mixed(with: rgb(1.0, 0.75, 0.20), by: s)))
            }
        }
        // Drifting ash.
        for i in 0..<16 {
            let x = (Double(pixelNoise(i, 31, cols)) + t * 0.3).truncatingRemainder(dividingBy: Double(cols))
            let y = (Double(pixelNoise(i, 32, rows)) + t * 0.5).truncatingRemainder(dividingBy: Double(rows - 3))
            ctx.fill(Path(CGRect(x: x * c, y: y * c, width: 2, height: 2)), with: .color(.white.opacity(0.4)))
        }
    }

    func taiga() {
        sky(rgb(0.62, 0.72, 0.85), rgb(0.85, 0.90, 0.95))
        ground(top: [.white, rgb(0.92, 0.95, 1.0)], fill: Self.dirt)
        // Spruce trees with snowy tips.
        for i in 0..<5 {
            let x = i * cols / 5 + 2
            let gy = rows - 4
            let green = rgb(0.13, 0.27, 0.18)
            cell(x, gy - 2, rgb(0.30, 0.20, 0.12), w: 1, h: 2)
            for (k, w) in [5, 3, 1].enumerated() {
                cell(x - w / 2, gy - 3 - k * 2, green, w: w, h: 2)
                cell(x - w / 2, gy - 3 - k * 2, .white.opacity(0.9), w: w, h: 1)
            }
        }
        // Falling snow.
        for i in 0..<24 {
            let x = (Double(pixelNoise(i, 41, cols)) + sin(t + Double(i)) * 0.5)
            let y = (Double(pixelNoise(i, 42, rows)) + t * 1.2).truncatingRemainder(dividingBy: Double(rows))
            ctx.fill(Path(CGRect(x: x * c, y: y * c, width: 2.5, height: 2.5)), with: .color(.white.opacity(0.9)))
        }
    }

    func lushCaves() {
        let stone = [rgb(0.30, 0.31, 0.30), rgb(0.26, 0.27, 0.26), rgb(0.34, 0.35, 0.33)]
        for y in 0..<rows { for x in 0..<cols { cell(x, y, pick(x, y, stone)) } }
        // Moss carpet and a pool of water.
        ground(top: [rgb(0.35, 0.55, 0.20), rgb(0.40, 0.62, 0.24)], fill: [rgb(0.30, 0.48, 0.18), rgb(0.27, 0.42, 0.16)])
        let pool = cols / 2
        for x in pool..<min(cols, pool + 10) {
            for y in (rows - 3)..<rows { cell(x, y, rgb(0.20, 0.40, 0.80).opacity(0.85 + 0.15 * sin(t * 2 + Double(x)))) }
        }
        // Vines with glow berries from the ceiling.
        for i in 0..<9 {
            let x = pixelNoise(i, 51, cols)
            let len = 2 + pixelNoise(i, 52, 4)
            cell(x, 0, rgb(0.25, 0.50, 0.15), w: 1, h: len)
            let glow = 0.6 + 0.4 * sin(t * 1.5 + Double(i))
            cell(x, len, rgb(1.0, 0.65, 0.20).opacity(glow))
        }
        // Big dripleaf.
        let dx = pool - 3
        cell(dx, rows - 6, rgb(0.30, 0.55, 0.20), w: 1, h: 2)
        cell(dx - 1, rows - 7, rgb(0.40, 0.70, 0.25), w: 3, h: 1)
    }
}

private extension Color {
    func mixed(with other: Color, by f: Double) -> NSColor {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return a.blended(withFraction: CGFloat(f), of: b) ?? a
    }
}
