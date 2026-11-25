import AppKit
import SwiftUI

/// The menu bar panel: free disk, memory pressure and swap, the top memory apps,
/// what you can get back, and the next scheduled clean.
public struct MenuBarPanel: View {
    @Bindable var model: BurrowModel
    var open: (Tab?) -> Void

    public init(model: BurrowModel, open: @escaping (Tab?) -> Void) {
        self.model = model
        self.open = open
        Fonts.register()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TunnelMark(size: 20)
                Text("burrow").font(Typo.display(17, .black)).tracking(-0.5)
                Spacer()
                if let h = model.status?.health_score { Text("health \(h)").font(Typo.body(12)).foregroundStyle(Ink.muted) }
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 6) {
                Text(model.scan != nil ? Fmt.bytes(model.reclaimAll) : "–").font(Typo.display(40, .heavy)).tracking(-1.6)
                ChipSquare().scaleEffect(0.55).frame(width: 18, height: 18).padding(.top, 6)
            }
            Text(model.scan != nil ? "you can get back · \(Fmt.bytes(model.reclaimSafe)) safe now" : model.scanProgress.map { "Scanning: " + $0 } ?? "Not scanned yet")
                .font(Typo.body(13)).foregroundStyle(Ink.deepSage).lineLimit(1)
                .padding(.bottom, 14)

            Rectangle().fill(Ink.ink).frame(height: 1)
            if let st = model.status {
                vitals(st).padding(.vertical, 12)
                Rectangle().fill(Ink.rule).frame(height: 1)
            }
            VStack(spacing: 0) {
                ForEach(model.processes.prefix(3)) { p in
                    HStack {
                        Text(p.name).font(Typo.body(13, .medium)).lineLimit(1)
                        Spacer()
                        Text(Fmt.bytes(p.rss)).font(Typo.mono(12)).foregroundStyle(p.rss > 1.5 * Fmt.GB ? Ink.neg : Ink.ink)
                    }
                    .frame(minHeight: 28)
                }
            }
            .padding(.vertical, 6)
            Rectangle().fill(Ink.rule).frame(height: 1)

            let on = model.routinesOn["weekly-clean"] == true
            Text(on ? "Next clean: " + (model.when["weekly-clean"] ?? Routine.all[0].defaultWhen).nextText : "Weekly cleaning is off")
                .font(Typo.body(12)).foregroundStyle(on ? Ink.deepSage : Ink.muted).padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 2) {
                item("Review & clean…") { open(.clean) }
                item("Old files…") { open(.files) }
                item("Memory & network…") { open(.monitor) }
                item(model.scanProgress == nil ? "Scan again" : "Scanning…") { model.scanClean() }.disabled(model.scanProgress != nil)
                item("Flush DNS…") { Task { await model.flushDNS() } }
            }
            Rectangle().fill(Ink.rule).frame(height: 1).padding(.vertical, 8)
            HStack {
                Button("Open Burrow") { open(nil) }.buttonStyle(PrimaryButton())
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(LinkButton(size: 13))
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Ink.paper)
        .foregroundStyle(Ink.ink)
        .task { await model.refreshStatus() }
    }

    func vitals(_ st: MoleStatus) -> some View {
        let pressure = st.memory?.pressure ?? "normal"
        let free = (st.disk?.total ?? 0) - (st.disk?.used ?? 0)
        return HStack(alignment: .top, spacing: 16) {
            vital(Fmt.bytes(free), "free disk")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(pressure == "normal" ? Ink.deepSage : pressure == "warn" ? Ink.warn : Ink.neg).frame(width: 8, height: 8)
                    Text("\(Int(st.memory?.used_percent ?? 0))%").font(Typo.display(20, .heavy))
                }
                Text("memory · \(pressure)").font(Typo.body(11)).foregroundStyle(Ink.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            vital(Fmt.bytes(st.memory?.swap_used), "in swap")
        }
    }

    func vital(_ big: String, _ small: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(Typo.display(20, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            Text(small).font(Typo.body(11)).foregroundStyle(Ink.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func item(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Typo.body(14)).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The menu bar item's label: the mark, and how much you can get back.
public struct MenuBarLabel: View {
    @Bindable var model: BurrowModel
    public init(model: BurrowModel) { self.model = model }
    public var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
            if model.scan != nil { Text("\(Int((model.reclaimAll / Fmt.GB).rounded()))G") }
        }
    }
}

/// Burrow → Settings: updates, Full Disk Access, and where Burrow keeps its files.
public struct SettingsView: View {
    @Bindable var model: BurrowModel
    @Bindable var updates: Updates

    public init(model: BurrowModel, updates: Updates) { self.model = model; self.updates = updates }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Updates").font(Typo.display(18, .semibold))
                if updates.isEnabled {
                    Toggle("Check for updates once a day", isOn: $updates.checksAutomatically)
                    HStack {
                        Text("Burrow \(updates.version)" + (updates.available.map { " · \($0) available" } ?? ""))
                        Spacer()
                        Button("Check now") { updates.check() }.disabled(!updates.canCheck)
                    }
                } else {
                    Text("This build doesn't update itself yet (no update feed). Burrow \(updates.version).").foregroundStyle(Ink.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Disk Access").font(Typo.display(18, .semibold))
                HStack {
                    Text(model.hasDiskAccess ? "On" : "Off").foregroundStyle(model.hasDiskAccess ? Ink.deepSage : Ink.warn)
                    Spacer()
                    Button("Open Privacy settings") { DiskAccess.openSettings() }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Files").font(Typo.display(18, .semibold))
                HStack {
                    Text(Paths.short(Paths.appSupport.path)).font(Typo.mono(12))
                    Spacer()
                    Button("Show in Finder") { model.reveal(Paths.history.path) }
                }
                Text("History, per-path logs of every action, and the scripts the schedules run. Mole's whitelist is ~/.config/mole/whitelist.")
                    .font(Typo.body(12)).foregroundStyle(Ink.muted)
            }
            Text("Cleaning by Mole (github.com/tw93/Mole), GPL-3.0, run as a separate program.").font(Typo.body(12)).foregroundStyle(Ink.muted2)
        }
        .padding(24)
        .frame(width: 460)
    }
}
