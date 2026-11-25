import AppKit
import SwiftUI

struct MonitorView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        if let st = model.status {
            let pct = Int(st.memory?.used_percent ?? 0)
            Page {
                HStack(alignment: .bottom, spacing: 32) {
                    BigNumber(value: "\(pct)%", negative: pct >= 85)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("of \(Fmt.bytes(st.memory?.total)) memory in use").font(Typo.display(30, .medium)).tracking(-0.75)
                        Text("\(Fmt.bytes(st.memory?.swap_used)) swapped to disk" + (st.memory?.pressure.map { " · pressure \($0)" } ?? ""))
                            .font(Typo.display(30, .medium)).tracking(-0.75).foregroundStyle(Ink.deepSage)
                    }
                    .padding(.bottom, 2)
                }
                HStack(alignment: .top, spacing: 56) {
                    processes(st).frame(maxWidth: .infinity)
                    network(st).frame(width: 380)
                }
                system(st)
            }
            .task { await model.refreshStatus() }
        } else {
            Page { Progress(text: "Reading status…") }
        }
    }

    func processes(_ st: MoleStatus) -> some View {
        let max = model.processes.first?.rss ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            SectionHead("Using the most memory", st.procs.map { "\($0) processes" } ?? "")
            if model.processes.isEmpty { Progress(text: "Reading processes…") }
            ForEach(Array(model.processes.enumerated()), id: \.1.id) { i, p in
                RuledRow {
                    (Text(p.name).font(Typo.body(15, .medium)) + Text(" · \(p.count)").foregroundColor(Ink.muted)).lineLimit(1).frame(width: 210, alignment: .leading)
                    Meter(fraction: p.rss / max, color: i == 0 && p.rss > 1.5 * Fmt.GB ? Ink.neg : p.appPath != nil ? Ink.ink : Ink.ruleStrong)
                    SizeText(bytes: p.rss)
                    Group { if p.appPath != nil { Button("Quit") { Task { await model.quit(p) } }.buttonStyle(LinkButton(negative: true)) } else { Color.clear } }
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    func network(_ st: MoleStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Network") { Text(st.networkSummary).foregroundStyle(Ink.deepSage) }
            ForEach((st.network ?? []).filter { ($0.ip ?? "").isEmpty == false || ($0.rx_rate_mbs ?? 0) > 0 }, id: \.name) { n in
                RuledRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.ifaceName(n.name)).font(Typo.body(15, .medium))
                        Text(n.name + (n.ip.map { " · " + $0 } ?? "")).font(Typo.mono(12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Text("↓\(Self.rate(n.rx_rate_mbs)) ↑\(Self.rate(n.tx_rate_mbs))").font(Typo.mono(12)).monospacedDigit()
                }
            }
            if st.proxy?.enabled == true {
                RuledRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.proxy?.type == "TUN" ? "VPN tunnel" : "Proxy").font(Typo.body(15, .medium))
                        Text("\(st.proxy?.host ?? "") · \(st.proxy?.type ?? "")").font(Typo.mono(12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Text(st.proxy?.type == "TUN" ? "Routes all traffic" : "On").font(Typo.body(13, .medium)).foregroundStyle(Ink.warn)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Network check" + (model.net.map { " · " + $0.at.formatted(date: .omitted, time: .shortened) } ?? "")).font(Typo.body(14, .medium))
                    Spacer()
                    Button(model.netBusy ? "Checking…" : model.net != nil ? "Run again" : "Run check") { Task { await model.netCheck() } }
                        .buttonStyle(LinkButton()).disabled(model.netBusy)
                }
                if let n = model.net {
                    HStack(spacing: 24) { trio(n.router, "Router"); trio(n.dns, "DNS lookup"); trio(n.internet, "Internet (1.1.1.1)") }
                } else {
                    Text("Pings your router and 1.1.1.1 and times a DNS lookup.").font(Typo.body(13)).foregroundStyle(Ink.muted)
                }
                HStack(spacing: 4) {
                    Text("Slow lookups?").foregroundStyle(Ink.muted)
                    Button("Flush DNS cache") { Task { await model.flushDNS() } }.buttonStyle(LinkButton(size: 13))
                    Text("(asks for your password)").foregroundStyle(Ink.muted)
                }
                .font(Typo.body(13))
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(Ink.sage)
            .padding(.top, 20)
        }
    }

    func trio(_ v: Int?, _ label: String) -> some View {
        VStack(alignment: .leading) {
            (Text(v.map(String.init) ?? "–").font(Typo.display(28, .heavy)) + Text(" ms").font(Typo.display(14, .medium)))
            Text(label).font(Typo.body(12)).foregroundStyle(Ink.muted)
        }
    }

    func system(_ st: MoleStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("System", "health \(st.health_score ?? 0) · \(st.health_score_msg ?? "")")
            RuledRow {
                (Text("CPU").font(Typo.body(15, .medium)) + Text(" · \(st.hardware?.cpu_model ?? ""), load \(String(format: "%.1f", st.cpu?.load1 ?? 0))").foregroundColor(Ink.muted)).frame(width: 360, alignment: .leading)
                Meter(fraction: (st.cpu?.usage ?? 0) / 100, color: Ink.deepSage)
                Text("\(Int(st.cpu?.usage ?? 0))%").font(Typo.mono(13)).frame(width: 84, alignment: .trailing)
            }
            if let d = st.disk {
                RuledRow {
                    (Text("Disk").font(Typo.body(15, .medium)) + Text(" · \(Fmt.bytes((d.total ?? 0) - (d.used ?? 0))) free").foregroundColor(Ink.muted)).frame(width: 360, alignment: .leading)
                    Meter(fraction: (d.used_percent ?? 0) / 100)
                    Text("\(Int(d.used_percent ?? 0))%").font(Typo.mono(13)).frame(width: 84, alignment: .trailing)
                }
            }
            if let b = st.batteries?.first {
                RuledRow {
                    (Text("Battery").font(Typo.body(15, .medium)) + Text(" · \(b.status ?? ""), health \(b.health ?? ""), \(b.cycle_count ?? 0) cycles").foregroundColor(Ink.muted)).frame(width: 360, alignment: .leading)
                    Meter(fraction: (b.percent ?? 0) / 100, color: Ink.deepSage)
                    Text("\(Int(b.percent ?? 0))%").font(Typo.mono(13)).frame(width: 84, alignment: .trailing)
                }
            }
            RuledRow { Text("Up for").font(Typo.body(15, .medium)) + Text(" · \(st.uptime ?? "")").foregroundColor(Ink.muted); Spacer() }
        }
    }

    static func ifaceName(_ n: String) -> String {
        n == "en0" ? "Wi‑Fi" : n.hasPrefix("en") ? "Ethernet" : n.hasPrefix("utun") ? "VPN" : n.hasPrefix("bridge") ? "Bridge" : n
    }

    static func rate(_ mbs: Double?) -> String {
        let k = (mbs ?? 0) * 1024
        return k >= 1024 ? String(format: "%.1f MB/s", k / 1024) : String(format: "%.1f KB/s", k)
    }
}

struct ScheduleView: View {
    @Bindable var model: BurrowModel

    var body: some View {
        Page {
            PageHead(title: "Schedule", lede: "Routines run as macOS launch agents, so they work while Burrow is closed and catch up after the Mac wakes. Only the weekly clean deletes anything, and it only touches what Mole calls safe.") { EmptyView() }
            VStack(spacing: 0) {
                Rectangle().fill(Ink.ink).frame(height: 1)
                ForEach(Routine.all) { r in routine(r) }
            }
            VStack(alignment: .leading, spacing: 0) {
                let total = model.history.reduce(0) { $0 + $1.freed }
                SectionHead("History", total > 0 ? "\(Fmt.bytes(total)) freed so far" : "")
                if model.history.isEmpty { Empty(text: "Nothing yet. Cleans, alerts and checks show up here.") }
                ForEach(model.history.prefix(40)) { h in
                    RuledRow {
                        Text(Date(timeIntervalSince1970: h.t).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(Typo.body(14)).foregroundStyle(Ink.muted2).frame(width: 150, alignment: .leading)
                        (Text(h.label).font(Typo.body(15, .medium)) + Text(" · \(h.how)\(h.note.map { ", " + $0 } ?? "")\(h.code.map { ", exit \($0)" } ?? "")").foregroundColor(Ink.muted))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let log = h.log {
                            Button("Paths") { model.reveal(Paths.logs.appendingPathComponent(log).path) }.buttonStyle(LinkButton(size: 13))
                        }
                        Text(h.freed > 0 ? Fmt.bytes(h.freed) : "").font(Typo.mono(13)).frame(width: 84, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear { model.history = History.load() }
    }

    func routine(_ r: Routine) -> some View {
        let on = model.routinesOn[r.id] == true
        let w = model.when[r.id] ?? r.defaultWhen
        return RuledRow(minHeight: 80) {
            VStack(alignment: .leading, spacing: 3) {
                Text(r.name).font(Typo.body(16, .medium))
                Text(r.detail).font(Typo.body(13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if on && w.kind != .interval { Text("Next: " + w.nextText).font(Typo.body(13)).foregroundStyle(Ink.deepSage) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { whenControls(r, w) }.frame(width: 260, alignment: .leading)
            Text(on ? r.modeLabel : "Off").font(Typo.body(13, .medium))
                .foregroundStyle(!on ? Ink.muted : r.mode == .auto ? Ink.deepSage : r.mode == .asks ? Ink.warn : Ink.muted)
                .frame(width: 120, alignment: .leading)
            Toggle("", isOn: Binding(get: { on }, set: { _ in Task { await model.toggle(r) } }))
                .toggleStyle(.switch).labelsHidden().tint(Ink.ink).disabled(model.busy != nil)
                .accessibilityLabel(r.name)
        }
    }

    @ViewBuilder func whenControls(_ r: Routine, _ w: When) -> some View {
        let time = Binding<Date>(
            get: { Calendar.current.date(bySettingHour: w.hour, minute: w.minute, second: 0, of: Date()) ?? Date() },
            set: { d in var n = w; n.hour = Calendar.current.component(.hour, from: d); n.minute = Calendar.current.component(.minute, from: d); Task { await model.setWhen(r, n) } })
        switch w.kind {
        case .weekly:
            Picker("", selection: Binding(get: { w.weekday }, set: { v in var n = w; n.weekday = v; Task { await model.setWhen(r, n) } })) {
                ForEach(0..<7, id: \.self) { Text(When.weekdays[$0]).tag($0) }
            }
            .labelsHidden().frame(width: 120)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
        case .monthly:
            Picker("", selection: Binding(get: { w.day }, set: { v in var n = w; n.day = v; Task { await model.setWhen(r, n) } })) {
                ForEach(1...28, id: \.self) { Text("Day \($0)").tag($0) }
            }
            .labelsHidden().frame(width: 100)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
        case .daily:
            Text("Daily at").font(Typo.body(14))
            DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
        case .interval:
            Text("Every 15 minutes").font(Typo.body(14, .medium))
        }
    }
}

// MARK: - Sheets

/// The preview every destructive action shows first.
struct ConfirmSheet: View {
    var plan: Plan
    var model: BurrowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(plan.title).font(Typo.display(22, .semibold)).tracking(-0.4)
            if !plan.body.isEmpty { Text(plan.body).font(Typo.body(14)).lineSpacing(5).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            if !plan.paths.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.paths, id: \.path) { p in
                            HStack {
                                Text(Paths.short(p.path)).font(Typo.mono(12)).foregroundStyle(Ink.ink2).lineLimit(2).truncationMode(.middle)
                                Spacer()
                                if p.size > 0 { Text(Fmt.bytes(p.size)).font(Typo.mono(12)).foregroundStyle(Ink.muted) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
            if !plan.commands.isEmpty && plan.kind != "clean" && plan.kind != "tool-uninstall" {
                Text(plan.commands.joined(separator: "\n")).font(Typo.mono(11)).foregroundStyle(Ink.muted).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { model.answer(false) }.buttonStyle(GhostButton()).keyboardShortcut(.cancelAction)
                Button(plan.confirm) { model.answer(true) }.buttonStyle(PrimaryButton(danger: plan.destructive)).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 520)
        .background(Ink.paper)
        .foregroundStyle(Ink.ink)
    }
}

/// The leftover checklist, AppZapper-style: everything an app left, grouped, untickable.
struct UninstallSheet: View {
    @State var request: UninstallRequest
    var model: BurrowModel

    init(request: UninstallRequest, model: BurrowModel) {
        _request = State(initialValue: request)
        self.model = model
    }

    var body: some View {
        let sel = request.items.filter(\.on)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: request.app.path)).resizable().frame(width: 40, height: 40)
                Text("Uninstall \(request.app.name)?").font(Typo.display(22, .semibold)).tracking(-0.4)
            }
            Text("Everything ticked moves to the Trash, so you can put it back. Untick anything you want to keep.")
                .font(Typo.body(14)).foregroundStyle(Ink.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    group(.app, "The app")
                    group(.data, "Settings, data, caches and login items")
                    group(.shared, "Shared with other apps from the same developer · kept unless you tick it")
                    if let token = request.cask {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Homebrew's record").font(Typo.body(12, .medium)).foregroundStyle(Ink.muted)
                            HStack(spacing: 10) {
                                Checkbox(request.forgetCask) { request.forgetCask.toggle() }
                                Text("brew uninstall --cask --force \(token)").font(Typo.mono(12))
                                Spacer()
                            }
                            Text("Runs after the app is in the Trash, so brew upgrade doesn't bring it back. Removes only Homebrew's record of the app.")
                                .font(Typo.body(12)).foregroundStyle(Ink.muted2)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { model.uninstallSheet = nil }.buttonStyle(GhostButton()).keyboardShortcut(.cancelAction)
                let total = sel.reduce(0) { $0 + $1.size }
                Button("Move \(Fmt.plural(sel.count, "item"))\(total > 0 ? " · " + Fmt.bytes(total) : "") to Trash") {
                    let r = request
                    Task { await model.finishUninstall(r) }
                }
                .buttonStyle(PrimaryButton(danger: true)).disabled(sel.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Ink.paper)
        .foregroundStyle(Ink.ink)
    }

    @ViewBuilder func group(_ g: LeftoverGroup, _ label: String) -> some View {
        let idx = request.items.indices.filter { request.items[$0].group == g }
        if !idx.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(Typo.body(12, .medium)).foregroundStyle(Ink.muted)
                ForEach(idx, id: \.self) { i in
                    HStack(spacing: 10) {
                        Checkbox(request.items[i].on) { request.items[i].on.toggle() }
                        Text(Paths.short(request.items[i].path)).font(Typo.mono(12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if request.items[i].size > 0 { Text(Fmt.bytes(request.items[i].size)).font(Typo.mono(12)).foregroundStyle(Ink.muted) }
                    }
                    .frame(minHeight: 28)
                }
            }
        }
    }
}

// MARK: - First launch

struct OnboardingView: View {
    @Bindable var model: BurrowModel
    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("Let Burrow look around").font(Typo.display(52, .heavy)).tracking(-2)
                Text("Burrow runs Mole and a few macOS tools to measure caches, find old files and clean what you approve. To see Documents, Desktop, Downloads and other apps' data, macOS needs you to turn on Full Disk Access for Burrow. It's asked once: updates keep it.")
                    .font(Typo.body(15)).lineSpacing(8).foregroundStyle(Ink.muted)
                Text("Nothing is deleted without you seeing the list first. Files go to the Trash; only caches are deleted. Burrow never touches iCloud folders, Photos, Mail, Messages, Keychains, ~/.ssh or .env files.")
                    .font(Typo.body(15)).lineSpacing(8).foregroundStyle(Ink.muted)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open Privacy & Security → Full Disk Access.")
                    Text("2. Turn on Burrow (or press + and choose Burrow in Applications).")
                    Text("3. Come back here. Burrow notices on its own.")
                }
                .font(Typo.body(14, .medium))
                HStack(spacing: 16) {
                    Button("Open Privacy settings") { DiskAccess.openSettings() }.buttonStyle(PrimaryButton())
                    Button("Check again") { model.recheckAccess() }.buttonStyle(GhostButton())
                    Button("Continue without it") { model.dismissOnboarding() }.buttonStyle(LinkButton())
                }
                Text("Without it Burrow still cleans caches, lists apps and tools and watches memory; old files and developer folders may be blocked.")
                    .font(Typo.body(13)).foregroundStyle(Ink.muted2)
                Text("If macOS asks whether Burrow may access files managed by Google Drive, Dropbox or iCloud, choose Don't Allow. Mole's scan looks there for build caches, and Burrow never cleans cloud folders.")
                    .font(Typo.body(13)).foregroundStyle(Ink.muted2)
            }
            .frame(maxWidth: 600)
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .padding(40)
    }
}

struct NeedsMoleView: View {
    @Bindable var model: BurrowModel
    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("Mole isn't installed").font(Typo.display(52, .heavy)).tracking(-2)
                Text("Burrow runs on mo, the open-source Mole cleaner by tw93 (GPL-3.0). Install it with Homebrew, then Burrow starts.")
                    .font(Typo.body(15)).lineSpacing(8).foregroundStyle(Ink.muted)
                Text("brew install mole").font(Typo.mono(13)).padding(.horizontal, 6).padding(.vertical, 2).background(Ink.sage)
                HStack(spacing: 16) {
                    Button("Install Mole with Homebrew") { Task { await model.installMole() } }.buttonStyle(PrimaryButton())
                    Button("Check again") { Task { await model.start() } }.buttonStyle(GhostButton())
                }
                if !model.moleInstallLog.isEmpty { Text(model.moleInstallLog).font(Typo.mono(12)).foregroundStyle(Ink.muted) }
            }
            .frame(maxWidth: 600)
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .padding(40)
    }
}
