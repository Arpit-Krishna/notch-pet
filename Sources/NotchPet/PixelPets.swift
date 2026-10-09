import SwiftUI

/// Every pet Pip can be. Sprites are pixel art drawn in code, traced from the in-game faces.
enum PetKind: String, CaseIterable, Identifiable {
    case grassBlock, creeper, zombie, warden, pig, cow, sheep, chicken, wolf, fox, cat, bee, axolotl, villager, steve, alex, herobrine, notch, classic

    var id: String { rawValue }

    var name: String {
        switch self {
        case .grassBlock: return "Grass Block"
        case .herobrine: return "Herobrine"
        case .notch: return "Notch"
        case .classic: return "Classic Pip"
        default: return rawValue.capitalized
        }
    }

    var theme: Theme { self == .classic ? .classic : .blocky }

    /// Each pet's sounds are pitched to its size: chickens chirp, cows rumble.
    var voice: Double {
        switch self {
        case .chicken, .bee: return 1.5
        case .cat, .fox, .axolotl: return 1.25
        case .cow, .notch, .zombie: return 0.8
        case .villager: return 0.9
        case .herobrine, .warden: return 0.6
        default: return 1.0
        }
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
let pixelInk = rgb(0.10, 0.08, 0.08)

/// A head, traced from the in-game face (minecraftfaces.com). Any grid size works;
/// it is scaled to fill a 10x10 cell box, sitting on the floor. `w` and `e` are eye
/// pixels (white and pupil), `k` is ink; `lid` is the palette key used to paint
/// closed eyes and `ink` the line drawn under them. A palette entry with several
/// colors is a texture: each pixel picks one by stable noise.
struct Sprite {
    let rows: [String]
    let palette: [Character: [Color]]
    var lid: Character
    var glowEyes = false
    var ink: Color = pixelInk
}

func pixelNoise(_ x: Int, _ y: Int, _ n: Int) -> Int {
    var h = UInt32(truncatingIfNeeded: x &* 73856093 ^ y &* 19349663)
    h ^= h >> 13; h &*= 0x5bd1e995; h ^= h >> 15
    return Int(h % UInt32(max(n, 1)))
}

extension PetKind {
    var sprite: Sprite? {
        let eye: [Character: [Color]] = ["w": [.white], "e": [pixelInk], "k": [pixelInk]]
        func p(_ extra: [Character: [Color]]) -> [Character: [Color]] { eye.merging(extra) { $1 } }
        switch self {
        case .creeper:
            return Sprite(rows: ["abcdfgah", "hijblgmn", "beeapeeq", "reesmeet", "tbfkkufb", "dhkkkkiv", "xykkkkzh", "sakAxkbB"],
                          palette: p(["A": [rgb(0.49, 0.88, 0.54)], "B": [rgb(0.40, 0.80, 0.33)], "a": [rgb(0.64, 0.80, 0.62)], "b": [rgb(0.27, 0.77, 0.21)], "c": [rgb(0.51, 0.80, 0.51)], "d": [rgb(0.54, 0.76, 0.58)], "f": [rgb(0.38, 0.88, 0.38)], "g": [rgb(0.44, 0.86, 0.36)], "h": [rgb(0.18, 0.58, 0.27)], "i": [rgb(0.38, 0.54, 0.40)], "j": [rgb(0.02, 0.58, 0.03)], "l": [rgb(0.27, 0.50, 0.27)], "m": [rgb(0.05, 0.45, 0.06)], "n": [rgb(0.82, 0.82, 0.82)], "p": [rgb(0.11, 0.84, 0.27)], "q": [rgb(0.86, 0.86, 0.86)], "r": [rgb(0.04, 0.73, 0.03)], "s": [rgb(0.11, 0.64, 0.22)], "t": [rgb(0.30, 0.90, 0.32)], "u": [rgb(0.78, 0.83, 0.76)], "v": [rgb(0.70, 0.80, 0.68)], "x": [rgb(0.76, 0.89, 0.73)], "y": [rgb(0.35, 0.62, 0.36)], "z": [rgb(0.62, 0.94, 0.62)]]), lid: "b")
        case .pig:
            return Sprite(rows: ["abaaccac", "abacacdd", "accccccd", "ewaaccwe", "acghhhdc", "ccicdjdd", "aallmndd", "aaccdcdd"],
                          palette: p(["a": [rgb(0.93, 0.60, 0.59)], "b": [rgb(0.88, 0.53, 0.52)], "c": [rgb(0.93, 0.63, 0.63)], "d": [rgb(0.95, 0.69, 0.68)], "g": [rgb(0.93, 0.73, 0.74)], "h": [rgb(0.95, 0.76, 0.77)], "i": [rgb(0.57, 0.29, 0.29)], "j": [rgb(0.61, 0.32, 0.31)], "l": [rgb(0.76, 0.49, 0.52)], "m": [rgb(0.81, 0.64, 0.60)], "n": [rgb(0.82, 0.55, 0.55)]]), lid: "a")
        case .cow:
            return Sprite(rows: ["aaabbccd", "aaabbbda", "ffabbaff", "ewahaawe", "aaaaaaaa", "adiiiida", "aigjjgid", "afjlljia"],
                          palette: p(["a": [rgb(0.25, 0.19, 0.14)], "b": [rgb(0.70, 0.70, 0.70)], "c": [rgb(0.51, 0.51, 0.51)], "d": [rgb(0.21, 0.16, 0.12)], "f": [rgb(0.79, 0.79, 0.79)], "g": [rgb(0.00, 0.00, 0.00)], "h": [rgb(0.63, 0.63, 0.63)], "i": [rgb(0.86, 0.86, 0.86)], "j": [rgb(0.38, 0.38, 0.38)], "l": [rgb(0.29, 0.29, 0.29)]]), lid: "a")
        case .sheep:
            return Sprite(rows: ["aabbbb", "ccccdc", "ewcgwe", "iggjji", "almmin", "biopin"],
                          palette: p(["a": [rgb(0.84, 0.84, 0.84)], "b": [rgb(0.79, 0.79, 0.79)], "c": [rgb(0.70, 0.58, 0.48)], "d": [rgb(0.72, 0.61, 0.53)], "g": [rgb(0.67, 0.54, 0.44)], "i": [rgb(0.56, 0.45, 0.37)], "j": [rgb(0.65, 0.51, 0.41)], "l": [rgb(0.58, 0.47, 0.39)], "m": [rgb(1.00, 0.71, 0.71)], "n": [rgb(0.86, 0.86, 0.86)], "o": [rgb(0.83, 0.59, 0.59)], "p": [rgb(0.85, 0.62, 0.62)]]), lid: "c")
        case .chicken:
            return Sprite(rows: ["aaaa", "eaae", "cccc", "dddd", "affa", ".ff."],
                          palette: p(["a": [rgb(0.89, 0.89, 0.89)], "c": [rgb(0.76, 0.58, 0.26)], "d": [rgb(0.59, 0.45, 0.20)], "f": [rgb(1.00, 0.00, 0.00)]]), lid: "a")
        case .wolf:
            return Sprite(rows: ["aaaa....aaaa", "aaaa....aaaa", "bbbb....bbbb", "bbbb....bbbb", "bbccbbbbccdd", "bbccbbbbccdd", "..eeggggee..", "..eeggggee..", "hhijjkkjjlhh", "hhijjkkjjlhh", "llijjjjjjill", "llijjjjjjill", "iiammmmmmaii", "iiammmmmmaii"],
                          palette: p(["a": [rgb(0.89, 0.87, 0.87)], "b": [rgb(0.78, 0.76, 0.76)], "c": [rgb(0.72, 0.70, 0.71)], "d": [rgb(0.75, 0.73, 0.74)], "g": [rgb(0.64, 0.53, 0.46)], "h": [rgb(0.65, 0.56, 0.49)], "i": [rgb(0.60, 0.55, 0.53)], "j": [rgb(0.92, 0.86, 0.84)], "l": [rgb(0.55, 0.44, 0.32)], "m": [rgb(0.25, 0.25, 0.27)]]), lid: "c")
        case .fox:
            return Sprite(rows: ["aa....aa", "ab....ba", "cddddddc", "cddddddc", "fcddddcf", "ewdhhdwe", "ccikkicc", "iiaaaaii"],
                          palette: p(["a": [rgb(0.98, 0.96, 0.96)], "b": [rgb(0.70, 0.56, 0.51)], "c": [rgb(0.81, 0.41, 0.11)], "d": [rgb(0.88, 0.49, 0.12)], "f": [rgb(0.69, 0.32, 0.13)], "h": [rgb(0.91, 0.56, 0.26)], "i": [rgb(0.91, 0.85, 0.82)]]), lid: "c")
        case .cat:
            return Sprite(rows: [".aa....aa.", ".aa....aa.", "bbbbbbbbbb", "bbbbbbbbbb", "wweebbeeww", "wweebbeeww", "bbffggffbb", "bbffggffbb", "bbhhhhhhbb", "bbhhhhhhbb"],
                          palette: p(["a": [rgb(0.15, 0.14, 0.19)], "b": [rgb(0.10, 0.09, 0.15)], "f": [rgb(0.34, 0.33, 0.38)], "g": [rgb(0.75, 0.45, 0.45)], "h": [rgb(0.69, 0.69, 0.69)], "e": [rgb(0.36, 0.62, 0.08)]]), lid: "b", ink: rgb(0.55, 0.55, 0.60))
        case .bee:
            return Sprite(rows: ["aabaaba", "bkabbka", "dfbbafd", "ewbbbwe", "eebbbee", "eefbfee", "dddfddd"],
                          palette: p(["a": [rgb(1.00, 0.84, 0.41)], "b": [rgb(0.93, 0.76, 0.27)], "d": [rgb(0.81, 0.56, 0.28)], "f": [rgb(0.89, 0.69, 0.24)], "w": [rgb(0.49, 0.78, 0.82)], "e": [rgb(0.16, 0.15, 0.18)]]), lid: "b")
        case .axolotl:
            return Sprite(rows: ["...a......a...", "a..ba....ab..a", "ba..ba..ab..ab", ".baccccccccab.", "..acccccccca..", "a..eccffcce..a", "ba.cccccccc.ab", ".baghcccchgab."],
                          palette: p(["a": [rgb(0.99, 0.22, 0.62)], "b": [rgb(1.00, 0.37, 0.54)], "c": [rgb(0.98, 0.76, 0.89)], "f": [rgb(0.82, 0.36, 0.65)], "g": [rgb(0.93, 0.50, 0.73)], "h": [rgb(1.00, 0.65, 0.84)], "e": [rgb(0.21, 0.00, 0.58)]]), lid: "c")
        case .warden:
            return Sprite(rows: ["abaaaaaaaaaaaaaa", "acaccaccaaccccca", "dacdcddddddddadd", "cddfdfdfddffffff", "fffcffffffffffff", "ffffffffffffcggg", "gggggfccccfggggg", "gggfcccaacccgggg", "gggcghhhhhhgcggg", "fgchhhhhhhhhhcgg", "fgfhhgggggghhfgg", "gfhhggffffgghhfg", "gfdggaaacacggcfg", "ggfdcdffffdccfgg", "ggfffggggggfffgg", "gggfggggggggfggg"],
                          palette: p(["a": [rgb(0.02, 0.43, 0.53)], "b": [rgb(0.46, 0.59, 0.73)], "c": [rgb(0.04, 0.31, 0.37)], "d": [rgb(0.07, 0.21, 0.27)], "f": [rgb(0.11, 0.18, 0.22)], "g": [rgb(0.09, 0.12, 0.15)], "h": [rgb(0.03, 0.02, 0.11)]]), lid: "g")
        case .zombie:
            return Sprite(rows: ["aaabcbaa", "aaadffab", "agghiijd", "jgjgjgdd", "geeggeej", "aggccgdb", "aabmmcab", "nnccbcbc"],
                          palette: p(["a": [rgb(0.27, 0.46, 0.21)], "b": [rgb(0.24, 0.40, 0.19)], "c": [rgb(0.22, 0.37, 0.16)], "d": [rgb(0.31, 0.49, 0.24)], "f": [rgb(0.35, 0.58, 0.24)], "g": [rgb(0.40, 0.56, 0.34)], "h": [rgb(0.47, 0.61, 0.40)], "i": [rgb(0.44, 0.58, 0.36)], "j": [rgb(0.37, 0.53, 0.28)], "m": [rgb(0.31, 0.43, 0.19)], "n": [rgb(0.20, 0.34, 0.13)]]), lid: "g")
        case .villager:
            return Sprite(rows: ["ababbbab", "abbbbbab", "abbbbbab", "bccccccb", "awebbewa", "fbaffabf", "fbgffgbf", "fbbffbbf"],
                          palette: p(["a": [rgb(0.74, 0.55, 0.45)], "b": [rgb(0.71, 0.48, 0.40)], "c": [rgb(0.20, 0.14, 0.07)], "f": [rgb(0.56, 0.37, 0.26)], "g": [rgb(0.47, 0.26, 0.21)], "e": [rgb(0.00, 0.59, 0.07)]]), lid: "b")
        case .steve:
            return Sprite(rows: ["aaaabbaa", "aaaaccaa", "adfgdfha", "idiijdll", "dweidewi", "lidnndlo", "ppcqqcpo", "nncrccoo"],
                          palette: p(["a": [rgb(0.18, 0.13, 0.05)], "b": [rgb(0.14, 0.09, 0.03)], "c": [rgb(0.26, 0.16, 0.07)], "d": [rgb(0.71, 0.54, 0.42)], "f": [rgb(0.74, 0.56, 0.45)], "g": [rgb(0.78, 0.59, 0.50)], "h": [rgb(0.67, 0.46, 0.35)], "i": [rgb(0.67, 0.49, 0.40)], "j": [rgb(0.61, 0.45, 0.36)], "l": [rgb(0.61, 0.41, 0.30)], "n": [rgb(0.42, 0.25, 0.19)], "o": [rgb(0.50, 0.33, 0.20)], "p": [rgb(0.56, 0.37, 0.26)], "q": [rgb(0.54, 0.30, 0.24)], "r": [rgb(0.26, 0.11, 0.04)], "e": [rgb(0.32, 0.24, 0.54)]]), lid: "d")
        case .herobrine:
            // Steve's face with blank glowing eyes.
            return Sprite(rows: ["aaaabbaa", "aaaaccaa", "adfgdfha", "idiijdll", "dwwidwwi", "lidnndlo", "ppcqqcpo", "nncrccoo"],
                          palette: p(["a": [rgb(0.18, 0.13, 0.05)], "b": [rgb(0.14, 0.09, 0.03)], "c": [rgb(0.26, 0.16, 0.07)], "d": [rgb(0.71, 0.54, 0.42)], "f": [rgb(0.74, 0.56, 0.45)], "g": [rgb(0.78, 0.59, 0.50)], "h": [rgb(0.67, 0.46, 0.35)], "i": [rgb(0.67, 0.49, 0.40)], "j": [rgb(0.61, 0.45, 0.36)], "l": [rgb(0.61, 0.41, 0.30)], "n": [rgb(0.42, 0.25, 0.19)], "o": [rgb(0.50, 0.33, 0.20)], "p": [rgb(0.56, 0.37, 0.26)], "q": [rgb(0.54, 0.30, 0.24)], "r": [rgb(0.26, 0.11, 0.04)]]), lid: "d", glowEyes: true)
        case .alex:
            // Not on minecraftfaces.com; drawn from Alex's default skin.
            return Sprite(rows: ["OOOOOOOO", "OOOOOOOO", "OssOOOOO", "sssssssO", "swessewO", "sssssssO", "sssmmssO", "ssssssOO"],
                          palette: p(["O": [rgb(0.88, 0.48, 0.18), rgb(0.82, 0.42, 0.14)], "s": [rgb(0.96, 0.80, 0.66), rgb(0.93, 0.77, 0.63)],
                                      "e": [rgb(0.25, 0.60, 0.30)], "m": [rgb(0.85, 0.55, 0.50)]]), lid: "s")
        case .notch:
            return Sprite(rows: ["..KKKKKK..", "..BBBBBB..", "KKKKKKKKKK", "HssssssssH", "swessssews",
                                 "ssssnnssss", "sHHHHHHHHs", "HHHssssHHH", "HHHHHHHHHH", ".HHHHHHHH."],
                          palette: p(["K": [rgb(0.12, 0.12, 0.13)], "B": [rgb(0.32, 0.32, 0.34)], "H": [rgb(0.42, 0.26, 0.15), rgb(0.38, 0.23, 0.13)],
                                      "s": [rgb(0.86, 0.66, 0.52)], "n": [rgb(0.74, 0.52, 0.40)]]), lid: "s")
        case .grassBlock, .classic:
            return nil
        }
    }
}

/// Any pet, picked by kind.
struct AnyPetView: View {
    let kind: PetKind
    let mood: Mood
    let look: CGPoint
    let size: CGFloat

    var body: some View {
        switch kind {
        case .classic: PetView(mood: mood, look: look, size: size)
        case .grassBlock: BlockPetView(mood: mood, look: look, size: size)
        default: SpritePetView(kind: kind, mood: mood, size: size)
        }
    }
}

struct SpritePetView: View {
    let kind: PetKind
    let mood: Mood
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: mood == .sleeping ? 1.0 / 6 : 1.0 / 24)) { tl in
            Canvas { ctx, sz in
                if let sprite = kind.sprite { draw(ctx, sz, sprite, t: tl.date.timeIntervalSinceReferenceDate) }
            }
        }
        .frame(width: size, height: size)
    }

    private func draw(_ ctx: GraphicsContext, _ sz: CGSize, _ sp: Sprite, t: Double) {
        let u = sz.width / 16
        var hop = 0.0, shake = 0.0
        switch mood {
        case .busy: hop = Int(t * 6) % 2 == 0 ? 0 : -1
        case .happy: hop = [0.0, -1, -2, -1][Int(t * 8) % 4]
        case .alert: shake = Int(t * 18) % 2 == 0 ? -0.5 : 0.5
        case .awake: hop = Int(t * 1.5) % 4 == 0 ? -1 : 0
        default: break
        }
        let x0 = 2.0 + shake, y0 = 4.0 + hop
        func px(_ x: Double, _ y: Double, _ c: Color, w: Double = 1, h: Double = 1) {
            ctx.fill(Path(CGRect(x: x * u, y: y * u, width: w * u + 0.3, height: h * u + 0.3)), with: .color(c))
        }

        px(2.5, 14.3, .black.opacity(mood == .happy ? 0.25 : 0.4), w: 9, h: 1)

        let grid = sp.rows.map { Array($0) }
        let cols = grid.map(\.count).max() ?? 1
        let cell = 10.0 / Double(max(cols, grid.count))
        let gx = x0 + (10 - Double(cols) * cell) / 2, gy = y0 + 10 - Double(grid.count) * cell
        func isEye(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y < grid.count, x >= 0, x < grid[y].count else { return false }
            return grid[y][x] == "w" || grid[y][x] == "e"
        }
        let blink = !sp.glowEyes && fmod(t, 3.9) < 0.15
        let closed = mood == .sleeping || blink
        let tint: Color? = mood == .alert && Int(t * 4) % 2 == 0 ? rgb(1, 0.1, 0.1).opacity(0.45)   // hurt flash
            : mood == .sleeping ? .black.opacity(0.28)
            : mood == .sad ? rgb(0.3, 0.3, 0.35).opacity(0.35) : nil
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                var key = ch
                var color: Color?
                if isEye(x, y) && (closed || mood == .happy) {
                    // Closed eyes: a dark line along the bottom; happy eyes: along the top.
                    let edge = closed ? !isEye(x, y + 1) : !isEye(x, y - 1)
                    if edge { color = sp.ink } else { key = sp.lid }
                } else if isEye(x, y) && mood == .sad {
                    color = (x + y) % 2 == 0 ? sp.ink : nil
                    if color == nil { key = sp.lid }
                }
                if color == nil {
                    let opts = sp.palette[key] ?? [.purple]
                    color = opts[pixelNoise(x, y, opts.count)]
                }
                let cx = gx + Double(x) * cell, cy = gy + Double(y) * cell
                px(cx, cy, color!, w: cell, h: cell)
                if let tint { px(cx, cy, tint, w: cell, h: cell) }
                if sp.glowEyes && ch == "w" && !closed {
                    ctx.fill(Path(CGRect(x: (cx - cell / 2) * u, y: (cy - cell / 2) * u, width: 2 * cell * u, height: 2 * cell * u)),
                             with: .color(.white.opacity(0.25 + 0.15 * sin(t * 3))))
                }
            }
        }

        PixelExtras.draw(ctx, u: u, mood: mood, t: t, x0: x0, y0: y0, pickaxe: true)
    }
}

