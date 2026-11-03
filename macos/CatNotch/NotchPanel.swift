import AppKit
import SwiftUI
import CatNotchCore

// Prototype constants. Hardware notch sizing comes in a later issue.
private let hover = NotchHover(closed: CGSize(width: 200, height: 32), open: CGSize(width: 520, height: 200))

@Observable
final class NotchModel {
    var isOpen = false
}

private struct NotchView: View {
    var model: NotchModel

    var body: some View {
        let size = hover.size(isOpen: model.isOpen)
        UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
            .fill(.black)
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(duration: 0.3), value: model.isOpen)
            .ignoresSafeArea() // a hardware notch would otherwise push the drawing below the hit rect
    }
}

/// Hosting view with a tracking area, so the pointer leaving the panel is seen while it takes mouse events.
private final class TrackedHostingView<Content: View>: NSHostingView<Content> {
    var onPointer: () -> Void = {}
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) } // only ours: the hosting view keeps its own for SwiftUI hover
        let new = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(new)
        area = new
    }
    override func mouseMoved(with event: NSEvent) { onPointer() }
    override func mouseEntered(with event: NSEvent) { onPointer() }
    override func mouseExited(with event: NSEvent) { onPointer() }
}

/// A panel AppKit may not nudge below the menu bar: the drawn Notch must sit where the hit rect says.
private final class TopPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One transparent panel at the top centre. It ignores the mouse (clicks fall through) except while open.
/// Pointer input is event driven only: monitors and a tracking area, no timer.
@MainActor
final class NotchPanel {
    private let model = NotchModel()
    private let panel: TopPanel

    init() {
        panel = TopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = TrackedHostingView(rootView: NotchView(model: model))
        view.onPointer = { [weak self] in self?.update() }
        panel.contentView = view

        // Monitors live as long as the app (prototype). Global sees moves over other apps (panel is ignoring), local sees moves over us (panel is taking events).
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in MainActor.assumeIsolated { self?.update() }; return event }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
        reposition()
        panel.orderFrontRegardless()
    }

    private var screenFrame: CGRect { (NSScreen.screens.first ?? NSScreen.main)?.frame ?? .zero }

    private func reposition() {
        panel.setFrame(hover.panelFrame(in: screenFrame), display: true)
        update()
    }

    private func update() {
        let open = hover.isOpen(cursor: NSEvent.mouseLocation, in: screenFrame, wasOpen: model.isOpen)
        guard open != model.isOpen else { return }
        model.isOpen = open
        panel.ignoresMouseEvents = !open
    }
}
