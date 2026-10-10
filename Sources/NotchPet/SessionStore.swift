import AppKit
import Foundation

/// Discovers live Claude Code and Codex transcripts and keeps their sessions up to date.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var toast: Toast?
    @Published var soundOn: Bool = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn"); SoundFX.enabled = soundOn }
    }
    /// Which alerts pop up or make a sound, per agent, plus quiet hours.
    @Published var alerts = AlertSettings.load() { didSet { alerts.save() } }
    /// Lingering potion particles, one per recent alert.
    @Published private(set) var effects: [PotionEffect] = []
    /// The chosen pet, whose voice plays on alerts.
    var pet: PetKind = .grassBlock
    /// Plan limits: Claude's come from the status line, Codex's from its session logs.
    @Published private(set) var claudeUsage: AgentUsage?
    @Published private(set) var codexUsage: AgentUsage?
    @Published private(set) var statusLineInstalled = HookInstaller.isStatusLineInstalled
    private var statusTail = Tail(url: HookInstaller.statusURL)
    private var limitAlerts: Set<String> = []
    private var claudeCost: [String: Double] = [:]
    private var claudeWindow: [String: Int] = [:]
    @Published private(set) var lastHappy: Date = .distantPast
    @Published private(set) var hooksInstalled = HookInstaller.isInstalled
    /// Codex runs a new hook only after you trust it in `/hooks`; the first Codex event proves it.
    @Published private(set) var codexHookPending = false
    private var codexHookSeen = UserDefaults.standard.bool(forKey: "codexHookSeen")
    @Published private(set) var hookError: String?

    private var events = Tail(url: HookInstaller.eventsURL)
    private var tails: [String: Tail] = [:]
    private var state: [String: Session] = [:]
    private var waitNotified: Set<String> = []
    private var ticks = 0
    private var timer: Timer?
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// A transcript must have been written this recently to be picked up.
    private let freshWindow: TimeInterval = 15 * 60
    /// Sessions disappear after this long without activity.
    private let dropAfter: TimeInterval = 20 * 60

    func start() {
        updateHookState()
        SoundFX.enabled = soundOn
        // Start from the end of the event log: older prompts were answered long ago.
        let size = (try? fm.attributesOfItem(atPath: HookInstaller.eventsURL.path))?[.size] as? UInt64
        if size == nil || size! > 2_000_000 {
            try? fm.createDirectory(at: HookInstaller.dir, withIntermediateDirectories: true)
            try? Data().write(to: HookInstaller.eventsURL)
        }
        _ = events.readNew(backfill: 0)
        if ((try? fm.attributesOfItem(atPath: HookInstaller.statusURL.path))?[.size] as? UInt64 ?? 0) > 4_000_000 {
            try? Data().write(to: HookInstaller.statusURL)
        }
        scanCodexUsage()
        startWatching()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var mood: Mood {
        let now = Date()
        let phases = sessions.map { $0.displayPhase(at: now) }
        if phases.contains(.waiting) { return .alert }
        if phases.contains(where: { $0.isBusy }) { return .busy }
        if now.timeIntervalSince(lastHappy) < 6 { return .happy }
        if sessions.contains(where: { $0.phase == .error && now.timeIntervalSince($0.lastEvent) < 120 }) { return .sad }
        if sessions.contains(where: { now.timeIntervalSince(max($0.lastEvent, $0.lastActivity)) < 5 * 60 }) { return .awake }
        return .sleeping
    }

    private func tick() {
        let now = Date()
        // New transcripts are announced by FSEvents; a full scan is only a slow safety net.
        if ticks % 60 == 0 { discover(now) } else if !changedPaths.isEmpty { discoverChanged(now) }
        if ticks % 300 == 299 { scanCodexUsage() }
        if ticks % 120 == 2 { refreshAccountUsage() }
        ticks += 1

        for (path, tail) in tails {
            let wasLive = tail.hasRead
            let lines = tail.readNew()
            guard !lines.isEmpty, var s = state[path] else { continue }
            let before = s.displayPhase(at: now)
            for line in lines {
                guard let o = jsonObject(line) else { continue }
                if let ts = parseDate(o["timestamp"]), ts > s.lastActivity { s.lastActivity = ts }
                switch s.agent {
                case .claude: ClaudeParser.apply(o, to: &s)
                case .codex: CodexParser.apply(o, to: &s)
                }
            }
            state[path] = s
            let after = s.displayPhase(at: now)
            if wasLive && before != after { transition(s, from: before, to: after) }
        }

        readHookEvents()
        readStatusLine(now)
        for s in state.values {
            if let u = s.codexLimits, u.updated > (codexUsage?.updated ?? .distantPast) { codexUsage = u }
            if s.agent == .claude, let cost = claudeCost.first(where: { s.id.contains($0.key) })?.value, s.costUSD != cost {
                state[s.id]?.costUSD = cost
            }
            if s.agent == .claude, let size = claudeWindow.first(where: { s.id.contains($0.key) })?.value, s.contextLimit != size {
                state[s.id]?.contextLimit = size
            }
        }
        checkLimits(now)

        // Quiet tool calls turn into "needs you?" without new lines, so check every tick.
        var anyWaiting = false
        for (id, s) in state {
            if s.displayPhase(at: now) == .waiting {
                anyWaiting = true
                if !waitNotified.contains(id) {
                    waitNotified.insert(id)
                    let title = s.permission != nil ? "\(s.agent.label) needs your OK" : "\(s.agent.label) may need you"
                    show(Toast(agent: s.agent, phase: .waiting, title: title, detail: "\(s.project) · \(s.permission ?? s.activity)", sessionID: s.id), sound: .waiting, kind: .waiting)
                }
            } else {
                waitNotified.remove(id)
            }
        }

        // Glowing lingers for as long as someone is waiting on you, then fades.
        if anyWaiting {
            if let i = effects.firstIndex(where: { $0.kind == .glowing && $0.until > now }) { effects[i].until = now.addingTimeInterval(3) }
            else { effects.append(PotionEffect(kind: .glowing, start: now, until: now.addingTimeInterval(3))) }
        }
        if effects.contains(where: { $0.until < now }) { effects.removeAll { $0.until < now } }

        for (id, s) in state where now.timeIntervalSince(max(s.lastEvent, s.lastActivity)) > dropAfter && !s.phase.isBusy || now.timeIntervalSince(max(s.lastEvent, s.lastActivity)) > 60 * 60 {
            state[id] = nil
            tails[id] = nil
        }

        let sorted = state.values.sorted {
            let a = $0.displayPhase(at: now).rawValue, b = $1.displayPhase(at: now).rawValue
            return a != b ? a < b : $0.lastEvent > $1.lastEvent
        }
        if sorted != sessions { sessions = sorted }
    }

    private func transition(_ s: Session, from: Phase, to: Phase) {
        switch to {
        case .done where from.isBusy || from == .waiting:
            lastHappy = Date()
            let took = s.turnStart.map { " in " + clock(Date().timeIntervalSince($0)) } ?? ""
            if show(Toast(agent: s.agent, phase: .done, title: "\(s.agent.label) finished\(took)", detail: "\(s.project) · \(s.activity)", sessionID: s.id), sound: .done, kind: .done) {
                addEffect(.luck, seconds: 8)
            }
        case .error:
            if show(Toast(agent: s.agent, phase: .error, title: "\(s.agent.label) hit an error", detail: "\(s.project) · \(s.activity)", sessionID: s.id), sound: .error, kind: .error) {
                addEffect(.harming, seconds: 8)
            }
        case .thinking, .working:
            if from == .idle || from == .done { addEffect(.speed, seconds: 2.5) }
        default:
            break
        }
    }

    private func addEffect(_ kind: PotionEffect.Kind, seconds: TimeInterval) {
        let now = Date()
        effects.removeAll { $0.kind == kind }
        effects.append(PotionEffect(kind: kind, start: now, until: now.addingTimeInterval(seconds)))
    }

    /// Raises an alert as the alert settings allow. Returns whether the popup was shown.
    @discardableResult
    private func show(_ t: Toast, sound: SoundFX.Kind, kind: AlertKind) -> Bool {
        if alerts.sound(t.agent, kind) && !alerts.isQuiet(at: Date()) { SoundFX.play(sound, pet: pet) }
        guard alerts.popup(t.agent, kind) else { return false }
        toast = t
        let id = t.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.toast?.id == id { self?.toast = nil }
        }
        return true
    }

    func dismissToast() { toast = nil }

    /// Turns the permission hook on or off (only ever from the panel switch).
    func setHooks(_ on: Bool) {
        do {
            if on { try HookInstaller.install() } else { try HookInstaller.uninstall() }
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        updateHookState()
    }

    /// Claude usage read from Anthropic with the Claude Code login (see AccountUsage).
    @Published private(set) var accountUsage: Bool = UserDefaults.standard.bool(forKey: "accountUsage")
    @Published private(set) var usageNote: String?
    private var fetchingUsage = false

    func setAccountUsage(_ on: Bool) {
        accountUsage = on
        UserDefaults.standard.set(on, forKey: "accountUsage")
        usageNote = nil
        if on { refreshAccountUsage(interactive: true) } else { claudeUsage = nil }   // don't leave old numbers looking current
    }

    /// True when Keychain access has to be granted again (after a rebuild of Pip, or when Claude
    /// Code rewrote its login). The card then offers a click to allow, instead of a surprise dialog.
    @Published private(set) var usageNeedsAccess = false

    /// Background refreshes never open the Keychain dialog; only a click (`interactive`) does.
    func refreshAccountUsage(interactive: Bool = false) {
        guard accountUsage, !fetchingUsage else { return }
        fetchingUsage = true
        Task { @MainActor in
            defer { fetchingUsage = false }
            do {
                claudeUsage = try await AccountUsage.fetch(interactive: interactive)
                usageNote = nil
                usageNeedsAccess = false
            } catch AccountUsage.Failure.needsAccess {
                usageNeedsAccess = true
                usageNote = "macOS needs you to allow Keychain access again. Click Allow below."
            } catch AccountUsage.Failure.noLogin {
                usageNote = "No Claude Code login found in Keychain (or access was denied)."
            } catch AccountUsage.Failure.expired {
                usageNote = "Claude Code login expired. Use Claude Code once and it refreshes."
            } catch AccountUsage.Failure.http(let code) {
                usageNote = "Anthropic answered \(code). Retrying in 2 minutes."
            } catch {
                usageNote = "Couldn't read usage. Retrying in 2 minutes."
            }
        }
    }

    func setStatusLine(_ on: Bool) {
        if !on && !accountUsage { claudeUsage = nil }
        do {
            if on { try HookInstaller.installStatusLine() } else { try HookInstaller.uninstallStatusLine() }
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        statusLineInstalled = HookInstaller.isStatusLineInstalled
    }

    /// Latest Claude Code status line payloads: plan limits plus per-session cost.
    private func readStatusLine(_ now: Date) {
        let lines = statusTail.readNew(backfill: 256 * 1024)
        guard !lines.isEmpty else { return }
        // Payloads carry no timestamp; the file's write time is when Claude Code last reported.
        let written = (try? fm.attributesOfItem(atPath: HookInstaller.statusURL.path))?[.modificationDate] as? Date ?? now
        for line in lines {
            guard let o = jsonObject(line) else { continue }
            if let u = UsageParser.claude(o, now: written), u.updated >= (claudeUsage?.updated ?? .distantPast) { claudeUsage = u }
            if let sid = o["session_id"] as? String, let cost = (o["cost"] as? [String: Any])?["total_cost_usd"] as? Double {
                claudeCost[sid] = cost
            }
            if let sid = o["session_id"] as? String, let size = (o["context_window"] as? [String: Any])?["context_window_size"] as? Int {
                claudeWindow[sid] = size
            }
        }
    }

    /// Codex limits from the newest rollout file of the past week, so they show even with no live session.
    private func scanCodexUsage() {
        let env = ProcessInfo.processInfo.environment
        let root = env["NOTCHPET_CODEX_ROOT"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex/sessions")
        let cal = Calendar.current
        var newest: (URL, Date)?
        for back in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where f.pathExtension == "jsonl" {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m > (newest?.1 ?? .distantPast) {
                    newest = (f, m)
                }
            }
            if newest != nil { break }
        }
        guard let (url, _) = newest else { return }
        for line in Tail(url: url).readNew(backfill: 1024 * 1024).reversed() {
            guard line.contains("\"rate_limits\""), let o = jsonObject(line),
                  let p = o["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any] else { continue }
            let u = UsageParser.codex(rl, at: parseDate(o["timestamp"]) ?? Date())
            if u.updated > (codexUsage?.updated ?? .distantPast) { codexUsage = u }
            return
        }
    }

    /// One heads-up per limit window when it crosses 75 % and again at 90 %.
    private func checkLimits(_ now: Date) {
        for (agent, usage) in [(Agent.claude, claudeUsage), (Agent.codex, codexUsage)] {
            for w in usage?.windows ?? [] {
                let pct = w.effective(at: now)
                guard let level = [90.0, 75.0].first(where: { pct >= $0 }) else { continue }
                let key = "\(agent.rawValue)-\(w.label)-\(w.resetsAt?.timeIntervalSince1970 ?? 0)-\(level)"
                guard !limitAlerts.contains(key) else { continue }
                limitAlerts.insert(key)
                let shown = show(Toast(agent: agent, phase: level >= 90 ? .error : .waiting,
                           title: "\(agent.label) \(w.label.lowercased()) limit at \(Int(pct))%",
                           detail: untilText(w.resetsAt, now: now), header: level >= 90 ? "Almost out!" : "Running low!"), sound: level >= 90 ? .error : .waiting, kind: .limit)
                if shown { addEffect(level >= 90 ? .harming : .glowing, seconds: 6) }
            }
        }
    }

    /// Applies permission prompts reported by the hook to the matching session.
    private func updateHookState() {
        hooksInstalled = HookInstaller.isInstalled
        let codexInstalled = HookInstaller.isInstalled(.codex)
        if !codexInstalled { codexHookSeen = false; UserDefaults.standard.set(false, forKey: "codexHookSeen") }
        var confirmed: Set<Agent> = []
        if HookInstaller.isInstalled(.claude) { confirmed.insert(.claude) }
        if codexInstalled && codexHookSeen { confirmed.insert(.codex) }
        hookConfirmed = confirmed
        codexHookPending = codexInstalled && !codexHookSeen
    }

    private func readHookEvents() {
        for line in events.readNew(backfill: 0) {
            guard let o = jsonObject(line), let e = o["event"] as? [String: Any] else { continue }
            if o["agent"] as? String == "codex" && !codexHookSeen {
                codexHookSeen = true
                UserDefaults.standard.set(true, forKey: "codexHookSeen")
                updateHookState()
            }
            let name = e["hook_event_name"] as? String ?? ""
            guard name == "PermissionRequest" || name == "Notification" else { continue }
            let at = Date(timeIntervalSince1970: o["at"] as? Double ?? Date().timeIntervalSince1970)
            let path = e["transcript_path"] as? String
            let sid = e["session_id"] as? String ?? ""
            guard let key = state.keys.first(where: { $0 == path || (!sid.isEmpty && $0.contains(sid)) }),
                  var s = state[key] else { continue }
            // Already answered: the transcript moved on after the prompt appeared.
            if s.lastProgress > at { continue }
            var what = s.activity
            if let tool = e["tool_name"] as? String {
                let input = e["tool_input"] as? [String: Any] ?? [:]
                what = s.agent == .claude ? ClaudeParser.describe(tool, input)
                                          : CodexParser.describe(tool, ["arguments": (try? String(data: JSONSerialization.data(withJSONObject: input), encoding: .utf8)) ?? ""])
            }
            s.permission = what.isEmpty ? "Permission prompt" : what
            state[key] = s
        }
    }

    // MARK: Discovery

    private var claudeRoot: URL {
        ProcessInfo.processInfo.environment["NOTCHPET_CLAUDE_ROOT"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude/projects")
    }
    private var codexRoot: URL {
        ProcessInfo.processInfo.environment["NOTCHPET_CODEX_ROOT"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex/sessions")
    }
    private var watcher: FileWatcher?
    private var changedPaths: Set<String> = []

    private func startWatching() {
        watcher = FileWatcher(paths: [claudeRoot.resolvingSymlinksInPath().path, codexRoot.resolvingSymlinksInPath().path]) { [weak self] paths in
            MainActor.assumeIsolated { self?.changedPaths.formUnion(paths.filter { $0.hasSuffix(".jsonl") }) }
        }
    }

    /// Only the files FSEvents reported: Claude's `<project>/<session>.jsonl` and Codex rollouts.
    private func discoverChanged(_ now: Date) {
        let claude = claudeRoot.resolvingSymlinksInPath().standardizedFileURL
        let codex = codexRoot.resolvingSymlinksInPath().standardizedFileURL.path
        var found: [(URL, Agent)] = []
        for path in changedPaths where tails[path] == nil {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if url.deletingLastPathComponent().deletingLastPathComponent().path == claude.path {
                found.append((url, .claude))
            } else if url.path.hasPrefix(codex + "/") && url.lastPathComponent.hasPrefix("rollout-") {
                found.append((url, .codex))
            }
        }
        changedPaths.removeAll()
        track(found, now)
    }

    private func discover(_ now: Date) {
        changedPaths.removeAll()
        var found: [(URL, Agent)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        for dir in (try? fm.contentsOfDirectory(at: claudeRoot, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? [] where f.pathExtension == "jsonl" {
                found.append((f, .claude))
            }
        }

        let cal = Calendar.current
        for back in 0...1 {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = codexRoot.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? [] where f.pathExtension == "jsonl" {
                found.append((f, .codex))
            }
        }
        track(found, now)
    }

    private func track(_ found: [(URL, Agent)], _ now: Date) {
        for (url, agent) in found where tails[url.path] == nil {
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(mtime) < freshWindow else { continue }
            let tail = Tail(url: url)
            var s = Session(id: url.path, agent: agent)
            s.lastEvent = mtime
            if agent == .codex, let first = tail.firstLine(), let o = jsonObject(first) {
                CodexParser.apply(o, to: &s)
            }
            tails[url.path] = tail
            state[url.path] = s
        }
    }
}
