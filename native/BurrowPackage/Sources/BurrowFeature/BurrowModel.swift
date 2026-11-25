import AppKit
import Observation
import SwiftUI
@preconcurrency import UserNotifications

public enum Tab: String, CaseIterable, Identifiable, Sendable {
    case overview, clean, apps, tools, files, developer, monitor, schedule
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .overview: "Overview"; case .clean: "Clean"; case .apps: "Apps"; case .tools: "Tools"
        case .files: "Old files"; case .developer: "Developer"; case .monitor: "Monitor"; case .schedule: "Schedule"
        }
    }
}

/// What Burrow remembers between launches (native-state.json).
struct SavedState: Codable {
    var scan: CleanScan?
    var apps: [InstalledApp]?
    var tools: [Tool]?
    var old: [OldFile]?
    var dev: DevScan?
    var when: [String: When]?
    var moleLatest: String?
    var moleCheckedAt: Date?
}

/// Everything the window and the menu bar panel show, and every action they offer.
@MainActor
@Observable
public final class BurrowModel {
    public enum Phase { case starting, needsMole, ready }

    public var phase: Phase = .starting
    public var tab: Tab = .overview
    public var hasDiskAccess = DiskAccess.granted
    public var onboardingDismissed = UserDefaults.standard.bool(forKey: "onboardingDismissed")

    // Mole
    public var moleVersion = ""
    public var moleViaBrew = false
    public var moleLatest: String?
    var moleCheckedAt: Date?
    public var moleUpdating = false
    public var moleInstallLog = ""

    // Scans
    public var status: MoleStatus?
    public var processes: [ProcessGroup] = []
    public var scan: CleanScan?
    public var scanFresh = false
    public var scanProgress: String?
    public var excluded: Set<String> = []
    public var expanded: Set<String> = []
    public var children: [String: [CleanItem]] = [:]
    public var loadingChildren: Set<String> = []
    public var protectedInScan: [String: String] = [:]

    public var apps: [InstalledApp]?
    public var appsBusy = false
    public var appFilter: AppFilter?
    public var tools: [Tool]?
    public var toolsBusy = false
    public var old: [OldFile]?
    public var oldBusy = false
    public var oldSelected: Set<String> = []
    public var dev: DevScan?
    public var devBusy = false
    public var devSelected: Set<String> = []
    public var net: NetCheck?
    public var netBusy = false

    // Schedules and history
    public var routinesOn: [String: Bool] = [:]
    public var when: [String: When] = [:]
    public var history: [HistoryEntry] = []
    public var sweepPending = false

    // Actions in flight, the confirmation sheet, toasts
    public var busy: String?
    public var pendingPlan: Plan?
    var pendingContinuation: CheckedContinuation<Approved?, Never>?
    public var uninstallSheet: UninstallRequest?
    public var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?

    public var openWindow: (() -> Void)?

    public enum AppFilter: String, CaseIterable { case unused, largest, all }

    public init() {}

    // MARK: Start

