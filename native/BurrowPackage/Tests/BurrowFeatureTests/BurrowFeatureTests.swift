import AppKit
import SwiftUI
import XCTest
@testable import BurrowFeature

/// Parsers against output recorded on a real Mac (Fixtures/, home folder replaced by /Users/you),
/// the never-touch rules, and snapshots of each tab (SNAPSHOT_DIR=/tmp swift test).
final class ParserTests: XCTestCase {
    func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSizes() {
        XCTAssertEqual(Fmt.parseSize("41.4MB"), 41.4 * 1024 * 1024, accuracy: 1)
        XCTAssertEqual(Fmt.parseSize("1.03 GB"), 1.03 * 1024 * 1024 * 1024, accuracy: 1)
        XCTAssertEqual(Fmt.parseSize("0B"), 0)
        XCTAssertEqual(Fmt.bytes(4.4 * 1024 * 1024 * 1024), "4.4 GB")
        XCTAssertEqual(Fmt.bytes(812 * 1024 * 1024), "812 MB")
    }

    func testCleanList() throws {
        let scan = CleanScan.parse(try fixture("clean-list.txt"))
        XCTAssertFalse(scan.categories.isEmpty)
        XCTAssertEqual(scan.categories.first?.name, "User essentials")
        let brew = scan.categories.flatMap(\.items).first { $0.path.hasSuffix("Caches/Homebrew") }
        XCTAssertEqual(brew?.size ?? 0, 41.4 * 1024 * 1024, accuracy: 1)
        XCTAssertGreaterThan(scan.total, 0)
        XCTAssertTrue(scan.categories.allSatisfy { !$0.items.isEmpty })
    }

    func testCleanListWithCounts() {
        let scan = CleanScan.parse("=== Browsers ===\n/Users/you/Library/Caches/Google/Chrome  # 3.07GB, 7 items\n# comment\n")
        XCTAssertEqual(scan.categories.first?.items.first?.count, 7)
    }

    func testStatus() throws {
        let st = try XCTUnwrap(MoleStatus.parse(try fixture("status.json")))
        XCTAssertEqual(st.hardware?.model, "MacBook Pro")
        XCTAssertNotNil(st.memory?.used_percent)
        XCTAssertNotNil(st.disk?.total)
        XCTAssertTrue(st.networkSummary.hasPrefix("Online"))
    }

    func testUninstallList() throws {
        let list = UninstallListEntry.parse(try fixture("ulist.txt"))
        XCTAssertGreaterThan(list.count, 3)
        XCTAssertEqual(list.first?.name, "IDLE")
        XCTAssertEqual(list.first?.uninstall_name, "IDLE")
    }

    func testUninstallPreview() throws {
        let rows = parseUninstallPreview(try fixture("uninstall-dry.txt"), appPath: "/Applications/The Unarchiver.app", home: "/Users/you")
        let paths = rows.map(\.path)
        XCTAssertTrue(paths.contains("/Applications/The Unarchiver.app"))
        XCTAssertTrue(paths.contains("/Users/you/Library/Containers/cx.c3.theunarchiver"))
        XCTAssertFalse(paths.contains { $0.contains("/private/var/db/receipts") }, "Review-only receipts are not offered")
        XCTAssertEqual(rows.first { $0.path.hasSuffix("The Unarchiver.app") }?.size ?? 0, 27.1 * 1024 * 1024, accuracy: 1)
    }

    func testLeftoversKeepGroupContainersUnticked() {
        var l = LeftoverList(home: "/Users/you")
        l.add("/Applications/X.app", size: 10, group: .app)
        l.add("~/Library/Group Containers/ABC.x", size: 5, group: LeftoverList.group(for: "/Users/you/Library/Group Containers/ABC.x", appPath: "/Applications/X.app"))
        l.add("~/Library/Caches/x/", size: 0, group: .data)
        l.add("/Users/you", size: 0, group: .data)
        let items = l.sorted
        XCTAssertEqual(items.first?.group, .app)
        XCTAssertEqual(items.first { $0.group == .shared }?.on, false)
        XCTAssertTrue(items.contains { $0.path == "/Users/you/Library/Caches/x" && $0.on })
        XCTAssertFalse(items.contains { $0.path == "/Users/you" })
    }

