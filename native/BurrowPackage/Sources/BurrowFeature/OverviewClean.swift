import SwiftUI

struct OverviewView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        Page {
            AccessBanner(model: model)
            if model.sweepPending {
                Banner(text: "Your monthly project sweep is ready. Review idle build folders and old worktrees.", info: true) {
                    Button("Review now") { model.openSweep() }.buttonStyle(LinkButton(size: 13))
                }
            }
            hero
            diskBar
            band
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHead("Worth a look", Fmt.plural(findings.count, "finding"))
                    if findings.isEmpty { Empty(text: "Nothing stands out right now.") }
                    ForEach(findings) { f in
                        RuledRow { Text(f.text).font(Typo.body(15, .medium)).frame(maxWidth: .infinity, alignment: .leading); f.action }
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 0) {
                    SectionHead("Right now", model.status?.health_score.map { "health \($0) / 100" } ?? "")
                    if let st = model.status {
                        HStack(alignment: .top, spacing: 24) {
                            vital("\(Int(st.memory?.used_percent ?? 0))%", "Memory used", "\(Fmt.bytes(st.memory?.swap_used)) in swap", neg: (st.memory?.used_percent ?? 0) >= 85)
                            vital("\(Int(st.cpu?.usage ?? 0))%", "CPU", st.networkSummary, ok: true)
                        }
                        .padding(.top, 20)
                    } else {
                        Progress(text: "Reading status…")
                    }
                }
                .frame(width: 380)
            }
        }
    }

    @ViewBuilder var hero: some View {
        HStack(alignment: .bottom, spacing: 32) {
            if let _ = model.scan {
                let all = model.reclaimAll
                BigNumber(value: all >= 10 * Fmt.GB ? "\(Int((all / Fmt.GB).rounded()))" : String(format: "%.1f", all / Fmt.GB))
                VStack(alignment: .leading, spacing: 2) {
                    Text("GB you can get back").font(Typo.display(30, .medium)).tracking(-0.75)
                    Text("\(Fmt.bytes(model.reclaimSafe)) safe now" + (model.reclaimReview > 0 ? ", \(Fmt.bytes(model.reclaimReview)) to review" : ""))
                        .font(Typo.display(30, .medium)).tracking(-0.75).foregroundStyle(Ink.deepSage)
                }
                .padding(.bottom, 2)
                Spacer()
                Button { model.tab = .clean } label: { Label("Review & clean", systemImage: "arrow.right").labelStyle(TrailingIcon()) }
                    .buttonStyle(LinkButton()).padding(.bottom, 6)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.scanProgress == nil ? "Find out what you can get back." : "Scanning your Mac…").font(Typo.display(30, .medium)).tracking(-0.75)
                    Text(model.scanProgress ?? "The first scan takes about a minute. Nothing is deleted.").font(Typo.display(30, .medium)).tracking(-0.75).foregroundStyle(Ink.deepSage)
                }
                Spacer()
                if model.scanProgress == nil {
                    Button { model.scanClean() } label: { Label("Scan my Mac", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButton())
                } else { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder var diskBar: some View {
        if let d = model.status?.disk, let total = d.total, let used = d.used {
            let free = total - used
            let s1 = min(model.reclaimSafe, used), s2 = min(model.reclaimReview, used - s1), rest = used - s1 - s2
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { g in
                    let w = g.size.width - 6
                    HStack(spacing: 2) {
                        Rectangle().fill(Ink.ink).frame(width: max(2, w * rest / total))
                        Rectangle().fill(Ink.deepSage).frame(width: max(2, w * s1 / total))
                        Rectangle().fill(Ink.ruleStrong).frame(width: max(2, w * s2 / total))
                        Rectangle().fill(Ink.sage)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 20) {
                    legend(Ink.ink, "Everything else", Fmt.bytes(rest))
                    legend(Ink.deepSage, "Safe to clean", Fmt.bytes(s1))
                    legend(Ink.ruleStrong, "Review first", Fmt.bytes(s2))
                    legend(Ink.sage, "Free", "\(Fmt.bytes(free)) of \(Fmt.bytes(total))")
                    if let p = d.purgeable, p > 0 { legend(.clear, "Purgeable", Fmt.bytes(p)) }
                }
            }
        }
    }

    func legend(_ c: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(c).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Ink.muted)
            Text(value).font(Typo.body(13, .medium)).monospacedDigit()
        }
        .font(Typo.body(13))
    }

    var band: some View {
        let on = model.routinesOn["weekly-clean"] == true
        let w = model.when["weekly-clean"] ?? Routine.all[0].defaultWhen
        return HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(on ? "Burrow cleans on its own. Next: \(w.nextText)" : "Weekly cleaning is off.").font(Typo.display(28, .medium)).tracking(-0.7)
                Text(on ? "Caches and logs are cleaned through a macOS launch agent, even when Burrow is closed. The Trash is left alone. Anything under Review first waits for you."
                        : "Turn it on and Burrow runs Mole every week through a macOS launch agent, even when the app is closed.")
                    .font(Typo.body(13)).foregroundStyle(Ink.onElectricMuted).frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.tab = .schedule } label: {
                HStack(spacing: 14) {
                    Text(on ? "Edit schedule" : "Set it up").font(Typo.body(14, .medium))
                    Image(systemName: "clock").font(.system(size: 17, weight: .semibold)).foregroundStyle(Ink.electric)
                        .frame(width: 44, height: 44).background(Ink.onElectric, in: Circle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .foregroundStyle(Ink.onElectric)
        .background(Ink.electric)
    }

    func vital(_ big: String, _ label: String, _ small: String, neg: Bool = false, ok: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(big).font(Typo.display(48, .heavy)).tracking(-1.7).foregroundStyle(neg ? Ink.neg : Ink.ink)
            Text(label).font(Typo.body(14, .medium))
            Text(small).font(Typo.body(13)).foregroundStyle(ok ? Ink.deepSage : Ink.muted2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Finding: Identifiable {
        var id: String
        var text: String
        var action: AnyView
    }

    var findings: [Finding] {
        var out: [Finding] = []
        func link(_ title: String, neg: Bool = false, _ act: @escaping () -> Void) -> AnyView {
            AnyView(Button(title, action: act).buttonStyle(LinkButton(negative: neg)))
        }
        if let top = model.processes.first, top.rss > 1.5 * Fmt.GB, top.appPath != nil {
            out.append(Finding(id: "mem", text: "\(top.name) is holding \(Fmt.bytes(top.rss)) of memory · \(Fmt.plural(top.count, "process", "processes"))",
                               action: link("Quit \(top.name)", neg: true) { Task { await model.quit(top) } }))
        }
        if let swap = model.status?.memory?.swap_used, swap > 8 * Fmt.GB {
            out.append(Finding(id: "swap", text: "\(Fmt.bytes(swap)) of memory is swapped to disk · a restart clears it", action: link("Details") { model.tab = .monitor }))
        }
        if let stale = model.dev?.staleWorktrees, !stale.isEmpty {
            out.append(Finding(id: "wt", text: "\(Fmt.plural(stale.count, "worktree")) untouched for 30+ days · \(Fmt.bytes(stale.reduce(0) { $0 + $1.bytes }))", action: link("Review") { model.tab = .developer }))
        }
        if let broken = model.dev?.launchAgents.filter({ !$0.exists && !$0.isBurrows }), !broken.isEmpty {
            out.append(Finding(id: "la", text: "\(Fmt.plural(broken.count, "login item")) \(broken.count == 1 ? "points" : "point") to a program that is gone", action: link("Review") { model.tab = .developer }))
        }
        if let inst = model.old?.filter({ $0.kind == .installer }), !inst.isEmpty {
            out.append(Finding(id: "inst", text: "\(Fmt.plural(inst.count, "installer")) in Downloads, Desktop and Documents · \(Fmt.bytes(inst.reduce(0) { $0 + $1.size }))", action: link("Review") { model.tab = .files }))
        }
        let un = model.unusedApps
        if !un.isEmpty {
            out.append(Finding(id: "apps", text: "\(Fmt.plural(un.count, "app")) not opened in 90+ days · \(Fmt.bytes(un.reduce(0) { $0 + $1.size }))", action: link("Review") { model.tab = .apps }))
        }
        if model.apps == nil && !model.appsBusy { out.append(Finding(id: "a0", text: "Installed apps have not been scanned yet", action: link("Scan") { Task { await model.scanApps() } })) }
        if let u = model.moleUpdate, !model.moleUpdating {
            out.append(Finding(id: "mole", text: "Mole \(u) is available · you have \(model.moleVersion)", action: link("Update Mole") { Task { await model.updateMole() } }))
        }
        if model.dev == nil && !model.devBusy { out.append(Finding(id: "d0", text: "Developer folders have not been scanned yet", action: link("Scan") { Task { await model.scanDev() } })) }
        if model.old == nil && !model.oldBusy { out.append(Finding(id: "o0", text: "Old files have not been scanned yet", action: link("Scan") { Task { await model.scanOld() } })) }
        return Array(out.prefix(6))
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

struct CleanView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        if let scan = model.scan {
            Page {
                PageHead(title: "\(Fmt.bytes(scan.total)) found",
                         lede: "Mole's dry run from \(Fmt.ago(scan.at.timeIntervalSince1970)). Nothing has been deleted. Untick anything you want to keep, or open a folder to keep part of it. System caches that need an admin password are not included.") { EmptyView() }
                VStack(spacing: 0) {
                    Rectangle().fill(Ink.ink).frame(height: 1)
                    ForEach(scan.categories) { c in category(c) }
                }
                Lede(text: "Mole skips anything in use and anything on its whitelist (~/.config/mole/whitelist). Items you untick are added to the whitelist for this run only. The Trash starts unticked: it's your undo for everything Burrow moves there.", size: 13)
            } bar: { bar }
        } else {
            Page {
                PageHead(title: "Clean", lede: "Mole checks caches, logs, browser data, developer caches and leftovers from apps you removed. The scan is a dry run and deletes nothing.") { EmptyView() }
                if let p = model.scanProgress { Progress(text: "Scanning: \(p)") }
                else { Button { model.scanClean() } label: { Label("Scan my Mac", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButton()) }
            }
        }
    }

    func category(_ c: CleanCategory) -> some View {
        let all = c.items.allSatisfy { !model.excluded.contains($0.path) }, none = c.items.allSatisfy { model.excluded.contains($0.path) }
        return VStack(spacing: 0) {
            RuledRow(minHeight: 56) {
                Checkbox(state: all ? .on : none ? .off : .mixed) { model.toggle(category: c) }
                Text(c.name).font(Typo.body(16, .medium)) + Text(" · \(Fmt.plural(c.items.count, "location"))").font(Typo.body(16)).foregroundColor(Ink.muted)
                Spacer()
                SizeText(bytes: c.size, strong: true)
            }
            VStack(spacing: 0) {
                ForEach(c.items) { it in item(it) }
            }
            .padding(.vertical, 4).padding(.bottom, 6)
            .background(Ink.panel.opacity(0.6))
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
    }

    @ViewBuilder func item(_ it: CleanItem) -> some View {
        let on = !model.excluded.contains(it.path)
        let open = model.expanded.contains(it.path)
        let guarded = model.protectedInScan[it.path]
        HStack(spacing: 10) {
            Checkbox(on) { model.toggle(path: it.path) }.disabled(guarded != nil)
            Button { model.expand(it) } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.muted)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 18)
            }
            .buttonStyle(.plain)
            Text(Paths.short(it.path)).font(Typo.mono(12)).foregroundStyle(on ? Ink.ink : Ink.muted).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text([it.count.map { "\($0) items" }, on ? nil : guarded.map { "kept, \($0)" } ?? "kept"].compactMap { $0 }.joined(separator: " · "))
                .font(Typo.body(13)).foregroundStyle(Ink.muted2)
            SizeText(bytes: it.size)
        }
        .padding(.leading, 30).frame(minHeight: 38)
        if open {
            VStack(spacing: 0) {
                if model.loadingChildren.contains(it.path) { Progress(text: "Measuring…") }
                else if (model.children[it.path] ?? []).isEmpty { Text("Nothing large inside.").foregroundStyle(Ink.muted).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(model.children[it.path] ?? []) { k in
                    HStack(spacing: 10) {
                        Checkbox(on && !model.excluded.contains(k.path)) { model.toggle(path: k.path) }.disabled(!on)
                        Text((k.path as NSString).lastPathComponent).font(Typo.mono(12)).lineLimit(1)
                        Spacer()
                        SizeText(bytes: k.size)
                    }
                    .frame(minHeight: 34)
                }
            }
            .padding(.leading, 86)
        }
    }

    @ViewBuilder var bar: some View {
        let sel = model.cleanSelected
        if let b = model.busy {
            ActionBar(title: b, note: "Mole is deleting the selected caches. This can take a few minutes.") {
                Button {} label: { HStack { ProgressView().controlSize(.small); Text("Cleaning…") } }.buttonStyle(PrimaryButton()).disabled(true)
            }
        } else if let p = model.scanProgress {
            ActionBar(title: "Checking what is there now…", note: "Mole is re-checking (\(p)). The Clean button turns on when it finishes, usually in about a minute.") {
                Button("Clean") {}.buttonStyle(PrimaryButton()).disabled(true)
            }
        } else if !model.scanFresh {
            ActionBar(title: "One quick check first", note: "This list is from an earlier session. Burrow re-checks so you approve exactly what is there now, then the Clean button turns on.") {
                Button { model.scanClean() } label: { Label("Check now", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButton())
            }
        } else {
            ActionBar(title: "\(Fmt.bytes(sel)) selected", note: "Clean deletes the ticked items for good (not to the Trash); apps rebuild caches. The Trash is left alone unless you tick it. Every run is logged in History.") {
                Button("Always keep unticked") { Task { await model.keepForever() } }.buttonStyle(LinkButton()).disabled(model.excluded.isEmpty)
                Button("Clean \(Fmt.bytes(sel))") { Task { await model.runClean() } }.buttonStyle(PrimaryButton()).disabled(sel <= 0)
            }
        }
    }
}
