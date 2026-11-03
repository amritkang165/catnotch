import AppKit

// No Dock icon comes from LSUIElement in the Info.plist.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

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
