import Foundation

// Parsers for Mole's output and Burrow's scan scripts, ported from the
// prototype (app/burrow.html v15). Each has a fixture test.

// MARK: - mo clean --dry-run → ~/.config/mole/clean-list.txt

public struct CleanItem: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var size: Double
    public var count: Int?
    public var id: String { path }
}

public struct CleanCategory: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var items: [CleanItem]
    public var size: Double { items.reduce(0) { $0 + $1.size } }
    public var id: String { name }
}

public struct CleanScan: Codable, Sendable {
    public var categories: [CleanCategory]
    public var at: Date
    public var total: Double { categories.reduce(0) { $0 + $1.size } }

    /// `=== Category ===` headers, then `path  # 41.4MB[, 12 items]` lines.
    public static func parse(_ text: String, at: Date = Date()) -> CleanScan {
        var cats: [CleanCategory] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let m = line.wholeMatch(of: /===\s*(.+?)\s*===/) {
                cats.append(CleanCategory(name: String(m.1), items: []))
                continue
            }
            if let m = line.firstMatch(of: /^(.+?)\s+#\s+([\d.]+\s*[KMGT]?B)(?:,\s*(\d+)\s+items?)?/), !cats.isEmpty {
                cats[cats.count - 1].items.append(CleanItem(path: String(m.1), size: Fmt.parseSize(String(m.2)), count: m.3.flatMap { Int($0) }))
            }
        }
        return CleanScan(categories: cats.filter { !$0.items.isEmpty }, at: at)
    }
}

/// Mole logs "clean run=… session ended at …, N items, X" in its operations log: the real total freed.
public func moleLoggedFreed(_ log: String, within: TimeInterval = 600, now: Date = Date()) -> Double? {
    let matches = log.matches(of: /clean run=[^\]\s]+ session ended at ([^,]+), \d+ items, ([\d.]+\s*[KMGT]?B)/)
    guard let last = matches.last else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let when = f.date(from: String(last.1)), now.timeIntervalSince(when) < within else { return nil }
    return Fmt.parseSize(String(last.2))
}

// MARK: - mo status --json

public struct MoleStatus: Codable, Sendable {
    public struct Memory: Codable, Sendable {
        public var used: Double?; public var total: Double?; public var used_percent: Double?
        public var swap_used: Double?; public var swap_total: Double?; public var pressure: String?
    }
    public struct CPU: Codable, Sendable { public var usage: Double?; public var load1: Double? }
    public struct Disk: Codable, Sendable {
        public var mount: String?; public var used: Double?; public var total: Double?
        public var used_percent: Double?; public var purgeable: Double?
    }
    public struct Hardware: Codable, Sendable {
        public var model: String?; public var cpu_model: String?; public var total_ram: String?; public var os_version: String?
    }
    public struct Net: Codable, Sendable { public var name: String; public var ip: String?; public var rx_rate_mbs: Double?; public var tx_rate_mbs: Double? }
    public struct Proxy: Codable, Sendable { public var enabled: Bool?; public var type: String?; public var host: String? }
    public struct Battery: Codable, Sendable {
        public var percent: Double?; public var status: String?; public var health: String?; public var cycle_count: Int?; public var capacity: Double?
    }
    public var health_score: Int?
    public var health_score_msg: String?
    public var uptime: String?
    public var procs: Int?
    public var hardware: Hardware?
    public var cpu: CPU?
    public var memory: Memory?
    public var disks: [Disk]?
    public var network: [Net]?
    public var proxy: Proxy?
    public var batteries: [Battery]?

    public static func parse(_ text: String) -> MoleStatus? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        return try? JSONDecoder().decode(MoleStatus.self, from: Data(text[start...].utf8))
    }

    public var disk: Disk? { disks?.first(where: { $0.mount == "/" }) ?? disks?.first }
    public var online: Bool { (network ?? []).contains { ($0.ip ?? "").isEmpty == false } }
    public var networkSummary: String {
        var s = online ? "Online" : "Offline"
        if proxy?.enabled == true { s += proxy?.type == "TUN" ? " · VPN on" : " · proxy on" }
        return s
    }
}

