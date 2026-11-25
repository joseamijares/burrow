import Foundation

/// The "never touch" rules. Every path Burrow moves, deletes or lets Mole
/// clean goes through `Guard.refusal(for:)` first; a non-nil answer means no.
public enum Guard {
    /// Folders Burrow never touches, nor anything inside them (relative to home).
    static let neverInsideHome = [
        "Library/Mobile Documents",      // iCloud Drive: deleting here deletes on every device
        "Library/CloudStorage",          // Dropbox, Google Drive, OneDrive…
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Containers/com.apple.mail",
        "Library/Containers/com.apple.MobileSMS",
        "Library/Group Containers/group.com.apple.notes",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/Burrow",
        "Pictures/Photos Library.photoslibrary",
        ".ssh",
        ".gnupg",
        ".claude/memory",
        ".claude/settings.json",
        ".claude/CLAUDE.md",
        ".codex/memories",
        ".codex/config.toml",
    ]

    /// Folders that may hold things Burrow cleans, but are never removed themselves.
    static let rootsInsideHome = [
        "", "Library", "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
        "Library/Preferences", "Library/LaunchAgents", "Library/Logs", "Documents", "Desktop", "Downloads", "Pictures",
        "Movies", "Music", "Applications", "Developer", "Projects", ".config", ".claude", ".codex", ".Trash",
    ]

    /// Outside home, only these places hold things Burrow may move to the Trash.
    static let allowedOutsideHome = ["/Applications/", "/private/var/folders/", "/var/folders/"]

    /// nil when the path may be acted on, otherwise the reason it may not.
    public static func refusal(for rawPath: String, home: String = Paths.home, checkFileSystem: Bool = true) -> String? {
        let path = (rawPath as NSString).standardizingPath
        guard path.hasPrefix("/"), !path.contains("/../") else { return "not an absolute path" }
        let rel: String?
        if path == home { rel = "" } else if path.hasPrefix(home + "/") { rel = String(path.dropFirst(home.count + 1)) } else { rel = nil }

        if let rel {
            if rootsInsideHome.contains(rel) { return "a top-level folder" }
            for p in neverInsideHome where rel == p || rel.hasPrefix(p + "/") { return "protected (\(p))" }
            // Agent memory anywhere under the coding-agent folders (e.g. ~/.claude/projects/*/memory).
            if rel.hasPrefix(".claude/") || rel.hasPrefix(".codex/"), rel.split(separator: "/").contains(where: { $0 == "memory" || $0 == "memories" }) {
                return "agent memory"
            }
            if rel.hasPrefix("Library/Messages") { return "protected (Messages)" }
        } else {
            guard allowedOutsideHome.contains(where: { path.hasPrefix($0) }) else { return "outside your home folder" }
            if path.hasPrefix("/Applications/") {
                // Only an app bundle (or a folder of them, like "/Applications/Python 3.12"), never Apple's own.
                let comps = path.dropFirst("/Applications/".count).split(separator: "/")
                guard let first = comps.first, comps.count <= 2 else { return "inside an app bundle" }
                if comps.count == 2 && !comps[1].hasSuffix(".app") { return "inside an app folder" }
                if comps.count == 1 && !first.hasSuffix(".app") && !isDirectoryOfApps(path) && checkFileSystem { return "not an app" }
                if checkFileSystem, let id = Bundle(path: path)?.bundleIdentifier, id.hasPrefix("com.apple.") { return "an Apple app" }
            }
        }

        let name = (path as NSString).lastPathComponent
        if name == ".env" || name.hasPrefix(".env.") { return "a .env file" }
        if name.hasSuffix(".photoslibrary") || name.hasSuffix(".keychain") || name.hasSuffix(".keychain-db") { return "a library Burrow never touches" }

        if checkFileSystem {
            let url = URL(fileURLWithPath: path)
            if let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]), v.isUbiquitousItem == true { return "synced with iCloud" }
            // A symlink is moved as the link itself. A path reached through a linked
            // parent folder is judged by where it really is.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil {
                let resolved = url.resolvingSymlinksInPath().path
                if resolved != path, let r = refusal(for: resolved, home: home, checkFileSystem: false) { return "really \(r)" }
            }
        }
        return nil
    }

    /// For Mole's clean list, whose entries are often whole cache folders (Mole empties
    /// them): only the never-touch places count. Matches are kept out of the clean.
    public static func protectedFromCleaning(_ rawPath: String, home: String = Paths.home) -> String? {
        let path = (rawPath as NSString).standardizingPath
        guard path.hasPrefix(home + "/") else { return nil }
        let rel = String(path.dropFirst(home.count + 1))
        for p in neverInsideHome where rel == p || rel.hasPrefix(p + "/") || p.hasPrefix(rel + "/") { return "protected (\(p))" }
        if rel.split(separator: "/").contains(where: { $0 == "memory" || $0 == "memories" }), rel.hasPrefix(".claude") || rel.hasPrefix(".codex") {
            return "agent memory"
        }
        return nil
    }

    static func isDirectoryOfApps(_ path: String) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return !items.isEmpty && items.contains { $0.hasSuffix(".app") }
    }
}
