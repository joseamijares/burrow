import AppKit
import Foundation

/// Mole, run as a separate program (the user's installed `mo`; Burrow doesn't bundle it).
public enum Mole {
    public static func executable() async -> String? {
        let r = await Shell.sh("command -v mo", timeout: 15)
        let p = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }

    public static func version() async -> (version: String, viaBrew: Bool) {
        let b = await Shell.sh("brew list --versions mole 2>/dev/null", timeout: 20)
        if let m = b.stdout.firstMatch(of: /(\d+\.\d+(?:\.\d+)?)/) { return (String(m.1), true) }
        let v = await Shell.sh("mo --version 2>&1", timeout: 15)
        return (Fmt.stripANSI(v.stdout).firstMatch(of: /(\d+\.\d+(?:\.\d+)?)/).map { String($0.1) } ?? "", false)
    }

    public static func latest() async -> String? {
        let r = await Shell.sh("curl -fsSL --max-time 10 https://api.github.com/repos/tw93/Mole/releases/latest | grep -m1 '\"tag_name\"'", timeout: 20)
        return r.stdout.firstMatch(of: /"tag_name"\s*:\s*"v?([\d.]+)"/).map { String($0.1) }
    }

    public static func status() async -> MoleStatus? {
        MoleStatus.parse((await Shell.sh("mo status --json 2>/dev/null", timeout: 30)).stdout)
    }