// MARK: - mo uninstall --list

public struct InstalledApp: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var bundle: String
    public var source: String
    public var uninstallName: String
    public var path: String
    public var size: Double
    public var lastUsed: Double   // Unix time; 0 = no usage record, which is never "unused"
    public var id: String { path }

    /// Apple apps, Claude and Burrow are never offered for uninstall.
    public var isProtected: Bool {
        name.range(of: #"^(Claude|Burrow)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || bundle.hasPrefix("com.apple.") || path.contains("/Claude Apps/") || bundle.hasPrefix("com.jamak.burrow")
    }

    public func isUnused(now: Date = Date()) -> Bool {
        guard let d = Fmt.days(lastUsed, now: now) else { return false }
        return d >= 90 && !isProtected
    }
}

public struct UninstallListEntry: Codable, Sendable {
    public var name: String
    public var bundle_id: String?
    public var source: String?
    public var uninstall_name: String?
    public var path: String
    public var size: String?

    public static func parse(_ text: String) -> [UninstallListEntry] {
        guard let start = text.firstIndex(of: "[") else { return [] }
        return (try? JSONDecoder().decode([UninstallListEntry].self, from: Data(text[start...].utf8))) ?? []
    }
}

/// `mdls -raw` prints "2025-03-02 10:11:12 +0000", or "(null)" when Spotlight has no date.
public func parseMdlsDate(_ s: String) -> Double {
    let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard v.firstMatch(of: /^\d{4}-\d\d-\d\d/) != nil else { return 0 }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return f.date(from: v)?.timeIntervalSince1970 ?? 0
}

// MARK: - printf 'y\n\n' | mo uninstall --dry-run --with-data NAME

public enum LeftoverGroup: String, Codable, Sendable { case app, data, shared }

public struct Leftover: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var size: Double
    public var group: LeftoverGroup
    public var on: Bool
    public var id: String { path }
}

/// Lines like `  ✓ /Applications/X.app · 27.1MB` and `  ✓ ~/Library/Containers/x`.
/// "Review only:" lines (system receipts) don't start with a path and are skipped.
public func parseUninstallPreview(_ text: String, appPath: String, home: String = Paths.home) -> [(path: String, size: Double, symbol: String)] {
    var out: [(String, Double, String)] = []
    let clean = Fmt.stripANSI(text).replacingOccurrences(of: "\r", with: "\n")
    for line in clean.split(separator: "\n") {
        guard let m = String(line).wholeMatch(of: /\s*(\S)\s+((?:\/|~\/).+?)(?:\s+·\s+([\d.]+\s*[KMGT]?B))?\s*/) else { continue }
        var p = String(m.2)
        if p.hasPrefix("~/") { p = home + p.dropFirst(1) }
        out.append((p, m.3.map { Fmt.parseSize(String($0)) } ?? 0, String(m.1)))
    }
    return out
}

/// The leftover checklist: Mole's preview plus Burrow's own appfind script.
/// Group Containers are shared by one developer's apps, so they start unticked.
public struct LeftoverList {
    public private(set) var items: [String: Leftover] = [:]
    let home: String
    public init(home: String = Paths.home) { self.home = home }

    public mutating func add(_ rawPath: String, size: Double, group: LeftoverGroup) {
        var p = rawPath
        if p.hasPrefix("~/") { p = home + p.dropFirst(1) }
        while p.hasSuffix("/") { p.removeLast() }
        guard p.hasPrefix("/"), p != home else { return }
        if var prev = items[p] {
            if prev.size == 0 && size > 0 { prev.size = size }
            if prev.group == .shared && group != .shared { prev.group = group; prev.on = true }
            items[p] = prev
            return
        }
        items[p] = Leftover(path: p, size: size, group: group, on: group != .shared)
    }

