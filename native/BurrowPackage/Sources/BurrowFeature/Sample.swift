import Foundation

extension BurrowModel {
    /// The prototype's sample data, for snapshots and previews. Never runs anything.
    static func sample() -> BurrowModel {
        let m = BurrowModel()
        let H = Paths.home, GB = Fmt.GB, MB = 1024.0 * 1024, now = Date().timeIntervalSince1970
        m.phase = .ready
        m.hasDiskAccess = true
        m.moleVersion = "1.74.0"
        m.moleLatest = "1.74.0"
        m.status = MoleStatus.parse("""
        {"health_score":62,"health_score_msg":"Fair: High Memory","procs":780,"uptime":"4d 0h",
         "hardware":{"model":"MacBook Pro","cpu_model":"Apple M3 Pro","total_ram":"18.0 GB","os_version":"macOS 27.0.1"},
         "cpu":{"usage":40,"load1":5.6},"memory":{"used_percent":82,"total":\(18 * GB),"swap_used":\(21.6 * GB),"pressure":"warn"},
         "disks":[{"mount":"/","used":\(431 * GB),"total":\(494 * GB),"used_percent":87,"purgeable":\(4.6 * GB)}],
         "network":[{"name":"en6","ip":"192.168.1.81","rx_rate_mbs":0.0076,"tx_rate_mbs":0.0082},{"name":"en0","ip":"192.168.1.77","rx_rate_mbs":0.0013,"tx_rate_mbs":0.0003}],
         "proxy":{"enabled":true,"type":"TUN","host":"utun0"},
         "batteries":[{"percent":100,"status":"charged","health":"Good","cycle_count":357}]}
        """)
        m.processes = [
            ProcessGroup(name: "Google Chrome", rss: 3.1 * GB, count: 41, appPath: "/Applications/Google Chrome.app"),
            ProcessGroup(name: "Slack", rss: 1.4 * GB, count: 6, appPath: "/Applications/Slack.app"),
            ProcessGroup(name: "Docker", rss: 1.2 * GB, count: 3, appPath: "/Applications/Docker.app"),
            ProcessGroup(name: "WindowServer", rss: 0.6 * GB, count: 1, appPath: nil),
        ]
        m.scan = CleanScan(categories: [
            CleanCategory(name: "User essentials", items: [CleanItem(path: H + "/Library/Caches", size: 4.39 * GB, count: 19), CleanItem(path: H + "/Library/Logs", size: 10.2 * MB, count: 10)]),
            CleanCategory(name: "Browsers", items: [CleanItem(path: H + "/Library/Caches/Google/Chrome", size: 3.07 * GB, count: 7)]),
            CleanCategory(name: "Developer tools", items: [CleanItem(path: H + "/.npm/_cacache", size: 705 * MB, count: 2), CleanItem(path: H + "/.npm/_npx", size: 810 * MB, count: 10)]),
            CleanCategory(name: "Trash", items: [CleanItem(path: H + "/.Trash", size: 2.2 * GB, count: 40)]),
        ], at: Date().addingTimeInterval(-240))
        m.scanFresh = true
        m.excluded = m.defaultExclusions(m.scan!)
        m.old = [
            OldFile(kind: .installer, path: H + "/Downloads/Xcode_26.xip", size: 3.1 * GB, last: now - 240 * 86400),
            OldFile(kind: .installer, path: H + "/Downloads/Docker.dmg", size: 0.6 * GB, last: now - 210 * 86400),
            OldFile(kind: .large, path: H + "/Desktop/Screen Recording 2026-03-02.mov", size: 1.8 * GB, last: now - 260 * 86400),
        ]
        m.oldSelected = [H + "/Downloads/Xcode_26.xip"]
        var dev = DevScan()
        dev.worktrees = [Worktree(repo: H + "/Documents/app", path: H + "/Documents/app/.claude/worktrees/quiz-timer", branch: "quiz-timer",
                                  last: now - 74 * 86400, dirty: 0, merged: true, kb: 1.6 * 1024 * 1024, missing: false)]
        dev.buildFolders = [BuildFolder(path: H + "/Documents/site/node_modules", last: now - 60 * 86400, kb: 820 * 1024)]
        dev.agentDirs = [AgentDir(name: ".codex", kb: 9.2 * 1024 * 1024), AgentDir(name: ".claude", kb: 4.9 * 1024 * 1024)]
        dev.oldSessions = [OldSessions(name: ".claude", dir: H + "/.claude/projects", count: 214, bytes: 380 * MB)]
        dev.launchAgents = [LaunchAgent(file: H + "/Library/LaunchAgents/com.example.helper.plist", label: "com.example.helper",
                                        program: "/Applications/Example.app/Contents/helper", exists: false, pid: "-")]
        m.dev = dev
        m.devSelected = Set(dev.buildFolders.map(\.path))
        m.apps = [
            InstalledApp(name: "Zoom", bundle: "us.zoom.xos", source: "App", uninstallName: "Zoom", path: "/Applications/zoom.us.app", size: 612 * MB, lastUsed: now - 210 * 86400),
            InstalledApp(name: "Unity Hub", bundle: "com.unity3d.unityhub", source: "App", uninstallName: "Unity Hub", path: "/Applications/Unity Hub.app", size: 480 * MB, lastUsed: now - 140 * 86400),
            InstalledApp(name: "Figma", bundle: "com.figma.Desktop", source: "App", uninstallName: "Figma", path: "/Applications/Figma.app", size: 302 * MB, lastUsed: 0),
            InstalledApp(name: "Slack", bundle: "com.tinyspeck.slackmacgap", source: "App", uninstallName: "Slack", path: "/Applications/Slack.app", size: 520 * MB, lastUsed: now - 3600),
        ]
        m.tools = [
            Tool(kind: .brew, name: "dotnet", version: "10.0.400", installed: now - 300 * 86400, kb: 669 * 1024, flag: 0, location: ""),
            Tool(kind: .brew, name: "postgresql@14", version: "14.19", installed: now - 500 * 86400, kb: 60 * 1024, flag: 1, location: ""),
            Tool(kind: .brew, name: "mole", version: "1.74.0", installed: now - 86400, kb: 4 * 1024, flag: 0, location: ""),
            Tool(kind: .npm, name: "@google/gemini-cli", version: "0.64.0", installed: now - 20 * 86400, kb: 100 * 1024, flag: 0, location: H + "/.local"),
            Tool(kind: .node, name: "v22.21.0", version: "v22.21.0", installed: now - 100 * 86400, kb: 1778 * 1024, flag: 1, location: ""),
        ]
        m.net = NetCheck(at: Date(), router: 3, dns: 18, internet: 24)
        m.routinesOn = ["weekly-clean": true]
        m.when = [:]
        m.history = [
            HistoryEntry(t: now - 2 * 86400, kind: "weekly-clean", freed: 4.1 * GB, how: "scheduled", note: nil, code: nil, log: nil),
            HistoryEntry(t: now - 3 * 86400, kind: "uninstall", freed: 820 * MB, how: "manual", note: "Unity Hub, 7 items", code: nil, log: "x.json"),
        ]
        return m
    }
}
