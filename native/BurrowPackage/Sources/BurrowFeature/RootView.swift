import SwiftUI

/// The main window: a top bar with the tabs, a quiet sidebar, and the tab's page.
public struct RootView: View {
    @Bindable var model: BurrowModel

    public init(model: BurrowModel) {
        self.model = model
        Fonts.register()
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            Rectangle().fill(Ink.divider).frame(height: 1)
            switch model.phase {
            case .starting:
                Spacer(); Progress(text: "Opening Burrow…"); Spacer()
            case .needsMole:
                NeedsMoleView(model: model)
            case .ready:
                if !model.hasDiskAccess && !model.onboardingDismissed {
                    OnboardingView(model: model)
                } else {
                    HStack(spacing: 0) {
                        Sidebar(model: model)
                        Rectangle().fill(Ink.divider).frame(width: 1)
                        page.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Ink.paper)
        .foregroundStyle(Ink.ink)
        .font(Typo.body())
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t).font(Typo.body(14)).foregroundStyle(Ink.onButton)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Ink.button)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .sheet(item: Binding(get: { model.pendingPlan }, set: { if $0 == nil { model.answer(false) } })) { plan in
            ConfirmSheet(plan: plan, model: model)
        }
        .sheet(item: $model.uninstallSheet) { req in
            UninstallSheet(request: req, model: model)
        }
        .task { if model.phase == .starting { await model.start() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let was = model.hasDiskAccess
            model.hasDiskAccess = DiskAccess.granted
            if !was && model.hasDiskAccess { model.recheckAccess() }
        }
    }

    @ViewBuilder var page: some View {
        switch model.tab {
        case .overview: OverviewView(model: model)
        case .clean: CleanView(model: model)
        case .apps: AppsView(model: model)
        case .tools: ToolsView(model: model)
        case .files: OldFilesView(model: model)
        case .developer: DeveloperView(model: model)
        case .monitor: MonitorView(model: model)
        case .schedule: ScheduleView(model: model)
        }
    }
}

struct TopBar: View {
    @Bindable var model: BurrowModel
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 9) {
                TunnelMark()
                Text("burrow").font(Typo.display(21, .black)).tracking(-0.7)
            }
            .fixedSize()
            Rectangle().fill(Ink.rule).frame(width: 1, height: 18)
            if model.phase == .ready {
                HStack(spacing: 2) {
                        ForEach(Tab.allCases) { t in
                            Button { model.tab = t; if t == .tools && model.tools == nil { Task { await model.scanTools() } } } label: {
                                HStack(spacing: 6) {
                                    Text(t.title).font(Typo.body(14, model.tab == t ? .medium : .regular))
                                    if t == .clean, let s = model.scan { Text("\(Int((s.total / Fmt.GB).rounded())) GB").font(Typo.body(12, .bold)).foregroundStyle(Ink.deepSage) }
                                    if t == .monitor, (model.status?.memory?.used_percent ?? 0) >= 80 { Rectangle().fill(Ink.neg).frame(width: 6, height: 6) }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(model.tab == t ? Ink.ink : Ink.muted)
                                .background(model.tab == t ? Ink.sage : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character("\(Tab.allCases.firstIndex(of: t)! + 1)")), modifiers: .command)
                        }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
            Text(model.statusLine).font(Typo.body(13)).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.tail)
            if model.phase == .ready {
                Button { model.scanClean() } label: {
                    Label(model.scanProgress != nil ? "Scanning…" : model.scan != nil ? "Scan again" : "Scan my Mac", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButton())
                .fixedSize()
                .disabled(model.scanProgress != nil)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.leading, 88).padding(.trailing, 16)
        .frame(height: 60)
    }
}

struct Sidebar: View {
    @Bindable var model: BurrowModel
    var body: some View {
        let h = model.status?.hardware
        VStack(alignment: .leading, spacing: 0) {
            Text(h?.model ?? "This Mac").font(Typo.display(20, .semibold)).tracking(-0.4).padding(.leading, 12).padding(.bottom, 4)
            Text([h?.cpu_model, h?.total_ram, h?.os_version].compactMap { $0 }.joined(separator: " · "))
                .font(Typo.body(12)).foregroundStyle(Ink.muted2).padding(.leading, 12).padding(.bottom, 16)
            if let scan = model.scan, !scan.categories.isEmpty {
                label("Safe to clean")
                ForEach(scan.categories.sorted { $0.size > $1.size }) { c in row(c.name, Fmt.bytes(c.size), .clean) }
            }
            label("Review first")
            row("Unused apps", model.apps.map { "\($0.filter { $0.isUnused() }.count)" } ?? "–", .apps)
            row("Installers & large files", model.old != nil ? Fmt.bytes(model.oldTotal) : "–", .files)
            row("Build folders", model.dev.map { Fmt.bytes($0.idleBuildBytes) } ?? "–", .developer)
            row("Old worktrees", model.dev.map { "\($0.staleWorktrees.count)" } ?? "–", .developer)
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Ink.rule).frame(height: 1)
                HStack(spacing: 8) {
                    Rectangle().fill(model.hasDiskAccess ? Ink.deepSage : Ink.warn).frame(width: 8, height: 8)
                    Text(model.hasDiskAccess ? "Full Disk Access on" : "Full Disk Access off").font(Typo.body(14, .medium))
                }
                if !model.hasDiskAccess {
                    Button("Turn it on") { DiskAccess.openSettings() }.buttonStyle(LinkButton(size: 12))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Burrow \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    HStack(spacing: 4) {
                        Text("Mole \(model.moleVersion)")
                        if model.moleUpdating { Text("· updating…") }
                        else if let u = model.moleUpdate { Text("·"); Button("Update to \(u)") { Task { await model.updateMole() } }.buttonStyle(LinkButton(size: 12)) }
                        else if model.moleLatest != nil { Text("· up to date") }
                    }
                    Text("Uses Mole by tw93, GPL-3.0.")
                }
                .font(Typo.body(12)).foregroundStyle(Ink.muted2)
            }
            .padding(.leading, 12)
        }
        .padding(EdgeInsets(top: 28, leading: 20, bottom: 20, trailing: 16))
        .frame(width: 248, alignment: .leading)
    }

