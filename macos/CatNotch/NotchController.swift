import AppKit
import CatNotchCore

/// One Notch panel per target display, hidden on a display a fullscreen app fills.
/// Everything is event driven: pointer monitors, screen changes, app and Space switches. No polling timer.
@MainActor
final class NotchController {
    // ponytail: fixed until settings exist; the settings issue sets this from `selectedDisplayId`.
    var selection = DisplaySelection.primary { didSet { sync() } }

    private var panels: [UInt32: NotchPanel] = [:]
    private var foreground: ForegroundState?

    init() {
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

    private static func id(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Makes the panels match the display rule: adds, removes and resizes them.
    private func sync() {
        let screens = NSScreen.screens
        // The primary display is the one with the menu bar, first in the list.
        guard let primary = screens.first.flatMap(Self.id) else { return }
        let targets = Set(selection.targets(available: screens.compactMap(Self.id), primary: primary))

        for (id, panel) in panels where !targets.contains(id) {
            panel.setHidden(true)
            panels[id] = nil
        }
        for id in targets {
            if let panel = panels[id] { panel.reposition() } else { panels[id] = NotchPanel(displayID: id) }
        }
        applyForeground()
    }

    private func refreshForeground() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // CatNotch itself in front (hovered or clicked): leave everything as it was.
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }

        let displays = NSScreen.screens.compactMap { screen in
            Self.id(of: screen).map { DisplayBounds(id: $0, bounds: CGDisplayBounds($0)) }
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
