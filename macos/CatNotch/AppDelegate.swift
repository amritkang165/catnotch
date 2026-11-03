import AppKit

// No Dock icon comes from LSUIElement in the Info.plist. The notch panel arrives in a later phase.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // weak reference, so keep the delegate alive while the app runs
        withExtendedLifetime(delegate) { app.run() }
    }
}
