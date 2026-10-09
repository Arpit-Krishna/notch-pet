import AppKit
import ServiceManagement
import SwiftUI

enum NotchMode: Equatable { case collapsed, toast, expanded }

enum Theme: String {
    case blocky, classic
}

/// UI state shared between the window controller and SwiftUI.
@MainActor
final class NotchUI: ObservableObject {
    @Published var mode: NotchMode = .collapsed
    @Published var look: CGPoint = .zero
    @Published var notchWidth: CGFloat = 190
    @Published var notchHeight: CGFloat = 32
    @Published var pet: PetKind = PetKind(rawValue: UserDefaults.standard.string(forKey: "pet") ?? "") ?? .grassBlock {
        didSet { UserDefaults.standard.set(pet.rawValue, forKey: "pet") }
    }
    @Published var showPicker = false
    var theme: Theme { pet.theme }

    nonisolated static let wing: CGFloat = 44
    nonisolated static let flare: CGFloat = 8
    nonisolated static let rowHeight: CGFloat = 52
    nonisolated static let maxRows = 5

    func size(for mode: NotchMode, rows: Int) -> CGSize {
        let collapsedW = notchWidth + 2 * NotchUI.wing + 2 * NotchUI.flare
        switch mode {
        case .collapsed:
            return CGSize(width: collapsedW, height: notchHeight)
        case .toast:
            return CGSize(width: max(collapsedW, 420), height: notchHeight + 58)
        case .expanded:
            let rows = showPicker ? max(rows, 3) : rows
            let n = max(1, min(rows, NotchUI.maxRows))
            let list = rows == 0 ? 64 : CGFloat(n) * (NotchUI.rowHeight + 6)
            return CGSize(width: max(collapsedW + 60, 480), height: notchHeight + 66 + (showPicker ? 0 : UsageStrip.height + 6) + list)
        }
    }
}

// MARK: - Theme helpers

extension Phase {
    func tint(_ theme: Theme) -> Color {
        guard theme == .blocky else { return color }
        switch self {
        case .waiting: return Color(red: 1.0, green: 0.85, blue: 0.25)      // gold
        case .working, .thinking: return Color(red: 0.39, green: 0.89, blue: 0.87) // diamond
        case .error: return Color(red: 1.0, green: 0.30, blue: 0.22)        // redstone
        case .done: return Color(red: 0.30, green: 0.90, blue: 0.45)        // emerald
        case .idle: return Color.white.opacity(0.4)
        }
    }
}

func uiFont(_ size: CGFloat, _ weight: Font.Weight = .regular, _ theme: Theme) -> Font {
    theme == .blocky ? .system(size: size - 0.5, weight: weight == .regular ? .medium : .heavy, design: .monospaced)
                     : .system(size: size, weight: weight)
}

/// Raised-button look from block games: light top/left edge, dark bottom/right edge.
struct Bevel: ViewModifier {
    let fill: Color
    var raised = true

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(raised ? 0.22 : 0)).frame(height: 2) }
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(raised ? 0.22 : 0)).frame(width: 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.45)).frame(height: 2) }
            .overlay(alignment: .trailing) { Rectangle().fill(.black.opacity(0.45)).frame(width: 2) }
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
    }
}

/// Black shape that hangs from the top edge: flared top corners, rounded bottom corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var flare: CGFloat = NotchUI.flare

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in r: CGRect) -> Path {
        let br = min(bottomRadius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + flare, y: r.minY + flare), control: CGPoint(x: r.minX + flare, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + flare, y: r.maxY - br))
        p.addQuadCurve(to: CGPoint(x: r.minX + flare + br, y: r.maxY), control: CGPoint(x: r.minX + flare, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - flare - br, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - flare, y: r.maxY - br), control: CGPoint(x: r.maxX - flare, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - flare, y: r.minY + flare))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - flare, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct RootView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUI

    var body: some View {
        let size = ui.size(for: ui.mode, rows: store.sessions.count)
        let theme = ui.theme
        ZStack(alignment: .top) {
        PotionParticles(effects: store.effects, shapeWidth: size.width, shapeHeight: size.height, notchHeight: ui.notchHeight)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: ui.mode == .collapsed ? 10 : (theme == .blocky ? 8 : 20))
                    .fill(Color.black)
                if ui.mode != .collapsed && ui.pet.biome != .none {
                    // The pet's home, painted under everything below the notch.
                    BiomeView(biome: ui.pet.biome)
                        .padding(.top, ui.notchHeight)
                        .padding(.horizontal, NotchUI.flare)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
                        .transition(.opacity)
                }
                VStack(spacing: 0) {
                    topBar
                    if ui.mode == .toast, let t = store.toast {
                        ToastView(toast: t, theme: theme)
                            .jumpOnClick(store.sessions.first { $0.id == t.sessionID })
                            .transition(.opacity)
                    } else if ui.mode == .expanded {
                        ExpandedView(store: store, ui: ui).transition(.opacity)
                    }
                }
                .padding(.horizontal, NotchUI.flare)
                .clipped()
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: ui.mode)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.sessions.count)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: ui.showPicker)
            Spacer(minLength: 0)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            AnyPetView(kind: ui.pet, mood: store.mood, look: ui.look, size: min(ui.notchHeight - 2, 30))
                .frame(width: NotchUI.wing)
            Color.clear.frame(width: ui.notchWidth)
            StatusWing(sessions: store.sessions, theme: ui.theme)
                .frame(width: NotchUI.wing)
            Spacer(minLength: 0)
        }
        .frame(height: ui.notchHeight)
    }
}

