import SwiftUI

/// The kinds of alerts Pip raises.
enum AlertKind: String, CaseIterable, Identifiable, Codable {
    case done, waiting, error, limit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .done: return "Turn finished"
        case .waiting: return "Needs you"
        case .error: return "Error"
        case .limit: return "Plan limit"
        }
    }
}

/// Per agent and per alert kind: show the popup, play the sound. Plus quiet hours, when
/// popups still show but nothing makes a sound. Everything defaults to on.
struct AlertSettings: Codable, Equatable {
    var popupsOff: Set<String> = []
    var soundsOff: Set<String> = []
    var quietHours = false
    var quietStart = 22   // hour, local time
    var quietEnd = 8

    private static func key(_ agent: Agent, _ kind: AlertKind) -> String { "\(agent.rawValue).\(kind.rawValue)" }

    func popup(_ agent: Agent, _ kind: AlertKind) -> Bool { !popupsOff.contains(Self.key(agent, kind)) }
    func sound(_ agent: Agent, _ kind: AlertKind) -> Bool { !soundsOff.contains(Self.key(agent, kind)) }

    mutating func toggle(popup agent: Agent, _ kind: AlertKind) { popupsOff.formSymmetricDifference([Self.key(agent, kind)]) }
    mutating func toggle(sound agent: Agent, _ kind: AlertKind) { soundsOff.formSymmetricDifference([Self.key(agent, kind)]) }

    /// True inside the quiet window; handles windows that cross midnight (22 → 8).
    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHours, quietStart != quietEnd else { return false }
        let h = calendar.component(.hour, from: date)
        return quietStart < quietEnd ? (h >= quietStart && h < quietEnd) : (h >= quietStart || h < quietEnd)
    }

    static func load() -> AlertSettings {
        guard let data = UserDefaults.standard.data(forKey: "alertSettings"),
              let s = try? JSONDecoder().decode(AlertSettings.self, from: data) else { return AlertSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "alertSettings") }
    }
}

/// The settings grid shown in the panel when the gear is pressed.
struct AlertSettingsView: View {
    @ObservedObject var store: SessionStore
    let theme: Theme

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("Alerts").frame(maxWidth: .infinity, alignment: .leading)
                ForEach([Agent.claude, .codex], id: \.self) { a in
                    Text(a.label).foregroundStyle(a.tint).frame(width: 92)
                }
            }
            .font(uiFont(10, .bold, theme))
            ForEach(AlertKind.allCases) { kind in
                HStack {
                    Text(kind.label).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach([Agent.claude, .codex], id: \.self) { a in
                        HStack(spacing: 10) {
                            toggle(on: store.alerts.popup(a, kind), on: "bell.fill", off: "bell.slash",
                                   help: "\(kind.label) popups for \(a.label)") { store.alerts.toggle(popup: a, kind) }
                            toggle(on: store.alerts.sound(a, kind), on: "speaker.wave.2.fill", off: "speaker.slash",
                                   help: "\(kind.label) sound for \(a.label)") { store.alerts.toggle(sound: a, kind) }
                        }
                        .frame(width: 92)
                    }
                }
            }
            HStack(spacing: 8) {
                toggle(on: store.alerts.quietHours, on: "moon.fill", off: "moon", help: "Quiet hours: popups only, no sounds") {
                    store.alerts.quietHours.toggle()
                }
                Text("Quiet hours")
                Spacer()
                hourStepper(\.quietStart)
                Text("→").foregroundStyle(.white.opacity(0.4))
                hourStepper(\.quietEnd)
            }
            .opacity(store.alerts.quietHours ? 1 : 0.6)
            .padding(.top, 2)
            Text("Notch Pet \(AppInfo.versionText)")
                .font(uiFont(8.5, .regular, theme)).foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(uiFont(10, .regular, theme))
        .foregroundStyle(.white.opacity(0.8))
        .padding(10)
        .modifier(CardBackground(theme: theme))
        .padding(.horizontal, 8)
    }

    private func toggle(on: Bool, on onIcon: String, off offIcon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? onIcon : offIcon).frame(width: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.white.opacity(0.9) : Color.white.opacity(0.3))
        .help(help)
    }

    private func hourStepper(_ path: WritableKeyPath<AlertSettings, Int>) -> some View {
        HStack(spacing: 3) {
            Button { store.alerts[keyPath: path] = (store.alerts[keyPath: path] + 23) % 24 } label: { Image(systemName: "chevron.left") }
            Text(String(format: "%02d:00", store.alerts[keyPath: path])).monospacedDigit()
            Button { store.alerts[keyPath: path] = (store.alerts[keyPath: path] + 1) % 24 } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
    }
}