    func testMdlsNullIsUnknownNotUnused() {
        XCTAssertEqual(parseMdlsDate("(null)"), 0)
        XCTAssertGreaterThan(parseMdlsDate("2025-03-02 10:11:12 +0000"), 0)
        let app = InstalledApp(name: "Figma", bundle: "com.figma.Desktop", source: "App", uninstallName: "Figma", path: "/Applications/Figma.app", size: 1, lastUsed: 0)
        XCTAssertFalse(app.isUnused())
        var old = app; old.lastUsed = Date().timeIntervalSince1970 - 200 * 86400
        XCTAssertTrue(old.isUnused())
        var apple = old; apple.bundle = "com.apple.Safari"
        XCTAssertFalse(apple.isUnused())
    }

    func testOldFiles() {
        let now = Date()
        let t = now.timeIntervalSince1970
        let text = """
        I\t100\t\(Int(t - 40 * 86400))\t\(Int(t - 40 * 86400))\t/Users/you/Downloads/a.pkg
        L\t100\t\(Int(t - 40 * 86400))\t\(Int(t - 40 * 86400))\t/Users/you/Downloads/a.pkg
        L\t500\t\(Int(t - 10 * 86400))\t\(Int(t - 10 * 86400))\t/Users/you/Movies/recent.mov
        L\t900\t\(Int(t - 200 * 86400))\t\(Int(t - 200 * 86400))\t/Users/you/Desktop/old\tname.mov
        """
        let files = parseOldFiles(text, now: now)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.first { $0.path.hasSuffix("a.pkg") }?.kind, .installer)
        XCTAssertTrue(files.contains { $0.path == "/Users/you/Desktop/old\tname.mov" })
    }

    func testDevScan() {
        let d = DevScan.parse("""
        W\t/r\t/r/.claude/worktrees/x\tx\t100\t100\t0\t1\t2048
        W\t/r\t/r/gone\tgone\t0\t0\t0\t0\t0
        A\t/r/node_modules\t100\t100\t60000
        X\t/Users/you/Library/Developer/Xcode/DerivedData\t70000
        G\t.claude\t5000
        O\t.claude\t/Users/you/.claude/projects\t3\t12345
        L\t/Users/you/Library/LaunchAgents/x.plist\tcom.x\t/nope\t0\t-
        """)
        XCTAssertEqual(d.worktrees.count, 2)
        XCTAssertTrue(d.worktrees[1].missing)
        XCTAssertTrue(d.worktrees[0].merged)
        XCTAssertEqual(d.buildFolders.first?.kb, 60000)
        XCTAssertNotNil(d.derivedData)
        XCTAssertEqual(d.oldSessions.first?.count, 3)
        XCTAssertFalse(d.launchAgents.first?.exists ?? true)
    }

    func testToolsTreat1985AsUnknown() {
        let tools = parseTools("brew\tmole\t1.74.0\t489024000\t4096\t0\t\nnpm\t@google/gemini-cli\t0.64.0\t1790000000\t100\t0\t/Users/you/.local\nnode\tv22\tv22\t1790000000\t9\t1\t/x\n")
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0].installed, 0)
        XCTAssertTrue(tools[0].isProtected)
        XCTAssertTrue(tools[2].isProtected)
        XCTAssertEqual(tools[1].location, "/Users/you/.local")
    }

    func testNetCheckAndProcesses() {
        let n = parseNetCheck("gw\t192.168.1.1\t3.2\nnet\t1.1.1.1\t24.6\ndns\t18\n")
        XCTAssertEqual(n.router, 3); XCTAssertEqual(n.internet, 25); XCTAssertEqual(n.dns, 18)
        let p = parseProcesses("""
          1 1000000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          2 2000000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Helper
          3 50000 /usr/sbin/WindowServer
        """)
        XCTAssertEqual(p.first?.name, "Google Chrome")
        XCTAssertEqual(p.first?.count, 2)
        XCTAssertEqual(p.first?.appPath, "/Applications/Google Chrome.app")
        XCTAssertNil(p.last?.appPath)
    }

    func testMoleLoggedFreed() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = Date()
        let log = "[x] clean run=abc session ended at \(f.string(from: now.addingTimeInterval(-60))), 120 items, 4.4GB\n"
        XCTAssertEqual(moleLoggedFreed(log, now: now) ?? 0, 4.4 * 1024 * 1024 * 1024, accuracy: 1)
        XCTAssertNil(moleLoggedFreed(log, now: now.addingTimeInterval(3600)))
    }
}

