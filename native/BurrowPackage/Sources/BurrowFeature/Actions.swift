import Foundation

// MARK: - History

/// One line of history.jsonl, the same format the prototype and the launch-agent
/// scripts write ({"t":…,"kind":…,"freed":…,"how":…,"note":…}).
public struct HistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var t: Double
    public var kind: String
    public var freed: Double
    public var how: String
    public var note: String?
    public var code: Int?
    /// Where the per-path log for this action is (logs/…json), for actions Burrow ran itself.
    public var log: String?
    public var id: String { "\(t)-\(kind)-\(note ?? "")" }

    public static let labels = [
        "weekly-clean": "Weekly safe clean", "clean": "Clean", "project-sweep": "Project sweep reminder", "memory-alert": "Memory alert",
        "network-check": "Network check", "trash-old": "Old files to Trash", "trash-dev": "Build folders to Trash", "worktree": "Worktree to Trash",
        "launch-agent": "Launch agent removed", "uninstall": "App uninstalled", "tool-uninstall": "Tool uninstalled",
        "trim": "Old agent transcripts to Trash", "flush-dns": "DNS cache flushed",
    ]
    public var label: String { Self.labels[kind] ?? kind }
}

public enum History {
    public static func load() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: Paths.history, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        return text.split(separator: "\n").compactMap { line -> HistoryEntry? in
            guard let data = line.data(using: .utf8) else { return nil }
            if let e = try? dec.decode(HistoryEntry.self, from: data) { return e }
            // The shell scripts write "code" as a number and "freed" as an integer; be lenient.
            guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return HistoryEntry(t: (o["t"] as? NSNumber)?.doubleValue ?? 0, kind: o["kind"] as? String ?? "?",
                                freed: (o["freed"] as? NSNumber)?.doubleValue ?? 0, how: o["how"] as? String ?? "",
                                note: o["note"] as? String, code: (o["code"] as? NSNumber)?.intValue)
        }.sorted { $0.t > $1.t }
    }

    public static func append(_ e: HistoryEntry) {
        guard var data = try? JSONEncoder().encode(e) else { return }
        data.append(10)
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: Paths.history) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: Paths.history)
        }
    }
}

// MARK: - Plans and the one place they run

/// One path in a plan, with what Burrow saw when it made the preview.
public struct PlannedPath: Codable, Hashable, Sendable {
    public var path: String
    public var size: Double
    public var modified: Double?   // seconds since 1970 when previewed; nil = don't compare

    public init(path: String, size: Double, modified: Double? = nil) {
        self.path = path; self.size = size; self.modified = modified
    }

    public static func now(_ path: String, size: Double) -> PlannedPath {
        PlannedPath(path: path, size: size, modified: ActionRunner.modified(path))
    }
}

/// What the person saw before saying yes. Only `Approval` can make one, and only
/// `ActionRunner` takes one: no move to the Trash happens without a preview.
public struct Plan: Sendable, Identifiable {
    public let id = UUID()
    public var kind: String
    public var title: String
    public var body: String
    public var paths: [PlannedPath]
    public var commands: [String]
    public var confirm: String
    public var destructive: Bool
    public var note: String?

    public init(kind: String, title: String, body: String, paths: [PlannedPath] = [], commands: [String] = [],
                confirm: String, destructive: Bool = true, note: String? = nil) {
        self.kind = kind; self.title = title; self.body = body; self.paths = paths; self.commands = commands
        self.confirm = confirm; self.destructive = destructive; self.note = note
    }

    public var total: Double { paths.reduce(0) { $0 + $1.size } }
}

/// Made by the confirmation sheet when the person presses its button.
public struct Approved: Sendable {
    public let plan: Plan
    let at = Date()
    init(_ plan: Plan) { self.plan = plan }
}

public struct ActionOutcome: Sendable {
    public var moved: [String] = []
    public var skipped: [(path: String, why: String)] = []
    public var failed: [(path: String, why: String)] = []
    public var freed: Double = 0
    public var summary: String {
        var s = "Moved \(Fmt.plural(moved.count, "item")) to the Trash"
        if freed > 0 { s += " (\(Fmt.bytes(freed)))" }
        if !skipped.isEmpty { s += ", skipped \(skipped.count)" }
        if !failed.isEmpty { s += ", \(failed.count) could not be moved" }
        return s + "."
    }
}

