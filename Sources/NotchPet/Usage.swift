import SwiftUI

/// One plan limit window, e.g. Claude's 5-hour session limit or the weekly limit.
struct LimitWindow: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let usedPct: Double
    let resetsAt: Date?

    /// A window whose reset time has passed is back to 0 %.
    func effective(at now: Date) -> Double {
        if let r = resetsAt, r <= now { return 0 }
        return usedPct
    }
}

struct AgentUsage: Equatable {
    var windows: [LimitWindow]
    var plan: String?
    var updated: Date
}

enum UsageParser {
    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func epoch(_ v: Any?) -> Date? {
        guard var e = number(v), e > 0 else { return parseDate(v) }
        if e > 1e12 { e /= 1000 }   // milliseconds
        return Date(timeIntervalSince1970: e)
    }

    /// Claude Code status line payload: `rate_limits.{five_hour, seven_day, …}.{used_percentage, resets_at}`.
    static func claude(_ payload: [String: Any], now: Date) -> AgentUsage? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        // Only the windows Claude documents in /usage. The account endpoint also returns
        // internal codename windows that mean nothing to a user, so those are skipped.
        let order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]
        var windows: [LimitWindow] = []
        for key in order {
            guard let w = limits[key] as? [String: Any],
                  let pct = number(w["used_percentage"] ?? w["utilization"]) else { continue }
            windows.append(LimitWindow(label: claudeLabel(key), usedPct: min(100, max(0, pct)), resetsAt: epoch(w["resets_at"])))
        }
        return windows.isEmpty ? nil : AgentUsage(windows: windows, plan: nil, updated: now)
    }

    private static func claudeLabel(_ key: String) -> String {
        switch key {
        case "five_hour": return "Session (5h)"
        case "seven_day": return "Weekly"
        case "seven_day_opus": return "Weekly Opus"
        case "seven_day_sonnet": return "Weekly Sonnet"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Codex `token_count` event: `rate_limits.{primary, secondary}.{used_percent, window_minutes, resets_at}`.
    static func codex(_ rl: [String: Any], at ts: Date) -> AgentUsage {
        var windows: [LimitWindow] = []
        for key in ["primary", "secondary"] {
            guard let w = rl[key] as? [String: Any], let pct = number(w["used_percent"]) else { continue }
            let minutes = number(w["window_minutes"]) ?? 0
            var reset = epoch(w["resets_at"])
            if reset == nil, let secs = number(w["resets_in_seconds"]) { reset = ts.addingTimeInterval(secs) }
            windows.append(LimitWindow(label: codexLabel(minutes), usedPct: min(100, max(0, pct)), resetsAt: reset))
        }
        var plan = rl["plan_type"] as? String
        if let credits = rl["credits"] as? [String: Any] {
            if credits["unlimited"] as? Bool == true { plan = (plan ?? "") + " · unlimited credits" }
            else if let bal = number(credits["balance"]) { plan = (plan ?? "") + String(format: " · %.0f credits", bal) }
        }
        return AgentUsage(windows: windows, plan: plan?.trimmingCharacters(in: CharacterSet(charactersIn: " ·")), updated: ts)
    }

    private static func codexLabel(_ minutes: Double) -> String {
        switch Int(minutes) {
        case 300: return "Session (5h)"
        case 10080: return "Weekly"
        case 0: return "Limit"
        default: return minutes >= 1440 ? "\(Int(minutes / 1440))-day" : "\(Int(minutes / 60))-hour"
        }
    }
}

func untilText(_ d: Date?, now: Date) -> String {
    guard let d else { return "" }
    let s = Int(d.timeIntervalSince(now))
    if s <= 0 { return "reset" }
    if s < 3600 { return "resets in \(s / 60)m" }
    if s < 86400 { return "resets in \(s / 3600)h \((s / 60) % 60)m" }
    return "resets in \(s / 86400)d \((s / 3600) % 24)h"
}

func tokenText(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)"
}

// MARK: - Views

