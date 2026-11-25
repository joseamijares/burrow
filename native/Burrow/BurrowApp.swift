import AppKit
import BurrowFeature
import SwiftUI
import UserNotifications

/// Burrow for Mac: a Mac cleaner and health monitor on top of Mole (`mo`).
/// The window has the eight tabs; the menu bar panel keeps running when the
/// window is closed. It updates itself with Sparkle (Updates in BurrowFeature).
@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Burrow", id: "main") {
            RootView(model: delegate.model)
                .frame(minWidth: 1060, minHeight: 640)
                .background(WindowOpener(model: delegate.model))
        }
        .defaultSize(width: 1280, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updates: delegate.updates)
            }
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarPanel(model: delegate.model) { tab in
                if let tab { delegate.model.tab = tab }
                delegate.model.openWindow?()
            }
            .background(WindowOpener(model: delegate.model))
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model, updates: delegate.updates)
        }
    }
}

/// Hands the model a way to bring the main window forward (for confirmations
/// started from the menu bar, and the panel's Open buttons).
struct WindowOpener: View {
    var model: BurrowModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.onAppear {
            model.openWindow = {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = BurrowModel()
    let updates = Updates()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { model.openWindow?() }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
