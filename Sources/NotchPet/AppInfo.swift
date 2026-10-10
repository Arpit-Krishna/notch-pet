import SwiftUI

/// Version info stamped into Info.plist by build.sh from the VERSION file.
enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    static var versionText: String { build.isEmpty ? "v\(version)" : "v\(version) (\(build))" }
}

/// The app icon: Pip the grass block standing in its plains home, on the macOS icon grid.
/// Rendered at 256 pt; `make-icon.sh` exports it at 4x and builds the .icns.
struct AppIconView: View {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let b = sz.width / 12   // 12 x 12 blocks
                func cell(_ x: Int, _ y: Int, _ c: Color, w: Int = 1, h: Int = 1) {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * b, y: CGFloat(y) * b, width: CGFloat(w) * b + 0.5, height: CGFloat(h) * b + 0.5)), with: .color(c))
                }
                // Stepped sky.
                let sky = [Self.rgb(0.36, 0.56, 0.93), Self.rgb(0.43, 0.63, 0.96), Self.rgb(0.51, 0.70, 0.98),
                           Self.rgb(0.58, 0.76, 1.0), Self.rgb(0.66, 0.82, 1.0)]
                for (i, c) in sky.enumerated() { cell(0, i * 2, c, w: 12, h: 2) }
                cell(8, 1, Self.rgb(1.0, 0.93, 0.50), w: 2, h: 2)   // square sun
                cell(1, 2, .white.opacity(0.9), w: 4); cell(2, 1, .white.opacity(0.9), w: 2)
                // Ground: one grass row over dirt.
                let grass = [Self.rgb(0.36, 0.62, 0.20), Self.rgb(0.45, 0.74, 0.27), Self.rgb(0.30, 0.52, 0.16)]
                let dirt = [Self.rgb(0.53, 0.38, 0.24), Self.rgb(0.45, 0.31, 0.19), Self.rgb(0.60, 0.44, 0.29)]
                for x in 0..<12 {
                    cell(x, 9, grass[(x * 7 + 3) % 3])
                    cell(x, 10, dirt[(x * 5 + 1) % 3])
                    cell(x, 11, dirt[(x * 11 + 2) % 3])
                }
            }
            // BlockPetView draws its block on columns 2-12 and rows 4-14 of a 16-pixel grid,
            // so shift it to stand centred on the grass.
            BlockPetView(mood: .awake, look: .zero, size: 150)
                .offset(x: 9, y: -4)
        }
        .frame(width: 206, height: 206)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous).strokeBorder(.black.opacity(0.25), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
        .frame(width: 256, height: 256)
    }
}