    func label(_ s: String) -> some View {
        Text(s).font(Typo.body(12, .medium)).foregroundStyle(Ink.muted).padding(.leading, 12).padding(.top, 14).padding(.bottom, 8)
    }

    func row(_ title: String, _ value: String, _ tab: Tab) -> some View {
        Button { model.tab = tab } label: {
            HStack {
                Text(title).font(Typo.body(14)).foregroundStyle(Ink.ink2).lineLimit(1)
                Spacer()
                Text(value).font(Typo.body(12)).foregroundStyle(Ink.muted2).monospacedDigit()
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A page: scrolling content with an optional action bar pinned under it.
struct Page<Content: View, Bar: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var bar: Bar
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) { content }
                    .padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            bar
        }
    }
}

extension Page where Bar == EmptyView {
    init(@ViewBuilder content: () -> Content) { self.content = content(); bar = EmptyView() }
}

struct ActionBar<Trailing: View>: View {
    var title: String
    var note: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Ink.divider).frame(height: 1)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.display(22, .semibold)).tracking(-0.4)
                    Text(note).font(Typo.body(13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, 44).padding(.vertical, 14)
            .frame(minHeight: 84)
            .background(Ink.panel)
        }
    }
}

struct ScanButton: View {
    var busy: Bool
    var scanned: Bool
    var first = "Scan"
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(busy ? "Scanning…" : scanned ? "Scan again" : first, systemImage: "arrow.clockwise") }
            .buttonStyle(GhostButton()).disabled(busy)
    }
}

struct AccessBanner: View {
    @Bindable var model: BurrowModel
    var body: some View {
        if !model.hasDiskAccess {
            Banner(text: "Burrow doesn't have Full Disk Access, so macOS may block it from Documents, Desktop and Downloads. Turn it on for Burrow in Privacy & Security, then come back.") {
                Button("Open Privacy settings") { DiskAccess.openSettings() }.buttonStyle(LinkButton(size: 13))
                Button("Check again") { model.recheckAccess(); model.show(model.hasDiskAccess ? "Access looks good. Scanning again." : "Still off. If you just turned it on, quit and reopen Burrow.") }
                    .buttonStyle(LinkButton(size: 13))
            }
        }
    }
}