/// Right-hand wing: one dot per session, colored by what it is doing.
struct StatusWing: View {
    let sessions: [Session]
    let theme: Theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let phases = sessions.prefix(4).map { ($0.agent, $0.displayPhase(at: tl.date)) }
            if phases.isEmpty {
                Text("zz").font(uiFont(10, .bold, theme)).foregroundStyle(.white.opacity(0.25))
            } else {
                HStack(spacing: 3) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { _, item in
                        Dot(agent: item.0, phase: item.1, theme: theme)
                    }
                }
            }
        }
    }
}

struct Dot: View {
    let agent: Agent
    let phase: Phase
    let theme: Theme
    @State private var pulse = false

    var body: some View {
        let color = phase.isBusy && theme == .classic ? agent.tint : phase.tint(theme)
        Group {
            if theme == .blocky {
                Rectangle().fill(color).frame(width: 6, height: 6)
                    .overlay(alignment: .topLeading) { Rectangle().fill(.white.opacity(0.5)).frame(width: 2, height: 2) }
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
        }
        .opacity(phase.isBusy || phase == .waiting ? (pulse ? 1 : 0.35) : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    let theme: Theme

    var body: some View {
        if theme == .blocky {
            // Styled like an in-game advancement popup.
            HStack(spacing: 10) {
                AgentBadge(agent: toast.agent, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(header).font(uiFont(12, .bold, theme)).foregroundStyle(toast.phase == .waiting ? Color(red: 1, green: 0.85, blue: 0.25) : toast.phase.tint(theme))
                    Text("\(toast.title) · \(toast.detail)").font(uiFont(11, .regular, theme)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .modifier(Bevel(fill: Color(white: 0.13)))
            .padding(.horizontal, 10)
            .padding(.top, 4)
        } else {
            HStack(spacing: 10) {
                AgentBadge(agent: toast.agent, theme: theme)
                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(toast.phase.color)
                    Text(toast.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
        }
    }

    private var header: String {
        if let h = toast.header { return h }
        switch toast.phase {
        case .done: return "Advancement made!"
        case .waiting: return "Needs you!"
        case .error: return "Ouch!"
        default: return toast.title
        }
    }
}

struct AgentBadge: View {
    let agent: Agent
    let theme: Theme

    var body: some View {
        let glyph = Text(agent.glyph)
            .font(.system(size: agent == .claude ? 12 : 9, weight: .heavy, design: .monospaced))
            .foregroundStyle(agent == .claude ? Color.white : Color.black)
            .frame(width: 24, height: 24)
        if theme == .blocky {
            glyph.modifier(Bevel(fill: agent.tint))
        } else {
            glyph.background(Circle().fill(agent.tint))
        }
    }
}

// MARK: - Expanded panel

struct ExpandedView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUI
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let theme = ui.theme
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            VStack(spacing: 6) {
                Text(summary(tl.date))
                    .font(uiFont(11, .regular, theme))
                    .foregroundStyle(store.hookError != nil ? Color.red.opacity(0.8) : .white.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 22)

                if !ui.showPicker {
                    UsageStrip(store: store, theme: theme, now: tl.date)
                }
                if ui.showPicker {
                    PetPicker(ui: ui)
                    Spacer(minLength: 0)
                } else if store.sessions.isEmpty {
                    Text(theme == .blocky ? "No Claude or Codex sessions in the last 15 minutes.\nPip is sleeping through the night."
                                          : "No Claude or Codex sessions in the last 15 minutes.\nPip is taking a nap.")
                        .multilineTextAlignment(.center)
                        .font(uiFont(12, .regular, theme))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 58)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(store.sessions) { s in
                                SessionRow(session: s, now: tl.date, theme: theme)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                footer(theme)
            }
        }
    }

    private func summary(_ now: Date) -> String {
        if ui.showPicker { return "Choose your pet" }
        if let err = store.hookError { return "Couldn't change permission alerts: \(err)" }
        let phases = store.sessions.map { $0.displayPhase(at: now) }
        let busy = phases.filter(\.isBusy).count
        let waiting = phases.filter { $0 == .waiting }.count
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting) need\(waiting == 1 ? "s" : "") you") }
        if busy > 0 { parts.append("\(busy) working") }
        let done = phases.filter { $0 == .done }.count
        if done > 0 { parts.append("\(done) done") }
        return parts.isEmpty ? "All quiet" : parts.joined(separator: " · ")
    }

    private func footer(_ theme: Theme) -> some View {
        HStack(spacing: 14) {
            Button { store.soundOn.toggle() } label: {
                Image(systemName: store.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .help(store.soundOn ? "Mute sounds" : "Unmute sounds")

            Button { store.setHooks(!store.hooksInstalled) } label: {
                Label("Permission alerts", systemImage: store.hooksInstalled ? "bell.badge.fill" : "bell.slash")
            }
            .foregroundStyle(store.codexHookPending ? Color(red: 1, green: 0.75, blue: 0.3)
                             : store.hooksInstalled ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
            .help(!store.hooksInstalled
                  ? "Off: Pip guesses from quiet tool calls. Click to add a small hook to ~/.claude/settings.json and ~/.codex/hooks.json (a backup is kept)."
                  : store.codexHookPending
                  ? "On for Claude. Codex only runs new hooks after you trust them: run /hooks in Codex and approve Notch Pet's. Until Pip sees one Codex prompt, it keeps guessing for Codex. Click to remove the hook."
                  : "On: Pip is told the moment Claude or Codex shows a permission prompt. Click to remove the hook.")

            Button {
                do {
                    if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
                } catch {}
                launchAtLogin = SMAppService.mainApp.status == .enabled
            } label: {
                Label("Login", systemImage: launchAtLogin ? "checkmark.circle.fill" : "circle")
            }
            .help("Open Notch Pet at login")

            Spacer()
            Button { ui.showPicker.toggle() } label: {
                Label(ui.showPicker ? "Done" : ui.pet.name, systemImage: ui.showPicker ? "checkmark" : "pawprint.fill")
            }
            .help("Choose your pet")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Notch Pet")
        }
        .buttonStyle(.plain)
        .font(uiFont(11, .regular, theme))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}

struct SessionRow: View {
    let session: Session
    let now: Date
    let theme: Theme

    var body: some View {
        let phase = session.displayPhase(at: now)
        let content = HStack(spacing: 10) {
            AgentBadge(agent: session.agent, theme: theme)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.project).font(uiFont(13, .semibold, theme)).foregroundStyle(.white).lineLimit(1)
                    if let b = session.branch {
                        Text(b).font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(theme == .blocky ? AnyShapeStyle(Color.black.opacity(0.35)) : AnyShapeStyle(Color.white.opacity(0.1)),
                                        in: theme == .blocky ? AnyShape(Rectangle()) : AnyShape(Capsule()))
                            .lineLimit(1)
                    }
                }
                Text(line(phase))
                    .font(uiFont(11, .regular, theme))
                    .foregroundStyle(phase == .idle ? Color.white.opacity(0.45) : Color.white.opacity(0.78))
                    .lineLimit(1)
                    .help(session.lastPrompt.isEmpty ? session.activity : "“\(session.lastPrompt)”")
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.permission != nil ? "Needs you" : phase.label)
                    .font(uiFont(10, .bold, theme))
                    .foregroundStyle(phase.tint(theme))
                Text(timeText(phase))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: NotchUI.rowHeight)

        Group {
            if theme == .blocky {
                content.modifier(Bevel(fill: phase == .waiting ? Color(red: 0.33, green: 0.26, blue: 0.08).opacity(0.85) : Color(white: 0.12).opacity(0.72)))
            } else {
                content
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(phase == .waiting ? 0.11 : 0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(phase == .waiting ? phase.color.opacity(0.5) : .clear, lineWidth: 1))
            }
        }
        .jumpOnClick(session)
        .contextMenu {
            Button("Go to window") { if !WindowJumper.jump(to: session) { NSSound.beep() } }
            if let cwd = session.cwd {
                Button("Open folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
                Button("Copy folder path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cwd, forType: .string)
                }
            }
            Button("Reveal transcript") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.id)]) }
        }
    }

    private func line(_ phase: Phase) -> String {
        if let p = session.permission { return "Asking to: \(p)" }
        switch phase {
        case .done: return "✓ " + session.activity
        case .idle: return session.lastPrompt.isEmpty ? session.activity : "Last: \(session.lastPrompt)"
        default:
            let steps = session.toolCount > 0 ? " · \(session.toolCount) steps" : ""
            let quiet = now.timeIntervalSince(max(session.lastEvent, session.lastActivity))
            let hush = phase.isBusy && quiet > 120 ? " · quiet \(relative(now.addingTimeInterval(-quiet), now: now))" : ""
            return session.activity + steps + hush
        }
    }

    private func timeText(_ phase: Phase) -> String {
        var parts: [String] = []
        if let n = session.contextTokens {
            if let lim = session.contextLimit, lim > 0 { parts.append("ctx \(Int(Double(n) / Double(lim) * 100))%") }
            else { parts.append("ctx \(tokenText(n))") }
        }
        if let c = session.costUSD { parts.append(String(format: "$%.2f", c)) }
        if phase.isBusy || phase == .waiting, let start = session.turnStart { parts.append(clock(now.timeIntervalSince(start))) }
        else { parts.append(relative(session.lastEvent, now: now) + " ago") }
        return parts.joined(separator: " · ")
    }
}
