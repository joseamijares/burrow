import Foundation

/// Burrow's routines: launch agents (com.jamak.burrow.<id>) that run the bundled
/// scripts from ~/Library/Application Support/Burrow/scripts, so they work while
/// Burrow is closed. The same labels and scripts as the prototype, so routines
/// turned on there keep working.
public struct Routine: Identifiable, Sendable {
    public enum Mode: Sendable { case auto, asks, alert, logs }
    public var id: String
    public var name: String
    public var detail: String
    public var mode: Mode
    public var modeLabel: String
    public var defaultWhen: When

    public static let all: [Routine] = [
        Routine(id: "weekly-clean", name: "Weekly safe clean",
                detail: "Runs mo clean: app caches, logs and browser data. Leaves the Trash alone so you can still undo. Sends one notification with what it freed.",
                mode: .auto, modeLabel: "Runs on its own", defaultWhen: When(kind: .weekly, weekday: 0, day: 1, hour: 3, minute: 0)),
        Routine(id: "project-sweep", name: "Monthly project sweep",
                detail: "Reminds you to review idle build folders and old worktrees. Nothing is removed until you approve it here.",
                mode: .asks, modeLabel: "Asks first", defaultWhen: When(kind: .monthly, weekday: 0, day: 1, hour: 10, minute: 0)),
        Routine(id: "memory-watch", name: "Memory watch",
                detail: "Checks every 15 minutes. Alerts when macOS reports memory pressure with swap over 85% full, and names the app using the most.",
                mode: .alert, modeLabel: "Alert only", defaultWhen: When(kind: .interval, weekday: 0, day: 1, hour: 0, minute: 0)),
        Routine(id: "network-check", name: "Daily network check",
                detail: "Times your router, DNS and internet once a day and logs the result to History.",
                mode: .logs, modeLabel: "Logs only", defaultWhen: When(kind: .daily, weekday: 0, day: 1, hour: 9, minute: 0)),
    ]

    public var label: String { "com.jamak.burrow.\(id)" }
    public var plistURL: URL { Paths.launchAgents.appendingPathComponent("\(label).plist") }
    public var isOn: Bool { FileManager.default.fileExists(atPath: plistURL.path) }
}

public struct When: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case weekly, monthly, daily, interval }
    public var kind: Kind
    public var weekday: Int   // 0 = Sunday, as launchd's Weekday
    public var day: Int
    public var hour: Int
    public var minute: Int

    public static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public func next(after now: Date = Date()) -> Date? {
        var c = DateComponents()
        c.hour = hour; c.minute = minute
        switch kind {
        case .interval: return nil
        case .weekly: c.weekday = weekday + 1
        case .monthly: c.day = day
        case .daily: break
        }
        return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
    }

    public var nextText: String {
        guard let d = next() else { return "every 15 min" }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

public enum Scheduler {
    public static func plist(for r: Routine, when w: When) -> Data? {
        var o: [String: Any] = [
            "Label": r.label,
            "ProgramArguments": ["/bin/bash", Paths.scripts.appendingPathComponent("\(r.id).sh").path],
            "StandardOutPath": Paths.appSupport.appendingPathComponent("\(r.id).log").path,
            "StandardErrorPath": Paths.appSupport.appendingPathComponent("\(r.id).log").path,
        ]
        switch w.kind {
        case .interval: o["StartInterval"] = 900
        case .weekly: o["StartCalendarInterval"] = ["Weekday": w.weekday, "Hour": w.hour, "Minute": w.minute]
        case .monthly: o["StartCalendarInterval"] = ["Day": w.day, "Hour": w.hour, "Minute": w.minute]
        case .daily: o["StartCalendarInterval"] = ["Hour": w.hour, "Minute": w.minute]
        }
        return try? PropertyListSerialization.data(fromPropertyList: o, format: .xml, options: 0)
    }

    static var domain: String { "gui/\(getuid())" }

    /// Writes the plist and (re)loads it. Turning a routine on is the person's
    /// action (a switch), so it isn't previewed like a delete.
    public static func turnOn(_ r: Routine, when w: When) async throws {
        try FileManager.default.createDirectory(at: Paths.launchAgents, withIntermediateDirectories: true)
        guard let data = plist(for: r, when: w) else { throw NSError(domain: "Burrow", code: 1) }
        try data.write(to: r.plistURL, options: .atomic)
        let res = await Shell.sh("launchctl bootout \(domain)/\(r.label) 2>/dev/null; sleep 0.5; launchctl bootstrap \(domain) \(Shell.quote(r.plistURL.path)) 2>&1", timeout: 30)
        if !res.ok {
            try? FileManager.default.removeItem(at: r.plistURL)
            throw NSError(domain: "Burrow", code: Int(res.code), userInfo: [NSLocalizedDescriptionKey: res.tail.isEmpty ? "launchctl exited with \(res.code)" : res.tail])
        }
    }

    public static func turnOff(_ r: Routine) async {
        _ = await Shell.sh("launchctl bootout \(domain)/\(r.label) 2>/dev/null; true", timeout: 30)
        try? FileManager.default.removeItem(at: r.plistURL)
    }

    /// Rewrites the plists of routines that are on, so they point at this version's scripts.
    public static func refresh(_ when: [String: When]) {
        for r in Routine.all where r.isOn {
            if let data = plist(for: r, when: when[r.id] ?? r.defaultWhen) { try? data.write(to: r.plistURL, options: .atomic) }
        }
    }
}