    public var sorted: [Leftover] {
        items.values.sorted { a, b in
            if (a.group == .app) != (b.group == .app) { return a.group == .app }
            return a.size > b.size
        }
    }

    public static func group(for path: String, appPath: String, symbol: String = "") -> LeftoverGroup {
        if path == appPath { return .app }
        return path.contains("/Group Containers/") ? .shared : .data
    }
}

/// appfind.sh: `KB\tpath` lines.
public func parseAppFind(_ text: String) -> [(path: String, size: Double)] {
    text.split(separator: "\n").compactMap { l in
        guard let i = l.firstIndex(of: "\t") else { return nil }
        return (String(l[l.index(after: i)...]), (Double(l[..<i]) ?? 0) * 1024)
    }
}

/// apps-meta.sh: `path\tKB\ticon` lines.
public func parseAppsMeta(_ text: String) -> [String: Double] {
    var out: [String: Double] = [:]
    for l in text.split(separator: "\n") {
        let p = l.split(separator: "\t", omittingEmptySubsequences: false)
        if p.count >= 2, let kb = Double(p[1]) { out[String(p[0])] = kb * 1024 }
    }
    return out
}

// MARK: - oldfiles.sh

public struct OldFile: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case installer = "I", large = "L" }
    public var kind: Kind
    public var path: String
    public var size: Double
    public var last: Double
    public var id: String { path }
}

/// `kind\tsize\tlastUsed\tmtime\tpath`. Large files opened in the last 120 days are dropped;
/// a file that is both an installer and large is listed once, as an installer.
public func parseOldFiles(_ text: String, now: Date = Date()) -> [OldFile] {
    let cutoff = now.timeIntervalSince1970 - 120 * 86400
    var seen: [String: OldFile] = [:]
    for l in text.split(separator: "\n") {
        let p = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 5, let kind = OldFile.Kind(rawValue: p[0]) else { continue }
        let path = p[4...].joined(separator: "\t")
        let last = max(Double(p[2]) ?? 0, Double(p[3]) ?? 0)
        if kind == .large && last > cutoff { continue }
        if seen[path]?.kind == .installer { continue }
        seen[path] = OldFile(kind: kind, path: path, size: Double(p[1]) ?? 0, last: last)
    }
    return seen.values.sorted { $0.size > $1.size }
}

// MARK: - devscan.sh

public struct Worktree: Codable, Hashable, Sendable, Identifiable {
    public var repo: String, path: String, branch: String
    public var last: Double, dirty: Int, merged: Bool, kb: Double, missing: Bool
    public var id: String { path }
    public var idle: Int { Fmt.days(last) ?? 0 }
    public var bytes: Double { kb * 1024 }
}

public struct BuildFolder: Codable, Hashable, Sendable, Identifiable {
    public var path: String, last: Double, kb: Double
    public var id: String { path }
    public var idle: Int { Fmt.days(last) ?? 0 }
    public var bytes: Double { kb * 1024 }
}

public struct AgentDir: Codable, Hashable, Sendable, Identifiable {
    public var name: String, kb: Double
    public var id: String { name }
    public static let names = [".claude": "Claude Code", ".codex": "Codex", ".cursor": "Cursor", ".gemini": "Gemini CLI", ".ollama": "Ollama",
                               ".windsurf": "Windsurf", ".continue": "Continue", ".aider": "Aider", ".copilot": "Copilot"]
    public var title: String { Self.names[name] ?? name }
}

public struct OldSessions: Codable, Hashable, Sendable { public var name: String, dir: String, count: Int, bytes: Double }

public struct LaunchAgent: Codable, Hashable, Sendable, Identifiable {
    public var file: String, label: String, program: String, exists: Bool, pid: String
    public var id: String { file }
    public var isBurrows: Bool { label.hasPrefix("com.jamak.burrow.") }
    public var running: Bool { pid != "-" && pid != "0" && !pid.isEmpty }
}