struct UsageStrip: View {
    @ObservedObject var store: SessionStore
    let theme: Theme
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            card(.claude, store.claudeUsage) {
                if store.accountUsage {
                    Text(store.usageNote ?? "Asking Anthropic for your usage…")
                } else if store.statusLineInstalled {
                    Text("Shows up after your next message in the Claude Code CLI.")
                } else {
                    Button { store.setAccountUsage(true) } label: {
                        Label("Connect Claude usage", systemImage: "link")
                            .font(uiFont(10, .bold, theme))
                            .foregroundStyle(Agent.claude.tint)
                    }
                    .buttonStyle(.plain)
                    .help("Reads your plan usage from Anthropic using the Claude Code login in your Keychain (macOS asks once). Sent only to api.anthropic.com.")
                }
            }
            card(.codex, store.codexUsage) {
                Text("No Codex usage seen in the last week.")
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func card(_ agent: Agent, _ usage: AgentUsage?, @ViewBuilder empty: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(agent.label).font(uiFont(11, .bold, theme)).foregroundStyle(agent.tint)
                if let plan = usage?.plan, !plan.isEmpty {
                    Text(plan).font(uiFont(9, .regular, theme)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if agent == .claude && (store.accountUsage || store.statusLineInstalled) {
                    Button {
                        if store.accountUsage { store.setAccountUsage(false) }
                        if store.statusLineInstalled { store.setStatusLine(false) }
                    } label: { Image(systemName: "link.badge.plus").rotationEffect(.degrees(45)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.3))
                        .help("Disconnect Claude usage")
                }
                if agent == .claude && !store.accountUsage {
                    // Old status line numbers can fill the card, so the connect button lives in the header too.
                    Button { store.setAccountUsage(true) } label: {
                        Label("Connect", systemImage: "link").font(uiFont(9.5, .bold, theme))
                    }
                    .buttonStyle(.plain).foregroundStyle(Agent.claude.tint)
                    .help("Read your plan usage from Anthropic using your Claude Code login (macOS asks once)")
                }
            }
            if agent == .claude, let note = store.usageNote {
                // A failed refresh must not leave old numbers looking current.
                Text(note).font(uiFont(9.5, .regular, theme)).foregroundStyle(Color(red: 1, green: 0.75, blue: 0.3))
                    .fixedSize(horizontal: false, vertical: true)
                if let usage {
                    Text("Last reading \(relative(usage.updated, now: now)) ago")
                        .font(uiFont(9, .regular, theme)).foregroundStyle(.white.opacity(0.4))
                }
            } else if let usage, !usage.windows.isEmpty {
                Text(freshness(agent, usage))
                    .font(uiFont(8.5, .regular, theme))
                    .foregroundStyle(isStale(agent, usage) ? Color(red: 1, green: 0.75, blue: 0.3) : .white.opacity(0.35))
                ForEach(usage.windows.prefix(2)) { w in   // the card fits two bars: session and weekly
                    LimitBar(window: w, theme: theme, now: now)
                }
            } else if usage != nil {
                Text("No limits reported for this plan.").font(uiFont(10, .regular, theme)).foregroundStyle(.white.opacity(0.45))
            } else {
                empty().font(uiFont(10, .regular, theme)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: UsageStrip.height, maxHeight: UsageStrip.height, alignment: .topLeading)
        .modifier(CardBackground(theme: theme))
    }

    nonisolated static let height: CGFloat = 88

    /// Readings older than this are flagged: Claude account usage refreshes every 2 minutes,
    /// the status line and Codex logs only when those tools are used.
    private func isStale(_ agent: Agent, _ u: AgentUsage) -> Bool {
        let age = now.timeIntervalSince(u.updated)
        return agent == .claude && store.accountUsage ? age > 10 * 60 : age > 60 * 60
    }

    private func freshness(_ agent: Agent, _ u: AgentUsage) -> String {
        let ago = "updated \(relative(u.updated, now: now)) ago"
        return isStale(agent, u) ? "⚠ \(ago), may be out of date" : ago
    }
}

struct CardBackground: ViewModifier {
    let theme: Theme
    func body(content: Content) -> some View {
        if theme == .blocky {
            content.modifier(Bevel(fill: Color(white: 0.08).opacity(0.72)))
        } else {
            content.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}

struct LimitBar: View {
    let window: LimitWindow
    let theme: Theme
    let now: Date

    var body: some View {
        let pct = window.effective(at: now)
        let color: Color = pct < 50 ? Color(red: 0.35, green: 0.9, blue: 0.45) : pct < 80 ? Color(red: 1, green: 0.75, blue: 0.2) : Color(red: 1, green: 0.35, blue: 0.3)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 4)
                if let r = window.resetsAt, r <= now {
                    // The window renewed since the last report; the real number arrives with the next message.
                    Text("renewed · updates on next message").foregroundStyle(.white.opacity(0.4))
                } else {
                    Text("\(Int(pct.rounded()))%").foregroundStyle(color)
                    Text(untilText(window.resetsAt, now: now)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .font(uiFont(9.5, .regular, theme))
            .lineLimit(1)
            GeometryReader { g in
                if theme == .blocky {
                    // Segmented like an experience bar.
                    let segs = 18
                    let filled = Int((pct / 100 * Double(segs)).rounded())
                    HStack(spacing: 1) {
                        ForEach(0..<segs, id: \.self) { i in
                            Rectangle().fill(i < filled ? color : Color.black.opacity(0.6))
                                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(i < filled ? 0.35 : 0.05)).frame(height: 1) }
                        }
                    }
                    .padding(1)
                    .background(Color.black)
                } else {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(color).frame(width: max(3, g.size.width * pct / 100))
                    }
                }
            }
            .frame(height: 5)
        }
    }
}