    public func start() async {
        phase = .starting
        try? Paths.installScripts()
        Mole.restoreWhitelistIfInterrupted()
        load()
        hasDiskAccess = DiskAccess.granted
        guard await Mole.executable() != nil else { phase = .needsMole; return }
        let v = await Mole.version()
        moleVersion = v.version
        moleViaBrew = v.viaBrew
        for r in Routine.all { routinesOn[r.id] = r.isOn }
        Scheduler.refresh(when)
        sweepPending = FileManager.default.fileExists(atPath: Paths.sweepPending.path)
        history = History.load()
        phase = .ready
        await refreshStatus()
        Task { await checkMole(force: false) }
        scanClean()
        if hasDiskAccess {
            if old == nil { Task { await scanOld() } }
            if dev == nil { Task { await scanDev() } }
        }
        if apps == nil { Task { await scanApps() } }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshStatus() }
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: Paths.state), let s = try? JSONDecoder().decode(SavedState.self, from: data) else {
            when = Self.prototypeSchedules()
            return
        }
        scan = s.scan; apps = s.apps; tools = s.tools; old = s.old; dev = s.dev
        when = s.when ?? Self.prototypeSchedules()
        moleLatest = s.moleLatest; moleCheckedAt = s.moleCheckedAt
        if let scan { excluded = defaultExclusions(scan) }
        oldSelected = Set(oldDefaults)
        devSelected = Set((dev?.buildFolders ?? []).filter { $0.idle >= 14 }.map(\.path))
    }

    /// Times set in the Claude-app prototype (its state.json), so its schedules carry over.
    static func prototypeSchedules() -> [String: When] {
        guard let data = try? Data(contentsOf: Paths.appSupport.appendingPathComponent("state.json")),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sched = o["sched"] as? [String: [String: Any]] else { return [:] }
        var out: [String: When] = [:]
        for (id, s) in sched {
            guard let r = Routine.all.first(where: { $0.id == id }) else { continue }
            var w = r.defaultWhen
            if let h = s["hour"] as? Int { w.hour = h }
            if let m = s["minute"] as? Int { w.minute = m }
            if let d = s["weekday"] as? Int { w.weekday = d }
            if let d = s["day"] as? Int { w.day = d }
            out[id] = w
        }
        return out
    }

    func save() {
        let s = SavedState(scan: scan, apps: apps, tools: tools, old: old, dev: dev, when: when, moleLatest: moleLatest, moleCheckedAt: moleCheckedAt)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: Paths.state, options: .atomic) }
    }

    public func recheckAccess() {
        hasDiskAccess = DiskAccess.granted
        if hasDiskAccess {
            Task { await scanOld() }
            Task { await scanDev() }
        }
    }

    public func dismissOnboarding() {
        onboardingDismissed = true
        UserDefaults.standard.set(true, forKey: "onboardingDismissed")
    }

    // MARK: Toasts and confirmation

    public func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Shows the plan and waits for the person. nil = cancelled.
    public func ask(_ plan: Plan) async -> Approved? {
        openWindow?()
        pendingContinuation?.resume(returning: nil)
        pendingPlan = plan
        return await withCheckedContinuation { pendingContinuation = $0 }
    }

    public func answer(_ yes: Bool) {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        let c = pendingContinuation
        pendingContinuation = nil
        c?.resume(returning: yes ? Approved(plan) : nil)
    }

    func notify(_ body: String) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = "Burrow"
            content.body = body
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: Numbers

    public var cleanSelected: Double {
        guard let scan else { return 0 }
        var t = 0.0
        for c in scan.categories {
            for it in c.items where !excluded.contains(it.path) {
                t += it.size
                for ch in children[it.path] ?? [] where excluded.contains(ch.path) { t -= ch.size }
            }
        }
        return max(0, t)
    }

    var oldDefaults: [String] {
        (old ?? []).filter { $0.kind == .installer && $0.path.range(of: #"\.(pkg|mpkg|xip)$"#, options: [.regularExpression, .caseInsensitive]) != nil
            && $0.path.hasPrefix(Paths.home + "/Downloads/") && (Fmt.days($0.last) ?? 0) >= 30 }.map(\.path)
    }

    public var oldTotal: Double { (old ?? []).reduce(0) { $0 + $1.size } }
    public var devTotal: Double { (dev?.idleBuildBytes ?? 0) + (dev?.staleWorktrees ?? []).reduce(0) { $0 + $1.bytes } }
    public var reclaimSafe: Double { scan?.total ?? 0 }
    public var reclaimReview: Double { oldTotal + devTotal }
    public var reclaimAll: Double { reclaimSafe + reclaimReview }
    public var unusedApps: [InstalledApp] { (apps ?? []).filter { $0.isUnused() } }

    public var moleUpdate: String? {
        guard let latest = moleLatest, !moleVersion.isEmpty, Self.newer(latest, than: moleVersion) else { return nil }
        return latest
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) { return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0) }
        return false
    }

    public var statusLine: String {
        if let busy { return busy }
        if let p = scanProgress { return "Scanning: " + p }
        if let scan { return "Last scan " + Fmt.ago(scan.at.timeIntervalSince1970) }
        return ""
    }

    // MARK: Status and monitor

    public func refreshStatus() async {
        if let s = await Mole.status() { status = s }
        processes = await Scanners.processes()
    }

    public func netCheck() async {
        netBusy = true
        net = await Scanners.netCheck()
        netBusy = false
    }

    public func quit(_ p: ProcessGroup) async {
        guard let path = p.appPath else { return }
        guard await ask(Plan(kind: "quit", title: "Quit \(p.name)?", body: "\(p.name) is asked to quit normally, so it can save your work first.",
                             confirm: "Quit \(p.name)", destructive: false)) != nil else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
        apps.forEach { $0.terminate() }
        show(apps.isEmpty ? "\(p.name) isn't running as an app." : "Asked \(p.name) to quit.")
        try? await Task.sleep(for: .seconds(2.5))
        processes = await Scanners.processes()
    }

    public func flushDNS() async {
        let r = await Shell.run("/usr/bin/osascript", ["-e", "do shell script \"dscacheutil -flushcache; killall -HUP mDNSResponder\" with administrator privileges"])
        if r.ok {
            ActionRunner.record("flush-dns", freed: 0, note: nil)
            history = History.load()
            show("DNS cache flushed.")
        } else {
            show("DNS flush was cancelled.")
        }
    }

    // MARK: Clean

    func defaultExclusions(_ scan: CleanScan) -> Set<String> {
        var out = Set<String>()
        protectedInScan = [:]
        for c in scan.categories {
            for i in c.items {
                // The Trash is Burrow's undo for everything it moves there: unticked unless you tick it.
                if i.path.hasSuffix("/.Trash") { out.insert(i.path) }
                if let why = Guard.protectedFromCleaning(i.path) { out.insert(i.path); protectedInScan[i.path] = why }
            }
        }
        return out
    }

    public func scanClean() {
        guard scanProgress == nil else { return }
        scanProgress = "starting Mole…"
        Task {
            let result = await Mole.dryRun { [weak self] line in
                Task { @MainActor in if self?.scanProgress != nil { self?.scanProgress = line } }
            }
            scan = result
            scanFresh = true
            scanProgress = nil
            children = [:]
            expanded = []
            excluded = defaultExclusions(result)
            save()
            if result.categories.isEmpty { show("Mole found nothing to clean right now.") }
        }
    }

    public func toggle(category c: CleanCategory) {
        let allOn = c.items.allSatisfy { !excluded.contains($0.path) }
        for i in c.items where protectedInScan[i.path] == nil {
            if allOn { excluded.insert(i.path) } else { excluded.remove(i.path) }
        }
    }

    public func toggle(path: String) {
        guard protectedInScan[path] == nil else { return }
        if excluded.contains(path) { excluded.remove(path) } else { excluded.insert(path) }
    }

    public func expand(_ item: CleanItem) {
        if expanded.contains(item.path) { expanded.remove(item.path); return }
        expanded.insert(item.path)
        guard children[item.path] == nil else { return }
        loadingChildren.insert(item.path)
        Task {
            children[item.path] = await Mole.children(of: item.path)
            loadingChildren.remove(item.path)
        }
    }

    public func runClean() async {
        guard scanFresh, let scan else { scanClean(); return }
        let sel = cleanSelected
        let keep = Array(excluded).sorted()
        let trashKept = keep.contains { $0.hasSuffix("/.Trash") } || !scan.categories.flatMap(\.items).contains { $0.path.hasSuffix("/.Trash") }
        var body = "Mole deletes these caches, logs and leftovers for good. Apps rebuild caches as needed."
        if !trashKept { body += " Mole also empties the Trash, including anything Burrow moved there." }
        if !keep.isEmpty { body += " \(Fmt.plural(keep.count, "item")) you unticked stay." }
        let cleaned = scan.categories.flatMap(\.items).filter { !excluded.contains($0.path) }
        let plan = Plan(kind: "clean", title: "Clean \(Fmt.bytes(sel))?", body: body,
                        paths: cleaned.map { PlannedPath(path: $0.path, size: $0.size) }, commands: ["mo clean 2>&1"],
                        confirm: "Clean \(Fmt.bytes(sel))")
        guard let ok = await ask(plan) else { return }
        busy = "Cleaning with Mole…"
        let (result, freed) = await Mole.clean(ok, keep: keep)
        busy = nil
        ActionRunner.record("clean", freed: freed, note: result.ok ? nil : "Mole exited with \(result.code)", code: result.ok ? nil : Int(result.code))
        history = History.load()
        notify("Burrow freed \(Fmt.bytes(freed)).")
        show("Cleaned. \(Fmt.bytes(freed)) freed.")
        self.scan = nil
        scanFresh = false
        save()
        scanClean()
        await refreshStatus()
    }

    public func keepForever() async {
        let keep = Array(excluded).sorted()
        guard !keep.isEmpty, await ask(Plan(kind: "whitelist", title: "Always keep these?",
                                            body: "Adds them to Mole's whitelist, so neither Burrow nor mo clean will delete them again.",
                                            paths: keep.map { PlannedPath(path: $0, size: 0) }, confirm: "Add to whitelist", destructive: false)) != nil else { return }
        Mole.keepForever(keep)
        show("Added to the whitelist.")
    }

    // MARK: Mole updates

    public func checkMole(force: Bool) async {
        if !force, let at = moleCheckedAt, Date().timeIntervalSince(at) < 6 * 3600 { return }
        if let l = await Mole.latest() { moleLatest = l; moleCheckedAt = Date(); save() }
    }

    public func updateMole() async {
        guard let to = moleUpdate else { return }
        let cmd = moleViaBrew ? "brew upgrade mole 2>&1" : "mo update 2>&1"
        guard let ok = await ask(Plan(kind: "mole-update", title: "Update Mole to \(to)?",
                                      body: moleViaBrew ? "Runs brew upgrade mole. Your whitelist and settings stay." : "Runs mo update. Your whitelist and settings stay.",
                                      commands: [cmd], confirm: "Update Mole", destructive: false)) else { return }
        moleUpdating = true
        busy = "Updating Mole…"
        let r = await ActionRunner.run(ok, timeout: 15 * 60)
        moleVersion = await Mole.version().version
        busy = nil
        moleUpdating = false
        show(r.ok ? "Mole is now \(moleVersion)." : "Mole update failed: \(r.tail)")
    }

    public func installMole() async {
        moleInstallLog = "Running brew install mole…"
        let r = await Shell.sh("brew install mole 2>&1", timeout: 15 * 60) { [weak self] line in
            Task { @MainActor in self?.moleInstallLog = Fmt.stripANSI(line) }
        }
        moleInstallLog = r.ok ? "Mole installed." : "brew install mole failed: \(r.tail)"
        if r.ok { await start() }
    }

    // MARK: Apps

    public func scanApps() async {
        guard !appsBusy else { return }
        appsBusy = true
        let list = await Mole.apps()
        if !list.isEmpty { apps = list; save() } else { show("App scan found nothing. Is Mole working? Try mo uninstall --list in Terminal.") }
        appsBusy = false
    }

    public func beginUninstall(_ app: InstalledApp) async {
        guard !app.isProtected else { return }
        busy = "Finding everything \(app.name) left on this Mac…"
        let items = await Mole.leftovers(of: app)
        let cask = await Mole.cask(forApp: app.path)
        busy = nil
        openWindow?()
        uninstallSheet = UninstallRequest(app: app, items: items, cask: cask)
    }

    public func finishUninstall(_ req: UninstallRequest) async {
        uninstallSheet = nil
        let app = req.app
        let chosen = req.items.filter(\.on)
        guard !chosen.isEmpty else { return }
        let plan = Plan(kind: "uninstall", title: "Uninstall \(app.name)", body: "", paths: chosen.map { PlannedPath(path: $0.path, size: $0.size) },
                        confirm: "Move to Trash")
        // The checklist sheet is the preview; pressing its button approves exactly what is ticked.
        let approved = Approved(plan)
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == app.path || (!app.bundle.isEmpty && $0.bundleIdentifier == app.bundle) }
        if !running.isEmpty {
            guard await ask(Plan(kind: "quit", title: "Quit \(app.name) first?",
                                 body: "\(app.name) is open. Burrow asks it to quit so nothing is in use while it is removed.",
                                 confirm: "Quit \(app.name)", destructive: false)) != nil else { return }
            running.forEach { $0.terminate() }
            try? await Task.sleep(for: .seconds(2.5))
        }
        busy = "Moving \(app.name) to the Trash…"
        let agents = chosen.filter { $0.path.contains("/LaunchAgents/") && $0.path.hasSuffix(".plist") }
        let out = await ActionRunner.trash(approved, history: nil) {
            for a in agents { _ = await Shell.sh("launchctl bootout gui/$(id -u) \(Shell.quote(a.path)) 2>/dev/null; true", timeout: 20) }
        }
        let appGone = !FileManager.default.fileExists(atPath: app.path)
        var cask: String?
        if appGone {
            apps?.removeAll { $0.path == app.path }
            if let token = req.cask, req.forgetCask, await Mole.forgetCask(token) {
                cask = token
                tools?.removeAll { $0.kind == .cask && $0.name == token }
            }
        }
        // Give the history line its app name (trash() wrote a generic one).
        rewriteLastHistory(note: "\(app.name), \(Fmt.plural(out.moved.count, "item"))\(cask.map { ", Homebrew cask \($0) removed" } ?? "")")
        busy = nil
        save()
        if !out.failed.isEmpty || !appGone {
            show(appGone ? "\(out.failed.count) item(s) could not be moved; they are probably owned by the system or in use."
                 : "\(app.name) itself could not be moved, usually because it was installed for all users. In Terminal: mo uninstall \"\(app.uninstallName)\"")
        } else {
            show("\(app.name) and \(Fmt.plural(max(0, out.moved.count - 1), "related item")) moved to the Trash (\(Fmt.bytes(out.freed))).")
        }
    }

    func rewriteLastHistory(note: String) {
        guard var text = try? String(contentsOf: Paths.history, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let last = lines.last, let data = last.data(using: .utf8), var e = try? JSONDecoder().decode(HistoryEntry.self, from: data) else { return }
        e.note = note
        if let d = try? JSONEncoder().encode(e) { lines[lines.count - 1] = String(decoding: d, as: UTF8.self) }
        text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: Paths.history, atomically: true, encoding: .utf8)
        history = History.load()
    }

    // MARK: Tools

    public func scanTools() async {
        guard !toolsBusy else { return }
        toolsBusy = true
        tools = await Scanners.tools()
        save()
        toolsBusy = false
    }

    public func uninstall(_ t: Tool) async {
        guard !t.isProtected else { return }
        let extra = t.kind == .brew && t.flag == 1 ? " Its background service is stopped first."
            : t.kind == .node ? " Every global npm package installed under this version goes with it."
            : t.kind == .brew ? " brew autoremove then removes dependencies nothing else needs." : ""
        guard let ok = await ask(Plan(kind: "tool-uninstall", title: "Uninstall \(t.name)?",
                                      body: "Runs the command below and removes it for good, not to the Trash.\(extra) You can reinstall it later the same way you installed it.",
                                      paths: [PlannedPath(path: t.commandShown, size: t.bytes)], commands: [t.command], confirm: "Uninstall")) else { return }
        busy = "Uninstalling \(t.name)…"
        let r = await ActionRunner.run(ok, timeout: 600, freed: t.bytes)
        busy = nil
        if r.ok {
            tools?.removeAll { $0.id == t.id }
            ActionRunner.record("tool-uninstall", freed: t.kind == .cask ? 0 : t.bytes, note: "\(t.kind.rawValue) \(t.name)")
            history = History.load()
            save()
            show("\(t.name) uninstalled.")
        } else {
            show("Could not uninstall \(t.name): \(r.tail)")
        }
    }

    // MARK: Old files

    public func scanOld() async {
        guard !oldBusy else { return }
        oldBusy = true
        old = await Scanners.oldFiles()
        oldSelected = Set(oldDefaults)
        save()
        oldBusy = false
    }

    public func trashOld() async {
        let items = (old ?? []).filter { oldSelected.contains($0.path) }
        guard !items.isEmpty, let ok = await ask(Plan(kind: "trash-old", title: "Move \(Fmt.plural(items.count, "file")) to the Trash?",
                                                      body: "You can put them back from the Trash until it is emptied.",
                                                      paths: items.map { PlannedPath.now($0.path, size: $0.size) }, confirm: "Move to Trash")) else { return }
        busy = "Moving to Trash…"
        let out = await ActionRunner.trash(ok)
        busy = nil
        old?.removeAll { out.moved.contains($0.path) }
        oldSelected.subtract(out.moved)
        history = History.load()
        save()
        show(out.summary)
    }

    // MARK: Developer

    public func scanDev() async {
        guard !devBusy else { return }
        devBusy = true
        let d = await Scanners.dev()
        dev = d
        devSelected = Set(d.buildFolders.filter { $0.idle >= 14 }.map(\.path))
        save()
        devBusy = false
    }

    public func trashDev() async {
        guard let dev else { return }
        var items = dev.buildFolders.filter { devSelected.contains($0.path) }
        if let dd = dev.derivedData, devSelected.contains(dd.path) { items.append(dd) }
        guard !items.isEmpty, let ok = await ask(Plan(kind: "trash-dev", title: "Move \(Fmt.plural(items.count, "build folder")) to the Trash?",
                                                      body: "Projects rebuild these on the next install or build (npm install, cargo build, Xcode).",
                                                      paths: items.map { PlannedPath(path: $0.path, size: $0.bytes) }, confirm: "Move to Trash")) else { return }
        busy = "Moving to Trash…"
        let out = await ActionRunner.trash(ok)
        busy = nil
        self.dev?.buildFolders.removeAll { out.moved.contains($0.path) }
        if let dd = dev.derivedData, out.moved.contains(dd.path) { self.dev?.derivedData = nil }
        devSelected.subtract(out.moved)
        history = History.load()
        save()
        show(out.summary)
    }

    /// A worktree with nothing uncommitted goes to the Trash (so it can come back),
    /// then `git worktree prune` clears git's record of it. The branch stays.
    public func removeWorktree(_ w: Worktree) async {
        if w.missing {
            guard let ok = await ask(Plan(kind: "worktree", title: "Prune missing worktree?", body: "The folder is already gone. This clears git's record of it.",
                                          paths: [PlannedPath(path: w.path, size: 0)], commands: ["git -C \(Shell.quote(w.repo)) worktree prune 2>&1"],
                                          confirm: "Prune", destructive: false)) else { return }
            let r = await ActionRunner.run(ok)
            if r.ok { dev?.worktrees.removeAll { $0.path == w.path }; ActionRunner.record("worktree", freed: 0, note: "pruned " + (w.path as NSString).lastPathComponent) }
            show(r.ok ? "Pruned." : r.tail)
        } else {
            let dirty = await Shell.sh("git -C \(Shell.quote(w.path)) status --porcelain 2>/dev/null | wc -l", timeout: 30)
            if (Int(dirty.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1) > 0 {
                show("That worktree has uncommitted changes now. Commit or stash first."); return
            }
            if let env = await ActionRunner.envFile(in: w.path) {
                show("That worktree holds \(Paths.short(env)). Burrow never moves .env files; move it out first, or remove the worktree with git."); return
            }
            guard let ok = await ask(Plan(kind: "worktree", title: "Move this worktree to the Trash?",
                                          body: "Nothing in it is uncommitted. Its folder goes to the Trash (ignored files such as node_modules too; a worktree holding a .env file is skipped), then git forgets the worktree. The branch and its commits stay in the repository.",
                                          paths: [PlannedPath(path: w.path, size: w.bytes)], confirm: "Move to Trash")) else { return }
            let out = await ActionRunner.trash(ok, history: (w.path as NSString).lastPathComponent)
            if !out.moved.isEmpty {
                _ = await Shell.sh("git -C \(Shell.quote(w.repo)) worktree prune 2>&1", timeout: 60)
                dev?.worktrees.removeAll { $0.path == w.path }
            }
            show(out.moved.isEmpty ? "Could not move it: \((out.skipped + out.failed).first?.why ?? "unknown")" : "Worktree moved to the Trash.")
        }
        history = History.load()
        save()
    }

    public func removeLaunchAgent(_ l: LaunchAgent) async {
        guard let ok = await ask(Plan(kind: "launch-agent", title: "Remove this launch agent?",
                                      body: "It stops now and no longer starts at login. The file goes to the Trash. If the app that made it is still installed, it may add it back.",
                                      paths: [PlannedPath(path: l.file, size: 0)], confirm: "Remove", note: l.label)) else { return }
        let out = await ActionRunner.trash(ok) {
            _ = await Shell.sh("launchctl bootout gui/$(id -u) \(Shell.quote(l.file)) 2>/dev/null; true", timeout: 30)
        }
        if !out.moved.isEmpty { dev?.launchAgents.removeAll { $0.file == l.file } }
        history = History.load()
        save()
        show(out.moved.isEmpty ? "Could not remove it." : "Launch agent removed.")
    }

    public func trimSessions(_ name: String) async {
        guard let o = dev?.oldSessions.first(where: { $0.name == name }), o.count > 0 else { return }
        let title = AgentDir.names[name] ?? name
        guard let ok = await ask(Plan(kind: "trim", title: "Move \(o.count) old transcripts to the Trash?",
                                      body: "\(title) transcripts older than 30 days (\(Fmt.bytes(o.bytes))). Memory folders are never touched. You will not be able to resume those sessions unless you put them back from the Trash.",
                                      paths: [PlannedPath(path: o.dir, size: o.bytes)],
                                      commands: ["/bin/bash \(Shell.quote(Paths.scripts.appendingPathComponent("trim-sessions.sh").path)) \(Shell.quote(o.dir)) \(Shell.quote(title))"],
                                      confirm: "Move to Trash")) else { return }
        busy = "Moving transcripts…"
        let r = await ActionRunner.run(ok, freed: o.bytes)
        busy = nil
        if r.ok, let i = dev?.oldSessions.firstIndex(where: { $0.name == name }) {
            dev?.oldSessions[i].count = 0
            dev?.oldSessions[i].bytes = 0
            ActionRunner.record("trim", freed: o.bytes, note: "\(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) files")
        }
        history = History.load()
        save()
        show(r.ok ? "Moved to the Trash." : "Could not move: \(r.tail)")
    }

    public func openSweep() {
        tab = .developer
        sweepPending = false
        try? FileManager.default.removeItem(at: Paths.sweepPending)
        Task { await scanDev() }
    }

    // MARK: Schedule

    public func toggle(_ r: Routine) async {
        let on = routinesOn[r.id] ?? false
        busy = on ? "Turning off \(r.name)…" : "Turning on \(r.name)…"
        do {
            if on { await Scheduler.turnOff(r); routinesOn[r.id] = false; show("\(r.name) is off.") }
            else {
                try await Scheduler.turnOn(r, when: when[r.id] ?? r.defaultWhen)
                routinesOn[r.id] = true
                show("\(r.name) is on." + (r.defaultWhen.kind == .interval ? "" : " Next: \((when[r.id] ?? r.defaultWhen).nextText)."))
            }
        } catch {
            show("Could not change the schedule: \(error.localizedDescription)")
        }
        busy = nil
        save()
    }

    public func setWhen(_ r: Routine, _ w: When) async {
        when[r.id] = w
        save()
        if routinesOn[r.id] == true {
            do { try await Scheduler.turnOn(r, when: w); show("Schedule updated. Next: \(w.nextText).") }
            catch { show("Could not update: \(error.localizedDescription)") }
        }
    }

    // MARK: Finder

    public func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

public struct UninstallRequest: Identifiable {
    public let id = UUID()
    public var app: InstalledApp
    public var items: [Leftover]
    /// The Homebrew cask that installed it; its record is removed after the app, if ticked.
    public var cask: String?
    public var forgetCask = true
}