public struct DevScan: Codable, Sendable {
    public var worktrees: [Worktree] = []
    public var buildFolders: [BuildFolder] = []
    public var derivedData: BuildFolder?
    public var agentDirs: [AgentDir] = []
    public var oldSessions: [OldSessions] = []
    public var launchAgents: [LaunchAgent] = []
    public var at = Date()

    public static func parse(_ text: String) -> DevScan {
        var d = DevScan()
        for l in text.split(separator: "\n") {
            let p = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            func n(_ i: Int) -> Double { i < p.count ? Double(p[i]) ?? 0 : 0 }
            switch p.first {
            case "W" where p.count >= 9:
                d.worktrees.append(Worktree(repo: p[1], path: p[2], branch: p[3], last: max(n(4), n(5)), dirty: Int(n(6)),
                                            merged: p[7] == "1", kb: n(8), missing: n(5) == 0 && n(8) == 0))
            case "A" where p.count >= 5:
                d.buildFolders.append(BuildFolder(path: p[1], last: max(n(2), n(3)), kb: n(4)))
            case "X" where p.count >= 3 && n(2) > 51200:
                d.derivedData = BuildFolder(path: p[1], last: 0, kb: n(2))
            case "G" where p.count >= 3:
                d.agentDirs.append(AgentDir(name: p[1], kb: n(2)))
            case "O" where p.count >= 3:
                d.oldSessions.append(OldSessions(name: p[1], dir: p[2], count: Int(n(3)), bytes: n(4)))
            case "L" where p.count >= 6:
                d.launchAgents.append(LaunchAgent(file: p[1], label: p[2], program: p[3], exists: p[4] == "1", pid: p[5]))
            default: break
            }
        }
        d.agentDirs.sort { $0.kb > $1.kb }
        return d
    }

    public var staleWorktrees: [Worktree] { worktrees.filter { $0.idle >= 30 } }
    public var idleBuildBytes: Double {
        buildFolders.filter { $0.idle >= 14 }.reduce(0) { $0 + $1.bytes } + (derivedData?.bytes ?? 0)
    }
}

// MARK: - tools.sh