    /// The dry run. Deletes nothing; Mole writes the plan to ~/.config/mole/clean-list.txt.
    /// `progress` gets Mole's "➤ section" lines.
    public static func dryRun(progress: @escaping @Sendable (String) -> Void) async -> CleanScan {
        _ = await Shell.sh("mo clean --dry-run 2>&1", timeout: 900) { line in
            let t = Fmt.stripANSI(line).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("➤") { progress(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        }
        let text = (try? String(contentsOf: Paths.cleanList, encoding: .utf8)) ?? ""
        return CleanScan.parse(text)
    }

    /// The real clean, for an approved plan. Burrow writes a temporary whitelist for
    /// this run: your whitelist (or, if you have none, Mole's own defaults, which a
    /// whitelist file would otherwise switch off), the paths you unticked, and the
    /// cloud folders Burrow never cleans. The original is journaled first and put back
    /// after, and on the next launch if Burrow was quit mid-run (`restoreWhitelistIfInterrupted`).
    public static func clean(_ approved: Approved, keep: [String]) async -> (result: Shell.Result, freed: Double) {
        let fm = FileManager.default
        let had = fm.fileExists(atPath: Paths.whitelist.path)
        let original = had ? ((try? String(contentsOf: Paths.whitelist, encoding: .utf8)) ?? "") : ""
        let journal = try? JSONSerialization.data(withJSONObject: ["had": had, "orig": original])
        try? fm.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        try? journal?.write(to: Paths.whitelistJournal)
        try? fm.createDirectory(at: Paths.moleConfig, withIntermediateDirectories: true)
        try? temporaryWhitelist(original: had ? original : nil, keep: keep).write(to: Paths.whitelist, atomically: true, encoding: .utf8)
        let before = freeBytes()
        let result = await ActionRunner.run(approved, timeout: 30 * 60)
        let after = freeBytes()
        restoreWhitelist(had: had, original: original)
        var freed = loggedFreed()
        if freed == nil, let m = Fmt.stripANSI(result.stdout).firstMatch(of: /Space freed:\s*([\d.]+\s*[KMGT]?B)/.ignoresCase()) {
            freed = Fmt.parseSize(String(m.1))
        }
        return (result, freed ?? max(0, after - before))
    }

    /// Cloud folders: deleting there deletes on every device.
    static var cloudRoots: [String] {
        let h = Paths.home
        return ["\(h)/Library/CloudStorage", "\(h)/Library/CloudStorage/*", "\(h)/Library/Mobile Documents*"]
    }

    static func temporaryWhitelist(original: String?, keep: [String]) -> String {
        var text = original ?? (defaultWhitelist().joined(separator: "\n") + "\n")
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "# Burrow, this run only\n"
        text += (keep.flatMap { [$0, $0 + "/*"] } + cloudRoots).joined(separator: "\n") + "\n"
        return text
    }

    /// Mole's built-in whitelist (DEFAULT_WHITELIST_PATTERNS in its lib/core/base.sh),
    /// which applies only while ~/.config/mole/whitelist doesn't exist. Read from the
    /// installed Mole; the copy below is Mole 1.74's, for when it can't be found.
    static func defaultWhitelist() -> [String] {
        let h = Paths.home
        let fallback = ["Library/Caches/ms-playwright*", "Library/Caches/camoufox*", "Library/Caches/Cypress*", ".gradle/caches/*", ".gradle/daemon/*",
                        ".ollama/models/*", "Library/Caches/com.nssurge.surge-mac/*", "Library/Application Support/com.nssurge.surge-mac/*",
                        "Library/Caches/org.R-project.R/R/renv/*", "Library/Caches/JetBrains*", "Library/Caches/com.jetbrains.toolbox*",
                        "Library/Caches/tealdeer/tldr-pages", "Library/Application Support/JetBrains*", "Library/Caches/com.apple.finder",
                        "Library/Mobile Documents*"].map { "\(h)/\($0)" } + ["FINDER_METADATA"]
        for mo in ["/opt/homebrew/bin/mo", "/usr/local/bin/mo"] {
            guard let real = try? FileManager.default.destinationOfSymbolicLink(atPath: mo) else { continue }
            let bin = URL(fileURLWithPath: real, relativeTo: URL(fileURLWithPath: mo).deletingLastPathComponent()).standardizedFileURL
            let base = bin.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("libexec/lib/core/base.sh")
            guard let text = try? String(contentsOf: base, encoding: .utf8),
                  let block = text.firstMatch(of: /DEFAULT_WHITELIST_PATTERNS=\(([^)]*)\)/) else { continue }
            let items = block.1.matches(of: /"([^"]+)"/).map { String($0.1).replacingOccurrences(of: "$HOME", with: h)
                .replacingOccurrences(of: "$FINDER_METADATA_SENTINEL", with: "FINDER_METADATA") }
            if !items.isEmpty { return items }
        }
        return fallback
    }

    static func restoreWhitelist(had: Bool, original: String) {
        if had { try? original.write(to: Paths.whitelist, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: Paths.whitelist) }
        try? FileManager.default.removeItem(at: Paths.whitelistJournal)
    }

    public static func restoreWhitelistIfInterrupted() {
        guard let data = try? Data(contentsOf: Paths.whitelistJournal),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        restoreWhitelist(had: o["had"] as? Bool ?? false, original: o["orig"] as? String ?? "")
    }

    /// Adds paths to Mole's whitelist for good ("Always keep unticked").
    public static func keepForever(_ paths: [String]) {
        var text = (try? String(contentsOf: Paths.whitelist, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += paths.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: Paths.moleConfig, withIntermediateDirectories: true)
        try? text.write(to: Paths.whitelist, atomically: true, encoding: .utf8)
    }

    static func loggedFreed() -> Double? {
        for p in ["Library/Logs/mole/operations.log", ".config/mole/operations.log"] {
            if let t = try? String(contentsOfFile: Paths.home + "/" + p, encoding: .utf8), let f = moleLoggedFreed(t) { return f }
        }
        return nil
    }

    public static func freeBytes() -> Double {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Double(v?.volumeAvailableCapacity ?? 0)
    }

    /// What `du` says a folder holds, for opening an item in the Clean list.
    public static func children(of path: String) async -> [CleanItem] {
        let r = await Shell.sh("cd \(Shell.quote(path)) 2>/dev/null && du -sk -- * .[!.]* 2>/dev/null | sort -nr | head -12", timeout: 60)
        return r.stdout.split(separator: "\n").compactMap { l in
            guard let m = String(l).wholeMatch(of: /(\d+)\t(.+)/), let kb = Double(m.1), kb * 1024 > 1024 * 1024 else { return nil }
            return CleanItem(path: path + "/" + m.2, size: kb * 1024, count: nil)
        }
    }

    // MARK: Apps

    public static func apps() async -> [InstalledApp] {
        let list = UninstallListEntry.parse((await Shell.sh("mo uninstall --list 2>/dev/null", timeout: 180)).stdout)
        guard !list.isEmpty else { return [] }
        let mdls = await Shell.sh("while IFS= read -r p; do printf '%s\\t%s\\n' \"$p\" \"$(mdls -name kMDItemLastUsedDate -raw \"$p\" 2>/dev/null)\"; done",
                                  input: list.map(\.path).joined(separator: "\n") + "\n", timeout: 180)
        var last: [String: Double] = [:]
        for l in mdls.stdout.split(separator: "\n") {
            guard let i = l.lastIndex(of: "\t") else { continue }
            last[String(l[..<i])] = parseMdlsDate(String(l[l.index(after: i)...]))
        }
        let meta = parseAppsMeta((await Shell.script("apps-meta", input: list.map(\.path).joined(separator: "\n") + "\n", timeout: 400)).stdout)
        return list.map { a in
            InstalledApp(name: a.name, bundle: a.bundle_id ?? "", source: a.source ?? "App", uninstallName: a.uninstall_name ?? a.name, path: a.path,
                         size: meta[a.path] ?? (a.size.map { $0 == "--" ? 0 : Fmt.parseSize($0) } ?? 0), lastUsed: last[a.path] ?? 0)
        }
    }

    /// Everything an app left behind: Mole's dry-run plan plus Burrow's own search of ~/Library.
    public static func leftovers(of app: InstalledApp) async -> [Leftover] {
        var list = LeftoverList()
        list.add(app.path, size: app.size, group: .app)
        let preview = await Shell.sh("printf 'y\\n\\n' | mo uninstall --dry-run --with-data \(Shell.quote(app.uninstallName)) 2>&1", timeout: 180)
        for e in parseUninstallPreview(preview.stdout, appPath: app.path) {
            list.add(e.path, size: e.size, group: LeftoverList.group(for: e.path, appPath: app.path))
        }
        let found = await Shell.script("appfind", [app.bundle, app.name], timeout: 120)
        for e in parseAppFind(found.stdout) { list.add(e.path, size: e.size, group: LeftoverList.group(for: e.path, appPath: app.path)) }
        return list.sorted.filter { Guard.refusal(for: $0.path) == nil || $0.group == .app }
    }

    /// The Homebrew cask that installed an app, if any: its record has to go too, or
    /// `brew upgrade` brings the app back. Looked up before the checklist, which shows it.
    public static func cask(forApp appPath: String) async -> String? {
        let r = await Shell.sh("brew info --cask --json=v2 --installed 2>/dev/null", timeout: 90)
        guard let data = r.stdout.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = o["casks"] as? [[String: Any]] else { return nil }
        let base = (appPath as NSString).lastPathComponent
        for c in casks {
            let arts = c["artifacts"] as? [Any] ?? []
            let has = arts.contains { ($0 as? [String: Any])?["app"].flatMap { $0 as? [Any] }?.contains { ($0 as? String) == base } ?? false }
            if has, let token = c["token"] as? String { return token }
        }
        return nil
    }

    /// Run only after the app itself is in the Trash, for the cask the checklist showed.
    public static func forgetCask(_ token: String) async -> Bool {
        await Shell.sh("brew uninstall --cask --force \(Shell.quote(token)) 2>&1", timeout: 300).ok
    }
}

