import AppKit
import CatNotchCore

/// One Notch panel per target display, hidden on a display a fullscreen app fills.
/// Everything is event driven: pointer monitors, screen changes, app and Space switches. No polling timer.
@MainActor
final class NotchController {
    private var selection: DisplaySelection { didSet { sync() } }

    private let store: CatNotchStore
    private let focus: FocusModel
    private let tasks: TaskModel
    private var panels: [UInt32: NotchPanel] = [:]
    private var foreground: ForegroundState?

    init(store: CatNotchStore, focus: FocusModel, tasks: TaskModel) {
        self.store = store
        self.focus = focus
        self.tasks = tasks
        selection = store.data.displaySelection
        // Settings changes the rule through the store; every Notch follows live. Lives as long as the app.
        _ = store.observe { [weak self] data in MainActor.assumeIsolated { // other settings share the store: only a real change re-syncs
            guard let self else { return }
            if data.displaySelection != self.selection { self.selection = data.displaySelection }
            self.panels.values.forEach { $0.apply(data) } // the look changed in Settings
        } }
        // Monitors live as long as the app. Global sees moves over other apps (panels ignore the mouse), local over ours.
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in MainActor.assumeIsolated { self?.pointerMoved() }; return event }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync(); self?.refreshForeground() }
        }
        // A fullscreen app lives in its own Space, so entering or leaving one switches the Space or the active app.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshForeground()
                    // The window list lags the Space switch animation; look again as it settles (a few one shots, not a poll).
                    for delay in [0.3, 0.7, 1.4] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { self?.refreshForeground() } }
                    }
                }
            }
        }
        sync()
        refreshForeground()
    }

    private func pointerMoved() { panels.values.forEach { $0.update() } }

    
    /// Makes the panels match the display rule: adds, removes and resizes them.
    private func sync() {
        let screens = NSScreen.screens
        // The primary display is the one with the menu bar, first in the list.
        guard let primary = screens.first.flatMap(\.displayID) else { return }
        let targets = Set(selection.targets(available: screens.compactMap(\.displayID), primary: primary))

        for (id, panel) in panels where !targets.contains(id) {
            panel.setHidden(true)
            panels[id] = nil
        }
        for id in targets {
            if let panel = panels[id] { panel.reposition() } else { panels[id] = NotchPanel(displayID: id, data: store.data, focus: focus, tasks: tasks) }
        }
        applyForeground()
    }

    private func refreshForeground() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // CatNotch itself in front (hovered or clicked): leave everything as it was.
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }

        let displays = NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayBounds(id: $0, bounds: CGDisplayBounds($0)) }
        }
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let windows = list.compactMap { w -> WindowInfo? in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: dict) else { return nil }
            return WindowInfo(pid: pid, layer: layer, bounds: rect)
        }
        foreground = ForegroundState.detect(pid: front.processIdentifier, bundle: front.bundleIdentifier ?? "", windows: windows, displays: displays, mainDisplay: CGMainDisplayID())
        applyForeground()
    }

    private func applyForeground() {
        for (id, panel) in panels { panel.setHidden(foreground?.hides(display: id) ?? false) }
    }
}
