import AppKit
import CatNotchCore

// No Dock icon comes from LSUIElement in the Info.plist.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    /// Creating it imports the old DeskNotch store on first launch. Not handed to the Notch yet: no view reads it.
    private let store = CatNotchStore.standard()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // weak reference, so keep the delegate alive while the app runs
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController()
    }
}
