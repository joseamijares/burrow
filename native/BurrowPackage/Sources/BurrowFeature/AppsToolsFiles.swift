import AppKit
import SwiftUI

struct AppsView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        let items = model.apps ?? []
        let filter = model.appFilter ?? (model.unusedApps.isEmpty ? .largest : .unused)
        Page {
            PageHead(title: model.apps != nil ? "\(items.count) apps · \(Fmt.bytes(items.reduce(0) { $0 + $1.size }))" : "Apps",
                     lede: "Apps Mole can uninstall, with when you last opened each one. Uninstalling finds everything an app left behind (settings, data, caches, containers, login items) and moves what you tick to the Trash.") {
                if model.apps != nil {
                    HStack(spacing: 0) {
                        seg(.unused, "Not used 90+ days · \(model.unusedApps.count)", filter)
                        seg(.largest, "Largest", filter)
                        seg(.all, "A–Z", filter)
                    }
                    .padding(2).background(Ink.sage, in: RoundedRectangle(cornerRadius: 8))
                }
                ScanButton(busy: model.appsBusy, scanned: model.apps != nil, first: "Scan apps") { Task { await model.scanApps() } }
            }
            if model.apps == nil {
                if model.appsBusy { Progress(text: "Listing apps and reading when you last opened them…") } else { Empty(text: "Not scanned yet.") }
            } else {
                let list = sorted(items, filter)
                VStack(spacing: 0) {
                    Rectangle().fill(Ink.ink).frame(height: 1)
                    if list.isEmpty { Empty(text: filter == .unused ? "Every app with a usage record was opened in the last 90 days." : "No apps found.") }
                    ForEach(list) { a in row(a) }
                }
                Lede(text: "“No usage record” means Spotlight has no last-opened date for the app, so Burrow never calls it unused. Apple apps, Claude and Burrow are protected.", size: 13)
            }
        }
    }

    func sorted(_ items: [InstalledApp], _ f: BurrowModel.AppFilter) -> [InstalledApp] {
        switch f {
        case .unused: model.unusedApps.sorted { $0.size > $1.size }
        case .largest: items.sorted { $0.size > $1.size }
        case .all: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func seg(_ f: BurrowModel.AppFilter, _ label: String, _ current: BurrowModel.AppFilter) -> some View {
        Button { model.appFilter = f } label: {
            Text(label).font(Typo.body(13, current == f ? .medium : .regular)).foregroundStyle(current == f ? Ink.ink : Ink.muted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(current == f ? Ink.paper : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    func row(_ a: InstalledApp) -> some View {
        let stale = (Fmt.days(a.lastUsed) ?? 0) >= 90
        return RuledRow {
            Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.name).font(Typo.body(15, .medium))
                    if a.source != "App" { Tag(text: a.source) }
                }
                Text(Paths.short(a.path)).font(Typo.mono(11)).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(a.lastUsed > 0 ? "opened " + Fmt.ago(a.lastUsed) : "no usage record").font(Typo.body(13)).foregroundStyle(stale ? Ink.warn : Ink.muted2)
                .frame(width: 170, alignment: .trailing)
            SizeText(bytes: a.size)
            HStack(spacing: 16) {
                Button("Show") { model.reveal(a.path) }.buttonStyle(LinkButton())
                Button(a.isProtected ? "Protected" : "Uninstall") { Task { await model.beginUninstall(a) } }
                    .buttonStyle(LinkButton(negative: true)).disabled(a.isProtected || model.busy != nil)
            }
            .frame(minWidth: 140, alignment: .trailing)
        }
    }
}

struct ToolsView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        let items = model.tools ?? []
        let total = items.filter { !($0.kind == .node && $0.flag == 1) }.reduce(0) { $0 + $1.bytes }
        Page {
            PageHead(title: model.tools != nil ? "\(items.count) tools · \(Fmt.bytes(total))" : "Tools",
                     lede: "Things you installed from the terminal: Homebrew, global npm packages, Python and Rust tools, and Node versions. Uninstalling runs the tool's own uninstaller, which removes it for good (not to the Trash), but you can always reinstall with the same command.") {
                ScanButton(busy: model.toolsBusy, scanned: model.tools != nil, first: "Scan tools") { Task { await model.scanTools() } }
            }
            if model.tools == nil {
                if model.toolsBusy { Progress(text: "Asking Homebrew, npm, pipx, uv, cargo and nvm…") } else { Empty(text: "Not scanned yet.") }
            } else {
                let dupes = Dictionary(grouping: items.filter { $0.kind == .npm }, by: \.name)
                ForEach(Tool.groups, id: \.0) { kind, title, hint in
                    let list = items.filter { $0.kind == kind }.sorted { $0.kb > $1.kb }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHead(title, "\(list.count) · \(Fmt.bytes(list.reduce(0) { $0 + $1.bytes }))")
                            if !hint.isEmpty { Lede(text: hint, size: 13).padding(.top, 8) }
                            ForEach(list) { t in row(t, dupes: (dupes[t.name] ?? []).filter { $0.location != t.location }.map { Tool.whereLabel($0.location) }) }
                        }
                    }
                }
            }
        }
    }

    func row(_ t: Tool, dupes: [String]) -> some View {
        RuledRow {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(t.name).font(Typo.body(15, .medium))
                    Text(t.version).font(Typo.mono(12)).foregroundStyle(Ink.muted)
                    if t.kind == .brew && t.flag == 1 { Tag(text: "running service", tone: .warn) }
                    if t.isProtected { Tag(text: t.kind == .node ? "nvm default" : "Burrow needs it") }
                    if t.kind == .npm && !dupes.isEmpty { Tag(text: "also in " + dupes.joined(separator: ", "), tone: .warn) }
                }
                if t.kind == .npm { Text(Tool.whereLabel(t.location)).font(Typo.body(12)).foregroundStyle(Ink.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(t.installed > 0 ? "installed " + Fmt.ago(t.installed) : "").font(Typo.body(13)).foregroundStyle(Ink.muted2).frame(width: 170, alignment: .trailing)
            SizeText(bytes: t.bytes)
            Button(t.isProtected ? "Protected" : "Uninstall") { Task { await model.uninstall(t) } }
                .buttonStyle(LinkButton(negative: true)).disabled(t.isProtected || model.busy != nil).frame(minWidth: 80, alignment: .trailing)
        }
    }
}