final class GuardTests: XCTestCase {
    let home = "/Users/you"
    override func setUp() {
        Paths.supportOverride = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-support-\(UUID().uuidString)")
    }
    func refused(_ p: String) -> Bool { Guard.refusal(for: p, home: home, checkFileSystem: false) != nil }

    func testNeverTouch() {
        for p in ["/Users/you", "/Users/you/Documents", "/Users/you/Library", "/Users/you/Library/Caches",
                  "/Users/you/Library/Mobile Documents/com~apple~CloudDocs/x.pdf", "/Users/you/Library/CloudStorage/GoogleDrive-a/x",
                  "/Users/you/Library/Keychains/login.keychain-db", "/Users/you/Library/Mail/V10", "/Users/you/Library/Messages/chat.db",
                  "/Users/you/Pictures/Photos Library.photoslibrary", "/Users/you/.ssh/id_ed25519", "/Users/you/project/.env",
                  "/Users/you/project/.env.local", "/Users/you/.claude/projects/x/memory/MEMORY.md", "/Users/you/.claude/settings.json",
                  "/System/Library/x", "/usr/local/bin/mo", "/Applications/Foo.app/Contents/MacOS/Foo", "/Users/you/a/../.ssh"] {
            XCTAssertTrue(refused(p), p)
        }
    }

    func testAllowed() {
        for p in ["/Users/you/Downloads/Xcode.xip", "/Users/you/Library/Caches/com.x", "/Users/you/Library/Containers/cx.c3.theunarchiver",
                  "/Users/you/Documents/site/node_modules", "/Applications/The Unarchiver.app", "/Applications/Python 3.12/IDLE.app",
                  "/private/var/folders/xx/yy/C/cx.c3", "/Users/you/.claude/projects/x/old.jsonl"] {
            XCTAssertFalse(refused(p), p)
        }
    }

    func testCleaningKeepsProtectedOut() {
        XCTAssertNotNil(Guard.protectedFromCleaning("/Users/you/Library/CloudStorage/GoogleDrive-a/proj/node_modules", home: home))
        XCTAssertNotNil(Guard.protectedFromCleaning("/Users/you/Library/Mail", home: home))
        XCTAssertNil(Guard.protectedFromCleaning("/Users/you/Library/Caches", home: home))
        XCTAssertNil(Guard.protectedFromCleaning("/Users/you/.Trash", home: home))
    }

    func testTrashDefaultsUnticked() async {
        let scan = CleanScan.parse("=== Trash ===\n/Users/you/.Trash  # 1GB\n=== Cloud ===\n\(NSHomeDirectory())/Library/CloudStorage/G/x/node_modules  # 1GB\n=== Caches ===\n/Users/you/Library/Caches/a  # 1GB\n")
        let excluded = await MainActor.run { BurrowModel().defaultExclusions(scan) }
        XCTAssertTrue(excluded.contains("/Users/you/.Trash"))
        XCTAssertTrue(excluded.contains { $0.contains("CloudStorage") })
        XCTAssertFalse(excluded.contains("/Users/you/Library/Caches/a"))
    }

