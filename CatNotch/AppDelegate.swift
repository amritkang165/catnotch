import AppKit
import Carbon.HIToolbox
import CatNotchCore

// No Dock icon comes from LSUIElement in the Info.plist.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    /// Creating it imports the old DeskNotch store on first launch.
    private let store = CatNotchStore.standard()
    private lazy var focus = FocusModel(store: store)
    private lazy var tasks = TaskModel(store: store)
    private lazy var nowPlaying = NowPlayingModel()
    private lazy var agenda = AgendaModel(store: store)
    private lazy var shelf = ShelfModel(store: store)
    private lazy var screenshots = ScreenshotModel()
    private lazy var system = SystemModel()
    private lazy var usage = UsageModel(store: store)
    private lazy var update = UpdateModel()
    private lazy var claude = ClaudeModel(store: store)
    private var settings: SettingsWindow?
    private var shortcuts: [GlobalShortcut] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // weak reference, so keep the delegate alive while the app runs
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(store: store, focus: focus, tasks: tasks, nowPlaying: nowPlaying, agenda: agenda, shelf: shelf, screenshots: screenshots, system: system, usage: usage, claude: claude)
        claude.start()
        let settings = SettingsWindow(store: store, focus: focus, agenda: agenda, usage: usage, claude: claude, update: update)
        self.settings = settings
        shortcuts = [
            GlobalShortcut(id: 1, key: kVK_ANSI_Comma, name: "Cmd+Option+,") { settings.show() },
            GlobalShortcut(id: 2, key: kVK_ANSI_Period, name: "Cmd+Option+.") { [weak self] in self?.notch?.toggleFromKeyboard() },
        ]
        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { _ in MainActor.assumeIsolated { settings.show() } }
    }
}