struct OldFilesView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        let items = model.old ?? []
        let sel = items.filter { model.oldSelected.contains($0.path) }.reduce(0) { $0 + $1.size }
        Page {
            AccessBanner(model: model)
            PageHead(title: model.old != nil ? "\(Fmt.bytes(model.oldTotal)) you forgot" : "Old files",
                     lede: "Installers anywhere in Downloads, Desktop and Documents, plus files over 300 MB you have not opened in four months. These go to the Trash, so you can still get them back. iCloud-synced files are never touched.") {
                ScanButton(busy: model.oldBusy, scanned: model.old != nil) { Task { await model.scanOld() } }
            }
            if model.old == nil {
                if model.oldBusy { Progress(text: "Looking through Downloads, Desktop and Documents…") } else { Empty(text: "Not scanned yet.") }
            } else {
                VStack(spacing: 0) {
                    Rectangle().fill(Ink.ink).frame(height: 1)
                    group(.installer, "Installers", ".dmg .pkg .xip .iso", items)
                    group(.large, "Large files not opened in 4+ months", "over 300 MB", items)
                }
            }
        } bar: {
            if model.old != nil {
                ActionBar(title: "\(Fmt.bytes(sel)) selected", note: "Moved to the Trash, not deleted. Burrow's weekly clean leaves the Trash alone.") {
                    Button("Move \(Fmt.bytes(sel)) to Trash") { Task { await model.trashOld() } }.buttonStyle(PrimaryButton()).disabled(sel <= 0 || model.busy != nil)
                }
            }
        }
    }

    @ViewBuilder func group(_ kind: OldFile.Kind, _ name: String, _ hint: String, _ all: [OldFile]) -> some View {
        let items = all.filter { $0.kind == kind }
        if items.isEmpty {
            RuledRow(minHeight: 56) { (Text(name).font(Typo.body(16, .medium)) + Text(" · none found").foregroundColor(Ink.muted)); Spacer() }
        } else {
            let allOn = items.allSatisfy { model.oldSelected.contains($0.path) }, some = items.contains { model.oldSelected.contains($0.path) }
            RuledRow(minHeight: 56) {
                Checkbox(state: allOn ? .on : some ? .mixed : .off) {
                    if allOn { model.oldSelected.subtract(items.map(\.path)) } else { model.oldSelected.formUnion(items.map(\.path)) }
                }
                Text(name).font(Typo.body(16, .medium)) + Text(" · \(hint)").font(Typo.body(16)).foregroundColor(Ink.muted)
                Spacer()
                Text("\(items.count) files").font(Typo.body(13)).foregroundStyle(Ink.muted2)
                SizeText(bytes: items.reduce(0) { $0 + $1.size }, strong: true)
            }
            VStack(spacing: 0) {
                ForEach(items) { f in
                    HStack(spacing: 10) {
                        Checkbox(model.oldSelected.contains(f.path)) {
                            if model.oldSelected.contains(f.path) { model.oldSelected.remove(f.path) } else { model.oldSelected.insert(f.path) }
                        }
                        Text(Paths.short(f.path)).font(Typo.body(14)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("opened " + Fmt.ago(f.last)).font(Typo.body(13)).foregroundStyle(Ink.muted2)
                        SizeText(bytes: f.size)
                        Button("Show") { model.reveal(f.path) }.buttonStyle(LinkButton())
                    }
                    .padding(.leading, 30).frame(minHeight: 38)
                }
            }
            .padding(.vertical, 4).background(Ink.panel.opacity(0.6))
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
    }
}

struct DeveloperView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        Page {
            AccessBanner(model: model)
            PageHead(title: model.dev != nil ? "\(Fmt.bytes(model.devTotal)) of dev leftovers" : "Developer",
                     lede: "Git worktrees, idle build folders, Xcode data, coding-agent folders and launch agents. Scans ~/Documents, ~/Projects, ~/GitHub, ~/dev and your Mole purge paths. Nothing here runs on a schedule.") {
                ScanButton(busy: model.devBusy, scanned: model.dev != nil) { Task { await model.scanDev() } }
            }
            if let dev = model.dev {
                worktrees(dev)
                builds(dev)
                HStack(alignment: .top, spacing: 56) {
                    agents(dev).frame(maxWidth: .infinity)
                    launchAgents(dev).frame(maxWidth: .infinity)
                }
            } else if model.devBusy {
                Progress(text: "Reading git repositories and measuring folders. This can take a minute.")
            } else {
                Empty(text: "Not scanned yet.")
            }
        }
    }

    func worktrees(_ dev: DevScan) -> some View {
        let wts = dev.worktrees.sorted { $0.idle > $1.idle }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHead("Git worktrees", "\(dev.staleWorktrees.count) untouched 30+ days, of \(wts.count)")
            if wts.isEmpty { Empty(text: "No extra worktrees found.") }
            ForEach(wts) { w in
                let canRemove = w.missing || (w.dirty == 0 && w.idle >= 30)
                RuledRow {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text((w.repo as NSString).lastPathComponent).font(Typo.body(15, .medium))
                            Text(Paths.short(w.path.replacingOccurrences(of: w.repo + "/", with: ""))).font(Typo.mono(12)).foregroundStyle(Ink.muted).lineLimit(1)
                        }
                        Text(w.branch).font(Typo.body(13)).foregroundStyle(Ink.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if w.missing { Tag(text: "folder missing", tone: .neg) }
                        else if w.dirty > 0 { Tag(text: "\(w.dirty) uncommitted", tone: .warn) }
                        else if w.merged { Tag(text: "merged") } else { Tag(text: "not merged", tone: .plain) }
                    }
                    .frame(width: 120, alignment: .leading)
                    Text(w.missing ? "" : "touched " + Fmt.ago(w.last)).font(Typo.body(13)).foregroundStyle(Ink.muted2).frame(width: 150, alignment: .trailing)
                    SizeText(bytes: w.bytes)
                    Button(w.missing ? "Prune" : "Remove") { Task { await model.removeWorktree(w) } }
                        .buttonStyle(LinkButton()).disabled(!canRemove || model.busy != nil)
                        .help(canRemove ? "" : w.dirty > 0 ? "Commit or stash first" : "Used in the last 30 days")
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
            Lede(text: "Remove moves a worktree with nothing uncommitted to the Trash, then runs git worktree prune. The branch stays.", size: 13).padding(.top, 8)
        }
    }

    func builds(_ dev: DevScan) -> some View {
        let arts = dev.buildFolders.sorted { $0.kb > $1.kb }
        var sel = arts.filter { model.devSelected.contains($0.path) }.reduce(0) { $0 + $1.bytes }
        if let dd = dev.derivedData, model.devSelected.contains(dd.path) { sel += dd.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHead("Build folders", "\(arts.count) over 50 MB, ignored by git")
            if let dd = dev.derivedData {
                RuledRow {
                    Checkbox(model.devSelected.contains(dd.path)) { toggle(dd.path) }
                    Text("Xcode DerivedData").font(Typo.body(15, .medium)) + Text(" · rebuilt on next build").foregroundColor(Ink.muted)
                    Spacer()
                    SizeText(bytes: dd.bytes)
                }
            }
            if arts.isEmpty { Empty(text: "No build folders over 50 MB.") }
            ForEach(arts.prefix(40)) { a in
                RuledRow {
                    Checkbox(model.devSelected.contains(a.path)) { toggle(a.path) }
                    Text(Paths.short(a.path)).font(Typo.mono(12)).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Text(a.idle < 14 ? "used " + Fmt.ago(a.last) : "idle \(a.idle) days").font(Typo.body(13)).foregroundStyle(a.idle < 14 ? Ink.warn : Ink.muted2)
                    SizeText(bytes: a.bytes)
                }
            }
            HStack {
                Spacer()
                Button("Move \(Fmt.bytes(sel)) to Trash") { Task { await model.trashDev() } }.buttonStyle(PrimaryButton()).disabled(sel <= 0 || model.busy != nil)
            }
            .padding(.top, 14)
        }
    }

    func toggle(_ p: String) { if model.devSelected.contains(p) { model.devSelected.remove(p) } else { model.devSelected.insert(p) } }

    func agents(_ dev: DevScan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("Coding agents", "\(Fmt.bytes(dev.agentDirs.reduce(0) { $0 + $1.kb * 1024 })) on disk")
            if dev.agentDirs.isEmpty { Empty(text: "No coding-agent folders found.") }
            ForEach(dev.agentDirs) { g in
                let old = dev.oldSessions.first { $0.name == g.name }
                RuledRow {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) { Text(g.title).font(Typo.body(15, .medium)); Text("~/" + g.name).font(Typo.mono(12)).foregroundStyle(Ink.muted) }
                        if let old, old.count > 0 { Text("\(old.count) transcripts older than 30 days · \(Fmt.bytes(old.bytes))").font(Typo.body(13)).foregroundStyle(Ink.muted) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SizeText(bytes: g.kb * 1024)
                    if let old, old.count > 0 { Button("Trash old") { Task { await model.trimSessions(g.name) } }.buttonStyle(LinkButton()) }
                    Button("Show") { model.reveal(Paths.home + "/" + g.name) }.buttonStyle(LinkButton())
                }
            }
        }
    }

    func launchAgents(_ dev: DevScan) -> some View {
        let list = dev.launchAgents.filter { !$0.isBurrows }.sorted { !$0.exists && $1.exists }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHead("Starts at login", Fmt.plural(list.count, "launch agent"))
            if list.isEmpty { Empty(text: "No launch agents in ~/Library/LaunchAgents.") }
            ForEach(list) { l in
                RuledRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.label.isEmpty ? (l.file as NSString).lastPathComponent : l.label).font(Typo.mono(12, .medium)).lineLimit(1)
                        Text(Paths.short(l.program)).font(Typo.mono(11)).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(!l.exists ? "Program missing" : l.running ? "Running" : "Idle").font(Typo.body(13))
                        .foregroundStyle(!l.exists ? Ink.neg : l.running ? Ink.deepSage : Ink.muted2)
                    Button("Remove") { Task { await model.removeLaunchAgent(l) } }.buttonStyle(LinkButton())
                }
            }
        }
    }
}