public enum ActionRunner {
    /// How a path leaves: the Trash. Tests swap in a plain delete of their temp files.
    nonisolated(unsafe) static var mover: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    public static func modified(_ path: String) -> Double? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    /// A `.env` file inside a folder (worktrees and build output can hold them),
    /// not counting examples or anything under node_modules.
    static func envFile(in path: String) async -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
              (path as NSString).lastPathComponent != "node_modules", !path.hasSuffix(".app") else { return nil }
        let r = await Shell.run("/usr/bin/find", [path, "-name", "node_modules", "-prune", "-o", "(", "-name", ".env", "-o", "-name", ".env.*", ")",
                                                  "!", "-name", "*.example", "!", "-name", "*.sample", "!", "-name", "*.template", "-print", "-quit"], timeout: 60)
        let hit = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return hit.isEmpty ? nil : hit
    }

    /// Writes the plan to logs/ before acting, then each path's result after.
    static func writeLog(_ plan: Plan, outcome: ActionOutcome?, file: URL) {
        var o: [String: Any] = [
            "kind": plan.kind, "title": plan.title, "at": Date().timeIntervalSince1970,
            "planned": plan.paths.map { ["path": $0.path, "size": $0.size] }, "commands": plan.commands,
        ]
        if let outcome {
            o["moved"] = outcome.moved
            o["skipped"] = outcome.skipped.map { ["path": $0.path, "why": $0.why] }
            o["failed"] = outcome.failed.map { ["path": $0.path, "why": $0.why] }
            o["freed"] = outcome.freed
        } else {
            o["status"] = "started"
        }
        try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: file) }
    }

    static func logFile(_ kind: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return Paths.logs.appendingPathComponent("\(f.string(from: Date())) \(kind).json")
    }

    /// Moves each approved path to the Trash. Before each one it checks the
    /// never-touch rules again and that the file hasn't changed since the preview.
    @discardableResult
    public static func trash(_ approved: Approved, history note: String? = nil, before: (@Sendable () async -> Void)? = nil) async -> ActionOutcome {
        let plan = approved.plan
        let log = logFile(plan.kind)
        writeLog(plan, outcome: nil, file: log)
        await before?()
        var out = ActionOutcome()
        let fm = FileManager.default
        for item in plan.paths {
            if let why = Guard.refusal(for: item.path) { out.skipped.append((item.path, why)); continue }
            guard fm.fileExists(atPath: item.path) || (try? fm.destinationOfSymbolicLink(atPath: item.path)) != nil else {
                out.skipped.append((item.path, "already gone")); continue
            }
            if let then = item.modified, let now = modified(item.path), abs(now - then) > 1 {
                out.skipped.append((item.path, "changed since the preview")); continue
            }
            if let env = await envFile(in: item.path) {
                out.skipped.append((item.path, "holds a .env file (\(Paths.short(env))); Burrow never moves those")); continue
            }
            do {
                try mover(URL(fileURLWithPath: item.path))
                out.moved.append(item.path)
                out.freed += item.size
            } catch {
                out.failed.append((item.path, error.localizedDescription))
            }
        }
        writeLog(plan, outcome: out, file: log)
        History.append(HistoryEntry(t: Date().timeIntervalSince1970, kind: plan.kind, freed: out.freed, how: "manual",
                                    note: note ?? plan.note ?? Fmt.plural(out.moved.count, "item"), log: log.lastPathComponent))
        return out
    }

    /// Runs an approved command plan (Mole clean, a tool's uninstaller, git, launchctl),
    /// logging it the same way. The commands are the ones the preview showed.
    public static func run(_ approved: Approved, timeout: TimeInterval = 600, freed: Double = 0,
                           onLine: (@Sendable (String) -> Void)? = nil) async -> Shell.Result {
        let plan = approved.plan
        let log = logFile(plan.kind)
        writeLog(plan, outcome: nil, file: log)
        var last = Shell.Result(code: 0, stdout: "", stderr: "")
        for c in plan.commands {
            last = await Shell.sh(c, timeout: timeout, onLine: onLine)
            if !last.ok { break }
        }
        var o = ActionOutcome()
        o.freed = last.ok ? freed : 0
        if !last.ok { o.failed = [("command", last.tail)] }
        writeLog(plan, outcome: o, file: log)
        return last
    }

    /// For results the caller measures itself (Mole's clean).
    public static func record(_ kind: String, freed: Double, note: String?, code: Int? = nil) {
        History.append(HistoryEntry(t: Date().timeIntervalSince1970, kind: kind, freed: freed, how: "manual", note: note, code: code))
    }
}
