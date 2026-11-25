import CoreText
import Foundation

/// Where Burrow keeps its files. The folder is shared with the Claude-app
/// prototype on purpose: history.jsonl and the com.jamak.burrow.* launch agents
/// carry over. The native app's own state is in native-state.json.
public enum Paths {
    public static let home = NSHomeDirectory()
    /// Tests point this at a temporary folder, so they never write to the real history.
    nonisolated(unsafe) static var supportOverride: URL?
    public static var appSupport: URL { supportOverride ?? URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Burrow") }
    public static var scripts: URL { appSupport.appendingPathComponent("scripts") }
    public static var logs: URL { appSupport.appendingPathComponent("logs") }
    public static var state: URL { appSupport.appendingPathComponent("native-state.json") }
    public static var history: URL { appSupport.appendingPathComponent("history.jsonl") }
    public static var whitelistJournal: URL { appSupport.appendingPathComponent("whitelist.restore.json") }
    public static var sweepPending: URL { appSupport.appendingPathComponent("sweep-pending") }
    nonisolated(unsafe) static var moleConfigOverride: URL?
    public static var moleConfig: URL { moleConfigOverride ?? URL(fileURLWithPath: home).appendingPathComponent(".config/mole") }
    public static var whitelist: URL { moleConfig.appendingPathComponent("whitelist") }
    public static var cleanList: URL { moleConfig.appendingPathComponent("clean-list.txt") }
    public static let launchAgents = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents")

    /// "~/…" for display.
    public static func short(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Copies the bundled scripts to the support folder, where launch agents and
    /// `Shell.script` run them from (a stable path, whatever the app is called or moved to).
    public static func installScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        guard let src = Bundle.module.url(forResource: "Scripts", withExtension: nil) else { return }
        for name in try fm.contentsOfDirectory(atPath: src.path) where name.hasSuffix(".sh") {
            let data = try Data(contentsOf: src.appendingPathComponent(name))
            let dest = scripts.appendingPathComponent(name)
            if (try? Data(contentsOf: dest)) != data { try data.write(to: dest, options: .atomic) }
        }
    }
}

public enum Fmt {
    public static let GB: Double = 1024 * 1024 * 1024

    /// 4.4 GB, 812 MB, 12 KB.
    public static func bytes(_ b: Double?) -> String {
        guard var b, b.isFinite else { return "–" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var i = 0
        while b >= 1024 && i < 4 { b /= 1024; i += 1 }
        let n = i == 0 || b >= 100 ? String(format: "%.0f", b) : String(format: "%.1f", b)
        return "\(n) \(units[i])"
    }

    public static func bytes(_ b: Int64) -> String { bytes(Double(b)) }

    /// "41.4MB", "1.03 GB", "225KB" → bytes.
    public static func parseSize(_ s: String) -> Double {
        guard let m = s.firstMatch(of: /([\d.]+)\s*([KMGT]?)i?B/.ignoresCase()), let n = Double(m.1) else { return 0 }
        let power = ["", "K", "M", "G", "T"].firstIndex(of: m.2.uppercased()) ?? 0
        return n * pow(1024, Double(power))
    }

    public static func stripANSI(_ s: String) -> String {
        s.replacing(/\x1b\[[0-9;?]*[A-Za-z]/, with: "")
    }

    /// Whole days since a Unix time, or nil when unknown (0).
    public static func days(_ t: Double, now: Date = Date()) -> Int? {
        t > 0 ? Int((now.timeIntervalSince1970 - t) / 86400) : nil
    }

    public static func ago(_ t: Double) -> String {
        guard let d = days(t) else { return "unknown" }
        if d < 1 { return "today" }
        if d == 1 { return "yesterday" }
        if d < 60 { return "\(d) days ago" }
        let months = Int((Double(d) / 30).rounded())
        return months < 24 ? "\(months) months ago" : "\(Int((Double(d) / 365).rounded())) years ago"
    }

    public static func plural(_ n: Int, _ word: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? word : many ?? word + "s")"
    }
}

/// Schibsted Grotesk and JetBrains Mono, bundled (SIL Open Font License, see Fonts/OFL-*.txt),
/// with Helvetica Neue for body text, as in the Paper file's tokens.
public enum Fonts {
    nonisolated(unsafe) private static var registered = false
    public static func register() {
        guard !registered, let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        registered = true
        for url in files where url.pathExtension == "woff2" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