public struct Tool: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case brew, cask, npm, node, pipx, uv, cargo }
    public var kind: Kind, name: String, version: String
    public var installed: Double, kb: Double, flag: Int, location: String
    public var id: String { "\(kind.rawValue)|\(name)|\(location)" }
    public var bytes: Double { kb * 1024 }

    /// Mole itself and the default nvm Node are never offered.
    public var isProtected: Bool { (kind == .brew && name.range(of: #"(^|/)mole$"#, options: .regularExpression) != nil) || (kind == .node && flag == 1) }

    /// What Burrow runs; also shown in the preview.
    public var command: String {
        let q = Shell.quote
        switch kind {
        case .brew: return (flag == 1 ? "brew services stop \(q(name)) >/dev/null 2>&1; " : "") + "brew uninstall \(q(name)) 2>&1 && brew autoremove 2>&1"
        case .cask: return "brew uninstall --cask \(q(name)) 2>&1"
        case .npm: return "PATH=\(q(location + "/bin")):\"$PATH\" npm uninstall -g \(q(name)) 2>&1"
        case .pipx: return "pipx uninstall \(q(name)) 2>&1"
        case .uv: return "uv tool uninstall \(q(name)) 2>&1"
        case .cargo: return "cargo uninstall \(q(name)) 2>&1"
        case .node: return ". \"$HOME/.nvm/nvm.sh\" && nvm uninstall \(q(name)) 2>&1"
        }
    }

    public var commandShown: String {
        switch kind {
        case .brew: return "brew uninstall \(name) && brew autoremove"
        case .cask: return "brew uninstall --cask \(name)"
        case .npm: return "npm uninstall -g \(name) (\(Tool.whereLabel(location)))"
        case .pipx: return "pipx uninstall \(name)"
        case .uv: return "uv tool uninstall \(name)"
        case .cargo: return "cargo uninstall \(name)"
        case .node: return "nvm uninstall \(name)"
        }
    }

    public static func whereLabel(_ w: String) -> String {
        if w.isEmpty { return "" }
        if w.contains("/.nvm/versions/node/") { return "nvm " + (w.split(separator: "/").last.map(String.init) ?? "") }
        if w == Paths.home + "/.local" { return "~/.local" }
        if w.hasPrefix("/opt/homebrew") { return "Homebrew Node" }
        return Paths.short(w)
    }

    public static let groups: [(Kind, String, String)] = [
        (.brew, "Homebrew formulas", "Installed with brew install. Dependencies are not listed; brew autoremove clears the ones nothing needs anymore."),
        (.cask, "Homebrew casks", "Apps and binaries installed with brew install --cask."),
        (.npm, "Global npm packages", "Installed with npm install -g, per Node install."),
        (.node, "Node versions (nvm)", "Each nvm version keeps its own global packages."),
        (.pipx, "Python tools (pipx)", ""), (.uv, "Python tools (uv)", ""), (.cargo, "Rust tools (cargo install)", ""),
    ]
}

/// `kind\tname\tversion\tinstalled\tKB\tflag\twhere`. Homebrew bottles carry 1985 timestamps,
/// so tools.sh reads INSTALL_RECEIPT.json; anything before 2000 is treated as unknown.
public func parseTools(_ text: String) -> [Tool] {
    text.split(separator: "\n").compactMap { l in
        let p = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 6, let kind = Tool.Kind(rawValue: p[0]) else { return nil }
        let t = Double(p[3]) ?? 0
        return Tool(kind: kind, name: p[1], version: p[2], installed: t > 946_684_800 ? t : 0, kb: Double(p[4]) ?? 0,
                    flag: Int(p[5]) ?? 0, location: p.count > 6 ? p[6] : "")
    }
}

// MARK: - netcheck.sh

public struct NetCheck: Codable, Sendable { public var at = Date(); public var router: Int?; public var dns: Int?; public var internet: Int? }

public func parseNetCheck(_ text: String) -> NetCheck {
    var n = NetCheck()
    for l in text.split(separator: "\n") {
        let p = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        switch p.first {
        case "gw": n.router = p.count > 2 ? Double(p[2]).map { Int($0.rounded()) } : nil
        case "net": n.internet = p.count > 2 ? Double(p[2]).map { Int($0.rounded()) } : nil
        case "dns": n.dns = p.count > 1 ? Int(p[1]) : nil
        default: break
        }
    }
    return n
}

// MARK: - ps -axo pid=,rss=,comm=

public struct ProcessGroup: Hashable, Sendable, Identifiable {
    public var name: String
    public var rss: Double
    public var count: Int
    /// The .app bundle, for apps in /Applications (the only ones Burrow offers to quit).
    public var appPath: String?
    public var id: String { name }
}

public func parseProcesses(_ text: String, limit: Int = 8) -> [ProcessGroup] {
    var map: [String: ProcessGroup] = [:]
    for l in text.split(separator: "\n") {
        guard let m = String(l).wholeMatch(of: /\s*(\d+)\s+(\d+)\s+(.+)/), let rss = Double(m.2) else { continue }
        let path = String(m.3)
        let app = path.firstMatch(of: /^(.*?\/([^\/]+)\.app)\//)
        let name = app.map { String($0.2) } ?? (path.split(separator: "/").last.map(String.init) ?? path)
        var g = map[name] ?? ProcessGroup(name: name, rss: 0, count: 0, appPath: nil)
        if let app, path.hasPrefix("/Applications"), !name.hasPrefix("Claude") { g.appPath = String(app.1) }
        g.rss += rss * 1024
        g.count += 1
        map[name] = g
    }
    return map.values.filter { $0.name != "Burrow" }.sorted { $0.rss > $1.rss }.prefix(limit).map { $0 }
}
