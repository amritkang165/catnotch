import AppKit
import ServiceManagement
import SwiftUI
import CatNotchCore

/// The one Settings window. Later features add their own controls to `SettingsView`.
@MainActor
final class SettingsWindow {
    private let window: NSWindow

    init(store: CatNotchStore) {
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
        window.title = "CatNotch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false // closing hides it; the shortcut shows the same window again
        window.center()
    }

    /// Opens it, or brings the open one to the front.
    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate() // the app has no Dock icon, so it is never active by itself
    }
}

private struct SettingsView: View {
    let store: CatNotchStore
    @State private var selection: DisplaySelection
    @State private var style: NotchStyle
    @State private var flavor: Flavor
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var screens = NSScreen.screens

    init(store: CatNotchStore) {
        self.store = store
        _selection = State(initialValue: store.data.displaySelection)
        _style = State(initialValue: store.data.notchStyle)
        _flavor = State(initialValue: store.data.notchFlavor)
    }

    var body: some View {
        Form {
            Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setLogin))
            Picker("Show the Notch on", selection: Binding(get: { shown }, set: { choice in selection = choice; store.update { $0.displaySelection = choice } })) {
                Text("Primary display").tag(DisplaySelection.primary)
                Text("All displays").tag(DisplaySelection.all)
                ForEach(screens, id: \.self) { screen in
                    if let id = screen.displayID { Text(screen.localizedName).tag(DisplaySelection.chosen(id)) }
                }
            }
            Picker("Style", selection: Binding(get: { style }, set: { choice in style = choice; store.update { $0.notchStyle = choice } })) {
                ForEach(NotchStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Flavour", selection: Binding(get: { flavor }, set: { choice in flavor = choice; store.update { $0.notchFlavor = choice } })) {
                ForEach(Flavor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Button("Quit CatNotch") { NSApp.terminate(nil) }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
        // Displays may come and go while the window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            opensAtLogin = SMAppService.mainApp.status == .enabled // changed in System Settings meanwhile
        }
    }

    /// An unplugged chosen display shows as the primary, which is what the Notch does with it.
    private var shown: DisplaySelection {
        if case .chosen(let id) = selection, !screens.contains(where: { $0.displayID == id }) { return .primary }
        return selection
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            print("[login] could not turn open at login \(on ? "on" : "off"):", error)
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