/// Things that float around a pixel pet: pickaxe, "!", XP orbs, Zz, tears.
enum PixelExtras {
    static func draw(_ ctx: GraphicsContext, u: CGFloat, mood: Mood, t: Double, x0: Double, y0: Double, pickaxe: Bool) {
        func px(_ x: Double, _ y: Double, _ c: Color, w: Double = 1, h: Double = 1, in g: GraphicsContext? = nil) {
            (g ?? ctx).fill(Path(CGRect(x: x * u, y: y * u, width: w * u + 0.3, height: h * u + 0.3)), with: .color(c))
        }
        switch mood {
        case .busy where pickaxe:
            var g = ctx
            g.translateBy(x: (x0 + 10) * u, y: (y0 + 6) * u)
            g.rotate(by: .degrees(-25 + 45 * sin(t * 11)))
            let handle = rgb(0.45, 0.30, 0.15), head = rgb(0.40, 0.90, 0.88), headDark = rgb(0.18, 0.55, 0.55)
            for i in 0..<4 { px(Double(i), -Double(i), handle, in: g) }
            for (hx, hy) in [(1, -5), (2, -5), (3, -5), (4, -4), (5, -3), (5, -2)] { px(Double(hx), Double(hy), head, in: g) }
            px(3, -4, headDark, in: g); px(4, -3, headDark, in: g)
        case .alert:
            let c = Int(t * 6) % 2 == 0 ? rgb(1, 0.85, 0.2) : rgb(1, 0.5, 0.1)
            px(13.5, 0, c, h: 3); px(13.5, 4, c)
        case .happy:
            for i in 0..<3 {
                let p = fmod(t * 0.9 + Double(i) / 3, 1)
                let ox = [0.5, 13.0, 14.5][i] + sin(t * 4 + Double(i)) * 0.5
                let c = i == 1 ? rgb(0.75, 1.0, 0.3) : rgb(1.0, 0.95, 0.35)
                px(ox, 10 - p * 10, c.opacity(1 - p), w: 1.5, h: 1.5)
            }
        case .sleeping:
            let p = fmod(t * 0.4, 1)
            let zx = 12.5 + p * 1.5, zy = 3.0 - p * 3
            let c = Color.white.opacity(1 - p)
            px(zx, zy, c, w: 3); px(zx + 1, zy + 1, c); px(zx, zy + 2, c, w: 3)
        case .sad:
            px(x0 + 2.5, y0 + 7.5 + fmod(t * 3, 2), rgb(0.4, 0.6, 1.0).opacity(0.9))
        default:
            break
        }
    }
}

/// Grid of pets shown in the panel when the paw button is pressed.
struct PetPicker: View {
    @ObservedObject var ui: NotchUI

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(PetKind.allCases) { kind in
                Button {
                    ui.pet = kind
                    SoundFX.play(.select, pet: kind)
                } label: {
                    VStack(spacing: 2) {
                        AnyPetView(kind: kind, mood: kind == ui.pet ? .happy : .awake, look: .zero, size: 30)
                        Text(kind.name)
                            .font(uiFont(8, .regular, .blocky))
                            .foregroundStyle(.white.opacity(kind == ui.pet ? 1 : 0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .modifier(Bevel(fill: kind == ui.pet ? Color(red: 0.25, green: 0.4, blue: 0.2) : Color(white: 0.2)))
                }
                .buttonStyle(.plain)
                .help(kind.name)
            }
        }
        .padding(.horizontal, 10)
    }
}