    func testRunnerTrashesOnlyApprovedUnchangedFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.dmg"), b = dir.appendingPathComponent("b.dmg"), env = dir.appendingPathComponent(".env")
        for f in [a, b, env] { try Data("x".utf8).write(to: f) }
        ActionRunner.mover = { try FileManager.default.removeItem(at: $0) }   // keep the real Trash clean
        let planned = [PlannedPath.now(a.path, size: 1), PlannedPath(path: b.path, size: 1, modified: 1), PlannedPath(path: env.path, size: 1)]
        let out = await ActionRunner.trash(Approved(Plan(kind: "test", title: "t", body: "", paths: planned, confirm: "OK")))
        XCTAssertEqual(out.moved, [a.path])
        XCTAssertTrue(out.skipped.contains { $0.path == b.path && $0.why.contains("changed") })
        XCTAssertTrue(out.skipped.contains { $0.path == env.path })
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.path))
        XCTAssertEqual(History.load().first?.kind, "test", "history goes to the override folder")
        XCTAssertTrue(Paths.history.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        try? FileManager.default.removeItem(at: dir)
    }

    func testSchedulePlist() throws {
        let r = Routine.all[0]
        let data = try XCTUnwrap(Scheduler.plist(for: r, when: r.defaultWhen))
        let o = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(o["Label"] as? String, "com.jamak.burrow.weekly-clean")
        XCTAssertEqual((o["StartCalendarInterval"] as? [String: Int])?["Weekday"], 0)
        XCTAssertNotNil(Routine.all[2].defaultWhen.kind == .interval ? Scheduler.plist(for: Routine.all[2], when: Routine.all[2].defaultWhen) : nil)
    }
}

final class WhitelistTests: XCTestCase {
    var tmp: URL!
    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-wl-\(UUID().uuidString)")
        Paths.supportOverride = tmp.appendingPathComponent("support")
        Paths.moleConfigOverride = tmp.appendingPathComponent("mole")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    /// The command stands in for `mo clean`: it copies the whitelist as Mole would see it.
    func plan() -> Approved {
        Approved(Plan(kind: "clean", title: "t", body: "", commands: ["cat \(Shell.quote(Paths.whitelist.path)) > \(Shell.quote(tmp.appendingPathComponent("seen").path))"], confirm: "OK"))
    }
    var seen: String { (try? String(contentsOf: tmp.appendingPathComponent("seen"), encoding: .utf8)) ?? "" }

    func testNoWhitelistGetsMoleDefaultsThenIsRemoved() async {
        _ = await Mole.clean(plan(), keep: ["/Users/you/Library/Caches/keep"])
        XCTAssertTrue(seen.contains("Library/Mobile Documents*"), "Mole's defaults stay in force")
        XCTAssertTrue(seen.contains("FINDER_METADATA"))
        XCTAssertTrue(seen.contains("/Users/you/Library/Caches/keep/*"))
        XCTAssertTrue(seen.contains("Library/CloudStorage/*"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.whitelist.path), "no whitelist before, none after")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.whitelistJournal.path))
    }

    func testExistingWhitelistIsKeptAndRestored() async throws {
        try FileManager.default.createDirectory(at: Paths.moleConfig, withIntermediateDirectories: true)
        try "/Users/you/mine\n".write(to: Paths.whitelist, atomically: true, encoding: .utf8)
        _ = await Mole.clean(plan(), keep: [])
        XCTAssertTrue(seen.hasPrefix("/Users/you/mine\n"))
        XCTAssertFalse(seen.contains("FINDER_METADATA"), "your whitelist replaces Mole's defaults, as before")
        XCTAssertEqual(try String(contentsOf: Paths.whitelist, encoding: .utf8), "/Users/you/mine\n")
    }

    func testInterruptedRunIsRestoredOnLaunch() throws {
        try FileManager.default.createDirectory(at: Paths.moleConfig, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        try "temporary\n".write(to: Paths.whitelist, atomically: true, encoding: .utf8)
        try JSONSerialization.data(withJSONObject: ["had": true, "orig": "original\n"]).write(to: Paths.whitelistJournal)
        Mole.restoreWhitelistIfInterrupted()
        XCTAssertEqual(try String(contentsOf: Paths.whitelist, encoding: .utf8), "original\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.whitelistJournal.path))
    }

    func testFolderWithEnvIsSkipped() async throws {
        let wt = tmp.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: wt.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try Data().write(to: wt.appendingPathComponent("node_modules/pkg/.env"))
        try Data().write(to: wt.appendingPathComponent(".env.example"))
        let none = await ActionRunner.envFile(in: wt.path)
        XCTAssertNil(none, "examples and node_modules don't count")
        try Data().write(to: wt.appendingPathComponent(".env.local"))
        ActionRunner.mover = { try FileManager.default.removeItem(at: $0) }
        let out = await ActionRunner.trash(Approved(Plan(kind: "test", title: "t", body: "", paths: [PlannedPath(path: wt.path, size: 1)], confirm: "OK")))
        XCTAssertTrue(out.moved.isEmpty)
        XCTAssertTrue(out.skipped.first?.why.contains(".env") ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wt.path))
    }
}

