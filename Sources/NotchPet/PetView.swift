import SwiftUI

/// Pip: a small round critter drawn entirely in code.
struct PetView: View {
    let mood: Mood
    /// Where the cursor is relative to Pip, each axis in -1...1 (y grows downward).
    let look: CGPoint
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: mood == .sleeping ? 1.0 / 8 : 1.0 / 30)) { tl in
            Canvas { ctx, sz in
                draw(ctx, sz, t: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
    }

    private var bodyColor: Color {
        switch mood {
        case .sleeping: return Color(red: 0.58, green: 0.60, blue: 0.72)
        case .awake: return Color(red: 0.76, green: 0.72, blue: 1.00)
        case .busy: return Color(red: 1.00, green: 0.74, blue: 0.50)
        case .alert: return Color(red: 1.00, green: 0.80, blue: 0.28)
        case .happy: return Color(red: 0.56, green: 0.92, blue: 0.66)
        case .sad: return Color(red: 1.00, green: 0.55, blue: 0.55)
        }
    }

    private func draw(_ ctx: GraphicsContext, _ sz: CGSize, t: Double) {
        let u = sz.width / 24   // drawing unit: everything is laid out on a 24x24 grid
        var dx = 0.0, dy = 0.0, squash = 1.0
        switch mood {
        case .sleeping: squash = 1 + 0.035 * sin(t * 1.6)
        case .awake: dy = 0.4 * sin(t * 2)
        case .busy: dy = 0.9 * sin(t * 9); squash = 1 + 0.03 * sin(t * 9 + 1)
        case .alert: dx = 0.6 * sin(t * 40)
        case .happy: dy = -abs(sin(t * 7)) * 3.2; squash = 1 + 0.06 * cos(t * 14)
        case .sad: dy = 1.2
        }

        let w = 18.0 * u * (2 - squash), h = 14.5 * u * squash
        let cx = sz.width / 2 + dx * u
        let bottom = sz.height - 2.5 * u + dy * u
        let bodyRect = CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h)

        // Shadow on the "floor".
        let shadowW = w * (mood == .happy ? 0.6 + 0.4 * (1 + dy / 3.2) : 0.9)
        ctx.fill(Path(ellipseIn: CGRect(x: sz.width / 2 - shadowW / 2, y: sz.height - 2.2 * u, width: shadowW, height: 1.4 * u)),
                 with: .color(.black.opacity(0.35)))

        // Ears.
        for side in [-1.0, 1.0] {
            var ear = Path()
            let ex = cx + side * w * 0.30
            ear.move(to: CGPoint(x: ex - 2.6 * u, y: bodyRect.minY + 2.2 * u))
            ear.addQuadCurve(to: CGPoint(x: ex + side * 1.0 * u, y: bodyRect.minY - 3.2 * u + (mood == .sad ? 2 * u : 0)),
                             control: CGPoint(x: ex - side * 0.4 * u, y: bodyRect.minY - 1.5 * u))
            ear.addQuadCurve(to: CGPoint(x: ex + 2.6 * u, y: bodyRect.minY + 2.2 * u),
                             control: CGPoint(x: ex + side * 2.2 * u, y: bodyRect.minY))
            ctx.fill(ear, with: .color(bodyColor))
        }

        // Body with a soft top highlight.
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: h * 0.48, style: .continuous)
        ctx.fill(bodyPath, with: .linearGradient(Gradient(colors: [bodyColor.opacity(1), bodyColor.opacity(0.82)]),
                                                 startPoint: CGPoint(x: cx, y: bodyRect.minY), endPoint: CGPoint(x: cx, y: bodyRect.maxY)))
        ctx.fill(Path(ellipseIn: CGRect(x: bodyRect.minX + w * 0.18, y: bodyRect.minY + h * 0.08, width: w * 0.3, height: h * 0.16)),
                 with: .color(.white.opacity(0.35)))

        // Eyes.
        let eyeY = bodyRect.minY + h * 0.46
        let eyeGap = w * 0.22
        let ink = Color(red: 0.12, green: 0.10, blue: 0.16)
        let blink = fmod(t, 3.9) < 0.13 && mood != .sleeping && mood != .happy
        for side in [-1.0, 1.0] {
            let ex = cx + side * eyeGap
            switch mood {
            case .sleeping:
                var p = Path()
                p.addArc(center: CGPoint(x: ex, y: eyeY - 0.6 * u), radius: 1.6 * u, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.1 * u, lineCap: .round))
            case .happy:
                var p = Path()
                p.addArc(center: CGPoint(x: ex, y: eyeY + 0.8 * u), radius: 1.7 * u, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.2 * u, lineCap: .round))
            case .sad:
                var p = Path()
                p.move(to: CGPoint(x: ex - 1.3 * u, y: eyeY - 1.3 * u)); p.addLine(to: CGPoint(x: ex + 1.3 * u, y: eyeY + 1.3 * u))
                p.move(to: CGPoint(x: ex + 1.3 * u, y: eyeY - 1.3 * u)); p.addLine(to: CGPoint(x: ex - 1.3 * u, y: eyeY + 1.3 * u))
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.0 * u, lineCap: .round))
            default:
                if blink {
                    var p = Path()
                    p.move(to: CGPoint(x: ex - 1.6 * u, y: eyeY)); p.addLine(to: CGPoint(x: ex + 1.6 * u, y: eyeY))
                    ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.0 * u, lineCap: .round))
                } else {
                    let r = (mood == .alert ? 2.7 : 2.3) * u
                    ctx.fill(Path(ellipseIn: CGRect(x: ex - r, y: eyeY - r * 1.1, width: 2 * r, height: 2.2 * r)), with: .color(.white))
                    let pr = (mood == .alert ? 1.1 : 1.4) * u
                    let px = ex + look.x * r * 0.42, py = eyeY + look.y * r * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: 2 * pr, height: 2 * pr)), with: .color(ink))
                    ctx.fill(Path(ellipseIn: CGRect(x: px - pr * 0.2, y: py - pr * 0.75, width: pr * 0.6, height: pr * 0.6)), with: .color(.white))
                }
            }
            // Cheeks.
            ctx.fill(Path(ellipseIn: CGRect(x: ex + side * 1.6 * u - 1.2 * u, y: eyeY + 2.4 * u, width: 2.4 * u, height: 1.3 * u)),
                     with: .color(Color(red: 1, green: 0.45, blue: 0.55).opacity(0.45)))
        }

        // Mouth.
        var mouth = Path()
        let my = eyeY + 3.3 * u
        switch mood {
        case .happy, .awake:
            mouth.addArc(center: CGPoint(x: cx, y: my - 0.6 * u), radius: 1.0 * u, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        case .alert:
            mouth.addEllipse(in: CGRect(x: cx - 0.7 * u, y: my - 0.7 * u, width: 1.4 * u, height: 1.6 * u))
        case .sad:
            mouth.addArc(center: CGPoint(x: cx, y: my + 0.6 * u), radius: 1.0 * u, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        case .busy:
            mouth.move(to: CGPoint(x: cx - 0.8 * u, y: my)); mouth.addLine(to: CGPoint(x: cx + 0.8 * u, y: my))
        case .sleeping:
            mouth.addEllipse(in: CGRect(x: cx - 0.5 * u, y: my - 0.4 * u, width: 1.0 * u, height: 0.9 * u))
        }
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 0.8 * u, lineCap: .round))

        // Little extras above the head.
        switch mood {
        case .sleeping:
            let phase = fmod(t * 0.5, 1)
            ctx.draw(Text("z").font(.system(size: 6 * u, weight: .heavy, design: .rounded)).foregroundColor(.white.opacity(1 - phase)),
                     at: CGPoint(x: cx + w * 0.5 + phase * 2 * u, y: bodyRect.minY - phase * 4 * u))
        case .alert:
            let pulse = 0.6 + 0.4 * sin(t * 8)
            ctx.draw(Text("!").font(.system(size: 8 * u, weight: .black, design: .rounded)).foregroundColor(Color.yellow.opacity(pulse)),
                     at: CGPoint(x: cx + w * 0.55, y: bodyRect.minY - 0.5 * u))
        case .busy:
            for i in 0..<3 {
                let a = t * 5 + Double(i) * 2.094
                let r = 0.7 * u * (1 + 0.3 * Double(i))
                ctx.fill(Path(ellipseIn: CGRect(x: cx + w * 0.55 + cos(a) * 1.8 * u - r / 2, y: bodyRect.minY + sin(a) * 1.8 * u - r / 2, width: r, height: r)),
                         with: .color(.white.opacity(0.85)))
            }
        case .happy:
            let tw = 0.5 + 0.5 * sin(t * 10)
            ctx.draw(Text("✦").font(.system(size: 5 * u)).foregroundColor(.white.opacity(tw)), at: CGPoint(x: cx - w * 0.55, y: bodyRect.minY))
            ctx.draw(Text("✦").font(.system(size: 4 * u)).foregroundColor(.white.opacity(1 - tw)), at: CGPoint(x: cx + w * 0.58, y: bodyRect.minY + 2 * u))
        default:
            break
        }
    }
}