public enum Scanners {
    public static func oldFiles() async -> [OldFile] { parseOldFiles((await Shell.script("oldfiles", timeout: 300)).stdout) }
    public static func dev() async -> DevScan { DevScan.parse((await Shell.script("devscan", timeout: 900)).stdout) }
    public static func tools() async -> [Tool] { parseTools((await Shell.script("tools", timeout: 300)).stdout) }
    public static func netCheck() async -> NetCheck { parseNetCheck((await Shell.script("netcheck", timeout: 60)).stdout) }
    public static func processes() async -> [ProcessGroup] { parseProcesses((await Shell.sh("ps -axo pid=,rss=,comm=", timeout: 15)).stdout) }
}

/// Full Disk Access can't be asked for; Burrow reads a file only it unlocks, and sends you to the pane.
public enum DiskAccess {
    public static var granted: Bool {
        let probes = ["Library/Application Support/com.apple.TCC/TCC.db", "Library/Safari/Bookmarks.plist", "Library/Containers/com.apple.stocks"]
        for p in probes {
            let path = Paths.home + "/" + p
            guard FileManager.default.fileExists(atPath: path) else { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue { return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil }
            if let h = FileHandle(forReadingAtPath: path) { try? h.close(); return true }
            return false
        }
        return false
    }

    public static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