/// Read-only scans on this Mac: `BURROW_LIVE=1 swift test --filter LiveTests`.
final class LiveTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["BURROW_LIVE"] == "1" else { throw XCTSkip("set BURROW_LIVE=1") }
        Paths.supportOverride = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-live")
        try Paths.installScripts()
    }

    func testStatusAndProcesses() async throws {
        let st = await Mole.status()
        XCTAssertNotNil(st?.memory?.used_percent)
        let procs = await Scanners.processes()
        XCTAssertFalse(procs.isEmpty)
        print("live: memory \(Int(st?.memory?.used_percent ?? 0))%, top \(procs.first?.name ?? "-")")
    }

    func testApps() async throws {
        let apps = await Mole.apps()
        XCTAssertGreaterThan(apps.count, 3)
        XCTAssertGreaterThan(apps.filter { $0.size > 0 }.count, apps.count / 2, "apps-meta sizes")
        XCTAssertTrue(apps.contains { $0.lastUsed > 0 }, "Spotlight dates")
        print("live: \(apps.count) apps, \(apps.filter { $0.isUnused() }.count) unused, \(apps.filter { $0.lastUsed == 0 }.count) without a usage record")
    }

    func testToolsAndNetwork() async throws {
        let tools = await Scanners.tools()
        XCTAssertTrue(tools.contains { $0.kind == .brew && $0.name.hasSuffix("mole") && $0.isProtected })
        XCTAssertFalse(tools.contains { $0.installed > 0 && $0.installed < 946_684_800 })
        let net = await Scanners.netCheck()
        XCTAssertNotNil(net.dns)
        print("live: \(tools.count) tools; router \(net.router.map(String.init) ?? "-") ms, dns \(net.dns.map(String.init) ?? "-") ms")
    }
}

/// Renders each tab with sample data: `SNAPSHOT_DIR=/tmp swift test --filter SnapshotTests`.
@MainActor
final class SnapshotTests: XCTestCase {
    func testTabs() throws {
        Paths.supportOverride = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-snap")
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { throw XCTSkip("set SNAPSHOT_DIR to render") }
        Fonts.register()
        let model = BurrowModel.sample()
        for scheme in [ColorScheme.light, .dark] {
            for tab in Tab.allCases {
                model.tab = tab
                render(RootView(model: model).environment(\.colorScheme, scheme), size: CGSize(width: 1280, height: 840),
                       appearance: scheme == .dark ? .darkAqua : .aqua, to: "\(dir)/burrow-\(tab.rawValue)\(scheme == .dark ? "-dark" : "").png")
            }
        }
        render(MenuBarPanel(model: model) { _ in }, size: CGSize(width: 320, height: 560), appearance: .aqua, to: "\(dir)/burrow-menubar.png")
        let req = UninstallRequest(app: model.apps![0], items: [
            Leftover(path: "/Applications/zoom.us.app", size: 612e6, group: .app, on: true),
            Leftover(path: Paths.home + "/Library/Application Support/zoom.us", size: 210e6, group: .data, on: true),
            Leftover(path: Paths.home + "/Library/Group Containers/BJ4HAAB9B3.ZoomClient3rd", size: 1e6, group: .shared, on: false)])
        render(UninstallSheet(request: req, model: model), size: CGSize(width: 640, height: 420), appearance: .aqua, to: "\(dir)/burrow-uninstall.png")
    }

    func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to path: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
